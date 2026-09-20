import AppIntents
import SwiftUI
import WidgetKit

/// コントロールセンターの「種をまく」ボタン。タップでアプリが開き、入力画面が表示される。
struct CaptureControlWidget: ControlWidget {
    static let kind = "ml.mrs1669.Otanecho.CaptureControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureSeedIntent()) {
                Label("種をまく", systemImage: "leaf")
            }
        }
        .displayName("種をまく")
        .description("お種帳を開いて、思いついたことをすぐ書き留めます。")
    }
}
