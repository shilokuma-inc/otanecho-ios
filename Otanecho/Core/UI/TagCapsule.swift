import SwiftUI

/// タグを表すカプセル。
struct TagCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule())
            .accessibilityIdentifier("tag")
    }
}

#Preview {
    HStack {
        TagCapsule(text: "アプリ")
        TagCapsule(text: "音声")
    }
    .padding()
}
