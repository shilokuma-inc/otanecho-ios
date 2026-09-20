import AppIntents
import Foundation

/// 「種をまく」: アプリを開いて入力画面を即時に表示する。
/// アクションボタン・コントロールセンター・ショートカット・Siri から呼ばれる。
/// 別プロセスで実行されるため、画面表示の要求は `PendingCaptureStore` 経由でアプリ本体に渡す。
nonisolated struct CaptureSeedIntent: AppIntent {
    static let title: LocalizedStringResource = "種をまく"
    static let description = IntentDescription("お種帳を開いて、思いついたことをすぐ書き留めます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingCaptureStore.shared.request(.capture(text: nil))
        return .result()
    }
}
