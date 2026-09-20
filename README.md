# お種帳（Otanecho）

ふと思いついたアイデアを **1 秒で書き留め**、あとから **オンデバイス AI（Apple Foundation Models）で育てる** iOS アプリ。

- 入力の速さを最優先。保存ボタンはなく、書いた瞬間に自動保存。
- AI は「黙って裏方」。タグ付け・タイトル生成は自動、深掘り（芽を出す）と週次レビューは使いたいときだけ。
- すべてデバイス上で処理。非対応端末でもメモアプリとして完全に成立する。

コンセプト・市場分析・ビジネスモデルは [docs/concept.md](docs/concept.md) を参照。

## 環境

- Xcode 26 以降（開発時は Xcode 27.0 beta）
- iOS 26.0 以降（AI 機能は Apple Intelligence 対応端末のみ）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## セットアップ

`Otanecho.xcodeproj` は Git 管理外で、`project.yml` から生成します。

```bash
xcodegen generate
open Otanecho.xcodeproj
```

コマンドラインでビルド・テスト:

```bash
xcodebuild build -project Otanecho.xcodeproj -scheme Otanecho \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation
```

```bash
xcodebuild test -project Otanecho.xcodeproj -scheme Otanecho \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -only-testing:OtanechoTests
```

## 構成

| パス | 内容 |
|---|---|
| `Otanecho/` | アプリ本体（SwiftUI） |
| `Otanecho/Features/` | 画面ごとの実装（Capture / Timeline / Deepen / Review / Voice / Shortcuts） |
| `Otanecho/Core/AI/` | `IdeaIntelligence` プロトコルと Foundation Models 実装 |
| `Shared/` | アプリ・ウィジェット・共有拡張で共用するモデル、永続化、App Intents |
| `OtanechoWidgets/` | コントロールセンター・ロック画面・ホーム画面ウィジェット |
| `OtanechoShare/` | 共有拡張（他アプリから「お種帳に保存」） |
| `project.yml` | XcodeGen 定義（ターゲット、Info.plist、entitlements） |

## Status

<div style="margin:0px;padding:0px;">
  <table width="98%" style="border-collapse: collapse;border:2px double #000080;text-align:center;margin:auto;">
    <tbody>
      <tr>
        <td style="border:2px double #000080;">branch \ workflow</td>
        <td style="border:2px double #000080;">Build</td>
        <td style="border:2px double #000080;">Archive</td>
        <td style="border:2px double #000080;">Upload</td>
      </tr>
      <tr>
        <td style="border:2px double #000080;text-align:left;">main</td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/build-main.yml">
            <img src="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/build-main.yml/badge.svg" alt="Build">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/archive-main.yml">
            <img src="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/archive-main.yml/badge.svg" alt="Archive">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;"></td>
      </tr>
      <tr>
        <td style="border:2px double #000080;text-align:left;">develop</td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/build-develop.yml">
            <img src="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/build-develop.yml/badge.svg" alt="Build">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/archive-develop.yml">
            <img src="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/archive-develop.yml/badge.svg" alt="Archive">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/upload-develop.yml">
            <img src="https://github.com/shilokuma-inc/otanecho-ios/actions/workflows/upload-develop.yml/badge.svg" alt="Upload">
          </a>
        </td>
      </tr>
    </tbody>
  </table>
</div>
