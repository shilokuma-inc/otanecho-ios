#!/usr/bin/env python3
"""UI テストの `.xcresult` から App Store 用のスクリーンショットを取り出す。

`OtanechoUITests/ScreenshotUITests` は 1 枚ずつ `XCTAttachment` として残すので、
`xcresulttool export attachments` で書き出し、`01_timeline.png` のような名前に戻して
`<出力先>/<言語>/` に並べ直す。

寸法と PNG の形式もここで確かめる。App Store Connect は寸法が 1 px でも違えば弾くし、
アルファ付きの PNG も受け付けない。アップロードまで進んでから落ちると原因が遠くなるため、
取り出した時点で落とす。

    python3 Tools/extract_screenshots.py \\
        --xcresult build/screenshots/ja.xcresult \\
        --language ja \\
        --output-dir build/screenshots
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

#: 添付名は XCTest 側で連番と UUID が足される（01_timeline.png → 01_timeline_0_<UUID>.png）
ATTACHMENT_NAME = re.compile(r"^(?P<name>\d{2}_[A-Za-z0-9-]+)_\d+_[0-9A-Fa-f-]{36}\.png$")

#: PNG の色タイプ。2 = RGB（アルファ無し）。App Store Connect はアルファ付きを弾く。
PNG_COLOR_TYPE_RGB = 2


def export_attachments(xcresult: Path, destination: Path) -> list[dict]:
    """`.xcresult` の添付を書き出し、manifest.json の中身を返す。"""
    result = subprocess.run(
        [
            "xcrun", "xcresulttool", "export", "attachments",
            "--path", str(xcresult),
            "--output-path", str(destination),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"xcresulttool が失敗しました（{result.returncode}）\n{result.stderr.strip()}")
    manifest = destination / "manifest.json"
    if not manifest.exists():
        raise SystemExit(f"{xcresult} から添付を書き出せませんでした（manifest.json が無い）")
    return json.loads(manifest.read_text())


def collect_screenshots(manifest: list[dict], exported_dir: Path) -> dict[str, Path]:
    """添付名 → 書き出されたファイル、の対応を作る。

    テストが再試行されると同じ名前が複数回出てくるので、時刻が新しいほうを採る。
    """
    found: dict[str, tuple[float, Path]] = {}
    for test in manifest:
        for attachment in test.get("attachments", []):
            readable = attachment.get("suggestedHumanReadableName", "")
            match = ATTACHMENT_NAME.match(readable)
            if match is None:
                continue
            name = match.group("name")
            timestamp = attachment.get("timestamp", 0.0)
            path = exported_dir / attachment["exportedFileName"]
            if name not in found or timestamp >= found[name][0]:
                found[name] = (timestamp, path)
    return {name: path for name, (_, path) in found.items()}


def read_png_header(path: Path) -> tuple[int, int, int]:
    """PNG の幅・高さ・色タイプを IHDR から読む。"""
    raw = path.read_bytes()[:26]
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"PNG ではありません: {path}")
    width, height, _depth, color_type = struct.unpack(">IIBB", raw[16:26])
    return width, height, color_type


def verify(path: Path, expected: tuple[int, int] | None) -> tuple[int, int]:
    width, height, color_type = read_png_header(path)
    if color_type != PNG_COLOR_TYPE_RGB:
        raise SystemExit(
            f"{path.name}: PNG の色タイプが {color_type} です。"
            "App Store Connect はアルファ付きの画像を受け付けません。"
        )
    if expected is not None and (width, height) != expected:
        raise SystemExit(
            f"{path.name}: {width}x{height} でした（期待は {expected[0]}x{expected[1]}）。"
            "撮影に使ったシミュレータの機種が想定と違う可能性があります。"
        )
    return width, height


def parse_size(raw: str | None) -> tuple[int, int] | None:
    if raw is None:
        return None
    try:
        width, height = raw.lower().split("x")
        return int(width), int(height)
    except ValueError:
        raise SystemExit(f"--expected-size は 1242x2688 の形で指定してください: {raw}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xcresult", type=Path, required=True, help="UI テストの結果バンドル")
    parser.add_argument("--language", required=True, help="撮影した言語。出力先のフォルダ名になる")
    parser.add_argument("--output-dir", type=Path, required=True, help="出力先。<ここ>/<言語>/ に並べる")
    parser.add_argument("--expected-size", default="1242x2688", help="期待する寸法。none で確認しない")
    parser.add_argument("--min-count", type=int, default=1, help="この枚数に満たなければ失敗にする")
    args = parser.parse_args()

    expected = None if args.expected_size == "none" else parse_size(args.expected_size)

    with tempfile.TemporaryDirectory() as tmp:
        exported = Path(tmp)
        manifest = export_attachments(args.xcresult, exported)
        screenshots = collect_screenshots(manifest, exported)

        if len(screenshots) < args.min_count:
            raise SystemExit(
                f"{args.language}: スクリーンショットが {len(screenshots)} 枚しかありません"
                f"（{args.min_count} 枚以上のはず）。UI テストが途中で失敗していないか確認してください。"
            )

        destination = args.output_dir / args.language
        # 撮り直しのたびに古い画像が混ざらないよう、言語ごとに作り直す
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True)

        for name in sorted(screenshots):
            target = destination / f"{name}.png"
            shutil.copyfile(screenshots[name], target)
            width, height = verify(target, expected)
            print(f"{args.language}/{target.name}  {width}x{height}")

    print(f"{args.language}: {len(screenshots)} 枚を {destination} に取り出しました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
