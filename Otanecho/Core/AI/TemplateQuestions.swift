import Foundation

/// AI を使わずに出せる、固定文の深掘りの問い。
nonisolated struct TemplateQuestion: Sendable, Identifiable {
    /// 狙いと番号から作る識別子。文言を直しても変わらない。
    let id: String
    let intent: QuestionIntent
    let text: LocalizedStringResource

    /// 今の言語での問いの文。`Sprout.question` にはこの値が保存される。
    var localizedText: String {
        String(localized: text)
    }
}

/// Apple Intelligence が使えない端末でも深掘りが回るように用意した、テンプレートの問い。
///
/// 成長段階は回答数だけで決まるので、問いが 1 つも出ないとその端末の種は永遠に「種」のままになる。
/// 判断基準 4（非対応端末でも完全に成立）を満たすため、種の中身を知らなくても機能する問いを
/// `QuestionIntent` の狙いごとに 2 本ずつ持つ。
nonisolated enum TemplateQuestions {
    /// 1 回に出す問いの数。AI の深掘りと揃える。
    static let questionsPerRound = 3

    static let all: [TemplateQuestion] = [
        TemplateQuestion(
            id: "challengeAssumptions.1",
            intent: .challengeAssumptions,
            text: "What are you assuming here that might not be true?"
        ),
        TemplateQuestion(
            id: "challengeAssumptions.2",
            intent: .challengeAssumptions,
            text: "If the opposite turned out to be right, what would change?"
        ),
        TemplateQuestion(
            id: "narrowTheTarget.1",
            intent: .narrowTheTarget,
            text: "Who, specifically, is this for?"
        ),
        TemplateQuestion(
            id: "narrowTheTarget.2",
            intent: .narrowTheTarget,
            text: "Who has this problem today, and when does it come up for them?"
        ),
        TemplateQuestion(
            id: "decideSmallestStep.1",
            intent: .decideSmallestStep,
            text: "What's the smallest thing you could try in the next 15 minutes?"
        ),
        TemplateQuestion(
            id: "decideSmallestStep.2",
            intent: .decideSmallestStep,
            text: "What could you do this week to find out whether this is worth pursuing?"
        ),
        TemplateQuestion(
            id: "compareSimilarCases.1",
            intent: .compareSimilarCases,
            text: "Does something similar already exist? How is this different?"
        ),
        TemplateQuestion(
            id: "compareSimilarCases.2",
            intent: .compareSimilarCases,
            text: "Where have you seen something like this work, or fail?"
        ),
        TemplateQuestion(
            id: "listObstacles.1",
            intent: .listObstacles,
            text: "What's most likely to stop this from happening?"
        ),
        TemplateQuestion(
            id: "listObstacles.2",
            intent: .listObstacles,
            text: "What would you need that you don't have yet?"
        ),
    ]

    /// 狙いが重複しないように問いを選ぶ。
    ///
    /// 5 つの狙いから `questionsPerRound` 個を選び、それぞれの狙いの問いから 1 本ずつ出す。
    /// `usedQuestions`（その種で既に出した問いの文）に含まれる問いは出さない。
    /// 残りの問いがある狙いが足りなければ、出せる分だけ返す。
    static func pick<Generator: RandomNumberGenerator>(
        excluding usedQuestions: Set<String>,
        using generator: inout Generator
    ) -> [TemplateQuestion] {
        let used = Set(usedQuestions.map(normalized))
        let remaining = all.filter { !used.contains(normalized($0.localizedText)) }
        let byIntent = Dictionary(grouping: remaining, by: \.intent)

        // 並びを安定させてから混ぜる（Dictionary の順序に依存させない）
        let intents = QuestionIntent.allCases
            .filter { byIntent[$0] != nil }
            .shuffled(using: &generator)
            .prefix(questionsPerRound)
        return intents.compactMap { byIntent[$0]?.randomElement(using: &generator) }
    }

    static func pick(excluding usedQuestions: Set<String>) -> [TemplateQuestion] {
        var generator = SystemRandomNumberGenerator()
        return pick(excluding: usedQuestions, using: &generator)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
