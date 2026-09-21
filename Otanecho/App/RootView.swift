import SwiftData
import SwiftUI

/// ルート画面。タイムラインを表示し、入力・レビューはシートで重ねる。
/// AI の裏方処理（SeedEnricher）もここで生成して下位に環境値として渡す。
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ideaIntelligence) private var intelligence
    @Environment(\.scenePhase) private var scenePhase

    @State private var enricher: SeedEnricher?
    private let onboarding = OnboardingTracker()
    /// 前面復帰時にタイムラインを再フェッチさせるためのトークン。
    @State private var timelineRefreshToken = 0
    @State private var wasInBackground = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            TimelineView(refreshToken: timelineRefreshToken)
                .navigationDestination(for: UUID.self) { seedID in
                    SeedDetailView(seedID: seedID)
                }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .capture(let prefill, let source):
                CaptureView(prefill: prefill, source: source)
            case .weeklyReview:
                WeeklyReviewView()
            }
        }
        .fullScreenCover(isPresented: $router.isShowingTutorial) {
            OnboardingView {
                onboarding.markCompleted()
                router.isShowingTutorial = false
            }
        }
        .environment(enricher)
        .task {
            if onboarding.shouldPresentOnLaunch {
                router.showTutorial()
            }
            if enricher == nil {
                enricher = SeedEnricher(container: modelContext.container, intelligence: intelligence)
            }
            await enricher?.enrichPending()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasInBackground = true
            case .active:
                // 共有拡張など別プロセスが追加した種を拾うため、バックグラウンドからの復帰時だけ再フェッチさせる
                if wasInBackground {
                    wasInBackground = false
                    timelineRefreshToken += 1
                }
                Task { await enricher?.enrichPending() }
            default:
                break
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .modelContainer(PersistenceController.makePreviewContainer())
}
