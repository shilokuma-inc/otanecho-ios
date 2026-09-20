import Foundation
import SwiftData

/// アイデアの種。1 件のメモに相当する。
@Model
final class Seed {
    #Index<Seed>([\.createdAt], [\.updatedAt], [\.stageRawValue])

    @Attribute(.unique) var id: UUID
    /// ユーザーが書いた本文（そのまま保持する。AI は編集しない）
    var body: String
    /// AI が生成した短いタイトル。未生成なら nil。
    var title: String?
    /// AI が付けたタグ（ユーザーが編集可能）
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var stageRawValue: Int
    var sourceRawValue: String
    /// 共有拡張などから来た場合の元 URL
    var sourceURL: String?
    var isArchived: Bool
    var isPinned: Bool
    /// 週次レビューで最後に表示した日時
    var lastReviewedAt: Date?
    /// タグ・タイトルの AI 処理が完了した日時。nil なら未処理。
    var enrichedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Sprout.seed)
    var sprouts: [Sprout]

    init(
        id: UUID = UUID(),
        body: String,
        title: String? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        source: CaptureSource = .app,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.body = body
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.stageRawValue = GrowthStage.seed.rawValue
        self.sourceRawValue = source.rawValue
        self.sourceURL = sourceURL
        self.isArchived = false
        self.isPinned = false
        self.lastReviewedAt = nil
        self.enrichedAt = nil
        self.sprouts = []
    }

    var stage: GrowthStage {
        get { GrowthStage(rawValue: stageRawValue) ?? .seed }
        set { stageRawValue = newValue.rawValue }
    }

    var source: CaptureSource {
        get { CaptureSource(rawValue: sourceRawValue) ?? .app }
        set { sourceRawValue = newValue.rawValue }
    }

    /// 一覧表示用のタイトル。AI タイトルがなければ本文の 1 行目。
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "（無題）" : String(trimmed.prefix(40))
    }

    var answeredSproutCount: Int {
        sprouts.filter { !($0.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    /// 回答数に基づいて段階を更新する。
    func refreshStage() {
        stage = GrowthStage.stage(forAnsweredCount: answeredSproutCount)
    }

    func touch() {
        updatedAt = .now
    }

    var snapshot: SeedSnapshot {
        SeedSnapshot(
            id: id,
            body: body,
            title: title,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            stage: stage,
            sprouts: sprouts
                .sorted { $0.createdAt < $1.createdAt }
                .map { SproutSnapshot(id: $0.id, question: $0.question, answer: $0.answer) }
        )
    }
}
