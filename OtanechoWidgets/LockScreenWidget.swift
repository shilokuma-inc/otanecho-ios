import SwiftUI
import WidgetKit

/// ロック画面ウィジェット。円形は leaf アイコンのみ、長方形は「種をまく」と今日の件数。どちらもタップで入力画面へ。
struct LockScreenWidget: Widget {
    static let kind = "jp.shilokuma.Otanecho.LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SeedTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Plant a Seed")
        .description("Jot down an idea from the Lock Screen with a single tap.")
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
        .accessibilityLabel("Plant a Seed")
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf")
                .font(.title2.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("Plant a Seed")
                    .font(.headline)
                Text("\(entry.todayCount) seeds today")
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
