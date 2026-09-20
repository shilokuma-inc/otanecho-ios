import SwiftData
import SwiftUI

@main
struct OtanechoApp: App {
    private let container = PersistenceController.makeContainer()
    @State private var router = AppRouter()
    @State private var intelligence: any IdeaIntelligence = IntelligenceFactory.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.ideaIntelligence, intelligence)
                .task {
                    // 初回応答を速めるため、オンデバイスモデルを事前に温める
                    (intelligence as? FoundationModelsIntelligence)?.prewarm()
                }
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { router.handle(link) }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    // アクションボタン・コントロールセンター・ショートカット（別プロセス）からの要求を拾う
                    if let link = PendingCaptureStore.shared.take() { router.handle(link) }
                }
        }
        .modelContainer(container)
    }
}
