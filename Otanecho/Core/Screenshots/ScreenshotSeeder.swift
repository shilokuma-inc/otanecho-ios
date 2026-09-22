#if DEBUG
import Foundation
import SwiftData

/// App Store 用のスクリーンショットを撮るときだけ使う、デモデータの流し込み口。
///
/// `OtanechoUITests/ScreenshotUITests` が、言語ごとのデモ文言と「起動直後に開く画面」を
/// 起動時の環境変数で渡してくる。ここはそれを受け取ってメモリ内ストアに展開するだけで、
/// 環境変数が無ければ何も起きない（通常の起動と完全に同じ経路を通る）。
///
/// 撮影用のデータをアプリ側に持たないのは、文言が 12 言語ぶんあって
/// String Catalog の検証対象にしたくないため。文言は UI テスト側の JSON が持つ。
///
/// `#if DEBUG` で囲ってあるので Release ビルドには 1 行も入らない。
nonisolated enum ScreenshotSeeder {
    /// デモデータ（JSON 文字列）を受け取る環境変数。
    static let contentKey = "OTANECHO_SCREENSHOT_CONTENT"
    /// 起動直後に開く画面を受け取る環境変数。値は otanecho:// のディープリンク。
    static let routeKey = "OTANECHO_SCREENSHOT_ROUTE"

    // MARK: - 受け取る JSON

    private struct Content: Decodable {
        struct SeedSpec: Decodable {
            struct SproutSpec: Decodable {
                let question: String
                /// 未回答の問いは null。詳細画面で「Unanswered」の見え方も撮りたいため残してある。
                let answer: String?
            }

            /// 固定の UUID。UI テストが「この種の詳細を開く」と指示するために使う。
            let id: UUID
            /// いまから何分前に書かれたことにするか。タイムラインの日付見出しを作るために散らす。
            let minutesAgo: Int
            let title: String
            let body: String
            let tags: [String]
            let sprouts: [SproutSpec]
        }

        let seeds: [SeedSpec]
    }

    // MARK: - 流し込み

    /// スクリーンショット用のメモリ内コンテナ。撮影中でなければ nil。
    static func makeContainer() -> ModelContainer? {
        guard let raw = ProcessInfo.processInfo.environment[contentKey] else { return nil }

        let content: Content
        do {
            content = try JSONDecoder().decode(Content.self, from: Data(raw.utf8))
        } catch {
            // ここで黙って通常起動に落とすと、空のタイムラインが撮れて
            // そのまま App Store に上がってしまう。気づけるように落とす。
            preconditionFailure("スクリーンショット用のデモデータを読めなかった: \(error)")
        }

        let container = PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        for spec in content.seeds {
            context.insert(makeSeed(spec))
        }
        do {
            try context.save()
        } catch {
            preconditionFailure("スクリーンショット用のデモデータを保存できなかった: \(error)")
        }
        return container
    }

    private static func makeSeed(_ spec: Content.SeedSpec) -> Seed {
        let createdAt = Date.now.addingTimeInterval(-Double(spec.minutesAgo) * 60)
        let seed = Seed(id: spec.id, body: spec.body, title: spec.title, tags: spec.tags, createdAt: createdAt)
        // AI 処理済みとして扱う。未処理のままだとシミュレータで動かない SeedEnricher が起動時に走る。
        seed.enrichedAt = createdAt

        for (index, sproutSpec) in spec.sprouts.enumerated() {
            // 表示順は createdAt 昇順なので、JSON に書いた順に並ぶよう 1 分ずつずらす
            let sproutCreatedAt = createdAt.addingTimeInterval(Double(index + 1) * 60)
            let sprout = Sprout(question: sproutSpec.question, createdAt: sproutCreatedAt)
            if let answer = sproutSpec.answer {
                sprout.answer = answer
                sprout.answeredAt = sproutCreatedAt
            }
            sprout.seed = seed
            seed.sprouts.append(sprout)
        }
        seed.refreshStage()
        return seed
    }

    // MARK: - 起動直後に開く画面

    /// 起動直後に開く画面。指定が無ければ nil（タイムラインのまま）。
    static var initialLink: DeepLink? {
        guard let raw = ProcessInfo.processInfo.environment[routeKey], !raw.isEmpty else { return nil }
        guard let url = URL(string: raw), let link = DeepLink(url: url) else {
            preconditionFailure("スクリーンショット用の遷移先を解釈できなかった: \(raw)")
        }
        return link
    }

    // MARK: - AI の差し替え

    /// 撮影中に使う AI の代役。撮影中でなければ nil。
    ///
    /// シミュレータでは Foundation Models が動かない。判定を実行時に任せると、
    /// 「使える」と返ってきてから失敗するまでの間だけスピナーが写るなど、
    /// 撮るたびに絵が変わる。撮影中は最初から使えないことにして固定する。
    static var intelligence: (any IdeaIntelligence)? {
        ProcessInfo.processInfo.environment[contentKey] == nil ? nil : UnavailableIntelligence()
    }

    private struct UnavailableIntelligence: IdeaIntelligence {
        var availability: IntelligenceAvailability { .deviceNotEligible }

        func enrich(body: String, existingTags: [String]) async throws -> SeedEnrichment {
            throw CancellationError()
        }

        func deepeningQuestions(for seed: SeedSnapshot) async throws -> [DeepeningQuestion] {
            throw CancellationError()
        }

        func relatedSeeds(to seed: SeedSnapshot, candidates: [SeedSnapshot]) async throws -> [UUID] {
            throw CancellationError()
        }

        func weeklyDigest(recent: [SeedSnapshot], dormant: [SeedSnapshot]) async throws -> WeeklyDigest {
            throw CancellationError()
        }
    }
}
#endif
