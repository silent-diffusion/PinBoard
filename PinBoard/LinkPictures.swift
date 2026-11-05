//
//  LinkPictures.swift  —  PinBoard
//
//  The plain rules behind "a picture for every link". A link pin's picture is the one its page
//  names for itself (og:image and the like). When a page names none — or its picture can't be
//  had — there are two stand-ins, tried in this order:
//    1. one of the page's own pictures (its `<img>` tags, best first: `PageImages`);
//    2. when Settings › Links › "Find a picture for links without one" is on, the first picture
//       the web search (Explore's source) finds for the link's title.
//  This file only decides: which of the page's pictures are worth trying, in which order, when the
//  search is used and for what words (`LinkPictureChoice`). Fetching them is in LinkPins.swift
//  (`LinkPictureFinder`). Nothing here goes on the internet: the tests check it on sample pages.
//  Foundation only, on purpose (like SmartLinksParsers.swift).
//

import Foundation

// MARK: - A page's own pictures

/// The pictures a page shows (its `<img>` tags), ranked: the ones most likely to be a real
/// picture of the page's subject first, without logos, icons, tracking pixels and the like.
enum PageImages {
    /// At most this many are returned.
    nonisolated static let limit = 12

    /// A picture declared smaller than this (either side, in points) is an icon, not a picture.
    nonisolated static let smallestSide = 120

    /// A picture that declares no size ranks as if it were this big (640 × 360 points, a usual
    /// picture in a page), among the ones that do declare a size; the page's order breaks ties. The
    /// page's main picture often declares nothing, and ranking it after every declared picture let
    /// the 150 × 150 thumbnails of a sidebar win.
    nonisolated static let unsizedArea = 640 * 360

    /// Names that say "not a picture of the page's subject" wherever they stand in the picture's
    /// address, also inside a longer word ("sitelogo.png", "favicon-192.png", "/sprites/").
    nonisolated static let unwantedPieces = ["logo", "sprite", "spinner", "tracking", "emoji", "favicon"]

    /// Names that say the same, but only as a whole word or its plural ("icon", "icons/"): they
    /// also stand inside ordinary words, and "silicon-valley.jpg", "blanket.jpg", "downloading.jpg"
    /// or "badger.jpg" are fine pictures.
    nonisolated static let unwantedWords = ["icon", "avatar", "pixel", "badge", "blank", "loading", "1x1"]

    /// The same for what a picture's `class` or `id` says (shorter: lazy-loading pages put "loading"
    /// in the class of every picture they have).
    nonisolated static let unwantedClasses = ["logo", "icon", "sprite", "avatar", "badge", "emoji"]

    /// Where pictures are only decoration: the page's menus and its foot.
    nonisolated static let decorativeParents: Set<String> = ["nav", "footer"]

    /// The pictures of the page `html` (it came from `pageURL`), as https addresses, best first.
    /// Each picture's `src`, else its `data-src` (lazy pages), else the widest of its `srcset`;
    /// skipped: pictures written into the page ("data:"), SVG drawings and GIFs, ones declared
    /// smaller than 120 in either side, ones named like logos, icons, sprites, avatars, pixels,
    /// tracking, badges, emoji, spinners, "loading" and "blank" (see `isUnwanted`), the same address
    /// twice, and pictures in a menu or the page's foot. Ranked by declared width × height (a
    /// picture that says only one side counts as a square, one that says nothing counts as
    /// 640 × 360: `unsizedArea`); pictures of the same size keep the page's order.
    nonisolated static func candidates(in html: String, pageURL: URL) -> [URL] {
        candidates(in: HTMLDocument(html: html, url: pageURL))
    }

    /// The same for a page that is read already. `tried`: pictures that were fetched already (the
    /// page's own preview picture, when it couldn't be had): they are left out, so none of the few
    /// tries is spent on the same picture twice.
    nonisolated static func candidates(in document: HTMLDocument, excluding tried: [URL] = []) -> [URL] {
        var found: [(url: URL, area: Int, order: Int)] = []
        var known = Set<URL>(tried)
        for image in document.elements(named: "img") {
            guard !isDecorative(image), let size = declaredSize(of: image), size.isBigEnough,
                  let url = address(of: image, in: document), known.insert(url).inserted else { continue }
            found.append((url, size.area ?? unsizedArea, found.count))
        }
        let ranked = found.sorted { (first: (url: URL, area: Int, order: Int), second: (url: URL, area: Int, order: Int)) -> Bool in
            if first.area != second.area { return first.area > second.area }
            return first.order < second.order
        }
        return ranked.prefix(limit).map { (item: (url: URL, area: Int, order: Int)) -> URL in item.url }
    }

    /// What a picture's `width` and `height` say: whether it is big enough, and its area when it
    /// says enough to have one.
    private nonisolated static func declaredSize(of image: HTMLDocument.Node) -> (isBigEnough: Bool, area: Int?)? {
        let width = size(image.attribute("width"))
        let height = size(image.attribute("height"))
        if let width, width < smallestSide { return (false, nil) }
        if let height, height < smallestSide { return (false, nil) }
        guard let side = width ?? height else { return (true, nil) }
        return (true, (width ?? side) * (height ?? side))
    }

    /// 800 for "800" and "800px"; nil for "100%", "auto" and anything else that isn't a count of points.
    nonisolated static func size(_ raw: String?) -> Int? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        if text.hasSuffix("px") { text.removeLast(2) }
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite, number >= 0 else { return nil }
        return Int(min(number, 100_000))
    }

    /// A picture in a menu or the page's foot (the one whose own parent says so).
    private nonisolated static func isDecorative(_ image: HTMLDocument.Node) -> Bool {
        var current = image.parent
        while let node = current {
            if decorativeParents.contains(node.name) { return true }
            current = node.parent
        }
        return false
    }

    /// Where the picture's file is, as an https address, unless it is one of the unwanted kinds.
    private nonisolated static func address(of image: HTMLDocument.Node, in document: HTMLDocument) -> URL? {
        var sources: [String] = []
        for key in ["srcset", "data-srcset"] {
            if let set = image.attribute(key), let widest = ArticleExtractor.widestSource(inSet: set) { sources.append(widest) }
        }
        for key in ["data-src", "data-lazy-src", "data-original", "src"] {
            if let source = image.attribute(key) { sources.append(source) }
        }
        let classes = image.classAndID
        for source in sources where !ArticleExtractor.isPlaceholder(source) {
            guard let url = document.resolve(source), !isUnwanted(url, classes: classes) else { continue }
            return url
        }
        return nil
    }

    /// Whether a picture is a drawing (SVG), an animation (GIF), or named like something that is
    /// not a picture of the page's subject: one of `unwantedPieces` anywhere in its address, one of
    /// `unwantedWords` as a whole word (or its plural), or one of `unwantedClasses` in its class or id.
    nonisolated static func isUnwanted(_ url: URL, classes: String = "") -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".svg") || path.hasSuffix(".gif") { return true }
        if unwantedPieces.contains(where: { (name: String) -> Bool in path.contains(name) }) { return true }
        let words = Set(nameWords(in: url.path))
        for name in unwantedWords where words.contains(name) || words.contains(name + "s") { return true }
        return unwantedClasses.contains { (name: String) -> Bool in classes.contains(name) }
    }

    /// The words of a picture's address, in small letters: split at everything that isn't a letter
    /// or a digit ("/icons/play-button.png" is "icons", "play", "button", "png"), and where a capital
    /// follows a small letter ("userAvatar.png" is "user", "avatar"), so a name written together
    /// like that is still recognised as the unwanted word it holds.
    nonisolated static func nameWords(in path: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character? = nil
        for character in path {
            let isWordCharacter = character.isLetter || character.isNumber
            let startsAfterSmallLetter = character.isUppercase && (previous?.isLowercase ?? false)
            if (!isWordCharacter || startsAfterSmallLetter) && !current.isEmpty {
                words.append(current.lowercased())
                current = ""
            }
            if isWordCharacter { current.append(character) }
            previous = character
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }
}

// MARK: - Which stand-ins to try

/// What to try for a link that has no picture: the page's own pictures, then maybe a web search.
struct LinkPicturePlan: Sendable, Equatable {
    /// The page's own pictures to try, in order.
    var pageImages: [URL]
    /// The words to search the web for; nil: no search.
    var searchTitle: String?

    /// Nothing to try at all.
    var isEmpty: Bool {
        pageImages.isEmpty && searchTitle == nil
    }
}

/// The decisions about stand-in pictures.
enum LinkPictureChoice {
    /// How many of the page's own pictures are tried (each one is a download).
    nonisolated static let pageTries = 3

    /// A page's own picture must be at least this big on its short side, in pixels, to be used.
    nonisolated static let shortestSide = 120

    /// The most characters of a title the web is searched for.
    nonisolated static let searchLimit = 100

    /// What to try. `imageTags`: the page's own pictures, best first (`PageImages.candidates`).
    /// `title`: what the page (or, for a link read again, the pin) is called. `link`: the page's
    /// address, to tell a real title from the address itself. `searchesWeb`: the Settings switch is
    /// on, the web is allowed and the search source can be used (a key is there when it needs one).
    nonisolated static func plan(imageTags: [URL], title: String?, link: URL?, searchesWeb: Bool) -> LinkPicturePlan {
        let words = searchesWeb ? searchTitle(title, link: link) : nil
        return LinkPicturePlan(pageImages: Array(imageTags.prefix(pageTries)), searchTitle: words)
    }

    /// The words the web is searched for: the title with its spaces tidied and at most 100
    /// characters long. nil when there is no real title: empty, or only the address (a new link pin
    /// is called after its site until the page says better, and the site's name finds nothing).
    nonisolated static func searchTitle(_ title: String?, link: URL?) -> String? {
        let words = (title ?? "").split(whereSeparator: { (character: Character) -> Bool in character.isWhitespace })
            .joined(separator: " ")
        guard !words.isEmpty else { return nil }
        if isAddress(words, of: link) { return nil }
        return words.count > searchLimit ? String(words.prefix(searchLimit)) : words
    }

    /// Whether `text` is just a web address: the link itself, its site, or something that reads as one.
    private nonisolated static func isAddress(_ text: String, of link: URL?) -> Bool {
        let lower = text.lowercased()
        if let link {
            let host = (link.host ?? "").lowercased()
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let whole = link.absoluteString.lowercased()
            if !bare.isEmpty && (lower == host || lower == bare || lower == "www." + bare) { return true }
            if lower == whole || lower == whole.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") { return true }
        }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        return !lower.contains(" ") && lower.contains(".") && lower.contains("/")
    }

    /// What to try for a reading `link` gets, or nil when it gets no stand-in at all: only a reading
    /// that asked for one (`standInCandidates` is set: an ordinary page or an article that gave no
    /// picture), has no picture yet, and is not a video's (a video page's picture is only what the
    /// pin falls back to when its video can't be had). The words for the web search are the page's
    /// own title, else `titleHint` (what the link's pin is called already).
    nonisolated static func standInPlan(for link: ResolvedLink, titleHint: String?, searchesWeb: Bool) -> LinkPicturePlan? {
        guard link.imageData == nil, link.route != .video, let own = link.standInCandidates else { return nil }
        let words = plan(imageTags: own, title: link.title ?? titleHint, link: link.url, searchesWeb: searchesWeb)
        return words.isEmpty ? nil : words
    }

    /// How long the look for a stand-in may take, in nanoseconds: what is left of the reading's own
    /// limit (`readingLimit`, of which the reading used `readingUsed`), and never more than
    /// `standInLimit`. nil when less than a second is left: not worth starting, the link stays
    /// without a picture rather than keep the person waiting past the limit they were promised.
    nonisolated static func standInTime(readingUsed: UInt64, readingLimit: UInt64, standInLimit: UInt64) -> UInt64? {
        guard readingLimit > readingUsed else { return nil }
        let time = min(readingLimit - readingUsed, standInLimit)
        return time >= 1_000_000_000 ? time : nil
    }

    /// Whether a picture of this size (in pixels) is big enough to stand in for a page's own.
    nonisolated static func isBigEnough(width: Int, height: Int) -> Bool {
        min(width, height) >= shortestSide
    }

    /// Tries the plan: the page's own pictures one after another (`pageImage` gives a picture's
    /// data when it downloads and is big enough, else nil), and when none works the web search
    /// (`searchPicture` gives the first result's picture, else nil). The first picture found wins;
    /// nothing is tried after it, and nothing at all once the work was stopped.
    nonisolated static func run(_ plan: LinkPicturePlan,
                                pageImage: (URL) async -> Data?,
                                searchPicture: (String) async -> Data?) async -> Data? {
        for url in plan.pageImages.prefix(pageTries) {
            if Task.isCancelled { return nil }
            if let data = await pageImage(url) { return data }
        }
        guard let title = plan.searchTitle, !Task.isCancelled else { return nil }
        return await searchPicture(title)
    }
}
