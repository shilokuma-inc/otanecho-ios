import SwiftUI
import WidgetKit

/// ロック画面ウィジェット。円形は leaf アイコンのみ、長方形は「種をまく」と今日の件数。どちらもタップで入力画面へ。
struct LockScreenWidget: Widget {
    static let kind = "jp.shilokuma.Otanecho.LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SeedTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("種をまく")
        .description("ロック画面から 1 タップでアイデアを書き留めます。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SeedWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            default:
                rectangular
            }
        }
        .widgetURL(DeepLink.capture(text: nil).url)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "leaf")
                .font(.title2.weight(.medium))
        }
        .accessibilityLabel("種をまく")
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf")
                .font(.title2.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("種をまく")
                    .font(.headline)
                Text("今日 \(entry.todayCount) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("円形", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    SeedWidgetEntry.sample
}

#Preview("長方形", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    SeedWidgetEntry.sample
    SeedWidgetEntry.empty
}
