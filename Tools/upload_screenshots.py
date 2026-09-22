#!/usr/bin/env python3
"""撮ったスクリーンショットを App Store Connect の対象バージョンに反映する。

`Tools/extract_screenshots.py` が並べた `<出力先>/<言語>/01_*.png …` を読み、
App Store Connect API で言語ごとにアップロードする。

    python3 Tools/upload_screenshots.py \\
        --screenshots-dir build/screenshots \\
        --bundle-id jp.shilokuma.Otanecho \\
        --display-type APP_IPHONE_65

認証は App Store Connect API Key（.p8）。次の環境変数でも渡せる。

    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_PRIVATE_KEY_PATH

触るのは **編集できる状態のバージョンだけ**。審査中や配信済みのバージョンは対象にしない。
言語ごとに、その表示サイズの既存のスクリーンショットセットを削除してから入れ直す。
（App Store Connect は 1 つの言語・表示サイズにつきセットを 1 つしか持てないため、
 差し替えは「消してから入れる」しかない。編集中のバージョンなので公開中の画面には影響しない。）

PyJWT が要る: `python3 -m pip install pyjwt cryptography`
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:  # pragma: no cover - 実行環境の問題なので案内だけ出す
    raise SystemExit(
        "PyJWT が入っていません。`python3 -m pip install pyjwt cryptography` を実行してください。"
    )

API = "https://api.appstoreconnect.apple.com"

#: スクリーンショットを差し替えられるバージョンの状態。
#: 審査中（WAITING_FOR_REVIEW / IN_REVIEW）や配信済み（READY_FOR_SALE）は触らない。
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}

#: 1 つの言語・表示サイズに載せられる枚数の上限（App Store Connect の制限）
MAX_SCREENSHOTS = 10

#: アップロード後、Apple 側の取り込みが終わるのを待つ上限（秒）
DELIVERY_TIMEOUT = 300


class ApiError(RuntimeError):
    pass


class AppStoreConnect:
    def __init__(self, token: str, dry_run: bool = False):
        self.token = token
        self.dry_run = dry_run

    # MARK: 低レベル

    def _request(self, method: str, url: str, payload: dict | None = None) -> dict:
        body = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise ApiError(f"{method} {url} が {error.code} で失敗しました\n{detail}") from None
        return json.loads(raw) if raw else {}

    def get(self, path: str, params: dict | None = None) -> dict:
        url = f"{API}{path}"
        if params:
            query = urllib.parse.urlencode(params)
            url = f"{url}?{query}"
        return self._request("GET", url)

    def get_all(self, path: str, params: dict | None = None) -> list[dict]:
        """ページングをたどって全件返す。"""
        params = dict(params or {})
        params.setdefault("limit", 200)
        result: list[dict] = []
        url = f"{API}{path}?{urllib.parse.urlencode(params)}"
        while url:
            page = self._request("GET", url)
            result.extend(page.get("data", []))
            url = page.get("links", {}).get("next")
        return result

    def post(self, path: str, payload: dict) -> dict:
        return self._request("POST", f"{API}{path}", payload)

    def patch(self, path: str, payload: dict) -> dict:
        return self._request("PATCH", f"{API}{path}", payload)

    def delete(self, path: str) -> None:
        self._request("DELETE", f"{API}{path}")

    # MARK: アプリとバージョン

    def find_app(self, bundle_id: str) -> dict:
        apps = self.get_all("/v1/apps", {"filter[bundleId]": bundle_id})
        if not apps:
            raise SystemExit(f"bundleId が {bundle_id} のアプリが見つかりません")
        return apps[0]

    def find_version(self, app_id: str, version_string: str | None) -> dict:
        versions = self.get_all(
            f"/v1/apps/{app_id}/appStoreVersions",
            {"filter[platform]": "IOS", "limit": 50},
        )
        editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE_STATES]

        if version_string:
            for version in versions:
                if version["attributes"]["versionString"] == version_string:
                    state = version["attributes"]["appStoreState"]
                    if state not in EDITABLE_STATES:
                        raise SystemExit(
                            f"バージョン {version_string} は {state} のため編集できません"
                        )
                    return version
            raise SystemExit(f"バージョン {version_string} が見つかりません")

        if not editable:
            states = ", ".join(sorted({v["attributes"]["appStoreState"] for v in versions}))
            raise SystemExit(
                "編集できる状態のバージョンがありません"
                f"（いまある状態: {states or 'なし'}）。"
                "App Store Connect で次のバージョンを作ってから実行してください。"
            )
        if len(editable) > 1:
            names = ", ".join(v["attributes"]["versionString"] for v in editable)
            raise SystemExit(
                f"編集できるバージョンが複数あります（{names}）。--app-version で選んでください。"
            )
        return editable[0]

    def localizations(self, version_id: str) -> dict[str, str]:
        entries = self.get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
        return {entry["attributes"]["locale"]: entry["id"] for entry in entries}

    # MARK: スクリーンショット

    def existing_set(self, localization_id: str, display_type: str) -> str | None:
        sets = self.get_all(
            f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets",
            {"filter[screenshotDisplayType]": display_type},
        )
        return sets[0]["id"] if sets else None

    def create_set(self, localization_id: str, display_type: str) -> str:
        if self.dry_run:
            return "dry-run"
        response = self.post(
            "/v1/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                        }
                    },
                }
            },
        )
        return response["data"]["id"]

    def upload(self, set_id: str, path: Path) -> str:
        """1 枚ぶんの予約 → 本体の転送 → 確定、までをやる。"""
        data = path.read_bytes()
        if self.dry_run:
            return "dry-run"

        reserved = self.post(
            "/v1/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileSize": len(data), "fileName": path.name},
                    "relationships": {
                        "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                    },
                }
            },
        )
        screenshot_id = reserved["data"]["id"]

        # 本体は Apple が指定する URL へ、指示どおりに分割して送る
        for operation in reserved["data"]["attributes"]["uploadOperations"]:
            offset = operation["offset"]
            chunk = data[offset:offset + operation["length"]]
            request = urllib.request.Request(operation["url"], data=chunk, method=operation["method"])
            for header in operation.get("requestHeaders", []):
                request.add_header(header["name"], header["value"])
            try:
                with urllib.request.urlopen(request):
                    pass
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")
                raise ApiError(f"{path.name} の転送が {error.code} で失敗しました\n{detail}") from None

        self.patch(
            f"/v1/appScreenshots/{screenshot_id}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": screenshot_id,
                    "attributes": {
                        "uploaded": True,
                        "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                    },
                }
            },
        )
        return screenshot_id

    def reorder(self, set_id: str, screenshot_ids: list[str]) -> None:
        """App Store に並ぶ順を、ファイル名の順（01_… 02_…）に揃える。"""
        if self.dry_run:
            return
        self.patch(
            f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
            {"data": [{"type": "appScreenshots", "id": i} for i in screenshot_ids]},
        )

    def wait_for_delivery(self, screenshot_ids: list[str]) -> None:
        """Apple 側の取り込みが終わるまで待つ。失敗していればここで気づける。"""
        if self.dry_run:
            return
        deadline = time.time() + DELIVERY_TIMEOUT
        pending = list(screenshot_ids)
        while pending and time.time() < deadline:
            still_pending = []
            for screenshot_id in pending:
                attributes = self.get(f"/v1/appScreenshots/{screenshot_id}")["data"]["attributes"]
                state = attributes.get("assetDeliveryState") or {}
                if state.get("errors"):
                    raise SystemExit(
                        f"{attributes.get('fileName')} の取り込みに失敗しました: {state['errors']}"
                    )
                if state.get("state") != "COMPLETE":
                    still_pending.append(screenshot_id)
            pending = still_pending
            if pending:
                time.sleep(5)
        if pending:
            raise SystemExit(
                f"{len(pending)} 枚の取り込みが {DELIVERY_TIMEOUT} 秒で終わりませんでした。"
                "App Store Connect の画面で状態を確認してください。"
            )


def make_token(key_id: str, issuer_id: str, private_key: str) -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def screenshots_for(directory: Path) -> list[Path]:
    """ファイル名の順に並べる。この順がそのまま App Store の並び順になる。"""
    return sorted(p for p in directory.glob("*.png"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--screenshots-dir", type=Path, required=True, help="<ここ>/<言語>/*.png を読む")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--display-type", default="APP_IPHONE_65", help="App Store Connect の表示サイズ")
    parser.add_argument("--languages", help="対象の言語（カンマ区切り）。省略すると全言語")
    parser.add_argument("--app-version", help="反映先のバージョン。省略すると編集できるバージョンを自動で選ぶ")
    parser.add_argument("--key-id", default=os.environ.get("APP_STORE_CONNECT_KEY_ID"))
    parser.add_argument("--issuer-id", default=os.environ.get("APP_STORE_CONNECT_ISSUER_ID"))
    parser.add_argument(
        "--private-key",
        type=Path,
        default=os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH"),
        help="App Store Connect API Key の .p8",
    )
    parser.add_argument(
        "--skip-missing-locales",
        action="store_true",
        help="App Store Connect にその言語が無ければ飛ばす（既定は止める）",
    )
    parser.add_argument("--dry-run", action="store_true", help="何も書き換えず、やることだけ出す")
    args = parser.parse_args()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from supported_languages import app_store_languages, parse_language_list

    targets = app_store_languages(parse_language_list(args.languages))

    missing_key = [
        name for name, value in
        [("--key-id", args.key_id), ("--issuer-id", args.issuer_id), ("--private-key", args.private_key)]
        if not value
    ]
    if missing_key:
        raise SystemExit(f"認証情報が足りません: {', '.join(missing_key)}")

    token = make_token(args.key_id, args.issuer_id, Path(args.private_key).read_text())
    client = AppStoreConnect(token, dry_run=args.dry_run)

    app = client.find_app(args.bundle_id)
    version = client.find_version(app["id"], args.app_version)
    version_string = version["attributes"]["versionString"]
    print(f"対象: {app['attributes']['name']} {version_string} "
          f"({version['attributes']['appStoreState']}) / {args.display_type}")
    if args.dry_run:
        print("--dry-run: App Store Connect には何も書き込みません")

    available = client.localizations(version["id"])

    # 書き込みを始める前に、全言語ぶんの前提をまとめて確かめる。
    # 途中で止めると一部の言語だけ差し替わった状態になるうえ、
    # 撮り直しに小一時間かかるので「直すべき点」は 1 回で出し切る。
    plan = []
    skipped: list[str] = []
    missing_locales: list[str] = []
    problems: list[str] = []
    for target in targets:
        directory = args.screenshots_dir / target.language
        images = screenshots_for(directory) if directory.is_dir() else []
        if not images:
            problems.append(f"{directory} にスクリーンショットがありません")
            continue
        if len(images) > MAX_SCREENSHOTS:
            problems.append(
                f"{directory} に {len(images)} 枚あります。"
                f"App Store Connect は 1 つの表示サイズにつき {MAX_SCREENSHOTS} 枚までです。"
            )
            continue

        localization_id = available.get(target.store_locale)
        if localization_id is None:
            if args.skip_missing_locales:
                print(f"  飛ばす — {target.language}: {target.store_locale} が {version_string} にありません")
                skipped.append(target.language)
            else:
                missing_locales.append(f"{target.language} → {target.store_locale}")
            continue

        plan.append((target, images, localization_id))

    if missing_locales:
        problems.append(
            f"App Store Connect の {version_string} に無い言語: {', '.join(missing_locales)}\n"
            "App Store Connect でこれらの言語を追加してから実行するか、"
            "--skip-missing-locales を付けてください。"
        )
    if problems:
        raise SystemExit("\n".join(problems))

    uploaded_total = 0
    for target, images, localization_id in plan:
        existing = client.existing_set(localization_id, args.display_type)
        if existing and not args.dry_run:
            client.delete(f"/v1/appScreenshotSets/{existing}")
        set_id = client.create_set(localization_id, args.display_type)

        screenshot_ids = [client.upload(set_id, image) for image in images]
        client.reorder(set_id, screenshot_ids)
        client.wait_for_delivery(screenshot_ids)
        uploaded_total += len(images)
        print(f"  {target.language} → {target.store_locale}: {len(images)} 枚")

    print(f"完了: {len(plan)} 言語 / {uploaded_total} 枚")
    if skipped:
        print(f"飛ばした言語: {', '.join(skipped)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
