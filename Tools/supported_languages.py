"""対応言語の定義（Localization/supported-languages.json）を読む共通処理。

スクリーンショットの撮影（extract_screenshots.py）と App Store Connect への反映
（upload_screenshots.py）、および GitHub Actions のワークフローから使う。

言語の一覧も、言語ごとの撮影設定・App Store のロケールも、すべてあの JSON が単一の定義。
ここには「読んで整合を確かめる」以上のことは書かない。
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Localization" / "supported-languages.json"


class AppStoreLanguage(NamedTuple):
    """1 言語ぶんの撮影・反映の設定。"""

    #: アプリ側の言語コード。String Catalog と screenshot-content.json のキー
    language: str
    #: xcodebuild -testLanguage に渡す値
    test_language: str
    #: xcodebuild -testRegion に渡す値
    test_region: str
    #: App Store Connect のロケール（アプリの言語コードとは別物）
    store_locale: str


def load_config() -> dict:
    return json.loads(CONFIG.read_text())


def all_languages() -> list[str]:
    """対応を宣言している言語すべて。JSON に書いた順のまま返す。"""
    return list(load_config()["languages"])


def app_store_languages(languages: list[str] | None = None) -> list[AppStoreLanguage]:
    """指定した言語（省略時は全言語）の撮影・反映の設定を返す。

    `appStore` に定義が無い言語があれば、その場で止める。
    黙って飛ばすと「撮ったつもりの言語が 1 つ足りない」ことに気づけないため。
    """
    config = load_config()
    known = config["languages"]
    mapping = config["appStore"]

    targets = known if languages is None else languages

    unknown = [language for language in targets if language not in known]
    if unknown:
        raise SystemExit(
            f"supported-languages.json の languages に無い言語: {', '.join(unknown)}\n"
            f"指定できるのは: {', '.join(known)}"
        )

    missing = [language for language in targets if language not in mapping]
    if missing:
        raise SystemExit(
            f"supported-languages.json の appStore に定義が無い言語: {', '.join(missing)}\n"
            "testLanguage / testRegion / storeLocale を足してください。"
        )

    return [
        AppStoreLanguage(
            language=language,
            test_language=mapping[language]["testLanguage"],
            test_region=mapping[language]["testRegion"],
            store_locale=mapping[language]["storeLocale"],
        )
        for language in targets
    ]


def parse_language_list(raw: str | None) -> list[str] | None:
    """カンマ区切り（または空白区切り）の指定を配列にする。空なら None（＝全言語）。"""
    if raw is None:
        return None
    items = [item.strip() for item in raw.replace(",", " ").split()]
    return items or None


def main() -> int:
    """撮影の設定をタブ区切りで出す。GitHub Actions のシェルから回すために使う。

        python3 Tools/supported_languages.py            # 全言語
        python3 Tools/supported_languages.py ja,zh-Hans # 指定した言語だけ
    """
    import argparse

    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("languages", nargs="?", help="カンマ区切りの言語。省略すると全言語")
    args = parser.parse_args()

    for entry in app_store_languages(parse_language_list(args.languages)):
        print("\t".join([entry.language, entry.test_language, entry.test_region, entry.store_locale]))
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
