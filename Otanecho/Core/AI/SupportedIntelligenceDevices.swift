import Foundation

/// Apple Intelligence に対応する端末の案内に使うデータ。
///
/// 機種名を 1 つずつ並べると新機種が出るたびに古くなるため、「この世代以降」という粒度で持つ。
/// 正確な最新の一覧は Apple のページに委ね、ここは目安を示すだけにしている。
nonisolated enum SupportedIntelligenceDevices {
    /// 端末の系統ごとの案内。
    nonisolated struct Family: Identifiable, Sendable {
        let id: String
        /// SF Symbols の名前。
        let symbolName: String
        /// 系統の名前。製品名なので翻訳せず、そのまま表示する。
        let name: String
        /// 対応する世代。「iPhone 16 以降」のような粒度で書く。
        let generations: [LocalizedStringResource]
    }

    static let families: [Family] = [
        Family(
            id: "iphone",
            symbolName: "iphone",
            name: "iPhone",
            generations: [
                "iPhone 15 Pro and iPhone 15 Pro Max",
                "iPhone 16 and later (all models)",
            ]
        ),
        Family(
            id: "ipad",
            symbolName: "ipad",
            name: "iPad",
            generations: [
                "iPad Pro (M1 and later)",
                "iPad Air (M1 and later)",
                "iPad mini (A17 Pro and later)",
            ]
        ),
    ]

    /// 対応端末の最新の一覧が載っている Apple のページ。世代で書いた案内が古くなったときの逃げ道。
    static let learnMoreURL = URL(string: "https://www.apple.com/apple-intelligence/")!
}
