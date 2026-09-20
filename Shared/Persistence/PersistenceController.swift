import Foundation
import SwiftData

/// SwiftData の ModelContainer を生成する。アプリ・ウィジェット・共有拡張で同じ App Group 内ストアを使う。
nonisolated enum PersistenceController {
    static let schema = Schema([Seed.self, Sprout.self])

    static var storeURL: URL {
        AppGroup.containerURL.appending(path: "Otanecho.store")
    }

    /// 本番用コンテナ。失敗した場合はメモリ内ストアにフォールバックしてアプリを落とさない。
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        do {
            let config = inMemory
                ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                : ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            assertionFailure("ModelContainer の生成に失敗: \(error)")
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    /// プレビュー・テスト用のサンプル入りコンテナ。
    @MainActor static func makePreviewContainer() -> ModelContainer {
        let container = makeContainer(inMemory: true)
        let context = container.mainContext
        let samples: [(String, [String], Int)] = [
            ("通勤中に聴くポッドキャストを、聴きながらメモできるアプリ", ["アプリ", "音声"], 0),
            ("週に一度、冷蔵庫の残り物だけで作るレシピを提案してくれるサービス", ["食", "生活"], 1),
            ("子どもの『なんで？』を記録して、成長とともに答えを更新していく日記", ["育児", "記録"], 3),
        ]
        for (body, tags, answered) in samples {
            let seed = Seed(body: body, tags: tags)
            seed.title = String(body.prefix(18))
            seed.enrichedAt = .now
            context.insert(seed)
            for index in 0..<max(answered, 1) {
                let sprout = Sprout(question: "この案で一番助かるのは誰ですか？（\(index + 1)）", intent: "対象を具体化する")
                if index < answered {
                    sprout.answer = "毎日忙しくて、考える時間が細切れになっている人。"
                    sprout.answeredAt = .now
                }
                sprout.seed = seed
                seed.sprouts.append(sprout)
            }
            seed.refreshStage()
        }
        return container
    }
}
