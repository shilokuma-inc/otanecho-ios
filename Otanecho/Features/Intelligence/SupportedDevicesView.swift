import SwiftUI

/// Apple Intelligence に対応する端末を一覧で示すシート。
/// 非対応端末で AI 機能を出せないときに、「どの端末なら使えるのか」を具体的に伝える。
struct SupportedDevicesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    intro
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))

                ForEach(SupportedIntelligenceDevices.families) { family in
                    Section {
                        ForEach(Array(family.generations.enumerated()), id: \.offset) { _, generation in
                            Text(generation)
                        }
                    } header: {
                        Label {
                            Text(verbatim: family.name)
                        } icon: {
                            Image(systemName: family.symbolName)
                        }
                    }
                }

                Section {
                    Link(destination: SupportedIntelligenceDevices.learnMoreURL) {
                        Label("See the full list on apple.com", systemImage: "safari")
                    }
                } footer: {
                    Text("Apple Intelligence also has to be turned on in Settings, and it's offered in a limited set of languages and regions.")
                }
            }
            .navigationTitle("Devices that support AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The AI runs entirely on your device, so the AI features need a device that supports Apple Intelligence.")
                .font(.subheadline)
            Text("You can jot down, search, and look back on your seeds on any device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SupportedDevicesView()
}
