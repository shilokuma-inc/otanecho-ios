import Foundation

/// アプリ本体・ウィジェット・共有拡張で共通に使う識別子。
nonisolated enum AppGroup {
    /// App Groups の識別子。project.yml の entitlements と一致させる。
    static let identifier = "group.ml.mrs1669.Otanecho"

    /// App Group 共有コンテナ。取得できない環境（未署名など）では Application Support にフォールバックする。
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.applicationSupportDirectory
    }
}

/// otanecho:// で受け付けるディープリンク。
nonisolated enum DeepLink: Equatable, Sendable {
    static let scheme = "otanecho"

    /// 入力画面を即時に開く。text があれば本文に流し込む。
    case capture(text: String?)
    /// 指定した種の詳細を開く。
    case seed(id: UUID)
    /// 週次レビューを開く。
    case review

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "capture":
            self = .capture(text: items.first { $0.name == "text" }?.value)
        case "seed":
            guard let raw = items.first(where: { $0.name == "id" })?.value, let id = UUID(uuidString: raw) else { return nil }
            self = .seed(id: id)
        case "review":
            self = .review
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .capture(let text):
            components.host = "capture"
            if let text, !text.isEmpty { components.queryItems = [URLQueryItem(name: "text", value: text)] }
        case .seed(let id):
            components.host = "seed"
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        case .review:
            components.host = "review"
        }
        return components.url!
    }
}
