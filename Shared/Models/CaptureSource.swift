import Foundation

/// どの入り口からアイデアが書き留められたか。
nonisolated enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case app
    case actionButton
    case controlCenter
    case lockScreenWidget
    case homeWidget
    case shareExtension
    case siri
    case voice
    case deepLink

    var label: String {
        switch self {
        case .app: "アプリ"
        case .actionButton: "アクションボタン"
        case .controlCenter: "コントロールセンター"
        case .lockScreenWidget: "ロック画面"
        case .homeWidget: "ウィジェット"
        case .shareExtension: "共有"
        case .siri: "Siri"
        case .voice: "音声"
        case .deepLink: "リンク"
        }
    }
}
