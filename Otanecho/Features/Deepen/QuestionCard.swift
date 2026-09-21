import SwiftUI

/// 深掘りの問いを 1 枚のカードで表示する。タップで回答欄が開く。
struct QuestionCard: View {
    let question: String
    let intent: String?
    let isExpanded: Bool
    /// カードがタップされたとき（開閉の切り替え）
    let onToggle: () -> Void
    /// 回答が確定されたとき
    let onSubmit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    if let intent, !intent.isEmpty {
                        Text(intent)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.fill.secondary, in: Capsule())
                    }
                    HStack(alignment: .top) {
                        Text(question)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Whatever comes to mind", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .focused($isFocused)
                    HStack {
                        Spacer()
                        Button("Answer") {
                            let text = trimmedDraft
                            guard !text.isEmpty else { return }
                            draft = ""
                            isFocused = false
                            onSubmit(text)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(trimmedDraft.isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear { isFocused = true }
            }
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: isExpanded)
    }
}

#Preview {
    @Previewable @State var expanded = true
    VStack(spacing: 12) {
        QuestionCard(
            question: "この案で一番助かるのは誰ですか？",
            intent: "対象を具体化する",
            isExpanded: expanded,
            onToggle: { expanded.toggle() },
            onSubmit: { _ in }
        )
        QuestionCard(
            question: "最初の 1 日で試せることは何ですか？",
            intent: "最小の一歩を決める",
            isExpanded: false,
            onToggle: {},
            onSubmit: { _ in }
        )
    }
    .padding()
}
