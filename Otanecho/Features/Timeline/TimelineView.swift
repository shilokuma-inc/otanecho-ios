import Foundation
import SwiftData
import SwiftUI

/// ルートのタイムライン。まいた種を新しい順に並べ、右下の「+」から即座に入力へ移る。
struct TimelineView: View {
    /// 値が変わると一覧を再フェッチする。前面復帰時に外部プロセス（共有拡張など）の追加分を拾うために使う。
    var refreshToken = 0

    @Environment(AppRouter.self) private var router
    @State private var searchText = ""
    @State private var stageFilter: GrowthStage?

    var body: some View {
        SeedListView(searchText: searchText, stageFilter: $stageFilter)
            .id(refreshToken)
            .navigationTitle("お種帳")
            .searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "種を探す")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("週次レビュー", systemImage: "leaf.circle") {
                        router.showWeeklyReview()
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                captureButton
            }
    }

    private var captureButton: some View {
        Button {
            router.showCapture()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("新しい種をまく")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - 一覧本体（@Query を持つ。id を変えると再フェッチされる）

private struct SeedListView: View {
    let searchText: String
    @Binding var stageFilter: GrowthStage?

    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Seed> { $0.isArchived == false },
        sort: \Seed.createdAt,
        order: .reverse
    )
    private var seeds: [Seed]

    var body: some View {
        if seeds.isEmpty {
            ContentUnavailableView {
                Label("最初の種をまきましょう", systemImage: "leaf")
            } description: {
                Text("右下の「+」から、思いついたことをそのまま書き留められます。")
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                Picker("段階", selection: $stageFilter) {
                    Text("すべて").tag(GrowthStage?.none)
                    ForEach(GrowthStage.allCases, id: \.self) { stage in
                        Text(stage.label).tag(Optional(stage))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }

            if filteredSeeds.isEmpty {
                Section {
                    if searchText.isEmpty {
                        ContentUnavailableView("該当する種はありません", systemImage: "magnifyingglass")
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.seeds) { seed in
                            row(for: seed)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    private func row(for seed: Seed) -> some View {
        NavigationLink(value: seed.id) {
            SeedRowView(seed: seed)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(
                seed.isPinned ? "ピン留めを解除" : "ピン留め",
                systemImage: seed.isPinned ? "pin.slash" : "pin"
            ) {
                togglePin(seed)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("アーカイブ", systemImage: "archivebox") {
                archive(seed)
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button(
                seed.isPinned ? "ピン留めを解除" : "ピン留め",
                systemImage: seed.isPinned ? "pin.slash" : "pin"
            ) {
                togglePin(seed)
            }
            Button("アーカイブ", systemImage: "archivebox") {
                archive(seed)
            }
            Divider()
            Button("削除", systemImage: "trash", role: .destructive) {
                delete(seed)
            }
        }
    }

    // MARK: - 絞り込みとセクション分け

    private var filteredSeeds: [Seed] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return seeds.filter { seed in
            if let stageFilter, seed.stage != stageFilter { return false }
            guard !query.isEmpty else { return true }
            if seed.body.localizedStandardContains(query) { return true }
            if let title = seed.title, title.localizedStandardContains(query) { return true }
            return seed.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    private var sections: [TimelineSection] {
        let calendar = Calendar.current
        let visible = filteredSeeds
        var result: [TimelineSection] = []

        let pinned = visible.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(TimelineSection(id: "pinned", title: "ピン留め", seeds: pinned))
        }

        // createdAt 降順で並んでいるので、隣同士を日付でまとめる
        for seed in visible where !seed.isPinned {
            let day = calendar.startOfDay(for: seed.createdAt)
            let id = day.formatted(.iso8601.year().month().day())
            if let last = result.last, last.id == id {
                result[result.count - 1].seeds.append(seed)
            } else {
                result.append(TimelineSection(id: id, title: Self.sectionTitle(for: day, calendar: calendar), seeds: [seed]))
            }
        }
        return result
    }

    private static func sectionTitle(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "今日" }
        if calendar.isDateInYesterday(day) { return "昨日" }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.month().day())
        }
        return day.formatted(.dateTime.year().month().day())
    }

    // MARK: - 操作

    private func togglePin(_ seed: Seed) {
        withAnimation {
            seed.isPinned.toggle()
        }
        save()
    }

    private func archive(_ seed: Seed) {
        withAnimation {
            seed.isArchived = true
        }
        save()
    }

    private func delete(_ seed: Seed) {
        withAnimation {
            modelContext.delete(seed)
        }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("種の保存に失敗: \(error)")
        }
    }
}

private struct TimelineSection: Identifiable {
    let id: String
    let title: String
    var seeds: [Seed]
}

#Preview("サンプルあり") {
    NavigationStack {
        TimelineView()
    }
    .environment(AppRouter())
    .modelContainer(PersistenceController.makePreviewContainer())
}

#Preview("空") {
    NavigationStack {
        TimelineView()
    }
    .environment(AppRouter())
    .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
