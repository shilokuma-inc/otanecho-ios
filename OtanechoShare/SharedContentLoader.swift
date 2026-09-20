import Foundation
import UniformTypeIdentifiers

/// 共有シートから受け取った内容。
nonisolated struct SharedContent: Sendable, Equatable {
    /// 共有されたプレーンテキスト
    var text: String?
    /// 共有された URL
    var url: URL?
    /// Web ページのタイトルなど、共有元が添えた見出し
    var title: String?

    var isEmpty: Bool { text == nil && url == nil }

    /// 種の本文にする文字列。共有テキストがあればそれを、なければタイトル + URL。
    var bodyText: String {
        if let text, !text.isEmpty {
            return text
        }
        var lines: [String] = []
        if let title, !title.isEmpty { lines.append(title) }
        if let url { lines.append(url.absoluteString) }
        return lines.joined(separator: "\n")
    }
}

/// `NSExtensionItem` からテキスト・URL・タイトルを取り出す。
/// JavaScript 前処理（`NSExtensionJavaScriptPreprocessingResultsKey`）は使わず、`public.url` と `public.plain-text` のみ扱う。
@MainActor
enum SharedContentLoader {
    static func load(from items: [NSExtensionItem]) async -> SharedContent {
        var content = SharedContent()

        for item in items {
            if content.title == nil {
                let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty { content.title = title }
            }
            // Safari などは attributedContentText にページタイトルを入れてくることがある
            if content.title == nil {
                let text = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let text, !text.isEmpty { content.title = text }
            }

            for provider in item.attachments ?? [] {
                if content.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    content.url = await loadURL(from: provider)
                }
                if content.text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    content.text = await loadText(from: provider)
                }
            }
        }

        // 本文と同じ文字列がタイトルにも入っている場合は重複を避ける
        if let text = content.text, content.title == text { content.title = nil }
        if let url = content.url, content.title == url.absoluteString { content.title = nil }
        return content
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else { return nil }
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else { return nil }
        let text: String?
        if let string = item as? String {
            text = string
        } else if let attributed = item as? NSAttributedString {
            text = attributed.string
        } else if let data = item as? Data {
            text = String(data: data, encoding: .utf8)
        } else {
            text = nil
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
