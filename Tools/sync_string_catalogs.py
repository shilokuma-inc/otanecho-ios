#!/usr/bin/env python3
"""ソースコードから String Catalog にキーを同期する。

Xcode.app でビルドすると `.xcstrings` へのキー追加は自動で行われるが、
`xcodebuild` では行われない。コマンドラインで作業するときはこのスクリプトを使う。

やっていること:
  1. `xcodebuild build` で各ソースファイルの `.stringsdata` を作らせる
  2. `xcrun xcstringstool sync` で `.stringsdata` を `.xcstrings` にマージする

使い方:
    python3 Tools/sync_string_catalogs.py
    python3 Tools/sync_string_catalogs.py --no-build   # 直前のビルド成果物を使う
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = "Otanecho.xcodeproj"
SCHEME = "Otanecho"
DESTINATION = "generic/platform=iOS Simulator"

# ターゲット名 -> そのターゲットが持つ String Catalog。
# `xcstringstool sync` は渡した .xcstrings のテーブル名（ファイル名）で振り分けるため、
# 1 ターゲット分をまとめて渡す。
CATALOGS = {
    "Otanecho": [
        "Otanecho/Resources/Localizable.xcstrings",
        "Otanecho/Resources/InfoPlist.xcstrings",
        # App Shortcuts の起動フレーズ（phrases）はこのテーブルに入る
        "Otanecho/Resources/AppShortcuts.xcstrings",
    ],
    "OtanechoWidgets": [
        "OtanechoWidgets/Localizable.xcstrings",
        "OtanechoWidgets/InfoPlist.xcstrings",
    ],
    "OtanechoShare": [
        "OtanechoShare/Localizable.xcstrings",
        "OtanechoShare/InfoPlist.xcstrings",
    ],
}


def xcodebuild(*args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    command = [
        "xcodebuild",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", DESTINATION,
        "-skipPackagePluginValidation",
        *args,
    ]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=capture, check=False)


def build_settings() -> dict[str, str]:
    """`-showBuildSettings` から中間生成物の場所を割り出すための設定を読む。"""
    result = xcodebuild("-showBuildSettings", capture=True)
    if result.returncode != 0:
        sys.exit(f"xcodebuild -showBuildSettings が失敗しました:\n{result.stderr}")
    settings: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if " = " not in line:
            continue
        key, _, value = line.strip().partition(" = ")
        settings.setdefault(key, value)
    return settings


def stringsdata_files(objroot: pathlib.Path, config_dir: str, target: str) -> list[pathlib.Path]:
    """対象ターゲットの `.stringsdata` を集める。

    中間生成物は `<OBJROOT>/<Project>.build/<Config><Platform>/<Target>.build/Objects-normal/<arch>/`
    に置かれる。他ターゲット・他プラットフォームのものを拾わないよう、ターゲットまで絞って探す。
    """
    base = objroot / f"{SCHEME}.build" / config_dir / f"{target}.build" / "Objects-normal"
    return sorted(base.glob("*/*.stringsdata"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="ビルドを省略し、直前の成果物を使う")
    args = parser.parse_args()

    if not args.no_build:
        print("==> ビルドして .stringsdata を生成")
        if xcodebuild("build", "-quiet").returncode != 0:
            return 1

    settings = build_settings()
    objroot = pathlib.Path(settings["OBJROOT"])
    config_dir = settings["CONFIGURATION"] + settings.get("EFFECTIVE_PLATFORM_NAME", "")

    failed = False
    for target, catalogs in CATALOGS.items():
        files = stringsdata_files(objroot, config_dir, target)
        if not files:
            print(f"!! {target}: .stringsdata が見つかりません（ビルドが必要かもしれません）")
            failed = True
            continue
        command = ["xcrun", "xcstringstool", "sync", *catalogs, "--stringsdata", *map(str, files)]
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            print(f"!! {target}: sync に失敗\n{result.stderr}")
            failed = True
            continue
        print(f"==> {target} を同期（.stringsdata {len(files)} 件）: {', '.join(catalogs)}")
        if result.stderr.strip():
            print(result.stderr.strip())

    if failed:
        return 1
    print("\n同期が完了しました。未翻訳のキーに訳を入れてください。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
