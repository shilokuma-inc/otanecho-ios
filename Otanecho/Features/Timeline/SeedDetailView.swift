import Foundation
import SwiftData
import SwiftUI

/// 種の詳細。本文の直接編集、タグ、深掘り、関連する種を 1 画面にまとめる。
struct SeedDetailView: View {
    @Query private var seeds: [Seed]

    init(seedID: UUID) {
        _seeds = Query(filter: #Predicate<Seed> { $0.id == seedID })
    }

    var body: some View {
        if let seed = seeds.first {
            SeedDetailContent(seed: seed)
        } else {
            ContentUnavailableView(
                "Not found",
                systemImage: "questionmark.circle",
                description: Text("This seed may have been deleted or moved out of the archive.")
            )
        }
    }
}

// MARK: - 本体

private struct SeedDetailContent: View {
    @Bindable var seed: Seed

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.ideaIntelligence) private var intelligence

    @State private var draft = ""
    @State private var pendingSave: Task<Void, Never>?
    @State private var isDeleted = false
    @State private var isDeepening = false
    @State private var isConfirmingDelete = false
    @State private var isAddingTag = false
    @State private var newTag = ""
    @FocusState private var isTagFieldFocused: Bool

    @State private var relatedSeeds: [Seed] = []
    @State private var isLoadingRelated = false

    private static let saveDebounce: Duration = .milliseconds(400)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stageHeader
                bodyEditor
                tagsRow
                deepenButton
                if !seed.sprouts.isEmpty {
                    sproutsSection
                }
                if isLoadingRelated || !relatedSeeds.isEmpty {
                    relatedSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(seed.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menu
            }
        }
        .confirmationDialog("Delete this seed?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                delete()
            }
        } message: {
            Text("Its sprouts will be deleted along with it. This can't be undone.")
        }
        .sheet(isPresented: $isDeepening) {
            // DeepenView は navigationTitle を持つので NavigationStack で包み、閉じるボタンを付ける
            NavigationStack {
                DeepenView(seed: seed)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isDeepening = false }
                        }
                    }
            }
        }
        .onAppear {
            draft = seed.body
        }
        .onChange(of: draft) { _, newValue in
            scheduleSave(newValue)
        }
        .onDisappear {
            flush()
        }
        .task(id: seed.id) {
            await loadRelatedSeeds()
        }
    }

    // MARK: 成長段階

    private var stageHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: seed.stage.systemImage)
                .font(.title)
                .foregroundStyle(seed.stage.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(seed.stage.label)
                    .font(.headline)
                Text(seed.stage.progressHint(answeredCount: seed.answeredSproutCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 本文

    private var bodyEditor: some View {
        TextEditor(text: $draft)
            .font(.body)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120, alignment: .top)
            .padding(4)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Body")
    }

    // MARK: タグ

    private var tagsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(seed.tags, id: \.self) { tag in
                    TagCapsule(text: tag)
                        .contextMenu {
                            Button("Remove tag", systemImage: "trash", role: .destructive) {
                                removeTag(tag)
                            }
                        }
                }
                if isAddingTag {
                    TextField("Tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 120)
                        .focused($isTagFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { commitNewTag() }
                        .onChange(of: isTagFieldFocused) { _, focused in
                            if !focused { commitNewTag() }
                        }
                } else {
                    Button("Add tag", systemImage: "plus") {
                        isAddingTag = true
                        isTagFieldFocused = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 深掘り

    private var deepenButton: some View {
        Button {
            flush()
            isDeepening = true
        } label: {
            Label("Grow", systemImage: "leaf")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private var sproutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprouts")
                .font(.headline)
            ForEach(seed.sprouts.sorted { $0.createdAt < $1.createdAt }) { sprout in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sprout.question)
                        .font(.subheadline.weight(.medium))
                    if sprout.isAnswered, let answer = sprout.answer {
                        Text(answer)
                            .font(.body)
                    } else {
                        Text("Unanswered")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(sprout.isAnswered ? 1 : 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: 関連する種

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Related seeds")
                    .font(.headline)
                if isLoadingRelated {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ForEach(relatedSeeds) { related in
                Button {
                    flush()
                    router.showSeed(id: related.id)
                } label: {
                    SeedRowView(seed: related)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: メニュー

    private var menu: some View {
        Menu {
            Button(
                seed.isPinned ? "Unpin" : "Pin",
                systemImage: seed.isPinned ? "pin.slash" : "pin"
            ) {
                seed.isPinned.toggle()
                save()
            }
            Button("Archive", systemImage: "archivebox") {
                archive()
            }
            ShareLink(item: seed.body) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - 保存

    private func scheduleSave(_ newValue: String) {
        guard !isDeleted else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            persist(newValue)
        }
    }

    private func persist(_ body: String) {
        guard !isDeleted, seed.body != body else { return }
        seed.body = body
        seed.touch()
        save()
    }

    private func flush() {
        pendingSave?.cancel()
        persist(draft)
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("種の保存に失敗: \(error)")
        }
    }

    // MARK: - タグ操作

    private func commitNewTag() {
        defer {
            isAddingTag = false
            newTag = ""
        }
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        guard !seed.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        seed.tags.append(tag)
        seed.touch()
        save()
    }

    private func removeTag(_ tag: String) {
        withAnimation {
            seed.tags.removeAll { $0 == tag }
        }
        seed.touch()
        save()
    }

    // MARK: - アーカイブ・削除

    private func archive() {
        flush()
        seed.isArchived = true
        save()
        dismiss()
    }

    private func delete() {
        pendingSave?.cancel()
        isDeleted = true
        dismiss()
        modelContext.delete(seed)
        save()
    }

    // MARK: - 関連する種

    private func loadRelatedSeeds() async {
        guard intelligence.availability.isAvailable else {
            relatedSeeds = []
            return
        }
        isLoadingRelated = true
        defer { isLoadingRelated = false }

        let selfID = seed.id
        var descriptor = FetchDescriptor<Seed>(
            predicate: #Predicate { $0.isArchived == false && $0.id != selfID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        guard let candidates = try? modelContext.fetch(descriptor), !candidates.isEmpty else {
            relatedSeeds = []
            return
        }

        do {
            let ids = try await intelligence.relatedSeeds(to: seed.snapshot, candidates: candidates.map(\.snapshot))
            let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            relatedSeeds = Array(ids.compactMap { byID[$0] }.prefix(5))
        } catch {
            // 失敗は静かに握りつぶし、セクションごと非表示にする
            relatedSeeds = []
        }
    }
}

#Preview {
    let container = PersistenceController.makePreviewContainer()
    let seed = try? container.mainContext.fetch(FetchDescriptor<Seed>()).first
    NavigationStack {
        SeedDetailView(seedID: seed?.id ?? UUID())
    }
    .environment(AppRouter())
    .modelContainer(container)
}

#Preview("見つからない") {
    NavigationStack {
        SeedDetailView(seedID: UUID())
    }
    .environment(AppRouter())
    .modelContainer(PersistenceController.makePreviewContainer())
}
