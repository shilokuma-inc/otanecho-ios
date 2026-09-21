import SwiftUI

/// 初回起動時に出すチュートリアル。アプリで何ができるかを 4 ページで伝える。
///
/// このビューは「見せて、終わったことを知らせる」だけにしてある。
/// 出すかどうかの判定も見せ終わった記録も持たないので、
/// 後から見返す導線からもそのまま出せる（`AppRouter.showTutorial()`）。
struct OnboardingView: View {
    /// 最後まで見た場合も Skip した場合も呼ばれる。
    let onFinish: () -> Void

    @State private var selection = 0

    private let pages = OnboardingPage.all

    private var isLastPage: Bool { selection == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            skipBar
            pager
            primaryButton
        }
        .background(Color(.systemBackground))
    }

    /// Skip は最初から最後まで右上に出しっぱなしにする。途中でやめたい人がすぐ抜けられることを優先する。
    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Skip") { onFinish() }
                .font(.body.weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var pager: some View {
        TabView(selection: $selection) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                pageView(page).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: page.symbolName)
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        // ページ全体を 1 つの読み上げ単位にして、スワイプのたびに見出しと本文がまとめて読まれるようにする
        .accessibilityElement(children: .combine)
    }

    private var primaryButton: some View {
        Button {
            if isLastPage {
                onFinish()
            } else {
                withAnimation { selection += 1 }
            }
        } label: {
            Text(isLastPage ? "Start" : "Next")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
}

#Preview {
    OnboardingView {}
}
