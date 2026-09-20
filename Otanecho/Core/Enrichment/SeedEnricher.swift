import Foundation
import Observation
import OSLog
import SwiftData

/// 保存済みの種に、オンデバイス AI でタイトルとタグを付ける裏方。
/// UI からは `enqueue(seedID:)` を呼ぶだけで、結果は SwiftData を通じて画面に反映される。失敗は UI に出さずログだけ残す。
@MainActor
@Observable
final class SeedEnricher {
    /// タイトル・タグ生成の対象になる本文の最小文字数（前後の空白を除く）。
    nonisolated static let minimumBodyLength = 6
    /// 1 つの種に付けるタグの最大数。
    nonisolated static let maximumTagCount = 5

    private let container: ModelContainer
    private let intelligence: any IdeaIntelligence
    private let logger = Logger(subsystem: "ml.mrs1669.Otanecho", category: "SeedEnricher")

    /// 同じ種を同時に処理しないための記録。
    @ObservationIgnored private var inFlight: Set<UUID> = []
    /// `enrichPending()` の多重実行を防ぐ。
    @ObservationIgnored private var isDraining = false

    /// 現在処理中の件数。基本は UI に出さないが、必要なら参照できる。
    private(set) var activeCount = 0

    init(container: ModelContainer, intelligence: any IdeaIntelligence) {
        self.container = container
        self.intelligence = intelligence
    }

    /// AI が利用できるかどうか。false のときは何もしない。
    var isAvailable: Bool { intelligence.availability.isAvailable }

    /// 指定した種の処理を非同期に依頼する。呼び出し側は結果を待たない。
    func enqueue(seedID: UUID) {
        guard isAvailable else { return }
        Task { await enrich(seedID: seedID) }
    }

    /// 未処理（`enrichedAt == nil`）で本文が十分な長さの種を、古い順に直列で処理する。
    func enrichPending() async {
        guard isAvailable, !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        for id in pendingSeedIDs() {
            await enrich(seedID: id)
        }
    }

    /// 1 件を処理する。成功して反映したら true。
    @discardableResult
    func enrich(seedID: UUID) async -> Bool {
        guard isAvailable, !inFlight.contains(seedID) else { return false }
        inFlight.insert(seedID)
        activeCount += 1
        defer {
            inFlight.remove(seedID)
            activeCount -= 1
        }

        guard let seed = fetchSeed(id: seedID), Self.isEligible(seed) else { return false }
        let body = seed.body
        let existingTags = seed.tags

        do {
            let result = try await intelligence.enrich(body: body, existingTags: existingTags)
            // 待っている間に削除・処理済みになっている可能性があるので取り直す
            guard let seed = fetchSeed(id: seedID), seed.enrichedAt == nil else { return false }
            Self.apply(result, to: seed)
            try container.mainContext.save()
            return true
        } catch {
            logger.error("種 \(seedID.uuidString, privacy: .public) の AI 処理に失敗: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - 判定・適用（純粋なロジック。テストから直接呼べる）

    /// 処理対象になる条件。
    nonisolated static func isEligible(body: String, enrichedAt: Date?) -> Bool {
        guard enrichedAt == nil else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumBodyLength
    }

    /// 既存タグを優先しつつ、大文字小文字を無視して重複を除き、最大数までに絞る。
    nonisolated static func mergedTags(existing: [String], suggested: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag in existing + suggested {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count == maximumTagCount { break }
        }
        return result
    }

    // MARK: - Private

    private static func isEligible(_ seed: Seed) -> Bool {
        isEligible(body: seed.body, enrichedAt: seed.enrichedAt)
    }

    /// AI の結果を反映する。本文には一切触れない。
    private static func apply(_ enrichment: SeedEnrichment, to seed: Seed) {
        let title = enrichment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            seed.title = title
        }
        seed.tags = mergedTags(existing: seed.tags, suggested: enrichment.tags)
        seed.enrichedAt = .now
    }

    private func fetchSeed(id: UUID) -> Seed? {
        var descriptor = FetchDescriptor<Seed>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }

    private func pendingSeedIDs() -> [UUID] {
        let descriptor = FetchDescriptor<Seed>(
            predicate: #Predicate { $0.enrichedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let seeds = try? container.mainContext.fetch(descriptor) else { return [] }
        return seeds.filter { Self.isEligible($0) }.map(\.id)
    }
}
