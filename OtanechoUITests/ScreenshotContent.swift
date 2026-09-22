import Foundation

/// スクリーンショットに写すデモデータ。
///
/// 文言は `Resources/screenshot-content.json` が言語ごとに持ち、
/// 並び順・書かれた時刻・種の ID といった言語に依らない部分はここ（`layout`）が持つ。
/// 分けてあるのは、12 言語ぶんの翻訳を差分で追いやすくするため。
struct ScreenshotContent {
    /// 言語に依らない、種の骨格。JSON 側の `seeds` と同じ順・同じ数で対応する。
    private static let layout: [(id: String, minutesAgo: Int)] = [
        // タイムラインの「今日」に出る。詳細画面のスクリーンショットもこの種を開く。
        (id: "A8E22C1A-53EE-45EB-AA3C-9FCC56ECF507", minutesAgo: 95),
        // 「昨日」
        (id: "2271D242-E49A-40F6-85AD-BE32B961CA5D", minutesAgo: 1_510),
        // 3 日前。日付の見出しが出る
        (id: "652B1931-AFC7-4CEC-A5BC-11DBE184F0D1", minutesAgo: 4_240),
    ]

    /// 詳細画面のスクリーンショットで開く種。
    static var featuredSeedID: String { layout[0].id }

    // MARK: - JSON の形

    private struct Catalog: Decodable {
        let languages: [String: Localized]
    }

    private struct Localized: Decodable {
        /// 入力画面のスクリーンショットに入れておく本文。
        let capture: String
        let seeds: [LocalizedSeed]
    }

    private struct LocalizedSeed: Decodable {
        let title: String
        let body: String
        let tags: [String]
        let sprouts: [LocalizedSprout]
    }

    private struct LocalizedSprout: Decodable {
        let question: String
        /// null なら未回答。詳細画面で未回答の見え方も一緒に写すために使う。
        let answer: String?
    }

    // MARK: - 読み込み

    /// 入力画面に入れておく本文。
    let captureText: String
    /// アプリへ渡すデモデータ（JSON 文字列）。
    let payload: String

    /// 指定した言語のデモデータを読む。用意が無ければ `XCTFail` ではなくエラーを投げる。
    static func load(language: String) throws -> ScreenshotContent {
        let bundle = Bundle(for: ScreenshotUITests.self)
        guard let url = bundle.url(forResource: "screenshot-content", withExtension: "json") else {
            throw Failure("screenshot-content.json がテストバンドルに入っていない")
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        guard let (key, localized) = resolve(language: language, in: catalog.languages) else {
            let available = catalog.languages.keys.sorted().joined(separator: ", ")
            throw Failure("screenshot-content.json に \(language) のデモデータが無い（あるのは \(available)）")
        }
        guard localized.seeds.count == layout.count else {
            throw Failure("\(key) の種が \(localized.seeds.count) 件。layout の \(layout.count) 件と合わせること")
        }

        let seeds = zip(layout, localized.seeds).map { entry, seed in
            AppSeed(
                id: entry.id,
                minutesAgo: entry.minutesAgo,
                title: seed.title,
                body: seed.body,
                tags: seed.tags,
                sprouts: seed.sprouts.map { AppSprout(question: $0.question, answer: $0.answer) }
            )
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(AppPayload(seeds: seeds))
        guard let payload = String(data: data, encoding: .utf8) else {
            throw Failure("デモデータを JSON 文字列にできなかった")
        }
        return ScreenshotContent(captureText: localized.capture, payload: payload)
    }

    /// テストランナーのロケールから、JSON に載っている言語キーを探す。
    ///
    /// `-testLanguage` に渡した値がそのまま返ってくるのが普通だが、
    /// OS 側で地域が足されたり（`pt-BR` → `pt-BR-BR`）落とされたり（`pt-BR` → `pt`）しても
    /// 拾えるようにしてある。ここで取りこぼすと、英語の作例のまま他言語として上がってしまう。
    private static func resolve(
        language: String,
        in catalog: [String: Localized]
    ) -> (key: String, value: Localized)? {
        if let exact = catalog[language] { return (language, exact) }

        // 後ろの副タグを 1 つずつ落としながら探す（pt-BR-BR → pt-BR）
        var candidate = language
        while let separator = candidate.lastIndex(of: "-") {
            candidate = String(candidate[..<separator])
            if let value = catalog[candidate] { return (candidate, value) }
        }

        // 逆に地域が落ちた場合（pt → pt-BR）。複数該当しないよう辞書順で 1 つに決める
        let prefix = candidate + "-"
        if let key = catalog.keys.filter({ $0.hasPrefix(prefix) }).sorted().first,
           let value = catalog[key] {
            return (key, value)
        }
        return nil
    }

    // MARK: - アプリへ渡す形（ScreenshotSeeder.Content と対になる）

    private struct AppPayload: Encodable {
        let seeds: [AppSeed]
    }

    private struct AppSeed: Encodable {
        let id: String
        let minutesAgo: Int
        let title: String
        let body: String
        let tags: [String]
        let sprouts: [AppSprout]
    }

    private struct AppSprout: Encodable {
        let question: String
        let answer: String?
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
