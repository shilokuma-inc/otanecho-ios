import SwiftUI
import UIKit

/// AI が使えない理由を 1〜2 行で静かに伝える。必要なら設定アプリへの導線を出す。
struct IntelligenceUnavailableView: View {
    let availability: IntelligenceAvailability
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "leaf")
                    .foregroundStyle(.tertiary)
            }
            if availability == .appleIntelligenceNotEnabled,
               let url = URL(string: UIApplication.openSettingsURLString) {
                Button("設定を開く") { openURL(url) }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var message: String {
        switch availability {
        case .available:
            "いまは問いを作れません。しばらくしてからお試しください。"
        case .deviceNotEligible:
            "この機能は Apple Intelligence 対応の iPhone で利用できます。"
        case .appleIntelligenceNotEnabled:
            "設定 > Apple Intelligence と Siri でオンにすると、この種への問いを受け取れます。"
        case .modelNotReady:
            "モデルの準備中です。しばらくしてからお試しください。"
        case .unknown:
            "いまは問いを作れません。しばらくしてからお試しください。"
        }
    }
}

#Preview("未有効") {
    IntelligenceUnavailableView(availability: .appleIntelligenceNotEnabled)
        .padding()
}

#Preview("非対応端末") {
    IntelligenceUnavailableView(availability: .deviceNotEligible)
        .padding()
}
