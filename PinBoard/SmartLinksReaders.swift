//
//  SmartLinksReaders.swift  —  PinBoard
//
//  What "Read links fully" keeps from each kind of page (the fetching is in SmartLinks.swift):
//  what an ordinary page says about itself (`PageSummary`); an article's text, writer and date
//  (`ArticleExtractor`); a Pinterest pin's picture, title and the page it links to
//  (`PinterestReader`); a YouTube video's details and top comments (`YouTubeReader`); and how
//  each becomes a `ResolvedLink`. Like SmartLinksParsers.swift these only read text they are
//  handed, so the tests check them on sample pages. Foundation only, on purpose.
//

import Foundation

// MARK: - An ordinary page

/// What an ordinary page says about itself in its head: its title, description, site name
/// and preview picture (the Open Graph and Twitter tags most pages carry).
struct PageSummary: Sendable, Equatable {
    var title: String? = nil
    var description: String? = nil
    var siteName: String? = nil
    var author: String? = nil
    var publishedAt: Date? = nil
    /// Preview pictures, best first (they are tried in this order).
    var imageURLs: [URL] = []
    /// The page's own address, when it gives one.
    var canonicalURL: URL? = nil
    /// What the page says it is ("article", "website", "video.other"…), in small letters.
    var kind: String? = nil

    nonisolated init() {}

    /// Reads the tags of `document`, which came from `url`.
    nonisolated init(document: HTMLDocument, url: URL) {
        title = PageSummary.title(of: document)
        let summary = document.meta("og:description") ?? document.meta("description") ?? document.meta("twitter:description")
        description = summary.map { (text: String) -> String in
            SmartLinkText.shorten(SmartLinkText.collapse(text), to: SmartLinkText.descriptionLimit)
        }
        siteName = document.meta("og:site_name") ?? document.meta("application-name")
        author = ArticleExtractor.metaAuthor(document)
        publishedAt = ArticleExtractor.metaDate(document)
        imageURLs = PageSummary.pictures(of: document)
        canonicalURL = document.canonical ?? document.resolve(document.meta("og:url"))
        kind = document.meta("og:type")?.lowercased()
    }

    /// og:title, then `<title>`, then twitter:title, then the first `<h1>` — at most 120 characters.
    nonisolated static func title(of document: HTMLDocument) -> String? {
        let firstHeading = document.elements(named: "h1").first.map { (node: HTMLDocument.Node) -> String in node.text }
        let candidates: [String?] = [document.meta("og:title"), document.title, document.meta("twitter:title"), firstHeading]
        for candidate in candidates {
            if let clean = SmartLinkText.cleaned(candidate) { return SmartLinkText.shorten(clean, to: SmartLinkText.titleLimit) }
        }
        return nil
    }

    /// The preview pictures a page names (og:image, twitter:image, `<link rel="image_src">`…),
    /// as https addresses, best first, each once.
    nonisolated static func pictures(of document: HTMLDocument) -> [URL] {
        var candidates: [String] = []
        for key in ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src", "image", "thumbnailurl"] {
            candidates.append(contentsOf: document.metas(key).prefix(50))   // (a page that names thousands names no more)
        }
        for link in document.elements(named: "link") where (link.attribute("rel") ?? "").lowercased() == "image_src" {
            if let href = link.attribute("href") { candidates.append(href) }
        }
        var result: [URL] = []
        var known = Set<URL>()
        for candidate in candidates {
            guard let url = document.resolve(candidate), known.insert(url).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

// MARK: - Articles

/// A readable article, as `ArticleExtractor` found it.
struct Article: Sendable, Equatable {
    var title: String?
    var author: String?
    var publishedAt: Date?
    var siteName: String?
    /// Its paragraphs, a blank line between them. A heading starts with "## ", a list item with
    /// "• ", a quote with "> " (ArticleReaderSheet shows each its own way).
    var text: String
    /// A short summary: the page's own description, or the start of the text.
    var excerpt: String?
    var leadImageURL: URL?
    /// The article's own address, when the page gives one.
    var canonicalURL: URL?
    var wordCount: Int
}

/// Finds the article in a page: its text (without menus, share buttons, sidebars, comments and
/// such), title, writer, date and lead picture. A page is only taken for an article when it has
/// real reading in it: at least 600 characters of text, and either says it is an article (its
/// tags or structured data), or keeps its text in an `<article>`, or has 1,500 characters or more.
enum ArticleExtractor {
    static let minimumCharacters = 600
    static let longCharacters = 1_500
    /// Class and id words of the parts of a page that are not the article (a word counts when a
    /// class or id word starts with it: "share-bar", "navbar", "sidebar-left"…).
    static let noiseWords: [String] = [
        "share", "social", "sidebar", "related", "promo", "newsletter", "cookie", "footer",
        "nav", "menu", "subscribe", "advert", "breadcrumb", "popup", "modal", "outbrain", "taboola"
    ]
    /// The same, as whole words only: "ad" is too short to match the start of other words, and
    /// "comment" would match "commentary" (a column of opinion is reading). "comment-list" and
    /// "comments-area" still count: their words are "comment" and "comments".
    static let noiseTokens: Set<String> = ["ad", "ads", "adsbygoogle"]
    /// Class names that describe the post rather than name a part of the page: WordPress lists a
    /// post's categories, tags, format, type and status as classes on it ("category-cookies",
    /// "tag-social-media", "format-standard"). Their words ("cookies", "social", "menu…") say
    /// nothing about what the element is, so they are not looked at.
    static let describingPrefixes: [String] = ["category-", "tag-", "post_tag-", "format-", "type-", "status-"]
    /// Class and id words that mark the text itself ("article-content", "post-body"): an element
    /// with one of these is never left out for its other words ("has-comments").
    static let contentWords: Set<String> = ["article", "content", "main", "story", "body", "entry", "prose"]
    /// Elements that are never part of the reading.
    static let skippedTags: Set<String> = [
        "nav", "header", "footer", "aside", "form", "button", "select", "input", "textarea", "label",
        "menu", "dialog", "figure", "figcaption", "iframe", "object", "embed", "video", "audio",
        "canvas", "picture", "img", "script", "style", "noscript", "svg", "template", "math", "map",
        "head", "title", "link", "meta"
    ]
    /// ARIA roles of the parts of a page that are not the article.
    static let skippedRoles: Set<String> = [
        "navigation", "complementary", "contentinfo", "banner", "dialog", "alertdialog", "menu",
        "menubar", "search", "toolbar", "tablist"
    ]
    /// The blocks whose text decides where the article is (see `scoredContent`).
    static let scoredBlocks: Set<String> = ["p", "pre", "blockquote", "li", "h2", "h3"]

    /// The article in `document` (which came from `url`), or nil when the page isn't one.
    nonisolated static func extract(from document: HTMLDocument, url: URL) -> Article? {
        let noise = NoiseMap(document)
        let lengths = TextLengths(document, noise: noise)
        let structured = LinkedDataArticle.first(in: document)
        let siteName = structured?.publisherName ?? document.meta("og:site_name") ?? document.meta("application-name")
            ?? SmartLinkText.bareHost(of: url)
        let title = articleTitle(document, structured: structured, siteName: siteName, url: url)
        let content = mainContent(of: document, noise: noise, lengths: lengths)
        let paragraphs = content.map { (choice: ContentChoice) -> [String] in
            ArticleExtractor.paragraphs(in: choice.roots, noise: noise, title: title)
        } ?? []
        var text = paragraphs.joined(separator: "\n\n")
        if let body = structured?.body, body.count >= minimumCharacters,
           text.count < body.count * 7 / 10 || paragraphs.count < 3 {
            // The page's own paragraphs read better (headings, lists), unless they are much shorter.
            text = ArticleExtractor.paragraphs(fromPlainText: body).joined(separator: "\n\n")
        }
        text = SmartLinkText.capped(text, to: SmartLinkText.textLimit)
        guard text.count >= minimumCharacters else { return nil }
        let pageKind = document.meta("og:type")?.lowercased() ?? ""
        let saysArticle = pageKind.contains("article") || pageKind.contains("blog") || structured != nil
            || content?.isArticleElement == true
        guard saysArticle || text.count >= longCharacters else { return nil }
        guard !Task.isCancelled else { return nil }   // given up on: what was read may be cut short
        let roots = content?.roots ?? []
        let excerpt = document.meta("og:description") ?? document.meta("description") ?? document.meta("twitter:description")
            ?? structured?.description
        return Article(title: title,
                       author: author(document, structured: structured, lengths: lengths),
                       publishedAt: publishedDate(document, structured: structured, roots: roots, lengths: lengths),
                       siteName: siteName,
                       text: text,
                       excerpt: SmartLinkText.cleaned(excerpt).map { (summary: String) -> String in
                           SmartLinkText.shorten(summary, to: SmartLinkText.descriptionLimit)
                       } ?? SmartLinkText.excerpt(of: text),
                       leadImageURL: leadImage(document, structured: structured, roots: roots),
                       canonicalURL: document.canonical ?? document.resolve(document.meta("og:url")) ?? structured?.url,
                       wordCount: SmartLinkText.wordCount(text))
    }

    // MARK: Where the article is

    /// The part of the page that holds the article; `isArticleElement` when that is an `<article>`.
    struct ContentChoice {
        var roots: [HTMLDocument.Node]
        var isArticleElement: Bool
    }

    /// The `<article>` with the most reading in it, else the `<main>` part, else the element whose
    /// paragraphs hold the most text (with its neighbours that hold a good part of it too).
    nonisolated static func mainContent(of document: HTMLDocument, noise: NoiseMap, lengths: TextLengths) -> ContentChoice? {
        if let article = mostReading(among: document.elements(named: "article"), noise: noise, lengths: lengths) {
            return ContentChoice(roots: [article], isArticleElement: true)
        }
        let roleMain = document.allElements.filter { (node: HTMLDocument.Node) -> Bool in
            node.attributes["role"]?.lowercased() == "main"
        }
        if let main = mostReading(among: document.elements(named: "main") + roleMain, noise: noise, lengths: lengths) {
            return ContentChoice(roots: [main], isArticleElement: false)
        }
        guard let scored = scoredContent(document, noise: noise, lengths: lengths) else { return nil }
        return ContentChoice(roots: scored, isArticleElement: false)
    }

    /// Among `candidates`, the one with the most reading in it (its text outside links and outside
    /// the parts that aren't the article, see `TextLengths`) — when that is at least 500 characters.
    /// A reader's comment or reply ("comment", "comment-body", "reply"…) is never a candidate: a
    /// long comment written as an `<article>` would otherwise be taken for the post itself.
    nonisolated static func mostReading(among candidates: [HTMLDocument.Node], noise: NoiseMap,
                                        lengths: TextLengths) -> HTMLDocument.Node? {
        var best: HTMLDocument.Node? = nil
        var bestLength = 0
        for candidate in candidates where !noise.contains(candidate) && !hasCommentName(candidate.classAndID) {
            let length = lengths.reading(of: candidate)
            if length > bestLength {
                best = candidate
                bestLength = length
            }
        }
        return bestLength >= 500 ? best : nil
    }

    /// Reader-style scoring: every paragraph (p, pre, blockquote, li, h2, h3, or a `<div>` of
    /// plain text) with at least 25 characters that isn't mostly links gives its length to the
    /// element it is in and half of it to the one around that. The best element wins, together
    /// with its neighbours that scored at least a quarter as much (an article split into parts).
    /// A reading that ran out of time (see `LinkResolver.timeLimit`) stops here, with nothing.
    nonisolated static func scoredContent(_ document: HTMLDocument, noise: NoiseMap,
                                          lengths: TextLengths) -> [HTMLDocument.Node]? {
        var scores: [ObjectIdentifier: Double] = [:]
        for (index, node) in document.allElements.enumerated() {
            if index % 1_000 == 999, Task.isCancelled { return nil }
            guard scoredBlocks.contains(node.name) || isTextDiv(node), !noise.contains(node) else { continue }
            let text = lengths.text(of: node)
            guard text >= 25, lengths.links(of: node) * 2 <= text else { continue }
            let value = Double(text)
            if let parent = node.parent { scores[ObjectIdentifier(parent), default: 0] += value }
            if let grandparent = node.parent?.parent { scores[ObjectIdentifier(grandparent), default: 0] += value / 2 }
        }
        var top: HTMLDocument.Node? = nil
        var topScore = 0.0
        for node in document.allElements {
            let score = scores[ObjectIdentifier(node)] ?? 0
            if score > topScore {
                top = node
                topScore = score
            }
        }
        guard let top, topScore >= 200 else { return nil }
        guard let parent = top.parent, parent.name != "#document" else { return [top] }
        return parent.elementChildren.filter { (sibling: HTMLDocument.Node) -> Bool in
            if sibling === top { return true }
            return !noise.contains(sibling) && (scores[ObjectIdentifier(sibling)] ?? 0) >= topScore / 4
        }
    }

    /// A `<div>` with no blocks inside it, only text (some sites write paragraphs this way).
    nonisolated static func isTextDiv(_ node: HTMLDocument.Node) -> Bool {
        guard node.name == "div" else { return false }
        return !node.children.contains { (child: HTMLDocument.Node) -> Bool in
            !child.isText && HTMLDocument.blockElements.contains(child.name)
        }
    }

    /// Whether an element is not part of the reading: its tag (nav, header, footer, aside,
    /// form…), its role, it is hidden, or its class or id says so ("comments", "share-bar",
    /// "sidebar"…) — unless its class or id also marks the text itself ("article-content").
    nonisolated static func isNoise(_ node: HTMLDocument.Node) -> Bool {
        let name = node.name
        if skippedTags.contains(name) { return true }
        if node.attributes["hidden"] != nil { return true }
        if node.attributes["aria-hidden"]?.lowercased() == "true" { return true }
        if let style = node.attributes["style"]?.lowercased().replacingOccurrences(of: " ", with: ""),
           style.contains("display:none") || style.contains("visibility:hidden") { return true }
        if let role = node.attributes["role"]?.lowercased(), skippedRoles.contains(role) { return true }
        if name == "html" || name == "body" || name == "article" || name == "main" { return false }
        guard node.attributes["class"] != nil || node.attributes["id"] != nil else { return false }   // (most elements: quick)
        return hasNoiseName(node.classAndID)
    }

    /// See `isNoise` (the words are compared in small letters; see `nameWords`).
    nonisolated static func hasNoiseName(_ names: String) -> Bool {
        var noisy = false
        for word in nameWords(names) {
            if contentWords.contains(word) { return false }
            if noiseTokens.contains(word) || isCommentWord(word) || noiseWords.contains(where: { (noise: String) -> Bool in word.hasPrefix(noise) }) {
                noisy = true
            }
        }
        return noisy
    }

    /// Whether a class and id name a reader's comment or reply ("comment", "comment-body",
    /// "div-comment-12", "reply"…; not "commentary").
    nonisolated static func hasCommentName(_ names: String) -> Bool {
        nameWords(names).contains { (word: String) -> Bool in isCommentWord(word) || word == "reply" || word == "replies" }
    }

    /// "comment", "comments", "commentlist", "commentscontainer"… — not "commentary" or
    /// "commentator" (a column of opinion is reading).
    nonisolated static func isCommentWord(_ word: String) -> Bool {
        word.hasPrefix("comment") && !word.hasPrefix("commentar") && !word.hasPrefix("commentat")
    }

    /// The words of a class and id ("post-body main" → "post", "body", "main"), in small letters,
    /// leaving out the class names that only describe the post (`describingPrefixes`).
    nonisolated static func nameWords(_ names: String) -> [String] {
        var words: [String] = []
        let classNames = names.lowercased().split { (character: Character) -> Bool in character.isWhitespace }
        for className in classNames {
            if describingPrefixes.contains(where: { (prefix: String) -> Bool in className.hasPrefix(prefix) }) { continue }
            let parts = className.split { (character: Character) -> Bool in !character.isLetter && !character.isNumber }
            for part in parts { words.append(String(part)) }
        }
        return words
    }

    // MARK: The text

    /// The reading inside `roots` as paragraphs (see `Article.text`). Paragraphs shorter than 20
    /// characters go (headings and list items stay), and so does anything that is mostly links.
    nonisolated static func paragraphs(in roots: [HTMLDocument.Node], noise: NoiseMap, title: String?) -> [String] {
        var writer = ParagraphWriter(title: title)
        for root in roots { writer.write(root, noise: noise) }
        writer.flush()
        return writer.paragraphs
    }

    /// A plain text (an article's text from its structured data) as paragraphs: one per line.
    /// Text written as HTML is read as HTML.
    nonisolated static func paragraphs(fromPlainText text: String) -> [String] {
        if text.contains("</p>") || text.contains("<br") {
            let document = HTMLDocument(html: text)
            return paragraphs(in: [document.root], noise: NoiseMap(document), title: nil)
        }
        let decoded = SmartLinkText.decodeEntities(text)
        return decoded.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { (line: String) -> String in SmartLinkText.collapse(line) }
            .filter { (line: String) -> Bool in !line.isEmpty }
    }

    // MARK: Title, writer, date, picture

    /// The structured data's headline, else og:title, `<title>` or the first `<h1>` — without the
    /// site's name tacked on at the end ("How to… | The Verge").
    nonisolated static func articleTitle(_ document: HTMLDocument, structured: LinkedDataArticle?,
                                         siteName: String?, url: URL) -> String? {
        let raw = SmartLinkText.cleaned(structured?.headline) ?? PageSummary.title(of: document)
        guard let raw else { return nil }
        let title = withoutSiteName(raw, siteName: siteName, host: SmartLinkText.bareHost(of: url))
        return SmartLinkText.shorten(title, to: SmartLinkText.titleLimit)
    }

    /// "How to… | The Verge" → "How to…" when the last part is the site's name (or its address).
    nonisolated static func withoutSiteName(_ title: String, siteName: String?, host: String?) -> String {
        for separator in [" | ", " - ", " — ", " – ", " · ", " :: "] {
            guard let range = title.range(of: separator, options: .backwards) else { continue }
            let head = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let tail = lettersOnly(String(title[range.upperBound...]))
            guard head.count >= 10, !tail.isEmpty else { continue }
            if let siteName, tail == lettersOnly(siteName) { return head }
            if let host, let name = mainName(ofHost: host), tail.hasPrefix(name) || name.hasPrefix(tail) { return head }
        }
        return title
    }

    /// "theverge" for "theverge.com", "bbc" for "bbc.co.uk".
    nonisolated static func mainName(ofHost host: String) -> String? {
        let labels = host.lowercased().split(separator: ".").map { (label: Substring) -> String in String(label) }
        guard labels.count >= 2 else { return nil }
        let secondLast = labels[labels.count - 2]
        if labels.count >= 3, secondLast.count <= 3 { return lettersOnly(labels[labels.count - 3]) }
        return lettersOnly(secondLast)
    }

    nonisolated static func lettersOnly(_ text: String) -> String {
        String(text.lowercased().filter { (character: Character) -> Bool in character.isLetter || character.isNumber })
    }

    /// The writer: the structured data's, the page's author tags, a link marked as the author's,
    /// an element marked as the author, or the byline ("By Jane Doe") — at most 60 characters.
    /// (Elements with far more text than a name are passed over without reading their text.)
    nonisolated static func author(_ document: HTMLDocument, structured: LinkedDataArticle?,
                                   lengths: TextLengths) -> String? {
        if let names = structured?.authors, !names.isEmpty {
            let joined = names.prefix(3).joined(separator: ", ")
            if let clean = cleanAuthor(joined, limit: 120) { return clean }
        }
        if let fromTags = metaAuthor(document) { return fromTags }
        for link in document.elements(named: "a") where (link.attribute("rel") ?? "").lowercased().contains("author") {
            guard lengths.text(of: link) <= 200 else { continue }
            if let name = cleanAuthor(link.text) { return name }
        }
        for node in document.allElements where node.attributes["itemprop"]?.lowercased() == "author" {
            guard lengths.text(of: node) <= 5_000 else { continue }   // (a short bio may be inside)
            if let name = itemName(node) { return name }
        }
        for node in document.allElements where hasBylineName(node) {
            guard lengths.text(of: node) <= 200 else { continue }
            if let name = cleanAuthor(node.text) { return name }
        }
        return nil
    }

    /// The writer named in a page's tags (author, article:author, parsely-author…).
    nonisolated static func metaAuthor(_ document: HTMLDocument) -> String? {
        for key in ["author", "article:author", "parsely-author", "sailthru.author", "dc.creator", "byl"] {
            for value in document.metas(key) {
                if let name = cleanAuthor(value) { return name }
            }
        }
        return nil
    }

    /// A microdata person's name: its `itemprop="name"` (a tag's content or its text), else its text.
    nonisolated static func itemName(_ node: HTMLDocument.Node) -> String? {
        var stack: [HTMLDocument.Node] = node.elementChildren
        while let next = stack.popLast() {
            if next.attributes["itemprop"]?.lowercased() == "name" {
                return cleanAuthor(next.attributes["content"] ?? next.text)
            }
            stack.append(contentsOf: next.elementChildren)
        }
        return cleanAuthor(node.attributes["content"] ?? node.text)
    }

    /// An element whose class says it is the byline or the author ("byline", "author-name").
    nonisolated static func hasBylineName(_ node: HTMLDocument.Node) -> Bool {
        guard !node.isText, node.name != "meta", node.name != "link", let classes = node.attributes["class"] else { return false }
        let words = classes.lowercased().split { (character: Character) -> Bool in
            !character.isLetter
        }
        return words.contains { (word: Substring) -> Bool in word == "byline" || word == "author" }
    }

    /// "By Jane Doe" → "Jane Doe"; nil for an address, a handle or anything too long for a name.
    nonisolated static func cleanAuthor(_ raw: String?, limit: Int = 60) -> String? {
        guard var name = SmartLinkText.cleaned(raw) else { return nil }
        for prefix in ["written by ", "posted by ", "by "] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        let lower = name.lowercased()
        if name.isEmpty || name.count > limit || lower.contains("http") || lower.contains("www.") || name.hasPrefix("@") { return nil }
        if LinkClassifier.date(from: name) != nil { return nil }
        return name
    }

    /// When the article was published: its structured data, the page's date tags, a `<time>`
    /// marked as the publishing date, or the first `<time datetime>` in the article.
    nonisolated static func publishedDate(_ document: HTMLDocument, structured: LinkedDataArticle?,
                                          roots: [HTMLDocument.Node], lengths: TextLengths) -> Date? {
        if let date = structured?.datePublished { return date }
        if let date = metaDate(document) { return date }
        let times = document.elements(named: "time")
        for time in times where time.attributes["itemprop"]?.lowercased() == "datepublished" || time.attributes["pubdate"] != nil {
            if let written = time.attribute("datetime"), let date = LinkClassifier.date(from: written) { return date }
            guard lengths.text(of: time) <= 64 else { continue }   // no date is written longer
            if let date = LinkClassifier.date(from: time.text) { return date }
        }
        let rootIDs = Set(roots.map { (root: HTMLDocument.Node) -> ObjectIdentifier in ObjectIdentifier(root) })
        let inside = times.filter { (time: HTMLDocument.Node) -> Bool in isInside(time, rootIDs) }
        for time in inside + times {
            if let text = time.attribute("datetime"), let date = LinkClassifier.date(from: text) { return date }
        }
        return nil
    }

    /// The publishing date in a page's tags (article:published_time, datePublished, DC.date.issued…).
    nonisolated static func metaDate(_ document: HTMLDocument) -> Date? {
        let keys = ["article:published_time", "og:article:published_time", "datepublished", "date", "dc.date.issued",
                    "dc.date", "dcterms.date", "pubdate", "publishdate", "publish-date", "sailthru.date",
                    "parsely-pub-date", "citation_publication_date", "published_time"]
        for key in keys {
            for value in document.metas(key) {
                if let date = LinkClassifier.date(from: value) { return date }
            }
        }
        return nil
    }

    /// The lead picture: the structured data's, the page's preview picture, or the first large
    /// picture in the article.
    nonisolated static func leadImage(_ document: HTMLDocument, structured: LinkedDataArticle?,
                                      roots: [HTMLDocument.Node]) -> URL? {
        if let first = structured?.imageURLs.first { return first }
        if let preview = PageSummary.pictures(of: document).first { return preview }
        let rootIDs = Set(roots.map { (root: HTMLDocument.Node) -> ObjectIdentifier in ObjectIdentifier(root) })
        for image in document.elements(named: "img") where isInside(image, rootIDs) {
            guard let url = document.resolve(pictureSource(of: image)) else { continue }
            let path = url.path.lowercased()
            if path.hasSuffix(".svg") || path.hasSuffix(".gif") { continue }
            if let width = image.attribute("width").flatMap({ (text: String) -> Int? in Int(text) }), width < 200 { continue }
            return url
        }
        return nil
    }

    /// Where a picture's file is: its `src` — unless that is missing or only a stand-in written
    /// into the page ("data:image/gif;base64,…", on pages that load their pictures as you scroll)
    /// — else its `data-src` (`data-lazy-src` on many WordPress sites), else the widest picture
    /// its `srcset` (or `data-srcset`) names.
    nonisolated static func pictureSource(of image: HTMLDocument.Node) -> String? {
        for key in ["src", "data-src", "data-lazy-src"] {
            if let source = image.attribute(key), !isPlaceholder(source) { return source }
        }
        for key in ["srcset", "data-srcset"] {
            if let set = image.attribute(key), let widest = widestSource(inSet: set) { return widest }
        }
        return nil
    }

    /// An empty picture address, or a picture written into the page itself ("data:…").
    nonisolated static func isPlaceholder(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed.hasPrefix("data:")
    }

    /// The widest picture a `srcset` names ("a.jpg 480w, b.jpg 1080w" → "b.jpg"; with "1x" and
    /// "2x", the sharper one). nil when it names none.
    nonisolated static func widestSource(inSet srcset: String) -> String? {
        var best: (source: String, size: Double)? = nil
        for candidate in srcsetCandidates(srcset) where !isPlaceholder(candidate.source) {
            if candidate.size > (best?.size ?? -1) { best = candidate }
        }
        return best?.source
    }

    /// A `srcset`'s pictures with their sizes: "a.jpg 480w" is 480, "b.jpg 2x" is 2, and an
    /// address without a size counts as 1 (one set uses one kind of size, so they compare).
    nonisolated static func srcsetCandidates(_ srcset: String) -> [(source: String, size: Double)] {
        var result: [(source: String, size: Double)] = []
        var source: String? = nil
        var size = 1.0
        for piece in srcset.split(whereSeparator: { (character: Character) -> Bool in character.isWhitespace }) {
            var token = String(piece)
            let endsCandidate = token.hasSuffix(",")   // "a.jpg 480w, b.jpg…": the comma ends one
            while token.hasSuffix(",") { token.removeLast() }
            if source == nil {
                if !token.isEmpty {
                    source = token
                    size = 1
                }
            } else if let value = descriptorSize(token) {
                size = value
            }
            if endsCandidate, let found = source {
                result.append((found, size))
                source = nil
            }
        }
        if let found = source { result.append((found, size)) }
        return result
    }

    /// 480 for "480w", 2 for "2x"; nil for anything else.
    nonisolated static func descriptorSize(_ token: String) -> Double? {
        let lower = token.lowercased()
        guard lower.hasSuffix("w") || lower.hasSuffix("x") else { return nil }
        return Double(lower.dropLast())
    }

    /// Whether `node` is inside one of the elements `roots` names (or is one).
    nonisolated static func isInside(_ node: HTMLDocument.Node, _ roots: Set<ObjectIdentifier>) -> Bool {
        guard !roots.isEmpty else { return false }
        var current: HTMLDocument.Node? = node
        while let next = current {
            if roots.contains(ObjectIdentifier(next)) { return true }
            current = next.parent
        }
        return false
    }
}

/// Which elements of a page are not part of its reading (see `ArticleExtractor.isNoise`), with
/// everything inside them. Worked out once per page.
struct NoiseMap {
    private var left: Set<ObjectIdentifier> = []

    nonisolated init(_ document: HTMLDocument) {
        var stack: [(node: HTMLDocument.Node, inherited: Bool)] = [(document.root, false)]
        while let (node, inherited) = stack.popLast() {
            let isNoise = inherited || ArticleExtractor.isNoise(node)
            if isNoise { left.insert(ObjectIdentifier(node)) }
            for child in node.children where !child.isText { stack.append((child, isNoise)) }
        }
    }

    /// Whether `node` is left out.
    nonisolated func contains(_ node: HTMLDocument.Node) -> Bool {
        left.contains(ObjectIdentifier(node))
    }
}

/// How much text every element of a page holds, worked out once per page in one pass, from the
/// innermost elements outwards. So weighing a block never reads everything inside it again: on
/// a page of blocks nested 60 deep, doing that made one reading take half a minute. For each
/// element it knows:
///   • `text(of:)`: the length of its text as `Node.text` writes it (spaces collapsed);
///   • `links(of:)`: how much of that is inside the links (`<a>`) within it;
///   • `reading(of:)`: its text outside links and outside the parts that aren't the article
///     (`NoiseMap`) — what `mostReading` compares.
struct TextLengths {
    /// A stretch of text as `Node.text` writes it: `length` characters once spaces are collapsed,
    /// and whether a space comes before and after it. Two stretches side by side are one space
    /// apart when either has a space there. Nothing but spaces: length 0, spaces on both sides.
    struct Piece: Equatable {
        var length = 0
        var spaceBefore = false
        var spaceAfter = false

        static let space = Piece(length: 0, spaceBefore: true, spaceAfter: true)

        /// This stretch followed by `next`.
        nonisolated func followed(by next: Piece) -> Piece {
            let spaced = spaceBefore || spaceAfter
            let nextSpaced = next.spaceBefore || next.spaceAfter
            if length == 0 && next.length == 0 {
                return Piece(length: 0, spaceBefore: spaced || nextSpaced, spaceAfter: spaced || nextSpaced)
            }
            if length == 0 {
                return Piece(length: next.length, spaceBefore: spaced || next.spaceBefore, spaceAfter: next.spaceAfter)
            }
            if next.length == 0 {
                return Piece(length: length, spaceBefore: spaceBefore, spaceAfter: spaceAfter || nextSpaced)
            }
            let gap = (spaceAfter || next.spaceBefore) ? 1 : 0
            return Piece(length: length + gap + next.length, spaceBefore: spaceBefore, spaceAfter: next.spaceAfter)
        }

        /// A piece of the page's text, measured the way `SmartLinkText.collapse` writes it.
        nonisolated static func of(_ text: String) -> Piece {
            var piece = Piece()
            var pendingSpace = false
            for scalar in text.unicodeScalars {
                if SmartLinkText.isInvisible(scalar) { continue }
                if SmartLinkText.isSpace(scalar) {
                    if piece.length == 0 { piece.spaceBefore = true }
                    pendingSpace = true
                    continue
                }
                if pendingSpace, piece.length > 0 { piece.length += 1 }
                pendingSpace = false
                piece.length += 1
            }
            if pendingSpace { piece.spaceAfter = true }
            return piece
        }
    }

    /// One element's measures.
    private struct Entry {
        var piece = Piece()
        var links = 0
        var reading = 0
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// Measures every element of `document` (each one after the elements inside it).
    nonisolated init(_ document: HTMLDocument, noise: NoiseMap) {
        var stack: [(node: HTMLDocument.Node, childrenDone: Bool)] = [(document.root, false)]
        while let (node, childrenDone) = stack.popLast() {
            if childrenDone {
                entries[ObjectIdentifier(node)] = measured(node, noise: noise)
                continue
            }
            stack.append((node, true))
            for child in node.children where !child.isText { stack.append((child, false)) }
        }
    }

    /// The length of `node`'s text (`node.text.count`, without reading it again).
    nonisolated func text(of node: HTMLDocument.Node) -> Int {
        entries[ObjectIdentifier(node)]?.piece.length ?? 0
    }

    /// How much of `node`'s text is inside the links within it.
    nonisolated func links(of node: HTMLDocument.Node) -> Int {
        entries[ObjectIdentifier(node)]?.links ?? 0
    }

    /// How much of `node`'s text is reading: outside links and the parts that aren't the article.
    nonisolated func reading(of node: HTMLDocument.Node) -> Int {
        entries[ObjectIdentifier(node)]?.reading ?? 0
    }

    /// One element's measures, from its children's (already measured).
    private nonisolated func measured(_ node: HTMLDocument.Node, noise: NoiseMap) -> Entry {
        var entry = Entry()
        let counts = !noise.contains(node)
        for child in node.children {
            if child.isText {
                let piece = Piece.of(child.textValue)
                entry.piece = entry.piece.followed(by: piece)
                if counts { entry.reading += piece.length }
                continue
            }
            let inner = entries[ObjectIdentifier(child)] ?? Entry()
            entry.piece = entry.piece.followed(by: TextLengths.outside(child, inner.piece))
            let isLink = child.name == "a"
            entry.links += isLink ? inner.piece.length : inner.links
            if counts, !isLink { entry.reading += inner.reading }
        }
        return entry
    }

    /// How an element's text reads from outside it: a block or a line break stands apart from
    /// the text around it; anything else runs on with it (see `Node.text`).
    private nonisolated static func outside(_ node: HTMLDocument.Node, _ piece: Piece) -> Piece {
        if node.name == "br" { return .space }
        guard HTMLDocument.blockElements.contains(node.name) else { return piece }
        return Piece.space.followed(by: piece).followed(by: .space)
    }
}

/// Writes the reading of a part of a page as paragraphs, one block after another (see
/// `ArticleExtractor.paragraphs(in:noise:title:)`).
struct ParagraphWriter {
    /// What kind of block text is written in.
    enum Kind: Equatable {
        case plain, heading(Int), listItem, preformatted
    }

    /// A block element being written, and whether it is inside a quote.
    struct Block {
        var kind: Kind
        var quoted: Bool
    }

    /// One step of walking through the page.
    private enum Step {
        case enter(HTMLDocument.Node)
        case leaveBlock
        case leaveLink
    }

    private(set) var paragraphs: [String] = []
    private var total = 0
    private var pending = ""
    private var pendingLinks = 0
    private var blocks: [Block] = [Block(kind: .plain, quoted: false)]
    private var linkDepth = 0
    private let title: String?

    nonisolated init(title: String?) {
        self.title = title.map { (text: String) -> String in text.lowercased() }
    }

    /// Writes everything inside `root` that isn't left out by `noise`. A reading that ran out of
    /// time (see `LinkResolver.timeLimit`) stops here.
    nonisolated mutating func write(_ root: HTMLDocument.Node, noise: NoiseMap) {
        var steps: [Step] = [.enter(root)]
        var walked = 0
        while let step = steps.popLast() {
            walked += 1
            if walked % 1_000 == 0, Task.isCancelled { return }
            if total > SmartLinkText.textLimit + 2_000 { return }   // enough: the text is capped anyway
            switch step {
            case .leaveBlock:
                flush()
                if blocks.count > 1 { blocks.removeLast() }
            case .leaveLink:
                linkDepth -= 1
            case .enter(let node):
                if node.isText {
                    add(node.textValue)
                    continue
                }
                if noise.contains(node) { continue }
                if node.name == "br" {
                    pending += "\n"
                    continue
                }
                if node.name == "hr" {
                    flush()
                    continue
                }
                if let block = block(for: node) {
                    flush()
                    blocks.append(block)
                    steps.append(.leaveBlock)
                }
                if node.name == "a" {
                    linkDepth += 1
                    steps.append(.leaveLink)
                }
                for child in node.children.reversed() { steps.append(.enter(child)) }
            }
        }
    }

    /// The block an element starts, if it starts one. A plain block inside a list item or a
    /// preformatted block takes that kind (a list item's paragraphs are all part of it).
    private nonisolated func block(for node: HTMLDocument.Node) -> Block? {
        let outer = blocks[blocks.count - 1]
        switch node.name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(node.name.dropFirst())) ?? 2
            return Block(kind: .heading(level), quoted: outer.quoted)
        case "li":
            return Block(kind: .listItem, quoted: outer.quoted)
        case "pre":
            return Block(kind: .preformatted, quoted: outer.quoted)
        case "blockquote":
            return Block(kind: outer.kind == .listItem ? .listItem : .plain, quoted: true)
        default:
            guard HTMLDocument.blockElements.contains(node.name) else { return nil }
            let inherited: Kind = (outer.kind == .listItem || outer.kind == .preformatted) ? outer.kind : .plain
            return Block(kind: inherited, quoted: outer.quoted)
        }
    }

    private nonisolated mutating func add(_ text: String) {
        pending += text
        if linkDepth > 0 { pendingLinks += text.count }
    }

    /// Ends the paragraph being written (keeping it when it is worth reading).
    nonisolated mutating func flush() {
        guard !pending.isEmpty else { return }
        let raw = pending
        let rawLength = raw.count
        let links = pendingLinks
        pending = ""
        pendingLinks = 0
        let block = blocks[blocks.count - 1]
        let body = tidy(raw, kind: block.kind)
        guard !body.isEmpty, links * 2 <= rawLength else { return }   // mostly links: a menu, not reading
        var paragraph: String
        switch block.kind {
        case .heading(let level):
            if level == 1, let title, body.lowercased() == title { return }   // the title again
            paragraph = level >= 2 ? "## " + body : body
        case .listItem:
            guard body.count >= 2 else { return }
            paragraph = "• " + body
        case .preformatted:
            paragraph = body
        case .plain:
            guard body.count >= 20 else { return }
            paragraph = body
        }
        if block.quoted { paragraph = "> " + paragraph }
        guard paragraphs.last != paragraph else { return }
        paragraphs.append(paragraph)
        total += paragraph.count + 2
    }

    /// A paragraph's text: spaces collapsed (line breaks from `<br>` kept); preformatted text as written.
    private nonisolated func tidy(_ raw: String, kind: Kind) -> String {
        if kind == .preformatted {
            return raw.trimmingCharacters(in: .newlines).trimmingCharacters(in: .whitespaces)
        }
        return raw.components(separatedBy: "\n")
            .map { (line: String) -> String in SmartLinkText.collapse(line) }
            .filter { (line: String) -> Bool in !line.isEmpty }
            .joined(separator: "\n")
    }
}

/// An article as a page's structured data (JSON-LD: Article, NewsArticle, BlogPosting…) describes it.
struct LinkedDataArticle {
    var headline: String? = nil
    var body: String? = nil
    var authors: [String] = []
    var datePublished: Date? = nil
    var publisherName: String? = nil
    var imageURLs: [URL] = []
    var description: String? = nil
    var url: URL? = nil

    /// The first article in the page's structured data (also inside "@graph" or "mainEntity").
    nonisolated static func first(in document: HTMLDocument) -> LinkedDataArticle? {
        for script in document.jsonLD {
            guard let json = parseLoosely(script) else { continue }
            guard let object = JSONText.firstObject(in: json, where: isArticle) else { continue }
            return LinkedDataArticle(object, root: json, base: document.baseURL)
        }
        return nil
    }

    /// An object whose "@type" is an article of some kind ("NewsArticle", ["Article", "Thing"]…).
    nonisolated static func isArticle(_ object: [String: Any]) -> Bool {
        let types: [String]
        if let single = object["@type"] as? String {
            types = [single]
        } else if let many = object["@type"] as? [Any] {
            types = many.compactMap { (value: Any) -> String? in value as? String }
        } else {
            return false
        }
        return types.contains { (type: String) -> Bool in
            type.hasSuffix("Article") || type == "BlogPosting" || type == "LiveBlogPosting" || type == "Report"
        }
    }

    /// Structured data as pages write it: sometimes wrapped in a comment, sometimes with line
    /// breaks inside its texts (which JSON doesn't allow, so those become spaces).
    nonisolated static func parseLoosely(_ text: String) -> Any? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["<!--", "//<![CDATA[", "<![CDATA["] where trimmed.hasPrefix(wrapper) {
            trimmed = String(trimmed.dropFirst(wrapper.count))
        }
        for wrapper in ["-->", "//]]>", "]]>"] where trimmed.hasSuffix(wrapper) {
            trimmed = String(trimmed.dropLast(wrapper.count))
        }
        if let json = JSONText.parse(trimmed) { return json }
        let flattened = trimmed.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        return JSONText.parse(flattened)
    }

    /// Reads one article object; `root` is the whole structured data (a writer or publisher may
    /// be named elsewhere in it by its "@id").
    nonisolated init(_ object: [String: Any], root: Any, base: URL?) {
        headline = JSONText.string(object["headline"]) ?? JSONText.string(object["name"])
        body = JSONText.string(object["articleBody"])
        description = JSONText.string(object["description"]).map { (text: String) -> String in SmartLinkText.decodeEntities(text) }
        datePublished = JSONText.string(object["datePublished"]).flatMap { (text: String) -> Date? in LinkClassifier.date(from: text) }
            ?? JSONText.string(object["dateCreated"]).flatMap { (text: String) -> Date? in LinkClassifier.date(from: text) }
        authors = LinkedDataArticle.names(object["author"], root: root)
        publisherName = LinkedDataArticle.names(object["publisher"], root: root).first
        imageURLs = LinkedDataArticle.images(object["image"], base: base)
        url = SmartLinkText.secureURL(JSONText.string(object["url"]), relativeTo: base)
        if let headline { self.headline = SmartLinkText.decodeEntities(headline) }
    }

    /// The names in a writer or publisher value: a text, an object with a "name", a list of
    /// those, or an "@id" naming an object elsewhere.
    nonisolated static func names(_ value: Any?, root: Any) -> [String] {
        if let text = JSONText.string(value) { return [SmartLinkText.decodeEntities(text)] }
        if let list = value as? [Any] {
            return list.flatMap { (item: Any) -> [String] in names(item, root: root) }
        }
        guard let object = value as? [String: Any] else { return [] }
        if let name = JSONText.string(object["name"]) { return [SmartLinkText.decodeEntities(name)] }
        if let id = JSONText.string(object["@id"]),
           let named = JSONText.firstObject(in: root, where: { (other: [String: Any]) -> Bool in
               JSONText.string(other["@id"]) == id && other["name"] != nil
           }),
           let name = JSONText.string(named["name"]) {
            return [SmartLinkText.decodeEntities(name)]
        }
        return []
    }

    /// The picture addresses in an "image" value: a text, an object with a "url", or a list of those.
    nonisolated static func images(_ value: Any?, base: URL?) -> [URL] {
        if let text = JSONText.string(value) {
            return SmartLinkText.secureURL(text, relativeTo: base).map { (url: URL) -> [URL] in [url] } ?? []
        }
        if let list = value as? [Any] {
            return list.flatMap { (item: Any) -> [URL] in images(item, base: base) }
        }
        if let object = value as? [String: Any] {
            return images(object["url"] ?? object["contentUrl"], base: base)
        }
        return []
    }
}

// MARK: - Pinterest

/// A Pinterest pin, as its page describes it.
struct PinterestPin: Sendable, Equatable {
    var pinID: String? = nil
    var title: String? = nil
    var description: String? = nil
    /// The pin's picture, largest first (tried in this order).
    var imageURLs: [URL] = []
    /// The page (or the pin's own data) says this is a video pin. Its video is never saved: a video
    /// pin becomes a link pin with its picture and title (`ResolvedLink.pinterest`).
    var isVideo = false
    /// The page the pin links to (its destination) — never a Pinterest address.
    var destination: String? = nil
    /// Who made or saved the pin.
    var creator: String? = nil
    var createdAt: Date? = nil
}

/// Reads a Pinterest pin's page: its picture (the largest there is), whether it is a video, its title,
/// description, the page it links to and who made it. Pinterest keeps these in JSON inside the
/// page (the pin's own object is found by its number); the page's og: tags fill in the rest.
/// Everything is best effort: whatever the page doesn't say stays nil.
enum PinterestReader {
    /// The pages are asked for as Safari on an iPad asks for them (Pinterest shows other visitors a
    /// page without the pin's data). The same words as the private browser's
    /// (`PrivateBrowserRules.userAgent`, WebBrowser.swift): they are kept in that one place.
    static let userAgent = PrivateBrowserRules.userAgent
    /// The size folders of Pinterest's picture addresses ("/736x/…"); "/originals/" is the largest.
    static let sizeFolders: Set<String> = ["60x60", "75x75", "136x136", "170x", "236x", "474x", "564x", "736x", "1200x"]

    /// The pin on a pin page. `pinID`: the pin's number (from its address), to find its data.
    /// Whether it is a video pin is worked out too (`isVideoPin`, SmartLinksReaders2.swift), but
    /// never where its video file is: a video pin is kept as a link with its picture.
    nonisolated static func parse(html: String, pinID: String? = nil) -> PinterestPin {
        let document = HTMLDocument(html: html, url: URL(string: "https://www.pinterest.com/"))
        var pin = PinterestPin(pinID: pinID)
        var own: [URL] = []
        let object = pinObject(in: document, pinID: pinID)
        if let object {
            read(object, into: &pin)
            own = pictureCandidates(in: object)
        }
        readTags(document, into: &pin)
        let preview = PageSummary.pictures(of: document)
        let scriptText = document.scripts.joined(separator: "\n")
        if own.isEmpty {
            // Only what is written anywhere in the page's scripts: that may be other pins' (the
            // related pins under this one), so the page's own preview picture comes first.
            pin.imageURLs = ordered(rawOriginals(in: scriptText), preview: preview)
        } else {
            pin.imageURLs = ordered(own: own, preview: preview)
        }
        pin.isVideo = isVideoPin(document: document, object: object)
        return pin
    }

    /// The pin's own object in the page's JSON: the one with its number and a picture or video.
    /// Without a number, the first object that looks like a pin.
    nonisolated static func pinObject(in document: HTMLDocument, pinID: String?) -> [String: Any]? {
        for script in document.elements(named: "script") {
            guard let text = script.rawText, text.count > 20, text.count < 8_000_000 else { continue }
            let type = (script.attribute("type") ?? "").lowercased()
            let id = script.attribute("id") ?? ""
            guard type.contains("json") || id.hasPrefix("__PWS") else { continue }
            guard let json = JSONText.parse(text) else { continue }
            let found = JSONText.firstObject(in: json) { (object: [String: Any]) -> Bool in
                isPinObject(object, pinID: pinID)
            }
            if let found { return found }
        }
        return nil
    }

    nonisolated static func isPinObject(_ object: [String: Any], pinID: String?) -> Bool {
        let hasMedia = object["images"] is [String: Any] || object["imageSpec_orig"] != nil || object["videos"] != nil
            || object["story_pin_data"] != nil || object["storyPinData"] != nil || object["imageLargeUrl"] != nil
        guard hasMedia else { return false }
        guard let pinID else { return object["id"] != nil || object["entityId"] != nil }
        return idText(object["id"]) == pinID || idText(object["entityId"]) == pinID
    }

    /// An id written as text or as a number.
    nonisolated static func idText(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? Int { return String(number) }
        return nil
    }

    /// Title, description, destination, creator and date from the pin's object (both of the
    /// ways Pinterest has written its pages).
    nonisolated static func read(_ object: [String: Any], into pin: inout PinterestPin) {
        pin.title = cleanTitle(JSONText.string(object["title"]) ?? JSONText.string(object["grid_title"])
                               ?? JSONText.string(object["gridTitle"]))
        let descriptions: [Any?] = [object["description"], object["closeup_unified_description"],
                                    object["closeupUnifiedDescription"], object["closeup_description"]]
        pin.description = descriptions.lazy.compactMap { (value: Any?) -> String? in cleanDescription(JSONText.string(value)) }.first
        let links: [Any?] = [object["link"], object["tracked_link"], object["trackedLink"]]
        pin.destination = links.lazy.compactMap { (value: Any?) -> String? in destination(JSONText.string(value)) }.first
        let creators: [[String]] = [["pinner", "full_name"], ["pinner", "fullName"], ["native_creator", "full_name"],
                                    ["nativeCreator", "fullName"], ["pinner", "username"]]
        pin.creator = creators.lazy.compactMap { (path: [String]) -> String? in JSONText.string(JSONText.value(object, path)) }.first
        let created = JSONText.string(object["created_at"]) ?? JSONText.string(object["createdAt"])
        pin.createdAt = created.flatMap { (text: String) -> Date? in LinkClassifier.date(from: text) }
    }

    /// The pin's picture addresses in its object, the original first.
    nonisolated static func pictureCandidates(in object: [String: Any]) -> [URL] {
        let paths: [[String]] = [["images", "orig", "url"], ["imageSpec_orig", "url"], ["images", "originals", "url"],
                                 ["imageLargeUrl"], ["images", "736x", "url"], ["imageSpec_736x", "url"],
                                 ["images", "474x", "url"], ["imageSpec_474x", "url"]]
        var result: [URL] = []
        for path in paths {
            guard let url = SmartLinkText.secureURL(JSONText.string(JSONText.value(object, path))), !result.contains(url) else { continue }
            result.append(url)
        }
        return result
    }

    /// Original picture addresses written anywhere in the page's scripts ("orig":{…"url":"…"}),
    /// for pages whose JSON can't be read whole.
    nonisolated static func rawOriginals(in text: String) -> [URL] {
        var result: [URL] = []
        var searchStart = text.startIndex
        var looked = 0
        while looked < 20, let found = text.range(of: "\"orig\":", range: searchStart..<text.endIndex) {
            looked += 1
            searchStart = found.upperBound
            guard let objectText = JSONText.object(after: "\"orig\":", in: String(text[found.lowerBound...].prefix(2_000))),
                  let object = JSONText.parse(objectText) as? [String: Any],
                  let url = SmartLinkText.secureURL(JSONText.string(object["url"])), !result.contains(url) else { continue }
            result.append(url)
        }
        return result
    }

    /// Fills in from the page's tags what the JSON didn't give (whether it is a video is decided apart, see `isVideoPin`).
    nonisolated static func readTags(_ document: HTMLDocument, into pin: inout PinterestPin) {
        if pin.title == nil { pin.title = cleanTitle(document.meta("og:title") ?? document.title) }
        if pin.description == nil {
            pin.description = cleanDescription(document.meta("og:description") ?? document.meta("description"))
        }
        if pin.destination == nil {
            pin.destination = destination(document.meta("pinterestapp:source")) ?? destination(document.meta("og:see_also"))
        }
        if pin.creator == nil, let pinner = SmartLinkText.secureURL(document.meta("pinterestapp:pinner")) {
            pin.creator = pinner.pathComponents.last { (part: String) -> Bool in part != "/" }
        }
    }

    /// The pictures in the order they are tried when only originals written anywhere in the
    /// page's scripts were found — which may be other pins' (the related pins on the same page):
    ///   1. the originals that belong to the page's preview picture;
    ///   2. the preview picture's original ("/736x/" → "/originals/");
    ///   3. the preview picture itself: the pin's own picture comes before anything unsure;
    ///   4. the other originals, only when the page names no preview picture at all.
    nonisolated static func ordered(_ found: [URL], preview: [URL]) -> [URL] {
        let keys = Set(preview.compactMap { (url: URL) -> String? in pictureKey(url) })
        var result: [URL] = []
        func add(_ url: URL?) {
            guard let url, !result.contains(url) else { return }
            result.append(url)
        }
        for url in found where keys.contains(pictureKey(url) ?? "") { add(url) }
        for url in preview { add(originalAddress(of: url)) }
        for url in preview { add(url) }
        if preview.isEmpty {
            for url in found { add(url) }
        }
        return result
    }

    /// The pictures in the order they are tried when the pin's own data names them: those
    /// (largest first), then the preview picture's original and the preview picture itself.
    nonisolated static func ordered(own: [URL], preview: [URL]) -> [URL] {
        var result: [URL] = []
        for url in own + ordered([], preview: preview) where !result.contains(url) {
            result.append(url)
        }
        return result
    }

    /// "ab/cd/ef/abcdef0123" for "https://i.pinimg.com/736x/ab/cd/ef/abcdef0123.jpg" (the same for
    /// every size of that picture).
    nonisolated static func pictureKey(_ url: URL) -> String? {
        var parts = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        guard parts.count >= 2, sizeFolders.contains(parts[0]) || parts[0] == "originals" else { return nil }
        parts.removeFirst()
        let joined = parts.joined(separator: "/")
        guard let dot = joined.lastIndex(of: ".") else { return joined }
        return String(joined[..<dot])
    }

    /// The same picture in its original size ("/736x/…" → "/originals/…"); nil when it isn't a
    /// Pinterest picture address with a size folder.
    nonisolated static func originalAddress(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parts = components.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        guard parts.count >= 2, sizeFolders.contains(parts[0]) else { return nil }
        parts[0] = "originals"
        components.path = "/" + parts.joined(separator: "/")
        return components.url
    }

    /// A pin's title without " | Pinterest"; nil for Pinterest's stand-in titles ("Pin on Recipes").
    nonisolated static func cleanTitle(_ raw: String?) -> String? {
        guard var title = SmartLinkText.cleaned(raw) else { return nil }
        for suffix in [" | Pinterest", " - Pinterest", " – Pinterest", "| Pinterest"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        let lower = title.lowercased()
        if title.isEmpty || lower == "pinterest" || lower.hasPrefix("pin on ") || lower.hasPrefix("pin by ") || lower.hasPrefix("pin page") {
            return nil
        }
        return SmartLinkText.shorten(title, to: SmartLinkText.titleLimit)
    }

    /// A pin's description without Pinterest's own lines ("This Pin was discovered by…",
    /// "Discover (and save!) your own Pins on Pinterest.") and the date some pages put in front.
    nonisolated static func cleanDescription(_ raw: String?) -> String? {
        guard var text = SmartLinkText.cleaned(raw) else { return nil }
        for marker in ["This Pin was discovered by", "Discover (and save!) your own Pins on Pinterest"] {
            if let range = text.range(of: marker) { text = String(text[..<range.lowerBound]) }
        }
        if let dash = text.range(of: " - "), text.distance(from: text.startIndex, to: dash.lowerBound) <= 12,
           LinkClassifier.date(from: String(text[..<dash.lowerBound])) != nil {
            text = String(text[dash.upperBound...])
        }
        return SmartLinkText.cleaned(text)
    }

    /// A pin's destination: an http(s) address that isn't Pinterest's own.
    nonisolated static func destination(_ raw: String?) -> String? {
        guard let url = SmartLinkText.secureURL(raw), let host = url.host?.lowercased() else { return nil }
        if LinkClassifier.isPinterest(url) || host == "pinimg.com" || host.hasSuffix(".pinimg.com") { return nil }
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - YouTube

/// A YouTube video's details, as YouTube's oEmbed answer or its Data API give them.
struct YouTubeVideo: Sendable, Equatable {
    var id: String = ""
    var title: String? = nil
    var channel: String? = nil
    /// The channel's page.
    var channelURL: String? = nil
    var publishedAt: Date? = nil
    /// Its length in seconds.
    var duration: Double? = nil
    var viewCount: Int? = nil
    /// The full description, line breaks kept.
    var description: String? = nil
    /// Thumbnail pictures, largest first.
    var thumbnailURLs: [URL] = []
    var comments: [PinComment] = []

    /// Takes from `other` whatever this doesn't know yet (what is known stays).
    nonisolated mutating func fillGaps(from other: YouTubeVideo) {
        if id.isEmpty { id = other.id }
        if title == nil { title = other.title }
        if channel == nil { channel = other.channel }
        if channelURL == nil { channelURL = other.channelURL }
        if publishedAt == nil { publishedAt = other.publishedAt }
        if duration == nil { duration = other.duration }
        if viewCount == nil { viewCount = other.viewCount }
        if description == nil { description = other.description }
        for url in other.thumbnailURLs where !thumbnailURLs.contains(url) { thumbnailURLs.append(url) }
        if comments.isEmpty { comments = other.comments }
    }
}

/// Reads a YouTube video's details only through YouTube's services for apps, as its terms ask:
/// its oEmbed answer (title, channel, thumbnail; no key needed), and the YouTube Data API with the
/// person's own key (which also gives the length, description and top comments). The watch page
/// itself is never read. Nothing of the video itself is ever downloaded: the pin plays it in YouTube's own
/// embedded player.
enum YouTubeReader {
    /// How many top comments are kept.
    static let commentLimit = 5

    nonisolated static func watchURL(id: String) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=" + id)
    }

    /// YouTube's own player for the video, in its privacy-enhanced form (no cookies until you play).
    nonisolated static func embedURL(id: String) -> URL? {
        guard LinkClassifier.isVideoID(id) else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/" + id + "?playsinline=1")
    }

    nonisolated static func oEmbedURL(id: String) -> URL? {
        guard let watch = watchURL(id: id) else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: watch.absoluteString), URLQueryItem(name: "format", value: "json")]
        return components?.url
    }

    /// The Data API's details of one video (title, channel, date, description, length, views).
    nonisolated static func apiVideoURL(id: String, key: String) -> URL? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")
        components?.queryItems = [URLQueryItem(name: "part", value: "snippet,contentDetails,statistics"),
                                  URLQueryItem(name: "id", value: id), URLQueryItem(name: "key", value: key)]
        return components?.url
    }

    /// The Data API's top comments of one video (most relevant first).
    nonisolated static func apiCommentsURL(id: String, key: String) -> URL? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/commentThreads")
        components?.queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "videoId", value: id),
                                  URLQueryItem(name: "order", value: "relevance"),
                                  URLQueryItem(name: "maxResults", value: String(commentLimit)),
                                  URLQueryItem(name: "textFormat", value: "plainText"), URLQueryItem(name: "key", value: key)]
        return components?.url
    }

    /// The thumbnails every video has: the full-size one (not every video has it), then the large one.
    nonisolated static func thumbnailURLs(id: String) -> [URL] {
        ["maxresdefault", "hqdefault"].compactMap { (name: String) -> URL? in
            URL(string: "https://i.ytimg.com/vi/" + id + "/" + name + ".jpg")
        }
    }

    /// YouTube's oEmbed answer: title, channel, channel page and a thumbnail.
    nonisolated static func parseOEmbed(_ data: Data) -> YouTubeVideo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else { return nil }
        var video = YouTubeVideo()
        video.title = JSONText.string(json["title"])
        video.channel = JSONText.string(json["author_name"])
        video.channelURL = SmartLinkText.secureURL(JSONText.string(json["author_url"]))?.absoluteString
        if let thumbnail = SmartLinkText.secureURL(JSONText.string(json["thumbnail_url"])) { video.thumbnailURLs = [thumbnail] }
        guard video.title != nil || video.channel != nil else { return nil }
        return video
    }

    /// The Data API's answer about one video (nil when it names none: a wrong id, a key error).
    nonisolated static func parseAPIVideo(_ data: Data) -> YouTubeVideo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let items = json["items"] as? [Any], let item = items.first as? [String: Any] else { return nil }
        var video = YouTubeVideo()
        video.id = JSONText.string(item["id"]) ?? ""
        let snippet = item["snippet"] as? [String: Any] ?? [:]
        video.title = JSONText.string(snippet["title"])
        video.channel = JSONText.string(snippet["channelTitle"])
        if let channelID = JSONText.string(snippet["channelId"]) { video.channelURL = "https://www.youtube.com/channel/" + channelID }
        video.publishedAt = JSONText.string(snippet["publishedAt"]).flatMap(LinkClassifier.date(from:))
        if let text = snippet["description"] as? String, SmartLinkText.cleaned(text) != nil { video.description = text }
        video.duration = JSONText.string(JSONText.value(item, ["contentDetails", "duration"])).flatMap(LinkClassifier.isoDuration)
        video.viewCount = JSONText.int(JSONText.value(item, ["statistics", "viewCount"]))
        let sizes = ["maxres", "standard", "high", "medium"]
        video.thumbnailURLs = sizes.compactMap { (size: String) -> URL? in
            SmartLinkText.secureURL(JSONText.string(JSONText.value(snippet, ["thumbnails", size, "url"])))
        }
        return video
    }

    /// The Data API's comment threads: each top comment's writer, text, likes and date (at most
    /// five). Anything unexpected — comments turned off, a key error — gives none.
    nonisolated static func parseAPIComments(_ data: Data) -> [PinComment] {
        guard let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let items = json["items"] as? [Any] else { return [] }
        var comments: [PinComment] = []
        for item in items {
            guard let snippet = JSONText.value(item, ["snippet", "topLevelComment", "snippet"]) as? [String: Any],
                  let author = JSONText.string(snippet["authorDisplayName"]),
                  let text = JSONText.string(snippet["textDisplay"]) ?? JSONText.string(snippet["textOriginal"]) else { continue }
            let date = JSONText.string(snippet["publishedAt"]).flatMap(LinkClassifier.date(from:))
            let kept = SmartLinkText.shorten(text, to: 2_000)
            comments.append(PinComment(author: author, text: kept, likes: JSONText.int(snippet["likeCount"]) ?? 0, date: date))
            if comments.count == commentLimit { break }
        }
        return comments
    }

    /// The little page the pin page's player shows: YouTube's own embedded player, filling it, and
    /// starting at once (the person has just tapped "Play"). nil for something that isn't a video id.
    nonisolated static func playerPage(videoID: String, allowsFullScreen: Bool = true) -> String? {
        guard let embed = embedURL(id: videoID)?.absoluteString else { return nil }
        // ("&" written the HTML way, inside an attribute; "fs=0": YouTube shows no full-screen button)
        let source = embed + "&amp;autoplay=1" + (allowsFullScreen ? "" : "&amp;fs=0")
        let allowed = allowsFullScreen ? "autoplay; encrypted-media; picture-in-picture; fullscreen\" allowfullscreen " : "autoplay; encrypted-media\" "
        let head = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<meta name=\"referrer\" content=\"strict-origin-when-cross-origin\">"
            + "<style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}"
            + "iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>"
        let frame = "<iframe src=\"" + source + "\" title=\"YouTube video player\" "
            + "allow=\"" + allowed
            + "referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>"
        return "<!DOCTYPE html><html><head>" + head + "</head><body>" + frame + "</body></html>"
    }

    /// The address the player's page says it is on. YouTube's player needs to know which app it
    /// is in, and apps say so with an address made of their app id ("https://com.example.pinboard"),
    /// as YouTube asks (without it the player shows "Error 153").
    nonisolated static func playerBaseURL(appID: String?) -> URL {
        let allowed = (appID ?? "").lowercased().filter { (character: Character) -> Bool in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
        }
        let host = allowed.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return URL(string: "https://" + (host.isEmpty ? "pinboard.app" : host) + "/") ?? URL(fileURLWithPath: "/")
    }
}

// MARK: - From what was read to a ResolvedLink

extension ResolvedLink {
    /// An ordinary page: its title, description, site name and dates (the picture is added by
    /// whoever downloads it).
    nonisolated static func page(_ summary: PageSummary, url: URL) -> ResolvedLink {
        var link = ResolvedLink(url: url, flavor: .page)
        link.title = summary.title
        link.description = summary.description
        link.siteName = summary.siteName
        link.author = summary.author
        link.publishedAt = summary.publishedAt
        if let canonical = summary.canonicalURL, !SmartLinkText.samePage(canonical, url) { link.linkedURL = canonical.absoluteString }
        return link
    }

    /// An article: its text, writer, date and site (the lead picture is added by whoever downloads it).
    nonisolated static func article(_ article: Article, url: URL) -> ResolvedLink {
        var link = ResolvedLink(url: url, flavor: .article)
        link.title = article.title
        link.description = article.excerpt ?? SmartLinkText.excerpt(of: article.text)
        link.text = article.text
        link.siteName = article.siteName
        link.author = article.author
        link.publishedAt = article.publishedAt
        if let canonical = article.canonicalURL, !SmartLinkText.samePage(canonical, url) { link.linkedURL = canonical.absoluteString }
        return link
    }

    /// A YouTube video: its details, description and comments (the thumbnail is added by whoever
    /// downloads it). Its channel's page is `linkedURL`.
    nonisolated static func youTube(_ video: YouTubeVideo, url: URL) -> ResolvedLink {
        var link = ResolvedLink(url: url, flavor: .youTube)
        link.title = video.title.map { (title: String) -> String in SmartLinkText.shorten(SmartLinkText.collapse(title), to: SmartLinkText.titleLimit) }
        if let description = video.description, SmartLinkText.cleaned(description) != nil {
            link.text = SmartLinkText.capped(description.trimmingCharacters(in: .whitespacesAndNewlines), to: SmartLinkText.textLimit)
            link.description = SmartLinkText.summary(of: description)
        }
        link.siteName = "YouTube"
        link.author = video.channel
        link.publishedAt = video.publishedAt
        link.linkedURL = video.channelURL
        link.duration = video.duration
        link.viewCount = video.viewCount
        link.comments = video.comments
        link.youTubeID = video.id.isEmpty ? nil : video.id
        return link
    }

    /// A Pinterest pin: its title, description, destination and creator (its picture is added by
    /// whoever downloads it). A picture pin becomes that picture; a video pin stays a link pin with
    /// its picture as the preview — its video is never saved (App Review guideline 5.2.3).
    nonisolated static func pinterest(_ pin: PinterestPin, url: URL) -> ResolvedLink {
        var link = ResolvedLink(url: url, flavor: pin.isVideo ? .page : .pinterest)
        link.title = pin.title
        if let description = pin.description {
            link.description = SmartLinkText.shorten(description, to: SmartLinkText.descriptionLimit)
            link.text = description
        }
        link.siteName = "Pinterest"
        link.author = pin.creator
        link.publishedAt = pin.createdAt
        link.linkedURL = pin.destination
        return link
    }
}
