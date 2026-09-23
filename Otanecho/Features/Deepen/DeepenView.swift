import StoreKit
import SwiftData
import SwiftUI

/// 種を深掘りして芽を出す画面。AI が 3 つの問いを投げ、答えると Sprout として種に残る。
/// AI が使えない環境ではテンプレートの問い（`TemplateQuestions`）を出すので、どの端末でも種 → 芽 → 木 と育つ。
struct DeepenView: View {
    let seed: Seed

    @Environment(\.ideaIntelligence) private var intelligence
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    @State private var phase: Phase = .idle
    /// 「別の問いをもらう」で加算して .task を再実行する
    @State private var generation = 0
    @State private var isBodyExpanded = false
    /// 開いている回答欄。AI の問いは DeepeningQuestion.id、既存の Sprout は Sprout.id
    @State private var expandedID: UUID?
    @State private var celebration: LocalizedStringResource?
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
        /// AI が使えないので、テンプレートの問いを出している。
        case template([DeepeningQuestion], IntelligenceAvailability)

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
        .navigationTitle("Grow")
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
                Label { Text(seed.stage.label) } icon: { Image(systemName: seed.stage.systemImage) }
                if seed.answeredSproutCount > 0 {
                    Text("\(seed.answeredSproutCount) questions answered")
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
                        Button(isBodyExpanded ? "Show less" : "Read more") {
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
            questionList(questions)
        case .template(let questions, let availability):
            VStack(alignment: .leading, spacing: 16) {
                questionList(questions)
                IntelligenceUnavailableView(availability: availability)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn't come up with questions", systemImage: "leaf")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again", systemImage: "arrow.clockwise") { generation += 1 }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func questionList(_ questions: [DeepeningQuestion]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Questions")
            ForEach(questions) { question in
                QuestionCard(
                    question: question.question,
                    intent: Self.intentText(question.intent),
                    isExpanded: expandedID == question.id,
                    onToggle: { toggle(question.id) },
                    onSubmit: { answer in answerNewQuestion(question, with: answer) }
                )
            }
            if questions.isEmpty {
                Text("You've answered all of these questions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            regenerateButton
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.breathe, options: .repeat(.continuous))
            Text("Thinking of questions…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var regenerateButton: some View {
        Button("Get different questions", systemImage: "arrow.clockwise") {
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
            sectionTitle("Earlier questions")
            ForEach(pendingSprouts) { sprout in
                QuestionCard(
                    question: sprout.question,
                    intent: Self.intentText(sprout.intent),
                    isExpanded: expandedID == sprout.id,
                    onToggle: { toggle(sprout.id) },
                    onSubmit: { answer in answerExisting(sprout, with: answer) }
                )
            }
        }
    }

    private var answeredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your answers")
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

    /// 問いの狙いの表示。既定の 5 種類はローカライズし、モデルが独自の値を返した場合はそのまま出す。
    private static func intentText(_ raw: String?) -> Text? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let intent = QuestionIntent.resolve(raw) { return Text(intent.label) }
        return Text(verbatim: raw)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
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
            showTemplateQuestions(availability)
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
            showTemplateQuestions(reason)
        } catch {
            phase = .failed
        }
    }

    /// AI が使えないときに、テンプレートから問いを出す。
    /// この種で既に出した問い（回答済み・未回答とも）は除く。未回答のものは「前の問い」に並んでいるため。
    private func showTemplateQuestions(_ availability: IntelligenceAvailability) {
        let used = Set(seed.sprouts.map(\.question))
        let questions = TemplateQuestions.pick(excluding: used).map {
            DeepeningQuestion(question: $0.localizedText, intent: $0.intent.rawValue)
        }
        withAnimation(.snappy) { phase = .template(questions, availability) }
    }

    private func answerNewQuestion(_ question: DeepeningQuestion, with answer: String) {
        let sprout = Sprout(question: question.question, intent: question.intent)
        sprout.answer = answer
        sprout.answeredAt = .now
        modelContext.insert(sprout)
        seed.sprouts.append(sprout)
        withAnimation(.snappy) {
            switch phase {
            case .loaded(let questions):
                phase = .loaded(questions.filter { $0.id != question.id })
            case .template(let questions, let availability):
                phase = .template(questions.filter { $0.id != question.id }, availability)
            case .idle, .loading, .failed:
                break
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
        let message: LocalizedStringResource
        switch stage {
        case .seed: return
        case .sprout: message = "It sprouted 🌱"
        case .tree: message = "It's a tree now 🌳"
        }
        celebrationTrigger += 1
        celebration = message
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            celebration = nil
            // 祝いの表示を見届けてから頼む。重ねて出すと祝いが目に入らない
            if stage == .tree {
                requestReviewIfNeeded()
            }
        }
    }

    private func requestReviewIfNeeded() {
        let prompt = AppReviewPrompt.shared
        guard prompt.shouldRequestAfterTree else { return }
        prompt.markRequested()
        requestReview()
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
