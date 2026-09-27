import Foundation
import Observation

/// 画面遷移の状態。ディープリンク・App Intent・UI から共通で操作する。
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case capture(prefill: String?, source: CaptureSource)
        case weeklyReview
        case settings

        var id: String {
            switch self {
            case .capture: "capture"
            case .weeklyReview: "weeklyReview"
            case .settings: "settings"
            }
        }
    }

    /// NavigationStack のパス（種の ID を積む）
    var path: [UUID] = []
    var sheet: Sheet?
    /// チュートリアルを出しているか。初回起動時のほか、後から見返す導線もここを立てる。
    var isShowingTutorial = false
    /// シートを閉じ終えたらチュートリアルを出す。シートと全画面表示を同時に切り替えると表示が崩れるため、
    /// シートの onDismiss まで待つ。
    var showsTutorialAfterSheetDismissal = false

    func showCapture(prefill: String? = nil, source: CaptureSource = .app) {
        sheet = .capture(prefill: prefill, source: source)
    }

    func showSeed(id: UUID) {
        sheet = nil
        path = [id]
    }

    func showWeeklyReview() {
        sheet = .weeklyReview
    }

    func showSettings() {
        sheet = .settings
    }

    /// チュートリアルを出す。初回起動かどうかの判定は OnboardingTracker が持つ。
    func showTutorial() {
        isShowingTutorial = true
    }

    /// 設定画面からチュートリアルを見返す。シートを閉じてから出す。
    func replayTutorial() {
        guard sheet != nil else {
            showTutorial()
            return
        }
        showsTutorialAfterSheetDismissal = true
        sheet = nil
    }

    /// シートが閉じ終わったときに RootView から呼ぶ。
    func sheetDidDismiss() {
        guard showsTutorialAfterSheetDismissal else { return }
        showsTutorialAfterSheetDismissal = false
        showTutorial()
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .capture(let text):
            showCapture(prefill: text, source: .deepLink)
        case .seed(let id):
            showSeed(id: id)
        case .review:
            showWeeklyReview()
        }
    }
}
