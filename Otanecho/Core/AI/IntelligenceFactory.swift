import Foundation

/// 実行環境に応じて IdeaIntelligence の実装を選ぶ。
/// 端末の対応可否は FoundationModelsIntelligence が `availability` で毎回動的に判定するため、ここでは分岐しない。
enum IntelligenceFactory {
    static func make() -> any IdeaIntelligence {
        #if DEBUG
        // 撮影中は AI を使えないことにして、撮るたびに絵が変わらないようにする
        if let stub = ScreenshotSeeder.intelligence { return stub }
        #endif
        return FoundationModelsIntelligence()
    }
}
