import Foundation
import Testing
@testable import Otanecho

struct AppReviewPromptTests {
    /// テストごとに独立した suite を使い、App Group の UserDefaults を汚さない。
    private func withSuite(_ body: (String) -> Void) {
        let suiteName = "AppReviewPromptTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        body(suiteName)
    }

    @Test func countsWeeklyReviewOpenings() {
        withSuite { suiteName in
            let prompt = AppReviewPrompt(suiteName: suiteName, appVersion: "1.1.0")
            #expect(prompt.weeklyReviewOpenCount == 0)

            prompt.recordWeeklyReviewOpened()
            prompt.recordWeeklyReviewOpened()

            #expect(prompt.weeklyReviewOpenCount == 2)
        }
    }

    @Test func requestsAfterWeeklyReviewOnlyFromTheThirdOpening() {
        withSuite { suiteName in
            let prompt = AppReviewPrompt(suiteName: suiteName, appVersion: "1.1.0")

            for _ in 1..<AppReviewPrompt.weeklyReviewThreshold {
                prompt.recordWeeklyReviewOpened()
                #expect(!prompt.shouldRequestAfterWeeklyReview)
            }
            prompt.recordWeeklyReviewOpened()

            #expect(prompt.shouldRequestAfterWeeklyReview)
        }
    }

    @Test func requestsAfterTreeUntilRequested() {
        withSuite { suiteName in
            let prompt = AppReviewPrompt(suiteName: suiteName, appVersion: "1.1.0")
            #expect(prompt.shouldRequestAfterTree)

            prompt.markRequested()

            #expect(!prompt.shouldRequestAfterTree)
        }
    }

    /// 木になった直後に出したら、同じ版では週次ふりかえりの末尾でも出さない（逆も同じ判定を共有する）。
    @Test func requestsOnlyOncePerVersionAcrossBothPlaces() {
        withSuite { suiteName in
            let prompt = AppReviewPrompt(suiteName: suiteName, appVersion: "1.1.0")
            for _ in 0..<AppReviewPrompt.weeklyReviewThreshold {
                prompt.recordWeeklyReviewOpened()
            }

            prompt.markRequested()

            #expect(!prompt.shouldRequestAfterTree)
            #expect(!prompt.shouldRequestAfterWeeklyReview)
        }
    }

    @Test func requestsAgainAfterTheVersionChanges() {
        withSuite { suiteName in
            AppReviewPrompt(suiteName: suiteName, appVersion: "1.1.0").markRequested()

            let next = AppReviewPrompt(suiteName: suiteName, appVersion: "1.2.0")

            #expect(next.shouldRequestAfterTree)
            #expect(!next.hasRequestedForCurrentVersion)
        }
    }
}
