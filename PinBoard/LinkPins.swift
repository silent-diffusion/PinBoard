//
//  LinkPins.swift  —  PinBoard
//
//  Link pins: a web address saved as a pin, with the page's title and preview
//  picture fetched once (when "Fetch link previews" is on) and kept locally — or, with
//  "Read links fully" on, read fully (an article's text, a video's details: SmartLinks.swift).
//  Links can be saved without their tracking ("Clean links", see LinkCleaner), and
//  a link pin's address and title can be changed later (LinkPinEditorSheet).
//  A page that names no preview picture gets a stand-in: one of its own pictures or, when
//  Settings › Links › "Find a picture for links without one" is on, the first picture a web
//  search finds for its title (`LinkPictureFinder`; the rules are in LinkPictures.swift). A link
//  in Hidden is never searched for: its title would go to the image service without a tap.
//

import SwiftUI
import ImageIO
import UIKit
import Foundation

// MARK: - Fetching a page's title and preview picture

struct LinkPreview: Sendable {
    var title: String?
    var description: String?
    var imageData: Data?
}

enum LinkPreviewFetcher {
    static let maximumHTMLBytes = 2_000_000
    static let timeout: TimeInterval = 15

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": "PinBoard/1.0 (link preview)", "Accept": "text/html"]
        return URLSession(configuration: configuration)
    }()

    /// The page's title, description and preview picture — or nil when the
    /// page can't be read. Only HTTPS pages are contacted; nothing else is sent.
    /// A page that names no picture (or whose picture can't be had) gets a stand-in: one of its
    /// own pictures, else — when Settings › Links › "Find a picture for links without one" is on —
    /// the first picture a web search finds for its title (see `LinkPictureFinder`).
    /// `fallbackTitle`: what the link's pin is called now, for that search when the page has no title.
    /// `keepsPicture`: the pin has a picture already, which a stand-in must not replace.
    /// `searchesWeb`: false for a link in Hidden — its title is never sent to the image service
    /// (the page's own pictures are still tried, they come from the link's own site).
    static func fetch(_ original: URL, fallbackTitle: String? = nil, keepsPicture: Bool = false,
                      searchesWeb: Bool = true) async -> LinkPreview? {
        guard await MainActor.run(body: { AppSettings.shared.webAllowed }) else { return nil }
        guard let url = secureURL(original) else { return nil }
        guard let (html, finalURL) = await downloadHTML(url) else { return nil }
        // A login or "are you a robot?" page is nobody's preview: its title and picture are not kept.
        let document = HTMLDocument(html: html, url: finalURL)
        if LoginWall.isWall(document, finalURL: finalURL, requestedURL: url) { return nil }
        let parsed = parse(html, base: url)
        var preview = LinkPreview(title: parsed.title, description: parsed.description, imageData: nil)
        if let imageURL = parsed.imageURL, let data = try? await WebImageService.download(imageURL) {
            // Only keep it if it really is a picture.
            if ImageProcessor.downsample(data, maxPixelSize: 32) != nil { preview.imageData = data }
        }
        if preview.imageData == nil, !keepsPicture {
            let tried: [URL] = parsed.imageURL.map { (address: URL) -> [URL] in [address] } ?? []
            preview.imageData = await standInPicture(for: document, tried: tried, title: parsed.title ?? fallbackTitle,
                                                     link: original, searchesWeb: searchesWeb)
        }
        if preview.title == nil && preview.description == nil && preview.imageData == nil { return nil }
        return preview
    }

    /// A picture for a page that has none: its own pictures, then the web search (when the Settings
    /// switch is on and `searchesWeb`). nil when there is nothing to try or nothing worked. `tried`: the
    /// picture the page named, which couldn't be had (it is not tried again). `link`: the address the
    /// link was saved as, to tell a real title from the address itself.
    private static func standInPicture(for document: HTMLDocument, tried: [URL], title: String?, link: URL,
                                       searchesWeb: Bool) async -> Data? {
        let search = await MainActor.run { () -> LinkPictureSearch? in
            LinkPictureSearch.current(AppSettings.shared, searchesWeb: searchesWeb)
        }
        let pictures = PageImages.candidates(in: document, excluding: tried)
        let plan = LinkPictureChoice.plan(imageTags: pictures, title: title, link: link, searchesWeb: search != nil)
        return await LinkPictureFinder.find(plan, search: search)
    }

    /// http → https; anything else is refused.
    static func secureURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = components.host, !host.isEmpty else { return nil }
        switch components.scheme?.lowercased() {
        case "https": return url
        case "http":
            components.scheme = "https"
            return components.url
        default: return nil
        }
    }

    private static func downloadHTML(_ url: URL) async -> (html: String, finalURL: URL)? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), !type.contains("html"), !type.contains("xml") { return nil }
        var data = Data()
        data.reserveCapacity(min(maximumHTMLBytes, 256_000))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maximumHTMLBytes { break }   // enough to find the head
            }
        } catch {
            if data.isEmpty { return nil }
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return (html, response.url ?? url)
    }

    struct Parsed {
        var title: String?
        var description: String?
        var imageURL: URL?
    }

    /// Reads <title> and the Open Graph / Twitter meta tags (attribute order doesn't matter).
    static func parse(_ html: String, base: URL) -> Parsed {
        var result = Parsed()
        var meta: [String: String] = [:]
        for tag in tags(named: "meta", in: html) {
            let attributes = self.attributes(of: tag)
            let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"] ?? "").lowercased()
            guard !key.isEmpty, let content = attributes["content"], meta[key] == nil else { continue }
            meta[key] = decodeEntities(content)
        }
        if let ogTitle = meta["og:title"], !ogTitle.isEmpty {
            result.title = ogTitle
        } else if let range = html.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]) {
            let inner = html[range].replacingOccurrences(of: "<title[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
            result.title = decodeEntities(inner)
        } else if let twitter = meta["twitter:title"] {
            result.title = twitter
        }
        result.title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if let title = result.title, title.count > 120 { result.title = TitleGenerator.shorten(title, to: 120) }
        result.description = (meta["og:description"] ?? meta["description"] ?? meta["twitter:description"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let description = result.description, description.count > 300 { result.description = TitleGenerator.shorten(description, to: 300) }
        let imageCandidates = [meta["og:image:secure_url"], meta["og:image"], meta["twitter:image"], meta["twitter:image:src"], meta["image"]]
        for candidate in imageCandidates.compactMap({ $0 }) where !candidate.isEmpty {
            if let resolved = URL(string: candidate, relativeTo: base)?.absoluteURL, let secure = secureURL(resolved) {
                result.imageURL = secure
                break
            }
        }
        if result.imageURL == nil {
            for tag in tags(named: "link", in: html) {
                let attributes = self.attributes(of: tag)
                if attributes["rel"]?.lowercased() == "image_src", let href = attributes["href"],
                   let resolved = URL(string: href, relativeTo: base)?.absoluteURL, let secure = secureURL(resolved) {
                    result.imageURL = secure
                    break
                }
            }
        }
        return result
    }

    private static func tags(named name: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range, in: html).map { String(html[$0]) }
        }
    }

    private static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z:_-]+)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", options: []) else { return result }
        let range = NSRange(tag.startIndex..., in: tag)
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let key = tag[keyRange].lowercased()
            for group in [3, 4, 5] {
                if let valueRange = Range(match.range(at: group), in: tag) {
                    result[key] = String(tag[valueRange])
                    break
                }
            }
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let simple: [(String, String)] = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…")]
        for (entity, replacement) in simple { result = result.replacingOccurrences(of: entity, with: replacement) }
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result), let numberRange = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[numberRange]), let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result
    }
}

// MARK: - A picture for a link whose page has none

/// What the web search for a link's picture needs from Settings, copied on the main actor so the
/// looking can run anywhere. `current` gives nil when no search should run: the switch (Settings ›
/// Links › "Find a picture for links without one") is off, the web isn't allowed (offline mode),
/// or the chosen source needs a key that isn't there.
struct LinkPictureSearch: Sendable, Equatable {
    /// Explore's source (Wikimedia Commons, Openverse, Pexels…).
    var source: WebImageSource
    /// The source's key ("" for the ones that need none).
    var apiKey: String
    /// Openverse's second credential; "" for every other source.
    var secondaryKey: String

    /// The search to run now, or nil when there is none (see above).
    @MainActor
    static func current(_ settings: AppSettings) -> LinkPictureSearch? {
        guard settings.linkPicturesFromWebSearch, settings.webAllowed else { return nil }
        let source = settings.webSource
        guard settings.isSourceReady(source) else { return nil }
        let secondary = source == .openverse ? settings.openverseClientSecret : ""
        return LinkPictureSearch(source: source, apiKey: settings.apiKey(for: source), secondaryKey: secondary)
    }

    /// The same, for one particular link: nil whenever `searchesWeb` is false. A link in Hidden is
    /// never searched for — its title would go to the image service without a tap, which the web
    /// suggestions never do for hidden boards and pins either. Its page's own pictures are still tried.
    @MainActor
    static func current(_ settings: AppSettings, searchesWeb: Bool) -> LinkPictureSearch? {
        guard searchesWeb else { return nil }
        return current(settings)
    }
}

/// Checks on a downloaded picture before it becomes a link's preview.
enum LinkPictureCheck {
    /// Whether `data` really is a picture (it decodes), the way every other preview is checked.
    nonisolated static func isPicture(_ data: Data) -> Bool {
        ImageProcessor.downsample(data, maxPixelSize: 32) != nil
    }

    /// The size in pixels a picture says it has, read from its header (it is not decoded, so a big
    /// picture costs nothing). nil when it isn't a picture.
    nonisolated static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        return (width, height)
    }

    /// Whether one of a page's own pictures is good enough to be the link's preview: a picture that
    /// decodes and is at least 120 pixels on its short side (not an icon).
    nonisolated static func isUsablePageImage(_ data: Data) -> Bool {
        guard let size = pixelSize(of: data), LinkPictureChoice.isBigEnough(width: size.width, height: size.height) else { return false }
        return isPicture(data)
    }
}

/// Fetches the stand-in picture of a link whose page names none. What to try and in which order is
/// decided by `LinkPictureChoice` (LinkPictures.swift); this does the downloading, within a time
/// limit, and never says anything when it fails: the link then simply has no picture, as before.
enum LinkPictureFinder {
    /// The whole look for a stand-in (the page's pictures and the search) gives up after this long,
    /// in nanoseconds, so a slow site never keeps a link waiting.
    nonisolated static let timeLimit: UInt64 = 10_000_000_000

    /// The data of the first picture the plan finds, or nil. The search (when the plan has one)
    /// uses `search`'s source and key. Gives up after `timeLimit` nanoseconds (the usual one, unless
    /// less of the reading's own time is left).
    nonisolated static func find(_ plan: LinkPicturePlan, search: LinkPictureSearch?,
                                 timeLimit: UInt64 = LinkPictureFinder.timeLimit) async -> Data? {
        guard !plan.isEmpty else { return nil }
        return await find(plan, timeLimit: timeLimit, pageImage: { (url: URL) async -> Data? in
            await pageImage(url)
        }, searchPicture: { (title: String) async -> Data? in
            guard let search else { return nil }
            return await webPicture(for: title, using: search)
        })
    }

    /// The same with the two ways of getting a picture handed in (the tests give it fake ones):
    /// `pageImage` fetches one of the page's own pictures, `searchPicture` the web search's. Work that is
    /// not finished after `timeLimit` nanoseconds is given up on, and so is work the person stopped.
    nonisolated static func find(_ plan: LinkPicturePlan, timeLimit: UInt64,
                                 pageImage: @escaping @Sendable (URL) async -> Data?,
                                 searchPicture: @escaping @Sendable (String) async -> Data?) async -> Data? {
        guard !plan.isEmpty else { return nil }
        return await withTaskGroup(of: Data?.self) { (group: inout TaskGroup<Data?>) -> Data? in
            group.addTask { await LinkPictureChoice.run(plan, pageImage: pageImage, searchPicture: searchPicture) }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeLimit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()   // the other one stops: the timer, or work that ran out of time
            return Task.isCancelled ? nil : first
        }
    }

    /// One of the page's own pictures: its data when it downloads (HTTPS only, at most 30 MB), is a
    /// picture and is big enough.
    nonisolated static func pageImage(_ url: URL) async -> Data? {
        guard let secure = LinkPreviewFetcher.secureURL(url), let data = try? await WebImageService.download(secure) else { return nil }
        return LinkPictureCheck.isUsablePageImage(data) ? data : nil
    }

    /// The first picture the web search finds for `title`: the picture itself, else its small
    /// version. nil when the search fails (no key, offline, rate limit: it says nothing about it),
    /// finds nothing, or the picture can't be downloaded. It leaves no notes anywhere: the title can
    /// be a hidden link's, and the notes of a search are shown in Explore's "Details".
    nonisolated static func webPicture(for title: String, using search: LinkPictureSearch) async -> Data? {
        let page: WebPage
        do {
            // The search writes its notes into a notebook of its own, which is thrown away
            // with it: not into Explore's, and not left in the default one either.
            page = try await WebDiagnostics.taskNotes.withValue(WebDiagnostics()) { () async throws -> WebPage in
                try await WebImageService.search(title, source: search.source, page: 1, offset: 0, perPage: 5,
                                                 apiKey: search.apiKey, secondaryKey: search.secondaryKey)
            }
        } catch {
            return nil
        }
        guard let first = page.images.first else { return nil }
        var addresses = [first.fullURL]
        if first.thumbURL != first.fullURL { addresses.append(first.thumbURL) }
        for address in addresses {
            if Task.isCancelled { return nil }
            if let data = try? await WebImageService.download(address), LinkPictureCheck.isPicture(data) { return data }
        }
        return nil
    }

    /// A reading of a link, with a stand-in picture when it asked for one and has none: what the
    /// reading's own page showed, else the web search (`options.pictureSearch`). The reading comes
    /// back as it was when there is nothing to try, nothing worked, or the work was stopped.
    /// `timeLimit`: how long this may take (see `LinkPictureChoice.standInTime`).
    nonisolated static func withStandIn(_ link: ResolvedLink, options: LinkReadingOptions,
                                        timeLimit: UInt64 = LinkPictureFinder.timeLimit) async -> ResolvedLink {
        guard options.findsStandInPicture,
              let plan = LinkPictureChoice.standInPlan(for: link, titleHint: options.titleHint, searchesWeb: options.pictureSearch != nil),
              let data = await find(plan, search: options.pictureSearch, timeLimit: timeLimit) else { return link }
        var result = link
        result.imageData = data
        return result
    }
}

// MARK: - Link cards and pages

/// The card a link pin shows in the grid: preview picture (if any), title, site.
struct LinkCardView: View {
    let pin: Pin
    let image: UIImage?
    /// Read so the card is redrawn when the text size changes (its height follows it).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Height of the text block under the preview (or the whole card when there is no preview).
    static func footerHeight(for pin: Pin) -> CGFloat {
        CardMetrics.footerHeight(hasTitle: !pin.title.isEmpty, hasCaption: pin.linkHost != nil)
    }

    /// Padding around the icon and title of a card without a preview picture.
    static let noPreviewPadding: CGFloat = 12

    /// The card's symbol, which says what the link was read as: a newspaper for an article, a
    /// play button for a YouTube video, a link for everything else (see `LinkFlavor`).
    static func symbol(for pin: Pin) -> String {
        switch pin.linkFlavor {
        case .article?: return "newspaper"
        case .youTube?: return "play.rectangle"
        default: return "link"
        }
    }

    /// A link without a preview picture is a compact card with room for two lines of its
    /// title at the current text size (the grid reads this before drawing the card).
    static var noPreviewHeight: CGFloat {
        noPreviewHeight(titleLineHeight: UIFont.preferredFont(forTextStyle: .subheadline).lineHeight)
    }

    /// Two title lines plus the padding — never less than the 88 points the card has always
    /// had, so it only grows at large text sizes (where two lines no longer fit in 88).
    static func noPreviewHeight(titleLineHeight: CGFloat) -> CGFloat {
        max(88, 2 * ceil(titleLineHeight) + 2 * noPreviewPadding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.textSpacing) {
            if pin.hasPreview {
                Color(uiColor: .secondarySystemFill)
                    .aspectRatio(CardMetrics.clamped(pin.aspectRatio), contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Image(systemName: LinkCardView.symbol(for: pin))
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: LinkCardView.symbol(for: pin))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(pin.title.isEmpty ? (pin.linkURL ?? "Link") : pin.title)
                        .font(.subheadline.weight(.semibold))   // measured as .subheadline in noPreviewHeight
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(LinkCardView.noPreviewPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: LinkCardView.noPreviewHeight)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
            }
        }
    }
}

/// A link pin on its page: the address, and a way to open it.
struct LinkPanelView: View {
    let pin: Pin
    var onRefetch: (() -> Void)? = nil
    @EnvironmentObject private var settings: AppSettings   // (whether the web may be used: see `openButton`)
    /// Links are read fully (Settings › Links): the refresh button reads the link again.
    var readsFully: Bool = false

    /// "Read link again", or the preview button's "Refresh preview" / "Fetch preview".
    private var refetchTitle: String {
        if readsFully { return "Read link again" }
        return pin.hasPreview ? "Refresh preview" : "Fetch preview"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let host = pin.linkHost {
                Label(host, systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
            }
            if let text = pin.linkURL {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack {
                if let url = PinActionRules.linkToOpen(pin) {   // the same rule as the pin menus' "Open link"
                    openButton(url)
                }
                if let onRefetch {
                    Button {
                        onRefetch()
                    } label: {
                        Label(refetchTitle, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
    }

    /// "Open link": the panel's prominent button — except for a YouTube video whose page shows
    /// "Play" (SmartLinksViews.swift): that is its one prominent button then. (Play shows only
    /// while the web may be used and the address names a video; otherwise "Open link" stays prominent.)
    @ViewBuilder
    private func openButton(_ url: URL) -> some View {
        let link = Link(destination: url) {
            Label("Open link", systemImage: "safari")
        }
        if pin.linkFlavor == .youTube, settings.webAllowed, LinkClassifier.youTubeID(in: url) != nil {
            link
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            link
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

// MARK: - Clean links

/// Takes the tracking out of a link you were given (the "?utm_…", "fbclid", "si=" and such
/// that only tell the site who shared it), leaving the bare address. Settings › Links turns it
/// on or off ("Clean links"). The rules, in order:
///   • only http(s) links are touched: anything else comes back exactly as it was;
///   • a redirect link (Google's "/url?q=…", Facebook's "l.php?u=…", Instagram's "?u=…",
///     "href.li/?…") becomes the address inside it, cleaned in turn;
///   • the scheme and the host are lower-cased; the path stays as it was written;
///   • an Amazon product page becomes just "/dp/<number>" (or "/gp/product/<number>");
///   • query parameters used for tracking go (`trackingNames`, `trackingPrefixes`, and on some
///     sites a few more: `siteTrackingNames`) — every other parameter stays, as it was written
///     (YouTube's "v", "t" and "list", a search's "q", a shop's "page", GitHub's "ref"…). Names
///     that mean something on other sites ("ref", "si", "feature") only go where they are known
///     to be tracking;
///   • a text highlight ("#:~:text=…") goes; any other "#…" stays;
///   • a "?" or "&" with nothing after it goes.
/// Cleaning a clean link changes nothing, and the result is always a valid link.
enum LinkCleaner {
    /// Query parameters that go wherever they appear (compared without case, so written here in
    /// small letters). Only names that mean nothing but tracking: "ref" (a GitHub branch, a GitLab
    /// pipeline), "referrer", "si" or "feature" can mean something, so they are not here.
    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "li_fat_id", "mc_cid", "mc_eid", "igshid", "igsh", "ig_rid", "ref_src", "ref_url",
        "spm", "sr_share", "srsltid", "_ga", "_gl", "sscid", "epik", "mkt_tok", "trk",
        "trkcampaign", "ncid", "cmpid", "rb_clickid", "ito", "xtor", "share_id",
        // A few more of the same kind: Google Ads, Amazon's and IMDb's "ref_".
        "gad_source", "ref_",
        // HubSpot (ads, e-mails, call-to-action buttons) — by name, not every "hs…" (a site's
        // own "hsLang" stays).
        "hsa_acc", "hsa_cam", "hsa_grp", "hsa_ad", "hsa_src", "hsa_tgt", "hsa_kw", "hsa_mt", "hsa_net",
        "hsa_ver", "hsctatracking", "_hsenc", "_hsmi", "_hsfp", "__hssc", "__hstc", "__hsfp",
        // Matomo (Piwik) campaigns — by name, not every "pk_…".
        "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "pk_content",
        // AT Internet campaigns — by name, not every "at_…".
        "at_medium", "at_campaign", "at_source", "at_custom1", "at_custom2", "at_custom3", "at_custom4"
    ]
    /// Query parameters that go when their name starts with one of these (compared without case).
    static let trackingPrefixes: [String] = ["utm_", "mtm_", "oly_", "vero_"]
    /// On x.com and twitter.com: who shared a post, and how.
    static let xTrackingNames: Set<String> = ["s", "t"]
    /// On YouTube (youtube.com, youtu.be): how a video was shared.
    static let youTubeTrackingNames: Set<String> = ["si", "feature"]
    /// On Spotify (open.spotify.com, spotify.link): who shared it.
    static let spotifyTrackingNames: Set<String> = ["si"]
    /// On Amazon: which link of the site was followed.
    static let amazonTrackingNames: Set<String> = ["ref"]

    /// The names that go on this site only (see `trackingNames` for those that go everywhere).
    static func siteTrackingNames(for host: String) -> Set<String> {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if isX(host) { return xTrackingNames }
        if bare == "youtube.com" || bare.hasSuffix(".youtube.com") || bare == "youtu.be" { return youTubeTrackingNames }
        if bare == "open.spotify.com" || bare == "spotify.link" { return spotifyTrackingNames }
        if isAmazon(host) { return amazonTrackingNames }
        return []
    }

    /// The link without its tracking; text that isn't an http(s) link comes back as it is.
    nonisolated static func cleaned(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWebLink(trimmed), let result = clean(trimmed, depth: 0), isWebLink(result) else { return link }
        return result
    }

    /// "Cleaned 3 links." — what "Clean existing links" (Settings › Links) says afterwards.
    static func cleanedText(count: Int) -> String {
        if count == 0 { return "Your links had no tracking to take out." }
        return "Cleaned \(count) link\(count == 1 ? "" : "s")."
    }

    /// A link cut into its parts, each exactly as it was written.
    struct Parts {
        var scheme: String
        var authority: String      // "www.example.com", or with a user and a port: "me@example.com:8080"
        var path: String           // "" or "/…"
        var query: String?         // what follows "?" (nil = no "?")
        var fragment: String?      // what follows "#" (nil = no "#")

        /// The host, lower-cased, without a user name or a port.
        var host: String {
            var text = Substring(authority)
            if let at = text.lastIndex(of: "@") { text = text[text.index(after: at)...] }
            if text.hasPrefix("[") {   // an IPv6 address: "[::1]:8080"
                guard let close = text.firstIndex(of: "]") else { return String(text).lowercased() }
                return String(text[...close]).lowercased()
            }
            if let colon = text.firstIndex(of: ":") { text = text[..<colon] }
            return String(text).lowercased()
        }

        /// The authority with its host (and port) lower-cased; a user name stays as it was.
        var lowercasedAuthority: String {
            guard let at = authority.lastIndex(of: "@") else { return authority.lowercased() }
            let user = String(authority[...at])
            return user + authority[authority.index(after: at)...].lowercased()
        }

        /// The parts put back together (an empty query or fragment leaves no "?" or "#").
        var text: String {
            var result = scheme.lowercased() + "://"
            result += lowercasedAuthority
            result += path
            if let query, !query.isEmpty { result += "?" + query }
            if let fragment, !fragment.isEmpty { result += "#" + fragment }
            return result
        }
    }

    /// Cuts a link written "scheme://authority/path?query#fragment" into its parts.
    static func parts(of link: String) -> Parts? {
        guard let schemeEnd = link.range(of: "://") else { return nil }
        let scheme = String(link[..<schemeEnd.lowerBound])
        var rest = link[schemeEnd.upperBound...]
        var fragment: String? = nil
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        var query: String? = nil
        if let mark = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: mark)...])
            rest = rest[..<mark]
        }
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        return Parts(scheme: scheme, authority: String(rest[..<slash]), path: String(rest[slash...]),
                     query: query, fragment: fragment)
    }

    /// An http(s) address with a host, and no spaces.
    static func isWebLink(_ text: String) -> Bool {
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The cleaning itself (see the rules above). `depth` limits redirects inside redirects.
    private static func clean(_ link: String, depth: Int) -> String? {
        guard var parts = parts(of: link) else { return nil }
        if depth < 3, let inner = unwrapped(parts) {
            return clean(inner, depth: depth + 1) ?? inner
        }
        let host = parts.host
        if isAmazon(host), let product = amazonProductPath(parts.path) {
            parts.path = product
            parts.query = nil
            parts.fragment = nil
            return parts.text
        }
        if let query = parts.query {
            let siteNames = siteTrackingNames(for: host)
            let pieces = query.split(separator: "&", omittingEmptySubsequences: true)
            let kept = pieces.filter { (piece: Substring) -> Bool in !isTracking(name(of: piece), siteNames: siteNames) }
            parts.query = kept.isEmpty ? nil : kept.joined(separator: "&")
        }
        if let fragment = parts.fragment, let highlight = fragment.range(of: ":~:") {
            parts.fragment = String(fragment[..<highlight.lowerBound])
        }
        return parts.text
    }

    /// Whether a query parameter (its name, decoded and lower-cased) is only there for tracking,
    /// on a site whose own tracking names are `siteNames` (see `siteTrackingNames`).
    static func isTracking(_ name: String, siteNames: Set<String>) -> Bool {
        if trackingNames.contains(name) || siteNames.contains(name) { return true }
        return trackingPrefixes.contains { (prefix: String) -> Bool in name.hasPrefix(prefix) }
    }

    /// Whether cleaning `link` takes something out of it (tracking, a redirect around it, a text
    /// highlight…) — not merely writing its scheme and host in small letters or dropping an empty
    /// "?" or "#". ("Clean existing links" counts only these.)
    nonisolated static func hasTracking(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = cleaned(trimmed)
        guard result != trimmed, let written = parts(of: trimmed) else { return false }
        return result != written.text
    }

    /// A query parameter's name, decoded and lower-cased ("UTM_Source=x" → "utm_source").
    static func name(of piece: Substring) -> String {
        let raw = String(piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        return (raw.removingPercentEncoding ?? raw).lowercased()
    }

    /// The decoded value of the first query parameter called `wanted`.
    static func value(of wanted: String, in query: String) -> String? {
        for piece in query.split(separator: "&") {
            let halves = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2, name(of: piece) == wanted else { continue }
            let raw = String(halves[1])
            return raw.removingPercentEncoding ?? raw
        }
        return nil
    }

    /// The address inside a redirect link, when this is one: Google's "/url?q=…", Facebook's
    /// "l.php?u=…", Instagram's "l.instagram.com/?u=…" or "href.li/?…".
    static func unwrapped(_ parts: Parts) -> String? {
        guard let query = parts.query, !query.isEmpty else { return nil }
        let host = parts.host
        let path = parts.path
        let atRoot = path.isEmpty || path == "/"
        if isGoogle(host), path == "/url" {
            return webLink(value(of: "q", in: query)) ?? webLink(value(of: "url", in: query))
        }
        if host == "l.facebook.com" || host == "lm.facebook.com", path == "/l.php" {
            return webLink(value(of: "u", in: query))
        }
        if host == "l.instagram.com", atRoot {
            return webLink(value(of: "u", in: query))
        }
        if host == "href.li", atRoot {
            var inner = query
            if let fragment = parts.fragment { inner += "#" + fragment }
            return webLink(inner) ?? webLink(inner.removingPercentEncoding)
        }
        return nil
    }

    /// `text`, trimmed, when it is an http(s) link.
    private static func webLink(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isWebLink(trimmed) ? trimmed : nil
    }

    /// google.com, www.google.com, google.co.uk, www.google.com.au…
    static func isGoogle(_ host: String) -> Bool {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let labels = bare.split(separator: ".")
        guard labels.first == "google", labels.count == 2 || labels.count == 3 else { return false }
        return labels.dropFirst().allSatisfy { (label: Substring) -> Bool in label.count <= 3 }
    }

    /// amazon.com, www.amazon.co.uk, smile.amazon.de…: "amazon" and then one or two short labels.
    static func isAmazon(_ host: String) -> Bool {
        let labels = host.split(separator: ".")
        guard let index = labels.lastIndex(of: "amazon") else { return false }
        let rest = labels[(index + 1)...]
        guard rest.count == 1 || rest.count == 2 else { return false }
        return rest.allSatisfy { (label: Substring) -> Bool in label.count <= 3 }
    }

    /// x.com and twitter.com (also with "www." or "mobile.").
    static func isX(_ host: String) -> Bool {
        var bare = host
        for prefix in ["www.", "mobile."] where bare.hasPrefix(prefix) { bare = String(bare.dropFirst(prefix.count)) }
        return bare == "x.com" || bare == "twitter.com"
    }

    /// "/dp/B08N5WRWNW" or "/gp/product/B08N5WRWNW" when an Amazon path names a product (the
    /// product's name before it and "/ref=…" after it are left out).
    static func amazonProductPath(_ path: String) -> String? {
        let segments: [String] = path.split(separator: "/").map { (segment: Substring) -> String in String(segment) }
        for (index, segment) in segments.enumerated() {
            let next = index + 1 < segments.count ? segments[index + 1] : ""
            if segment == "dp", isProductNumber(next) { return "/dp/" + next }
            if segment == "gp", next == "product", index + 2 < segments.count, isProductNumber(segments[index + 2]) {
                return "/gp/product/" + segments[index + 2]
            }
        }
        return nil
    }

    /// An Amazon product number (ASIN): ten letters and digits.
    static func isProductNumber(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { (character: Character) -> Bool in
            character.isASCII && (character.isLetter || character.isNumber)
        }
    }
}

// MARK: - Typing a link

/// Typing or pasting a link to save — or, with `init(editing:onSave:)`, changing a link pin's
/// address and title. With "Clean links" on (Settings › Links) the link is saved without its
/// tracking, and the sheet shows the cleaned address under the field while it differs.
struct LinkPinEditorSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    /// The link pin being changed (nil = a new link pin).
    private let existing: Pin?
    private let onSave: (_ url: URL, _ title: String?) -> Void
    @State private var text: String
    @State private var title: String
    @State private var clipboardHasLink = false   // checked without reading the clipboard (no "Allow Paste" prompt)

    /// A new link pin.
    init(onSave: @escaping (URL) -> Void) {
        existing = nil
        self.onSave = { url, _ in onSave(url) }
        _text = State(initialValue: "")
        _title = State(initialValue: "")
    }

    /// Changing a link pin: the sheet opens with its address and title. `onSave` gets the address
    /// (cleaned when "Clean links" is on) and the title to hand to `LibraryStore.updateLinkPin`:
    /// nil = the title stays as it is, "" = the person cleared a title (the page's comes back),
    /// otherwise a title the person typed.
    init(editing pin: Pin, onSave: @escaping (_ url: URL, _ title: String?) -> Void) {
        existing = pin
        self.onSave = onSave
        _text = State(initialValue: pin.linkURL ?? "")
        _title = State(initialValue: pin.title)
    }

    private var url: URL? { LibraryStore.linkURL(in: text) }

    /// The address as it will be saved: cleaned when "Clean links" is on.
    private var savedURL: URL? {
        guard let url else { return nil }
        guard settings.cleanLinks else { return url }
        return URL(string: LinkCleaner.cleaned(url.absoluteString)) ?? url
    }

    /// The cleaned address, while it differs from what is typed (shown under the field).
    private var cleanedPreview: String? {
        guard let url, let saved = savedURL, saved.absoluteString != url.absoluteString else { return nil }
        return saved.absoluteString
    }

    /// Something was typed or changed: then a swipe down must not throw it away.
    private var hasChanges: Bool {
        guard let existing else { return !text.isEmpty }
        return text != (existing.linkURL ?? "") || title != existing.title
    }

    /// See `init(editing:onSave:)`.
    private var titleToSave: String? {
        guard let existing else { return nil }
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed == existing.title.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : typed
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                addressField
                if let cleanedPreview {
                    Text("Will be saved as: " + cleanedPreview)   // (plain text: an address is no Markdown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                if clipboardHasLink { clipboardButton }
                if existing != nil { titleField }
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(existing == nil ? "New link pin" : "Edit link")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let pasteboard = UIPasteboard.general
                clipboardHasLink = pasteboard.hasURLs || pasteboard.hasStrings
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(url == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Once something is typed or changed, a swipe down can't throw it away: Cancel or Save decides.
        .interactiveDismissDisabled(hasChanges)
    }

    private var addressField: some View {
        NativeTextField(placeholder: "https://…", text: $text, returnKey: .done, autocapitalization: .none, autocorrection: false,
                        autoFocus: true) {
            save()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Empty = the page's title (or the AI's) stays.
    private var titleField: some View {
        NativeTextField(placeholder: "Title (empty: the page's own)", text: $title) {
            save()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var clipboardButton: some View {
        Button {
            // The clipboard is read only now, on purpose (iOS may ask to allow the paste).
            let pasteboard = UIPasteboard.general
            if let pasted = pasteboard.url?.absoluteString ?? pasteboard.string, LibraryStore.linkURL(in: pasted) != nil {
                text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                clipboardHasLink = false
            }
        } label: {
            Label("Use the link on the clipboard", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var footnote: String {
        let previews = settings.fetchLinkPreviews && settings.webAllowed
        if existing == nil {
            if settings.readsLinksFully {
                return "The page is read once and kept in your library: its title and picture, an article's text, a video's details. A link to a Pinterest picture, a picture file or a video file (.mp4, .mov) becomes that picture or video; a video on TikTok, Instagram or another site stays a link with its picture."
            }
            return previews
                ? "The page's title and preview picture are fetched once and kept in your library."
                : "Link previews are off, so the card shows the address only."
        }
        return previews
            ? "Another page's address fetches its title and preview picture again. A title you type stays."
            : "Link previews are off, so the card shows the address only. A title you type stays."
    }

    private func save() {
        guard let saved = savedURL else { return }
        onSave(saved, titleToSave)
        dismiss()
    }
}
