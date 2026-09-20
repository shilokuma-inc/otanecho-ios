import Foundation
import SwiftData
import Testing
@testable import Otanecho

@MainActor
struct EnrichmentTests {
    private func makeContainer() -> ModelContainer {
        PersistenceController.makeContainer(inMemory: true)
    }

    @discardableResult
    private func insertSeed(
        _ body: String,
        tags: [String] = [],
        createdAt: Date = .now,
        into container: ModelContainer
    ) throws -> Seed {
        let seed = Seed(body: body, tags: tags, createdAt: createdAt)
        container.mainContext.insert(seed)
        try container.mainContext.save()
        return seed
    }

    @Test func enrichPendingAppliesTitleAndMergedTags() async throws {
        let container = makeContainer()
        let body = "通勤中に聴くポッドキャストを、聴きながらメモできるアプリ"
        let seed = try insertSeed(body, tags: ["既存"], into: container)

        let mock = MockIdeaIntelligence(
            enrichment: SeedEnrichment(title: "  ポッドキャストメモ  ", tags: ["アプリ", "既存", "音声", "移動", "余り", "はみ出し"])
        )
        let enricher = SeedEnricher(container: container, intelligence: mock)

        await enricher.enrichPending()

        #expect(seed.title == "ポッドキャストメモ")
        #expect(seed.tags == ["既存", "アプリ", "音声", "移動", "余り"])
        #expect(seed.enrichedAt != nil)
        #expect(seed.body == body, "本文は変更しない")
        #expect(mock.recorder.enrichBodies == [body])
    }

    @Test func enrichPendingProcessesOldestFirstAndSkipsIneligible() async throws {
        let container = makeContainer()
        let newer = try insertSeed("あとから書いた十分に長い種", createdAt: .now, into: container)
        let older = try insertSeed("さきに書いた十分に長い種", createdAt: .now.addingTimeInterval(-60), into: container)
        let short = try insertSeed("短い", into: container)
        let done = try insertSeed("すでに処理済みの長い種です", into: container)
        done.enrichedAt = .now
        try container.mainContext.save()

        let mock = MockIdeaIntelligence(enrichment: SeedEnrichment(title: "T", tags: ["a"]))
        let enricher = SeedEnricher(container: container, intelligence: mock)

        await enricher.enrichPending()

        #expect(mock.recorder.enrichBodies == [older.body, newer.body])
        #expect(older.enrichedAt != nil)
        #expect(newer.enrichedAt != nil)
        #expect(short.enrichedAt == nil)
        #expect(short.title == nil)
    }

    @Test func doesNothingWhenIntelligenceIsUnavailable() async throws {
        let container = makeContainer()
        let seed = try insertSeed("十分に長い本文の種ですが AI は使えません", into: container)

        let mock = MockIdeaIntelligence(
            availability: .deviceNotEligible,
            enrichment: SeedEnrichment(title: "呼ばれないはず", tags: ["x"])
        )
        let enricher = SeedEnricher(container: container, intelligence: mock)

        await enricher.enrichPending()
        let enriched = await enricher.enrich(seedID: seed.id)
        enricher.enqueue(seedID: seed.id)
        await Task.yield()

        #expect(enriched == false)
        #expect(enricher.isAvailable == false)
        #expect(mock.recorder.enrichCallCount == 0)
        #expect(seed.title == nil)
        #expect(seed.tags.isEmpty)
        #expect(seed.enrichedAt == nil)
    }

    @Test func failureLeavesSeedUntouched() async throws {
        let container = makeContainer()
        let seed = try insertSeed("失敗しても本文とタグは守られる種", tags: ["守る"], into: container)

        let mock = MockIdeaIntelligence(enrichError: .generationFailed("テスト"))
        let enricher = SeedEnricher(container: container, intelligence: mock)

        let enriched = await enricher.enrich(seedID: seed.id)

        #expect(enriched == false)
        #expect(mock.recorder.enrichCallCount == 1)
        #expect(seed.title == nil)
        #expect(seed.tags == ["守る"])
        #expect(seed.enrichedAt == nil)
    }

    @Test func concurrentRequestsForSameSeedRunOnce() async throws {
        let container = makeContainer()
        let seed = try insertSeed("同じ種を同時に処理しても一度だけ", into: container)

        let mock = MockIdeaIntelligence(enrichHandler: { _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return SeedEnrichment(title: "一度だけ", tags: [])
        })
        let enricher = SeedEnricher(container: container, intelligence: mock)

        let id = seed.id
        async let first = enricher.enrich(seedID: id)
        async let second = enricher.enrich(seedID: id)
        let results = await [first, second]

        #expect(results.filter { $0 }.count == 1)
        #expect(mock.recorder.enrichCallCount == 1)
        #expect(seed.title == "一度だけ")
    }

    @Test func mergedTagsKeepsExistingFirstAndDeduplicatesCaseInsensitively() {
        let merged = SeedEnricher.mergedTags(
            existing: ["Swift", " 音声 "],
            suggested: ["swift", "音声", "", "アプリ", "移動", "食", "余り"]
        )
        #expect(merged == ["Swift", "音声", "アプリ", "移動", "食"])
    }

    @Test func eligibilityRequiresUnprocessedAndLongEnoughBody() {
        #expect(SeedEnricher.isEligible(body: "", enrichedAt: nil) == false)
        #expect(SeedEnricher.isEligible(body: "五文字です", enrichedAt: nil) == false)
        #expect(SeedEnricher.isEligible(body: "これで六文字", enrichedAt: nil))
        #expect(SeedEnricher.isEligible(body: "   前後の空白は数えない   ", enrichedAt: nil))
        #expect(SeedEnricher.isEligible(body: "十分に長いが処理済み", enrichedAt: .now) == false)
    }
}
