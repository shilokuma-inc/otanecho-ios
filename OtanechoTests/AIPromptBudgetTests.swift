import Foundation
import Testing
@testable import Otanecho

/// AI 層のうち、Foundation Models 本体に依存しない純粋なヘルパーの検証。
struct AIPromptBudgetTests {
    // MARK: - PromptBudget.truncate

    @Test func truncateKeepsShortTextAsIs() {
        #expect(PromptBudget.truncate("短い文", limit: 10) == "短い文")
        #expect(PromptBudget.truncate("  前後の空白は除く  ", limit: 100) == "前後の空白は除く")
    }

    @Test func truncateFitsWithinLimitAndEndsWithEllipsis() {
        let long = String(repeating: "あ", count: 2_000)
        let result = PromptBudget.truncate(long, limit: 1_200)
        #expect(result.count == 1_200)
        #expect(result.hasSuffix("…"))
        #expect(result.dropLast().allSatisfy { $0 == "あ" })
    }

    @Test func truncateHandlesDegenerateLimits() {
        #expect(PromptBudget.truncate("abc", limit: 0).isEmpty)
        #expect(PromptBudget.truncate("abc", limit: 1) == "…")
        #expect(PromptBudget.truncate("abc", limit: 3) == "abc")
        #expect(PromptBudget.truncate("abcd", limit: 3) == "ab…")
    }

    @Test func truncateCountsGraphemeClustersNotBytes() {
        // 絵文字や結合文字が途中で壊れないことを確認する
        let text = String(repeating: "👨‍👩‍👧", count: 10)
        let result = PromptBudget.truncate(text, limit: 5)
        #expect(result.count == 5)
        #expect(result == String(repeating: "👨‍👩‍👧", count: 4) + "…")
    }

    @Test func bodyUsesBodyLimit() {
        let long = String(repeating: "い", count: PromptBudget.bodyLimit + 500)
        #expect(PromptBudget.body(long).count == PromptBudget.bodyLimit)
        #expect(PromptBudget.body("そのまま") == "そのまま")
    }

    // MARK: - PromptBudget.preview

    @Test func previewCollapsesWhitespaceIntoSingleLine() {
        let text = "1 行目\n\n  2 行目\t3 行目   "
        #expect(PromptBudget.preview(text) == "1 行目 2 行目 3 行目")
    }

    @Test func previewRespectsDefaultLimit() {
        let text = String(repeating: "う", count: 300)
        let result = PromptBudget.preview(text)
        #expect(result.count == PromptBudget.previewLimit)
        #expect(result.hasSuffix("…"))
    }

    // MARK: - PromptBudget.candidates / numberedList

    @Test func candidatesAreCappedAtLimit() {
        let items = Array(0..<100)
        #expect(PromptBudget.candidates(items).count == PromptBudget.candidateLimit)
        #expect(PromptBudget.candidates(items) == Array(0..<PromptBudget.candidateLimit))
        #expect(PromptBudget.candidates([1, 2]) == [1, 2])
    }

    @Test func numberedListStartsAtOneAndCanOffset() {
        let seeds = [
            makeSnapshot(body: "通勤中に聴くポッドキャスト"),
            makeSnapshot(body: "冷蔵庫の残り物レシピ", title: "残り物レシピ"),
        ]
        let list = PromptBudget.numberedList(seeds)
        let lines = list.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "1. 通勤中に聴くポッドキャスト")
        #expect(lines[1] == "2. 残り物レシピ — 冷蔵庫の残り物レシピ")

        let offset = PromptBudget.numberedList(seeds, startingAt: 5)
        #expect(offset.hasPrefix("5. "))
        #expect(offset.contains("\n6. "))
    }

    @Test func numberedListTruncatesLongBodies() {
        let seed = makeSnapshot(body: String(repeating: "え", count: 500))
        let line = PromptBudget.numberedList([seed])
        // "1. " + タイトル(40) + " — " + プレビュー(80) を超えない
        #expect(line.count <= 3 + 40 + 3 + PromptBudget.previewLimit)
        #expect(!line.contains("\n"))
    }

    // MARK: - IndexMapper

    @Test func indexMapperConvertsOneBasedIndicesToIDs() {
        let seeds = (0..<3).map { _ in makeSnapshot(body: "x") }
        let ids = IndexMapper.ids(from: [2, 1, 3], in: seeds)
        #expect(ids == [seeds[1].id, seeds[0].id, seeds[2].id])
    }

    @Test func indexMapperDropsOutOfRangeAndDuplicates() {
        let seeds = (0..<3).map { _ in makeSnapshot(body: "x") }
        let ids = IndexMapper.ids(from: [0, 4, -1, 2, 2, 100, 1, 2], in: seeds)
        #expect(ids == [seeds[1].id, seeds[0].id])
    }

    @Test func indexMapperHonorsLimit() {
        let seeds = (0..<10).map { _ in makeSnapshot(body: "x") }
        let ids = IndexMapper.ids(from: Array(1...10), in: seeds, limit: 5)
        #expect(ids.count == 5)
        #expect(ids == seeds.prefix(5).map(\.id))
    }

    @Test func indexMapperReturnsEmptyForEmptyInputs() {
        let seeds = (0..<3).map { _ in makeSnapshot(body: "x") }
        #expect(IndexMapper.ids(from: [], in: seeds).isEmpty)
        #expect(IndexMapper.ids(from: [1, 2], in: []).isEmpty)
    }

    @Test func indexMapperRestrictsToAllowedRange() {
        // recent 2 件 + dormant 3 件 を 1 つのリストにした想定。dormant は 3〜5 番。
        let combined = (0..<5).map { _ in makeSnapshot(body: "x") }
        let ids = IndexMapper.ids(from: [1, 3, 2, 5, 4, 6], in: combined, allowing: 3...5, limit: 2)
        #expect(ids == [combined[2].id, combined[4].id])
    }

    // MARK: - TagNormalizer

    @Test func tagNormalizerReusesExistingSpelling() {
        let result = TagNormalizer.merge(generated: ["swiftui", " Swift UI ", "アプリ"], existing: ["SwiftUI", "デザイン"])
        #expect(result == ["SwiftUI", "アプリ"])
    }

    @Test func tagNormalizerRemovesDuplicatesEmptyAndHashes() {
        let result = TagNormalizer.merge(generated: ["#育児", "育児", "", "  ", "＃記録", "記 録"], existing: [])
        #expect(result == ["育児", "記録"])
    }

    @Test func tagNormalizerCapsAtMaxCount() {
        let result = TagNormalizer.merge(generated: ["a", "b", "c", "d", "e", "f"], existing: [])
        #expect(result == ["a", "b", "c", "d"])
        #expect(TagNormalizer.merge(generated: ["a", "b", "c"], existing: [], maxCount: 2) == ["a", "b"])
    }

    @Test func tagNormalizerKeyIgnoresCaseAndWhitespace() {
        #expect(TagNormalizer.key(" Swift UI ") == TagNormalizer.key("swiftui"))
        #expect(TagNormalizer.key("食") != TagNormalizer.key("生活"))
    }

    // MARK: - QuestionIntent

    @Test func questionIntentResolvesModelOutput() {
        #expect(QuestionIntent.resolve("Challenge the assumptions") == .challengeAssumptions)
        #expect(QuestionIntent.resolve(" make the target concrete ") == .narrowTheTarget)
        // モデルが前置きを付けて返すことがある
        #expect(QuestionIntent.resolve("Intent: Decide the smallest first step") == .decideSmallestStep)
    }

    @Test func questionIntentResolvesStoredAndLegacyValues() {
        // 保存値（rawValue）から戻せる
        #expect(QuestionIntent.resolve("compareSimilarCases") == .compareSimilarCases)
        // 英語ソース化する前に保存された日本語表記も表示できる
        #expect(QuestionIntent.resolve("前提を疑う") == .challengeAssumptions)
        #expect(QuestionIntent.resolve("狙い: 最小の一歩を決める") == .decideSmallestStep)
    }

    @Test func questionIntentReturnsNilForUnknownValues() {
        #expect(QuestionIntent.resolve("") == nil)
        #expect(QuestionIntent.resolve("   ") == nil)
        #expect(QuestionIntent.resolve("独自の狙い") == nil)
        // 短すぎる文字列で部分一致に寄せない
        #expect(QuestionIntent.resolve("the") == nil)
    }

    @Test func questionIntentStoresStableIdentifier() {
        #expect(QuestionIntent.storedValue(for: "Surface the obstacles") == "listObstacles")
        #expect(QuestionIntent.storedValue(for: "障害を洗い出す") == "listObstacles")
        // 寄せられない値は表示を壊さないようそのまま残す
        #expect(QuestionIntent.storedValue(for: " 独自の狙い ") == "独自の狙い")
    }

    @Test func questionIntentModelValuesCoverEveryCase() {
        #expect(QuestionIntent.modelValues.count == QuestionIntent.allCases.count)
        #expect(Set(QuestionIntent.modelValues).count == QuestionIntent.allCases.count)
    }

    // MARK: - OutputLanguage

    @Test func outputLanguageUsesEnglishLanguageNames() {
        #expect(OutputLanguage.name(for: Locale(identifier: "ja_JP")) == "Japanese")
        #expect(OutputLanguage.name(for: Locale(identifier: "en_US")) == "English")
        #expect(OutputLanguage.name(for: Locale(identifier: "ru_RU")) == "Russian")
    }

    @Test func outputLanguageKeepsScriptForChinese() {
        // 言語コードだけ渡すと簡体字の端末に繁体字が返ることがあるため、表記体系まで伝える
        #expect(OutputLanguage.name(for: Locale(identifier: "zh_Hans_CN")).contains("Simplified"))
        #expect(OutputLanguage.name(for: Locale(identifier: "zh_Hant_TW")).contains("Traditional"))
    }

    // MARK: - 生成テキストの表示上限

    @Test func generatedTextLimitsDependOnScript() {
        let japanese = Locale(identifier: "ja_JP")
        let english = Locale(identifier: "en_US")

        #expect(PromptBudget.usesCompactScript(japanese))
        #expect(PromptBudget.usesCompactScript(Locale(identifier: "zh_Hans_CN")))
        #expect(PromptBudget.usesCompactScript(Locale(identifier: "ko_KR")))
        #expect(!PromptBudget.usesCompactScript(english))
        #expect(!PromptBudget.usesCompactScript(Locale(identifier: "de_DE")))

        // 表意文字の言語は従来どおり、それ以外は同じ情報量を入れられるよう伸ばす
        #expect(PromptBudget.titleLimit(for: japanese) == 30)
        #expect(PromptBudget.titleLimit(for: english) == 60)
        #expect(PromptBudget.questionLimit(for: english) > PromptBudget.questionLimit(for: japanese))
        #expect(PromptBudget.proposalLimit(for: english) > PromptBudget.proposalLimit(for: japanese))
    }

    // MARK: - Helpers

    private func makeSnapshot(body: String, title: String? = nil) -> SeedSnapshot {
        SeedSnapshot(
            id: UUID(),
            body: body,
            title: title,
            tags: [],
            createdAt: .now,
            updatedAt: .now,
            stage: .seed,
            sprouts: []
        )
    }
}
