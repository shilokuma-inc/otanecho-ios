import AppIntents
import Foundation

/// 「種をまく」: アプリを開いて入力画面を即時に表示する。
/// アクションボタン・コントロールセンター・ショートカット・Siri から呼ばれる。
/// 別プロセスで実行されるため、画面表示の要求は `PendingCaptureStore` 経由でアプリ本体に渡す。
nonisolated struct CaptureSeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Plant a Seed"
    static let description = IntentDescription("Opens Otanecho so you can jot down what just came to mind.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingCaptureStore.shared.request(.capture(text: nil))
        return .result()
    }
}
