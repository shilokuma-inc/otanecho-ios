import XCTest

/// 入力 → 自動保存 → 一覧 → 詳細 → 芽を出す → 週次レビュー の一連の流れを通すスモークテスト。
/// 各画面のスクリーンショットを添付として残す（xcresult から取り出して確認する用途）。
final class CaptureFlowUITests: XCTestCase {
    @MainActor
    func testCaptureToDeepenFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // openurl 由来のシステムダイアログが残っていたら閉じる
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Cancel"].waitForExistence(timeout: 2) {
            springboard.buttons["Cancel"].tap()
        }

        snapshot(app, "01_timeline")

        // 1. 「+」から入力画面へ
        let fab = app.buttons["新しい種をまく"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        fab.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        snapshot(app, "02_capture_empty")

        // 2. 入力すると保存ボタン無しで自動保存される（キーボード上に「芽を出す」が現れる）
        editor.typeText("Podcast memo app: take notes one-handed while listening on the train, then review only the key points later.")
        let deepenFromCapture = app.buttons["芽を出す"]
        XCTAssertTrue(deepenFromCapture.waitForExistence(timeout: 5), "自動保存後にキーボードツールバーへ「芽を出す」が出るはず")
        snapshot(app, "03_capture_typed")

        // 3. 閉じると一覧に出る
        app.buttons["閉じる"].firstMatch.tap()
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Podcast")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        snapshot(app, "04_timeline_saved")

        // 4. AI のタグ付けを待つ（オンデバイスモデル。最大 90 秒）
        let tagged = app.staticTexts.matching(identifier: "tag").firstMatch
        let taggedAppeared = tagged.waitForExistence(timeout: 90)
        snapshot(app, taggedAppeared ? "05_timeline_enriched" : "05_timeline_not_enriched")

        // 5. 詳細へ
        row.tap()
        let deepenButton = app.buttons["芽を出す"]
        XCTAssertTrue(deepenButton.waitForExistence(timeout: 5))
        snapshot(app, "06_detail")

        // 6. 芽を出す（問いの生成を最大 120 秒待つ）
        deepenButton.tap()
        let regenerate = app.buttons["別の問いをもらう"]
        let questionsLoaded = regenerate.waitForExistence(timeout: 120)
        snapshot(app, questionsLoaded ? "07_deepen_questions" : "07_deepen_failed_or_unavailable")

        if questionsLoaded {
            // 最初の問いに答えてみる
            let firstQuestion = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "？")).firstMatch
            if firstQuestion.exists {
                firstQuestion.tap()
                let answerField = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
                if answerField.waitForExistence(timeout: 3) {
                    answerField.tap()
                    answerField.typeText("Commuters who listen to podcasts but forget the key points.")
                    if app.buttons["答える"].waitForExistence(timeout: 3) {
                        app.buttons["答える"].tap()
                        sleep(2)
                        snapshot(app, "08_deepen_answered")
                    }
                }
            }
        }
        app.buttons["閉じる"].firstMatch.tap()
        sleep(1)
        snapshot(app, "09_detail_after_deepen")

        // 7. 週次レビュー
        app.navigationBars.buttons.element(boundBy: 0).tap() // 戻る
        let review = app.buttons["週次レビュー"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        sleep(20)
        snapshot(app, "10_weekly_review")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
