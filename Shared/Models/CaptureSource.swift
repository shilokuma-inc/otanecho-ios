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

    var label: LocalizedStringResource {
        switch self {
        case .app: "App"
        case .actionButton: "Action Button"
        case .controlCenter: "Control Center"
        case .lockScreenWidget: "Lock Screen"
        case .homeWidget: "Widget"
        case .shareExtension: "Share"
        case .siri: "Siri"
        case .voice: "Voice"
        case .deepLink: "Link"
        }
    }
}
