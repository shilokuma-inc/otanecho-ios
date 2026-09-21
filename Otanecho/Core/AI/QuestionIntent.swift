import Foundation

/// 深掘りの問いの「狙い」。
///
/// 次の 3 つを意図的に分けている。
/// - `rawValue`: 保存する値。モデルの出力言語や UI の言語が変わっても揺れない識別子。
/// - `modelValue`: モデルに `.anyOf` で選ばせる値。出力言語に関係なく英語で固定する。
/// - `label`: 画面に出す値。String Catalog で翻訳する。
///
/// 分けておかないと、端末の言語を変えたときに保存済みの問いの狙いが表示できなくなる。
nonisolated enum QuestionIntent: String, CaseIterable, Sendable {
    case challengeAssumptions
    case narrowTheTarget
    case decideSmallestStep
    case compareSimilarCases
    case listObstacles

    /// モデルに選ばせる選択肢。英語で固定する。
    var modelValue: String {
        switch self {
        case .challengeAssumptions: "Challenge the assumptions"
        case .narrowTheTarget: "Make the target concrete"
        case .decideSmallestStep: "Decide the smallest first step"
        case .compareSimilarCases: "Compare with similar cases"
        case .listObstacles: "Surface the obstacles"
        }
    }

    /// 画面に出すラベル。`modelValue` と同じ英語だが、こちらは翻訳される。
    /// 文言を変えるときは両方を揃えること。
    var label: LocalizedStringResource {
        switch self {
        case .challengeAssumptions: "Challenge the assumptions"
        case .narrowTheTarget: "Make the target concrete"
        case .decideSmallestStep: "Decide the smallest first step"
        case .compareSimilarCases: "Compare with similar cases"
        case .listObstacles: "Surface the obstacles"
        }
    }

    /// 日本語版（英語ソース化する前）が保存していた表記。
    /// 既存ユーザーの問いを表示できるように残している。
    private var legacyJapaneseValue: String {
        switch self {
        case .challengeAssumptions: "前提を疑う"
        case .narrowTheTarget: "対象を具体化する"
        case .decideSmallestStep: "最小の一歩を決める"
        case .compareSimilarCases: "似た事例と比べる"
        case .listObstacles: "障害を洗い出す"
        }
    }

    /// モデルに渡す選択肢の一覧。
    static let modelValues = allCases.map(\.modelValue)

    /// モデルの出力や保存済みの値から狙いを解決する。
    /// 前後の空白、「Intent: 」のような前置き、旧日本語表記を吸収する。解決できなければ nil。
    static func resolve(_ raw: String) -> QuestionIntent? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let stored = QuestionIntent(rawValue: trimmed) { return stored }
        if let exact = allCases.first(where: {
            $0.modelValue.caseInsensitiveCompare(trimmed) == .orderedSame || $0.legacyJapaneseValue == trimmed
        }) {
            return exact
        }

        // 短すぎる文字列で部分一致を試すと無関係な狙いに寄ってしまうので、ある程度の長さを条件にする
        guard trimmed.count >= 4 else { return nil }
        return allCases.first {
            trimmed.localizedCaseInsensitiveContains($0.modelValue) || trimmed.contains($0.legacyJapaneseValue)
        }
    }

    /// `Sprout.intent` に保存する値。解決できなければモデルの出力をそのまま残す。
    static func storedValue(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolve(trimmed)?.rawValue ?? trimmed
    }
}
