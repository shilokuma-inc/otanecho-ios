import Foundation
import Testing
@testable import Otanecho

struct SeedModelTests {
    @Test func growthStageFollowsAnsweredCount() {
        #expect(GrowthStage.stage(forAnsweredCount: 0) == .seed)
        #expect(GrowthStage.stage(forAnsweredCount: 1) == .sprout)
        #expect(GrowthStage.stage(forAnsweredCount: 2) == .sprout)
        #expect(GrowthStage.stage(forAnsweredCount: 3) == .tree)
    }

    @Test func deepLinkRoundTrip() {
        let link = DeepLink.capture(text: "ふと思いついた")
        #expect(DeepLink(url: link.url) == link)
        let id = UUID()
        #expect(DeepLink(url: DeepLink.seed(id: id).url) == .seed(id: id))
        #expect(DeepLink(url: DeepLink.review.url) == .review)
        #expect(DeepLink(url: URL(string: "https://example.com")!) == nil)
    }
}
