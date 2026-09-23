import Foundation
import FoundationModels
import os

/// Apple Foundation Models（オンデバイス）による IdeaIntelligence の実装。
///
/// - 各メソッドは呼び出しごとに新しい `LanguageModelSession` を作り、会話履歴を持ち越さない。
/// - 入力は `PromptBudget` で必ず切り詰め、モデルのコンテキスト長（`SystemLanguageModel.contextSize`）に収める。
/// - 候補の参照には 1 始まりの番号を使い、モデルに UUID を生成させない。
/// - プロンプトと instructions は英語で固定し、**出力言語だけ**を端末の設定言語に合わせる（`OutputLanguage`）。
nonisolated final class FoundationModelsIntelligence: IdeaIntelligence, Sendable {
    private static let logger = Logger(subsystem: "jp.shilokuma.Otanecho", category: "AI")

    /// 決定的な出力が欲しい処理（タイトル・タグ・関連付け）の温度
    private static let preciseOptions = GenerationOptions(temperature: 0.3)
    /// 発想の幅が欲しい処理（問い・ダイジェスト）の温度
    private static let creativeOptions = GenerationOptions(temperature: 0.7)

    private let model: SystemLanguageModel
    /// 出力させる言語。テストや検証で差し替えられるように保持する。
    private let locale: Locale
    /// 入力の上限を決めるコンテキスト長の上書き。nil ならモデルから実行時に取る。
    private let contextSizeOverride: Int?

    init(model: SystemLanguageModel = .default, locale: Locale = .current, contextSize: Int? = nil) {
        self.model = model
        self.locale = locale
        self.contextSizeOverride = contextSize
    }

    /// 入力の上限。コンテキスト長は OS と端末世代で変わるので、呼び出しのたびに取り直す。
    /// `contextSize` は iOS 26.4 未満では常に 4,096 を返す（`@backDeployed`）。
    private var limits: PromptBudget.Limits {
        PromptBudget.limits(forContextSize: contextSizeOverride ?? model.contextSize)
    }

    // MARK: - Availability

    var availability: IntelligenceAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unknown
            }
        }
    }

    /// モデルの読み込みを先に始めておく。画面表示の直前などに呼ぶと初回応答が速くなる。
    func prewarm() {
        guard availability.isAvailable else { return }
        LanguageModelSession(model: model, instructions: Self.commonInstructions(language: outputLanguage)).prewarm()
    }

    /// モデルに出力させる言語の名前（英語表記）。
    private var outputLanguage: String {
        OutputLanguage.name(for: locale)
    }

    // MARK: - IdeaIntelligence

    func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment {
        try ensureAvailable()
        let limits = self.limits
        let trimmedBody = PromptBudget.body(body, limit: limits.body)
        guard !trimmedBody.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        let tags = PromptBudget.candidates(existingTags.map(TagNormalizer.clean).filter { !$0.isEmpty }, limit: limits.candidates)
        var prompt = """
        Give the following note a title and tags.

        [Note]
        \(trimmedBody)
        """
        if !tags.isEmpty {
            prompt += "\n\n[Existing tags]\n" + tags.joined(separator: ", ")
            prompt += "\nIf any existing tag means close to the same thing, reuse it exactly as written."
        }

        let output: EnrichmentOutput = try await generate(
            prompt,
            instructions: Self.enrichInstructions(language: outputLanguage),
            options: Self.preciseOptions,
            label: "enrich"
        )

        let title = PromptBudget.truncate(
            output.title.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: PromptBudget.titleLimit(for: locale)
        )
        let mergedTags = TagNormalizer.merge(generated: output.tags, existing: existingTags)
        return SeedEnrichment(title: title, tags: mergedTags)
    }

    func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion] {
        try ensureAvailable()
        let limits = self.limits
        let body = PromptBudget.body(seed.body, limit: limits.body)
        guard !body.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        var prompt = """
        Write 3 questions that help the user develop the following idea.

        [Idea]
        \(body)
        """
        let history = Array(seed.sprouts.suffix(limits.sprouts))
        if !history.isEmpty {
            let lines = history.map { sprout -> String in
                let question = PromptBudget.preview(sprout.question, limit: PromptBudget.sproutPreviewLimit)
                if let answer = sprout.answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "- Q: \(question)\n  A: \(PromptBudget.preview(answer, limit: PromptBudget.sproutPreviewLimit))"
                }
                return "- Q: \(question) (unanswered)"
            }
            prompt += "\n\n[Questions asked so far]\n" + lines.joined(separator: "\n")
            prompt += "\nAsk from angles that do not overlap these. Where an answer is given, ask something that builds one step further on it."
        }

        let output: QuestionsOutput = try await generate(
            prompt,
            instructions: Self.questionInstructions(language: outputLanguage),
            options: Self.creativeOptions,
            label: "deepeningQuestions"
        )

        let questionLimit = PromptBudget.questionLimit(for: locale)
        let questions = output.questions
            .map { item in
                DeepeningQuestion(
                    question: PromptBudget.truncate(
                        item.question.trimmingCharacters(in: .whitespacesAndNewlines),
                        limit: questionLimit
                    ),
                    intent: QuestionIntent.storedValue(for: item.intent)
                )
            }
            .filter { !$0.question.isEmpty }
        guard !questions.isEmpty else {
            throw IdeaIntelligenceError.generationFailed("no questions were generated")
        }
        return Array(questions.prefix(3))
    }

    func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID] {
        try ensureAvailable()
        let limits = self.limits
        let body = PromptBudget.body(seed.body, limit: limits.body)
        guard !body.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        let pool = PromptBudget.candidates(candidates.filter { $0.id != seed.id }, limit: limits.candidates)
        guard !pool.isEmpty else { return [] }

        let prompt = """
        [Reference idea]
        \(body)

        [Candidates]
        \(PromptBudget.numberedList(pool))

        From the candidates, list up to 5 numbers that relate strongly to the reference idea, strongest first.
        Treat candidates as strongly related when they share a theme, an audience, or the problem they try to solve.
        If nothing is related, return an empty list.
        """

        let output: RelatedOutput = try await generate(
            prompt,
            instructions: Self.relatedInstructions(language: outputLanguage),
            options: Self.preciseOptions,
            label: "relatedSeeds"
        )
        return IndexMapper.ids(from: output.relatedIndices, in: pool, limit: 5)
    }

    func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest {
        try ensureAvailable()
        let limits = self.limits
        let recentPool = PromptBudget.candidates(recent, limit: limits.candidates)
        let dormantPool = PromptBudget.candidates(dormant, limit: limits.candidates)
        let combined = recentPool + dormantPool
        guard !combined.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        var prompt = "Here are the ideas the user jotted down. Use the numbers exactly as given.\n"
        if recentPool.isEmpty {
            prompt += "\n[Seeds from this week]\n(no new seeds this week)\n"
        } else {
            prompt += "\n[Seeds from this week]\n" + PromptBudget.numberedList(recentPool) + "\n"
        }
        if dormantPool.isEmpty {
            prompt += "\n[Dormant seeds]\n(none)\n"
        } else {
            prompt += "\n[Dormant seeds] (numbers \(recentPool.count + 1)-\(combined.count))\n"
            prompt += PromptBudget.numberedList(dormantPool, startingAt: recentPool.count + 1) + "\n"
        }
        prompt += """

        Put together these 3 things.
        1. summary: what the user seems drawn to this week, in 2-3 sentences.
        2. resurfacedIndices: up to 3 numbers from the dormant seeds that look ready to move if revisited now (empty if there are no dormant seeds).
        3. combinations: up to 2 pairs from the list that would get interesting when combined. Give 2 numbers and a suggestion of at most 20 words.
        """

        let output: DigestOutput = try await generate(
            prompt,
            instructions: Self.digestInstructions(language: outputLanguage),
            options: Self.creativeOptions,
            label: "weeklyDigest"
        )

        let dormantRange = (recentPool.count + 1)...max(recentPool.count + 1, combined.count)
        let resurfaced = dormantPool.isEmpty
            ? []
            : IndexMapper.ids(from: output.resurfacedIndices, in: combined, allowing: dormantRange, limit: 3)

        let proposalLimit = PromptBudget.proposalLimit(for: locale)
        let combinations = output.combinations
            .compactMap { item -> WeeklyDigest.Combination? in
                let ids = IndexMapper.ids(from: item.indices, in: combined, limit: 2)
                let proposal = PromptBudget.truncate(
                    item.proposal.trimmingCharacters(in: .whitespacesAndNewlines),
                    limit: proposalLimit
                )
                guard ids.count == 2, !proposal.isEmpty else { return nil }
                return WeeklyDigest.Combination(seedIDs: ids, proposal: proposal)
            }
            .prefix(2)

        return WeeklyDigest(
            summary: output.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            resurfacedSeedIDs: resurfaced,
            combinations: Array(combinations)
        )
    }

    // MARK: - Session

    private func ensureAvailable() throws {
        let current = availability
        guard current.isAvailable else { throw IdeaIntelligenceError.unavailable(current) }
    }

    /// 新しいセッションで 1 回だけ生成する。エラーは `IdeaIntelligenceError` に変換する。
    private func generate<Output: Generable>(
        _ prompt: String,
        instructions: String,
        options: GenerationOptions,
        label: StaticString
    ) async throws -> Output {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let start = ContinuousClock.now
        Self.logger.debug("\(label, privacy: .public) 開始 (prompt: \(prompt.count) 文字)")
        do {
            let response = try await session.respond(to: prompt, generating: Output.self, options: options)
            let elapsed = (ContinuousClock.now - start).formatted(.units(allowed: [.seconds, .milliseconds]))
            Self.logger.debug("\(label, privacy: .public) 完了 (\(elapsed, privacy: .public))")
            return response.content
        } catch let error as IdeaIntelligenceError {
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            let reason = Self.describe(error)
            Self.logger.error("\(label, privacy: .public) 失敗: \(reason, privacy: .public)")
            throw IdeaIntelligenceError.generationFailed(reason)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("\(label, privacy: .public) 失敗: \(String(describing: error), privacy: .public)")
            throw IdeaIntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    /// 失敗の理由。ログにだけ出すので翻訳しない。
    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation: "the content tripped the safety guardrail"
        case .exceededContextWindowSize: "the input was too long"
        case .unsupportedLanguageOrLocale: "the language is not supported by the model"
        case .assetsUnavailable: "the model is not ready"
        case .decodingFailure: "the response could not be decoded"
        case .unsupportedGuide: "the output format is not supported"
        case .rateLimited: "too many requests"
        case .concurrentRequests: "another request is in flight"
        case .refusal: "the model refused to respond"
        @unknown default: error.localizedDescription
        }
    }

    // MARK: - Instructions

    /// すべての処理で共通の前提。`language` に端末の設定言語（英語表記の言語名）を入れる。
    static func commonInstructions(language: String) -> String {
        """
        You are a quiet editorial assistant for the notes a user jots down about their ideas.
        Write every part of your output in \(language), regardless of the language these instructions are written in.
        Never rewrite the user's text, and never invent anything that is not in it.
        Never judge or dismiss the user's opinions or ideas.
        """
    }

    private static func enrichInstructions(language: String) -> String {
        commonInstructions(language: language) + """

        Your job is to give a note a short title and tags.
        The title restates the note in at most 8 words. No embellishment, no commentary.
        Tags are 1 to 4 nouns that name what the note is about, one noun each. No symbols, no "#".
        """
    }

    private static func questionInstructions(language: String) -> String {
        commonInstructions(language: language) + """

        Your job is to write open questions that help the user develop an idea.
        Each question is at most 20 words and concrete enough that the user can start answering in a sentence.
        Avoid yes/no questions, questions that stay abstract, and questions that criticize.
        Give each question one intent, chosen from these 5:
        \(QuestionIntent.modelValues.map { "\"\($0)\"" }.joined(separator: ", ")).
        The 3 questions must each have a different intent.
        Report the intent in English, exactly as listed above, even though the question itself is in \(language).
        """
    }

    private static func relatedInstructions(language: String) -> String {
        commonInstructions(language: language) + """

        Your job is to find ideas that relate to each other.
        The candidates come numbered. Answer only with those numbers, and never use a number that is not in the list.
        Do not stretch to include weak matches. Return an empty list when nothing is related.
        """
    }

    private static func digestInstructions(language: String) -> String {
        commonInstructions(language: language) + """

        Your job is to write a short digest looking back on a week of ideas.
        Keep the tone calm, avoid asserting conclusions, and help the user notice what they are drawn to.
        The seeds come numbered. When you refer to one, use only the numbers you were given.
        A suggestion is at most 20 words and names one concrete way two seeds connect.
        """
    }
}

// MARK: - Generable 出力型

@Generable(description: "A title and tags for a note")
nonisolated struct EnrichmentOutput {
    @Guide(description: "A title of at most 8 words in the requested output language. Restates the note, with no embellishment")
    var title: String

    @Guide(description: "Nouns naming what the note is about, one per entry, in the requested output language. No symbols. Reuse an existing tag's exact wording when one means close to the same thing", .count(1...4))
    var tags: [String]
}

@Generable(description: "A question that helps develop an idea")
nonisolated struct QuestionOutput {
    @Guide(description: "An open, easy-to-start question of at most 20 words, in the requested output language")
    var question: String

    @Guide(description: "What the question is for. Always in English, exactly as listed", .anyOf(QuestionIntent.modelValues))
    var intent: String
}

@Generable(description: "A set of questions for developing an idea")
nonisolated struct QuestionsOutput {
    @Guide(description: "Questions that each have a different intent. Exactly 3", .count(3))
    var questions: [QuestionOutput]
}

@Generable(description: "The numbers of the most closely related candidates")
nonisolated struct RelatedOutput {
    @Guide(description: "Numbers of strongly related candidates (1-based), strongest first. Empty when nothing is related", .maximumCount(5))
    var relatedIndices: [Int]
}

@Generable(description: "A combination of two seeds")
nonisolated struct CombinationOutput {
    @Guide(description: "The numbers of the 2 seeds to combine (1-based, and different from each other)", .count(2))
    var indices: [Int]

    @Guide(description: "A suggestion of at most 20 words for combining them, in the requested output language")
    var proposal: String
}

@Generable(description: "A look back on this week")
nonisolated struct DigestOutput {
    @Guide(description: "What the user seems drawn to this week, in 2-3 sentences, in the requested output language")
    var summary: String

    @Guide(description: "Numbers of dormant seeds worth another look (1-based). At most 3", .maximumCount(3))
    var resurfacedIndices: [Int]

    @Guide(description: "Suggestions for combining seeds. At most 2", .maximumCount(2))
    var combinations: [CombinationOutput]
}
