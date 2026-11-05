//
//  SmartLinksReaders2.swift  —  PinBoard
//
//  More of what "Read links fully" keeps from a page (round 14; the fetching is in
//  SmartLinks.swift, the older readers in SmartLinksReaders.swift):
//    • whether a Pinterest pin is a video pin (`PinterestReader.isVideoPin`; its video is never saved);
//    • a reader for any page that has no reader of its own (`MediaPage`: whether it shows a video,
//      its main picture, its oEmbed address) and oEmbed answers (`OEmbed`);
//    • the guard against login and "are you a robot?" pages (`LoginWall`): the words and picture
//      of such a page are never saved as a pin;
//    • readers for Reddit, TikTok, Instagram and X (Twitter), each best effort.
//  Like the other reader files this one only reads text it is handed (no internet, no library),
//  so the tests check it on sample pages. Foundation only, on purpose.
//

import Foundation

// MARK: - JSON helpers

extension JSONText {
    /// Every object inside `root` that `matches` accepts, in the order the page has them: arrays in
    /// their order, an object's keys in alphabetical order (a Swift dictionary has no order of its
    /// own, so without this the first match could differ from one run to the next). Looks at no more
    /// than `limit` values, so a huge page can't keep it busy.
    nonisolated static func allObjects(in root: Any, limit: Int = 200_000,
                                       where matches: ([String: Any]) -> Bool) -> [[String: Any]] {
        var found: [[String: Any]] = []
        var stack: [Any] = [root]
        var visited = 0
        while let value = stack.popLast(), visited < limit {
            visited += 1
            if let object = value as? [String: Any] {
                if matches(object) { found.append(object) }
                for key in object.keys.sorted().reversed() {   // (reversed: the stack hands out the last one pushed first)
                    if let child = object[key], child is [String: Any] || child is [Any] { stack.append(child) }
                }
            } else if let array = value as? [Any] {
                for child in array.reversed() where child is [String: Any] || child is [Any] { stack.append(child) }
            }
        }
        return found
    }

    /// true or false, whether it was written as a JSON boolean or as the text "true"/"false".
    nonisolated static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let text = value as? String {
            switch text.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return nil
    }
}

// MARK: - Pinterest: is this a video pin?

extension PinterestReader {
    /// Whether the pin on this page is a video pin. Only that is worked out, never where its
    /// video file is: PinBoard doesn't save videos from Pinterest (App Review guideline 5.2.3), so a
    /// video pin is kept as a link pin with its picture and title. Its own data says so ("is_video",
    /// a `video_list`, `videos`), or the page's tags do (an og:type starting with "video", og:video,
    /// a VideoObject).
    nonisolated static func isVideoPin(document: HTMLDocument, object: [String: Any]?) -> Bool {
        if let object {
            if JSONText.bool(object["is_video"]) == true || JSONText.bool(object["isVideo"]) == true { return true }
            if object["videos"] is [String: Any] { return true }
            let lists = JSONText.allObjects(in: object, limit: 50_000) { (candidate: [String: Any]) -> Bool in
                candidate["video_list"] is [String: Any] || candidate["videoList"] is [String: Any]
            }
            if !lists.isEmpty { return true }
        }
        if (document.meta("og:type") ?? "").lowercased().hasPrefix("video") { return true }
        if document.meta("og:video") != nil || document.meta("og:video:secure_url") != nil { return true }
        return !MediaPage.videoObjects(in: document).isEmpty
    }
}

// MARK: - Any page: its video, its picture, its oEmbed address

/// A picture a page names, with the size it says it has (Open Graph's og:image:width / height).
struct MediaPicture: Sendable, Equatable {
    var url: URL
    var width: Int? = nil
    var height: Int? = nil

    /// The longer side, in pixels; 0 when the page doesn't say.
    var longestSide: Int { max(width ?? 0, height ?? 0) }
}

/// What a page that has no reader of its own says about the video or picture it is about: whether
/// it shows a video (og:video, twitter:player:stream, a JSON-LD VideoObject — the video itself is
/// never saved, App Review guideline 5.2.3), its pictures
/// (og:image — the largest first, a JSON-LD ImageObject), whether it says it is a photo, and the
/// address of its oEmbed description.
struct MediaPage: Sendable, Equatable {
    /// The page says it is a video (og:type "video.*", a VideoObject, or og:video tags).
    var declaresVideo = false
    /// The pictures the page names, the largest first (those of unknown size after the sized ones).
    var pictures: [MediaPicture] = []
    /// The page says it is a photo: og:type "photo", "image" or "…:photo" ("flickr_photos:photo"),
    /// or its structured data is a single ImageObject.
    var isPhoto = false
    /// `<link rel="alternate" type="application/json+oembed">`, when the page has one.
    var oEmbedURL: URL? = nil

    nonisolated init() {}

    nonisolated init(document: HTMLDocument) {
        let type = (document.meta("og:type") ?? "").lowercased()
        let objects = MediaPage.videoObjects(in: document)
        declaresVideo = type.hasPrefix("video") || !objects.isEmpty || MediaPage.hasVideoTags(document)
        pictures = MediaPage.pictures(in: document)
        isPhoto = MediaPage.isPhotoType(type) || MediaPage.isSingleImageObject(document)
        oEmbedURL = MediaPage.oEmbedLink(in: document)
    }

    /// No more than this many tags of one kind are read (a page may say "og:image" a few times, not thousands).
    static let mostTags = 50

    /// The minimum size of the longer side of a photo page's picture when the page says it (a
    /// smaller picture is an icon or a thumbnail, not what the page is about).
    static let smallestPhotoSide = 600

    /// Whether a photo page's main picture makes the page a picture pin: its longer side is at
    /// least `smallestPhotoSide` when the page says its size, and when it doesn't, the page is
    /// trusted (it is no article, or the article reader would have had it).
    nonisolated func wantsPicture() -> Bool {
        guard isPhoto, let main = pictures.first else { return false }
        if main.longestSide > 0 { return main.longestSide >= MediaPage.smallestPhotoSide }
        return true
    }

    // MARK: Reading the tags

    /// The page's JSON-LD objects whose "@type" is VideoObject.
    nonisolated static func videoObjects(in document: HTMLDocument) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for script in document.jsonLD {
            guard let json = LinkedDataArticle.parseLoosely(script) else { continue }
            result += JSONText.allObjects(in: json, limit: 20_000) { (object: [String: Any]) -> Bool in
                types(of: object).contains("VideoObject")
            }
        }
        return result
    }

    /// An object's "@type" as a list ("ImageObject", or ["Article", "Thing"]).
    nonisolated static func types(of object: [String: Any]) -> [String] {
        if let single = object["@type"] as? String { return [single] }
        if let many = object["@type"] as? [Any] {
            return many.compactMap { (value: Any) -> String? in value as? String }
        }
        return []
    }

    /// Any og:video / twitter:player tag at all (even one that isn't a file).
    nonisolated static func hasVideoTags(_ document: HTMLDocument) -> Bool {
        for key in ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"] where !document.metas(key).isEmpty {
            return true
        }
        return false
    }

    /// The pictures the page names, the largest first. og:image with the size og:image:width /
    /// og:image:height give (paired in page order), then the other tags.
    nonisolated static func pictures(in document: HTMLDocument) -> [MediaPicture] {
        let images = Array(document.metas("og:image").prefix(mostTags))
        // A size belongs to the og:image before it; with some images having a size and some not, which
        // goes with which can't be told, so then none are used.
        let widths = document.metas("og:image:width").map { (text: String) -> Int? in Int(text.trimmingCharacters(in: .whitespaces)) }
        let heights = document.metas("og:image:height").map { (text: String) -> Int? in Int(text.trimmingCharacters(in: .whitespaces)) }
        let sizesAreTold = widths.count == images.count || images.count == 1
        var result: [MediaPicture] = []
        var known = Set<URL>()
        for (index, value) in images.enumerated() {
            guard let url = document.resolve(value), known.insert(url).inserted else { continue }
            let width = sizesAreTold && index < widths.count ? widths[index] : nil
            let height = sizesAreTold && index < heights.count ? heights[index] : nil
            result.append(MediaPicture(url: url, width: width, height: height))
        }
        let others = ["og:image:secure_url", "og:image:url", "twitter:image", "twitter:image:src"]
        for key in others {
            for value in document.metas(key).prefix(mostTags) {
                guard let url = document.resolve(value), known.insert(url).inserted else { continue }
                result.append(MediaPicture(url: url))
            }
        }
        // The pictures whose size is known, the largest first; the others keep their place after them.
        let sized = result.filter { (picture: MediaPicture) -> Bool in picture.longestSide > 0 }
            .sorted { (first: MediaPicture, second: MediaPicture) -> Bool in first.longestSide > second.longestSide }
        let unsized = result.filter { (picture: MediaPicture) -> Bool in picture.longestSide == 0 }
        return sized + unsized
    }

    /// "photo", "image", "flickr_photos:photo", "500px:photo", "instapp:photo"…
    nonisolated static func isPhotoType(_ type: String) -> Bool {
        if type == "photo" || type == "image" || type == "photograph" { return true }
        return type.hasSuffix(":photo") || type.hasSuffix(":image") || type.hasSuffix(".photo")
    }

    /// The page's structured data is one picture (an ImageObject or Photograph at the top). An
    /// ImageObject inside a bigger description (a publisher's logo, a post's featured image) says
    /// nothing about what the page is, so it doesn't count.
    nonisolated static func isSingleImageObject(_ document: HTMLDocument) -> Bool {
        for script in document.jsonLD {
            guard let json = LinkedDataArticle.parseLoosely(script) else { continue }
            let top: [String: Any]? = (json as? [String: Any]) ?? (json as? [Any])?.first as? [String: Any]
            guard let top else { continue }
            let kinds = types(of: top)
            if kinds.contains("ImageObject") || kinds.contains("Photograph") { return true }
        }
        return false
    }

    /// The oEmbed description a page offers: `<link rel="alternate" type="application/json+oembed" href="…">`.
    nonisolated static func oEmbedLink(in document: HTMLDocument) -> URL? {
        for link in document.elements(named: "link") {
            let type = (link.attribute("type") ?? "").lowercased()
            guard type.contains("json+oembed") || type == "application/json+oembed" else { continue }
            if let url = document.resolve(link.attribute("href")) { return url }
        }
        return nil
    }
}

// MARK: - oEmbed

/// An oEmbed answer (https://oembed.com): what a site says about a page's content in a few
/// fields. A "photo" has the picture's address; a "video" only a player (and a thumbnail).
struct OEmbed: Sendable, Equatable {
    /// "photo", "video", "rich" or "link".
    var type = ""
    var title: String? = nil
    var authorName: String? = nil
    var authorURL: String? = nil
    var providerName: String? = nil
    /// A photo's address.
    var url: URL? = nil
    var thumbnailURL: URL? = nil
    var width: Int? = nil
    var height: Int? = nil
    /// The embed code (only a tweet's text is read from it).
    var html: String? = nil

    /// The answer in `data` (JSON); nil when it isn't one.
    nonisolated static func parse(_ data: Data) -> OEmbed? {
        guard let object = JSONText.parse(String(decoding: data, as: UTF8.self)) as? [String: Any] else { return nil }
        var embed = OEmbed()
        embed.type = (JSONText.string(object["type"]) ?? "").lowercased()
        embed.title = SmartLinkText.cleaned(JSONText.string(object["title"]))
        embed.authorName = SmartLinkText.cleaned(JSONText.string(object["author_name"]))
        embed.authorURL = JSONText.string(object["author_url"])
        embed.providerName = SmartLinkText.cleaned(JSONText.string(object["provider_name"]))
        embed.url = SmartLinkText.secureURL(JSONText.string(object["url"]))
        embed.thumbnailURL = SmartLinkText.secureURL(JSONText.string(object["thumbnail_url"]))
        embed.width = JSONText.int(object["width"])
        embed.height = JSONText.int(object["height"])
        embed.html = JSONText.string(object["html"])
        let hasSomething = embed.title != nil || embed.authorName != nil || embed.url != nil || embed.thumbnailURL != nil || embed.html != nil
        return hasSomething ? embed : nil
    }
}

extension ResolvedLink {
    /// Fills what a reading is still missing from an oEmbed answer: the title, the writer and the
    /// site's name. What the page itself said stays.
    nonisolated mutating func fillGaps(from embed: OEmbed) {
        if SmartLinkText.cleaned(title) == nil, let embedTitle = embed.title {
            title = SmartLinkText.shorten(embedTitle, to: SmartLinkText.titleLimit)
        }
        if SmartLinkText.cleaned(author) == nil { author = embed.authorName }
        if SmartLinkText.cleaned(siteName) == nil { siteName = embed.providerName }
    }
}

// MARK: - Login and "are you a robot?" pages

/// Tells a page that is only a wall — a login page, a sign-up prompt, a "just a moment" or "are you
/// a robot?" page — from the page that was asked for. Many sites (Instagram and Facebook most of
/// all) answer a link they won't show to a stranger with such a page, and its title and picture
/// must never become the pin's: the pin stays a plain link.
enum LoginWall {
    /// Words in a path that mean "sign in first" ("/accounts/login/", "/login.php", "/i/flow/login",
    /// "/authwall"). The address the answer *ended up at* counts, so a redirect to one is seen.
    static let pathWords: Set<String> = ["login", "log-in", "signin", "sign-in", "sign_in", "signup", "sign-up",
                                         "authwall", "checkpoint", "sso", "oauth", "oauth2"]
    /// The first part of a host that means a sign-in site ("accounts.google.com", "login.example.com").
    static let hostWords: Set<String> = ["login", "accounts", "auth", "sso", "signin", "consent"]
    /// Titles that are a wall whole.
    static let exactTitles: Set<String> = ["instagram", "facebook", "log in", "login", "sign in", "sign up"]
    /// Titles that start like a wall (only for pages with hardly any text, see `isWall`).
    static let titleStarts: [String] = [
        "log in", "login", "log into", "sign in", "signin", "sign up", "signup", "please log in", "please sign in",
        "just a moment", "attention required", "access denied", "verify you are human", "are you a robot",
        "robot check", "security check", "captcha", "you've been blocked", "you have been blocked", "whoa there",
        "one more step", "checking your browser", "pardon our interruption", "request blocked", "ddos protection"
    ]
    /// Phrases in a title that say it on their own.
    static let titlePhrases: [String] = ["log in or sign up", "login • instagram", "log in to facebook", "sign in to continue"]

    /// Whether `document`, which ended up at `finalURL`, is a wall and not the page asked for.
    /// `requestedURL`: the address that was asked for. An address the person asked for is what they
    /// wanted ("…/wiki/OAuth", "github.com/me/sso"): only a *redirect* to a sign-in address makes a
    /// wall of it. (nil: not known, so any sign-in address counts, as before.)
    nonisolated static func isWall(_ document: HTMLDocument, finalURL: URL, requestedURL: URL? = nil) -> Bool {
        let wasRedirected = requestedURL.map { (asked: URL) -> Bool in !SmartLinkText.samePage(asked, finalURL) } ?? true
        if wasRedirected, isSignInRedirect(document, finalURL) { return true }
        let title = SmartLinkText.cleaned(document.meta("og:title")) ?? document.title
        if let lower = title?.lowercased() {
            if exactTitles.contains(lower) { return true }
            // Words in a title say "wall" only for a page with hardly any text, or one with a password
            // field: an article may well be about logging in ("How to log in to Facebook").
            let little = hasLittleText(document)
            let looksLikeAForm = little || hasPasswordField(document)
            if looksLikeAForm, titlePhrases.contains(where: { (phrase: String) -> Bool in lower.contains(phrase) }) { return true }
            if little, lower.count <= 70, titleStarts.contains(where: { (start: String) -> Bool in startsLikeWall(lower, start) }) { return true }
        }
        return asksForPassword(document)
    }

    /// `lower` starts with `start` as a whole word ("sign in" is not "sign insurance").
    private nonisolated static func startsLikeWall(_ lower: String, _ start: String) -> Bool {
        guard lower.hasPrefix(start) else { return false }
        guard let next = lower.dropFirst(start.count).first else { return true }
        return !next.isLetter && !next.isNumber
    }

    /// A redirect that ended at a sign-in address is a wall. The one exception: a full page at an
    /// address that only has a sign-in *word* in its path and no query (a short link that leads to the
    /// article "…/wiki/OAuth"); real sign-in redirects carry a "?next=…" or are a page with next to
    /// nothing on it.
    private nonisolated static func isSignInRedirect(_ document: HTMLDocument, _ finalURL: URL) -> Bool {
        if hasSignInHost(finalURL) { return true }
        guard hasSignInPathWord(finalURL) else { return false }
        return finalURL.query != nil || hasLittleText(document) || hasPasswordField(document)
    }

    /// An address that is a sign-in page: a host such as "accounts.…" / "login.…", or a path word.
    nonisolated static func isWallAddress(_ url: URL) -> Bool {
        hasSignInHost(url) || hasSignInPathWord(url)
    }

    private nonisolated static func hasSignInHost(_ url: URL) -> Bool {
        guard let first = url.host?.lowercased().split(separator: ".").first else { return false }
        return hostWords.contains(String(first))
    }

    private nonisolated static func hasSignInPathWord(_ url: URL) -> Bool {
        for part in url.path.lowercased().split(separator: "/") {
            var word = String(part)
            if let dot = word.firstIndex(of: ".") { word = String(word[..<dot]) }   // "login.php"
            if pathWords.contains(word) { return true }
        }
        return false
    }

    /// A page with a password field and next to nothing else (and no picture of its own).
    nonisolated static func asksForPassword(_ document: HTMLDocument) -> Bool {
        hasPasswordField(document) && document.metas("og:image").isEmpty && hasLittleText(document)
    }

    private nonisolated static func hasPasswordField(_ document: HTMLDocument) -> Bool {
        document.elements(named: "input").contains { (input: HTMLDocument.Node) -> Bool in
            (input.attribute("type") ?? "").lowercased() == "password"
        }
    }

    /// Hardly any visible text (a wall says a few words; a real page says many).
    private nonisolated static func hasLittleText(_ document: HTMLDocument) -> Bool {
        document.root.text.count < 600
    }
}

// MARK: - Reddit

/// A Reddit post as its public JSON describes it (`<post address>.json`).
struct RedditPost: Sendable, Equatable {
    var id: String? = nil
    var title: String? = nil
    /// The post's own text (a text post), without Reddit's markdown marks.
    var text: String? = nil
    /// "u/name" (nil for a deleted account).
    var author: String? = nil
    /// "r/pics".
    var subreddit: String? = nil
    var createdAt: Date? = nil
    /// The post's own address on www.reddit.com.
    var permalink: URL? = nil
    /// A video post. Its video is never saved (App Review guideline 5.2.3): the pin is a link to the
    /// post with the video's first frame as its picture.
    var isVideo = false
    /// The picture of a picture post or a gallery's first picture, the best first.
    var pictureURLs: [URL] = []
    /// A preview picture Reddit made for the post (a link post's page, a video's first frame), the largest first.
    var previewURLs: [URL] = []
    /// What a link post points to (never a Reddit address).
    var linkedURL: String? = nil

    /// The pictures worth downloading for this post, in the order they are tried.
    var imageCandidates: [URL] {
        pictureURLs + previewURLs
    }
}

/// Reads a Reddit post from its public JSON. Reddit's pages themselves are a web app; the
/// ".json" of a post is open to anyone and says everything the pin needs. Best effort.
enum RedditReader {
    /// reddit.com (any sub-domain: www., old., np., m.) and its short domain redd.it (v.redd.it is the video host).
    nonisolated static func isReddit(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "reddit.com" || host.hasSuffix(".reddit.com") || host == "redd.it" || host.hasSuffix(".redd.it")
    }

    /// A post's id: "/r/pics/comments/1abcde/title/", "/comments/1abcde", "/gallery/1abcde", "redd.it/1abcde".
    nonisolated static func postID(in url: URL) -> String? {
        guard isReddit(url), let host = url.host?.lowercased() else { return nil }
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part).lowercased() }
        var candidate: String? = nil
        if host == "redd.it" || host == "www.redd.it" {
            candidate = parts.first
        } else if host.hasSuffix("reddit.com"), let index = parts.firstIndex(where: { (part: String) -> Bool in part == "comments" || part == "gallery" }),
                  index + 1 < parts.count {
            candidate = parts[index + 1]
        }
        guard let candidate, candidate.count >= 5, candidate.count <= 8,
              candidate.allSatisfy({ (character: Character) -> Bool in character.isASCII && (character.isLetter || character.isNumber) }) else { return nil }
        return candidate
    }

    /// A link that leads to one post: its own address, a share link ("/r/pics/s/AbCdEf": Reddit
    /// redirects it to the post), or a video's address on v.redd.it (the same).
    nonisolated static func isPostLink(_ url: URL) -> Bool {
        if postID(in: url) != nil { return true }
        guard let host = url.host?.lowercased() else { return false }
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        if host == "v.redd.it" { return !parts.isEmpty }
        return host.hasSuffix("reddit.com") && parts.count >= 3 && parts[parts.count - 2] == "s"
    }

    /// The post's public JSON ("raw_json=1": addresses come without "&amp;"; one comment is plenty).
    nonisolated static func jsonURL(postID: String) -> URL? {
        URL(string: "https://www.reddit.com/comments/" + postID + ".json?raw_json=1&limit=1")
    }

    /// The post in `data` (Reddit's JSON); nil when it holds none.
    nonisolated static func parse(_ data: Data) -> RedditPost? {
        guard let json = JSONText.parse(String(decoding: data, as: UTF8.self)) else { return nil }
        // The post is the first object with a title and a permalink (a comment has neither).
        let found = JSONText.firstObject(in: json, limit: 50_000) { (object: [String: Any]) -> Bool in
            object["title"] is String && object["permalink"] is String
        }
        guard let object = found else { return nil }
        var post = RedditPost()
        post.id = JSONText.string(object["id"])
        post.title = SmartLinkText.cleaned(SmartLinkText.decodeEntities(JSONText.string(object["title"]) ?? ""))
        post.text = selfText(object)
        post.author = author(object)
        post.subreddit = subreddit(object)
        post.createdAt = JSONText.double(object["created_utc"]).map { (seconds: Double) -> Date in Date(timeIntervalSince1970: seconds) }
        if let link = JSONText.string(object["permalink"]) { post.permalink = SmartLinkText.secureURL("https://www.reddit.com" + link) }
        readMedia(object, into: &post)
        if !post.isVideo, post.pictureURLs.isEmpty, let parent = (object["crosspost_parent_list"] as? [Any])?.first as? [String: Any] {
            readMedia(parent, into: &post)   // a cross-post shows what the original post shows
        }
        return post
    }

    private nonisolated static func selfText(_ object: [String: Any]) -> String? {
        guard let raw = JSONText.string(object["selftext"]), raw != "[removed]", raw != "[deleted]" else { return nil }
        let plain = plainText(SmartLinkText.decodeEntities(raw))
        return plain.isEmpty ? nil : SmartLinkText.capped(plain, to: SmartLinkText.textLimit)
    }

    private nonisolated static func author(_ object: [String: Any]) -> String? {
        guard let name = JSONText.string(object["author"]), name != "[deleted]" else { return nil }
        return "u/" + name
    }

    private nonisolated static func subreddit(_ object: [String: Any]) -> String? {
        if let prefixed = JSONText.string(object["subreddit_name_prefixed"]) { return prefixed }
        return JSONText.string(object["subreddit"]).map { (name: String) -> String in "r/" + name }
    }

    /// Whether it is a video post, its pictures (a picture post, a gallery), preview pictures and link.
    nonisolated static func readMedia(_ object: [String: Any], into post: inout RedditPost) {
        let videoPaths: [[String]] = [["secure_media", "reddit_video"], ["media", "reddit_video"], ["preview", "reddit_video_preview"]]
        for path in videoPaths where JSONText.value(object, path) is [String: Any] { post.isVideo = true }
        if JSONText.bool(object["is_video"]) == true { post.isVideo = true }
        for key in ["url_overridden_by_dest", "url"] {
            guard let url = SmartLinkText.secureURL(unescaped(JSONText.string(object[key]))) else { continue }
            if isPicture(url) {
                if !post.pictureURLs.contains(url) { post.pictureURLs.append(url) }
            } else if key == "url_overridden_by_dest", !isReddit(url), post.linkedURL == nil {
                post.linkedURL = url.absoluteString
            }
        }
        for url in galleryPictures(object) where !post.pictureURLs.contains(url) { post.pictureURLs.append(url) }
        for url in previews(object) where !post.previewURLs.contains(url) { post.previewURLs.append(url) }
    }

    /// An address that is a picture file: by its ending, or a picture host of Reddit's and Imgur's.
    nonisolated static func isPicture(_ url: URL) -> Bool {
        if LinkClassifier.mediaKind(of: url) == .imageFile { return true }
        let host = url.host?.lowercased() ?? ""
        return (host == "i.redd.it" || host == "i.imgur.com") && LinkClassifier.mediaKind(of: url) != .videoFile
    }

    private nonisolated static func unescaped(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// A gallery's first picture: its original on i.redd.it (from the id and type Reddit gives), then
    /// the preview address Reddit gives for it.
    nonisolated static func galleryPictures(_ object: [String: Any]) -> [URL] {
        guard let metadata = object["media_metadata"] as? [String: Any], !metadata.isEmpty else { return [] }
        var firstID = ((object["gallery_data"] as? [String: Any])?["items"] as? [Any])?.compactMap { (item: Any) -> String? in
            JSONText.string((item as? [String: Any])?["media_id"])
        }.first
        if firstID == nil { firstID = metadata.keys.sorted().first }
        guard let id = firstID, let entry = metadata[id] as? [String: Any] else { return [] }
        var result: [URL] = []
        let type = (JSONText.string(entry["m"]) ?? "").lowercased()
        let endings: [String: String] = ["image/jpg": "jpg", "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp"]
        if let ending = endings[type], let original = SmartLinkText.secureURL("https://i.redd.it/" + id + "." + ending) { result.append(original) }
        if let source = SmartLinkText.secureURL(unescaped(JSONText.string(JSONText.value(entry, ["s", "u"])))) { result.append(source) }
        return result
    }

    /// Reddit's own preview pictures (the largest, then the others) and the post's thumbnail.
    nonisolated static func previews(_ object: [String: Any]) -> [URL] {
        var result: [URL] = []
        if let image = ((object["preview"] as? [String: Any])?["images"] as? [Any])?.first as? [String: Any] {
            if let source = SmartLinkText.secureURL(unescaped(JSONText.string(JSONText.value(image, ["source", "url"])))) { result.append(source) }
            for resolution in (image["resolutions"] as? [Any] ?? []).reversed() {
                if let url = SmartLinkText.secureURL(unescaped(JSONText.string((resolution as? [String: Any])?["url"]))), !result.contains(url) {
                    result.append(url)
                }
            }
        }
        if let thumbnail = SmartLinkText.secureURL(JSONText.string(object["thumbnail"])), !result.contains(thumbnail) { result.append(thumbnail) }
        return result
    }

    /// A post's text without markdown: paragraphs apart by blank lines, headings as "## ", list
    /// items as "• ", quotes as "> "; bold, italics, strike-through, code marks and link addresses
    /// left out ("[the guide](https://…)" → "the guide").
    nonisolated static func plainText(_ markdown: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            current = []
        }
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "---" || line == "***" {
                flush()
                continue
            }
            if let heading = markedLine(line, marks: ["###### ", "##### ", "#### ", "### ", "## ", "# "]) {
                flush()
                paragraphs.append("## " + withoutMarks(heading))
            } else if let item = markedLine(line, marks: ["- ", "* ", "+ "]) {
                flush()
                paragraphs.append("• " + withoutMarks(item))
            } else if let quoted = markedLine(line, marks: ["> ", ">"]) {
                flush()
                paragraphs.append("> " + withoutMarks(quoted))
            } else {
                current.append(withoutMarks(line))
            }
        }
        flush()
        return paragraphs.map { (paragraph: String) -> String in SmartLinkText.collapse(paragraph) }
            .filter { (paragraph: String) -> Bool in !paragraph.isEmpty }
            .joined(separator: "\n\n")
    }

    /// `line` without the first of `marks` it starts with; nil when it starts with none.
    private nonisolated static func markedLine(_ line: String, marks: [String]) -> String? {
        for mark in marks where line.hasPrefix(mark) {
            return String(line.dropFirst(mark.count))
        }
        return nil
    }

    /// Emphasis and code marks removed, and "[text](address)" shortened to "text".
    nonisolated static func withoutMarks(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            // (Looks only a little way ahead for the closing marks: a line of "[" must not be read to its end for each one.)
            if text[index] == "[", let closeText = text[index...].prefix(1_000).firstIndex(of: "]") {
                let afterText = text.index(after: closeText)
                if afterText < text.endIndex, text[afterText] == "(", let closeAddress = text[afterText...].prefix(2_000).firstIndex(of: ")") {
                    result += text[text.index(after: index)..<closeText]
                    index = text.index(after: closeAddress)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        for mark in ["**", "__", "~~", "`", "&#x200B;", "\u{200B}"] {
            result = result.replacingOccurrences(of: mark, with: "")
        }
        return result
    }
}

// MARK: - TikTok

/// A TikTok video as its page's data describes it.
struct TikTokPost: Sendable, Equatable {
    var id: String? = nil
    /// The description the creator wrote (hashtags included).
    var text: String? = nil
    /// "@uniqueid".
    var username: String? = nil
    /// The creator's display name.
    var nickname: String? = nil
    var createdAt: Date? = nil
    var playCount: Int? = nil
    /// The cover picture (a video's first frame). The video itself is never saved (App Review
    /// guideline 5.2.3): a video becomes a link pin with this picture.
    var coverURL: URL? = nil
    /// A photo post's pictures.
    var pictureURLs: [URL] = []
}

/// Reads a TikTok page's caption, creator and cover picture (best effort: TikTok changes its pages).
enum TikTokReader {
    nonisolated static func isTikTok(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    /// TikTok's oEmbed address for a video page (its title, creator and thumbnail).
    nonisolated static func oEmbedURL(for url: URL) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.tiktok.com/oembed?url=" + encoded)
    }

    /// The video in a page's data ("__UNIVERSAL_DATA_FOR_REHYDRATION__", or the older "SIGI_STATE");
    /// nil when the page has none.
    nonisolated static func parse(html: String) -> TikTokPost? {
        let document = HTMLDocument(html: html, url: URL(string: "https://www.tiktok.com/"))
        for script in document.elements(named: "script") {
            let id = script.attribute("id") ?? ""
            guard id == "__UNIVERSAL_DATA_FOR_REHYDRATION__" || id == "SIGI_STATE",
                  let text = script.rawText, let json = JSONText.parse(text) else { continue }
            let holder = JSONText.firstObject(in: json, limit: 100_000) { (object: [String: Any]) -> Bool in
                object["itemStruct"] is [String: Any]
            }
            if let item = holder?["itemStruct"] as? [String: Any] { return post(from: item) }
            if let module = JSONText.value(json, ["ItemModule"]) as? [String: Any],
               let first = module.keys.sorted().first, let item = module[first] as? [String: Any] {
                return post(from: item)
            }
        }
        return nil
    }

    nonisolated static func post(from item: [String: Any]) -> TikTokPost {
        var post = TikTokPost()
        post.id = JSONText.string(item["id"])
        post.text = SmartLinkText.cleaned(JSONText.string(item["desc"]))
        if let author = item["author"] as? [String: Any] {
            post.username = JSONText.string(author["uniqueId"]).map { (name: String) -> String in "@" + name }
            post.nickname = SmartLinkText.cleaned(JSONText.string(author["nickname"]))
        } else if let name = JSONText.string(item["author"]) {
            post.username = "@" + name
        }
        post.createdAt = JSONText.double(item["createTime"]).map { (seconds: Double) -> Date in Date(timeIntervalSince1970: seconds) }
        post.playCount = JSONText.int(JSONText.value(item, ["stats", "playCount"]))
        if let video = item["video"] as? [String: Any] {
            post.coverURL = SmartLinkText.secureURL(JSONText.string(video["cover"])) ?? SmartLinkText.secureURL(JSONText.string(video["originCover"]))
        }
        if let images = (item["imagePost"] as? [String: Any])?["images"] as? [Any] {
            for image in images {
                let list = JSONText.value(image, ["imageURL", "urlList"]) as? [Any]
                if let url = SmartLinkText.secureURL(JSONText.string(list?.first)) { post.pictureURLs.append(url) }
            }
        }
        return post
    }
}

// MARK: - Instagram

/// An Instagram post as its page (or its embed page) describes it.
struct InstagramPost: Sendable, Equatable {
    var caption: String? = nil
    /// The creator's name as the page's title writes it ("Jane Doe").
    var author: String? = nil
    /// "@username", when the page says it.
    var username: String? = nil
    var publishedAt: Date? = nil
    var pictureURLs: [URL] = []
    /// A reel or video post. Its video is never saved (App Review guideline 5.2.3): the pin is a link
    /// to the post with the video's picture.
    var isVideo = false

    /// Whether the page gave anything of the post at all.
    var hasContent: Bool { !pictureURLs.isEmpty || isVideo || caption != nil }
}

/// Reads the public posts and reels of Instagram (best effort). Instagram shows a stranger its
/// login page for most links; then the post's embed page is tried, and if that says nothing either
/// the pin is a plain link — a login page's words and picture are never kept.
enum InstagramReader {
    /// The code of a post or reel: instagram.com/p/CODE/, /reel/CODE/, /reels/CODE/, /tv/CODE/ (also
    /// after a user name: /jane/p/CODE/); instagr.am too.
    nonisolated static func shortcode(in url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "instagram.com" || host.hasSuffix(".instagram.com") || host == "instagr.am" else { return nil }
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        guard let index = parts.firstIndex(where: { (part: String) -> Bool in ["p", "reel", "reels", "tv"].contains(part.lowercased()) }),
              index + 1 < parts.count else { return nil }
        let code = parts[index + 1]
        guard code.count >= 5, code.count <= 20, code.allSatisfy({ (character: Character) -> Bool in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }) else { return nil }
        return code
    }

    /// The post's own page.
    nonisolated static func postAddress(code: String) -> URL? {
        URL(string: "https://www.instagram.com/p/" + code + "/")
    }

    /// The post's embed page: it carries the picture and the caption of a public post.
    nonisolated static func embedAddress(code: String) -> URL? {
        URL(string: "https://www.instagram.com/p/" + code + "/embed/captioned/")
    }

    /// The post a page describes: its tags (og:image, og:video, og:title, og:description). nil when
    /// the page is a wall (login page…) or says nothing of a post.
    nonisolated static func parse(html: String, finalURL: URL, requestedURL: URL? = nil) -> InstagramPost? {
        let document = HTMLDocument(html: html, url: finalURL)
        if LoginWall.isWall(document, finalURL: finalURL, requestedURL: requestedURL) { return nil }
        var post = InstagramPost()
        for key in ["og:image", "og:image:secure_url", "twitter:image"] {
            for value in document.metas(key).prefix(MediaPage.mostTags) {
                if let url = document.resolve(value), !post.pictureURLs.contains(url) { post.pictureURLs.append(url) }
            }
        }
        for key in ["og:video:secure_url", "og:video", "og:video:url"] where document.meta(key) != nil { post.isVideo = true }
        if (document.meta("og:type") ?? "").lowercased().hasPrefix("video") { post.isVideo = true }
        let fromTitle = splitTitle(document.meta("og:title") ?? document.title ?? "")
        post.author = fromTitle.author
        post.caption = fromTitle.caption
        if let description = document.meta("og:description") {
            let fromDescription = splitDescription(description)
            post.username = fromDescription.username
            post.publishedAt = fromDescription.date
            // The description has the whole caption; the title's may be cut short.
            if let caption = fromDescription.caption, caption.count >= (post.caption?.count ?? 0) { post.caption = caption }
        }
        return post.hasContent ? post : nil
    }

    /// "Jane Doe on Instagram: “Sunset at the beach.”" → ("Jane Doe", "Sunset at the beach.").
    nonisolated static func splitTitle(_ title: String) -> (author: String?, caption: String?) {
        guard let range = title.range(of: " on Instagram:") else { return (nil, nil) }
        let author = SmartLinkText.cleaned(String(title[..<range.lowerBound]))
        let caption = SmartLinkText.cleaned(unquoted(String(title[range.upperBound...])))
        return (author, caption)
    }

    /// "1,234 likes, 56 comments - janedoe on March 5, 2024: "Sunset." " → ("@janedoe", date, "Sunset.").
    nonisolated static func splitDescription(_ description: String) -> (username: String?, date: Date?, caption: String?) {
        guard let dash = description.range(of: " - "), let on = description.range(of: " on ", range: dash.upperBound..<description.endIndex) else {
            return (nil, nil, nil)
        }
        let name = SmartLinkText.cleaned(String(description[dash.upperBound..<on.lowerBound]))
        let rest = String(description[on.upperBound...])
        guard let colon = rest.range(of: ": ") else { return (name.map { (text: String) -> String in "@" + text }, nil, nil) }
        let date = LinkClassifier.date(from: String(rest[..<colon.lowerBound]))
        let caption = SmartLinkText.cleaned(unquoted(String(rest[colon.upperBound...])))
        return (name.map { (text: String) -> String in "@" + text }, date, caption)
    }

    /// `text` without the quotation marks (straight or curly) Instagram puts around a caption, and
    /// the full stop its description puts after the closing one.
    nonisolated static func unquoted(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}", "'"]
        if result.count >= 2, result.hasSuffix("."), let beforeStop = result.dropLast().last, quotes.contains(beforeStop) {
            result.removeLast()
        }
        while let first = result.first, quotes.contains(first) { result.removeFirst() }
        while let last = result.last, quotes.contains(last) { result.removeLast() }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The post in its embed page: the picture ("EmbeddedMediaImage"), the caption ("Caption", without
    /// its user name and comment count) and whether it is a video.
    nonisolated static func parseEmbed(html: String) -> InstagramPost? {
        let document = HTMLDocument(html: html, url: URL(string: "https://www.instagram.com/"))
        var post = InstagramPost()
        for image in document.elements(named: "img") where (image.attribute("class") ?? "").contains("EmbeddedMediaImage") {
            if let url = document.resolve(image.attribute("src")), !post.pictureURLs.contains(url) { post.pictureURLs.append(url) }
        }
        for node in document.allElements {
            let className = node.attribute("class") ?? ""
            if className.contains("CaptionUsername"), post.username == nil, let name = SmartLinkText.cleaned(node.text) {
                post.username = "@" + name
            }
            if className.split(separator: " ").contains("Caption"), post.caption == nil {
                post.caption = caption(of: node)
            }
        }
        let data = document.scripts.joined(separator: "\n")
        if JSONText.stringValue(forKey: "video_url", in: data) != nil { post.isVideo = true }
        if post.pictureURLs.isEmpty, let address = JSONText.stringValue(forKey: "display_url", in: data), let url = SmartLinkText.secureURL(address) {
            post.pictureURLs.append(url)
        }
        return post.hasContent ? post : nil
    }

    /// A caption element's own words: not the user name, the comment count or the buttons in it.
    private nonisolated static func caption(of node: HTMLDocument.Node) -> String? {
        var pieces: [String] = []
        for child in node.children {
            if child.isText {
                pieces.append(child.textValue)
                continue
            }
            let className = child.attribute("class") ?? ""
            if className.contains("CaptionUsername") || className.contains("CaptionComments") || className.contains("Footer") { continue }
            pieces.append(child.name == "br" ? " " : child.text)
        }
        return SmartLinkText.cleaned(pieces.joined(separator: " "))
    }
}

// MARK: - X (Twitter)

/// A post on X as Twitter's oEmbed answer describes it (there is no open way to get its pictures).
struct Tweet: Sendable, Equatable {
    var text: String
    var authorName: String? = nil
    /// "@handle".
    var handle: String? = nil
    var publishedAt: Date? = nil
}

/// X keeps almost everything behind sign-in and has no open programming interface without keys.
/// Its oEmbed service (publish.twitter.com/oembed) does answer for public posts with the text, the
/// writer and the date, so a post becomes a link pin with its text. Nothing more is attempted.
enum TwitterReader {
    /// A post's address: twitter.com or x.com, "/<user>/status/<number>".
    nonisolated static func isPostLink(_ url: URL) -> Bool {
        postID(in: url) != nil
    }

    nonisolated static func postID(in url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let hosts: Set<String> = ["twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "mobile.x.com"]
        guard hosts.contains(host) else { return nil }
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        guard let index = parts.firstIndex(where: { (part: String) -> Bool in part == "status" || part == "statuses" }), index + 1 < parts.count,
              SmartLinkText.isDigits(parts[index + 1]) else { return nil }
        return parts[index + 1]
    }

    /// The oEmbed address for a post ("omit_script" and "dnt": no scripts, no tracking).
    nonisolated static func oEmbedURL(for url: URL) -> URL? {
        guard let id = postID(in: url) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = ("https://twitter.com/i/status/" + id).addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://publish.twitter.com/oembed?omit_script=true&dnt=true&url=" + encoded)
    }

    /// The post in an oEmbed answer: the text of its `<p>` (links to pictures left out), the writer and the date.
    nonisolated static func parse(oEmbed data: Data) -> Tweet? {
        guard let embed = OEmbed.parse(data), let html = embed.html else { return nil }
        let document = HTMLDocument(html: html, url: URL(string: "https://twitter.com/"))
        guard let paragraph = document.elements(named: "p").first else { return nil }
        let text = words(of: paragraph)
        guard !text.isEmpty else { return nil }
        var tweet = Tweet(text: text)
        tweet.authorName = embed.authorName
        if let address = embed.authorURL, let url = URL(string: address) {
            let name = url.pathComponents.last { (part: String) -> Bool in part != "/" }
            tweet.handle = name.map { (text: String) -> String in "@" + text }
        }
        if let date = document.elements(named: "a").last {
            tweet.publishedAt = LinkClassifier.date(from: date.text)
        }
        return tweet
    }

    /// A paragraph's words, with "pic.twitter.com/…" links (a picture we can't fetch) left out.
    private nonisolated static func words(of paragraph: HTMLDocument.Node) -> String {
        var pieces: [String] = []
        for child in paragraph.children {
            if child.isText {
                pieces.append(child.textValue)
            } else if child.name == "br" {
                pieces.append(" ")
            } else if child.name == "a", child.text.hasPrefix("pic.twitter.com") {
                continue
            } else {
                pieces.append(child.text)
            }
        }
        return SmartLinkText.cleaned(pieces.joined()) ?? ""
    }
}

// MARK: - From what was read to a ResolvedLink

extension ResolvedLink {
    /// A page that is a wall (a login page…): nothing of it is kept, so the pin stays a plain link
    /// with the address as its title.
    nonisolated static func blocked(url: URL) -> ResolvedLink {
        ResolvedLink(url: url, flavor: .page)
    }

    /// A Reddit post. A picture post is a picture pin whose source page is the post's own address;
    /// a video post is a link to the post with the video's first frame as its picture (its video is
    /// never saved); a text post is an article (its text is the pin's text); a link post is a link
    /// to the post with the page it points to as `linkedURL`. `given`: the address that was shared.
    nonisolated static func reddit(_ post: RedditPost, given: URL) -> ResolvedLink {
        let canonical = post.permalink ?? given
        var flavor = LinkFlavor.page
        if post.isVideo {
            flavor = .page
        } else if !post.pictureURLs.isEmpty {
            flavor = .imageFile
        } else if post.text != nil {
            flavor = .article
        }
        let isMedia = flavor == .imageFile || post.isVideo
        // A short link or a share link is saved as the post it leads to; any other link as it was given.
        let host = given.host?.lowercased() ?? ""
        let isShort = host == "redd.it" || host.hasSuffix(".redd.it") || given.path.contains("/s/")
        let address: URL = isMedia || isShort ? canonical : given
        var link = ResolvedLink(url: address, flavor: flavor)
        link.title = post.title.map { (title: String) -> String in SmartLinkText.shorten(SmartLinkText.collapse(title), to: SmartLinkText.titleLimit) }
        link.text = post.text
        link.description = post.text.flatMap { (text: String) -> String? in SmartLinkText.summary(of: text) }
        link.siteName = post.subreddit ?? "Reddit"
        link.author = post.author
        link.publishedAt = post.createdAt
        link.linkedURL = post.linkedURL
        return link
    }

    /// A TikTok post: its caption as the title and text, the creator, date and view count; nil when
    /// neither the page nor oEmbed said anything. A video is a link pin with its cover as the picture
    /// (its video is never saved); a photo post is a picture pin.
    nonisolated static func tikTok(_ post: TikTokPost?, embed: OEmbed?, url: URL) -> ResolvedLink? {
        guard post != nil || embed != nil else { return nil }
        let text = post?.text ?? embed?.title
        let flavor: LinkFlavor = post?.pictureURLs.isEmpty == false ? .imageFile : .page
        var link = ResolvedLink(url: url, flavor: flavor)
        let byline = post?.nickname ?? post?.username ?? embed?.authorName
        link.title = text.map { (caption: String) -> String in SmartLinkText.shorten(SmartLinkText.collapse(caption), to: 80) }
            ?? byline.map { (name: String) -> String in "TikTok by " + name }
        link.text = text
        link.description = text.flatMap { (caption: String) -> String? in SmartLinkText.summary(of: caption) }
        link.siteName = "TikTok"
        link.author = post?.username ?? embed?.authorName
        link.publishedAt = post?.createdAt
        link.viewCount = post?.playCount
        return link
    }

    /// The pictures worth downloading for a TikTok reading: a photo post's, the cover, oEmbed's thumbnail.
    nonisolated static func tikTokPictures(_ post: TikTokPost?, embed: OEmbed?) -> [URL] {
        var result: [URL] = post?.pictureURLs ?? []
        for url in [post?.coverURL, embed?.thumbnailURL] {
            if let url, !result.contains(url) { result.append(url) }
        }
        return result
    }

    /// An Instagram post: a picture pin, or a link pin that keeps the caption — a reel or video
    /// with its picture as the preview (its video is never saved). Its source page is the post's own address.
    nonisolated static func instagram(_ post: InstagramPost, url: URL) -> ResolvedLink {
        let flavor: LinkFlavor = !post.isVideo && !post.pictureURLs.isEmpty ? .imageFile : .page
        var link = ResolvedLink(url: url, flavor: flavor)
        let by = post.author ?? post.username
        if let caption = post.caption {
            link.title = SmartLinkText.shorten(SmartLinkText.collapse(caption), to: 80)
        } else {
            link.title = by.map { (name: String) -> String in "Instagram post by " + name }
        }
        link.text = post.caption
        link.description = post.caption.flatMap { (caption: String) -> String? in SmartLinkText.summary(of: caption) }
        link.siteName = "Instagram"
        link.author = post.author ?? post.username
        link.publishedAt = post.publishedAt
        return link
    }

    /// A post on X: an article whose text is the post ("By Jane Doe (@jane) · X · date").
    nonisolated static func tweet(_ tweet: Tweet, url: URL) -> ResolvedLink {
        var link = ResolvedLink(url: url, flavor: .article)
        link.title = SmartLinkText.shorten(SmartLinkText.collapse(tweet.text), to: 80)
        link.text = tweet.text
        link.description = SmartLinkText.summary(of: tweet.text)
        link.siteName = "X"
        var writer = tweet.authorName ?? ""
        if let handle = tweet.handle { writer += writer.isEmpty ? handle : " (" + handle + ")" }
        link.author = SmartLinkText.cleaned(writer)
        link.publishedAt = tweet.publishedAt
        return link
    }
}
