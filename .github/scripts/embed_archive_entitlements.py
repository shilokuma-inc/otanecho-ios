#!/usr/bin/env python3
"""署名なしの Archive のアプリと App Extension に、プロジェクトの entitlements をアドホック署名で入れる（upload.yml・archive-main.yml）。

書き出した IPA の全部のバンドルに、Archive の entitlements が残ったかも確かめる（`check`）。

Export は、Archive の各バンドルの署名にある entitlement だけを引き継いで配布用に署名し直し、profile からは足さない。
`CODE_SIGNING_ALLOWED=NO` の Archive には署名が無いので、そのまま書き出すと基本の entitlement（application-identifier など）しか
無い配布ビルドになる。App Groups が抜けると、アプリ・ウィジェット・共有拡張が同じ container を読めず、データがバンドルごとに分かれる。

- 各ターゲットの `CODE_SIGN_ENTITLEMENTS` の `$(VAR)` を、ビルドの設定（`xcodebuild -showBuildSettings`）で展開して署名する。
  値は Export が配布用の profile に合わせて書き換える
- Archive の中の `.app`・`.appex` を、`FULL_PRODUCT_NAME` でターゲットと突き合わせる。ビルドの設定は `-alltargets` で読む
  （スキームで読むと、スキームに書いていない依存先の App Extension のターゲットが出ないことがある）
- 外側の署名は内側のバンドルの署名を封じるので、深い（内側の）バンドルから署名する

shilokuma-inc/app-kit v1.4.0 の `tools/embed_archive_entitlements.py`（アプリ本体だけを扱う）を、
shariverse/oshikatsu-countdown-ios の `.github/scripts/embed-entitlements.rb` と同じやり方で App Extension まで広げたもの。
app-kit が App Extension を扱えるようになったら、ワークフローごと app-kit に入れ替えてこのファイルを消す。

    python3 .github/scripts/embed_archive_entitlements.py embed build.xcarchive \\
        --project Otanecho.xcodeproj --sdk iphoneos --configuration Release
    python3 .github/scripts/embed_archive_entitlements.py check build.xcarchive app.ipa   # Export の後（IPA か、それを書き出した場所）
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

#: entitlements の値の中の `$(NAME)` / `${NAME}`（Xcode がビルドの設定で展開する書き方）
VARIABLE = re.compile(r"\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]")

#: 展開し残した変数（`$(NAME:修飾子)`・`$NAME` も含む）。署名の前と、書き出した IPA で探す
LEFTOVER = re.compile(r"\$[({]?[A-Za-z_]")

#: Xcode が署名のときに決める変数のうち、Archive の前には決められないもの（App ID の接頭辞。古い App ID では Team ID と違う）
UNKNOWN_BEFORE_SIGNING = "AppIdentifierPrefix"

#: 署名し直すバンドル
BUNDLE_SUFFIXES = (".app", ".appex")

#: バンドルの中にあると、署名していない中身を抱えたまま外側を署名することになるもの
NESTED_CODE_SUFFIXES = (".framework", ".dylib")


def fail(message: str) -> SystemExit:
    """GitHub Actions の注釈になる形のエラーで止める（`raise fail(...)`）。"""
    return SystemExit(f"::error::{message}")


def expand(value, settings: dict[str, str]):
    """entitlements（plist を読んだもの）の文字列の `$(NAME)` を、ビルドの設定の値に置き換える。

    設定に無い名前があれば止める。Xcode は空にするが、App Group が空のまま署名されると気づけない。
    """
    if isinstance(value, str):
        missing = sorted({name for name in VARIABLE.findall(value) if name not in settings})
        if missing:
            hint = ""
            if UNKNOWN_BEFORE_SIGNING in missing:
                hint = ("（$(AppIdentifierPrefix) は署名のときに App ID の profile から決まり、Archive の前には分かりません。"
                        "App ID の接頭辞が Team ID と同じなら $(TeamIdentifierPrefix) と書いてください）")
            raise fail(f"entitlements の {', '.join(missing)} がビルドの設定にありません: {value}{hint}")
        return VARIABLE.sub(lambda match: settings[match.group(1)], value)
    if isinstance(value, list):
        return [expand(item, settings) for item in value]
    if isinstance(value, dict):
        return {key: expand(item, settings) for key, item in value.items()}
    return value


def with_signing_prefixes(settings: dict[str, str]) -> dict[str, str]:
    """`$(TeamIdentifierPrefix)` を、ビルドの設定の DEVELOPMENT_TEAM（`<Team ID>.`）で補う。

    Xcode は署名するときにこの値を決めるので、`-showBuildSettings` の結果には無い（App Groups などに使う）。
    `$(AppIdentifierPrefix)` は App ID の接頭辞で、古い App ID では Team ID と違うので補わない（使っていれば expand が止める）。
    """
    team = settings.get("DEVELOPMENT_TEAM", "")
    if not team:
        return settings
    return {"TeamIdentifierPrefix": f"{team}.", **settings}


def target_settings(entries: list[dict], product_name: str) -> tuple[str, dict[str, str]]:
    """`-showBuildSettings -alltargets -json` の結果から、`product_name`（`App.app`・`Widget.appex`）を作るターゲットを選ぶ。

    `-alltargets` は同じターゲットを 2 回出すことがあるので、ターゲットの名前でまとめてから 1 つに決まるかを見る。
    """
    matches = {entry["target"]: entry["buildSettings"] for entry in entries
               if entry.get("buildSettings", {}).get("FULL_PRODUCT_NAME") == product_name}
    if len(matches) != 1:
        raise fail(f"{product_name} を作るターゲットが 1 つに決まりません（{', '.join(sorted(matches)) or 'なし'}）")
    return next(iter(matches.items()))


def archived_bundles(archive: Path) -> list[Path]:
    """Archive の `Products/Applications` の中のアプリと App Extension を、深い（内側の）ものから順に返す。"""
    applications = archive / "Products" / "Applications"
    bundles = [path for path in applications.rglob("*") if path.is_dir() and path.suffix in BUNDLE_SUFFIXES]
    if not bundles:
        raise fail(f"{applications} にアプリがありません")
    return sorted(bundles, key=lambda path: (-len(path.relative_to(applications).parts), str(path)))


def signed_entitlements(bundle: Path) -> dict | None:
    """バンドルの署名にある entitlements。署名が無ければ None。"""
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)],
                            capture_output=True, check=False)
    if result.returncode != 0:
        return None
    return plistlib.loads(result.stdout) if result.stdout.strip() else {}


def merge(signed: dict, added: dict, name: str) -> dict:
    """署名済みのバンドルの entitlements に、プロジェクトの entitlements を足す。同じキーで値が違えば止める。"""
    conflicts = sorted(key for key in signed.keys() & added.keys() if signed[key] != added[key])
    if conflicts:
        raise fail(f"{name} の署名の {', '.join(conflicts)} が、プロジェクトの entitlements と違います")
    return {**signed, **added}


def sign(bundle: Path, entitlements: dict | None, signed: dict | None) -> None:
    """バンドルをアドホック署名する（本番の署名は Export がする）。entitlements が None なら entitlements なしで署名する。"""
    # 署名し直すときは、元の署名の識別子とフラグを残す
    preserve = [] if signed is None else ["--preserve-metadata=identifier,flags"]
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none", *preserve]
    with tempfile.NamedTemporaryFile(suffix=".entitlements") as file:
        if entitlements is not None:
            file.write(plistlib.dumps(entitlements))
            file.flush()
            command += ["--generate-entitlement-der", "--entitlements", file.name]
        subprocess.run([*command, str(bundle)], check=True)


def embed(args: argparse.Namespace) -> int:
    """Archive のアプリと App Extension を、`CODE_SIGN_ENTITLEMENTS` を展開した entitlements でアドホック署名する。

    `CODE_SIGN_ENTITLEMENTS` が空のバンドルも、外側を署名できるように entitlements なしで署名する。
    署名の後に、入れた entitlements と署名の中身が同じかを確かめる。
    """
    bundles = archived_bundles(args.archive)
    applications = args.archive / "Products" / "Applications"
    nested_code = sorted(str(path.relative_to(applications)) for path in applications.rglob("*")
                         if path.suffix in NESTED_CODE_SUFFIXES)
    if nested_code:
        # 足すときは、フレームワークも内側から署名するように直す（app-kit の fix-stub-framework-signatures.sh も参考になる）
        raise fail(f"Archive に、このスクリプトが署名しない中身があります: {', '.join(nested_code)}")

    output = subprocess.run(
        ["xcodebuild", "-showBuildSettings", "-json", "-project", args.project, "-alltargets",
         "-sdk", args.sdk, "-configuration", args.configuration],
        capture_output=True, text=True, check=True,
    ).stdout
    entries = json.loads(output)

    embedded = 0
    for bundle in bundles:
        name = str(bundle.relative_to(applications))
        target, settings = target_settings(entries, bundle.name)
        settings = with_signing_prefixes(settings)
        signed = signed_entitlements(bundle)
        path = settings.get("CODE_SIGN_ENTITLEMENTS", "")
        if not path:
            if signed is None:
                sign(bundle, None, None)
            print(f"{name}（{target}）: CODE_SIGN_ENTITLEMENTS が空なので、entitlements は入れません")
            continue

        entitlements = expand(plistlib.loads((Path(settings["SRCROOT"]) / path).read_bytes()), settings)
        leftover = sorted(key for key, value in entitlements.items() if LEFTOVER.search(repr(value)))
        if leftover:
            raise fail(f"{path} の {', '.join(leftover)} に、展開できない変数が残っています")
        if signed is not None:
            entitlements = merge(signed, entitlements, name)
        if entitlements != signed:
            sign(bundle, entitlements, signed)
            if signed_entitlements(bundle) != entitlements:
                raise fail(f"{name} の署名の entitlements が、入れようとしたものと違います")
        for key, value in sorted(entitlements.items()):
            print(f"{name}（{target}）に入れました: {key} = {value}")
        embedded += 1

    if embedded == 0:
        print("entitlements を入れたバンドルはありません（どのターゲットも CODE_SIGN_ENTITLEMENTS が空）")
    return 0


def exported_ipa(path: Path) -> Path:
    """書き出した IPA を返す。書き出した場所（フォルダ）を渡されたら、その中の 1 つを選ぶ。"""
    if path.is_file():
        return path
    packages = sorted(path.glob("*.ipa"))
    if len(packages) != 1:
        raise fail(f"{path} の中に、書き出した IPA が 1 つに決まりません（{len(packages)} 件）")
    return packages[0]


def missing_entitlements(archived: dict, exported: dict) -> list[str]:
    """Archive の署名にあるのに、書き出したバンドルに無い・減った entitlement の説明。

    文字列などの値は比べない（`aps-environment` のように、Export が配信用に書き換える項目があるため）。
    配列（App Groups・Associated Domains など）は、Archive の項目がすべて残っているかを見る。
    """
    problems = []
    for key, value in sorted(archived.items()):
        if key not in exported:
            problems.append(key)
        elif isinstance(value, list):
            kept = exported[key] if isinstance(exported[key], list) else []
            dropped = [item for item in value if item not in kept]
            if dropped:
                problems.append(f"{key} の {', '.join(map(str, dropped))}")
    return problems


def check(args: argparse.Namespace) -> int:
    """書き出した IPA の全部のバンドルの署名に、Archive の同じバンドルの entitlement がすべて残っているかを確かめる。

    配布用の profile に無い entitlement（App ID の capability が無効など）を Export が落とすと、
    その機能が動かなくなって初めて気づくことになるので、App Store Connect に上げる前に止める。
    値は、展開されていない変数 `$(…)` が残っていないかも見る。
    """
    ipa = exported_ipa(args.export)
    applications = args.archive / "Products" / "Applications"
    problems = []
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(["ditto", "-x", "-k", str(ipa), directory], check=True)
        payload = Path(directory) / "Payload"
        for bundle in archived_bundles(args.archive):
            name = str(bundle.relative_to(applications))
            exported_bundle = payload / name
            if not exported_bundle.is_dir():
                problems.append(f"{ipa.name} に {name} がありません")
                continue
            archived = signed_entitlements(bundle)
            if archived is None:
                # embed を流していない（署名なしのまま書き出した）と、比べるものが無くて通ってしまうので止める
                problems.append(f"Archive の {name} に署名がありません。書き出しの前に embed を流してください")
                continue
            exported = signed_entitlements(exported_bundle) or {}
            for key, value in sorted(exported.items()):
                print(f"{name}: {key} = {value}")
            missing = missing_entitlements(archived, exported)
            if missing:
                problems.append(f"{name} に {'、'.join(missing)} がありません。"
                                "配布用の profile に入っているか（App ID の capability が有効か）を確かめてください")
            leftover = sorted(key for key, value in exported.items() if LEFTOVER.search(repr(value)))
            if leftover:
                problems.append(f"{name} の entitlement に、展開されていない変数 $(…) が残っています: {', '.join(leftover)}")
    if problems:
        for problem in problems:
            print(f"::error::{problem}")
        return 1
    return 0


def main(argv: list[str]) -> int:
    """`embed`・`check` を流す（使い方はモジュールの説明）。"""
    parser = argparse.ArgumentParser(description="Archive のアプリと App Extension に entitlements を入れ、書き出した IPA に残ったかを確かめる")
    commands = parser.add_subparsers(dest="command", required=True)
    embed_parser = commands.add_parser("embed", help="Archive のアプリと App Extension に entitlements をアドホック署名で入れる")
    embed_parser.add_argument("archive", type=Path, help="xcodebuild archive で作った .xcarchive")
    embed_parser.add_argument("--project", required=True)
    embed_parser.add_argument("--sdk", required=True)
    embed_parser.add_argument("--configuration", required=True)
    embed_parser.set_defaults(handler=embed)
    check_parser = commands.add_parser("check", help="書き出した IPA の全部のバンドルに Archive の entitlements が残ったかを確かめる")
    check_parser.add_argument("archive", type=Path)
    check_parser.add_argument("export", type=Path, help="書き出した IPA か、それを書き出したフォルダ")
    check_parser.set_defaults(handler=check)
    args = parser.parse_args(argv)
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
