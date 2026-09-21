import AppIntents
import SwiftUI
import WidgetKit

/// コントロールセンターの「種をまく」ボタン。タップでアプリが開き、入力画面が表示される。
struct CaptureControlWidget: ControlWidget {
    static let kind = "jp.shilokuma.Otanecho.CaptureControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CaptureSeedIntent()) {
                Label("Plant a Seed", systemImage: "leaf")
            }
        }
        .displayName("Plant a Seed")
        .description("Opens Otanecho so you can jot down what just came to mind.")
    }
}
