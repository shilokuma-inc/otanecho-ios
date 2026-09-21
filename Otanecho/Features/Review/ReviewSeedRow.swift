import SwiftUI

/// ふりかえり画面で種を 1 行で示す。タップで詳細へ。
struct ReviewSeedRow: View {
    let seed: Seed
    /// 補足行。渡さなければ作成日時の相対表示になる。
    /// 日付などロケール依存の整形済み文字列も渡せるように `Text` で受け取る。
    var caption: Text?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: seed.stage.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(seed.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    (caption ?? Text(verbatim: seed.createdAt.formatted(.relative(presentation: .named))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
