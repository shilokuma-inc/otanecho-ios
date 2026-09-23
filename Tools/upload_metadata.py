#!/usr/bin/env python3
"""App Store の説明文・キーワード・サポート URL を App Store Connect に反映する。

`Localization/app-store-metadata/<言語>.json` を読み、対象バージョンの言語ごとに書き込む。

    python3 Tools/upload_metadata.py --bundle-id jp.shilokuma.Otanecho

認証は App Store Connect API Key（.p8）。次の環境変数でも渡せる。

    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_PRIVATE_KEY_PATH

触るのは **編集できる状態のバージョンだけ**。審査中や配信済みのバージョンは対象にしない。

`--check` なら App Store Connect には一切つながず、手元のファイルの欠損と文字数超過だけ見る。
CI（Verify/localizations）はこちらを使う。

PyJWT が要る: `python3 -m pip install pyjwt cryptography`
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

#: 既定の置き場所
METADATA_DIR = Path(__file__).resolve().parent.parent / "Localization" / "app-store-metadata"

#: 言語によらない値をまとめたファイル
SHARED_FILE = "shared.json"

#: App Store Connect 側の上限。超えると反映時に弾かれるので、手元で先に落とす。
LIMITS = {
    "description": 4000,
    "keywords": 100,
}


class Metadata:
    """1 言語ぶんの App Store メタデータ。"""

    def __init__(self, language: str, store_locale: str, description: str,
                 keywords: str, support_url: str):
        self.language = language
        self.store_locale = store_locale
        self.description = description
        self.keywords = keywords
        self.support_url = support_url

    @property
    def attributes(self) -> dict[str, str]:
        return {
            "description": self.description,
            "keywords": self.keywords,
            "supportUrl": self.support_url,
        }


def load(directory: Path, language: str, store_locale: str, shared: dict) -> tuple[Metadata | None, list[str]]:
    """1 言語ぶん読む。問題があればメタデータの代わりに理由を返す。"""
    path = directory / f"{language}.json"
    if not path.is_file():
        return None, [f"{path} がありません"]

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return None, [f"{path} が JSON として読めません: {error}"]

    problems: list[str] = []
    description = raw.get("description")
    if not isinstance(description, str) or not description.strip():
        problems.append(f"{path}: description がありません")
        description = ""

    keywords_raw = raw.get("keywords")
    if not isinstance(keywords_raw, list) or not keywords_raw:
        problems.append(f"{path}: keywords がありません（配列で書く）")
        keywords = ""
    else:
        # App Store Connect にはカンマ区切りの 1 本の文字列として渡す。
        # 区切りのあとに空白を入れると、そのぶん 100 字の枠を食うので詰めて繋ぐ。
        keywords = ",".join(str(k).strip() for k in keywords_raw)

    for field, value in (("description", description), ("keywords", keywords)):
        limit = LIMITS[field]
        if len(value) > limit:
            problems.append(f"{path}: {field} が {len(value)} 字あります（上限 {limit} 字）")

    support_url = shared.get("supportUrl")
    if not support_url:
        problems.append(f"{directory / SHARED_FILE}: supportUrl がありません")
        support_url = ""

    if problems:
        return None, problems
    return Metadata(language, store_locale, description, keywords, support_url), []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--metadata-dir", type=Path, default=METADATA_DIR, help="<ここ>/<言語>.json を読む")
    parser.add_argument("--languages", help="対象の言語（カンマ区切り）。省略すると全言語")
    parser.add_argument("--bundle-id", help="--check のときは不要")
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
        "--missing-locales",
        choices=("fail", "skip", "create"),
        default="fail",
        help="App Store Connect にその言語が無いときの扱い。"
             "fail: 止める（既定） / skip: 飛ばす / create: その言語を追加してから反映する",
    )
    parser.add_argument("--check", action="store_true",
                        help="App Store Connect につながず、手元のファイルの欠損と文字数だけ見る")
    parser.add_argument("--dry-run", action="store_true", help="何も書き換えず、やることだけ出す")
    args = parser.parse_args()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from supported_languages import app_store_languages, parse_language_list

    targets = app_store_languages(parse_language_list(args.languages))

    shared_path = args.metadata_dir / SHARED_FILE
    shared = json.loads(shared_path.read_text(encoding="utf-8")) if shared_path.is_file() else {}
    if not shared_path.is_file():
        print(f"{shared_path} がありません", file=sys.stderr)

    entries: list[Metadata] = []
    problems: list[str] = []
    for target in targets:
        metadata, issues = load(args.metadata_dir, target.language, target.store_locale, shared)
        problems.extend(issues)
        if metadata:
            entries.append(metadata)

    if problems:
        raise SystemExit("\n".join(problems))

    if args.check:
        for entry in entries:
            print(f"  {entry.language}: description {len(entry.description)} 字 / "
                  f"keywords {len(entry.keywords)} 字")
        print(f"問題なし: {len(entries)} 言語")
        return 0

    if not args.bundle_id:
        raise SystemExit("--bundle-id が要ります")

    missing_key = [
        name for name, value in
        [("--key-id", args.key_id), ("--issuer-id", args.issuer_id), ("--private-key", args.private_key)]
        if not value
    ]
    if missing_key:
        raise SystemExit(f"認証情報が足りません: {', '.join(missing_key)}")

    from app_store_connect import AppStoreConnect, make_token

    token = make_token(args.key_id, args.issuer_id, Path(args.private_key).read_text())
    client = AppStoreConnect(token, dry_run=args.dry_run)

    app = client.find_app(args.bundle_id)
    version = client.find_version(app["id"], args.app_version)
    version_string = version["attributes"]["versionString"]
    print(f"対象: {app['attributes']['name']} {version_string} "
          f"({version['attributes']['appStoreState']})")
    if args.dry_run:
        print("--dry-run: App Store Connect には何も書き込みません")

    available = client.localizations(version["id"])

    # スクリーンショットのときと同じく、書き込む前に全言語ぶんの前提を確かめる
    plan: list[tuple[Metadata, str | None]] = []
    skipped: list[str] = []
    missing_locales: list[str] = []
    for entry in entries:
        localization_id = available.get(entry.store_locale)
        if localization_id is None:
            if args.missing_locales == "create":
                plan.append((entry, None))
            elif args.missing_locales == "skip":
                print(f"  飛ばす — {entry.language}: {entry.store_locale} が {version_string} にありません")
                skipped.append(entry.language)
            else:
                missing_locales.append(f"{entry.language} → {entry.store_locale}")
            continue
        plan.append((entry, localization_id))

    if missing_locales:
        raise SystemExit(
            f"App Store Connect の {version_string} に無い言語: {', '.join(missing_locales)}\n"
            "App Store Connect でこれらの言語を追加してから実行するか、"
            "--missing-locales create（追加してから反映）か "
            "--missing-locales skip（飛ばす）を付けてください。"
        )

    for entry, localization_id in plan:
        if localization_id is None:
            localization_id = client.create_localization(
                version["id"], entry.store_locale, entry.attributes)
            print(f"  {entry.language} → {entry.store_locale}: 追加して書き込み")
            continue
        if not args.dry_run:
            client.patch(
                f"/v1/appStoreVersionLocalizations/{localization_id}",
                {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization_id,
                        "attributes": entry.attributes,
                    }
                },
            )
        print(f"  {entry.language} → {entry.store_locale}: 書き込み")

    print(f"完了: {len(plan)} 言語")
    if skipped:
        print(f"飛ばした言語: {', '.join(skipped)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
