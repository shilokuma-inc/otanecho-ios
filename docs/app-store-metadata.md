# App Store のメタデータ

説明文・キーワード・サポート URL を、対応している全言語ぶん App Store Connect に反映するまでを
自動化している。GitHub Actions の
[`Metadata/App Store`](../.github/workflows/app-store-metadata.yml) を **手動で** 実行する。

スクリーンショットは別の仕組み（[app-store-screenshots.md](app-store-screenshots.md)）。
撮影が要らないぶん、こちらは数十秒で終わる。

## 元ネタ

`Localization/app-store-metadata/` が正。

```
Localization/app-store-metadata/
├── shared.json      言語によらない値（supportUrl）
├── en.json          description / keywords
├── ja.json
└── …                supported-languages.json の languages ぶん
```

`keywords` は配列で書く。App Store Connect にはカンマ区切りの 1 本の文字列として渡すので、
**区切りのあとに空白を入れない**（そのぶん 100 字の枠を食う）。

| 項目 | 上限 |
|---|---|
| `description` | 4000 字 |
| `keywords`（カンマ区切りで繋いだ全体） | 100 字 |

欠損と上限超過は `Verify/localizations`（PR ごとに走る）が落とす。手元でも確認できる。

```bash
python3 Tools/upload_metadata.py --check
```

## 使い方

Actions タブ → `Metadata/App Store` → `Run workflow`。

| 入力 | 既定 | 意味 |
|---|---|---|
| `languages` | 空（全言語） | 反映する言語をカンマ区切りで絞る。例: `ja,en` |
| `app_version` | 空 | 反映先のバージョン。空なら編集できるものを自動で選ぶ |
| `missing_locales` | `create` | その言語が App Store Connect に無いときの扱い。`create` は追加してから反映 |
| `dry_run` | オフ | 書き込まず、やることだけ出す |

まず `dry_run` を入れて回し、対象バージョンと言語を確かめてから本番で流すのが安全。

## 触らないもの

- **アプリ名・サブタイトル**: `appInfoLocalizations` という別リソースにぶら下がっているため、
  このワークフローの対象外。App Store Connect で設定する。
- **プロモーションテキスト・マーケティング URL・新機能**: 同じ `appStoreVersionLocalizations` の
  属性なので足すのは簡単だが、いまは使っていないので入れていない。
- **審査中・配信済みのバージョン**: `Tools/app_store_connect.py` の `EDITABLE_STATES` に
  入っている状態のバージョンしか触らない。

## サポート URL

`shared.json` の `supportUrl` は Apple の審査で実際に開かれるので、必ず到達できる URL にすること。
いまは公開リポジトリの Issues を指している。専用のサポートページを用意したら差し替える
（組織の慣例では `https://shilokuma-inc.github.io/iOS-Release-Sample/` 配下）。
