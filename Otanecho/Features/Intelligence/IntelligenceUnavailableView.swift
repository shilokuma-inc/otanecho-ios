import SwiftUI
import UIKit

/// AI が使えないときに、深掘りのテンプレートの問いの下へ添える控えめな案内。
/// 「AI が使えると、この種に沿った問いが出せる」ことだけを 1〜2 行で伝える（判断基準 2・4）。
/// 設定で直せるなら設定アプリへ、端末そのものが非対応なら対応端末の一覧へ導線を出す。
struct IntelligenceUnavailableView: View {
    let availability: IntelligenceAvailability
    @Environment(\.openURL) private var openURL
    @State private var isShowingSupportedDevices = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .font(.footnote)
            .buttonStyle(.borderless)
    }

    private var message: LocalizedStringResource {
        switch availability {
        case .available, .unknown:
            "Questions tailored to this seed aren't available right now."
        case .deviceNotEligible:
            "On a device with Apple Intelligence, you'd also get questions tailored to this seed."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence & Siri in Settings to also get questions tailored to this seed."
        case .modelNotReady:
            "The model is still getting ready. Once it is, you'll also get questions tailored to this seed."
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
