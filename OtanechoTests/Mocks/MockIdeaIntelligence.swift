import Foundation
import Synchronization
@testable import Otanecho

/// テスト用の IdeaIntelligence。各メソッドの返り値・エラーを差し込め、呼び出し内容を記録する。
nonisolated struct MockIdeaIntelligence: IdeaIntelligence {
    /// 呼び出しの記録。値型のモックからでも共有できるよう参照型にしている。
    final class Recorder: Sendable {
        private let enrichedBodies = Mutex<[String]>([])

        func recordEnrich(body: String) {
            enrichedBodies.withLock { $0.append(body) }
        }

        /// `enrich(body:existingTags:)` に渡された本文（呼ばれた順）。
        var enrichBodies: [String] {
            enrichedBodies.withLock { $0 }
        }

        var enrichCallCount: Int { enrichBodies.count }
    }

    var availability: IntelligenceAvailability
    let recorder = Recorder()

    var enrichHandler: @Sendable (String, [String]) async throws -> SeedEnrichment
    var questionsHandler: @Sendable (SeedSnapshot) async throws -> [DeepeningQuestion]
    var relatedHandler: @Sendable (SeedSnapshot, [SeedSnapshot]) async throws -> [UUID]
    var digestHandler: @Sendable ([SeedSnapshot], [SeedSnapshot]) async throws -> WeeklyDigest

    init(
        availability: IntelligenceAvailability = .available,
        enrichHandler: @escaping @Sendable (String, [String]) async throws -> SeedEnrichment = { _, _ in
            SeedEnrichment(title: "タイトル", tags: [])
        },
        questionsHandler: @escaping @Sendable (SeedSnapshot) async throws -> [DeepeningQuestion] = { _ in [] },
        relatedHandler: @escaping @Sendable (SeedSnapshot, [SeedSnapshot]) async throws -> [UUID] = { _, _ in [] },
        digestHandler: @escaping @Sendable ([SeedSnapshot], [SeedSnapshot]) async throws -> WeeklyDigest = { _, _ in
            WeeklyDigest(summary: "", resurfacedSeedIDs: [], combinations: [])
        }
    ) {
        self.availability = availability
        self.enrichHandler = enrichHandler
        self.questionsHandler = questionsHandler
        self.relatedHandler = relatedHandler
        self.digestHandler = digestHandler
    }

    /// enrich が常に同じ結果を返すモック。
    init(availability: IntelligenceAvailability = .available, enrichment: SeedEnrichment) {
        self.init(availability: availability, enrichHandler: { _, _ in enrichment })
    }

    /// enrich が常に失敗するモック。
    init(availability: IntelligenceAvailability = .available, enrichError: IdeaIntelligenceError) {
        self.init(availability: availability, enrichHandler: { _, _ in throw enrichError })
    }

    func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment {
        recorder.recordEnrich(body: body)
        return try await enrichHandler(body, existingTags)
    }

    func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion] {
        try await questionsHandler(seed)
    }

    func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID] {
        try await relatedHandler(seed, candidates)
    }

    func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest {
        try await digestHandler(recent, dormant)
    }
}
