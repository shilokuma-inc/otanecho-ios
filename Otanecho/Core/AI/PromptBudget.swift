import Foundation

/// オンデバイスモデルのコンテキスト（約 4,096 トークン）に収めるための入力切り詰めヘルパー。
/// Foundation Models 本体には依存しないので、単体テストで検証できる。
nonisolated enum PromptBudget {
    /// 本文として渡す最大文字数
    static let bodyLimit = 1_200
    /// 候補リストに載せる最大件数
    static let candidateLimit = 30
    /// 候補 1 件あたりのプレビュー最大文字数
    static let previewLimit = 80
    /// 過去の問答を渡す最大件数
    static let sproutLimit = 6
    /// 問い・答え 1 件あたりのプレビュー最大文字数
    static let sproutPreviewLimit = 120

    // MARK: - 生成テキストの表示上限

    /// AI が付けるタイトルの上限
    static func titleLimit(for locale: Locale = .current) -> Int { scaled(30, for: locale) }
    /// 深掘りの問いの上限
    static func questionLimit(for locale: Locale = .current) -> Int { scaled(60, for: locale) }
    /// 掛け合わせの提案の上限
    static func proposalLimit(for locale: Locale = .current) -> Int { scaled(80, for: locale) }

    /// 表記体系に合わせて上限を伸ばす。
    ///
    /// 同じ内容を書いても、表意文字を使う言語は英語やロシア語よりずっと少ない文字数で収まる。
    /// 日本語向けに決めた文字数をそのまま当てると英語のタイトルが途中で切れるため、倍率を変える。
    static func scaled(_ base: Int, for locale: Locale) -> Int {
        usesCompactScript(locale) ? base : base * 2
    }

    /// 1 文字あたりの情報量が大きい表記体系か。
    static func usesCompactScript(_ locale: Locale) -> Bool {
        guard let code = locale.language.languageCode?.identifier else { return false }
        return ["ja", "zh", "yue", "ko"].contains(code)
    }

    /// 末尾を「…」で切り詰める。結果は必ず `limit` 文字以内。
    static func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return "" }
        guard trimmed.count > limit else { return trimmed }
        guard limit > 1 else { return "…" }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    /// 改行や連続する空白を 1 つの半角スペースにまとめて 1 行にし、`limit` 文字以内に切り詰める。
    static func preview(_ text: String, limit: Int = previewLimit) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return truncate(collapsed, limit: limit)
    }

    /// 本文を切り詰める。
    static func body(_ text: String) -> String {
        truncate(text, limit: bodyLimit)
    }

    /// 候補を最大件数に絞る。
    static func candidates<T>(_ items: [T], limit: Int = candidateLimit) -> [T] {
        Array(items.prefix(limit))
    }

    /// 種を 1 始まりの番号付きリストにする。番号はモデルに UUID を触らせないための代替キー。
    /// 例: `1. タイトル — 本文プレビュー`
    static func numberedList(_ seeds: [SeedSnapshot], startingAt start: Int = 1) -> String {
        seeds.enumerated().map { offset, seed in
            let title = preview(seed.displayTitle, limit: 40)
            let body = preview(seed.body)
            if body.isEmpty || body == title {
                return "\(start + offset). \(title)"
            }
            return "\(start + offset). \(title) — \(body)"
        }
        .joined(separator: "\n")
    }
}

/// モデルが返す 1 始まりの番号を、渡した候補の UUID に戻す。
nonisolated enum IndexMapper {
    /// 範囲外・重複を除いて、順序を保ったまま UUID に変換する。
    /// - Parameters:
    ///   - indices: モデルが返した 1 始まりの番号
    ///   - items: 番号付きリストに載せた候補（順序はリストと同じ）
    ///   - limit: 返す最大件数
    static func ids(from indices: [Int], in items: [SeedSnapshot], limit: Int = .max) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for index in indices {
            guard index >= 1, index <= items.count else { continue }
            let id = items[index - 1].id
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
            if result.count >= limit { break }
        }
        return result
    }

    /// 番号を `range`（1 始まり・閉区間）の中に限定してから UUID に変換する。
    /// 例: recent と dormant を 1 つのリストにした場合、dormant の番号だけを受け付ける。
    static func ids(from indices: [Int], in items: [SeedSnapshot], allowing range: ClosedRange<Int>, limit: Int = .max) -> [UUID] {
        ids(from: indices.filter { range.contains($0) }, in: items, limit: limit)
    }
}

/// タグの正規化。既存タグと表記を揃え、重複を除く。
nonisolated enum TagNormalizer {
    static let maxCount = 4

    /// 比較用のキー。前後空白を除き、内部の空白を潰し、大文字小文字を無視する。
    static func key(_ tag: String) -> String {
        tag.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined()
            .lowercased()
    }

    /// 表示用に整える。先頭の `#` と前後の空白を除く。
    static func clean(_ tag: String) -> String {
        var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("#") || trimmed.hasPrefix("＃") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 生成タグを整える。既存タグに（大文字小文字・空白を無視して）一致するものがあれば既存の表記を採用し、
    /// 重複と空文字を除いて最大 `maxCount` 件返す。
    static func merge(generated: [String], existing: [String], maxCount: Int = maxCount) -> [String] {
        let existingByKey = Dictionary(
            existing.map { (key(clean($0)), clean($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        var result: [String] = []
        for raw in generated {
            let cleaned = clean(raw)
            guard !cleaned.isEmpty else { continue }
            let normalizedKey = key(cleaned)
            guard !normalizedKey.isEmpty, !seen.contains(normalizedKey) else { continue }
            seen.insert(normalizedKey)
            result.append(existingByKey[normalizedKey] ?? cleaned)
            if result.count >= maxCount { break }
        }
        return result
    }
}
