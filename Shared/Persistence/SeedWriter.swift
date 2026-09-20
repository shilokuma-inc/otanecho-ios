import Foundation
import SwiftData
import WidgetKit

/// 共有拡張・App Intent・音声入力など、アプリ本体の UI を経由しない入り口から種を保存する共通処理。
nonisolated enum SeedWriter {
    enum SaveError: LocalizedError {
        /// 本文が空白のみで保存対象がない
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .emptyBody: "内容が空のため保存できません"
            }
        }
    }

    /// 本文を保存し、保存した種の ID を返す。保存後にウィジェットのタイムラインを更新する。
    /// - Parameters:
    ///   - body: ユーザーが書いた本文。前後の空白・改行は取り除いて保存する。
    ///   - source: どの入り口から保存されたか
    ///   - sourceURL: 共有拡張などから来た場合の元 URL
    ///   - container: 保存先の ModelContainer（App Group 共有ストア）
    /// - Throws: 本文が空白のみなら `SaveError.emptyBody`、保存に失敗すれば SwiftData のエラー
    @MainActor
    @discardableResult
    static func save(
        body: String,
        source: CaptureSource,
        sourceURL: String? = nil,
        container: ModelContainer
    ) throws -> UUID {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SaveError.emptyBody }

        let seed = Seed(body: trimmed, source: source, sourceURL: sourceURL)
        let context = container.mainContext
        context.insert(seed)
        try context.save()

        WidgetCenter.shared.reloadAllTimelines()
        return seed.id
    }
}
