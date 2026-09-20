import Foundation

/// AI 処理やウィジェットに渡すための Sendable な値表現。@Model をスレッド越しに渡さないために使う。
nonisolated struct SeedSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var body: String
    var title: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var stage: GrowthStage
    var sprouts: [SproutSnapshot]

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "（無題）" : String(trimmed.prefix(40))
    }
}

nonisolated struct SproutSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var question: String
    var answer: String?
}
