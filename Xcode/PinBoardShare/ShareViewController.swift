//
//  ShareViewController.swift  —  PinBoard share extension
//
//  Where the share sheet starts ("PinBoard" in the share sheet of Photos, Safari, Files and other
//  apps). It shows ShareView and hands it what was shared; it closes the sheet when the person
//  saves or cancels.
//

import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.finish = { [weak self] (saved: Bool) in self?.close(saved: saved) }
        let host = UIHostingController(rootView: ShareView(model: model))
        // A steady, solid background from the first frame (never the see-through glass).
        view.backgroundColor = .systemGroupedBackground
        host.view.backgroundColor = .systemGroupedBackground
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { (item: NSExtensionItem) -> [NSItemProvider] in item.attachments ?? [] }
        // The page's title, when the other app gives one (Safari does): it helps "Suggested".
        let titles = items.compactMap { (item: NSExtensionItem) -> String? in
            let text = item.attributedTitle?.string ?? item.attributedContentText?.string
            return (text ?? "").isEmpty ? nil : text
        }
        let model = model
        let pageTitle = titles.first
        Task { @MainActor in await model.load(providers, pageTitle: pageTitle) }
    }

    private func close(saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }
}
