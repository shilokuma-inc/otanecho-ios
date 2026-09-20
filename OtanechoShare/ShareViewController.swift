import SwiftUI
import UIKit

/// 共有拡張のエントリポイント。実装時に SwiftUI の保存 UI をホストする。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: Text("お種帳に保存（実装中）"))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
