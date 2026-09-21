#!/usr/bin/env python3
"""String Catalog を Xcode と同じ整形に揃える。

`.xcstrings` は JSON だが、Xcode はキーと値の区切りを `" : "`（コロンの前にも空白）で書き、
キーを辞書順に並べる。スクリプトで編集したあとにこの整形へ戻しておかないと、
Xcode で開いて保存した瞬間にファイル全体が差分になる。

使い方:
    python3 Tools/format_string_catalogs.py          # 整形する
    python3 Tools/format_string_catalogs.py --check  # 整形済みかを確認するだけ（CI 用）
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

CATALOG_DIRS = ("Otanecho/Resources", "OtanechoWidgets", "OtanechoShare")


def catalogs() -> list[pathlib.Path]:
    found: list[pathlib.Path] = []
    for directory in CATALOG_DIRS:
        found.extend(sorted((ROOT / directory).glob("*.xcstrings")))
    return found


def formatted(data: dict) -> str:
    """Xcode と同じ整形の JSON 文字列にする。"""
    data = dict(data)
    if "strings" in data:
        data["strings"] = dict(sorted(data["strings"].items()))
    return json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n"


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def save(path: pathlib.Path, data: dict) -> None:
    path.write_text(formatted(data))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="整形せず、整形済みかどうかだけを見る")
    args = parser.parse_args()

    unformatted: list[pathlib.Path] = []
    for path in catalogs():
        want = formatted(load(path))
        if path.read_text() == want:
            continue
        unformatted.append(path)
        if not args.check:
            path.write_text(want)

    relative = [str(p.relative_to(ROOT)) for p in unformatted]
    if args.check:
        if relative:
            print("整形が Xcode と違うファイル:")
            for name in relative:
                print(" -", name)
            print("\npython3 Tools/format_string_catalogs.py を実行してください。")
            return 1
        print(f"整形済み（{len(catalogs())} ファイル）")
        return 0

    if relative:
        print("整形しました:")
        for name in relative:
            print(" -", name)
    else:
        print(f"整形の変更はありません（{len(catalogs())} ファイル）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
