import Foundation
import SwiftData
import SwiftUI

/// タイムラインの 1 行。
struct SeedRowView: View {
    let seed: Seed

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: seed.stage.systemImage)
                .font(.title3)
                .foregroundStyle(seed.stage.tint)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityLabel(seed.stage.label)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(seed.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if seed.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("ピン留め")
                    }
                }

                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !seed.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(seed.tags.prefix(3)), id: \.self) { tag in
                            TagCapsule(text: tag)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 本文プレビュー。AI タイトルが無いときは 1 行目がタイトルになるので、2 行目以降を見せる。
    private var preview: String? {
        let trimmed = seed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let title = seed.title, !title.isEmpty {
            return trimmed
        }
        let rest = trimmed
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}

#Preview {
    List {
        SeedRowView(seed: Seed(body: "通勤中に聴くポッドキャストを、聴きながらメモできるアプリ\n音声で反応を残せると良さそう", tags: ["アプリ", "音声", "移動", "余り"]))
        SeedRowView(seed: Seed(body: "タイトルなしの短いメモ"))
    }
    .modelContainer(PersistenceController.makePreviewContainer())
}
