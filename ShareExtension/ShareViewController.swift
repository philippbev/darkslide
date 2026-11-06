import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Principal class of the Share Extension (see Info.plist). Hosts ``ShareScanView`` over the one
/// image the share sheet hands over, typically a screenshot of a recipe, and completes or cancels
/// the extension request when ``ShareScanModel`` finishes.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // The app's Settings ▸ Display choice, so the scan sheet matches the app rather than the host.
        overrideUserInterfaceStyle = AppearancePreference.current.interfaceStyle
        let model = ShareScanModel(provider: firstImageProvider(),
                                   onFinish: { [weak self] saved in self?.finish(saved: saved) })
        let host = UIHostingController(rootView: ShareScanView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func firstImageProvider() -> NSItemProvider? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        return items.flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    private func finish(saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
