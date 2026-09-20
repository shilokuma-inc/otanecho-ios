import Foundation

/// 実行環境に応じて IdeaIntelligence の実装を選ぶ。
/// Foundation Models 実装（FoundationModelsIntelligence）が追加されたら、ここで生成する。
enum IntelligenceFactory {
    static func make() -> any IdeaIntelligence {
        UnavailableIdeaIntelligence(availability: .unknown)
    }
}
