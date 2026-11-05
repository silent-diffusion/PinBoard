//
//  WebImagesUnsplash.swift  —  PinBoard
//
//  Unsplash as an image source (Settings › Explore & web search, with the person's own access
//  key), and what Unsplash's API guidelines ask of every app that uses it: each saved photo is
//  reported to its `download_location`, and the photographer and Unsplash are credited with links
//  that carry Unsplash's referral tags (`utm_source`, `utm_medium=referral`). The rest of the
//  web image service is WebImages.swift.
//

import SwiftUI
import Foundation

extension WebImageService {
    // MARK: Unsplash

    /// The `utm_source` Unsplash asks every link back to it to carry (the app's name), with
    /// `utm_medium=referral`. TODO for the owner: if the app is registered at unsplash.com/developers
    /// under another name, use that name here.
    static let unsplashAppName = "PinBoard"

    /// `url` with Unsplash's referral tags added (`utm_source`, `utm_medium`).
    static func unsplashTagged(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { (item: URLQueryItem) -> Bool in !item.name.hasPrefix("utm_") }
        items.append(URLQueryItem(name: "utm_source", value: unsplashAppName))
        items.append(URLQueryItem(name: "utm_medium", value: "referral"))
        components.queryItems = items
        return components.url ?? url
    }

    /// Unsplash asks every app to tell it when one of its photos is downloaded (saved to the
    /// library): one request to the photo's `download_location`, with the person's key. Nothing
    /// waits for it, and a failure changes nothing. Other sources: nothing to do.
    static func reportDownload(of image: WebImage) {
        guard let location = image.downloadLocation else { return }
        Task { @MainActor in
            let settings = AppSettings.shared
            let key = settings.unsplashKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, settings.webAllowed else { return }
            var request = makeRequest(location)
            request.setValue("Client-ID \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("v1", forHTTPHeaderField: "Accept-Version")
            _ = try? await session.data(for: request)
        }
    }

    struct UnsplashResponse: Decodable {
        struct Result: Decodable {
            struct URLs: Decodable {
                var regular: String?
                var small: String?
                var full: String?
            }
            struct UserLinks: Decodable { var html: String? }
            struct User: Decodable {
                var name: String?
                var username: String?
                var links: UserLinks?
            }
            struct Links: Decodable {
                var html: String?
                var download_location: String?
            }
            var id: String
            var width: Double?
            var height: Double?
            var description: String?
            var alt_description: String?
            var urls: URLs?
            var user: User?
            var links: Links?
        }
        var total_pages: Int?
        var results: [Lenient<Result>]?
    }

    static func searchUnsplash(_ query: String, page: Int, perPage: Int, key: String) async throws -> WebPage {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = url("https://api.unsplash.com/search/photos", [
            "query": query,
            "page": "\(page)",
            "per_page": "\(perPage)",
            "content_filter": "high"
        ]) else { return WebPage(images: [], hasMore: false, nextOffset: 0) }
        var request = makeRequest(url)
        request.setValue("Client-ID \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        let data = try await fetch(request, source: .unsplash, secrets: [cleanKey])
        let decoded = try JSONDecoder().decode(UnsplashResponse.self, from: data)
        var images: [WebImage] = []
        for result in (decoded.results ?? []).compactMap({ $0.value }) {
            guard let thumb = httpsURL(result.urls?.small ?? result.urls?.regular) else { continue }
            let full = httpsURL(result.urls?.regular) ?? thumb
            let title = (result.description ?? result.alt_description ?? "").trimmingCharacters(in: .whitespaces)
            // The photo's page, the photographer's and Unsplash's are linked with Unsplash's referral tags.
            let page = httpsURL(result.links?.html).map { (url: URL) -> URL in unsplashTagged(url) } ?? full
            var image = WebImage(id: "unsplash-\(result.id)",
                                 title: title.isEmpty ? nil : TitleGenerator.shorten(title, to: 60),
                                 thumbURL: thumb,
                                 fullURL: full,
                                 pageURL: page,
                                 width: result.width ?? 1,
                                 height: result.height ?? 1,
                                 credit: "Photo by \(result.user?.name ?? "unknown") on Unsplash")
            image.linkedCredit = unsplashCredit(result.user)
            image.downloadLocation = httpsURL(result.links?.download_location)
            images.append(image)
        }
        let hasMore = page < (decoded.total_pages ?? page)
        return WebPage(images: images, hasMore: hasMore, nextOffset: 0)
    }

    /// "Photo by <name> on Unsplash" with both links tagged; nil without a profile address.
    private static func unsplashCredit(_ user: UnsplashResponse.Result.User?) -> WebImageCredit? {
        let profile = httpsURL(user?.links?.html)
            ?? user?.username.flatMap { (name: String) -> URL? in URL(string: "https://unsplash.com/@" + name) }
        guard let profile, let site = URL(string: "https://unsplash.com/") else { return nil }
        return WebImageCredit(name: user?.name ?? user?.username ?? "unknown", profileURL: unsplashTagged(profile),
                              siteName: "Unsplash", siteURL: unsplashTagged(site))
    }
}
