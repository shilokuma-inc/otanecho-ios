import Foundation
import Testing
@testable import Otanecho

struct OnboardingTests {
    /// テストごとに独立した suite を使い、標準の UserDefaults を汚さない。
    private func withTracker(_ body: (OnboardingTracker, UserDefaults) -> Void) {
        let suiteName = "OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(OnboardingTracker(suiteName: suiteName), defaults)
    }

    @Test func presentsOnFirstLaunch() {
        withTracker { tracker, _ in
            #expect(tracker.completedVersion == 0)
            #expect(tracker.shouldPresentOnLaunch)
        }
    }

    @Test func doesNotPresentAgainOnceCompleted() {
        withTracker { tracker, _ in
            tracker.markCompleted()

            #expect(tracker.completedVersion == OnboardingTracker.currentVersion)
            #expect(!tracker.shouldPresentOnLaunch)
        }
    }

    /// 版が上がったときだけ出し直す。見せ終わった版が今の版以上なら出さない。
    @Test func doesNotPresentWhenANewerVersionWasAlreadySeen() {
        withTracker { tracker, defaults in
            defaults.set(OnboardingTracker.currentVersion + 1, forKey: OnboardingTracker.storageKey)

            #expect(!tracker.shouldPresentOnLaunch)
        }
    }

    @Test func pagesAreUniqueAndStartWithCapture() {
        let pages = OnboardingPage.all

        #expect(pages.count >= 3)
        #expect(Set(pages.map(\.id)).count == pages.count)
        #expect(pages.first?.id == "capture")
    }
}
