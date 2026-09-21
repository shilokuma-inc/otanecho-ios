import Foundation
import Observation

/// 画面遷移の状態。ディープリンク・App Intent・UI から共通で操作する。
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case capture(prefill: String?, source: CaptureSource)
        case weeklyReview

        var id: String {
            switch self {
            case .capture: "capture"
            case .weeklyReview: "weeklyReview"
            }
        }
    }

    /// NavigationStack のパス（種の ID を積む）
    var path: [UUID] = []
    var sheet: Sheet?
    /// チュートリアルを出しているか。初回起動時のほか、後から見返す導線もここを立てる。
    var isShowingTutorial = false

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

    /// チュートリアルを出す。初回起動かどうかの判定は OnboardingTracker が持つ。
    func showTutorial() {
        isShowingTutorial = true
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
