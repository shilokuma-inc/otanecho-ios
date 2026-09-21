import Foundation
import SwiftData
import WidgetKit

/// ウィジェットに表示する 1 時点分のデータ。
nonisolated struct SeedWidgetEntry: TimelineEntry {
    let date: Date
    /// 直近に書き留めた種（新しい順、最大 2 件）
    let recentSeeds: [SeedSnapshot]
    /// 今日書き留めた件数
    let todayCount: Int

    static let empty = SeedWidgetEntry(date: .now, recentSeeds: [], todayCount: 0)

    /// プレビュー・ギャラリー表示用のサンプル
    static var sample: SeedWidgetEntry {
        let now = Date.now
        return SeedWidgetEntry(
            date: now,
            recentSeeds: [
                SeedSnapshot(
                    id: UUID(),
                    body: String(localized: "An app for taking notes while listening to a podcast on the commute"),
                    title: String(localized: "Notes while listening"),
                    tags: [String(localized: "Apps")], createdAt: now, updatedAt: now,
                    stage: .seed, sprouts: []
                ),
                SeedSnapshot(
                    id: UUID(),
                    body: String(localized: "A service that suggests recipes from only what's left in the fridge"),
                    title: nil, tags: [String(localized: "Food")], createdAt: now, updatedAt: now,
                    stage: .sprout, sprouts: []
                ),
            ],
            todayCount: 3
        )
    }
}

/// App Group 共有ストアから直近の種と今日の件数を読み、15 分ごとに更新するプロバイダ。
nonisolated struct SeedTimelineProvider: TimelineProvider {
    /// 次回更新までの間隔
    static let refreshInterval: TimeInterval = 15 * 60

    nonisolated func placeholder(in context: Context) -> SeedWidgetEntry {
        .sample
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping @Sendable (SeedWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task {
            completion(await Self.loadEntry())
        }
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SeedWidgetEntry>) -> Void) {
        Task {
            let entry = await Self.loadEntry()
            let nextUpdate = Date.now.addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    /// `Seed` は @Model なので mainContext から読み、Sendable な `SeedSnapshot` にして返す。
    private static func loadEntry() async -> SeedWidgetEntry {
        await MainActor.run {
            let container = PersistenceController.makeContainer()
            let context = container.mainContext
            let startOfToday = Calendar.current.startOfDay(for: .now)

            var recent = FetchDescriptor<Seed>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            recent.fetchLimit = 2

            let today = FetchDescriptor<Seed>(
                predicate: #Predicate { $0.createdAt >= startOfToday }
            )

            let seeds = (try? context.fetch(recent))?.map(\.snapshot) ?? []
            let count = (try? context.fetchCount(today)) ?? 0
            return SeedWidgetEntry(date: .now, recentSeeds: seeds, todayCount: count)
        }
    }
}
