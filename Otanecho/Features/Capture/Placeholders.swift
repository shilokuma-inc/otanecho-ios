// NOTE: このファイルは統合時に削除するスタブです。
// 他担当が並行して実装している View と同名・同シグネチャの最小実装を置き、
// このブランチ単体でビルドを通すためだけに存在します。本実装が入ったら丸ごと削除してください。

import SwiftUI

/// 深掘り画面（AI 担当が実装）。
struct DeepenView: View {
    let seed: Seed

    init(seed: Seed) {
        self.seed = seed
    }

    var body: some View {
        ContentUnavailableView(
            "深掘り（実装中）",
            systemImage: "leaf",
            description: Text(seed.displayTitle)
        )
    }
}

/// 週次レビュー画面（AI 担当が実装）。
struct WeeklyReviewView: View {
    init() {}

    var body: some View {
        ContentUnavailableView("週次レビュー（実装中）", systemImage: "leaf.circle")
    }
}

/// 音声入力ボタン（入口担当が実装）。認識結果は text に追記される想定。
struct VoiceInputButton: View {
    @Binding var text: String

    init(text: Binding<String>) {
        _text = text
    }

    var body: some View {
        Button("音声入力", systemImage: "mic") {}
            .disabled(true)
    }
}
