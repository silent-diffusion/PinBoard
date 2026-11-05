//
//  WebBrowser.swift  —  PinBoard
//
//  Searching a picture on the web ("Search this picture on the web ▸": Google Lens, Bing,
//  TinEye, Yandex) and PinBoard's own private browser, which keeps nothing: no cookies, no
//  history, no cache (Settings › Explore & web search › "Open web searches in").
//
//  The two address helpers above the browser (`ReverseImageSearch`, `WebSearchOpening`) are
//  final: menus and Explore call them. The browser itself is `PrivateBrowserSheet`.
//

import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers
import AVFoundation   // (only for the test harness, whose stand-in for key-value observing lives here; on the device it is Foundation's)
import Foundation

/// The addresses of the reverse image search sites (pure; the harness tests them).
enum ReverseImageSearch {
    /// The site's search for a picture that has a web address of its own (a web result, a
    /// picture saved from the web).
    nonisolated static func searchURL(_ engine: ReverseImageEngine, imageURL: URL) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = imageURL.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        switch engine {
        case .googleLens: return URL(string: "https://lens.google.com/uploadbyurl?url=" + encoded)
        case .bing: return URL(string: "https://www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&sbisrc=UrlPaste&q=imgurl:" + encoded)
        case .tinEye: return URL(string: "https://tineye.com/search?url=" + encoded)
        case .yandex: return URL(string: "https://yandex.com/images/search?rpt=imageview&url=" + encoded)
        }
    }

    /// The site's page for uploading a picture (for a picture that only lives in the library:
    /// PinBoard puts it on the clipboard, and the page takes it).
    nonisolated static func uploadURL(_ engine: ReverseImageEngine) -> URL {
        switch engine {
        case .googleLens: return URL(string: "https://lens.google.com/")!
        case .bing: return URL(string: "https://www.bing.com/visualsearch")!
        case .tinEye: return URL(string: "https://tineye.com/")!
        case .yandex: return URL(string: "https://yandex.com/images/")!
        }
    }
}

/// What a "Search this picture on the web" tap opens (pure apart from the clipboard; final).
enum WebSearchOpening {
    /// How long the picture stays on the clipboard (seconds). Long enough to switch to the page
    /// and paste it, short enough that a picture the person only wanted to search for isn't
    /// left on the clipboard for good.
    nonisolated static let clipboardSeconds: TimeInterval = 120

    /// The address to open, and whether the picture was put on the clipboard for the person to
    /// paste or upload on that page (a picture that lives only in the library has no web
    /// address of its own, so the site can't be sent a link to it).
    @MainActor
    static func destination(_ engine: ReverseImageEngine, imageURL: URL?, pictureData: Data?) -> (url: URL, copiedPicture: Bool) {
        if let imageURL, let search = ReverseImageSearch.searchURL(engine, imageURL: imageURL) {
            return (search, false)
        }
        if let pictureData, let image = UIImage(data: pictureData) {
            // `setObjects` (not `.image =`): the picture goes on under its own types (PNG, JPEG…),
            // stays on this device only, and expires — see `clipboardSeconds` for the two minutes.
            UIPasteboard.general.setObjects([image], localOnly: true, expirationDate: Date().addingTimeInterval(clipboardSeconds))
            return (ReverseImageSearch.uploadURL(engine), true)
        }
        return (ReverseImageSearch.uploadURL(engine), false)
    }

    /// The toast after opening: only when the picture went to the clipboard. It says how long
    /// the picture stays there and that it doesn't leave this device.
    nonisolated static func copiedNote(_ copied: Bool) -> String? {
        copied ? "The picture is on your clipboard for two minutes, on this device only — paste or upload it on the page." : nil
    }
}

// MARK: - PinBoard's private browser

/// The plain rules of PinBoard's browser (pure, so the harness can test them).
enum PrivateBrowserRules {
    /// What the browser calls itself to web sites: Safari on an iPad. A bare web view is often
    /// sent a thinner page (or none) by big sites, and a search site should see what Safari sees.
    /// Reading a Pinterest link asks for its page with the same words (`PinterestReader.userAgent`).
    nonisolated static let userAgent = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// What the small note says when something other than a web address was asked for.
    nonisolated static let refusedNote = "PinBoard's browser opens only web addresses (https or http)."

    /// What the sheet's button that hands the page to the person's own browser is called (its
    /// VoiceOver label). It opens whichever browser they made their default — Safari, Chrome… —
    /// so it never says "Safari".
    nonisolated static let openInBrowserLabel = "Open in browser"

    /// What the small note says when the page is a kind of file the web view can't show (a download,
    /// say): the default browser can.
    nonisolated static let cannotShowFileNote = "PinBoard's browser can't show this kind of file. “Open in browser” can."

    /// Only ordinary web addresses load: https and http, with a host. Anything else
    /// (`tel:`, `mailto:`, another app's scheme, `file:`, `javascript:`) is refused.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The page itself may move to a web address, or to the empty page the browser shows
    /// when it closes. (Frames inside a page are the page's own business and aren't asked.)
    nonisolated static func allowsPageLoad(_ url: URL) -> Bool {
        isAllowed(url) || url.absoluteString == "about:blank"
    }

    /// The host of an address without a leading "www." ("example.com"), or "" when there is none.
    nonisolated static func hostText(_ url: URL?) -> String {
        guard var host = url?.host else { return "" }
        if host.lowercased().hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    /// The bar's title: the page's own title, else its host, else "Web search" (before anything loaded).
    nonisolated static func title(pageTitle: String?, address: URL?) -> String {
        let trimmed = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let host = hostText(address)
        return host.isEmpty ? "Web search" : host
    }

    /// What "Open in browser" opens: the page now shown, or the address the sheet started with.
    /// (The name is from when this button opened Safari; it opens the person's default browser now.)
    nonisolated static func safariTarget(current: URL?, start: URL) -> URL {
        if let current, isAllowed(current) { return current }
        return start
    }
}

/// What the toolbar and the address strip show about the page (one value, so the screen only
/// redraws when something in it really changed).
struct PrivateBrowserState: Equatable {
    var title = ""
    var address: URL? = nil
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    /// 0 … 1 while a page loads.
    var progress = 0.0
    /// The page came over an encrypted connection (https, nothing mixed in).
    var isSecure = false
}

/// The browser's web view and everything it tells the screen. The web view keeps nothing: its
/// data store is the non-persistent kind (nothing is written to disk: no cookies, no history,
/// no cache), and when the sheet closes the page is emptied and the store wiped as well.
@MainActor
final class PrivateBrowserModel: ObservableObject {
    @Published private(set) var state = PrivateBrowserState()
    /// A short line when a page was refused or didn't load (nil: nothing to say).
    @Published private(set) var notice: String? = nil

    let webView: WKWebView
    private let dataStore: WKWebsiteDataStore
    private let delegate = PrivateBrowserDelegate()
    private var observations: [NSKeyValueObservation] = []
    private var startedWith: URL? = nil
    private var isShutDown = false

    init() {
        let store = WKWebsiteDataStore.nonPersistent()
        dataStore = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.mediaTypesRequiringUserActionForPlayback = .all   // nothing plays until you press play
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = PrivateBrowserRules.userAgent
        view.allowsBackForwardNavigationGestures = true
        webView = view
        delegate.model = self
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        watch()
    }

    /// Loads the first page (once per address). A refused address loads nothing and says why.
    func start(_ url: URL) {
        guard startedWith != url, !isShutDown else { return }
        startedWith = url
        guard PrivateBrowserRules.isAllowed(url) else {
            notice = PrivateBrowserRules.refusedNote
            return
        }
        notice = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    /// Loads an address in this same view (a link that wanted a window of its own).
    func load(_ request: URLRequest) {
        guard let url = request.url, PrivateBrowserRules.isAllowed(url) else { return }
        webView.load(request)
    }

    func say(_ text: String?) {
        if notice != text { notice = text }
    }

    /// Reads the web view's state once, and only publishes it when it differs.
    func refresh() {
        guard !isShutDown else { return }
        let now = PrivateBrowserState(
            title: PrivateBrowserRules.title(pageTitle: webView.title, address: webView.url),
            address: webView.url,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            isLoading: webView.isLoading,
            progress: webView.estimatedProgress,
            isSecure: webView.hasOnlySecureContent)
        if now != state { state = now }
    }

    /// The sheet closed: stop what loads, empty the page (its sound stops at once) and wipe
    /// everything the store may still hold. Safe to call twice.
    func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        for observation in observations { observation.invalidate() }
        observations = []
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        let store = dataStore
        Task { @MainActor in
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0))
        }
    }

    /// Watches the web view (its properties are observable): each change reads the state anew,
    /// on the main actor. (One line per property, so the compiler never has a long list to work out.)
    private func watch() {
        let view = webView
        observations.append(view.observe(\.title, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.url, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.canGoBack, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.canGoForward, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.isLoading, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.estimatedProgress, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
        observations.append(view.observe(\.hasOnlySecureContent, options: [.new]) { @Sendable [weak self] _, _ in PrivateBrowserModel.refreshSoon(self) })
    }

    /// From a KVO callback (which may come from any thread) to the main actor, carrying nothing but the model.
    nonisolated private static func refreshSoon(_ target: PrivateBrowserModel?) {
        Task { @MainActor in target?.refresh() }
    }
}

/// Decides what the page may do: only web addresses load (a link to another app, a phone
/// number or a file is refused with a note), a link that wants a window of its own opens in
/// this view, and a page the web view can't show is left to the default browser.
@MainActor
final class PrivateBrowserDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: PrivateBrowserModel?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.targetFrame?.isMainFrame == false { return .allow }   // a frame inside the page
        guard PrivateBrowserRules.allowsPageLoad(url) else {
            model?.say(PrivateBrowserRules.refusedNote)
            return .cancel
        }
        model?.say(nil)
        if navigationAction.targetFrame == nil {
            // A link that wanted a new window: it opens here instead.
            model?.load(navigationAction.request)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, !navigationResponse.canShowMIMEType {
            model?.say(PrivateBrowserRules.cannotShowFileNote)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        model?.load(navigationAction.request)
        return nil   // never a second web view: the page opens in this one
    }

    // The toolbar and the address are read again at each step of a page load, as well as when the
    // web view says something changed, so they are right even if one of those notices is missed.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        model?.refresh()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        model?.refresh()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        model?.refresh()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.refresh()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failed(with: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        failed(with: error)
    }

    /// The content process can be stopped by the system when memory runs short: the page loads again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// A page that didn't load says so once (a load the person stopped, or replaced by another, is not a failure).
    private func failed(with error: any Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return }
        model?.say("The page didn't load. \(error.localizedDescription)")
    }
}

/// The web view inside the sheet. It is the model's own (made once); closing the sheet shuts it down.
struct PrivateWebView: UIViewRepresentable {
    let model: PrivateBrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.model.shutDown()
    }

    /// Only holds the model, so `dismantleUIView` can reach it.
    @MainActor
    final class Coordinator {
        let model: PrivateBrowserModel
        init(model: PrivateBrowserModel) { self.model = model }
    }
}

/// PinBoard's own browser for web searches (Settings › Explore & web search › "Open web searches in"): a large
/// sheet with Done, back and forward, reload (or stop) and "Open in browser" (the default browser,
/// whichever the person chose in the Settings app). It keeps nothing
/// between uses: no cookies, no history, no cache. `hidden`: the search was started from a
/// hidden pin, so the sheet is covered in the App Switcher like the rest of Hidden.
struct PrivateBrowserSheet: View {
    let url: URL
    let hidden: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model = PrivateBrowserModel()

    init(url: URL, hidden: Bool = false) {
        self.url = url
        self.hidden = hidden
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.state.title.isEmpty ? PrivateBrowserRules.title(pageTitle: nil, address: url) : model.state.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .largeSheetSizing()   // on iPad: a page-sized sheet, not the small form sheet
        .hiddenPrivacyCover(hidden)
        // The app's short messages show over this sheet while it is up: the hand-over notes that
        // come up as the page opens ("Saved to Photos — upload it on the page.", the clipboard's, "PinBoard
        // isn't allowed to add to Photos…") would otherwise be hidden under it. Applied outside the
        // NavigationStack: the cover counts the screens it is on as they appear and disappear. The
        // browser has its own bar along the bottom (back, forward, reload), so the messages float above it.
        .importFlowCover(toastAboveControls: true)
        .task(id: url) { model.start(url) }
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            addressStrip
            if let note = model.notice {
                noticeBar(note)
            }
            PrivateWebView(model: model)
        }
    }

    /// The host (and a lock when the page is encrypted) above the page, with a thin progress
    /// line while it loads: what you are looking at is never hidden from you.
    private var addressStrip: some View {
        let shown = model.state.address ?? url
        return HStack(spacing: 6) {
            Image(systemName: model.state.isSecure ? "lock.fill" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(PrivateBrowserRules.hostText(shown))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(.horizontal, 16)
        .background(.bar)
        .overlay(alignment: .bottom) { progressLine }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.state.isSecure ? "Secure page, \(PrivateBrowserRules.hostText(shown))" : "Page, \(PrivateBrowserRules.hostText(shown))")
    }

    @ViewBuilder
    private var progressLine: some View {
        if model.state.isLoading {
            ProgressView(value: min(1, max(0.05, model.state.progress)))
                .progressViewStyle(.linear)
                .accessibilityHidden(true)
        }
    }

    private func noticeBar(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { model.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!model.state.canGoBack)
                .accessibilityLabel("Back")
            Spacer()
            Button { model.goForward() } label: { Image(systemName: "chevron.forward") }
                .disabled(!model.state.canGoForward)
                .accessibilityLabel("Forward")
            Spacer()
            reloadButton
            Spacer()
            Button {
                // Hands the page to the default browser (an https address opens there, not in PinBoard).
                openURL(PrivateBrowserRules.safariTarget(current: model.state.address, start: url))
            } label: {
                Image(systemName: "safari")   // the generic "browser" symbol: it is not only for Safari
            }
            .accessibilityLabel(PrivateBrowserRules.openInBrowserLabel)
        }
    }

    /// Reload, or Stop while a page is loading.
    private var reloadButton: some View {
        Button {
            if model.state.isLoading { model.stopLoading() } else { model.reload() }
        } label: {
            Image(systemName: model.state.isLoading ? "xmark" : "arrow.clockwise")
        }
        .accessibilityLabel(model.state.isLoading ? "Stop loading" : "Reload")
    }
}
