import Foundation
import Testing
@testable import Otanecho

struct TemplateQuestionsTests {
    /// 結果を再現できるように、シードを固定した乱数を使う（SplitMix64）。
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    private static let seeds: [UInt64] = Array(0..<50)

    @Test func hasTwoQuestionsForEveryIntent() {
        let all = TemplateQuestions.all

        #expect(all.count == 10)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.localizedText)).count == all.count)
        for intent in QuestionIntent.allCases {
            #expect(all.filter { $0.intent == intent }.count == 2, "\(intent) の問いは 2 本")
        }
    }

    @Test(arguments: seeds)
    func picksThreeQuestionsWithDistinctIntents(seed: UInt64) {
        var generator = SeededGenerator(state: seed)

        let picked = TemplateQuestions.pick(excludingIDs: [], using: &generator)

        #expect(picked.count == TemplateQuestions.questionsPerRound)
        #expect(Set(picked.map(\.intent)).count == picked.count)
    }

    @Test(arguments: seeds)
    func neverPicksQuestionsAlreadyUsedForTheSeed(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        // 各狙いの 1 本目を使い終えた状態
        let usedIDs = Set(TemplateQuestions.all.filter { $0.id.hasSuffix(".1") }.map(\.id))

        let picked = TemplateQuestions.pick(excludingIDs: usedIDs, using: &generator)

        #expect(picked.count == TemplateQuestions.questionsPerRound)
        #expect(picked.allSatisfy { !usedIDs.contains($0.id) })
        #expect(Set(picked.map(\.intent)).count == picked.count)
    }

    /// 端末の言語を切り替えると保存時と文が変わるが、ID で照合するので同じ問いは出ない。
    @Test func excludesByIDEvenWhenTheSavedTextNoLongerMatches() {
        var generator = SeededGenerator(state: 3)
        let usedIDs = Set(TemplateQuestions.all.map(\.id))
        // 別の言語で保存された文のつもり。今の言語のどの問いとも一致しない
        let legacyTexts: Set<String> = ["A question saved in another language"]

        let picked = TemplateQuestions.pick(excludingIDs: usedIDs, legacyTexts: legacyTexts, using: &generator)

        #expect(picked.isEmpty)
    }

    /// `templateID` を持たない古い `Sprout` は、問いの文で照合して除外する。
    @Test(arguments: seeds)
    func excludesLegacySproutsByText(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        let legacyTexts = Set(TemplateQuestions.all.filter { $0.id.hasSuffix(".1") }.map(\.localizedText))

        let picked = TemplateQuestions.pick(excludingIDs: [], legacyTexts: legacyTexts, using: &generator)

        #expect(picked.count == TemplateQuestions.questionsPerRound)
        #expect(picked.allSatisfy { !legacyTexts.contains($0.localizedText) })
    }

    /// 答え終えた狙いは選ばれず、残りの狙いだけで出せる分を返す。
    @Test(arguments: seeds)
    func returnsFewerWhenOnlyAFewIntentsRemain(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        let remainingIntents: Set<QuestionIntent> = [.narrowTheTarget, .listObstacles]
        let usedIDs = Set(TemplateQuestions.all.filter { !remainingIntents.contains($0.intent) }.map(\.id))

        let picked = TemplateQuestions.pick(excludingIDs: usedIDs, using: &generator)

        #expect(picked.count == remainingIntents.count)
        #expect(Set(picked.map(\.intent)) == remainingIntents)
    }

    @Test func returnsNothingOnceEveryQuestionIsUsed() {
        var generator = SeededGenerator(state: 1)
        let usedIDs = Set(TemplateQuestions.all.map(\.id))

        #expect(TemplateQuestions.pick(excludingIDs: usedIDs, using: &generator).isEmpty)
    }

    /// 保存済みの問いに前後の空白が付いていても、使用済みとして扱う。
    @Test func ignoresSurroundingWhitespaceWhenExcluding() {
        var generator = SeededGenerator(state: 2)
        let legacyTexts = Set(TemplateQuestions.all.map { " \($0.localizedText)\n" })

        #expect(TemplateQuestions.pick(excludingIDs: [], legacyTexts: legacyTexts, using: &generator).isEmpty)
    }

    @Test func storesTheIntentAsItsRawValue() {
        for question in TemplateQuestions.all {
            #expect(QuestionIntent.resolve(question.intent.rawValue) == question.intent)
        }
    }
}
