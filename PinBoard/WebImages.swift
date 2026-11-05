//
//  WebImages.swift  —  PinBoard
//
//  "Explore" — searching openly-licensed image sources on the web and saving
//  results into the library with one tap.
//
//  Safety rules that every source follows:
//    • only HTTPS URLs are ever loaded or downloaded,
//    • API keys go only to their own service, in the header/parameter that
//      service documents, and are redacted from the diagnostics text,
//    • downloads are capped in size,
//    • nothing is fetched until you ask (unless "Automatically load" is on).
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Sources

enum WebImageSource: String, CaseIterable, Identifiable {
    case commons, openverse, pexels, pixabay, unsplash
    var id: String { rawValue }

    var label: String {
        switch self {
        case .commons: return "Wikimedia Commons"
        case .openverse: return "Openverse"
        case .pexels: return "Pexels"
        case .pixabay: return "Pixabay"
        case .unsplash: return "Unsplash"
        }
    }

    var needsKey: Bool {
        switch self {
        case .commons, .openverse: return false
        case .pexels, .pixabay, .unsplash: return true
        }
    }

    var signupURL: URL? {
        switch self {
        case .commons: return URL(string: "https://commons.wikimedia.org/wiki/Commons:Welcome")
        case .openverse: return URL(string: "https://api.openverse.org/v1/#tag/auth/operation/register")
        case .pexels: return URL(string: "https://www.pexels.com/api/")
        case .pixabay: return URL(string: "https://pixabay.com/api/docs/")
        case .unsplash: return URL(string: "https://unsplash.com/developers")
        }
    }
}

/// One search result from the web.
struct WebImage: Identifiable, Hashable, Sendable {
    var id: String
    var title: String?
    var thumbURL: URL
    var fullURL: URL
    var pageURL: URL
    var width: Double
    var height: Double
    var credit: String?
    /// The same credit with links, where the source asks for them (Unsplash: the photographer's
    /// page and Unsplash's, both tagged with where the visit came from). nil: `credit` as plain text.
    var linkedCredit: WebImageCredit? = nil
    /// Where saving this picture must be reported (Unsplash's `download_location`); nil for the
    /// other sources, which ask for nothing of the kind.
    var downloadLocation: URL? = nil

    var aspectRatio: CGFloat { CGFloat(max(width, 1) / max(height, 1)) }
}

/// "Photo by Jane Doe on Unsplash", with a link on the name and one on the site, as Unsplash's
/// API guidelines require.
struct WebImageCredit: Hashable, Sendable {
    var name: String
    var profileURL: URL
    var siteName: String
    var siteURL: URL

    /// The line as text with its two links (for a SwiftUI `Text`).
    var attributed: AttributedString {
        var name = AttributedString(self.name)
        name.link = profileURL
        var site = AttributedString(siteName)
        site.link = siteURL
        return AttributedString("Photo by ") + name + AttributedString(" on ") + site
    }
}

struct WebPage: Sendable {
    var images: [WebImage]
    var hasMore: Bool
    var nextOffset: Int      // Commons uses an offset instead of page numbers
}

enum WebImageError: LocalizedError {
    case missingKey(WebImageSource)
    case rateLimited(WebImageSource)
    case badResponse(Int)
    case tooLarge
    case insecureURL
    case offline
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let source):
            return source.needsKey
                ? "\(source.label) needs an API key. Add one in \(SettingsCatalog.path(.imageSource)), or switch to Wikimedia Commons."
                : "\(source.label) refused the request (not authorized)."
        case .rateLimited(let source):
            return source == .openverse
                ? "Openverse's free limit was reached (about 5 searches per hour without credentials). Add credentials in \(SettingsCatalog.path(.imageSource)) or switch source."
                : "\(source.label) says too many requests. Try again in a little while."
        case .badResponse(let code):
            return "The image service replied with an error (\(code))."
        case .tooLarge:
            return "That image is too large to download."
        case .insecureURL:
            return "The image service returned an address that isn't HTTPS, so it was skipped."
        case .offline:
            return "Offline mode is on (Settings), so nothing is fetched from the web."
        case .network(let text):
            return text
        }
    }
}

// MARK: - Diagnostics (shown under "No web results" so problems can be reported)

/// Remembers the last request and reply of a web search, with any secret redacted.
///
/// There is no one notebook for the whole app, on purpose: the notes hold the words that were
/// searched for, and a hidden board's or hidden pin's search must never leave them where the
/// normal side's Explore shows them under "Details" (or "Copy details" puts them on the clipboard).
/// So each web feed (`WebFeedView`) keeps notes of its own and runs its searches inside
/// `WebDiagnostics.taskNotes.withValue(notes) { … }`; only that feed shows them.
final class WebDiagnostics: @unchecked Sendable {
    /// Holds the notes of the running task: what is bound with `withValue` is `current` for the
    /// code inside it, for every task that code starts, and for nobody else. (This is what the
    /// `@TaskLocal` attribute would write for us. It is spelled out because the attribute is a
    /// Swift macro, and plain code needs no macro support from the compiler.)
    static let taskNotes = TaskLocal<WebDiagnostics>(wrappedValue: WebDiagnostics())

    /// The notes the search of the running task writes into. A web feed makes its own (see above).
    /// A search that no feed asked for lands in the default notebook, which nothing ever shows
    /// (a link's picture search, LinkPins.swift, uses a throwaway notebook instead, so even the
    /// default one never holds a hidden link's title).
    static var current: WebDiagnostics { taskNotes.get() }

    private let lock = NSLock()
    private var lines: [String] = []

    func record(_ line: String, secrets: [String] = []) {
        var text = line
        for secret in secrets where secret.count >= 4 {
            text = text.replacingOccurrences(of: secret, with: "•••")
        }
        lock.lock()
        lines.append(text)
        if lines.count > 12 { lines.removeFirst(lines.count - 12) }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        lines = []
        lock.unlock()
    }

    var report: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Service

enum WebImageService {
    /// How PinBoard names itself to the image services (Wikimedia asks every app to say who it is).
    /// TODO for the owner: add the public contact address once there is one, e.g. "(…; you@example.com)".
    static let userAgent = "PinBoard/1.0 (iPhone and iPad app)"
    static let maximumDownloadBytes = 30 * 1024 * 1024

    /// Cached Openverse bearer token (only when credentials are configured).
    private final class TokenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String? = nil
        private var expires = Date.distantPast

        func current() -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard let value, expires > Date().addingTimeInterval(60) else { return nil }
            return value
        }

        func store(_ token: String, lifetime: Double) {
            lock.lock()
            value = token
            expires = Date().addingTimeInterval(lifetime)
            lock.unlock()
        }
    }
    private static let tokenCache = TokenCache()

    /// A throwaway connection for everything web-related: no cookies, no
    /// persistent cache, nothing remembered between searches.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        configuration.timeoutIntervalForRequest = 25
        return URLSession(configuration: configuration)
    }()

    /// Accepts only well-formed HTTPS addresses.
    static func httpsURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        return request
    }

    /// Downloads a file (used when saving a web image into the library).
    /// Stops early — before the body is read — when the file is too large.
    static func download(_ url: URL) async throws -> Data {
        guard await MainActor.run(body: { AppSettings.shared.webAllowed }) else { throw WebImageError.offline }
        guard url.scheme?.lowercased() == "https" else { throw WebImageError.insecureURL }
        var request = makeRequest(url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if !(200...299).contains(http.statusCode) { throw WebImageError.badResponse(http.statusCode) }
        }
        if response.expectedContentLength > Int64(maximumDownloadBytes) { throw WebImageError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(maximumDownloadBytes)))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumDownloadBytes { throw WebImageError.tooLarge }
        }
        return data
    }

    /// Searches `source`. `page` starts at 1; `offset` is only used by Commons.
    static func search(_ query: String,
                       source: WebImageSource,
                       page: Int,
                       offset: Int,
                       perPage: Int = 30,
                       apiKey: String,
                       secondaryKey: String = "") async throws -> WebPage {
        guard await MainActor.run(body: { AppSettings.shared.webAllowed }) else { throw WebImageError.offline }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return WebPage(images: [], hasMore: false, nextOffset: 0) }
        if source.needsKey, apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            throw WebImageError.missingKey(source)
        }
        WebDiagnostics.current.reset()
        WebDiagnostics.current.record("Source: \(source.label) · query “\(trimmed)” · page \(page) · offset \(offset)")
        do {
            let result: WebPage
            switch source {
            case .commons: result = try await searchCommons(trimmed, offset: offset, perPage: perPage)
            case .openverse: result = try await searchOpenverse(trimmed, page: page, perPage: perPage, clientID: apiKey, clientSecret: secondaryKey)
            case .pexels: result = try await searchPexels(trimmed, page: page, perPage: perPage, key: apiKey)
            case .pixabay: result = try await searchPixabay(trimmed, page: page, perPage: perPage, key: apiKey)
            case .unsplash: result = try await searchUnsplash(trimmed, page: page, perPage: perPage, key: apiKey)
            }
            WebDiagnostics.current.record("Usable results: \(result.images.count) · more available: \(result.hasMore)")
            return result
        } catch let error as WebImageError {
            WebDiagnostics.current.record("Error: \(error.localizedDescription)")
            throw error
        } catch let error as DecodingError {
            WebDiagnostics.current.record("Reply could not be decoded: \(error)")
            throw WebImageError.network("The reply from \(source.label) had an unexpected format.")
        } catch {
            WebDiagnostics.current.record("Error: \(error.localizedDescription)")
            throw WebImageError.network(error.localizedDescription)
        }
    }

    static func fetch(_ request: URLRequest, source: WebImageSource, secrets: [String] = []) async throws -> Data {   // (not private: used by WebImagesUnsplash.swift)
        if let url = request.url {
            WebDiagnostics.current.record("Request: \(url.absoluteString)", secrets: secrets)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let snippet = String(decoding: data.prefix(500), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
        WebDiagnostics.current.record("Reply: HTTP \(status), \(data.count) bytes: \(snippet)", secrets: secrets)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw WebImageError.rateLimited(source) }
            if http.statusCode == 401 || http.statusCode == 403 { throw WebImageError.missingKey(source) }
            if !(200...299).contains(http.statusCode) { throw WebImageError.badResponse(http.statusCode) }
        }
        return data
    }

    static func url(_ base: String, _ items: [String: String]) -> URL? {   // (not private: used by WebImagesUnsplash.swift)
        var components = URLComponents(string: base)
        components?.queryItems = items
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    /// Decodes an element if it can; anything unexpected simply becomes nil
    /// instead of failing the whole page of results.
    struct Lenient<T: Decodable>: Decodable {   // (not private: used by WebImagesUnsplash.swift)
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    // MARK: Wikimedia Commons (no key)

    private struct CommonsResponse: Decodable {
        struct Continue: Decodable { var gsroffset: Int? }
        struct Query: Decodable {
            var pages: [Lenient<Page>]?
            private enum CodingKeys: String, CodingKey { case pages }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                pages = try? c.decodeIfPresent([Lenient<Page>].self, forKey: .pages)
            }
        }
        struct Page: Decodable {
            var pageid: Int
            var title: String
            var index: Int?
            var imageinfo: [Lenient<ImageInfo>]?
        }
        struct ImageInfo: Decodable {
            var thumburl: String?
            var thumbwidth: Double?
            var thumbheight: Double?
            var url: String?
            var descriptionurl: String?
            var width: Double?
            var height: Double?
            var mime: String?
            var extmetadata: [String: MetaValue]?
            private enum CodingKeys: String, CodingKey {
                case thumburl, thumbwidth, thumbheight, url, descriptionurl, width, height, mime, extmetadata
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                thumburl = try? c.decodeIfPresent(String.self, forKey: .thumburl)
                thumbwidth = try? c.decodeIfPresent(Double.self, forKey: .thumbwidth)
                thumbheight = try? c.decodeIfPresent(Double.self, forKey: .thumbheight)
                url = try? c.decodeIfPresent(String.self, forKey: .url)
                descriptionurl = try? c.decodeIfPresent(String.self, forKey: .descriptionurl)
                width = try? c.decodeIfPresent(Double.self, forKey: .width)
                height = try? c.decodeIfPresent(Double.self, forKey: .height)
                mime = try? c.decodeIfPresent(String.self, forKey: .mime)
                extmetadata = try? c.decodeIfPresent([String: MetaValue].self, forKey: .extmetadata)
            }
        }
        struct MetaValue: Decodable {
            var value: String?
            private enum CodingKeys: String, CodingKey { case value }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try? c.decodeIfPresent(String.self, forKey: .value)
            }
        }
        struct APIError: Decodable { var code: String?; var info: String? }
        var `continue`: Continue?
        var query: Query?
        var error: APIError?
    }

    private static func searchCommons(_ query: String, offset: Int, perPage: Int, photosOnlyFilter: Bool = true) async throws -> WebPage {
        // "filetype:bitmap" asks the search itself for photos/graphics only. If
        // that ever comes back empty on the first page, the search is repeated
        // without it and the results are filtered here instead.
        let searchText = photosOnlyFilter ? "\(query) filetype:bitmap" : query
        guard let url = url("https://commons.wikimedia.org/w/api.php", [
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "generator": "search",
            "gsrsearch": searchText,
            "gsrnamespace": "6",
            "gsrlimit": "\(min(perPage, 50))",
            "gsroffset": "\(offset)",
            "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": "800",
            "iiextmetadatafilter": "Artist|LicenseShortName"
        ]) else { return WebPage(images: [], hasMore: false, nextOffset: 0) }

        let data = try await fetch(makeRequest(url), source: .commons)
        let decoded = try JSONDecoder().decode(CommonsResponse.self, from: data)
        if let apiError = decoded.error {
            throw WebImageError.network("Wikimedia Commons: \(apiError.info ?? apiError.code ?? "unknown error")")
        }
        let pages = (decoded.query?.pages ?? []).compactMap { $0.value }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        WebDiagnostics.current.record("Pages in reply: \(pages.count)")
        if pages.isEmpty, offset == 0, photosOnlyFilter {
            WebDiagnostics.current.record("Nothing with the photo filter; retrying without it.")
            return try await searchCommons(query, offset: offset, perPage: perPage, photosOnlyFilter: false)
        }

        var images: [WebImage] = []
        for page in pages {
            guard let info = page.imageinfo?.first?.value,
                  let thumb = httpsURL(info.thumburl),
                  let fullString = info.url,
                  let full = httpsURL(fullString) else { continue }
            let mime = (info.mime ?? "").lowercased()
            let lowered = fullString.lowercased()
            let isPhoto = mime.hasPrefix("image/jpeg") || mime.hasPrefix("image/png") || mime.hasPrefix("image/webp")
                || lowered.hasSuffix(".jpg") || lowered.hasSuffix(".jpeg") || lowered.hasSuffix(".png") || lowered.hasSuffix(".webp")
            guard isPhoto else { continue }
            let width = info.width ?? info.thumbwidth ?? 1
            let height = info.height ?? info.thumbheight ?? 1
            // Originals can be enormous; ask for a 1600 px version instead when possible.
            var saveURL = full
            if width > 1800, let thumbString = info.thumburl,
               let bigger = httpsURL(thumbString.replacingOccurrences(of: "/800px-", with: "/1600px-")) {
                saveURL = bigger
            }
            let artist = info.extmetadata?["Artist"]?.value?.strippingHTML
            let license = info.extmetadata?["LicenseShortName"]?.value?.strippingHTML
            var creditParts: [String] = []
            if let artist, !artist.isEmpty { creditParts.append(TitleGenerator.shorten(artist, to: 40)) }
            if let license, !license.isEmpty { creditParts.append(license) }
            creditParts.append("Wikimedia Commons")
            let title = page.title
                .replacingOccurrences(of: "File:", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let cleanTitle = (title as NSString).deletingPathExtension
            images.append(WebImage(id: "commons-\(page.pageid)",
                                   title: cleanTitle,
                                   thumbURL: thumb,
                                   fullURL: saveURL,
                                   pageURL: httpsURL(info.descriptionurl) ?? full,
                                   width: width,
                                   height: height,
                                   credit: creditParts.joined(separator: " · ")))
        }
        let next = decoded.`continue`?.gsroffset
        return WebPage(images: images, hasMore: next != nil, nextOffset: next ?? 0)
    }

    // MARK: Openverse

    private struct OpenverseResponse: Decodable {
        struct Result: Decodable {
            var id: String
            var title: String?
            var url: String?
            var thumbnail: String?
            var width: Double?
            var height: Double?
            var creator: String?
            var foreign_landing_url: String?
            var license: String?
            var provider: String?
        }
        var page_count: Int?
        var page: Int?
        var results: [Lenient<Result>]?
    }

    private struct OpenverseToken: Decodable {
        var access_token: String
        var expires_in: Double?
    }

    private static func openverseBearer(clientID: String, clientSecret: String) async -> String? {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else { return nil }
        if let cached = tokenCache.current() { return cached }

        guard let url = URL(string: "https://api.openverse.org/v1/auth_tokens/token/") else { return nil }
        var request = makeRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "client_secret", value: secret)
        ]
        request.httpBody = (form.percentEncodedQuery ?? "").data(using: .utf8)
        guard let reply = try? await session.data(for: request),
              let token = try? JSONDecoder().decode(OpenverseToken.self, from: reply.0) else {
            WebDiagnostics.current.record("Openverse: could not get a token with the saved credentials; searching anonymously.")
            return nil
        }
        tokenCache.store(token.access_token, lifetime: token.expires_in ?? 3600)
        return token.access_token
    }

    private static func searchOpenverse(_ query: String, page: Int, perPage: Int, clientID: String, clientSecret: String) async throws -> WebPage {
        // Openverse allows at most 20 results per page without credentials (50 with).
        let bearer = await openverseBearer(clientID: clientID, clientSecret: clientSecret)
        let pageSize = min(perPage, bearer == nil ? 20 : 50)
        guard let url = url("https://api.openverse.org/v1/images/", [
            "q": query,
            "page": "\(page)",
            "page_size": "\(pageSize)",
            "mature": "false"
        ]) else { return WebPage(images: [], hasMore: false, nextOffset: 0) }
        var request = makeRequest(url)
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let data = try await fetch(request, source: .openverse, secrets: [bearer ?? ""])
        let decoded = try JSONDecoder().decode(OpenverseResponse.self, from: data)
        var images: [WebImage] = []
        for result in (decoded.results ?? []).compactMap({ $0.value }) {
            guard let full = httpsURL(result.url) else { continue }
            let thumb = httpsURL(result.thumbnail) ?? full
            var creditParts: [String] = []
            if let creator = result.creator, !creator.isEmpty { creditParts.append(TitleGenerator.shorten(creator, to: 40)) }
            if let license = result.license, !license.isEmpty { creditParts.append(license.uppercased()) }
            creditParts.append(result.provider?.titleCased ?? "Openverse")
            images.append(WebImage(id: "openverse-\(result.id)",
                                   title: result.title,
                                   thumbURL: thumb,
                                   fullURL: full,
                                   pageURL: httpsURL(result.foreign_landing_url) ?? full,
                                   width: result.width ?? 1,
                                   height: result.height ?? 1,
                                   credit: creditParts.joined(separator: " · ")))
        }
        let hasMore = page < (decoded.page_count ?? page)
        return WebPage(images: images, hasMore: hasMore, nextOffset: 0)
    }

    // MARK: Pexels

    private struct PexelsResponse: Decodable {
        struct Photo: Decodable {
            struct Src: Decodable {
                var original: String?
                var large2x: String?
                var large: String?
                var medium: String?
            }
            var id: Int
            var width: Double?
            var height: Double?
            var url: String?
            var photographer: String?
            var alt: String?
            var src: Src?
        }
        var photos: [Lenient<Photo>]?
        var next_page: String?
    }

    private static func searchPexels(_ query: String, page: Int, perPage: Int, key: String) async throws -> WebPage {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = url("https://api.pexels.com/v1/search", [
            "query": query,
            "page": "\(page)",
            "per_page": "\(perPage)"
        ]) else { return WebPage(images: [], hasMore: false, nextOffset: 0) }
        var request = makeRequest(url)
        request.setValue(cleanKey, forHTTPHeaderField: "Authorization")
        let data = try await fetch(request, source: .pexels, secrets: [cleanKey])
        let decoded = try JSONDecoder().decode(PexelsResponse.self, from: data)
        var images: [WebImage] = []
        for photo in (decoded.photos ?? []).compactMap({ $0.value }) {
            guard let thumb = httpsURL(photo.src?.medium ?? photo.src?.large) else { continue }
            let full = httpsURL(photo.src?.large2x ?? photo.src?.large ?? photo.src?.original) ?? thumb
            let alt = (photo.alt ?? "").trimmingCharacters(in: .whitespaces)
            images.append(WebImage(id: "pexels-\(photo.id)",
                                   title: alt.isEmpty ? nil : alt,
                                   thumbURL: thumb,
                                   fullURL: full,
                                   pageURL: httpsURL(photo.url) ?? full,
                                   width: photo.width ?? 1,
                                   height: photo.height ?? 1,
                                   credit: "Photo by \(photo.photographer ?? "unknown") · Pexels"))
        }
        return WebPage(images: images, hasMore: decoded.next_page != nil, nextOffset: 0)
    }

    // MARK: Pixabay

    private struct PixabayResponse: Decodable {
        struct Hit: Decodable {
            var id: Int
            var previewURL: String?
            var webformatURL: String?
            var largeImageURL: String?
            var imageWidth: Double?
            var imageHeight: Double?
            var user: String?
            var pageURL: String?
            var tags: String?
        }
        var totalHits: Int?
        var hits: [Lenient<Hit>]?
    }

    private static func searchPixabay(_ query: String, page: Int, perPage: Int, key: String) async throws -> WebPage {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = url("https://pixabay.com/api/", [
            "key": cleanKey,
            "q": query,
            "image_type": "photo",
            "safesearch": "true",
            "page": "\(page)",
            "per_page": "\(max(3, perPage))"
        ]) else { return WebPage(images: [], hasMore: false, nextOffset: 0) }
        let data = try await fetch(makeRequest(url), source: .pixabay, secrets: [cleanKey])
        let decoded = try JSONDecoder().decode(PixabayResponse.self, from: data)
        var images: [WebImage] = []
        for hit in (decoded.hits ?? []).compactMap({ $0.value }) {
            guard let thumb = httpsURL(hit.webformatURL ?? hit.previewURL) else { continue }
            let full = httpsURL(hit.largeImageURL) ?? thumb
            images.append(WebImage(id: "pixabay-\(hit.id)",
                                   title: hit.tags.map { TitleGenerator.shorten($0.replacingOccurrences(of: ",", with: " ·"), to: 60) },
                                   thumbURL: thumb,
                                   fullURL: full,
                                   pageURL: httpsURL(hit.pageURL) ?? full,
                                   width: hit.imageWidth ?? 1,
                                   height: hit.imageHeight ?? 1,
                                   credit: "Image by \(hit.user ?? "unknown") · Pixabay"))
        }
        let total = decoded.totalHits ?? 0
        return WebPage(images: images, hasMore: page * perPage < min(total, 500), nextOffset: 0)
    }

}

// MARK: - Thumbnails (loaded through the same private connection)

/// In-memory cache of web thumbnails (and a handful of full-size pictures for
/// Quick Look); nothing is written to disk.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let fullCache = NSCache<NSString, UIImage>()
    init() {
        cache.countLimit = 300
        fullCache.countLimit = 6
    }
    func image(for url: URL) -> UIImage? { cache.object(forKey: url.absoluteString as NSString) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url.absoluteString as NSString) }
    func fullImage(for url: URL) -> UIImage? { fullCache.object(forKey: url.absoluteString as NSString) }
    func storeFull(_ image: UIImage, for url: URL) { fullCache.setObject(image, forKey: url.absoluteString as NSString) }
}

/// Shows a web image, fetched with the app's private session (no cookies,
/// proper identification) instead of SwiftUI's default loader.
struct RemoteImageView: View {
    let url: URL
    @State private var image: UIImage? = nil
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            if let cached = RemoteImageCache.shared.image(for: url) {
                image = cached
                return
            }
            let target = url
            let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
                guard let data = try? await WebImageService.download(target),
                      let cgImage = ImageProcessor.downsample(data, maxPixelSize: 900) else {
                    return LoadedImage(image: nil)
                }
                return LoadedImage(image: UIImage(cgImage: cgImage))
            }.value
            if let result = loaded.image {
                RemoteImageCache.shared.store(result, for: url)
                image = result
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Feed (used by Explore, at the end of boards, and under a pin)

/// A masonry grid of web results that loads more as you scroll. Tapping a
/// result opens it as a full pin page; "+" saves it into the library (onto
/// the given boards, asking first if it looks like a pin you already have);
/// a long-press menu has more options. Results stay when you come back.
struct WebFeedView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow

    let query: String
    var boardIDs: [UUID] = []
    /// Saving puts results straight into Hidden (a hidden pin's page with no board).
    var hidden: Bool = false
    var metrics: GridMetrics
    /// Bump this to save every loaded result that is not in the library yet (Explore asks first).
    var saveAllRequest: Int = 0
    /// Told how many of the loaded results are not saved yet, whenever that changes, so
    /// Explore's ⋯ menu can say how many "Save all" would save.
    var onUnsavedCountChange: (Int) -> Void = { _ in }

    @State private var images: [WebImage] = []
    @State private var page = 1
    @State private var offset = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loading: Task<[WebImage], Never>? = nil   // the request running now, if any
    @State private var generation = 0          // bumped by every reload; older requests are ignored
    @State private var errorText: String? = nil
    @State private var savingIDs: Set<String> = []
    @State private var pickingBoardFor: WebImage? = nil
    @State private var quickLook: QuickLookRequest? = nil
    @State private var showDetails = false
    @State private var hasLoaded = false       // at least one request has finished
    @State private var emptyHops = 0           // pages in a row with nothing usable
    @State private var loadedKey = ""          // what the current results belong to
    @State private var searchPage: WebSearchPage? = nil   // a picture's web search, shown in PinBoard's own browser
    /// What this feed's own searches did (its "Details"). Only this feed's searches write here and
    /// only this feed shows it, so a hidden feed's words never reach the normal side's Explore.
    @State private var notes = WebDiagnostics()

    /// Identifies what the current results belong to. Never contains a key.
    private var feedKey: String { "\(query)|\(settings.webSource.rawValue)|\(settings.keysVersion)" }

    /// The side of the library saved results land on: the normal library (Explore, normal
    /// boards and pins), or Hidden for a hidden board's or hidden pin's feed.
    private var scope: PinScope { store.importScope(boardIDs: boardIDs, hidden: hidden) }

    /// Pages already saved on that side — computed once per render, not per card.
    /// (A page saved as a hidden pin never shows as saved in a normal feed.)
    private var savedPages: Set<String> {
        Set(store.pins(scope: scope).compactMap { $0.sourceURL })
    }

    var body: some View {
        let savedPages = savedPages
        let unsavedCount = unsaved(besides: savedPages).count
        VStack(spacing: 12) {
            if !images.isEmpty {
                MasonryGrid(items: images, metrics: metrics,
                            aspectRatio: { $0.aspectRatio },
                            footerHeight: { WebResultCard.footerHeight(for: $0) }) { image in
                    let saved = savedPages.contains(image.pageURL.absoluteString)
                    NavigationLink(value: Route.webImage(image, images, boardIDs: boardIDs, hidden: scope == .hidden)) {
                        WebResultCard(image: image,
                                      isSaved: saved,
                                      isSaving: savingIDs.contains(image.id) && importFlow.isWorking,
                                      onSave: { save(image, to: boardIDs) })
                    }
                    .buttonStyle(.plain)
                    .contextMenu { resultMenu(for: image, saved: saved) }
                    .onAppear {
                        if image.id == images.last?.id { loadMore() }
                    }
                }
            }
            if let errorText {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { reload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    diagnostics
                }
                .padding()
            } else if isLoading {
                ProgressView()
                    .padding()
            } else if images.isEmpty, !query.isEmpty, hasLoaded {
                VStack(spacing: 8) {
                    Text("No web results for “\(query)”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    diagnostics
                }
                .padding()
            } else if !hasMore, !images.isEmpty {
                Text("That's everything for “\(query)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .onAppear {
            // Coming back to this screen keeps the results; only a new query reloads.
            if loadedKey != feedKey { reload() }
            onUnsavedCountChange(unsavedCount)
        }
        .onChange(of: unsavedCount) { _, count in onUnsavedCountChange(count) }
        .onChange(of: feedKey) { reload() }
        .onChange(of: saveAllRequest) { saveAllVisible() }
        .onChange(of: importFlow.isWorking) { _, working in
            // Between the download and the commit a question sheet may be up: still busy.
            if !working, importFlow.review == nil { savingIDs = [] }
        }
        .onChange(of: importFlow.review == nil) { _, closed in
            if closed, !importFlow.isWorking { savingIDs = [] }
        }
        .sheet(item: $pickingBoardFor) { image in
            BoardPickerSheet(title: "Save to…", scope: scope) { chosen in
                if let chosen { settings.lastBoardID = chosen }
                save(image, to: chosen.map { [$0] } ?? [])
            }
            .hiddenPrivacyCover(scope == .hidden)   // a hidden feed's boards never show in the App Switcher
        }
        .fullScreenCover(item: $quickLook) { request in
            QuickLookView(request: request)
        }
        .webSearchSheet($searchPage, hidden: scope == .hidden)
    }

    /// A result's long-press menu. Worded and drawn like Quick Look's menu; "Search this picture
    /// on the web" is `ReverseSearchMenu` (Google Lens, Bing, TinEye, Yandex), the one submenu every
    /// place that offers it uses, with the one label `ReverseSearchMenu.title`.
    @ViewBuilder
    private func resultMenu(for image: WebImage, saved: Bool) -> some View {
        Button {
            save(image, to: boardIDs)
        } label: {
            Label(saved ? "Saved" : "Save to library", systemImage: saved ? "checkmark" : "plus")
        }
        .disabled(saved || savingIDs.contains(image.id))
        Button {
            pickingBoardFor = image
        } label: {
            Label("Save to board…", systemImage: "folder.badge.plus")
        }
        .disabled(savingIDs.contains(image.id))
        Button {
            openQuickLook(at: image)
        } label: {
            Label("Quick look", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        ReverseSearchMenu { (engine: ReverseImageEngine) in
            searchPage = ReverseSearchLauncher.open(engine, imageURL: image.fullURL, settings: settings, flow: importFlow)
        }
        Link(destination: image.pageURL) {
            Label("Open source page", systemImage: "safari")
        }
    }

    /// Quick Look over the results, starting at this one. Near its end it asks
    /// the feed for more, so the feed here grows along with it. Saving there
    /// lands where saving here does (this feed's boards, or Hidden).
    private func openQuickLook(at image: WebImage) {
        let index = images.firstIndex(of: image) ?? 0
        quickLook = .web(images: images, startIndex: index, loadMore: {
            // Everything the feed has after loading the next page; Quick Look skips what it already shows.
            _ = await nextPage()
            return images
        }, boardIDs: boardIDs, hidden: hidden)
    }

    /// What was sent and what came back — so a problem can be reported exactly.
    private var diagnostics: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notes.report)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Copy details") {
                    UIPasteboard.general.string = notes.report
                }
                .font(.caption)
            }
            .padding(.top, 4)
        } label: {
            Text("Details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 600)
    }

    private func reload() {
        generation += 1        // a request for the previous query may still be running; its result is ignored
        loadedKey = feedKey
        images = []
        page = 1
        offset = 0
        hasMore = true
        errorText = nil
        hasLoaded = false
        emptyHops = 0
        isLoading = false
        loading = nil
        loadMore()
    }

    /// Scrolling reached the last result: fetch the next page (once at a time).
    private func loadMore() {
        _ = startLoading()
    }

    /// The next page for Quick Look: joins the request already running, or starts
    /// one. Returns the new results (none when there is nothing more).
    private func nextPage() async -> [WebImage] {
        if let loading { return await loading.value }
        guard let started = startLoading() else { return [] }
        return await started.value
    }

    /// Starts fetching the next page, or returns nil when there is nothing to fetch.
    private func startLoading() -> Task<[WebImage], Never>? {
        guard !isLoading, hasMore, !query.trimmingCharacters(in: .whitespaces).isEmpty, settings.webAllowed else { return nil }
        isLoading = true
        let requestGeneration = generation
        let task = Task { @MainActor () async -> [WebImage] in
            let fresh = await fetchNextPage(generation: requestGeneration)
            if requestGeneration == generation {
                isLoading = false
                loading = nil
            }
            return fresh
        }
        loading = task
        return task
    }

    /// Fetches pages until one brings something new (skipping at most a few with
    /// nothing usable) and adds it to the results.
    private func fetchNextPage(generation requestGeneration: Int) async -> [WebImage] {
        while true {
            let source = settings.webSource
            let key = settings.apiKey(for: source)
            let secret = settings.openverseClientSecret
            let words = query
            let pageNumber = page
            let startOffset = offset
            let ownNotes = notes
            do {
                // The search writes what it does into this feed's own notes (and nobody else's).
                let result = try await WebDiagnostics.taskNotes.withValue(ownNotes) { () async throws -> WebPage in
                    try await WebImageService.search(words,
                                                     source: source,
                                                     page: pageNumber,
                                                     offset: startOffset,
                                                     apiKey: key,
                                                     secondaryKey: secret)
                }
                guard requestGeneration == generation else { return [] }   // the query changed meanwhile
                let known = Set(images.map { $0.id })
                let fresh = result.images.filter { !known.contains($0.id) }
                images += fresh
                page += 1
                offset = result.nextOffset
                errorText = nil
                hasLoaded = true
                if fresh.isEmpty, result.hasMore, emptyHops < 3 {
                    // This page had nothing usable (e.g. only PDFs); look at the next one.
                    emptyHops += 1
                    continue
                }
                emptyHops = 0
                hasMore = result.hasMore && !result.images.isEmpty
                return fresh
            } catch {
                guard requestGeneration == generation else { return [] }
                errorText = error.localizedDescription
                hasLoaded = true
                hasMore = false
                return []
            }
        }
    }

    private func save(_ image: WebImage, to boards: [UUID]) {
        guard !savingIDs.contains(image.id) else { return }
        savingIDs.insert(image.id)
        // With no board chosen, a hidden feed saves straight into Hidden (never into the normal library).
        importFlow.importWeb([image], boardIDs: boards, hidden: boards.isEmpty && scope == .hidden)
    }

    /// The loaded results whose page is not among `savedPages` (not saved on this side yet),
    /// leaving out those whose own save is under way (their "+" was tapped): "Save all" neither
    /// counts them nor saves them a second time.
    private func unsaved(besides savedPages: Set<String>) -> [WebImage] {
        images.filter { (image: WebImage) -> Bool in
            !savedPages.contains(image.pageURL.absoluteString) && !savingIDs.contains(image.id)
        }
    }

    /// Saves every loaded result that isn't saved (or being saved) yet — everything scrolled
    /// through so far, not only what is on screen (Explore's ⋯ › "Save all 57 results…", after asking).
    private func saveAllVisible() {
        let wanted = unsaved(besides: savedPages)
        guard !wanted.isEmpty else {
            importFlow.flash("Everything shown is already in your library.", symbol: "info.circle")   // nothing was done
            return
        }
        for image in wanted { savingIDs.insert(image.id) }
        importFlow.importWeb(wanted, boardIDs: boardIDs, hidden: boardIDs.isEmpty && scope == .hidden)
    }
}

struct WebResultCard: View {
    @Environment(\.pinAccent) private var accent
    let image: WebImage
    var isSaved: Bool
    var isSaving: Bool
    var onSave: () -> Void

    /// The exact height of the text under the picture (the grid relies on it).
    static func footerHeight(for image: WebImage) -> CGFloat {
        CardMetrics.footerHeight(hasTitle: !(image.title ?? "").isEmpty, hasCaption: image.credit != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.textSpacing) {
            ZStack(alignment: .bottomTrailing) {
                Color(uiColor: .secondarySystemFill)
                    .aspectRatio(CardMetrics.clamped(image.aspectRatio), contentMode: .fit)
                    .overlay { RemoteImageView(url: image.thumbURL) }
                    .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))

                Button(action: onSave) {
                    ZStack {
                        Circle()
                            .fill(isSaved ? Color.green : accent)
                            .frame(width: 34, height: 34)
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: isSaved ? "checkmark" : "plus")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .shadow(radius: 3)
                    // The 34-pt circle is what you see; a 44-pt square around it is what you can tap.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSaved || isSaving)
                .padding(3)   // (the circle stays 8 pt from the picture's corner, as before)
                .accessibilityLabel(isSaved ? "Saved" : "Save to library")
            }
            if let title = image.title, !title.isEmpty {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .frame(height: CardMetrics.titleLineHeight, alignment: .leading)
            }
            if let credit = image.credit {
                Text(credit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: CardMetrics.captionLineHeight, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(image.title ?? "Web image")
    }
}

// MARK: - Searching a picture on the web

/// A web search shown in PinBoard's own private browser (see `PrivateBrowserSheet`).
struct WebSearchPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// "Search this picture on the web ▸": Google Lens, Bing, TinEye and Yandex. The menu only says
/// which one was chosen; `ReverseSearchLauncher.open` does the rest, so any menu can use both.
struct ReverseSearchMenu: View {
    /// The one label for it everywhere (Explore's menu, Quick Look's, the pins' menu).
    nonisolated static let title = "Search this picture on the web"

    let onSearch: (ReverseImageEngine) -> Void

    var body: some View {
        Menu {
            ForEach(ReverseImageEngine.allCases) { (engine: ReverseImageEngine) in
                Button {
                    onSearch(engine)
                } label: {
                    Text(engine.label)
                }
            }
        } label: {
            Label(ReverseSearchMenu.title, systemImage: "magnifyingglass")
        }
    }
}

/// Opens a reverse image search the way Settings › Explore & web search › "Open web searches in" says.
enum ReverseSearchLauncher {
    /// Opens the search for a picture that has a web address of its own. With the default browser chosen, it
    /// opens it and nil comes back; with PinBoard's browser, the page to show (put it in a
    /// `@State var page: WebSearchPage?` that has `.webSearchSheet($page, hidden:)`). A picture that
    /// only lives in the library is passed as `pictureData`: it goes on the clipboard and the
    /// site's upload page opens (the note says so).
    @MainActor
    static func open(_ engine: ReverseImageEngine, imageURL: URL?, pictureData: Data? = nil,
                     settings: AppSettings, flow: ImportFlow) -> WebSearchPage? {
        let target = WebSearchOpening.destination(engine, imageURL: imageURL, pictureData: pictureData)
        if let note = WebSearchOpening.copiedNote(target.copiedPicture) { flow.flash(note, symbol: "info.circle") }
        if settings.webSearchBrowser == .safari {
            UIApplication.shared.open(target.url)
            return nil
        }
        return WebSearchPage(url: target.url)
    }
}

extension View {
    /// Shows a web search (`WebSearchPage`) in PinBoard's private browser. `hidden`: the search
    /// belongs to a hidden pin or board, so the sheet is covered in the App Switcher too.
    func webSearchSheet(_ page: Binding<WebSearchPage?>, hidden: Bool) -> some View {
        sheet(item: page) { (shown: WebSearchPage) in
            PrivateBrowserSheet(url: shown.url)
                .hiddenPrivacyCover(hidden)
        }
    }
}

// MARK: - Explore tab

/// The words of Explore's "Save all" (plain rules; the harness tests them). `count`: the
/// loaded results not saved yet.
enum SaveAllText {
    /// The ⋯ menu item: "Save all 57 results…" (it asks before saving).
    static func menuItem(_ count: Int) -> String {
        switch count {
        case 0: return "Save all results…"
        case 1: return "Save 1 result…"
        default: return "Save all \(count) results…"
        }
    }

    /// The question it asks: "Save 57 results to your library?"
    static func question(_ count: Int) -> String {
        "Save \(results(count)) to your library?"
    }

    /// The question's button: "Save 57 results".
    static func button(_ count: Int) -> String {
        "Save \(results(count))"
    }

    private static func results(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }
}

struct ExploreView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    @State private var explorePath = NavigationPath()   // the pages open on top of the results
    @State private var query = ""
    @State private var submitted = ""
    @State private var saveAllRequest = 0
    /// How many loaded results are not saved yet (the feed says, see WebFeedView).
    @State private var unsavedCount = 0
    @State private var confirmingSaveAll = false

    var body: some View {
        NavigationStack(path: $explorePath) {
            page
                // Swiping left or right here moves to the next tab (only on this root screen:
                // a pin opened from here swipes as usual).
                .tabSwipeRoot(.explore)
                .navigationTitle("Explore")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        sourceMenu
                        moreMenu
                    }
                }
                // "Save all" asks first: after some scrolling, hundreds of results are loaded.
                .confirmationDialog(SaveAllText.question(unsavedCount), isPresented: $confirmingSaveAll,
                                    titleVisibility: .visible) {
                    Button(SaveAllText.button(unsavedCount)) { saveAllRequest += 1 }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Each one becomes a pin in Unsorted. Results you saved already are left out.")
                }
                // The × in the search field clears the results as well.
                .onChange(of: query) { _, text in
                    if text.trimmingCharacters(in: .whitespaces).isEmpty { submitted = "" }
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onChange(of: router.pendingRoute) { _, route in
            guard let route, router.selectedTab == .explore else { return }   // (see AppRouter.open)
            router.pendingRoute = nil
            explorePath.append(route)
        }
    }

    /// The web source to search (a menu with a checkmark on the chosen one).
    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $settings.webSource) {
                ForEach(WebImageSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
        } label: {
            Label(settings.webSource.label, systemImage: "globe")
                .font(.subheadline)
        }
    }

    /// ⋯: save every result loaded so far (after asking), and Settings.
    private var moreMenu: some View {
        Menu {
            Button {
                confirmingSaveAll = true
            } label: {
                Label(SaveAllText.menuItem(unsavedCount), systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(submitted.isEmpty || settings.offlineMode || unsavedCount == 0)
            Divider()
            Button {
                router.showSettings = true
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
        } label: {
            MoreMenuLabel()
        }
        .accessibilityLabel("More")
    }

    /// The search with its ideas or results — or, in Offline mode, a page saying why there is
    /// nothing to search. (The tab itself stays in the tab bar either way: tabs never come and go.)
    @ViewBuilder
    private var page: some View {
        if settings.offlineMode {
            offlinePage
        } else {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SearchBar(placeholder: "Search \(settings.webSource.label)…",
                                  text: $query,
                                  onSubmit: { submit(query) })

                        if submitted.isEmpty {
                            suggestions
                        } else {
                            WebFeedView(query: submitted,
                                        metrics: GridMetrics(columns: settings.columnCount(forWidth: geometry.size.width),
                                                             width: geometry.size.width - PinTheme.gridSpacing * 2),
                                        saveAllRequest: saveAllRequest,
                                        onUnsavedCountChange: { count in unsavedCount = count })
                        }
                    }
                    .padding(.horizontal, PinTheme.gridSpacing)
                    .padding(.bottom, 24)
                }
                .hidesBarsOnScroll()   // scrolling down tucks the bars away (ScrollingBars.swift)
            }
        }
    }

    /// Offline mode is on. No search field, no results and no thumbnails are on screen, so
    /// nothing here touches the network; one button turns Offline mode off again (the search
    /// you had comes back and loads anew).
    private var offlinePage: some View {
        ContentUnavailableView {
            Label("Explore is off in Offline mode", systemImage: "wifi.slash")
        } description: {
            Text("Nothing leaves this device while Offline mode is on, so there are no web images to search.")
        } actions: {
            Button("Turn Offline mode off") {
                settings.offlineMode = false
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())   // a sideways swipe anywhere on the page still changes tabs
    }

    @ViewBuilder
    private var suggestions: some View {
        let ideas = store.topTags(limit: 12)
        if settings.webSource.needsKey && !settings.isSourceReady(settings.webSource) {
            Label("\(settings.webSource.label) needs an API key — add it in \(SettingsCatalog.path(.imageSource)) or pick another source.",
                  systemImage: "key")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if !settings.recentSearches.isEmpty {
            HStack {
                Text("Recent searches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { settings.recentSearches = [] }
                    .font(.caption)
            }
            FlowLayout(spacing: 8) {
                ForEach(settings.recentSearches, id: \.self) { recent in
                    Button {
                        query = recent
                        submit(recent)
                    } label: {
                        Label(recent, systemImage: "clock")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        Text(ideas.isEmpty
             ? "Search for ideas — “mid-century living room”, “sourdough”, “mountain cabins” — then tap Search. Tap + on anything to keep it."
             : "Ideas from your library")
            .font(.caption)
            .foregroundStyle(.secondary)
        if !ideas.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(ideas, id: \.self) { tag in
                    Button(tag) {
                        query = tag
                        submit(tag)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        submitted = trimmed
        settings.rememberSearch(trimmed)
    }
}
