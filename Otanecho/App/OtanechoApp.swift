import SwiftData
import SwiftUI

@main
struct OtanechoApp: App {
    private let container = PersistenceController.makeContainer()
    @State private var router = AppRouter()
    @State private var intelligence: any IdeaIntelligence = IntelligenceFactory.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.ideaIntelligence, intelligence)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { router.handle(link) }
                }
        }
        .modelContainer(container)
    }
}
