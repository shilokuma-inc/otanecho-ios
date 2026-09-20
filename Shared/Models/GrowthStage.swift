import Foundation

/// アイデアの成長段階。深掘りの回答数に応じて進む。
nonisolated enum GrowthStage: Int, Codable, CaseIterable, Sendable, Comparable {
    /// 書き留めたばかりの種
    case seed = 0
    /// 深掘りに 1 回以上答えた芽
    case sprout = 1
    /// 深掘りに 3 回以上答え、形になってきた木
    case tree = 2

    static func < (lhs: GrowthStage, rhs: GrowthStage) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .seed: "種"
        case .sprout: "芽"
        case .tree: "木"
        }
    }

    var systemImage: String {
        switch self {
        case .seed: "circle.dotted"
        case .sprout: "leaf"
        case .tree: "tree"
        }
    }

    /// 回答済みの深掘り数から段階を決める。
    static func stage(forAnsweredCount count: Int) -> GrowthStage {
        switch count {
        case ..<1: .seed
        case 1..<3: .sprout
        default: .tree
        }
    }
}
