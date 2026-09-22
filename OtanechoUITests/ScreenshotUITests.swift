import XCTest

/// App Store Connect に載せるスクリーンショットを撮る。
///
/// 画面ごとにアプリを起動し直し、起動時の環境変数で「デモデータ」と「最初に開く画面」を渡す。
/// タップで辿らないのは、12 言語ぶん撮るのに表示文言を頼りにできないため。
/// 画面が出たことの確認だけはアクセシビリティ識別子で行う（これは翻訳されない）。
///
/// 撮った画像は `.xcresult` に添付として残る。取り出しは `Tools/extract_screenshots.py`。
///
/// 実行のしかた:
///
/// ```
/// xcodebuild test -scheme Otanecho \
///   -destination 'platform=iOS Simulator,name=iPhone 11 Pro Max' \
///   -only-testing:OtanechoUITests/ScreenshotUITests \
///   -testLanguage ja -testRegion JP
/// ```
final class ScreenshotUITests: XCTestCase {
    /// 画面が出るまで待つ上限。CI のシミュレータは初回起動が遅い。
    private static let appearanceTimeout: TimeInterval = 30
    /// 画面が出てから撮るまでの待ち。シートやプッシュのアニメーションが終わるのを待つ。
    private static let settleDuration: TimeInterval = 1.5

    /// 撮影する言語。`xcodebuild -testLanguage` はアプリだけでなくこのテストランナーにも効くので、
    /// 自分のロケールを見れば「いま何語で撮っているか」が分かる。
    /// 環境変数で渡す手もあるが、`TEST_RUNNER_` 付きのビルド設定はランナーまで届かなかった。
    private var language: String {
        Locale.preferredLanguages.first ?? "en"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let content = try ScreenshotContent.load(language: language)

        let app = XCUIApplication()

        // 01 タイムライン
        launch(app, content: content, route: nil)
        waitForScreen(app.buttons["timeline.captureButton"], name: "タイムライン")
        snapshot("01_timeline")

        // 02 入力（思いついたことが書かれた状態で開く）
        launch(app, content: content, route: captureRoute(text: content.captureText))
        waitForScreen(app.textViews["capture.editor"], name: "入力")
        snapshot("02_capture")

        // 03 詳細（深掘りの問答が並んだ状態）
        launch(app, content: content, route: seedRoute(id: ScreenshotContent.featuredSeedID))
        waitForScreen(app.buttons["seedDetail.growButton"], name: "詳細")
        snapshot("03_detail")

        // 04 週次レビュー
        launch(app, content: content, route: reviewRoute())
        waitForScreen(app.descendants(matching: .any)["weeklyReview.list"], name: "週次レビュー")
        snapshot("04_review")

        // 05 チュートリアル（初回起動の扱いにするので、見せ終わった記録を渡さない）
        launch(app, content: content, route: nil, showsTutorial: true)
        waitForScreen(app.buttons["onboarding.skipButton"], name: "チュートリアル")
        snapshot("05_tutorial")
    }

    // MARK: - 起動

    @MainActor
    private func launch(
        _ app: XCUIApplication,
        content: ScreenshotContent,
        route: URL?,
        showsTutorial: Bool = false
    ) {
        // UserDefaults は起動引数で上書きできる（NSArgumentDomain）。この指定は保存されないので、
        // 最後にチュートリアルを撮るときに渡さなければ、初回起動として出てくれる。
        app.launchArguments = showsTutorial ? [] : ["-onboarding.completedVersion", "1"]
        app.launchEnvironment["OTANECHO_SCREENSHOT_CONTENT"] = content.payload
        app.launchEnvironment["OTANECHO_SCREENSHOT_ROUTE"] = route?.absoluteString
        app.launch()
    }

    // MARK: - 最初に開く画面（otanecho:// のディープリンク）

    private func captureRoute(text: String) -> URL {
        route(host: "capture", queryItems: [URLQueryItem(name: "text", value: text)])
    }

    private func seedRoute(id: String) -> URL {
        route(host: "seed", queryItems: [URLQueryItem(name: "id", value: id)])
    }

    private func reviewRoute() -> URL {
        route(host: "review", queryItems: [])
    }

    private func route(host: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "otanecho"
        components.host = host
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            preconditionFailure("遷移先の URL を組み立てられなかった: \(host)")
        }
        return url
    }

    // MARK: - 撮影

    @MainActor
    private func waitForScreen(_ element: XCUIElement, name: String) {
        XCTAssertTrue(
            element.waitForExistence(timeout: Self.appearanceTimeout),
            "\(name)（\(language)）が出てこなかった"
        )
        Thread.sleep(forTimeInterval: Self.settleDuration)
    }

    @MainActor
    private func snapshot(_ name: String) {
        // アプリの窓ではなく画面全体を撮る。App Store は上端のステータスバーまで含んだ寸法を要求する。
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
