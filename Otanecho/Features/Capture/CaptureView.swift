import Foundation
import SwiftData
import SwiftUI

/// 思いついた瞬間に書き留める入力画面。
/// 開いた瞬間にキーボードが上がり、書いた内容は自動で保存される。保存ボタンは無い。
struct CaptureView: View {
    let prefill: String?
    let source: CaptureSource

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(SeedEnricher.self) private var enricher: SeedEnricher?

    @FocusState private var isEditorFocused: Bool
    @State private var text: String
    @State private var seed: Seed?
    @State private var pendingSave: Task<Void, Never>?
    @State private var hasFinished = false
    @State private var savedFeedbackTrigger = 0

    /// 本文更新のデバウンス間隔。
    private static let saveDebounce: Duration = .milliseconds(400)

    init(prefill: String? = nil, source: CaptureSource = .app) {
        self.prefill = prefill
        self.source = source
        _text = State(initialValue: prefill ?? "")
    }

    var body: some View {
        NavigationStack {
            editor
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark", role: .close) {
                            finish()
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        VoiceInputButton(text: $text)
                        Spacer()
                        if let seed, !isBlank {
                            Button("Grow", systemImage: "leaf") {
                                deepen(seed)
                            }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
        .sensoryFeedback(.impact(weight: .light), trigger: savedFeedbackTrigger)
        .onAppear {
            isEditorFocused = true
            createSeedIfNeeded(with: text)
        }
        .task {
            // シート表示直後にフォーカスが外れる環境があるため、少し遅らせてもう一度だけ当てる
            try? await Task.sleep(for: .milliseconds(150))
            if !isEditorFocused { isEditorFocused = true }
        }
        .onChange(of: text) { _, newValue in
            scheduleSave(newValue)
        }
        .onDisappear {
            finish()
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .focused($isEditorFocused)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Whatever just came to mind")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    // MARK: - 保存

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSave(_ newValue: String) {
        guard !hasFinished else { return }
        guard seed != nil else {
            createSeedIfNeeded(with: newValue)
            return
        }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            persist(newValue)
        }
    }

    /// 空でない最初の文字が入った時点で Seed を作る。
    private func createSeedIfNeeded(with body: String) {
        guard seed == nil, !hasFinished else { return }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newSeed = Seed(body: body, source: source)
        modelContext.insert(newSeed)
        save()
        seed = newSeed
    }

    private func persist(_ body: String) {
        guard let seed, seed.body != body else { return }
        seed.body = body
        seed.touch()
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("種の保存に失敗: \(error)")
        }
    }

    /// 画面を閉じるときの後始末。空白のみなら削除、保存済みならハプティクスと AI 処理の依頼。
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        pendingSave?.cancel()
        guard let seed else { return }

        if isBlank {
            modelContext.delete(seed)
            save()
            self.seed = nil
        } else {
            persist(text)
            savedFeedbackTrigger += 1
            enricher?.enqueue(seedID: seed.id)
        }
    }

    private func deepen(_ seed: Seed) {
        let id = seed.id
        finish()
        dismiss()
        router.showSeed(id: id)
    }
}

#Preview("空") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CaptureView()
        }
        .environment(AppRouter())
        .modelContainer(PersistenceController.makePreviewContainer())
}

#Preview("プレフィル") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CaptureView(prefill: "共有から来たテキスト", source: .shareExtension)
        }
        .environment(AppRouter())
        .modelContainer(PersistenceController.makePreviewContainer())
}
