import SwiftUI
import WidgetKit

/// ホーム画面ウィジェット。直近の種と今日の件数を表示し、「+」から入力画面へ。
/// small は全面タップで入力画面、medium は各種のタップで詳細へ。
struct HomeScreenWidget: Widget {
    static let kind = "jp.shilokuma.Otanecho.HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SeedTimelineProvider()) { entry in
            HomeScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Otanecho")
        .description("Glance at your latest seeds, and plant a new one with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SeedWidgetEntry

    private var isSmall: Bool { family == .systemSmall }
    private var visibleSeeds: [SeedSnapshot] { Array(entry.recentSeeds.prefix(isSmall ? 1 : 2)) }
    private var captureURL: URL { DeepLink.capture(text: nil).url }

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(isSmall ? captureURL : nil)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if visibleSeeds.isEmpty {
                Text("Plant your first seed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                ForEach(visibleSeeds) { seed in
                    seedRow(seed)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                plusButton
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Otanecho", systemImage: "leaf")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(entry.todayCount) seeds today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func seedRow(_ seed: SeedSnapshot) -> some View {
        let row = HStack(spacing: 6) {
            Image(systemName: seed.stage.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(seed.displayTitle)
                .font(isSmall ? .footnote : .subheadline)
                .lineLimit(isSmall ? 3 : 1)
        }
        if isSmall {
            row
        } else {
            Link(destination: DeepLink.seed(id: seed.id).url) {
                row
            }
        }
    }

    @ViewBuilder
    private var plusButton: some View {
        let icon = Image(systemName: "plus.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Plant a Seed")
        if isSmall {
            icon
        } else {
            Link(destination: captureURL) { icon }
        }
    }
}

#Preview("small", as: .systemSmall) {
    HomeScreenWidget()
} timeline: {
    SeedWidgetEntry.sample
    SeedWidgetEntry.empty
}

#Preview("medium", as: .systemMedium) {
    HomeScreenWidget()
} timeline: {
    SeedWidgetEntry.sample
    SeedWidgetEntry.empty
}
