import Foundation

/// App Store のレビュー依頼を出してよいかの判定と記録。
///
/// 出す場所は「種が木になった直後」と「週次ふりかえりを 3 回開いたあとの末尾」の 2 か所だけ（判断基準 5）。
/// どちらから出た場合も、同じ `CFBundleShortVersionString` のあいだは 1 回までにする。
/// 実際に OS がダイアログを出すかどうかは StoreKit 側が決めるので、ここでは「頼んだ」ことだけを記録する。
nonisolated struct AppReviewPrompt: Sendable {
    static let shared = AppReviewPrompt(suiteName: AppGroup.identifier)

    /// 週次ふりかえりを何回開いたら依頼してよいか。
    static let weeklyReviewThreshold = 3

    /// 保存先のキー。テストから直接組み立てられるように private にしていない。
    static let weeklyReviewOpenCountKey = "appReview.weeklyReviewOpenCount"
    static let requestedVersionKey = "appReview.requestedVersion"

    private let suiteName: String?
    private let appVersion: String

    init(suiteName: String?, appVersion: String = Self.bundleVersion) {
        self.suiteName = suiteName
        self.appVersion = appVersion
    }

    private static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// これまでに週次ふりかえりを開いた回数。版をまたいで数え続ける。
    var weeklyReviewOpenCount: Int {
        defaults.integer(forKey: Self.weeklyReviewOpenCountKey)
    }

    /// 今の版で既に依頼したか。
    var hasRequestedForCurrentVersion: Bool {
        defaults.string(forKey: Self.requestedVersionKey) == appVersion
    }

    /// 週次ふりかえりを開いたことを記録する。
    func recordWeeklyReviewOpened() {
        defaults.set(weeklyReviewOpenCount + 1, forKey: Self.weeklyReviewOpenCountKey)
    }

    /// 種が木になった直後に依頼してよいか。
    var shouldRequestAfterTree: Bool {
        !hasRequestedForCurrentVersion
    }

    /// 週次ふりかえりの末尾まで来たときに依頼してよいか。
    var shouldRequestAfterWeeklyReview: Bool {
        !hasRequestedForCurrentVersion && weeklyReviewOpenCount >= Self.weeklyReviewThreshold
    }

    /// 依頼したことを記録する。以後この版では出さない。
    func markRequested() {
        defaults.set(appVersion, forKey: Self.requestedVersionKey)
    }
}
