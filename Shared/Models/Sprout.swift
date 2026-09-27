import Foundation
import SwiftData

/// 深掘りの問いと、それに対するユーザーの答え。
@Model
final class Sprout {
    @Attribute(.unique) var id: UUID
    /// AI が投げかけた問い
    var question: String
    /// 問いの狙い（例: 前提を疑う、対象を具体化する）
    var intent: String?
    /// テンプレートの問いの識別子（例: `listObstacles.1`）。AI が生成した問いは nil。
    /// 言語を切り替えても変わらないので、重複判定はこちらを正とする。
    var templateID: String?
    /// ユーザーの答え。未回答なら nil。
    var answer: String?
    var createdAt: Date
    var answeredAt: Date?
    var seed: Seed?

    init(
        id: UUID = UUID(),
        question: String,
        intent: String? = nil,
        templateID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.question = question
        self.intent = intent
        self.templateID = templateID
        self.answer = nil
        self.createdAt = createdAt
        self.answeredAt = nil
    }

    var isAnswered: Bool {
        !(answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
