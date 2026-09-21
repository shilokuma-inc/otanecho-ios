import AppIntents

/// Siri・ショートカット・Spotlight から呼び出せるアプリショートカット。
/// インストール直後から「お種帳で種をまく」と話しかけるだけで入力画面が開く。
nonisolated struct OtanechoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureSeedIntent(),
            phrases: [
                "Plant a seed in \(.applicationName)",
                "Jot something down in \(.applicationName)",
                "Open \(.applicationName) and take a note",
            ],
            shortTitle: "Plant a Seed",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: QuickSaveSeedIntent(),
            phrases: [
                "Note to \(.applicationName)",
                "Jot it down in \(.applicationName)",
                "Take a note in \(.applicationName)",
            ],
            shortTitle: "Note to Otanecho",
            systemImageName: "square.and.pencil"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .lime
}
