import SwiftUI

extension GrowthStage {
    /// 段階を表す色。種は控えめ、芽は緑、木は茶系。
    var tint: Color {
        switch self {
        case .seed: .secondary
        case .sprout: .green
        case .tree: .brown
        }
    }

    /// 次の段階に進むまでの案内文。
    func progressHint(answeredCount: Int) -> String {
        switch self {
        case .seed:
            "あと \(max(1 - answeredCount, 1)) 回答えると芽になります"
        case .sprout:
            "あと \(max(3 - answeredCount, 1)) 回答えると木になります"
        case .tree:
            "しっかり育ちました"
        }
    }
}
