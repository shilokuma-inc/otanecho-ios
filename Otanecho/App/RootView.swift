import SwiftData
import SwiftUI

/// ルート画面。タイムラインを表示し、入力・レビューはシートで重ねる。
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            ContentUnavailableView("お種帳", systemImage: "leaf", description: Text("タイムラインは実装中です"))
                .navigationTitle("お種帳")
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .capture(let prefill, _):
                Text(prefill ?? "入力画面（実装中）")
            case .weeklyReview:
                Text("週次レビュー（実装中）")
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .modelContainer(PersistenceController.makePreviewContainer())
}
