import SwiftUI

/// マイクボタン。タップで録音を開始し（アイコンが波形アニメーションに変わる）、再タップで停止する。
/// 確定した文字起こしだけを `text` の末尾に追記し、途中結果はボタンの隣に薄く表示する。
struct VoiceInputButton: View {
    @Binding private var text: String
    @State private var transcriber = VoiceTranscriber()

    init(text: Binding<String>) {
        _text = text
    }

    private var isDisabled: Bool {
        transcriber.permission == .denied || transcriber.isPreparing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    transcriber.onFinalText = { [$text] segment in
                        $text.wrappedValue.append(segment)
                    }
                    Task { await transcriber.toggle() }
                } label: {
                    icon
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel(transcriber.isRecording ? "Stop voice input" : "Start voice input")

                statusText
            }

            if transcriber.permission == .denied {
                Text("Allow microphone and speech recognition in Settings to write by speaking.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = transcriber.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .task { transcriber.refreshPermission() }
        .onDisappear {
            Task { await transcriber.stop() }
        }
    }

    private var icon: some View {
        Image(systemName: transcriber.isRecording ? "waveform" : "mic.fill")
            .font(.title3)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: transcriber.isRecording)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(transcriber.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            .frame(width: 40, height: 40)
            .background(.fill.tertiary, in: .circle)
            .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var statusText: some View {
        if transcriber.isPreparing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Getting ready…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if transcriber.isRecording {
            Text(transcriber.volatileText.isEmpty ? String(localized: "Listening…") : transcriber.volatileText)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .animation(.default, value: transcriber.volatileText)
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack(alignment: .leading, spacing: 16) {
        TextEditor(text: $text)
            .frame(height: 160)
            .padding(8)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        VoiceInputButton(text: $text)
    }
    .padding()
}
