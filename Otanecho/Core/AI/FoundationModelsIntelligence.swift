import Foundation
import FoundationModels
import os

/// Apple Foundation Models（オンデバイス）による IdeaIntelligence の実装。
///
/// - 各メソッドは呼び出しごとに新しい `LanguageModelSession` を作り、会話履歴を持ち越さない。
/// - 入力は `PromptBudget` で必ず切り詰め、約 4,096 トークンのコンテキストに収める。
/// - 候補の参照には 1 始まりの番号を使い、モデルに UUID を生成させない。
nonisolated final class FoundationModelsIntelligence: IdeaIntelligence, Sendable {
    private static let logger = Logger(subsystem: "jp.shilokuma.Otanecho", category: "AI")

    /// 決定的な出力が欲しい処理（タイトル・タグ・関連付け）の温度
    private static let preciseOptions = GenerationOptions(temperature: 0.3)
    /// 発想の幅が欲しい処理（問い・ダイジェスト）の温度
    private static let creativeOptions = GenerationOptions(temperature: 0.7)

    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
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
        LanguageModelSession(model: model, instructions: Self.commonInstructions).prewarm()
    }

    // MARK: - IdeaIntelligence

    func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment {
        try ensureAvailable()
        let trimmedBody = PromptBudget.body(body)
        guard !trimmedBody.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        let tags = PromptBudget.candidates(existingTags.map(TagNormalizer.clean).filter { !$0.isEmpty })
        var prompt = """
        次のメモにタイトルとタグを付けてください。

        【メモ】
        \(trimmedBody)
        """
        if !tags.isEmpty {
            prompt += "\n\n【既存のタグ】\n" + tags.joined(separator: "、")
            prompt += "\n既存のタグに近い意味のものがあれば、同じ表記を使ってください。"
        }

        let output: EnrichmentOutput = try await generate(
            prompt,
            instructions: Self.enrichInstructions,
            options: Self.preciseOptions,
            label: "enrich"
        )

        let title = PromptBudget.truncate(output.title.trimmingCharacters(in: .whitespacesAndNewlines), limit: 30)
        let mergedTags = TagNormalizer.merge(generated: output.tags, existing: existingTags)
        return SeedEnrichment(title: title, tags: mergedTags)
    }

    func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion] {
        try ensureAvailable()
        let body = PromptBudget.body(seed.body)
        guard !body.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        var prompt = """
        次のアイデアを深めるための問いを 3 つ作ってください。

        【アイデア】
        \(body)
        """
        let history = Array(seed.sprouts.suffix(PromptBudget.sproutLimit))
        if !history.isEmpty {
            let lines = history.map { sprout -> String in
                let question = PromptBudget.preview(sprout.question, limit: PromptBudget.sproutPreviewLimit)
                if let answer = sprout.answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "- 問い: \(question)\n  答え: \(PromptBudget.preview(answer, limit: PromptBudget.sproutPreviewLimit))"
                }
                return "- 問い: \(question)（未回答）"
            }
            prompt += "\n\n【これまでの問答】\n" + lines.joined(separator: "\n")
            prompt += "\nこれまでの問いと重ならない、別の角度の問いにしてください。答えがある場合は、その答えを踏まえて一歩先へ進める問いにしてください。"
        }

        let output: QuestionsOutput = try await generate(
            prompt,
            instructions: Self.questionInstructions,
            options: Self.creativeOptions,
            label: "deepeningQuestions"
        )

        let questions = output.questions
            .map { item in
                DeepeningQuestion(
                    question: PromptBudget.truncate(item.question.trimmingCharacters(in: .whitespacesAndNewlines), limit: 60),
                    intent: QuestionIntent.normalize(item.intent)
                )
            }
            .filter { !$0.question.isEmpty }
        guard !questions.isEmpty else {
            throw IdeaIntelligenceError.generationFailed("問いが生成されませんでした")
        }
        return Array(questions.prefix(3))
    }

    func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID] {
        try ensureAvailable()
        let body = PromptBudget.body(seed.body)
        guard !body.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        let pool = PromptBudget.candidates(candidates.filter { $0.id != seed.id })
        guard !pool.isEmpty else { return [] }

        let prompt = """
        【基準のアイデア】
        \(body)

        【候補】
        \(PromptBudget.numberedList(pool))

        候補の中から、基準のアイデアと関連が強いものの番号を、関連が強い順に最大 5 つ挙げてください。
        テーマ・対象・解決したい課題が重なるものを関連が強いとみなします。関連するものがなければ空にしてください。
        """

        let output: RelatedOutput = try await generate(
            prompt,
            instructions: Self.relatedInstructions,
            options: Self.preciseOptions,
            label: "relatedSeeds"
        )
        return IndexMapper.ids(from: output.relatedIndices, in: pool, limit: 5)
    }

    func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest {
        try ensureAvailable()
        let recentPool = PromptBudget.candidates(recent)
        let dormantPool = PromptBudget.candidates(dormant)
        let combined = recentPool + dormantPool
        guard !combined.isEmpty else { throw IdeaIntelligenceError.emptyInput }

        var prompt = "ユーザーが書き留めたアイデアの一覧です。番号はこのまま使ってください。\n"
        if recentPool.isEmpty {
            prompt += "\n【今週の種】\n（今週は新しい種がありませんでした）\n"
        } else {
            prompt += "\n【今週の種】\n" + PromptBudget.numberedList(recentPool) + "\n"
        }
        if dormantPool.isEmpty {
            prompt += "\n【眠っている種】\n（なし）\n"
        } else {
            prompt += "\n【眠っている種】（\(recentPool.count + 1) 〜 \(combined.count) 番）\n"
            prompt += PromptBudget.numberedList(dormantPool, startingAt: recentPool.count + 1) + "\n"
        }
        prompt += """

        次の 3 点をまとめてください。
        1. summary: 今週の種から読み取れる関心の傾向を 2〜3 文で。
        2. resurfacedIndices: 眠っている種のうち、いま見直すと動き出しそうなものの番号を最大 3 つ（眠っている種がなければ空）。
        3. combinations: 一覧の中の 2 つを掛け合わせると面白くなりそうな組み合わせを最大 2 件。番号 2 つと、60 文字以内の提案。
        """

        let output: DigestOutput = try await generate(
            prompt,
            instructions: Self.digestInstructions,
            options: Self.creativeOptions,
            label: "weeklyDigest"
        )

        let dormantRange = (recentPool.count + 1)...max(recentPool.count + 1, combined.count)
        let resurfaced = dormantPool.isEmpty
            ? []
            : IndexMapper.ids(from: output.resurfacedIndices, in: combined, allowing: dormantRange, limit: 3)

        let combinations = output.combinations
            .compactMap { item -> WeeklyDigest.Combination? in
                let ids = IndexMapper.ids(from: item.indices, in: combined, limit: 2)
                let proposal = PromptBudget.truncate(item.proposal.trimmingCharacters(in: .whitespacesAndNewlines), limit: 80)
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

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .guardrailViolation: "内容が安全ガイドラインに触れたため生成できませんでした"
        case .exceededContextWindowSize: "入力が長すぎます"
        case .unsupportedLanguageOrLocale: "この言語には対応していません"
        case .assetsUnavailable: "モデルの準備ができていません"
        case .decodingFailure: "応答の解釈に失敗しました"
        case .unsupportedGuide: "出力形式の指定に対応していません"
        case .rateLimited: "リクエストが多すぎます。しばらくしてからお試しください"
        case .concurrentRequests: "別の処理が進行中です"
        case .refusal: "モデルが応答を拒否しました"
        @unknown default: error.localizedDescription
        }
    }

    // MARK: - Instructions

    private static let commonInstructions = """
    あなたは、ユーザーが書き留めたアイデアのメモを静かに支える編集アシスタントです。
    出力はすべて日本語で書きます。
    ユーザーの本文を改変したり、書かれていない内容を創作したりしません。
    ユーザーの意見や発想を否定・評価しません。
    """

    private static let enrichInstructions = commonInstructions + """

    メモに短いタイトルとタグを付けるのが役割です。
    タイトルは 20 文字以内の日本語で、本文の言い換えにとどめ、装飾語や感想を付けません。
    タグは本文の主題を表す名詞を 1 語ずつ、1〜4 個。記号や「#」は付けません。
    """

    private static let questionInstructions = commonInstructions + """

    アイデアを深めるための「開いた問い」を作るのが役割です。
    問いは 40 文字以内で、ユーザーが一言で答え始められる具体的なものにします。
    はい／いいえで終わる問い、抽象的すぎる問い、批判的な問いは避けます。
    各問いには狙いを 1 つ添えます。狙いは次の 5 つから選びます:
    「前提を疑う」「対象を具体化する」「最小の一歩を決める」「似た事例と比べる」「障害を洗い出す」。
    3 つの問いは、それぞれ異なる狙いにします。
    """

    private static let relatedInstructions = commonInstructions + """

    アイデア同士の関連を見つけるのが役割です。
    候補は番号付きで渡されます。必ずその番号だけで答え、候補にない番号は使いません。
    関連が弱いものを無理に挙げず、無関係なら空のリストを返します。
    """

    private static let digestInstructions = commonInstructions + """

    1 週間分のアイデアをふりかえる短いダイジェストを書くのが役割です。
    文体は穏やかで、断定を避け、ユーザーが自分の関心に気づく手助けをします。
    種は番号付きで渡されます。番号を参照するときは、必ず渡された番号だけを使います。
    提案は 60 文字以内で、2 つの種を結びつける具体的な一言にします。
    """
}

// MARK: - Generable 出力型

/// 問いの狙い。モデルの出力が揺れても既定の 5 種類に寄せる。
nonisolated enum QuestionIntent {
    static let all = ["前提を疑う", "対象を具体化する", "最小の一歩を決める", "似た事例と比べる", "障害を洗い出す"]

    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if all.contains(trimmed) { return trimmed }
        if let match = all.first(where: { trimmed.contains($0) || $0.contains(trimmed) }), !trimmed.isEmpty {
            return match
        }
        return trimmed.isEmpty ? all[1] : trimmed
    }
}

@Generable(description: "メモに付けるタイトルとタグ")
nonisolated struct EnrichmentOutput {
    @Guide(description: "20 文字以内の日本語タイトル。本文の言い換えで、装飾語を付けない")
    var title: String

    @Guide(description: "本文の主題を表す名詞 1 語ずつ。記号を付けない。既存タグに近いものがあれば同じ表記を使う", .count(1...4))
    var tags: [String]
}

@Generable(description: "アイデアを深める問い")
nonisolated struct QuestionOutput {
    @Guide(description: "40 文字以内の、答えやすい開いた問い（日本語）")
    var question: String

    @Guide(description: "問いの狙い", .anyOf(QuestionIntent.all))
    var intent: String
}

@Generable(description: "深掘りの問いのセット")
nonisolated struct QuestionsOutput {
    @Guide(description: "それぞれ狙いの異なる問い。ちょうど 3 問", .count(3))
    var questions: [QuestionOutput]
}

@Generable(description: "関連の強い候補の番号")
nonisolated struct RelatedOutput {
    @Guide(description: "関連が強い候補の番号（1 始まり）。関連が強い順。無関係なら空", .maximumCount(5))
    var relatedIndices: [Int]
}

@Generable(description: "2 つの種の掛け合わせ")
nonisolated struct CombinationOutput {
    @Guide(description: "掛け合わせる 2 つの種の番号（1 始まり・異なる番号）", .count(2))
    var indices: [Int]

    @Guide(description: "60 文字以内の掛け合わせの提案")
    var proposal: String
}

@Generable(description: "今週のふりかえり")
nonisolated struct DigestOutput {
    @Guide(description: "今週の関心の傾向を 2〜3 文で")
    var summary: String

    @Guide(description: "眠っている種のうち、もう一度見てほしいものの番号（1 始まり）。最大 3 つ", .maximumCount(3))
    var resurfacedIndices: [Int]

    @Guide(description: "掛け合わせの提案。最大 2 件", .maximumCount(2))
    var combinations: [CombinationOutput]
}
