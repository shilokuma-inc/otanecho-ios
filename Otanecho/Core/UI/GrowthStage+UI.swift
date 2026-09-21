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
    func progressHint(answeredCount: Int) -> LocalizedStringResource {
        switch self {
        case .seed:
            let remaining = max(1 - answeredCount, 1)
            return "Answer \(remaining) more questions to sprout"
        case .sprout:
            let remaining = max(3 - answeredCount, 1)
            return "Answer \(remaining) more questions to become a tree"
        case .tree:
            return "Fully grown"
        }
    }
}
