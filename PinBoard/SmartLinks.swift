//
//  SmartLinks.swift  —  PinBoard
//
//  Reading a link fully when it is added (Settings › Links › "Read links fully"): what kind of
//  page it is, and what is worth keeping from it — an article's text, writer and date; a
//  Pinterest pin's picture and the page it links to; a YouTube video's details and top comments
//  (from YouTube's oEmbed and Data API); a Reddit, TikTok, Instagram or X post; the picture any
//  other page is about. A link straight to a picture or video file becomes that pin.
//  Videos are never taken out of a web page or a social site (App Review guideline 5.2.3): a
//  post or page with a video is kept as a link pin with its picture and title. Only a link that
//  is itself a video file (an .mp4 or .mov address) is downloaded, as a browser would.
//  This file does the fetching (only over HTTPS, only from the link's own site and the services
//  it names, with no cookies kept) and hands what was found to the library. How the pages are
//  read is in SmartLinksParsers.swift and SmartLinksReaders.swift; the screens are in
//  SmartLinksViews.swift.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Writing what was read into a pin

extension ResolvedLink {
    /// Writes what was read into a link pin: its title (as the page's title, and only when the
    /// person hasn't typed one), its text, short description, writer, date, site, the page it
    /// links to, the kind of link, the comments, and a YouTube video's length. Only what was
    /// found is written: reading a page again never erases what the pin already has.
    func fill(_ pin: inout Pin) {
        if let title = SmartLinkText.cleaned(title), !pin.titleEditedByUser { pin.setImportedTitle(title) }
        if let text, SmartLinkText.cleaned(text) != nil { pin.textBody = text }
        if let description = SmartLinkText.cleaned(description) { pin.aiDescription = description }
        fillDetails(&pin)
        // (Only a plausible length: a page can write any number, see `isPlausibleLength`.)
        if flavor == .youTube, let duration, SmartLinkText.isPlausibleLength(duration), !pin.isVideo { pin.duration = duration }
    }

    /// Keeps what was read with the picture or video pin a link became (a Pinterest pin, a
    /// picture or video file): the title only when the pin has none, the description when it
    /// has none, where it came from, and the writer, date, site, linked page and kind of link.
    /// What kind of pin it is, its picture and its video are never touched.
    func fillExtras(_ pin: inout Pin) {
        if pin.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let title = SmartLinkText.cleaned(title) {
            pin.setImportedTitle(title)
        }
        if pin.aiDescription.isEmpty, let description = SmartLinkText.cleaned(description) { pin.aiDescription = description }
        if pin.textBody.isEmpty, let text, SmartLinkText.cleaned(text) != nil { pin.textBody = text }
        if pin.sourceURL == nil { pin.sourceURL = url.absoluteString }
        fillDetails(&pin)
    }

    /// What every pin a link became keeps: writer, date, site, linked page, kind of link, comments.
    /// A reading that found less never makes an article a plain page: when its site now sends
    /// only a teaser or a cookie page (read as an ordinary page, with no text), the pin stays an
    /// article, with its byline, "Read article" and the text it has.
    private func fillDetails(_ pin: inout Pin) {
        let foundLess = flavor == .page && pin.linkFlavor == .article && text == nil
        if !foundLess { pin.linkFlavor = flavor }
        if let author = SmartLinkText.cleaned(author) { pin.author = author }
        if let publishedAt { pin.publishedAt = publishedAt }
        if let siteName = SmartLinkText.cleaned(siteName) { pin.siteName = siteName }
        if let linkedURL = SmartLinkText.cleaned(linkedURL) { pin.linkedURL = linkedURL }
        if !comments.isEmpty { pin.comments = comments }
        if let viewCount { pin.viewCount = viewCount }
    }
}

extension AppSettings {
    /// Links are read fully now: "Read links fully" and "Fetch link previews" are both on, and the
    /// app may use the internet. (Reading a page means fetching it, so someone who turned link
    /// previews off never has their links fetched.)
    var readsLinksFully: Bool {
        readLinksFully && fetchLinkPreviews && webAllowed
    }
}

/// What reading a link needs from Settings, copied on the main thread (so the reading itself can
/// run anywhere).
struct LinkReadingOptions: Sendable {
    /// The person's YouTube Data API key ("" = none).
    var youTubeAPIKey: String = ""
    /// Whether a page that names no picture of its own may be given a stand-in: one of its own
    /// pictures, then the web search (`LinkPictureFinder`). Off by default; `resolve(_:settings:…)`
    /// turns it on, except for a link whose pin has its picture already.
    var findsStandInPicture = false
    /// The web search for that picture (Settings › Links › "Find a picture for links without
    /// one", with its source and key); nil: no search, the page's own pictures only.
    var pictureSearch: LinkPictureSearch? = nil
    /// What the link's pin is called already (nil for a link not saved yet): the search's words
    /// when the page has no title of its own.
    var titleHint: String? = nil
}

// MARK: - Fetching

/// The fetching behind "Read links fully": pages, pictures, small JSON answers and video files.
/// Only HTTPS addresses are contacted; nothing is remembered between requests (no cookies, no
/// cache); pages are asked for as Safari on an iPad asks for them, so sites send their normal page.
enum LinkFetcher {
    /// A video file from a link is saved when it is at most this big.
    static let maximumVideoBytes: Int64 = 500 * 1024 * 1024

    /// What fetching a link brought back.
    enum Fetched: Sendable {
        case html(String, finalURL: URL)
        case picture(Data, finalURL: URL)
        case video(URL)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// For video files, which may take a few minutes.
    static let videoSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    /// A link's page (at most 3 MB of it), or the picture or video file it turns out to be.
    nonisolated static func fetchPage(_ url: URL) async -> Fetched? {
        guard let secure = LinkPreviewFetcher.secureURL(url) else { return nil }
        var request = URLRequest(url: secure)
        request.httpMethod = "GET"
        request.setValue(PinterestReader.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        let finalURL = response.url ?? secure
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        switch LinkClassifier.mediaKind(fromContentType: type) {
        case .imageFile?:
            guard let data = await read(bytes, limit: WebImageService.maximumDownloadBytes, keepsPart: false) else { return nil }
            return .picture(data, finalURL: finalURL)
        case .videoFile?:
            bytes.task.cancel()   // the link is itself a video file: it is downloaded later, to a file
            return .video(finalURL)
        default:
            break
        }
        let lower = type.lowercased()
        guard lower.isEmpty || lower.contains("html") || lower.contains("xml") else {
            bytes.task.cancel()   // a PDF, a zip…: nothing to read
            return nil
        }
        guard let data = await read(bytes, limit: HTMLDocument.maximumBytes, keepsPart: true) else { return nil }
        return .html(text(of: data, contentType: type), finalURL: finalURL)
    }

    /// Where a link ends up after its redirects (a share link, a short link), without downloading
    /// the page behind it. nil when it can't be reached.
    nonisolated static func finalAddress(of url: URL) async -> URL? {
        guard let secure = LinkPreviewFetcher.secureURL(url) else { return nil }
        var request = URLRequest(url: secure)
        request.setValue(PinterestReader.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
        bytes.task.cancel()   // only the address is wanted
        return response.url
    }

    /// A download read into memory. More than `limit` bytes: nil, or — with `keepsPart` (a page,
    /// whose head and main text come first) — its first `limit` bytes.
    nonisolated static func read(_ bytes: URLSession.AsyncBytes, limit: Int, keepsPart: Bool) async -> Data? {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit {
                    bytes.task.cancel()
                    return keepsPart ? data : nil
                }
            }
        } catch {
            // Cut off (or given up on): a page may still be read from what came.
            return keepsPart && !data.isEmpty ? data : nil
        }
        return data
    }

    /// A page's bytes as text: UTF-8 (the web's usual), or the Windows/Latin-1 letters a page says
    /// it uses. A page cut off in the middle of a letter keeps everything before it.
    nonisolated static func text(of data: Data, contentType: String) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let head = String(decoding: data.prefix(4_096), as: UTF8.self).lowercased()
        let declared = contentType.lowercased() + " " + head
        let latin = ["windows-1252", "iso-8859-1", "latin1", "latin-1"].contains { (name: String) -> Bool in declared.contains(name) }
        if latin, let text = String(data: data, encoding: .windowsCP1252) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// The most a service's answer may be (oEmbed and the YouTube Data API send a few KB).
    static let maximumDataBytes = 2_000_000

    /// A small answer from a service (oEmbed, the YouTube Data API, a Reddit post's JSON): at most
    /// 2 MB, only when the service said all was well. `userAgent`: Reddit answers only browsers. It is read as it comes, so a bigger answer is stopped at 2 MB
    /// instead of being downloaded whole first.
    nonisolated static func fetchData(_ url: URL, userAgent: String = WebImageService.userAgent) async -> Data? {
        guard let secure = LinkPreviewFetcher.secureURL(url) else { return nil }
        var request = URLRequest(url: secure)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status), response.expectedContentLength <= Int64(maximumDataBytes) else {
            bytes.task.cancel()   // an error, or said to be too big: not read at all
            return nil
        }
        return await read(bytes, limit: maximumDataBytes, keepsPart: false)
    }

    /// How many of a page's pictures are tried by default when it names several.
    nonisolated static let pictureTries = 3

    /// The first of `candidates` that downloads as a real picture (at most `tries` are tried).
    nonisolated static func downloadPicture(from candidates: [URL], tries: Int = LinkFetcher.pictureTries) async -> Data? {
        var tried = 0
        for url in candidates where tried < tries {
            if Task.isCancelled { return nil }
            guard let secure = LinkPreviewFetcher.secureURL(url) else { continue }
            tried += 1
            guard let data = try? await WebImageService.download(secure) else { continue }
            if ImageProcessor.downsample(data, maxPixelSize: 32) != nil { return data }   // only a real picture
        }
        return nil
    }

    /// Downloads a link that is itself a video file (at most 500 MB) to a temporary file the import
    /// then owns ("import-<id>.mp4", like a video chosen in Files), as a browser's download would.
    /// nil when it can't be had. The file is written as it comes and the download stops as soon as
    /// it passes 500 MB, so a server that doesn't say the size first can't make it run on for gigabytes.
    nonisolated static func downloadVideo(_ url: URL) async -> URL? {
        guard let secure = LinkPreviewFetcher.secureURL(url) else { return nil }
        // First only ask how big it is, so a huge file is never downloaded at all. (Some servers
        // don't answer this question; the limit below still holds for them.)
        var head = URLRequest(url: secure)
        head.httpMethod = "HEAD"
        head.setValue(PinterestReader.userAgent, forHTTPHeaderField: "User-Agent")
        if let (_, response) = try? await session.data(for: head), let http = response as? HTTPURLResponse,
           (200...299).contains(http.statusCode) {
            if response.expectedContentLength > maximumVideoBytes { return nil }
            if LinkClassifier.refusesVideo(contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "") { return nil }
        }
        var request = URLRequest(url: secure)
        request.setValue(PinterestReader.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await videoSession.bytes(for: request) else { return nil }
        let http = response as? HTTPURLResponse
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard let status = http?.statusCode, (200...299).contains(status),
              response.expectedContentLength <= maximumVideoBytes, !LinkClassifier.refusesVideo(contentType: type) else {
            bytes.task.cancel()   // an error, too big, a page, a stream or a video that can't be played here
            return nil
        }
        let ext = videoExtension(for: response.url ?? secure, mimeType: response.mimeType)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(ext)")
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: destination) else {
            bytes.task.cancel()
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        let written = await writeDownload(bytes, to: handle, limit: maximumVideoBytes)
        try? handle.close()
        guard written > 0 else {
            try? FileManager.default.removeItem(at: destination)   // stopped, cut off or empty: nothing is left behind
            return nil
        }
        return destination
    }

    /// Writes a download into `handle` as it comes, 64 KB at a time. Returns how many bytes were
    /// written — or 0 when it passed `limit` (the download is stopped there), broke off, or the
    /// import it belongs to was stopped.
    nonisolated static func writeDownload(_ bytes: URLSession.AsyncBytes, to handle: FileHandle, limit: Int64) async -> Int64 {
        let chunkSize = 65_536
        var chunk = Data()
        chunk.reserveCapacity(chunkSize)
        var total: Int64 = 0
        do {
            for try await byte in bytes {
                chunk.append(byte)
                guard chunk.count >= chunkSize else { continue }
                total += Int64(chunk.count)
                guard total <= limit, !Task.isCancelled else {
                    bytes.task.cancel()
                    return 0
                }
                try handle.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
            total += Int64(chunk.count)
            guard total <= limit else { return 0 }
            try handle.write(contentsOf: chunk)
        } catch {
            bytes.task.cancel()
            return 0
        }
        return total
    }

    /// "mp4", "mov" or "m4v": from the address, else from the type the server said (a 3GPP
    /// video is the same kind of file as an MP4, so it is saved as one).
    nonisolated static func videoExtension(for url: URL, mimeType: String?) -> String {
        let fromAddress = url.pathExtension.lowercased()
        if LinkClassifier.videoExtensions.contains(fromAddress) { return fromAddress }
        switch (mimeType ?? "").lowercased() {
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        default: return "mp4"
        }
    }
}

// MARK: - Reading a link

/// Reads a link fully: works out what it leads to and reads it with the reader for that kind of
/// link. One more kind of site is one more reader and one more line in `read(_:options:depth:)`.
enum LinkResolver {
    /// A link's whole reading takes at most this long (in nanoseconds); after that it counts as
    /// unread, and the link is added the old way. (Looking for a stand-in picture for a page that
    /// has none comes after the reading and uses what is left of this time, at most
    /// `LinkPictureFinder.timeLimit`; it never makes a reading count as unread.)
    static let timeLimit: UInt64 = 25_000_000_000

    /// Short-link services: a link from one of these is saved as the address it leads to. Any
    /// other link is saved as it was given (a redirect elsewhere may be a sign-in or cookie page).
    static let shorteners: Set<String> = [
        "t.co", "bit.ly", "buff.ly", "ow.ly", "tinyurl.com", "goo.gl", "lnkd.in", "trib.al", "dlvr.it",
        "ift.tt", "amzn.to", "amzn.eu", "a.co", "fb.me", "is.gd", "rebrand.ly", "cutt.ly", "shorturl.at",
        "tiny.cc", "bl.ink", "flip.it", "wp.me", "apple.co", "spoti.fi", "nyti.ms", "wapo.st", "bbc.in",
        "cnn.it", "reut.rs", "econ.st", "bloom.bg", "g.co", "hubs.ly", "hubs.la", "mailchi.mp", "on.ft.com"
    ]

    /// What `url` leads to, read with the settings of now; nil when it can't be read (offline, not
    /// a web address, the site didn't answer in time…). A page that names no picture gets a
    /// stand-in (see `LinkPictureFinder`) — unless `keepsPicture`: the link's pin has a picture
    /// already ("Read link again" never swaps it for a guess). `titleHint`: what the link's pin is
    /// called, for the picture search when the page has no title. `searchesWeb`: false for a link
    /// that goes into (or lives in) Hidden: its title is never sent to the image service, only the
    /// page's own pictures are tried.
    @MainActor
    static func resolve(_ url: URL, settings: AppSettings, titleHint: String? = nil, keepsPicture: Bool = false,
                        searchesWeb: Bool = true) async -> ResolvedLink? {
        guard settings.webAllowed else { return nil }
        let options = readingOptions(settings: settings, titleHint: titleHint, keepsPicture: keepsPicture, searchesWeb: searchesWeb)
        return await resolve(url, options: options)
    }

    /// What a reading takes from Settings, copied now so the reading can run anywhere (the
    /// parameters are those of `resolve(_:settings:…)`). Kept apart from it so the tests can check
    /// what a link on each side of the library gets, without reading a page.
    @MainActor
    static func readingOptions(settings: AppSettings, titleHint: String? = nil, keepsPicture: Bool = false,
                               searchesWeb: Bool = true) -> LinkReadingOptions {
        let key = settings.youTubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = LinkReadingOptions(youTubeAPIKey: key)
        options.findsStandInPicture = !keepsPicture
        options.pictureSearch = LinkPictureSearch.current(settings, searchesWeb: searchesWeb)
        options.titleHint = titleHint
        return options
    }

    /// The same with the settings already copied; the reading gives up after `timeLimit`.
    nonisolated static func resolve(_ url: URL, options: LinkReadingOptions) async -> ResolvedLink? {
        guard let secure = LinkPreviewFetcher.secureURL(url) else { return nil }
        let started = DispatchTime.now().uptimeNanoseconds
        let found = await withTaskGroup(of: ResolvedLink?.self) { (group: inout TaskGroup<ResolvedLink?>) -> ResolvedLink? in
            group.addTask { await read(secure, options: options, depth: 0) }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeLimit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()   // the other one stops (a reading that ran out of time, or the timer)
            return Task.isCancelled ? nil : first   // "Stop": what came back may be cut short
        }
        // A page that named no picture: one of its own, or the web search's. Looked for after the
        // reading (so it never makes a reading run out of time), in what is left of its 25 seconds.
        guard let found, !Task.isCancelled else { return found }
        let used = DispatchTime.now().uptimeNanoseconds - started
        guard let time = LinkPictureChoice.standInTime(readingUsed: used, readingLimit: timeLimit, standInLimit: LinkPictureFinder.timeLimit) else {
            return found
        }
        return await LinkPictureFinder.withStandIn(found, options: options, timeLimit: time)
    }

    /// The reader for each kind of link. `depth`: how many redirects were followed to get here.
    nonisolated static func read(_ url: URL, options: LinkReadingOptions, depth: Int) async -> ResolvedLink? {
        if let id = LinkClassifier.youTubeID(in: url) {
            return await YouTubeReader.read(id: id, link: url, apiKey: options.youTubeAPIKey)
        }
        if LinkClassifier.isPinterest(url) {
            return await PinterestReader.read(url)
        }
        if let kind = LinkClassifier.mediaKind(of: url) {
            return await readMedia(url, kind: kind)
        }
        if let site = await readSite(url) {
            return site
        }
        return await readPage(url, options: options, depth: depth)
    }

    /// The sites with a reader of their own besides YouTube and Pinterest: Reddit, TikTok,
    /// Instagram and X. nil when the link isn't a post of theirs, or couldn't be read that way
    /// (the ordinary page reading then has its go).
    nonisolated static func readSite(_ url: URL) async -> ResolvedLink? {
        if RedditReader.isPostLink(url) { return await RedditReader.read(url) }
        if TikTokReader.isTikTok(url) { return await TikTokReader.read(url) }
        if InstagramReader.shortcode(in: url) != nil { return await InstagramReader.read(url) }
        if TwitterReader.isPostLink(url) { return await TwitterReader.read(url) }
        return nil
    }

    /// Whether a link is read by a reader of its own (so a short link that leads to one is handed to it).
    nonisolated static func hasOwnReader(_ url: URL) -> Bool {
        if LinkClassifier.youTubeID(in: url) != nil || LinkClassifier.isPinterest(url) { return true }
        return RedditReader.isPostLink(url) || TikTokReader.isTikTok(url)
            || InstagramReader.shortcode(in: url) != nil || TwitterReader.isPostLink(url)
    }

    /// A link straight to a picture (downloaded now) or a video file (downloaded when it is imported).
    nonisolated static func readMedia(_ url: URL, kind: LinkFlavor) async -> ResolvedLink? {
        if kind == .videoFile { return ResolvedLink(url: url, flavor: .videoFile, videoURL: url) }
        guard let data = await LinkFetcher.downloadPicture(from: [url], tries: 1) else { return nil }
        return ResolvedLink(url: url, flavor: .imageFile, imageData: data)
    }

    /// Any other link: its page is fetched and read as an article, as a picture page, or as an
    /// ordinary page (a page with a video too: its video is never taken out of it). A short link that turns out to lead to a site with a reader of its own
    /// (YouTube, Pinterest, Reddit…) is read by that reader.
    nonisolated static func readPage(_ url: URL, options: LinkReadingOptions, depth: Int) async -> ResolvedLink? {
        guard let fetched = await LinkFetcher.fetchPage(url) else { return nil }
        switch fetched {
        case .picture(let data, _):
            guard ImageProcessor.downsample(data, maxPixelSize: 32) != nil else { return nil }
            return ResolvedLink(url: url, flavor: .imageFile, imageData: data)
        case .video(let finalURL):
            return ResolvedLink(url: url, flavor: .videoFile, videoURL: finalURL)
        case .html(let html, let finalURL):
            let isElsewhere = !SmartLinkText.samePage(finalURL, url)
            if depth == 0, isElsewhere, hasOwnReader(finalURL) {
                return await read(finalURL, options: options, depth: 1)
            }
            return await page(html: html, finalURL: finalURL, link: savedAddress(link: url, finalURL: finalURL), requestedURL: url)
        }
    }

    /// A fetched page, read in this order; `link` is the address the pin keeps:
    ///   1. a login or "are you a robot?" page is nobody's content: a plain link, nothing of it kept;
    ///   2. an article (with its lead picture);
    ///   3. an ordinary page — its picture, or (a photo page) the picture itself as a picture pin.
    ///      A page whose point is a video (og:video, a VideoObject) is an ordinary page too: its
    ///      video is never saved (App Review guideline 5.2.3), the pin keeps its picture and title.
    /// `requestedURL`: the address that was asked for (a short link's own address, where `link` is
    /// where it led); nil = `link`. Only a page that was *sent* to a sign-in address is a wall of that
    /// kind (see `LoginWall.isWall`).
    nonisolated static func page(html: String, finalURL: URL, link: URL, requestedURL: URL? = nil) async -> ResolvedLink {
        let document = HTMLDocument(html: html, url: finalURL)
        if LoginWall.isWall(document, finalURL: finalURL, requestedURL: requestedURL ?? link) { return ResolvedLink.blocked(url: link) }
        let media = MediaPage(document: document)
        if let article = ArticleExtractor.extract(from: document, url: finalURL) {
            var pictures = PageSummary.pictures(of: document)
            if let lead = article.leadImageURL { pictures.insert(lead, at: 0) }
            var resolved = ResolvedLink.article(article, url: link)
            resolved.imageData = await LinkFetcher.downloadPicture(from: pictures)
            if resolved.imageData == nil { resolved.standInCandidates = standInCandidates(in: document, tried: pictures) }
            return resolved
        }
        return await ordinaryPage(document, finalURL: finalURL, link: link, media: media)
    }

    /// An ordinary page: its title, description and preview picture; what its oEmbed description
    /// (when it has one) adds — a writer, a site name, a thumbnail; and, when the page says it is a
    /// photo (og:type, oEmbed "photo") with a big enough picture, the picture itself as a picture pin
    /// whose source page is the page.
    nonisolated static func ordinaryPage(_ document: HTMLDocument, finalURL: URL, link: URL, media: MediaPage) async -> ResolvedLink {
        let summary = PageSummary(document: document, url: finalURL)
        var resolved = ResolvedLink.page(summary, url: link)
        var embed: OEmbed? = nil
        if let address = media.oEmbedURL, let data = await LinkFetcher.fetchData(address) { embed = OEmbed.parse(data) }
        if let embed { resolved.fillGaps(from: embed) }
        var photo = media
        if let embed, embed.type == "photo", let address = embed.url {
            photo.isPhoto = true
            photo.pictures.insert(MediaPicture(url: address, width: embed.width, height: embed.height), at: 0)
        }
        if photo.wantsPicture() {
            let addresses = photo.pictures.map { (picture: MediaPicture) -> URL in picture.url }
            if let data = await LinkFetcher.downloadPicture(from: addresses) {
                resolved.flavor = .imageFile
                resolved.imageData = data
                return resolved
            }
        }
        var candidates = summary.imageURLs
        if let thumbnail = embed?.thumbnailURL, !candidates.contains(thumbnail) { candidates.append(thumbnail) }
        resolved.imageData = await LinkFetcher.downloadPicture(from: candidates)
        if resolved.imageData == nil { resolved.standInCandidates = standInCandidates(in: document, tried: candidates) }
        return resolved
    }

    /// The page's own pictures to try when it named none that could be had (`ResolvedLink.standInCandidates`).
    /// `tried`: the pictures the page did name — the ones that were fetched already (the first few)
    /// are not tried again.
    nonisolated static func standInCandidates(in document: HTMLDocument, tried: [URL]) -> [URL] {
        PageImages.candidates(in: document, excluding: Array(tried.prefix(LinkFetcher.pictureTries)))
    }

    /// The address a link is saved with: where a short link led, else the link as it was given.
    nonisolated static func savedAddress(link: URL, finalURL: URL) -> URL {
        guard let host = SmartLinkText.bareHost(of: link), shorteners.contains(host),
              let final = SmartLinkText.secureURL(finalURL.absoluteString) else { return link }
        return final
    }
}

// MARK: - The readers' fetching

extension YouTubeReader {
    /// Everything about the video `id`, only from YouTube's own services for apps (its terms allow
    /// nothing else; the watch page is never read): the Data API with the person's own key (details
    /// and top comments), filled in from YouTube's oEmbed answer (title, channel, thumbnail; no key
    /// needed); the thumbnail downloaded. `link` is the address the pin keeps. nil when nothing at
    /// all could be read.
    nonisolated static func read(id: String, link: URL, apiKey: String) async -> ResolvedLink? {
        async let fromAPI = apiVideo(id: id, key: apiKey)
        async let comments = apiComments(id: id, key: apiKey)
        async let fromEmbed = oEmbed(id: id)
        var video = await fromAPI ?? YouTubeVideo(id: id)
        video.id = id
        if let embed = await fromEmbed { video.fillGaps(from: embed) }
        video.comments = await comments
        guard video.title != nil || video.channel != nil || video.description != nil else { return nil }
        var resolved = ResolvedLink.youTube(video, url: link)
        var thumbnails = video.thumbnailURLs.filter { (url: URL) -> Bool in url.absoluteString.contains("maxres") }
        for url in thumbnailURLs(id: id) + video.thumbnailURLs where !thumbnails.contains(url) { thumbnails.append(url) }
        resolved.imageData = await LinkFetcher.downloadPicture(from: thumbnails, tries: 4)
        return resolved
    }

    /// YouTube's oEmbed answer (no key needed): title, channel and thumbnail.
    nonisolated static func oEmbed(id: String) async -> YouTubeVideo? {
        guard let url = oEmbedURL(id: id), let data = await LinkFetcher.fetchData(url) else { return nil }
        return parseOEmbed(data)
    }

    /// The Data API's details, when the person gave a key (a wrong key or no quota: nil).
    nonisolated static func apiVideo(id: String, key: String) async -> YouTubeVideo? {
        guard !key.isEmpty, let url = apiVideoURL(id: id, key: key), let data = await LinkFetcher.fetchData(url) else { return nil }
        return parseAPIVideo(data)
    }

    /// The top comments, when the person gave a key (comments turned off, a key error: none).
    nonisolated static func apiComments(id: String, key: String) async -> [PinComment] {
        guard !key.isEmpty, let url = apiCommentsURL(id: id, key: key), let data = await LinkFetcher.fetchData(url) else { return [] }
        return parseAPIComments(data)
    }
}

extension PinterestReader {
    /// The pin's own address, "https://www.pinterest.com/pin/<number>/" (whatever country site or
    /// short link it was shared as), so the same pin shared twice is known.
    nonisolated static func pinAddress(_ number: String) -> URL? {
        URL(string: "https://www.pinterest.com/pin/" + number + "/")
    }

    /// A Pinterest link read: a pin gives its picture (downloaded, the largest there is), title,
    /// description, destination and creator. A video pin's video is never saved: it stays a link
    /// pin with that picture. Any other Pinterest page (a board, a profile) is read as an ordinary page.
    nonisolated static func read(_ url: URL) async -> ResolvedLink? {
        guard let fetched = await LinkFetcher.fetchPage(url) else { return nil }
        guard case .html(let html, let finalURL) = fetched else { return nil }
        let number = LinkClassifier.pinterestPinID(in: finalURL) ?? LinkClassifier.pinterestPinID(in: url)
        guard let number, let address = pinAddress(number) else {
            return await LinkResolver.page(html: html, finalURL: finalURL, link: url, requestedURL: url)
        }
        let pin = parse(html: html, pinID: number)
        var resolved = ResolvedLink.pinterest(pin, url: address)
        resolved.imageData = await LinkFetcher.downloadPicture(from: pin.imageURLs, tries: 4)
        return resolved
    }
}

// MARK: - The other sites' fetching

extension RedditReader {
    /// A Reddit post: its public JSON (a share link or a v.redd.it address is followed to the post
    /// first), and the post's picture (a video's first frame) downloaded. nil when Reddit says no (the page is then read
    /// as an ordinary page).
    nonisolated static func read(_ url: URL) async -> ResolvedLink? {
        var id = postID(in: url)
        if id == nil, let final = await LinkFetcher.finalAddress(of: url) { id = postID(in: final) }
        guard let id, let address = jsonURL(postID: id),
              let data = await LinkFetcher.fetchData(address, userAgent: PinterestReader.userAgent),
              let post = parse(data) else { return nil }
        var resolved = ResolvedLink.reddit(post, given: url)
        resolved.imageData = await LinkFetcher.downloadPicture(from: post.imageCandidates)
        resolved.becomesLinkWithoutPicture()
        return resolved
    }
}

extension TikTokReader {
    /// A TikTok post: the page's data (caption, creator, cover) and TikTok's oEmbed answer (title,
    /// creator, thumbnail). A video is kept as a link pin with its cover picture; the video itself is
    /// never saved. nil when neither the page nor oEmbed said anything.
    nonisolated static func read(_ url: URL) async -> ResolvedLink? {
        var post: TikTokPost? = nil
        var address = url
        // Only an answer from TikTok itself is read: a link that leads away from TikTok (an open
        // redirect) must not hand its page's data over as TikTok's.
        if case .html(let html, let finalURL)? = await LinkFetcher.fetchPage(url),
           isTikTok(finalURL), !(LoginWall.isWallAddress(finalURL) && !SmartLinkText.samePage(finalURL, url)) {
            address = finalURL   // (a short link: where it led)
            post = parse(html: html)
        }
        var embed: OEmbed? = nil
        if let oEmbed = oEmbedURL(for: address), let data = await LinkFetcher.fetchData(oEmbed, userAgent: PinterestReader.userAgent) {
            embed = OEmbed.parse(data)
        }
        guard var resolved = ResolvedLink.tikTok(post, embed: embed, url: address) else { return nil }
        resolved.imageData = await LinkFetcher.downloadPicture(from: ResolvedLink.tikTokPictures(post, embed: embed))
        resolved.becomesLinkWithoutPicture()
        return resolved
    }
}

extension InstagramReader {
    /// An Instagram post: its page's tags, else (for a login page) its embed page. A post that can't
    /// be read either way is a plain link — never the login page's words or picture.
    nonisolated static func read(_ url: URL) async -> ResolvedLink? {
        guard let code = shortcode(in: url), let address = postAddress(code: code) else { return nil }
        var post: InstagramPost? = nil
        if case .html(let html, let finalURL)? = await LinkFetcher.fetchPage(address) {
            post = parse(html: html, finalURL: finalURL, requestedURL: address)
        }
        if post == nil, let embedURL = embedAddress(code: code), case .html(let html, _)? = await LinkFetcher.fetchPage(embedURL) {
            post = parseEmbed(html: html)
        }
        guard let post else { return ResolvedLink.blocked(url: url) }
        var resolved = ResolvedLink.instagram(post, url: address)
        resolved.imageData = await LinkFetcher.downloadPicture(from: post.pictureURLs)
        resolved.becomesLinkWithoutPicture()
        return resolved
    }
}

extension TwitterReader {
    /// A post on X: its text, writer and date from oEmbed (no sign-in, no key). nil when oEmbed
    /// doesn't answer (the page is then read as an ordinary page).
    nonisolated static func read(_ url: URL) async -> ResolvedLink? {
        guard let address = oEmbedURL(for: url),
              let data = await LinkFetcher.fetchData(address, userAgent: PinterestReader.userAgent),
              let tweet = parse(oEmbed: data) else { return nil }
        return ResolvedLink.tweet(tweet, url: url)
    }
}

// MARK: - The library's side

extension LibraryStore {
    /// What the status pill says while a link is read.
    static let readingLinkStatus = "Reading the link…"
    /// What it says while a link to a video file is downloaded.
    static let downloadingVideoStatus = "Downloading the video…"

    /// The items a link becomes: the link itself (with what reading it found), or the picture or
    /// video it leads to. With reading off (or offline) it is the plain link, as before; a link
    /// that can't be read is too (its preview is then fetched after the import, the old way).
    /// The status pill says "Reading the link…" meanwhile, on the side the link goes to.
    func prepareLinkSmart(_ url: URL, scope: PinScope) async -> [PendingImport] {
        guard AppSettings.shared.readsLinksFully else { return [prepareLink(url, scope: scope)] }
        if let known = knownPinterestItem(for: url, scope: scope) { return [known] }
        let previousStatus = importStatus
        let previousScope = importStatusScope
        setImportStatus(LibraryStore.readingLinkStatus, scope: scope)
        let items = await readLinkItems(url, scope: scope)
        // Put back what the pill said before (an import's "Reading 2 of 3…"), unless something
        // else has said something since.
        if importStatus == LibraryStore.readingLinkStatus || importStatus == LibraryStore.downloadingVideoStatus {
            setImportStatus(previousStatus, scope: previousScope)
        }
        return items
    }

    /// The reading behind `prepareLinkSmart`. After the wait, nothing is prepared when another
    /// profile is in use now (the batch belongs to the library it was started in).
    private func readLinkItems(_ url: URL, scope: PinScope) async -> [PendingImport] {
        let profile = profileID
        // A link going to Hidden is never searched for on the web (its title would leave without a tap).
        let found = await LinkResolver.resolve(url, settings: AppSettings.shared, searchesWeb: scope == .visible)
        guard isCurrentProfile(profile) else { return [] }
        guard var resolved = found else { return [prepareLink(url, scope: scope)] }
        resolved.url = keptLink(resolved.url)
        if resolved.route == .video {
            let items = await prepareVideoItems(resolved, scope: scope, profile: profile)
            guard isCurrentProfile(profile) else {
                LibraryStore.discardTemporaryCopies(of: items)
                return []
            }
            if !items.isEmpty { return items }
            resolved = resolved.withoutVideo()   // the video couldn't be had: its picture (or the link) instead
        }
        if let data = resolved.imageData, resolved.route == .picture {
            return [await preparePictureItem(data, resolved: resolved, scope: scope)]
        }
        var item = prepareLink(resolved.url, scope: scope)
        item.resolvedLink = resolved
        return [item]
    }

    /// A Pinterest pin saved before (on this side of the library, as a picture or video pin): the
    /// item that puts that pin on the chosen boards instead of downloading it again.
    private func knownPinterestItem(for url: URL, scope: PinScope) -> PendingImport? {
        guard LinkClassifier.isPinterest(url), let number = LinkClassifier.pinterestPinID(in: url),
              let address = PinterestReader.pinAddress(number) else { return nil }
        return itemForSavedSource(keptLink(address).absoluteString, scope: scope)
    }

    /// The item for a web page saved before as a picture or video pin (like a web result saved
    /// twice: committing it just puts that pin on the chosen boards).
    private func itemForSavedSource(_ source: String, scope: PinScope) -> PendingImport? {
        guard let existingID = pinID(forSourceURL: source, scope: scope), let existing = livePin(existingID) else { return nil }
        return PendingImport(payload: .image(Data(), title: "", sourceURL: nil, credit: nil), profileID: profileID, identicalTo: existing)
    }

    /// A picture a link led to, as an item: the link is its source page (a Pinterest pin's page,
    /// or the picture's own address), and what was read travels with it.
    private func preparePictureItem(_ data: Data, resolved: ResolvedLink, scope: PinScope) async -> PendingImport {
        let source = resolved.url.absoluteString
        var extras = resolved
        extras.imageData = nil   // the picture itself travels in the item
        let fileName = cleanFileName(resolved.url.deletingPathExtension().lastPathComponent)
        let title = resolved.title.map { (text: String) -> String in TitleGenerator.shorten(text, to: 60) }
            ?? (resolved.flavor == .imageFile ? fileName : "")
        var item = await prepareImage(data, title: title, sourceURL: source, credit: nil, scope: scope)
        item.resolvedLink = extras
        if let existingID = pinID(forSourceURL: source, scope: scope), let existing = livePin(existingID) {
            item.identicalTo = existing   // saved before: it goes on the boards instead
        }
        return item
    }

    /// A link that is itself a video file (an .mp4 or .mov address): downloaded to a temporary file
    /// ("Downloading the video…"), then prepared like a video chosen in Files. [] when it can't be
    /// downloaded or read.
    private func prepareVideoItems(_ resolved: ResolvedLink, scope: PinScope, profile: UUID) async -> [PendingImport] {
        guard let videoURL = resolved.videoURL, resolved.flavor == .videoFile else { return [] }
        if let known = itemForSavedSource(resolved.url.absoluteString, scope: scope) { return [known] }
        setImportStatus(LibraryStore.downloadingVideoStatus, scope: scope)
        guard !Task.isCancelled, let file = await LinkFetcher.downloadVideo(videoURL) else { return [] }
        let downloaded = (file: file, address: videoURL)
        guard isCurrentProfile(profile) else {
            try? FileManager.default.removeItem(at: downloaded.file)
            return []
        }
        let fileName = cleanFileName(downloaded.address.deletingPathExtension().lastPathComponent)
        let title = resolved.title.map { (text: String) -> String in TitleGenerator.shorten(text, to: 60) } ?? fileName
        var items = await prepareVideo(at: downloaded.file, title: title, scope: scope)
        if items.isEmpty {
            try? FileManager.default.removeItem(at: downloaded.file)   // not a video this device can read
            return []
        }
        var extras = resolved
        extras.imageData = nil
        extras.videoURL = nil
        for index in items.indices { items[index].resolvedLink = extras }
        return items
    }

    /// Fills a new link pin in with what was read before the import (instead of fetching the page
    /// again): see `ResolvedLink.fill`. Its picture is stored as the link's preview. Written only
    /// while the pin still links to the same page (it may be pointed elsewhere meanwhile, see
    /// `fetchLinkPreview`) and the same profile is in use.
    func applyResolvedLink(_ resolved: ResolvedLink, to id: UUID) async {
        let profile = profileID
        guard let pin = pin(id), pin.isLink, let link = pin.linkURL,
              LibraryStore.previewStillWanted(for: pin, fetched: resolved.url.absoluteString) else { return }
        // A re-read that found less than the article (a teaser or a cookie page, read as an
        // ordinary page): the article stays as it was — its title, description and picture too.
        if resolved.flavor == .page, resolved.text == nil, pin.linkFlavor == .article { return }
        modify(id) { (pin: inout Pin) in resolved.fill(&pin) }
        if let data = resolved.imageData {
            await attachImage(data, to: id, forPage: link)
            guard isCurrentProfile(profile), LibraryStore.previewStillWanted(for: self.pin(id), fetched: link) else { return }
        }
        modify(id) { (pin: inout Pin) in pin.needsAnalysis = true }
        scheduleSave()
        startAnalysisIfNeeded()
    }

    /// Keeps what was read about a link with the picture or video pin the link became (see
    /// `ResolvedLink.fillExtras`).
    func applyLinkExtras(_ resolved: ResolvedLink, to id: UUID) {
        guard pin(id) != nil else { return }
        modify(id) { (pin: inout Pin) in resolved.fillExtras(&pin) }
        scheduleSave()
    }

    /// "Read link again" (a pin page's ⋯ menu and its link panel): reads a link pin's page again
    /// and keeps what it finds (see `applyResolvedLink`). A link that leads to a picture (a
    /// Pinterest picture pin, a picture file) becomes a picture pin in place. A link to a video stays
    /// a link pin (with the video's picture). With reading off, or when nothing came back, the
    /// preview is fetched the old way. Returns whether the link was read.
    @discardableResult
    func readLink(for id: UUID) async -> Bool {
        await readLink(for: id, showsStatus: true, fallsBack: true)
    }

    /// See `readLink(for:)`. `showsStatus`: the pill says "Reading the link…" (off while "Read
    /// existing links" says "Reading link 3 of 12…"). `fallsBack`: fetch the preview the old way
    /// when reading fails.
    func readLink(for id: UUID, showsStatus: Bool, fallsBack: Bool) async -> Bool {
        let settings = AppSettings.shared
        guard let pin = livePin(id), pin.isLink, let link = pin.linkURL, let url = URL(string: link) else { return false }
        guard settings.readsLinksFully else {
            if fallsBack { await fetchLinkPreview(for: id) }
            return false
        }
        let profile = profileID
        let side = scope(of: pin)   // a hidden pin's work is never shown on the normal side
        if showsStatus { setImportStatus(LibraryStore.readingLinkStatus, scope: side) }
        let found = await LinkResolver.resolve(url, settings: settings, titleHint: pin.title, keepsPicture: pin.hasPreview,
                                               searchesWeb: side == .visible)   // a hidden link is never searched for
        if showsStatus { setImportStatus(nil, scope: side) }
        guard isCurrentProfile(profile), LibraryStore.previewStillWanted(for: self.pin(id), fetched: link) else { return false }
        guard var resolved = found else {
            if fallsBack { await fetchLinkPreview(for: id) }
            return false
        }
        let canonical = resolved.url   // a Pinterest pin's own address, "…/pin/<number>/"
        resolved.url = url   // the pin keeps its own address
        if let data = resolved.imageData, resolved.videoURL == nil, resolved.flavor == .pinterest || resolved.flavor == .imageFile {
            // Its source page, as for a picture shared fresh: a Pinterest pin's own address (so
            // sharing that pin again is recognised), else the picture's link.
            let source = resolved.flavor == .pinterest ? keptLink(canonical).absoluteString : link
            return await turnIntoPicture(id, data: data, resolved: resolved, link: link, source: source, profile: profile)
        }
        await applyResolvedLink(resolved, to: id)
        return true
    }

    /// A link pin whose link leads to a picture becomes that picture's pin, as one shared fresh
    /// would be: the picture is stored (the same way a preview is), then the pin turns into a
    /// picture pin whose source page is `source` (see `becomePicture`), keeping its boards, tags,
    /// note and a title the person typed; its untouched picture goes to the originals folder when
    /// those are kept (Settings › iCloud & storage).
    private func turnIntoPicture(_ id: UUID, data: Data, resolved: ResolvedLink, link: String, source: String,
                                 profile: UUID) async -> Bool {
        let revisionBefore = pin(id)?.pictureRevision ?? 0
        await attachImage(data, to: id, forPage: link)
        guard isCurrentProfile(profile), let now = pin(id), now.isLink, now.hasPreview, now.pictureRevision > revisionBefore,
              LibraryStore.previewStillWanted(for: now, fetched: link) else { return false }
        modify(id) { (pin: inout Pin) in LibraryStore.becomePicture(&pin, resolved: resolved, source: source) }
        scheduleSave()
        startAnalysisIfNeeded()
        await keepConvertedOriginal(data, for: id, profile: profile)
        return true
    }

    /// What a link pin turned into its picture's pin becomes (a plain rule, so the tests check it):
    /// what was read is written in (`ResolvedLink.fill`), and it becomes a picture pin whose source
    /// page is `source`. Like a picture pin shared fresh, a title that wasn't typed (or written by
    /// the AI) is at most 60 characters, and it is nobody's look-alike yet.
    nonisolated static func becomePicture(_ pin: inout Pin, resolved: ResolvedLink, source: String) {
        resolved.fill(&pin)
        pin.kind = .image
        pin.hasPreview = false
        pin.sourceURL = source
        pin.linkURL = nil
        pin.duration = nil
        pin.duplicateOfID = nil
        if !pin.titleEditedByUser, !pin.titleIsAuto, pin.title.count > 60 {
            pin.setImportedTitle(TitleGenerator.shorten(pin.title, to: 60))
        }
        pin.needsAnalysis = true
    }

    /// Keeps the untouched picture of a link pin that became a picture pin in the originals
    /// folder, as a picture shared fresh does (see `keepOriginalPicture`). Never for a hidden pin:
    /// nothing hidden goes to that folder. When the pin was hidden, changed or removed meanwhile,
    /// or another profile is in use now, the copy is taken out again.
    private func keepConvertedOriginal(_ data: Data, for id: UUID, profile: UUID) async {
        guard let before = pin(id), !isHidden(before), before.originalName == nil else { return }
        guard let kept = await keepOriginalPicture(data, for: id, profile: profile) else { return }
        guard isCurrentProfile(profile), let now = pin(id), now.kind == .image, !isHidden(now), now.originalName == nil,
              now.pictureRevision == before.pictureRevision else {
            LibraryStore.dropOriginal(kept.name, in: kept.folder)
            return
        }
        modify(id) { (pin: inout Pin) in
            pin.originalName = kept.name
            pin.originalBytes = kept.bytes
        }
        scheduleSave()
    }

    /// Whether "Read existing links" takes this pin: a link that was never read fully, or one that
    /// was read as an ordinary page or an article and still has no picture (reading it again may
    /// find one now: one of the page's own pictures, or the web search's). A link that was read
    /// as anything else, or has its picture, is left alone. One rule for the run and for the count
    /// on the Settings button, so the two always agree.
    nonisolated static func wantsReading(_ pin: Pin) -> Bool {
        guard pin.isLink else { return false }
        guard let flavor = pin.linkFlavor else { return true }
        return !pin.hasPreview && (flavor == .page || flavor == .article)
    }

    /// Settings › Links › "Read existing links": reads every link pin of `scope` that
    /// `wantsReading` takes (never read fully, or read without finding a picture), one at a time
    /// (the pill says "Reading link 3 of 12…"), with a short pause
    /// between links. It stops when its task is cancelled ("Stop") or another profile is opened.
    /// `progress` hears (links done, links in all) as it goes.
    @discardableResult
    func readAllLinks(scope: PinScope, progress: (@MainActor (Int, Int) -> Void)? = nil) async -> LinkReadingSummary {
        let profile = profileID
        let ids = pins(scope: scope).filter { (pin: Pin) -> Bool in LibraryStore.wantsReading(pin) }
            .map { (pin: Pin) -> UUID in pin.id }
        var summary = LinkReadingSummary(total: ids.count)
        guard !ids.isEmpty else { return summary }
        beginLibraryWork()
        defer { endLibraryWork() }
        for (index, id) in ids.enumerated() {
            if Task.isCancelled || !isCurrentProfile(profile) {
                summary.stopped = true
                break
            }
            guard let pin = livePin(id), LibraryStore.wantsReading(pin), self.scope(of: pin) == scope else { continue }
            setImportStatus("Reading link \(index + 1) of \(ids.count)…", scope: scope)
            progress?(index, ids.count)
            let wasRead = await readLink(for: id, showsStatus: false, fallsBack: false)
            if Task.isCancelled {
                // "Stop" while this link was being read: it was given up on, it isn't one that
                // couldn't be read (one read before Stop reached it still counts as read).
                if wasRead { summary.read += 1 }
                summary.stopped = true
                break
            }
            if wasRead {
                summary.read += 1
            } else {
                summary.unread += 1
            }
            if index + 1 < ids.count { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        setImportStatus(nil, scope: scope)
        progress?(summary.read + summary.unread, ids.count)
        return summary
    }
}

// MARK: - "Read existing links" while it runs

/// "Read existing links" (Settings › Links) while it runs: how far it has got, and a way to stop
/// it. There is one for the whole app, so it goes on — and can still be stopped — after Settings
/// is closed and opened again.
@MainActor
final class LinkReadingJob: ObservableObject {
    static let shared = LinkReadingJob()

    @Published private(set) var isRunning = false
    @Published private(set) var isStopping = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    private var task: Task<Void, Never>? = nil

    /// Starts reading the normal side's unread links (nothing happens while a run is going).
    /// `finished` hears how it went.
    func start(store: LibraryStore, finished: @escaping @MainActor @Sendable (LinkReadingSummary) -> Void) {
        guard task == nil else { return }
        isRunning = true
        isStopping = false
        done = 0
        total = 0
        task = Task { @MainActor [weak self] in
            let summary = await store.readAllLinks(scope: .visible) { (done: Int, total: Int) in
                self?.done = done
                self?.total = total
            }
            self?.task = nil
            self?.isRunning = false
            self?.isStopping = false
            finished(summary)
        }
    }

    /// "Stop": the link being read is finished off, then it stops.
    func stop() {
        guard task != nil else { return }
        isStopping = true
        task?.cancel()
    }

    /// "Reading 3 of 12…" (or "Stopping…").
    var progressText: String {
        if isStopping { return "Stopping…" }
        guard total > 0 else { return "Reading…" }
        return "Reading \(min(done + 1, total)) of \(total)…"
    }
}
