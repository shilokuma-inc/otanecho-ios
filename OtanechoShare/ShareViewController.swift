import SwiftUI
import UIKit

/// 共有拡張のエントリポイント。SwiftUI の `ShareComposeView` をホストし、保存・キャンセルで拡張を閉じる。
/// メモリ制限が厳しいため、`ModelContainer` は保存の瞬間にだけ生成する。
final class ShareViewController: UIViewController {
    private let model = ShareComposeModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let host = UIHostingController(
            rootView: ShareComposeView(
                model: model,
                onSave: { [weak self] in self?.save() },
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        loadSharedContent()
    }

    private func loadSharedContent() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { [model] in
            model.content = await SharedContentLoader.load(from: items)
            model.isLoading = false
        }
    }

    private func save() {
        guard model.canSave else { return }
        model.isSaving = true
        model.errorMessage = nil
        do {
            let container = PersistenceController.makeContainer()
            try SeedWriter.save(
                body: model.composedBody,
                source: .shareExtension,
                sourceURL: model.content.url?.absoluteString,
                container: container
            )
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            model.isSaving = false
            model.errorMessage = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }

    private func cancel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }
}
