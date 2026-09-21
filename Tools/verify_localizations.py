#!/usr/bin/env python3
"""String Catalog の翻訳欠損とプレースホルダ不整合を検証する。

String Catalog は訳が欠けていると**黙ってソース言語（英語）にフォールバックする**ため、
日本語 UI の中に英語が混ざっていても実行するまで気づけない。これを機械的に落とすのが目的。

見ているもの:
  1. 訳の欠損            対応言語（enforced）のエントリが無い
  2. 未翻訳              state が "new"
  3. レビュー待ち         state が "needs_review"
  4. プレースホルダ不整合  %@ / %lld などの数・型・位置引数がソースと食い違う
  5. stale なキー         extractionState が "stale"（コードから消えたキーの残骸）
  6. 複数形の欠損         その言語に必要な複数形カテゴリが揃っていない
  7. カタログ間の不一致    同じキーの訳が複数の .xcstrings で食い違う
  8. 設定のずれ           sourceLanguage / developmentLanguage / enforced の整合

使い方:
    python3 Tools/verify_localizations.py
    python3 Tools/verify_localizations.py --languages ja,en   # 対象言語を絞る
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Localization" / "supported-languages.json"
PROJECT_YML = ROOT / "project.yml"

CATALOG_DIRS = ("Otanecho/Resources", "OtanechoWidgets", "OtanechoShare")

# 各言語で必須の複数形カテゴリ（CLDR の cardinal plural rules より）。
#
# es / fr / it / pt-BR の "many" は 100 万以上のような大きな数にだけ使われ、
# 実際のアプリでは埋めないことも多いので必須にしていない。
# ru は 2〜4 / 5〜20 で語形が変わるため few・many まで必須。
REQUIRED_PLURAL_CATEGORIES = {
    "en": {"one", "other"},
    "de": {"one", "other"},
    "es": {"one", "other"},
    "fr": {"one", "other"},
    "it": {"one", "other"},
    "pt-BR": {"one", "other"},
    "ru": {"one", "few", "many", "other"},
    "ja": {"other"},
    "ko": {"other"},
    "zh-Hans": {"other"},
    "zh-Hant": {"other"},
    "id": {"other"},
}

# 訳が入っていると見なす state。
TRANSLATED_STATES = {"translated"}
# 落とす state とその理由。
REJECTED_STATES = {
    "new": "未翻訳（state: new）",
    "needs_review": "レビュー待ち（state: needs_review）",
}

# `%1$@` `%lld` `%.2f` などのフォーマット指定子。`%%` はリテラルなので拾わない。
SPECIFIER = re.compile(
    r"%(?:(?P<index>\d+)\$)?"
    r"(?P<flags>[-+ #0]*)"
    r"(?P<width>\d+|\*)?"
    r"(?:\.(?P<precision>\d+|\*))?"
    r"(?P<length>hh|h|ll|l|q|L|z|t|j)?"
    r"(?P<conversion>[@diouxXeEfgGcsSpaA])"
)

# App Shortcuts / App Intents が使う `${applicationName}` `${text}` 形式のプレースホルダ。
NAMED_PLACEHOLDER = re.compile(r"\$\{(\w+)\}")

# 型が同じとみなす変換指定子。長さ修飾子（lld と d など）は区別しない。
CONVERSION_KINDS = {
    "@": "object", "s": "cstring", "S": "cstring",
    "d": "int", "i": "int", "o": "int", "u": "int", "x": "int", "X": "int", "c": "int",
    "e": "float", "E": "float", "f": "float", "g": "float", "G": "float", "a": "float", "A": "float",
    "p": "pointer",
}


class Finding:
    """1 件の違反。"""

    def __init__(self, catalog: str, key: str, language: str, reason: str, kind: str):
        self.catalog = catalog
        self.key = key
        self.language = language
        self.reason = reason
        self.kind = kind

    def __str__(self) -> str:
        where = f"{self.catalog}: {self.key!r}"
        if self.language:
            where += f" ({self.language})"
        return f"{where}: {self.reason}"


def load_config() -> dict:
    config = json.loads(CONFIG.read_text())
    for field in ("sourceLanguage", "languages", "enforced"):
        if field not in config:
            sys.exit(f"{CONFIG} に {field} がありません")
    return config


def catalogs() -> list[pathlib.Path]:
    found: list[pathlib.Path] = []
    for directory in CATALOG_DIRS:
        found.extend(sorted((ROOT / directory).glob("*.xcstrings")))
    return found


def specifiers(text: str) -> list[tuple[int | None, str]]:
    """フォーマット指定子を (位置引数, 型) のリストにする。出現順。"""
    result: list[tuple[int | None, str]] = []
    for match in SPECIFIER.finditer(text):
        index = int(match.group("index")) if match.group("index") else None
        kind = CONVERSION_KINDS.get(match.group("conversion"), match.group("conversion"))
        result.append((index, kind))
    return result


def compare_specifiers(source: str, translation: str) -> str | None:
    """プレースホルダの食い違いを説明する文字列。問題なければ None。"""
    expected_named = set(NAMED_PLACEHOLDER.findall(source))
    actual_named = set(NAMED_PLACEHOLDER.findall(translation))
    if expected_named != actual_named:
        missing = sorted(expected_named - actual_named)
        extra = sorted(actual_named - expected_named)
        parts = []
        if missing:
            parts.append("足りない: " + ", ".join(f"${{{name}}}" for name in missing))
        if extra:
            parts.append("余分: " + ", ".join(f"${{{name}}}" for name in extra))
        return "名前付きプレースホルダが一致しません（" + " / ".join(parts) + "）"

    expected = specifiers(source)
    actual = specifiers(translation)

    if collections.Counter(k for _, k in expected) != collections.Counter(k for _, k in actual):
        return (
            f"プレースホルダが一致しません（ソース: {_format_specifiers(expected)} / "
            f"訳: {_format_specifiers(actual)}）"
        )

    # 訳が位置引数を使っている場合は、その位置の型がソースの同じ位置と一致すること
    indexed = [(i, k) for i, k in actual if i is not None]
    if not indexed:
        return None
    if len(indexed) != len(actual):
        return "位置引数（%1$@ など）と位置指定なしの指定子が混在しています"
    positions = sorted(i for i, _ in indexed)
    if positions != list(range(1, len(expected) + 1)):
        return f"位置引数が 1〜{len(expected)} を網羅していません（{positions}）"
    for index, kind in indexed:
        if expected[index - 1][1] != kind:
            return f"位置引数 %{index}$ の型がソースと違います（ソース: {expected[index - 1][1]} / 訳: {kind}）"
    return None


def _format_specifiers(items: list[tuple[int | None, str]]) -> str:
    return "[" + ", ".join(k if i is None else f"{i}:{k}" for i, k in items) + "]"


def source_value(key: str, entry: dict, source_language: str) -> str:
    """ソース言語の文言。String Catalog はソース言語の値を省略でき、そのときはキーが値になる。"""
    unit = entry.get("localizations", {}).get(source_language, {}).get("stringUnit")
    if unit and unit.get("value"):
        return unit["value"]
    return key


def units_of(localization: dict) -> list[tuple[str, str | None, str]]:
    """1 言語分の訳を (ラベル, state, 文言) のリストにする。

    String Catalog には 3 つの持ち方がある。
    - `stringUnit`: ふつうの訳
    - `variations.plural`: 複数形（カテゴリごとに 1 つ）
    - `stringSet`: App Shortcuts の起動フレーズ。1 つのキーに複数の言い回しを持てる
    """
    if "stringUnit" in localization:
        unit = localization["stringUnit"]
        return [("", unit.get("state"), unit.get("value", ""))]

    if "stringSet" in localization:
        string_set = localization["stringSet"]
        state = string_set.get("state")
        values = string_set.get("values", [])
        return [(f"phrase{index + 1}", state, value) for index, value in enumerate(values)]

    plural = localization.get("variations", {}).get("plural", {})
    result: list[tuple[str, str | None, str]] = []
    for category, value in sorted(plural.items()):
        unit = value.get("stringUnit")
        if unit:
            result.append((category, unit.get("state"), unit.get("value", "")))
    return result


def verify_catalog(path: pathlib.Path, config: dict, enforced: list[str]) -> list[Finding]:
    name = str(path.relative_to(ROOT))
    data = json.loads(path.read_text())
    findings: list[Finding] = []

    source_language = data.get("sourceLanguage")
    if source_language != config["sourceLanguage"]:
        findings.append(Finding(name, "(file)", "", f"sourceLanguage が {source_language!r}（期待: {config['sourceLanguage']!r}）", "config"))
        source_language = config["sourceLanguage"]

    for key, entry in sorted(data.get("strings", {}).items()):
        if entry.get("extractionState") == "stale":
            findings.append(Finding(name, key, "", "コードに存在しないキーが残っています（extractionState: stale）", "stale"))

        localizations = entry.get("localizations", {})
        source = source_value(key, entry, source_language)
        source_is_plural = "variations" in localizations.get(source_language, {})

        for language in enforced:
            localization = localizations.get(language)

            # ソース言語は値を省略できる（キーがそのまま文言になる）
            if localization is None:
                if language == source_language and not source_is_plural:
                    continue
                findings.append(Finding(name, key, language, "訳がありません", "missing"))
                continue

            units = units_of(localization)
            if not units and "variations" not in localization:
                findings.append(Finding(name, key, language, "訳の中身が空です", "missing"))
                continue

            if "variations" in localization:
                required = REQUIRED_PLURAL_CATEGORIES.get(language, {"other"})
                present = {category for category, _, _ in units}
                for missing in sorted(required - present):
                    findings.append(
                        Finding(name, key, language, f"複数形の {missing} がありません（必要: {sorted(required)}）", "plural")
                    )
            elif source_is_plural and "stringSet" not in localization:
                findings.append(
                    Finding(name, key, language, "ソースが複数形なのに単数形の訳になっています", "plural")
                )

            is_source = language == source_language
            for category, state, value in units:
                label = f"{language}/{category}" if category else language

                # ソース言語はコードに書いた文言そのものなので、state は見ない
                # （抽出直後は "new" のまま残るが、翻訳の欠損ではない）
                if not is_source:
                    if state in REJECTED_STATES:
                        findings.append(Finding(name, key, label, REJECTED_STATES[state], "state"))
                        continue
                    if state not in TRANSLATED_STATES:
                        findings.append(Finding(name, key, label, f"state が {state!r} です", "state"))
                        continue

                if not value.strip():
                    findings.append(Finding(name, key, label, "訳が空文字です", "missing"))
                    continue
                mismatch = compare_specifiers(source, value)
                if mismatch:
                    findings.append(Finding(name, key, label, mismatch, "placeholder"))

    return findings


def verify_cross_catalog(config: dict, enforced: list[str]) -> list[Finding]:
    """同じキーの訳が複数の .xcstrings で食い違っていないか。

    `Shared/` の文言は 3 つのターゲットの String Catalog に重複して現れるため、
    片方だけ直して片方が古いままになりやすい。
    """
    # (キー, 言語, カテゴリ) -> {訳: [カタログ名]}
    seen: dict[tuple[str, str, str], dict[str, list[str]]] = collections.defaultdict(lambda: collections.defaultdict(list))
    for path in catalogs():
        # InfoPlist はターゲットごとに意味が違うキー（CFBundleDisplayName など）なので比較しない
        if path.stem == "InfoPlist":
            continue
        name = str(path.relative_to(ROOT))
        data = json.loads(path.read_text())
        for key, entry in data.get("strings", {}).items():
            for language, localization in entry.get("localizations", {}).items():
                if language not in enforced:
                    continue
                for category, _, value in units_of(localization):
                    if not value:
                        continue
                    seen[(key, language, category)][value].append(name)

    findings: list[Finding] = []
    for (key, language, category), values in sorted(seen.items()):
        if len(values) <= 1:
            continue
        label = f"{language}/{category}" if category else language
        detail = " / ".join(f"{value!r} ({', '.join(names)})" for value, names in sorted(values.items()))
        findings.append(Finding("(複数のカタログ)", key, label, f"訳が食い違っています: {detail}", "cross"))
    return findings


def verify_config(config: dict) -> list[Finding]:
    findings: list[Finding] = []
    languages = config["languages"]
    enforced = config["enforced"]

    unknown = [language for language in enforced if language not in languages]
    if unknown:
        findings.append(Finding(str(CONFIG.relative_to(ROOT)), "enforced", "", f"languages に無い言語が指定されています: {unknown}", "config"))

    if config["sourceLanguage"] not in languages:
        findings.append(Finding(str(CONFIG.relative_to(ROOT)), "sourceLanguage", "", "languages に含まれていません", "config"))

    missing_rules = [language for language in languages if language not in REQUIRED_PLURAL_CATEGORIES]
    if missing_rules:
        findings.append(
            Finding(
                "Tools/verify_localizations.py", "REQUIRED_PLURAL_CATEGORIES", "",
                f"複数形の必須カテゴリが定義されていない言語があります: {missing_rules}", "config",
            )
        )

    # project.yml の developmentLanguage と揃っているか（簡易パース）
    match = re.search(r"^\s*developmentLanguage:\s*(\S+)\s*$", PROJECT_YML.read_text(), re.MULTILINE)
    if not match:
        findings.append(Finding("project.yml", "developmentLanguage", "", "見つかりません", "config"))
    elif match.group(1) != config["sourceLanguage"]:
        findings.append(
            Finding("project.yml", "developmentLanguage", "",
                    f"{match.group(1)!r} ですが supported-languages.json の sourceLanguage は {config['sourceLanguage']!r} です", "config")
        )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--languages", help="検証する言語をカンマ区切りで指定（既定は enforced）")
    args = parser.parse_args()

    config = load_config()
    enforced = args.languages.split(",") if args.languages else config["enforced"]

    findings = verify_config(config)
    files = catalogs()
    for path in files:
        findings.extend(verify_catalog(path, config, enforced))
    findings.extend(verify_cross_catalog(config, enforced))

    pending = [language for language in config["languages"] if language not in enforced]

    print(f"検証: {len(files)} ファイル / 対象言語 {len(enforced)} ({', '.join(enforced)})")
    if pending:
        print(f"未強制の言語 {len(pending)} ({', '.join(pending)}) — 訳を入れたら supported-languages.json の enforced に追加する")

    if not findings:
        print("\n翻訳の欠損はありません。")
        return 0

    print(f"\n{len(findings)} 件の問題:\n")
    for finding in findings:
        print(" -", finding)

    print("\n内訳:")
    by_kind = collections.Counter(finding.kind for finding in findings)
    labels = {
        "missing": "訳の欠損", "state": "未翻訳・レビュー待ち", "placeholder": "プレースホルダ不整合",
        "plural": "複数形の欠損", "stale": "stale なキー", "cross": "カタログ間の不一致", "config": "設定のずれ",
    }
    for kind, count in by_kind.most_common():
        print(f"  {labels.get(kind, kind)}: {count}")
    by_language = collections.Counter(finding.language.split("/")[0] for finding in findings if finding.language)
    if by_language:
        print("  言語別:", ", ".join(f"{language} {count}" for language, count in by_language.most_common()))
    return 1


if __name__ == "__main__":
    sys.exit(main())
