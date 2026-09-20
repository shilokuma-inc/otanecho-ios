import SwiftUI
import WidgetKit

@main
struct OtanechoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// 仮のウィジェット。実装時に差し替える。
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlaceholderWidget", provider: PlaceholderProvider()) { _ in
            Text("お種帳").containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("お種帳")
        .description("アイデアをすぐ書き留める")
        .supportedFamilies([.systemSmall])
    }
}

nonisolated struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

nonisolated struct PlaceholderProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    nonisolated func getSnapshot(in context: Context, completion: @escaping @Sendable (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    nonisolated func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
