import Foundation

/// 別プロセス（App Intent・ウィジェット・コントロールセンター）から「アプリを開いて画面を出したい」要求を
/// アプリ本体へ受け渡すための保留キュー。App Group の UserDefaults に 1 件だけ保持する。
///
/// 使い方:
/// - 要求側: `PendingCaptureStore.shared.request(.capture(text: nil))` を呼んでからアプリを開く
/// - アプリ側: `scenePhase == .active` になったタイミングで `PendingCaptureStore.shared.take()` を呼び、
///   返ってきた `DeepLink` を `AppRouter.handle(_:)` に渡す
nonisolated struct PendingCaptureStore: Sendable {
    static let shared = PendingCaptureStore(suiteName: AppGroup.identifier)

    /// これより古い要求は無視する（秒）
    static let maxAge: TimeInterval = 60

    private let suiteName: String?
    private let urlKey = "pendingCapture.url"
    private let requestedAtKey = "pendingCapture.requestedAt"

    init(suiteName: String?) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// アプリが前面に来たときに処理してほしい要求を登録する。既存の要求は上書きする。
    func request(_ link: DeepLink) {
        let defaults = defaults
        defaults.set(link.url.absoluteString, forKey: urlKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: requestedAtKey)
    }

    /// 保留中の要求を取り出し、ストアから消す。要求がない・解釈できない・古すぎる場合は nil。
    func take() -> DeepLink? {
        let defaults = defaults
        defer { clear() }

        guard
            let raw = defaults.string(forKey: urlKey),
            let url = URL(string: raw),
            let link = DeepLink(url: url)
        else { return nil }

        let requestedAt = defaults.double(forKey: requestedAtKey)
        guard Date.now.timeIntervalSince1970 - requestedAt <= Self.maxAge else { return nil }
        return link
    }

    /// 保留中の要求を破棄する。
    func clear() {
        let defaults = defaults
        defaults.removeObject(forKey: urlKey)
        defaults.removeObject(forKey: requestedAtKey)
    }
}
