import Observation
import SwiftUI

/// 共有シートの状態。読み込み中の内容・ひとこと・エラーを保持する。
@Observable
final class ShareComposeModel {
    var content = SharedContent()
    var note = ""
    var isLoading = true
    var isSaving = false
    var errorMessage: String?

    var canSave: Bool {
        !isSaving && (!content.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 保存する本文。ひとこと + 改行 + 共有テキスト or URL。
    var composedBody: String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let shared = content.bodyText
        return [trimmedNote, shared].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// 共有シートの UI。上部に共有内容のプレビュー、下にひとことを書く欄。「保存」1 タップで終わる。
struct ShareComposeView: View {
    @Bindable var model: ShareComposeModel
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNoteFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                preview
                noteEditor
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("お種帳に保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSave) {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").bold()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
        .onAppear { isNoteFocused = true }
    }

    @ViewBuilder
    private var preview: some View {
        if model.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("共有内容を読み込み中…")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        } else if model.content.isEmpty {
            Text("共有された内容がありません。ひとことだけでも保存できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let title = model.content.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                if let text = model.content.text {
                    Text(text)
                        .font(.footnote)
                        .lineLimit(4)
                }
                if let url = model.content.url {
                    Label(url.absoluteString, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
    }

    private var noteEditor: some View {
        TextEditor(text: $model.note)
            .focused($isNoteFocused)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 96, maxHeight: 160)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if model.note.isEmpty {
                    Text("ひとこと（任意）")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }
}

#Preview("URL") {
    let model = ShareComposeModel()
    model.isLoading = false
    model.content = SharedContent(
        text: nil,
        url: URL(string: "https://developer.apple.com/documentation/speech"),
        title: "Speech | Apple Developer Documentation"
    )
    return ShareComposeView(model: model, onSave: {}, onCancel: {})
}

#Preview("テキスト") {
    let model = ShareComposeModel()
    model.isLoading = false
    model.content = SharedContent(text: "アイデアは寝かせると育つ。1 週間後に見返す仕組みが欲しい。", url: nil, title: nil)
    return ShareComposeView(model: model, onSave: {}, onCancel: {})
}
