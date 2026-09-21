import Foundation

/// チュートリアルの 1 ページぶんの中身。
/// 表示と中身を分けてあるので、ページの増減や文言の差し替えはここだけで済む。
nonisolated struct OnboardingPage: Identifiable, Sendable {
    let id: String
    /// SF Symbols の名前。
    let symbolName: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
}

extension OnboardingPage {
    /// 「速く書ける → AI が整える → 育てる → 見返す」の順に、アプリ 1 周ぶんの体験を並べる。
    nonisolated static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "capture",
            symbolName: "bolt.fill",
            title: "Catch it in a second",
            message: "There's no save button. Tap +, start typing, and it's already saved as a seed."
        ),
        OnboardingPage(
            id: "enrich",
            symbolName: "wand.and.sparkles",
            title: "The AI works backstage",
            message: "Titles and tags are added on their own. Everything runs on your device, so nothing you write leaves it."
        ),
        OnboardingPage(
            id: "grow",
            symbolName: "leaf.fill",
            title: "Grow it with questions",
            message: "Tap Grow and answer the questions you're asked. A seed sprouts, and then becomes a tree."
        ),
        OnboardingPage(
            id: "review",
            symbolName: "calendar",
            title: "Look back once a week",
            message: "The weekly review brings back the seeds you forgot and suggests pairings you wouldn't have thought of."
        ),
    ]
}
