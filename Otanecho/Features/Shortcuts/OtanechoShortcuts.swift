import AppIntents

/// Siri・ショートカット・Spotlight から呼び出せるアプリショートカット。
/// インストール直後から「お種帳で種をまく」と話しかけるだけで入力画面が開く。
nonisolated struct OtanechoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureSeedIntent(),
            phrases: [
                "\(.applicationName)で種をまく",
                "\(.applicationName)で書き留める",
                "\(.applicationName)を開いてメモ",
            ],
            shortTitle: "Plant a Seed",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: QuickSaveSeedIntent(),
            phrases: [
                "\(.applicationName)にメモ",
                "\(.applicationName)に書き留める",
                "\(.applicationName)にメモして",
            ],
            shortTitle: "Note to Otanecho",
            systemImageName: "square.and.pencil"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .lime
}
