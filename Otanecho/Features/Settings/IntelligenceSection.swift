import SwiftUI
import UIKit

/// 設定画面の Apple Intelligence セクション。
/// AI 機能は使えない端末では静かに消える（判断基準 4）ので、「なぜ出ないのか」をここで確かめられるようにする。
struct IntelligenceSection: View {
    @Environment(\.ideaIntelligence) private var intelligence
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var availability: IntelligenceAvailability = .unknown
    @State private var isShowingSupportedDevices = false

    var body: some View {
        Section {
            LabeledContent("Status") {
                Label(Self.statusText(availability), systemImage: Self.statusSymbol(availability))
                    .foregroundStyle(availability.isAvailable ? .green : .secondary)
            }
            .accessibilityIdentifier("settings.intelligenceStatus")

            if availability == .appleIntelligenceNotEnabled,
               let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
            }

            Button("Devices that support AI") { isShowingSupportedDevices = true }
        } header: {
            Text(verbatim: "Apple Intelligence")
        } footer: {
            Text("Apple Intelligence also has to be turned on in Settings, and it's offered in a limited set of languages and regions.")
        }
        .sheet(isPresented: $isShowingSupportedDevices) {
            SupportedDevicesView()
        }
        .task { refresh() }
        // 設定アプリで有効化して戻ってきたときに状態を取り直す
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        availability = intelligence.availability
    }

    private static func statusText(_ availability: IntelligenceAvailability) -> LocalizedStringResource {
        switch availability {
        case .available: "Available"
        case .appleIntelligenceNotEnabled: "Needs to be turned on in Settings"
        case .deviceNotEligible: "Not supported on this device"
        case .modelNotReady: "Getting ready"
        case .unknown: "Unavailable right now"
        }
    }

    private static func statusSymbol(_ availability: IntelligenceAvailability) -> String {
        switch availability {
        case .available: "checkmark.circle.fill"
        case .appleIntelligenceNotEnabled: "gearshape"
        case .deviceNotEligible: "iphone.slash"
        case .modelNotReady: "hourglass"
        case .unknown: "questionmark.circle"
        }
    }
}

#Preview("利用可") {
    List { IntelligenceSection() }
        .environment(\.ideaIntelligence, FoundationModelsIntelligence())
}

#Preview("非対応端末") {
    List { IntelligenceSection() }
        .environment(\.ideaIntelligence, UnavailableIdeaIntelligence(availability: .deviceNotEligible))
}
