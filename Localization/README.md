# ローカライズ

お種帳は **英語をソース言語** とし、String Catalog（`.xcstrings`）で多言語化する。

## 対応言語

対応言語は [`supported-languages.json`](supported-languages.json) が単一定義。

| キー | 意味 |
|---|---|
| `sourceLanguage` | String Catalog のソース言語。`project.yml` の `options.developmentLanguage` と一致させる |
| `languages` | プロジェクトが対応を宣言する言語。`project.yml` の `options.knownRegions` と一致させる |
| `enforced` | 翻訳の完全性を CI で強制する言語。`languages` の部分集合 |

`enforced` は「訳が入り終わった言語」を並べる枠。新しい言語の訳を投入したらここへ追加する。
これにより、訳の投入が段階的でも CI を常にグリーンに保てる（最終的に `languages` と一致する）。

## String Catalog の配置

ターゲットごとに独立した Bundle を持つため、**ターゲットごとに** String Catalog を置く。

| ターゲット | Localizable | InfoPlist |
|---|---|---|
| Otanecho | `Otanecho/Resources/Localizable.xcstrings` | `Otanecho/Resources/InfoPlist.xcstrings` |
| OtanechoWidgets | `OtanechoWidgets/Localizable.xcstrings` | `OtanechoWidgets/InfoPlist.xcstrings` |
| OtanechoShare | `OtanechoShare/Localizable.xcstrings` | `OtanechoShare/InfoPlist.xcstrings` |

### `Shared/` の文言はどの Bundle から引くか

`Shared/` は 3 つのターゲットに**ソースとして直接コンパイルされる**（フレームワークではない）。
そのため `Shared/` 内の文言は、実行中のターゲット自身の Bundle から解決される:

- アプリ本体で動くときは `Otanecho.app` の String Catalog
- ウィジェット拡張で動くときは `OtanechoWidgets.appex` の String Catalog
- 共有拡張で動くときは `OtanechoShare.appex` の String Catalog

**同じキーが複数のターゲットの String Catalog に重複して現れるのは正常**で、Xcode のビルド時抽出が
ターゲットごとに行うためこうなる。訳を直すときは**重複しているすべてのファイルを直す**必要がある。

`Bundle` を明示せずに `Text("…")` / `LocalizedStringResource("…")` を使えば正しい Bundle が選ばれるので、
`Shared/` の中で `Bundle.main` を明示的に渡したり、独自の Bundle 解決を書いたりしないこと。

## 検証

```bash
python3 Tools/verify_localizations.py
```

PR と `develop` / `main` への push で CI が同じものを回す（`.github/workflows/verify-localizations.yml`）。
JSON を読むだけなので macOS ランナーもビルドもいらない。

見ているのは次の 8 つ。

| 検査 | 内容 |
|---|---|
| 訳の欠損 | `enforced` の言語のエントリが無い |
| 未翻訳 | `state` が `new` |
| レビュー待ち | `state` が `needs_review` |
| プレースホルダ不整合 | `%@` / `%lld` / `%1$@` / `${applicationName}` の数・型・位置引数がソースと食い違う |
| stale なキー | `extractionState` が `stale`（コードから消えたキーの残骸） |
| 複数形の欠損 | その言語に必要な複数形カテゴリが揃っていない |
| カタログ間の不一致 | 同じキーの訳が複数の `.xcstrings` で食い違う |
| 設定のずれ | `sourceLanguage` / `project.yml` の `developmentLanguage` / `enforced` の整合 |

**プレースホルダ不整合を最優先で落としている。** 訳の欠損は英語が出るだけだが、
指定子の数や型が食い違うと実行時にクラッシュしたり無関係な値が表示されたりする。

複数形の必須カテゴリは `Tools/verify_localizations.py` の `REQUIRED_PLURAL_CATEGORIES` に持っている。
言語を追加したらここにも足す（足していないと検証スクリプト自身が落ちて気づける）。

### 日本語のハードコードを防ぐ

`.swiftlint.yml` のカスタムルール `hardcoded_japanese_string` が、
`Text(...)` や `String(localized:)` のように**文言を受け取る API に日本語を直接渡している箇所**を警告する。

「文字列リテラルに日本語があれば違反」にすると、翻訳対象ではないもの（`#Preview` の名前、
プレビュー用のサンプルデータ、開発者向けのログ、`String(localized:)` の `comment`）まで拾ってノイズになるため、
対象を絞っている。`Text(verbatim:)` は意図的に翻訳しない書き方なので検知しない。

## 翻訳を追加・修正するとき

1. ソース文言（英語）はコード側の文字列リテラルがそのままキーになる
2. String Catalog にキーを同期する
   - Xcode.app でビルドすれば自動で同期される
   - コマンドラインで作業しているときは `python3 Tools/sync_string_catalogs.py`
     （`xcodebuild` は `.xcstrings` を更新しないため、`xcrun xcstringstool sync` を代わりに回している）
3. Xcode の String Catalog エディタか `.xcstrings` の直接編集で訳を入れる
4. スクリプトで `.xcstrings` を書き換えたら `python3 Tools/format_string_catalogs.py` で整形を揃える

### `InfoPlist.xcstrings` は手で管理する

`InfoPlist.xcstrings` のキーは Info.plist のキー名で、ソースコードから抽出されない。
`xcstringstool sync` に渡すと「コードに無いキー」と判断されて毎回 `extractionState: "stale"` を付けられるため、
同期スクリプトの対象から外している。Info.plist にキーを足したときは `.xcstrings` にも手で足すこと。

### 整形は Xcode に合わせる

`.xcstrings` は JSON だが、Xcode はキーと値の区切りを `" : "`（コロンの前にも空白）で書き、キーを辞書順に並べる。
スクリプトで編集したまま放置すると、Xcode で開いて保存した瞬間にファイル全体が差分になる。
`Tools/format_string_catalogs.py` で揃えられる（`--check` で確認のみ）。

### 同じ英語・違う訳になるケースに注意

String Catalog のキーはソース文言そのものなので、**英語が同じなら 1 つのエントリに統合される**。
「芽」（成長段階の名前）と「芽を出す」（深掘りを始める操作）はどちらも英語にすると `Sprout` になり、
訳を 1 つしか持てなくなった。段階名を `Sprout`、操作を `Grow` と書き分けて解消している。
同じ英単語で別の訳を当てたくなったら、まず英語側の文言を見直すこと。

### 複数形

件数を含む文言は `variations.plural` で定義する。英語は `one` / `other` を分け、日本語は `other` だけでよい。
`\(count)` をそのまま埋め込んだだけの文言は、英語で "1 questions" のような表示になるため避ける。
