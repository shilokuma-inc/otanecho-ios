import Foundation

/// チュートリアルを見せ終わったかどうかの記録。
///
/// 「見せ終わった版」を番号で持つ。初回起動かどうかはこの番号で判定し、
/// あとから内容を大きく入れ替えたくなったら `currentVersion` を上げれば既存ユーザーにももう一度出せる。
///
/// 設定画面から見返すときは `reset()` で記録を落としてから出す。途中で閉じても次回起動時にもう一度出る。
/// 表示の判定と記録をここに閉じ込めてあるので、画面側は「出す / 出さない」を知らなくて済む。
nonisolated struct OnboardingTracker: Sendable {
    /// いまのチュートリアルの版。内容を入れ替えて見せ直したくなったら上げる。
    static let currentVersion = 1

    /// 保存先のキー。テストから直接組み立てられるように private にしていない。
    static let storageKey = "onboarding.completedVersion"

    /// 保存先の suite。アプリ本体だけが使う値なので既定は標準の UserDefaults。
    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// 見せ終わったチュートリアルの版。一度も見せていなければ 0。
    var completedVersion: Int {
        defaults.integer(forKey: Self.storageKey)
    }

    /// 起動時に自動で出すべきか。
    var shouldPresentOnLaunch: Bool {
        completedVersion < Self.currentVersion
    }

    /// 最後まで見た場合も Skip した場合も、どちらも「見せ終わった」として記録する。
    /// 途中でやめた人に毎回出し直すのは、Skip を置いた意味が無くなるため。
    func markCompleted() {
        defaults.set(Self.currentVersion, forKey: Self.storageKey)
    }

    /// 見せ終わった記録を消す。設定画面から見返すときに使う。
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
