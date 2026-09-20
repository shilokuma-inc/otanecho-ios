import Foundation
import SwiftUI

/// AI が生成するタイトルとタグ。
nonisolated struct SeedEnrichment: Sendable, Equatable {
    var title: String
    var tags: [String]
}

/// 深掘りの問い。
nonisolated struct DeepeningQuestion: Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var question: String
    /// 問いの狙い（前提を疑う / 対象を具体化する / 最小の一歩を決める など）
    var intent: String
}

/// 週次レビューのダイジェスト。
nonisolated struct WeeklyDigest: Sendable, Equatable {
    /// 今週の傾向を 2〜3 文で
    var summary: String
    /// 放置されている種のうち、もう一度見てほしいもの
    var resurfacedSeedIDs: [UUID]
    /// 意外な組み合わせの提案
    var combinations: [Combination]

    nonisolated struct Combination: Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var seedIDs: [UUID]
        var proposal: String
    }
}

/// AI が利用できない理由。UI で静かに非表示にするための判定に使う。
nonisolated enum IntelligenceAvailability: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    var isAvailable: Bool { self == .available }
}

/// アイデアを育てる AI 機能の抽象。実装は Foundation Models だが、非対応端末用のスタブとテスト用モックも差し替えられる。
nonisolated protocol IdeaIntelligence: Sendable {
    var availability: IntelligenceAvailability { get }

    /// 本文からタイトルとタグを生成する。
    func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment

    /// 深掘りの問いを最大 3 つ返す。過去の問答があれば踏まえる。
    func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion]

    /// 候補の中から関連の強い種の ID を返す（関連が強い順）。
    func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID]

    /// 週次レビューのダイジェストを生成する。
    func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest
}

/// 非対応端末・未有効化のときに使うスタブ。すべて利用不可を返す。
nonisolated struct UnavailableIdeaIntelligence: IdeaIntelligence {
    var availability: IntelligenceAvailability

    init(availability: IntelligenceAvailability = .deviceNotEligible) {
        self.availability = availability
    }

    func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment {
        throw IdeaIntelligenceError.unavailable(availability)
    }

    func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion] {
        throw IdeaIntelligenceError.unavailable(availability)
    }

    func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID] {
        throw IdeaIntelligenceError.unavailable(availability)
    }

    func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest {
        throw IdeaIntelligenceError.unavailable(availability)
    }
}

nonisolated enum IdeaIntelligenceError: Error, Sendable, Equatable {
    case unavailable(IntelligenceAvailability)
    case emptyInput
    case generationFailed(String)
}

extension EnvironmentValues {
    /// 画面から AI 機能を呼ぶための環境値。
    @Entry var ideaIntelligence: any IdeaIntelligence = UnavailableIdeaIntelligence()
}
