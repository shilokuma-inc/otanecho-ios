import AppIntents
import Foundation

/// 「お種帳にメモ」: アプリを開かずに、渡された内容をそのまま種として保存する。
/// Siri に話しかけて音声で保存する用途が中心。
struct QuickSaveSeedIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "お種帳にメモ"
    nonisolated static let description = IntentDescription("アプリを開かずに、話した内容や渡されたテキストを種として保存します。")
    nonisolated static let openAppWhenRun = false

    @Parameter(title: "内容", requestValueDialog: "何を書き留めますか？")
    var text: String

    nonisolated init() {}

    nonisolated init(text: String) {
        self.text = text
    }

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("\(\.$text) をお種帳にメモ")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SeedWriter.save(body: text, source: .siri, container: PersistenceController.makeContainer())
        } catch SeedWriter.SaveError.emptyBody {
            throw $text.needsValueError("何を書き留めますか？")
        }
        return .result(dialog: "書き留めました")
    }
}
