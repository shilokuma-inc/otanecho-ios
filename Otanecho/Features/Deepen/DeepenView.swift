import SwiftData
import SwiftUI

/// 種を深掘りして芽を出す画面。AI が 3 つの問いを投げ、答えると Sprout として種に残る。
/// AI が使えない環境でも、既存の未回答の問いには答えられる。
struct DeepenView: View {
    let seed: Seed

    @Environment(\.ideaIntelligence) private var intelligence
    @Environment(\.modelContext) private var modelContext

    @State private var phase: Phase = .idle
    /// 「別の問いをもらう」で加算して .task を再実行する
    @State private var generation = 0
    @State private var isBodyExpanded = false
    /// 開いている回答欄。AI の問いは DeepeningQuestion.id、既存の Sprout は Sprout.id
    @State private var expandedID: UUID?
    @State private var celebration: String?
    @State private var celebrationTrigger = 0
    @State private var celebrationTask: Task<Void, Never>?

    init(seed: Seed) {
        self.seed = seed
    }

    private enum Phase {
        case idle
        case loading
        case loaded([DeepeningQuestion])
        case failed
        case unavailable(IntelligenceAvailability)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    private var pendingSprouts: [Sprout] {
        seed.sprouts.filter { !$0.isAnswered }.sorted { $0.createdAt > $1.createdAt }
    }

    private var answeredSprouts: [Sprout] {
        seed.sprouts.filter(\.isAnswered).sorted { ($0.answeredAt ?? .distantPast) > ($1.answeredAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                aiSection
                if !pendingSprouts.isEmpty {
                    pendingSection
                }
                if !answeredSprouts.isEmpty {
                    answeredSection
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("芽を出す")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: generation) { await loadQuestions() }
        .sensoryFeedback(.success, trigger: celebrationTrigger)
        .overlay(alignment: .bottom) {
            if let celebration {
                Text(celebration)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: celebration)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(seed.displayTitle)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Label(seed.stage.label, systemImage: seed.stage.systemImage)
                if seed.answeredSproutCount > 0 {
                    Text("答えた問い \(seed.answeredSproutCount)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if seed.body != seed.displayTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(seed.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(isBodyExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    if isBodyLong {
                        Button(isBodyExpanded ? "閉じる" : "続きを読む") {
                            withAnimation(.snappy) { isBodyExpanded.toggle() }
                        }
                        .font(.caption.weight(.medium))
                    }
                }
            }
        }
    }

    private var isBodyLong: Bool {
        seed.body.count > 90 || seed.body.filter(\.isNewline).count >= 3
    }

    @ViewBuilder
    private var aiSection: some View {
        switch phase {
        case .idle, .loading:
            loadingView
        case .loaded(let questions):
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("問い")
                ForEach(questions) { question in
                    QuestionCard(
                        question: question.question,
                        intent: question.intent,
                        isExpanded: expandedID == question.id,
                        onToggle: { toggle(question.id) },
                        onSubmit: { answer in answerNewQuestion(question, with: answer) }
                    )
                }
                if questions.isEmpty {
                    Text("この問いにはすべて答えました。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                regenerateButton
            }
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                Label("うまく問いを作れませんでした", systemImage: "leaf")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("再試行", systemImage: "arrow.clockwise") { generation += 1 }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .unavailable(let availability):
            IntelligenceUnavailableView(availability: availability)
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.breathe, options: .repeat(.continuous))
            Text("問いを考えています…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var regenerateButton: some View {
        Button("別の問いをもらう", systemImage: "arrow.clockwise") {
            expandedID = nil
            generation += 1
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(phase.isLoading)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("前の問い")
            ForEach(pendingSprouts) { sprout in
                QuestionCard(
                    question: sprout.question,
                    intent: sprout.intent,
                    isExpanded: expandedID == sprout.id,
                    onToggle: { toggle(sprout.id) },
                    onSubmit: { answer in answerExisting(sprout, with: answer) }
                )
            }
        }
    }

    private var answeredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("これまでの答え")
            ForEach(answeredSprouts) { sprout in
                VStack(alignment: .leading, spacing: 6) {
                    Text(sprout.question)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sprout.answer ?? "")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        withAnimation(.snappy) {
            expandedID = expandedID == id ? nil : id
        }
    }

    private func loadQuestions() async {
        let availability = intelligence.availability
        guard availability.isAvailable else {
            phase = .unavailable(availability)
            return
        }
        phase = .loading
        do {
            let questions = try await intelligence.deepeningQuestions(for: seed.snapshot)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { phase = .loaded(questions) }
        } catch is CancellationError {
            return
        } catch let IdeaIntelligenceError.unavailable(reason) {
            phase = .unavailable(reason)
        } catch {
            phase = .failed
        }
    }

    private func answerNewQuestion(_ question: DeepeningQuestion, with answer: String) {
        let sprout = Sprout(question: question.question, intent: question.intent)
        sprout.answer = answer
        sprout.answeredAt = .now
        modelContext.insert(sprout)
        seed.sprouts.append(sprout)
        if case .loaded(let questions) = phase {
            withAnimation(.snappy) {
                phase = .loaded(questions.filter { $0.id != question.id })
            }
        }
        finishAnswer()
    }

    private func answerExisting(_ sprout: Sprout, with answer: String) {
        sprout.answer = answer
        sprout.answeredAt = .now
        finishAnswer()
    }

    /// 回答後の共通処理: 段階を更新して保存し、段階が上がっていれば祝う。
    private func finishAnswer() {
        let before = seed.stage
        seed.refreshStage()
        seed.touch()
        expandedID = nil
        do {
            try modelContext.save()
        } catch {
            assertionFailure("回答の保存に失敗: \(error)")
        }
        if seed.stage > before {
            celebrate(seed.stage)
        }
    }

    private func celebrate(_ stage: GrowthStage) {
        let message: String
        switch stage {
        case .seed: return
        case .sprout: message = "芽が出ました 🌱"
        case .tree: message = "木になりました 🌳"
        }
        celebrationTrigger += 1
        celebration = message
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            celebration = nil
        }
    }
}

// MARK: - Preview

#Preview("AI あり") {
    let container = PersistenceController.makePreviewContainer()
    let seed = (try? container.mainContext.fetch(FetchDescriptor<Seed>()))?.first ?? Seed(body: "サンプル")
    NavigationStack {
        DeepenView(seed: seed)
    }
    .modelContainer(container)
    .environment(\.ideaIntelligence, FoundationModelsIntelligence())
}

#Preview("AI 未有効") {
    let container = PersistenceController.makePreviewContainer()
    let seed = (try? container.mainContext.fetch(FetchDescriptor<Seed>()))?.last ?? Seed(body: "サンプル")
    NavigationStack {
        DeepenView(seed: seed)
    }
    .modelContainer(container)
    .environment(\.ideaIntelligence, UnavailableIdeaIntelligence(availability: .appleIntelligenceNotEnabled))
}
