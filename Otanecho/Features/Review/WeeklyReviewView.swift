import SwiftData
import SwiftUI

/// 週次レビュー。今週触れた種と眠っている種を並べ、AI が使えればダイジェストを添える。
/// AI が使えない環境でも、件数と眠っている種の一覧だけで成立する画面にしている。
struct WeeklyReviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ideaIntelligence) private var intelligence
    @Environment(\.dismiss) private var dismiss

    @State private var data: ReviewData?
    @State private var digest: DigestPhase = .idle

    init() {}

    private struct ReviewData {
        var totalCount: Int
        /// 過去 7 日に作成または更新された種（更新が新しい順）
        var recent: [Seed]
        /// 作成から 14 日以上経ち、最近レビューしていない、まだ種のままのもの（古い順）
        var dormant: [Seed]

        var seedsByID: [UUID: Seed] {
            Dictionary((recent + dormant).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private enum DigestPhase {
        case idle
        case loading
        case ready(WeeklyDigest)
        /// AI が使えない・失敗した・入力がない。AI セクションは出さない。
        case skipped
    }

    private static let recentVisibleLimit = 5

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    if data.totalCount == 0 {
                        ContentUnavailableView(
                            "Your review appears once you've planted some seeds",
                            systemImage: "leaf",
                            description: Text("Jot down what comes to mind, and look back on it all once a week.")
                        )
                    } else {
                        content(data)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("This Week's Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .task {
            let loaded = load()
            data = loaded
            await runDigest(with: loaded)
        }
    }

    // MARK: - Content

    private func content(_ data: ReviewData) -> some View {
        List {
            recentSection(data)
            digestSections(data)
            if case .skipped = digest, !data.dormant.isEmpty {
                dormantSection(data.dormant)
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("weeklyReview.list")
    }

    private func recentSection(_ data: ReviewData) -> some View {
        Section {
            if data.recent.isEmpty {
                Text("No new seeds this week yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data.recent.prefix(Self.recentVisibleLimit)) { seed in
                    ReviewSeedRow(seed: seed, caption: Text(verbatim: seed.updatedAt.formatted(.relative(presentation: .named)))) {
                        open(seed)
                    }
                }
            }
        } header: {
            Text("This week")
        } footer: {
            // 件数が 2 つ出る文は 1 つのキーに押し込めず、複数形を言語ごとに正しく扱えるよう 2 文に分ける
            if !data.recent.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You touched \(data.recent.count) seeds this week.")
                    if data.recent.count > Self.recentVisibleLimit {
                        Text("\(data.recent.count - Self.recentVisibleLimit) more are in your timeline.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func digestSections(_ data: ReviewData) -> some View {
        switch digest {
        case .idle, .loading:
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .foregroundStyle(.green)
                        .symbolEffect(.breathe, options: .repeat(.continuous))
                    Text("Writing your review…")
                        .foregroundStyle(.secondary)
                }
            }
        case .ready(let result):
            let seeds = data.seedsByID
            if !result.summary.isEmpty {
                Section("What you focused on") {
                    Text(result.summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            let resurfaced = result.resurfacedSeedIDs.compactMap { seeds[$0] }
            if !resurfaced.isEmpty {
                Section("Worth another look") {
                    ForEach(resurfaced) { seed in
                        ReviewSeedRow(seed: seed) { open(seed) }
                    }
                }
            }
            let combinations = result.combinations.filter { $0.seedIDs.allSatisfy { seeds[$0] != nil } }
            if !combinations.isEmpty {
                Section("Ideas worth combining") {
                    ForEach(combinations) { combination in
                        combinationRow(combination, seeds: seeds)
                    }
                }
            }
        case .skipped:
            EmptyView()
        }
    }

    private func combinationRow(_ combination: WeeklyDigest.Combination, seeds: [UUID: Seed]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(combination.seedIDs.enumerated()), id: \.offset) { index, id in
                    if index > 0 {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    if let seed = seeds[id] {
                        Button(seed.displayTitle) { open(seed) }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .lineLimit(1)
                    }
                }
            }
            Text(combination.proposal)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func dormantSection(_ dormant: [Seed]) -> some View {
        Section {
            ForEach(dormant) { seed in
                ReviewSeedRow(seed: seed, caption: Text("Planted \(daysSince(seed.createdAt)) days ago")) {
                    open(seed)
                }
            }
        } header: {
            Text("Dormant seeds")
        } footer: {
            Text("You haven't touched these in a while. Reading them again might show you something new.")
        }
    }

    // MARK: - Data

    private func load() -> ReviewData {
        let now = Date.now
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let seedStage = GrowthStage.seed.rawValue

        var recentDescriptor = FetchDescriptor<Seed>(
            predicate: #Predicate { seed in
                !seed.isArchived && (seed.createdAt >= weekAgo || seed.updatedAt >= weekAgo)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = PromptBudget.candidateLimit

        var dormantDescriptor = FetchDescriptor<Seed>(
            predicate: #Predicate { seed in
                !seed.isArchived
                    && seed.createdAt <= twoWeeksAgo
                    && seed.stageRawValue == seedStage
                    && (seed.lastReviewedAt == nil || seed.lastReviewedAt! <= twoWeeksAgo)
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        dormantDescriptor.fetchLimit = PromptBudget.candidateLimit

        let totalDescriptor = FetchDescriptor<Seed>(predicate: #Predicate { !$0.isArchived })

        let recent = (try? modelContext.fetch(recentDescriptor)) ?? []
        let dormant = (try? modelContext.fetch(dormantDescriptor)) ?? []
        let total = (try? modelContext.fetchCount(totalDescriptor)) ?? (recent.count + dormant.count)
        return ReviewData(totalCount: total, recent: recent, dormant: dormant)
    }

    private func runDigest(with data: ReviewData) async {
        guard data.totalCount > 0, intelligence.availability.isAvailable, !(data.recent.isEmpty && data.dormant.isEmpty) else {
            digest = .skipped
            markReviewed(data.dormant)
            return
        }
        digest = .loading
        do {
            let result = try await intelligence.weeklyDigest(
                recent: data.recent.map(\.snapshot),
                dormant: data.dormant.map(\.snapshot)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { digest = .ready(result) }
            let seeds = data.seedsByID
            markReviewed(result.resurfacedSeedIDs.compactMap { seeds[$0] })
        } catch is CancellationError {
            return
        } catch {
            withAnimation(.snappy) { digest = .skipped }
            markReviewed(data.dormant)
        }
    }

    /// 画面に出した眠っている種に、レビュー済みの印を付ける。
    private func markReviewed(_ seeds: [Seed]) {
        guard !seeds.isEmpty else { return }
        let now = Date.now
        for seed in seeds {
            seed.lastReviewedAt = now
        }
        try? modelContext.save()
    }

    private func open(_ seed: Seed) {
        dismiss()
        router.showSeed(id: seed.id)
    }

    private func daysSince(_ date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0)
    }
}

// MARK: - Preview

#Preview("AI あり") {
    let container = PersistenceController.makePreviewContainer()
    let context = container.mainContext
    let old = Seed(body: "駅の待ち時間に 3 分で読める、地元の歴史の小話を配信する", createdAt: .now.addingTimeInterval(-20 * 86_400))
    context.insert(old)
    let older = Seed(body: "冷蔵庫の中身を撮ると賞味期限を並べてくれるカメラ", createdAt: .now.addingTimeInterval(-40 * 86_400))
    context.insert(older)
    return WeeklyReviewView()
        .modelContainer(container)
        .environment(AppRouter())
        .environment(\.ideaIntelligence, FoundationModelsIntelligence())
}

#Preview("AI なし") {
    let container = PersistenceController.makePreviewContainer()
    let old = Seed(body: "駅の待ち時間に 3 分で読める、地元の歴史の小話を配信する", createdAt: .now.addingTimeInterval(-20 * 86_400))
    container.mainContext.insert(old)
    return WeeklyReviewView()
        .modelContainer(container)
        .environment(AppRouter())
        .environment(\.ideaIntelligence, UnavailableIdeaIntelligence())
}

#Preview("種なし") {
    WeeklyReviewView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
        .environment(AppRouter())
        .environment(\.ideaIntelligence, UnavailableIdeaIntelligence())
}
