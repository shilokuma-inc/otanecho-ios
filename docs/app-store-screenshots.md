# App Store 用スクリーンショット

対応している全言語ぶんのスクリーンショットを撮り、App Store Connect に反映するまでを自動化している。
GitHub Actions の [`Screenshots/App Store`](../.github/workflows/screenshots.yml) を **手動で** 実行する。

## 使い方

Actions タブ → `Screenshots/App Store` → `Run workflow`。

| 入力 | 既定 | 意味 |
|---|---|---|
| `languages` | 空（全言語） | 撮る言語をカンマ区切りで絞る。例: `ja,en` |
| `device` | `iPhone 11 Pro Max` | 撮影に使うシミュレータの機種 |
| `display_type` | `APP_IPHONE_65` | App Store Connect の表示サイズ |
| `expected_size` | `1242x2688` | この寸法でなければ落とす。`none` で確認しない |
| `app_version` | 空 | 反映先のバージョン。空なら編集できるものを自動で選ぶ |
| `upload` | オン | 外すと撮るだけ。結果は artifact から取れる |
| `missing_locales` | `create` | App Store Connect にその言語が無いときの扱い。`create` はその言語を追加してから反映、`skip` は飛ばす、`fail` は止める |

まず `upload` を外して回し、artifact の中身を見てから本番で流すのが安全。

`missing_locales` が `create` のとき、App Store Connect にまだ無い言語はこちらで追加する。
スクリーンショットの置き場所は言語ごとにしかないため、先に言語が無いと反映できないため。
ただし説明文やキーワードは空のまま作られるので、審査に出す前に App Store Connect で埋めること。

説明文・キーワード・サポート URL は別のワークフローが受け持つ。
[app-store-metadata.md](app-store-metadata.md) を参照。

## 撮る流れ

```
supported-languages.json ─┬→ 言語の一覧
                          └→ 言語ごとの testLanguage / testRegion / storeLocale

xcodebuild build-for-testing        1 回だけビルド
  └ xcodebuild test-without-building  言語ぶん繰り返す（-testLanguage を差し替え）
      └ ScreenshotUITests            画面ごとにアプリを起動し直して 5 枚撮る
          └ .xcresult                XCTAttachment として残る
              └ extract_screenshots.py  build/screenshots/<言語>/01_*.png …
                  └ upload_screenshots.py  App Store Connect へ
```

## 撮っている画面

| ファイル | 画面 |
|---|---|
| `01_timeline.png` | タイムライン（種・芽・木が 1 つずつ並ぶ） |
| `02_capture.png` | 入力（本文が入り、キーボードが上がった状態） |
| `03_detail.png` | 詳細（深掘りの問答が並んだ「木」の種） |
| `04_review.png` | 週次レビュー |
| `05_tutorial.png` | 初回起動のチュートリアル |

並び順はファイル名の順がそのまま App Store の並び順になる。

## 仕組みの要点

### 画面はタップで辿らず、起動時に指定する

12 言語ぶん撮るのに、表示されている文言を頼りに画面を辿ることはできない。
`ScreenshotUITests` は画面ごとにアプリを起動し直し、`OTANECHO_SCREENSHOT_ROUTE` に
`otanecho://` のディープリンクを渡して、最初から目的の画面を開かせている。
画面が出たことの確認だけは、翻訳されないアクセシビリティ識別子で行う
（`timeline.captureButton` など）。

### 撮影中は AI を切っている

Foundation Models はシミュレータでは動かない。実行時の判定に任せると
「使えると返ってから失敗するまでの間だけスピナーが写る」ような揺れが出るため、
撮影中は最初から使えないことにしている（`ScreenshotSeeder.intelligence`）。
週次レビューの AI ダイジェストは、そのためスクリーンショットには写らない。

### デモデータは UI テストが持つ

写っている種は [`OtanechoUITests/Resources/screenshot-content.json`](../OtanechoUITests/Resources/screenshot-content.json) の作例。
アプリ側に持たせていないのは、12 言語ぶんの文言を String Catalog の検証対象にしたくないため。
受け取り口（`Otanecho/Core/Screenshots/ScreenshotSeeder.swift`）は `#if DEBUG` で囲ってあり、
Release ビルドには入らない。

言語に依らない部分（種の ID・並び順・書かれた時刻）は `OtanechoUITests/ScreenshotContent.swift` の
`layout` が持ち、JSON は文言だけにしてある。翻訳の差分が読みやすいようにするため。

> この作例は機械翻訳ではなく書き下ろしているが、ネイティブのレビューは通していない。
> 実際にストアへ出す前に一度目を通すのが望ましい。

### 反映先

- 触るのは **編集できる状態のバージョンだけ**（`PREPARE_FOR_SUBMISSION` など）。
  審査中・配信済みのバージョンには触らない。
- 言語ごとに、その表示サイズの既存のスクリーンショットセットを **削除してから入れ直す**。
  App Store Connect は 1 つの言語・表示サイズにつきセットを 1 つしか持てないため、
  差し替えはこうするしかない。編集中のバージョンなので、公開中のストア表示には影響しない。
- App Store Connect 側にその言語（ロケール）が無ければ既定で止まる。
  ストアの言語は説明文やキーワードも一緒に要るので、ここで勝手に作らない。
  足りない言語は書き込みを始める前にまとめて出る（1 言語ずつ落ちて撮り直すことにならないように）。

## 言語を足すとき

[`Localization/supported-languages.json`](../Localization/supported-languages.json) に足すのが起点。

1. `languages` / `enforced` に言語を足す（通常のローカライズ対応。[Localization/README.md](../Localization/README.md)）
2. 同じファイルの `appStore` に `testLanguage` / `testRegion` / `storeLocale` を足す
   - `storeLocale` は App Store Connect のロケール。アプリの言語コードとは別物（`en` → `en-US` など）
3. `OtanechoUITests/Resources/screenshot-content.json` にその言語の作例を足す
4. App Store Connect 側にもその言語を追加しておく

2 と 3 を忘れた場合はワークフローがその場で落ちる（黙って英語のまま上がることはない）。

## 手元で試す

```bash
xcodegen generate

xcodebuild build-for-testing -project Otanecho.xcodeproj -scheme Otanecho \
  -destination 'platform=iOS Simulator,name=iPhone 11 Pro Max' \
  -derivedDataPath build/DerivedData

xcodebuild test-without-building -project Otanecho.xcodeproj -scheme Otanecho \
  -destination 'platform=iOS Simulator,name=iPhone 11 Pro Max' \
  -derivedDataPath build/DerivedData \
  -only-testing:OtanechoUITests/ScreenshotUITests \
  -testLanguage ja -testRegion JP \
  -resultBundlePath build/results/ja.xcresult

python3 Tools/extract_screenshots.py \
  --xcresult build/results/ja.xcresult --language ja --output-dir build/screenshots
```

App Store Connect への反映まで試すなら、API Key（`.p8`）を用意して:

```bash
python3 -m pip install pyjwt cryptography

APP_STORE_CONNECT_KEY_ID=XXXXXXXXXX \
APP_STORE_CONNECT_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
APP_STORE_CONNECT_PRIVATE_KEY_PATH=./AuthKey_XXXXXXXXXX.p8 \
python3 Tools/upload_screenshots.py \
  --screenshots-dir build/screenshots \
  --bundle-id jp.shilokuma.Otanecho \
  --languages ja \
  --dry-run
```

## 使っているシークレット

既存の配信ワークフローと同じものを使い回している。

| シークレット | 用途 |
|---|---|
| `APPLE_API_KEY_BASE64` | App Store Connect API Key（`.p8`）を base64 にしたもの |
| `APPLE_API_KEY_ID` | Key ID |
| `APPLE_API_ISSUER_ID` | Issuer ID |
