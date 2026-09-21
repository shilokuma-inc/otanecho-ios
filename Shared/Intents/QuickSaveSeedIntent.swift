import AppIntents
import Foundation

/// 「お種帳にメモ」: アプリを開かずに、渡された内容をそのまま種として保存する。
/// Siri に話しかけて音声で保存する用途が中心。
struct QuickSaveSeedIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Note to Otanecho"
    nonisolated static let description = IntentDescription("Saves what you say, or the text you pass in, as a seed without opening the app.")
    nonisolated static let openAppWhenRun = false

    @Parameter(title: "Content", requestValueDialog: "What would you like to jot down?")
    var text: String

    nonisolated init() {}

    nonisolated init(text: String) {
        self.text = text
    }

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Note \(\.$text) to Otanecho")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SeedWriter.save(body: text, source: .siri, container: PersistenceController.makeContainer())
        } catch SeedWriter.SaveError.emptyBody {
            throw $text.needsValueError("What would you like to jot down?")
        }
        return .result(dialog: "Jotted it down")
    }
}
