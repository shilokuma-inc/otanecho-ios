import Foundation

/// オンデバイスモデルに出力させる言語。
///
/// Foundation Models は「指示文が何語で書かれているか」ではなく「出力言語として明示されたもの」に従いやすいので、
/// instructions に英語で言語名を書いて渡す。プロンプト自体は英語で固定し、出力言語だけを差し替える。
nonisolated enum OutputLanguage {
    /// 言語名が解決できなかったときに使う言語。
    static let fallbackName = "English"

    /// 表記体系まで伝えないと出力が揺れる言語。
    ///
    /// `Locale.Language.script` は明示されていなくても推定値が入る（`ja_JP` でも `Jpan`）ため、
    /// すべての言語にスクリプトを付けると "Japanese (Japanese)" のような不自然な指示になってしまう。
    /// 実際に表記体系で分かれる言語だけを列挙しておく。
    private static let scriptSensitiveLanguages: Set<String> = ["zh", "sr", "az", "uz", "pa", "mn"]

    /// 端末の設定言語を英語の言語名にする（例: `ja` → "Japanese"）。
    ///
    /// 中国語のように表記体系で分かれる言語は、スクリプトまで含めて伝える
    /// （`zh-Hans` → "Chinese, Simplified"）。言語コードだけにすると、
    /// 簡体字の端末に繁体字が返ってくることがある。
    static func name(for locale: Locale = .current) -> String {
        let english = Locale(identifier: "en")
        let language = locale.language
        guard let code = language.languageCode?.identifier else { return fallbackName }
        if scriptSensitiveLanguages.contains(code),
           let script = language.script?.identifier,
           let named = english.localizedString(forIdentifier: "\(code)-\(script)") {
            return named
        }
        return english.localizedString(forLanguageCode: code) ?? fallbackName
    }
}
