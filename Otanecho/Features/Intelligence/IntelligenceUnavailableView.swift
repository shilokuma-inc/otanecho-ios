import SwiftUI
import UIKit

/// AI が使えない理由を 1〜2 行で静かに伝える。
/// 設定で直せるなら設定アプリへ、端末そのものが非対応なら対応端末の一覧へ導線を出す。
struct IntelligenceUnavailableView: View {
    let availability: IntelligenceAvailability
    @Environment(\.openURL) private var openURL
    @State private var isShowingSupportedDevices = false

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
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $isShowingSupportedDevices) {
            SupportedDevicesView()
        }
    }

    @ViewBuilder
    private var action: some View {
        switch availability {
        case .deviceNotEligible:
            button("See supported devices") { isShowingSupportedDevices = true }
        case .appleIntelligenceNotEnabled:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                button("Open Settings") { openURL(url) }
            }
        case .available, .modelNotReady, .unknown:
            EmptyView()
        }
    }

    private func button(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
    }

    private var message: LocalizedStringResource {
        switch availability {
        case .available:
            "Questions aren't available right now. Please try again later."
        case .deviceNotEligible:
            "This feature needs a device that supports Apple Intelligence."
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
