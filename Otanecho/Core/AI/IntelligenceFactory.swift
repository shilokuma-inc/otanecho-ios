import Foundation

/// 実行環境に応じて IdeaIntelligence の実装を選ぶ。
/// 端末の対応可否は FoundationModelsIntelligence が `availability` で毎回動的に判定するため、ここでは分岐しない。
enum IntelligenceFactory {
    static func make() -> any IdeaIntelligence {
        FoundationModelsIntelligence()
    }
}
