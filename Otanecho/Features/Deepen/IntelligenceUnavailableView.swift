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
                Button("Open Settings") { openURL(url) }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var message: LocalizedStringResource {
        switch availability {
        case .available:
            "Questions aren't available right now. Please try again later."
        case .deviceNotEligible:
            "This feature is available on iPhone models that support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence & Siri in Settings to receive questions for this seed."
        case .modelNotReady:
            "The model is still getting ready. Please try again later."
        case .unknown:
            "Questions aren't available right now. Please try again later."
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
