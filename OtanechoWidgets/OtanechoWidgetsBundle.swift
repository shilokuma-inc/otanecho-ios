import SwiftUI
import WidgetKit

/// お種帳のウィジェット一式。
/// - コントロールセンター: 「種をまく」ボタン
/// - ロック画面: 円形・長方形
/// - ホーム画面: small / medium
@main
struct OtanechoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CaptureControlWidget()
        LockScreenWidget()
        HomeScreenWidget()
    }
}
