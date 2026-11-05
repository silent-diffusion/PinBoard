//
//  SmartLinksParsers.swift  —  PinBoard
//
//  The plain reading tools behind "Read links fully" (see SmartLinks.swift): what a link
//  leads to, judged from its address alone (`LinkClassifier`); a small, forgiving HTML reader
//  (`HTMLDocument`); text and JSON helpers; and `ResolvedLink`, what reading a link found.
//  Nothing in this file goes on the internet, touches the library or draws anything: it only
//  turns text into facts, so the tests can check it on sample pages. It needs Foundation
//  only, on purpose (the tests build it on its own). The readers for articles, Pinterest and
//  YouTube pages are in SmartLinksReaders.swift.
//

import Foundation

// MARK: - What reading a link found

/// What reading a link found. Only the address and what kind of link it is are always known;
/// anything the page didn't say stays nil. Made off the main thread and handed to the library,
/// so it holds plain values only (Sendable).
struct ResolvedLink: Sendable {
    /// The address to save: the link as it was given (or where a short link such as "pin.it/…"
    /// led), without its tracking when Settings › Links › "Clean links" is on.
    var url: URL
    /// What the link turned out to be.
    var flavor: LinkFlavor
    var title: String? = nil
    /// A short summary (at most 300 characters): the page's own description, or its first lines.
    var description: String? = nil
    /// An article's text or a video's description (at most 40,000 characters), with a blank line
    /// between paragraphs.
    var text: String? = nil
    /// The site's own name ("The Verge", "YouTube", "Pinterest").
    var siteName: String? = nil
    /// An article's writer, a video's channel, a Pinterest pin's creator.
    var author: String? = nil
    var publishedAt: Date? = nil
    /// A Pinterest pin's destination, a video's channel page, or an article's own (canonical)
    /// address when it differs from `url`.
    var linkedURL: String? = nil
    /// The picture, already downloaded: a page's preview, an article's lead picture, a YouTube
    /// thumbnail, a Pinterest pin's picture, or the picture file a link leads straight to.
    var imageData: Data? = nil
    /// A video to download: only ever a video file a link leads straight to (an .mp4 or .mov
    /// address). Never a video inside a web page or on a social site, and never YouTube (its videos
    /// are only ever played in YouTube's own player) — App Review guideline 5.2.3.
    var videoURL: URL? = nil
    /// A video's length in seconds (YouTube).
    var duration: Double? = nil
    /// How often a video was watched (YouTube), when it was said.
    var viewCount: Int? = nil
    /// A video's top comments (YouTube, with an API key).
    var comments: [PinComment] = []
    /// The YouTube video's id ("dQw4w9WgXcQ").
    var youTubeID: String? = nil
    /// The video file couldn't be downloaded, so the pin is just the link instead.
    /// The import says so once it is done.
    var videoFailed = false
    /// Set only for an ordinary page or an article that gave no picture of its own: the page's own
    /// pictures to try instead, best first (`PageImages.candidates`; none when it shows none). nil for
    /// every other reading — a site with a reader of its own, a page that gave its picture, a sign-in
    /// page — which gets no stand-in picture (see `LinkPictureFinder`).
    var standInCandidates: [URL]? = nil
}

/// Which way a read link goes into the library.
enum LinkRoute: Sendable, Equatable {
    /// Download the video file it is first (a video pin).
    case video
    /// Its picture is the pin (a picture pin).
    case picture
    /// A link pin, filled in with what was read.
    case link
}

extension ResolvedLink {
    /// Where this reading leads. Only a link that is itself a video file is downloaded as a video.
    var route: LinkRoute {
        if videoURL != nil, flavor == .videoFile { return .video }
        if imageData != nil, flavor == .imageFile || flavor == .pinterest { return .picture }
        return .link
    }

    /// The same reading once its video file turned out not to be downloadable: no video any more,
    /// and the import is told (`videoFailed`). A link that was only a file address stays what it was.
    func withoutVideo() -> ResolvedLink {
        var copy = self
        copy.videoURL = nil
        copy.videoFailed = true
        if copy.flavor == .videoFile, copy.title != nil || copy.siteName != nil { copy.flavor = .page }
        return copy
    }

    /// A picture post (Reddit, TikTok, Instagram) is read before its picture is downloaded. When
    /// the download failed there is no picture to be the pin, so it is an ordinary link now — not
    /// one captioned "Picture from the web".
    mutating func becomesLinkWithoutPicture() {
        if flavor == .imageFile, imageData == nil { flavor = .page }
    }
}

/// How "Read existing links" (Settings › Links) went.
struct LinkReadingSummary: Sendable, Equatable {
    /// Links that were waiting to be read.
    var total = 0
    /// Links read.
    var read = 0
    /// Links that couldn't be read (they keep what they had).
    var unread = 0
    /// The person stopped it (or another profile was opened) before it got through them all.
    var stopped = false

    /// What the confirmation says afterwards.
    var text: String {
        if total == 0 { return "Your links have all been read already." }
        var parts: [String] = []
        if stopped { parts.append("Stopped.") }
        if read > 0 { parts.append("Read \(read) link\(read == 1 ? "" : "s").") }
        if unread > 0 {
            parts.append(read == 0 && !stopped ? "None of your links could be read." : "\(unread) couldn't be read.")
        }
        if parts.isEmpty { parts.append("No links were read.") }
        return parts.joined(separator: " ")
    }
}

/// One paragraph of an article's text as the reader shows it: a heading ("## "), a list item
/// ("• "), a quote ("> ") or plain text (see `Article.text`).
struct ArticleParagraph: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case plain, heading, bullet, quote
    }

    /// Its place in the text (paragraphs never move, so this is enough to tell them apart).
    let id: Int
    let kind: Kind
    /// The paragraph without its "## ", "• " or "> ".
    let text: String

    /// `text` (an article's, paragraphs separated by blank lines) as paragraphs.
    nonisolated static func split(_ text: String) -> [ArticleParagraph] {
        var result: [ArticleParagraph] = []
        for piece in text.components(separatedBy: "\n\n") {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            var kind = Kind.plain
            var body = trimmed
            for (marker, markerKind) in [("## ", Kind.heading), ("• ", Kind.bullet), ("> ", Kind.quote)] where trimmed.hasPrefix(marker) {
                kind = markerKind
                body = String(trimmed.dropFirst(marker.count))
                break
            }
            result.append(ArticleParagraph(id: result.count, kind: kind, text: body))
        }
        return result
    }
}

// MARK: - Telling links apart by their address

/// Tells what a link leads to from its address alone (nothing is fetched): a YouTube video, a
/// Pinterest pin, a picture or video file. Also reads the dates and lengths pages give.
enum LinkClassifier {
    /// Picture files that become picture pins.
    static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif"]
    /// Video files that become video pins: the kinds iPhone and iPad can play. (Not WebM or
    /// Matroska: the system can't read them, so such a video would be downloaded for nothing.)
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    /// The same, as the types servers say they send.
    static let videoTypes: Set<String> = ["video/mp4", "video/quicktime", "video/x-m4v", "video/3gpp"]

    /// The 11-character id of a YouTube video: youtube.com/watch?v=ID, youtu.be/ID,
    /// youtube.com/shorts/ID, /embed/ID, /live/ID (also on m., music. and youtube-nocookie.com).
    /// nil for anything else (a channel, a playlist, another site).
    nonisolated static func youTubeID(in url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        var candidate: String? = nil
        if host == "youtu.be" || host == "www.youtu.be" {
            candidate = parts.first
        } else if isYouTubeHost(host), let first = parts.first?.lowercased() {
            if first == "watch" {
                candidate = queryValue(named: "v", in: url)
            } else if ["shorts", "embed", "live", "v", "e"].contains(first), parts.count > 1 {
                candidate = parts[1]
            }
        }
        guard let candidate, isVideoID(candidate) else { return nil }
        return candidate
    }

    /// youtube.com with any sub-domain (www., m., music.), and youtube-nocookie.com.
    nonisolated static func isYouTubeHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "youtube.com" || host.hasSuffix(".youtube.com") { return true }
        return host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    /// Exactly 11 letters, digits, "-" or "_" (what every YouTube video id looks like).
    nonisolated static func isVideoID(_ text: String) -> Bool {
        guard text.utf8.count == 11 else { return false }
        return text.utf8.allSatisfy { (byte: UInt8) -> Bool in
            SmartLinkText.isASCIIAlphanumeric(byte) || byte == 45 || byte == 95   // "-" "_"
        }
    }

    /// Any Pinterest address: pinterest.com and its country sites (pinterest.co.uk, de.pinterest.com,
    /// pinterest.fr…), and the short links pin.it makes. Not pinimg.com (Pinterest's picture files:
    /// those are picture links).
    nonisolated static func isPinterest(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "pin.it" || host == "www.pin.it" { return true }
        let labels: [String] = host.split(separator: ".").map { (label: Substring) -> String in String(label) }
        guard let index = labels.lastIndex(of: "pinterest") else { return false }
        let rest = labels[(index + 1)...]
        guard rest.count == 1 || rest.count == 2 else { return false }
        return rest.allSatisfy { (label: String) -> Bool in
            label.count >= 2 && label.count <= 3 && label.allSatisfy { (character: Character) -> Bool in character.isLetter }
        }
    }

    /// The number of a Pinterest pin: "/pin/1234567890/", or the newer "/pin/some-title--1234567890/".
    nonisolated static func pinterestPinID(in url: URL) -> String? {
        let parts: [String] = url.path.split(separator: "/").map { (part: Substring) -> String in String(part) }
        guard let index = parts.firstIndex(where: { (part: String) -> Bool in part.lowercased() == "pin" }),
              index + 1 < parts.count else { return nil }
        let segment = parts[index + 1]
        if segment.count >= 5, SmartLinkText.isDigits(segment) { return segment }
        if let dashes = segment.range(of: "--", options: .backwards) {
            let tail = String(segment[dashes.upperBound...])
            if tail.count >= 5, SmartLinkText.isDigits(tail) { return tail }
        }
        return nil
    }

    /// A picture or video file by its extension ("jpg", ".MP4"…); nil for anything else.
    nonisolated static func mediaKind(fromExtension fileExtension: String) -> LinkFlavor? {
        var name = fileExtension.trimmingCharacters(in: .whitespaces).lowercased()
        if name.hasPrefix(".") { name.removeFirst() }
        if pictureExtensions.contains(name) { return .imageFile }
        if videoExtensions.contains(name) { return .videoFile }
        return nil
    }

    /// A link whose address ends in a picture or video file name.
    nonisolated static func mediaKind(of url: URL) -> LinkFlavor? {
        let fileExtension = url.pathExtension
        guard !fileExtension.isEmpty else { return nil }
        return mediaKind(fromExtension: fileExtension)
    }

    /// A picture or video by the type a server says it sends ("image/jpeg", "video/mp4; …").
    /// Drawings (SVG) and icons are not pictures PinBoard can keep, and only the videos in
    /// `videoTypes` are videos it can keep.
    nonisolated static func mediaKind(fromContentType contentType: String) -> LinkFlavor? {
        let bare = bareType(contentType)
        if bare.hasPrefix("image/") {
            if bare.contains("svg") || bare.contains("icon") { return nil }
            return .imageFile
        }
        if videoTypes.contains(bare) { return .videoFile }
        return nil
    }

    /// "video/mp4" for "Video/MP4; codecs=…": the type alone, in small letters.
    nonisolated static func bareType(_ contentType: String) -> String {
        let first = contentType.split(separator: ";").first ?? ""
        return first.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// A type a server gives a video's address that isn't worth downloading: a page, a stream's
    /// playlist, or a video iPhone and iPad can't play (WebM, Matroska…). A type that says
    /// nothing ("application/octet-stream", or none) is not refused: the file is checked once here.
    nonisolated static func refusesVideo(contentType: String) -> Bool {
        let bare = bareType(contentType)
        if bare.hasPrefix("text/") || bare.contains("mpegurl") { return true }
        return bare.hasPrefix("video/") && !videoTypes.contains(bare)
    }

    /// A length written the ISO 8601 way, in seconds: "PT4M13S" → 253, "PT1H2M" → 3720,
    /// "P1DT2H" → 93600. nil for anything else (months and years are not lengths).
    nonisolated static func isoDuration(_ text: String) -> Double? {
        let upper = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard upper.hasPrefix("P"), upper.count > 1 else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        var sawValue = false
        for character in upper.dropFirst() {
            if character == "T" {
                guard number.isEmpty, !inTime else { return nil }
                inTime = true
                continue
            }
            if character.isASCII, character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number) else { return nil }
            number = ""
            switch (character, inTime) {
            case ("W", false): total += value * 604_800
            case ("D", false): total += value * 86_400
            case ("H", true): total += value * 3_600
            case ("M", true): total += value * 60
            case ("S", true): total += value
            default: return nil
            }
            sawValue = true
        }
        guard number.isEmpty, sawValue else { return nil }
        return total
    }

    /// A date as pages write them: ISO 8601 with or without fractions of a second and a time
    /// zone ("2024-01-02T10:00:00Z", "2024-01-02T10:00:00.123+01:00", "2024-01-02T10:00"), a day
    /// alone ("2024-01-02", "January 2, 2024"), and the way e-mail and Pinterest write them
    /// ("Tue, 02 Jan 2024 10:00:00 +0000"). A day alone is kept as noon of that day (world time),
    /// so it shows as that same day wherever the device is. Without a time zone: world time (UTC).
    nonisolated static func date(from text: String) -> Date? {
        let trimmed = trimmedFractions(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard trimmed.count >= 8, trimmed.count <= 64 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in dayFormats {
            formatter.dateFormat = format
            if let day = formatter.date(from: trimmed) { return day.addingTimeInterval(12 * 3_600) }
        }
        for format in timeFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Dates without a time (kept as noon, see `date(from:)`).
    static let dayFormats: [String] = ["yyyy-MM-dd", "yyyy/MM/dd", "MMMM d, yyyy", "MMM d, yyyy", "d MMMM yyyy", "d MMM yyyy"]
    /// Dates with a time, most common first.
    static let timeFormats: [String] = [
        "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE MMM dd HH:mm:ss Z yyyy"
    ]

    /// "…05.123456Z" → "…05.123Z": the date readers take at most three digits after the second.
    nonisolated static func trimmedFractions(_ text: String) -> String {
        guard let tee = text.firstIndex(where: { (character: Character) -> Bool in character == "T" || character == " " }),
              let dot = text[tee...].firstIndex(of: ".") else { return text }
        var end = text.index(after: dot)
        var digits = 0
        while end < text.endIndex, text[end].isASCII, text[end].isNumber {
            digits += 1
            end = text.index(after: end)
        }
        guard digits > 3 else { return text }
        let keep = text.index(dot, offsetBy: 4)
        return String(text[..<keep]) + String(text[end...])
    }

    /// The value of one query parameter of a link ("v" of "watch?v=…").
    nonisolated static func queryValue(named name: String, in url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first(where: { (item: URLQueryItem) -> Bool in item.name == name })?.value
    }
}

// MARK: - Text helpers

/// Small text helpers shared by the readers (plain functions, no state).
enum SmartLinkText {
    /// The longest title kept (a page's title can be a paragraph).
    static let titleLimit = 120
    /// The longest short description kept (`ResolvedLink.description`).
    static let descriptionLimit = 300
    /// The longest text kept (an article's text, a video's description).
    static let textLimit = 40_000

    /// Runs of spaces, tabs, line breaks and non-breaking spaces become one space; invisible
    /// characters (soft hyphens, zero-width spaces) go; no space at either end.
    nonisolated static func collapse(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if isInvisible(scalar) { continue }
            if isSpace(scalar) {
                pendingSpace = true
                continue
            }
            if pendingSpace, !result.isEmpty { result.append(" ") }
            pendingSpace = false
            result.append(scalar)
        }
        return String(result)
    }

    /// A space, tab, line break, non-breaking space… (what `collapse` joins into one space).
    /// Plain ASCII is told apart at once; only other characters ask Unicode (which is slower).
    nonisolated static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x80 { return scalar.value == 0x20 || (scalar.value >= 0x09 && scalar.value <= 0x0D) }
        return scalar.properties.isWhitespace
    }

    /// A soft hyphen or a zero-width space: characters `collapse` leaves out.
    nonisolated static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{00AD}" || scalar == "\u{200B}" || scalar == "\u{FEFF}"
    }

    /// `text` cut to at most `limit` characters at a word, with "…" when something was cut.
    nonisolated static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(max(1, limit - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    /// A long text cut to at most `limit` characters, at the end of a paragraph when there is one
    /// in the last quarter (so an article never ends in the middle of a sentence if it can help it).
    nonisolated static func capped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        if let lastBreak = cut.range(of: "\n\n", options: .backwards),
           cut.distance(from: cut.startIndex, to: lastBreak.lowerBound) > limit * 3 / 4 {
            return String(cut[..<lastBreak.lowerBound])
        }
        return shorten(cut, to: limit)
    }

    /// Trimmed, with its inner spaces collapsed; nil when nothing is left.
    nonisolated static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let result = collapse(text)
        return result.isEmpty ? nil : result
    }

    /// `text` with "&amp;", "&#8217;" and the like turned into their characters.
    nonisolated static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let bytes = Array(text.utf8)
        return HTMLEntities.decode(bytes, 0, bytes.count, inAttribute: false)
    }

    /// The words in a text ("it's" is one word).
    nonisolated static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isWordPart = scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "'" || scalar == "’"
            if isWordPart, !inWord { count += 1 }
            inWord = isWordPart
        }
        return count
    }

    /// Minutes an article takes to read at an easy pace (230 words a minute); at least 1.
    nonisolated static func readingMinutes(words: Int) -> Int {
        max(1, Int((Double(words) / 230).rounded()))
    }

    /// A video length worth keeping and showing: at least a second, and less than a billion
    /// seconds (about 30 years). A page can write any number ("1e300"), and one that big would
    /// not even fit in a whole number: working out "4:13" from it would stop the app.
    nonisolated static func isPlausibleLength(_ seconds: Double) -> Bool {
        seconds.isFinite && seconds >= 1 && seconds < 1e9
    }

    /// "4:13", "1:02:03" — a video's length (nil for one that isn't plausible, see above).
    nonisolated static func lengthText(_ seconds: Double) -> String? {
        guard isPlausibleLength(seconds) else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// "999", "1.2K", "12K", "3.4M", "1.1B" — a count as YouTube shows it.
    nonisolated static func compactCount(_ count: Int) -> String {
        let value = Double(max(0, count))
        let steps: [(Double, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        for (size, letter) in steps where value >= size {
            let scaled = value / size
            if scaled >= 10 { return "\(Int(scaled))\(letter)" }
            let tenths = (scaled * 10).rounded(.down) / 10
            let text = tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
            return text + letter
        }
        return String(Int(value))
    }

    /// The first lines of a text, joined, as a short description (at most `limit` characters).
    nonisolated static func summary(of text: String, limit: Int = descriptionLimit) -> String? {
        var pieces: [String] = []
        var length = 0
        for line in text.components(separatedBy: .newlines) {
            let clean = collapse(line)
            if clean.isEmpty { continue }
            pieces.append(clean)
            length += clean.count
            if length >= limit { break }
        }
        let joined = pieces.joined(separator: " ")
        return joined.isEmpty ? nil : shorten(joined, to: limit)
    }

    /// Parts joined with " · ", leaving out the empty ones; nil when none is left
    /// ("Jane Doe · The Verge · 5 min read").
    nonisolated static func joinedLine(_ parts: [String?]) -> String? {
        let kept = parts.compactMap { (part: String?) -> String? in cleaned(part) }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// An article's opening as its short description: its first plain paragraph (and the next
    /// one too when the first is short), never a heading, list item or quote; at most `limit`.
    nonisolated static func excerpt(of text: String, limit: Int = descriptionLimit) -> String? {
        var pieces: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            if paragraph.hasPrefix("## ") || paragraph.hasPrefix("• ") || paragraph.hasPrefix("> ") { continue }
            let clean = collapse(paragraph)
            if clean.isEmpty { continue }
            pieces.append(clean)
            if pieces.joined(separator: " ").count >= 100 { break }
        }
        let joined = pieces.joined(separator: " ")
        return joined.isEmpty ? summary(of: text, limit: limit) : shorten(joined, to: limit)
    }

    /// Two addresses lead to the same page: the same host (without "www.") and path (without a
    /// last "/"), whatever their query, fragment or "http"/"https".
    nonisolated static func samePage(_ first: URL, _ second: URL) -> Bool {
        pageIdentity(first) == pageIdentity(second)
    }

    /// See `samePage`.
    nonisolated static func pageIdentity(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        if path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// "example.com" for "https://www.example.com/page".
    nonisolated static func bareHost(of url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Only digits 0–9 (and at least one).
    nonisolated static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (byte: UInt8) -> Bool in byte >= 48 && byte <= 57 }
    }

    /// A–Z, a–z, 0–9.
    nonisolated static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    /// An http(s) address (with a host) made from `text`, turned into https; nil for anything
    /// else ("javascript:", a mail address, a broken address).
    nonisolated static func secureURL(_ text: String?, relativeTo base: URL? = nil) -> URL? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let escaped = raw.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: escaped, relativeTo: base)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else { return nil }
        switch components.scheme?.lowercased() {
        case "https": return url
        case "http":
            components.scheme = "https"
            return components.url
        default: return nil
        }
    }
}

// MARK: - HTML character references

/// Turns "&amp;", "&eacute;", "&#8217;" and "&#x1F600;" into their characters.
enum HTMLEntities {
    /// The named references pages use (a browser knows two thousand; these cover real pages).
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "laquo": "«", "raquo": "»", "lsaquo": "‹",
        "rsaquo": "›", "bull": "•", "middot": "·", "prime": "′", "Prime": "″", "copy": "©",
        "reg": "®", "trade": "™", "deg": "°", "plusmn": "±", "times": "×", "divide": "÷",
        "micro": "µ", "para": "¶", "sect": "§", "euro": "€", "pound": "£", "yen": "¥",
        "cent": "¢", "curren": "¤", "iexcl": "¡", "iquest": "¿", "ordf": "ª", "ordm": "º",
        "sup1": "¹", "sup2": "²", "sup3": "³", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "shy": "\u{00AD}", "zwj": "\u{200D}", "zwnj": "\u{200C}", "thinsp": "\u{2009}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        "dagger": "†", "Dagger": "‡", "permil": "‰", "larr": "←", "rarr": "→", "uarr": "↑",
        "darr": "↓", "harr": "↔", "hearts": "♥", "acute": "´", "cedil": "¸", "uml": "¨",
        "macr": "¯", "circ": "ˆ", "tilde": "˜", "not": "¬", "brvbar": "¦", "minus": "−",
        "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "infin": "∞", "radic": "√", "sum": "∑",
        "equiv": "≡", "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä",
        "Aring": "Å", "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê",
        "Euml": "Ë", "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "ETH": "Ð",
        "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö",
        "Oslash": "Ø", "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý",
        "THORN": "Þ", "szlig": "ß", "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã",
        "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é",
        "ecirc": "ê", "euml": "ë", "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï",
        "eth": "ð", "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ",
        "ouml": "ö", "oslash": "ø", "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü",
        "yacute": "ý", "thorn": "þ", "yuml": "ÿ", "Yuml": "Ÿ", "OElig": "Œ", "oelig": "œ",
        "Scaron": "Š", "scaron": "š", "Zcaron": "Ž", "zcaron": "ž", "fnof": "ƒ", "alpha": "α",
        "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "theta": "θ", "lambda": "λ",
        "mu": "μ", "pi": "π", "sigma": "σ", "tau": "τ", "phi": "φ", "omega": "ω", "Delta": "Δ",
        "Sigma": "Σ", "Omega": "Ω"
    ]

    /// Names browsers also read without the closing ";" (in text only, never inside attributes,
    /// so an address such as "?a=1&copy=2" stays as written).
    static let legacyNames: Set<String> = ["amp", "lt", "gt", "quot", "nbsp", "copy", "reg"]

    /// Characters 128–159 written as numbers mean the Windows letters in that place (what every
    /// browser does): "&#146;" is "’".
    static let windows1252: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020,
        0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
        0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022,
        0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178
    ]

    /// `bytes[start..<end]` (UTF-8) as text, with its character references turned into characters.
    nonisolated static func decode(_ bytes: [UInt8], _ start: Int, _ end: Int, inAttribute: Bool) -> String {
        guard start < end else { return "" }
        var index = start
        while index < end, bytes[index] != 38 { index += 1 }   // "&"
        if index == end { return String(decoding: bytes[start..<end], as: UTF8.self) }
        var output: [UInt8] = []
        output.reserveCapacity(end - start)
        index = start
        while index < end {
            let byte = bytes[index]
            guard byte == 38, let found = reference(in: bytes, at: index, end: end, inAttribute: inAttribute) else {
                output.append(byte)
                index += 1
                continue
            }
            output.append(contentsOf: Array(found.text.utf8))
            index = found.next
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// The character reference starting with the "&" at `index`, and where reading goes on.
    private nonisolated static func reference(in bytes: [UInt8], at index: Int, end: Int,
                                              inAttribute: Bool) -> (text: String, next: Int)? {
        var cursor = index + 1
        guard cursor < end else { return nil }
        if bytes[cursor] == 35 {   // "#"
            cursor += 1
            let hex = cursor < end && (bytes[cursor] == 120 || bytes[cursor] == 88)   // "x" "X"
            if hex { cursor += 1 }
            var value: UInt32 = 0
            var digits = 0
            while cursor < end, digits < 8, let digit = digitValue(bytes[cursor], hex: hex) {
                value = value &* (hex ? 16 : 10) &+ digit
                digits += 1
                cursor += 1
            }
            guard digits > 0 else { return nil }
            if cursor < end, bytes[cursor] == 59 { cursor += 1 }   // ";"
            return (String(Character(scalar(for: value))), cursor)
        }
        let nameStart = cursor
        while cursor < end, cursor - nameStart < 32, SmartLinkText.isASCIIAlphanumeric(bytes[cursor]) { cursor += 1 }
        guard cursor > nameStart else { return nil }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self)
        if cursor < end, bytes[cursor] == 59 {
            guard let text = named[name] else { return nil }
            return (text, cursor + 1)
        }
        guard !inAttribute, legacyNames.contains(name), let text = named[name] else { return nil }
        return (text, cursor)
    }

    private nonisolated static func digitValue(_ byte: UInt8, hex: Bool) -> UInt32? {
        if byte >= 48 && byte <= 57 { return UInt32(byte - 48) }
        guard hex else { return nil }
        if byte >= 97 && byte <= 102 { return UInt32(byte - 87) }
        if byte >= 65 && byte <= 70 { return UInt32(byte - 55) }
        return nil
    }

    /// The character a number stands for (a broken number becomes "�", as in browsers).
    private nonisolated static func scalar(for value: UInt32) -> Unicode.Scalar {
        let replacement: Unicode.Scalar = "\u{FFFD}"
        if value == 0 || value > 0x10FFFF { return replacement }
        if let windows = windows1252[value] { return Unicode.Scalar(windows) ?? replacement }
        return Unicode.Scalar(value) ?? replacement
    }
}

// MARK: - A small HTML reader

/// A small, forgiving HTML reader: enough to find a page's title, its meta tags, its scripts
/// and its main text. It never fails on bad HTML — a missing end tag, a stray "<", a page cut
/// off in the middle all read the way a browser would read them, near enough — and it reads
/// at most 3 MB of a page. What it leaves out: the contents of `<script>` and `<style>` (a
/// script's text is kept apart, in `scripts`, and structured data in `jsonLD`), `<noscript>`,
/// `<svg>`, `<math>` and `<template>`.
final class HTMLDocument {
    /// One element of the page (`<p>`, `<a href>`…) or one piece of its text.
    final class Node {
        /// The element's name in small letters ("p", "a"…); "#text" for a piece of text.
        let name: String
        /// The element's attributes: names in small letters, values with "&amp;" and such decoded.
        let attributes: [String: String]
        /// What is inside it, in page order.
        fileprivate(set) var children: [Node] = []
        /// The element it is inside (nil for the document itself).
        fileprivate(set) weak var parent: Node?
        /// A piece of text: the text itself, exactly as written (spaces not collapsed).
        fileprivate(set) var textValue: String = ""
        /// A `<script>`'s contents (they are not part of the page's text).
        fileprivate(set) var rawText: String? = nil

        init(name: String, attributes: [String: String] = [:]) {
            self.name = name
            self.attributes = attributes
        }

        /// A piece of text (not an element).
        var isText: Bool { name == "#text" }

        /// One attribute's value ("href", "class"…), or nil.
        func attribute(_ attributeName: String) -> String? {
            attributes[attributeName.lowercased()]
        }

        /// Its class and id together, in small letters ("post-body main") — what the article
        /// reader looks at to tell text from sidebars, share buttons and comments.
        var classAndID: String {
            let classes = attributes["class"] ?? ""
            let id = attributes["id"] ?? ""
            return (classes + " " + id).lowercased()
        }

        /// The elements directly inside it (no text pieces).
        var elementChildren: [Node] {
            children.filter { (child: Node) -> Bool in !child.isText }
        }

        /// Its text, spaces collapsed: what a reader sees of it. Block elements (paragraphs,
        /// list items, headings…) and line breaks are kept apart by a space.
        var text: String {
            var pieces = ""
            var stack: [(node: Node, entering: Bool)] = [(self, true)]
            while let (node, entering) = stack.popLast() {
                if node.isText {
                    pieces += node.textValue
                    continue
                }
                guard entering else {
                    pieces += " "
                    continue
                }
                if node.name == "br" {
                    pieces += " "
                    continue
                }
                if HTMLDocument.blockElements.contains(node.name) {
                    pieces += " "
                    stack.append((node, false))
                }
                for child in node.children.reversed() { stack.append((child, true)) }
            }
            return SmartLinkText.collapse(pieces)
        }

        /// Adds an element or a piece of text at the end (pieces of text next to each other are joined).
        fileprivate func append(_ child: Node) {
            child.parent = self
            children.append(child)
        }

        fileprivate func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            if let last = children.last, last.isText {
                last.textValue += text
                return
            }
            let piece = Node(name: "#text")
            piece.textValue = text
            append(piece)
        }
    }

    /// Pages are read up to this size (bigger pages are cut here, which is plenty for their head
    /// and main text).
    static let maximumBytes = 3_000_000

    /// Elements that never have anything inside them.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr", "keygen", "command", "basefont", "bgsound", "frame"
    ]
    /// Elements whose contents are not HTML (read up to their end tag as they are).
    static let rawTextElements: Set<String> = ["script", "style", "title", "textarea", "xmp", "iframe", "noembed", "noframes", "noscript"]
    /// Elements whose contents are left out altogether (they may hold elements of their own).
    static let skippedElements: Set<String> = ["svg", "math", "template"]
    /// Elements that make a block of their own (their text never runs into the text around them).
    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "caption", "center", "dd", "details",
        "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html", "legend", "li",
        "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "td",
        "tfoot", "th", "thead", "tr", "ul", "search"
    ]
    /// Starting one of these ends a paragraph that is still open (`<p>one<div>` → the p ends).
    static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div",
        "dl", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "section",
        "summary", "table", "ul", "li", "dd", "dt", "search", "listing", "xmp"
    ]
    static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    /// The document itself: every element and piece of text is inside it.
    let root: Node
    /// Every element in page order (so looking elements up by name is quick).
    let allElements: [Node]
    /// The text of every `<script>`, in page order.
    let scripts: [String]
    /// The text of every `<script type="application/ld+json">` (a page's structured data).
    let jsonLD: [String]
    /// The address the page came from (relative links are read against it).
    let baseURL: URL?
    private let metaValues: [String: [String]]

    /// Reads `html` (at most `maximumBytes` of it). `url`: where it came from, for relative links.
    init(html: String, url: URL? = nil) {
        var bytes = Array(html.utf8)
        if bytes.count > HTMLDocument.maximumBytes { bytes.removeSubrange(HTMLDocument.maximumBytes...) }
        let builder = HTMLTreeBuilder(bytes: bytes)
        builder.run()
        root = builder.root
        allElements = builder.elements
        scripts = builder.scripts
        jsonLD = builder.jsonLD
        metaValues = builder.metas
        var base = url
        if let href = builder.baseHref, let resolved = URL(string: href, relativeTo: url)?.absoluteURL { base = resolved }
        baseURL = base
    }

    /// The page's `<title>`, spaces collapsed (nil when it has none).
    var title: String? {
        guard let element = allElements.first(where: { (node: Node) -> Bool in node.name == "title" }) else { return nil }
        return SmartLinkText.cleaned(element.text)
    }

    /// The first `<meta>` with this property, name or itemprop ("og:title", "description",
    /// "datePublished"…; small and capital letters alike), trimmed; nil when empty or missing.
    func meta(_ key: String) -> String? {
        for value in metaValues[key.lowercased()] ?? [] {
            if let clean = SmartLinkText.cleaned(value) { return clean }
        }
        return nil
    }

    /// Every `<meta>` with this property, name or itemprop, in page order.
    func metas(_ key: String) -> [String] {
        metaValues[key.lowercased()] ?? []
    }

    /// The page's own address (`<link rel="canonical">`), when it gives one.
    var canonical: URL? {
        for link in elements(named: "link") {
            let relation = (link.attribute("rel") ?? "").lowercased()
            let words = relation.split(separator: " ").map { (word: Substring) -> String in String(word) }
            if words.contains("canonical"), let url = resolve(link.attribute("href")) { return url }
        }
        return nil
    }

    /// Every element with this name ("p", "article"…), in page order.
    func elements(named name: String) -> [Node] {
        let wanted = name.lowercased()
        return allElements.filter { (node: Node) -> Bool in node.name == wanted }
    }

    /// A link found on the page as a full https address (relative links are read against the
    /// page's address); nil when it isn't a web address.
    func resolve(_ link: String?) -> URL? {
        SmartLinkText.secureURL(link, relativeTo: baseURL)
    }
}

/// Reads HTML bytes into `HTMLDocument.Node`s. One use only (see `HTMLDocument.init`).
private final class HTMLTreeBuilder {
    private let bytes: [UInt8]
    private let count: Int
    let root = HTMLDocument.Node(name: "#document")
    /// The elements open now, outermost first (change it only with `push`, `pop(from:)` and
    /// `popLast()`, which keep `openCounts` right).
    private var stack: [HTMLDocument.Node]
    /// How many elements of each name are open now: an end tag, or a new block looking for an
    /// open paragraph to close, doesn't walk the open elements for one that isn't there.
    private var openCounts: [String: Int] = [:]
    private(set) var elements: [HTMLDocument.Node] = []
    private(set) var scripts: [String] = []
    private(set) var jsonLD: [String] = []
    private(set) var metas: [String: [String]] = [:]
    private(set) var baseHref: String? = nil
    /// Elements nested deeper than this are still kept, but what is inside them is put beside
    /// them (so a page of a hundred thousand nested tags can't exhaust anything).
    private static let maximumDepth = 256

    // The bytes the reader looks for.
    private static let lessThan: UInt8 = 60, greaterThan: UInt8 = 62, slash: UInt8 = 47
    private static let bang: UInt8 = 33, question: UInt8 = 63, equals: UInt8 = 61
    private static let doubleQuote: UInt8 = 34, singleQuote: UInt8 = 39, dash: UInt8 = 45

    // Where a list item, a table cell… may be closed by the next one (see `closeInScope`).
    private static let defaultScope: Set<String> = ["html", "table", "td", "th", "caption", "marquee", "object", "template", "applet"]
    private static let buttonScope: Set<String> = defaultScope.union(["button"])
    private static let listScope: Set<String> = defaultScope.union(["ol", "ul", "menu"])
    private static let definitionScope: Set<String> = defaultScope.union(["dl"])
    private static let tableScope: Set<String> = ["html", "table", "template"]
    private static let rowScope: Set<String> = ["html", "table", "tr", "template"]
    /// What may stand in a page's head (anything else starts the body).
    private static let headContent: Set<String> = ["head", "title", "meta", "link", "script", "style", "base", "noscript",
                                                   "template", "basefont", "bgsound"]

    init(bytes: [UInt8]) {
        self.bytes = bytes
        count = bytes.count
        stack = [root]
    }

    private var current: HTMLDocument.Node { stack[stack.count - 1] }

    /// Opens `node`: what follows goes inside it.
    private func push(_ node: HTMLDocument.Node) {
        stack.append(node)
        openCounts[node.name, default: 0] += 1
    }

    /// Closes the open element at `index` and everything opened inside it.
    private func pop(from index: Int) {
        for node in stack[index...] { openCounts[node.name, default: 0] -= 1 }
        stack.removeSubrange(index...)
    }

    /// Closes the innermost open element (never the document itself).
    private func popLast() {
        guard stack.count > 1 else { return }
        pop(from: stack.count - 1)
    }

    /// Whether an element called `name` is open now.
    private func isOpen(_ name: String) -> Bool {
        (openCounts[name] ?? 0) > 0
    }

    /// Reads everything — or, when the reading this is part of was given up on (it ran out of
    /// time, see `LinkResolver.timeLimit`), stops there: what was read so far is kept.
    func run() {
        var index = 0
        var steps = 0
        while index < count {
            steps += 1
            if steps % 1_000 == 0, Task.isCancelled { return }
            if bytes[index] == HTMLTreeBuilder.lessThan {
                index = readTag(at: index)
            } else {
                var end = index + 1
                while end < count, bytes[end] != HTMLTreeBuilder.lessThan { end += 1 }
                addText(from: index, to: end)
                index = end
            }
        }
    }

    // MARK: Tags

    /// Reads whatever starts with the "<" at `index`; returns where reading goes on.
    private func readTag(at index: Int) -> Int {
        guard index + 1 < count else {
            addText(from: index, to: count)
            return count
        }
        let next = bytes[index + 1]
        if next == HTMLTreeBuilder.bang { return skipDeclaration(at: index) }
        if next == HTMLTreeBuilder.question { return skip(past: HTMLTreeBuilder.greaterThan, from: index + 2) }
        if next == HTMLTreeBuilder.slash {
            if index + 2 < count, isLetter(bytes[index + 2]) { return readEndTag(at: index) }
            return skip(past: HTMLTreeBuilder.greaterThan, from: index + 2)   // "</>", "</ 3": nothing, as in browsers
        }
        if isLetter(next) { return readStartTag(at: index) }
        addText(from: index, to: index + 1)   // a "<" on its own is just text
        return index + 1
    }

    /// Comments ("<!-- … -->"), "<!DOCTYPE …>" and "<![CDATA[ … ]]>" are skipped.
    private func skipDeclaration(at index: Int) -> Int {
        if matches("<!--", at: index) {
            let start = index + 4
            if start < count, bytes[start] == HTMLTreeBuilder.greaterThan { return start + 1 }   // "<!-->"
            if start + 1 < count, bytes[start] == HTMLTreeBuilder.dash, bytes[start + 1] == HTMLTreeBuilder.greaterThan { return start + 2 }
            return find("-->", from: start).map { (found: Int) -> Int in found + 3 } ?? count
        }
        if matches("<![CDATA[", at: index) {
            return find("]]>", from: index + 9).map { (found: Int) -> Int in found + 3 } ?? count
        }
        return skip(past: HTMLTreeBuilder.greaterThan, from: index + 2)
    }

    private func readStartTag(at index: Int) -> Int {
        var cursor = index + 1
        let nameStart = cursor
        while cursor < count, isNameByte(bytes[cursor]) { cursor += 1 }
        let name = lowercasedText(from: nameStart, to: cursor)
        guard let tag = readAttributes(from: cursor) else { return count }   // cut off inside the tag: the rest is dropped
        return open(name, attributes: tag.attributes, selfClosing: tag.selfClosing, contentStart: tag.end)
    }

    private func readEndTag(at index: Int) -> Int {
        var cursor = index + 2
        let nameStart = cursor
        while cursor < count, isNameByte(bytes[cursor]) { cursor += 1 }
        let name = lowercasedText(from: nameStart, to: cursor)
        let end = skip(past: HTMLTreeBuilder.greaterThan, from: cursor)   // (an end tag's attributes mean nothing)
        close(name)
        return end
    }

    /// A tag's attributes up to its ">", and whether it ended in "/>". nil when the page ends first.
    private func readAttributes(from start: Int) -> (attributes: [String: String], selfClosing: Bool, end: Int)? {
        var result: [String: String] = [:]
        var cursor = start
        var selfClosing = false
        while cursor < count {
            let byte = bytes[cursor]
            if isSpace(byte) {
                cursor += 1
                continue
            }
            if byte == HTMLTreeBuilder.greaterThan { return (result, selfClosing, cursor + 1) }
            if byte == HTMLTreeBuilder.slash {
                selfClosing = true
                cursor += 1
                continue
            }
            selfClosing = false
            let nameStart = cursor
            cursor += 1   // (a name may start with "=", as browsers read it)
            while cursor < count, !isSpace(bytes[cursor]), bytes[cursor] != HTMLTreeBuilder.greaterThan,
                  bytes[cursor] != HTMLTreeBuilder.slash, bytes[cursor] != HTMLTreeBuilder.equals { cursor += 1 }
            let name = lowercasedText(from: nameStart, to: cursor)
            guard let value = readAttributeValue(after: cursor) else { return nil }
            cursor = value.end
            if result[name] == nil { result[name] = value.text }   // the first of two wins, as in browsers
        }
        return nil
    }

    /// The value after an attribute's name ("= "…"", "='…'", "=bare"), or "" when it has none.
    private func readAttributeValue(after nameEnd: Int) -> (text: String, end: Int)? {
        var cursor = nameEnd
        while cursor < count, isSpace(bytes[cursor]) { cursor += 1 }
        guard cursor < count, bytes[cursor] == HTMLTreeBuilder.equals else { return ("", nameEnd) }
        cursor += 1
        while cursor < count, isSpace(bytes[cursor]) { cursor += 1 }
        guard cursor < count else { return nil }
        let quote = bytes[cursor]
        if quote == HTMLTreeBuilder.doubleQuote || quote == HTMLTreeBuilder.singleQuote {
            var end = cursor + 1
            while end < count, bytes[end] != quote { end += 1 }
            guard end < count else { return nil }
            return (HTMLEntities.decode(bytes, cursor + 1, end, inAttribute: true), end + 1)
        }
        var end = cursor
        while end < count, !isSpace(bytes[end]), bytes[end] != HTMLTreeBuilder.greaterThan { end += 1 }
        return (HTMLEntities.decode(bytes, cursor, end, inAttribute: true), end)
    }

    // MARK: Building the tree

    /// Opens an element (closing what it closes by being opened); returns where reading goes on.
    private func open(_ name: String, attributes: [String: String], selfClosing: Bool, contentStart: Int) -> Int {
        closeImplied(by: name)
        if name == "html" || name == "head" || name == "body", isOpen(name) {
            return contentStart   // a second <body> adds nothing
        }
        let node = HTMLDocument.Node(name: name, attributes: attributes)
        current.append(node)
        elements.append(node)
        if name == "meta" { noteMeta(attributes) }
        if name == "base", baseHref == nil { baseHref = attributes["href"] }
        if HTMLDocument.voidElements.contains(name) { return contentStart }
        if HTMLDocument.rawTextElements.contains(name) {
            let end = findEndTag(name, from: contentStart)
            keepRawText(of: node, from: contentStart, to: end.contentEnd)
            return end.after
        }
        if HTMLDocument.skippedElements.contains(name) {
            return selfClosing ? contentStart : skipElement(name, from: contentStart)
        }
        if stack.count < HTMLTreeBuilder.maximumDepth { push(node) }
        return contentStart
    }

    /// An end tag: closes the nearest open element of that name (with everything opened inside
    /// it). An end tag nothing matches is ignored, as browsers do.
    private func close(_ name: String) {
        if name == "br" {   // "</br>" is a line break in every browser
            let node = HTMLDocument.Node(name: "br")
            current.append(node)
            elements.append(node)
            return
        }
        if name == "body" || name == "html" { return }   // what follows still belongs to the body
        guard isOpen(name) else { return }
        var index = stack.count - 1
        let lowest = max(1, stack.count - 64)
        while index >= lowest {
            if stack[index].name == name {
                pop(from: index)
                return
            }
            index -= 1
        }
    }

    /// What browsers close by themselves when an element starts: an open paragraph before a
    /// block, the previous list item before a new one, a heading before a heading…
    private func closeImplied(by name: String) {
        // "</head>" may be left out: anything that belongs in the body ends the head, as in browsers.
        if isOpen("head"), !HTMLTreeBuilder.headContent.contains(name) { close("head") }
        if HTMLDocument.closesParagraph.contains(name) { closeInScope("p", boundaries: HTMLTreeBuilder.buttonScope) }
        switch name {
        case "li":
            closeInScope("li", boundaries: HTMLTreeBuilder.listScope)
        case "dd", "dt":
            closeInScope("dd", boundaries: HTMLTreeBuilder.definitionScope)
            closeInScope("dt", boundaries: HTMLTreeBuilder.definitionScope)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            if HTMLDocument.headings.contains(current.name) { popLast() }
        case "option", "optgroup":
            if current.name == "option" { popLast() }
            if name == "optgroup", current.name == "optgroup" { popLast() }
        case "tr":
            closeInScope("tr", boundaries: HTMLTreeBuilder.tableScope)
        case "td", "th":
            closeInScope("td", boundaries: HTMLTreeBuilder.rowScope)
            closeInScope("th", boundaries: HTMLTreeBuilder.rowScope)
        case "thead", "tbody", "tfoot":
            for section in ["thead", "tbody", "tfoot"] { closeInScope(section, boundaries: HTMLTreeBuilder.tableScope) }
        case "a", "button":
            closeInScope(name, boundaries: HTMLTreeBuilder.defaultScope)
        default:
            break
        }
    }

    /// Closes the nearest open `name`, unless one of `boundaries` is open inside it. Like `close`,
    /// it looks only at the 64 innermost open elements: a page of deeply nested blocks would
    /// otherwise have every new block walk hundreds of them.
    private func closeInScope(_ name: String, boundaries: Set<String>) {
        guard isOpen(name) else { return }
        var index = stack.count - 1
        let lowest = max(1, stack.count - 64)
        while index >= lowest {
            let openName = stack[index].name
            if openName == name {
                pop(from: index)
                return
            }
            if boundaries.contains(openName) { return }
            index -= 1
        }
    }

    private func addText(from start: Int, to end: Int) {
        guard start < end else { return }
        current.appendText(HTMLEntities.decode(bytes, start, end, inAttribute: false))
    }

    /// A `<meta>`'s content, under each of its keys (property, name, itemprop).
    private func noteMeta(_ attributes: [String: String]) {
        guard let content = attributes["content"] else { return }
        for keyName in ["property", "name", "itemprop"] {
            guard let key = attributes[keyName]?.trimmingCharacters(in: .whitespaces).lowercased(), !key.isEmpty else { continue }
            metas[key, default: []].append(content)
        }
    }

    /// What is inside a script, a title, a text area…: a script's text is kept apart; a title's
    /// and a text area's become their text; the rest (styles, frames, noscript) is left out.
    private func keepRawText(of node: HTMLDocument.Node, from start: Int, to end: Int) {
        guard start < end else { return }
        switch node.name {
        case "script":
            let text = String(decoding: bytes[start..<end], as: UTF8.self)
            node.rawText = text
            scripts.append(text)
            if (node.attributes["type"] ?? "").lowercased().contains("ld+json") { jsonLD.append(text) }
        case "title", "textarea":
            node.appendText(HTMLEntities.decode(bytes, start, end, inAttribute: false))
        default:
            break
        }
    }

    /// Where the contents of a raw-text element end (the "<" of its end tag) and where reading
    /// goes on after that end tag. A missing end tag runs to the end of the page.
    private func findEndTag(_ name: String, from start: Int) -> (contentEnd: Int, after: Int) {
        let wanted = Array(name.utf8)
        var index = start
        while index + 1 < count {
            if bytes[index] == HTMLTreeBuilder.lessThan, bytes[index + 1] == HTMLTreeBuilder.slash,
               let nameEnd = matchName(wanted, at: index + 2) {
                return (index, skip(past: HTMLTreeBuilder.greaterThan, from: nameEnd))
            }
            index += 1
        }
        return (count, count)
    }

    /// Skips an `<svg>`, `<math>` or `<template>` with everything inside it (the same element
    /// may be nested inside it).
    private func skipElement(_ name: String, from start: Int) -> Int {
        let wanted = Array(name.utf8)
        var depth = 1
        var index = start
        while index + 1 < count {
            guard bytes[index] == HTMLTreeBuilder.lessThan else {
                index += 1
                continue
            }
            if bytes[index + 1] == HTMLTreeBuilder.slash, let nameEnd = matchName(wanted, at: index + 2) {
                depth -= 1
                index = skip(past: HTMLTreeBuilder.greaterThan, from: nameEnd)
                if depth == 0 { return index }
                continue
            }
            if let nameEnd = matchName(wanted, at: index + 1) {
                let tagEnd = skip(past: HTMLTreeBuilder.greaterThan, from: nameEnd)
                let selfClosing = tagEnd >= 2 && tagEnd - 2 >= nameEnd && bytes[tagEnd - 2] == HTMLTreeBuilder.slash
                if !selfClosing { depth += 1 }
                index = tagEnd
                continue
            }
            index += 1
        }
        return count
    }

    // MARK: Byte helpers

    /// When `wanted` (a lower-case name) is written at `index` (any case) and then ends, where it ends.
    private func matchName(_ wanted: [UInt8], at index: Int) -> Int? {
        guard index + wanted.count <= count else { return nil }
        for offset in 0..<wanted.count where lowercased(bytes[index + offset]) != wanted[offset] { return nil }
        let after = index + wanted.count
        if after < count, isNameByte(bytes[after]) { return nil }   // "<scripts>" is not "<script>"
        return after
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        let wanted = Array(text.utf8)
        guard index + wanted.count <= count else { return false }
        for offset in 0..<wanted.count where lowercased(bytes[index + offset]) != lowercased(wanted[offset]) { return false }
        return true
    }

    private func find(_ text: String, from start: Int) -> Int? {
        let wanted = Array(text.utf8)
        guard let first = wanted.first, wanted.count <= count else { return nil }
        var index = start
        while index + wanted.count <= count {
            if bytes[index] == first, matches(text, at: index) { return index }
            index += 1
        }
        return nil
    }

    /// The index just after the next `byte` from `start` (the end of the page when there is none).
    private func skip(past byte: UInt8, from start: Int) -> Int {
        var index = start
        while index < count {
            if bytes[index] == byte { return index + 1 }
            index += 1
        }
        return count
    }

    private func lowercasedText(from start: Int, to end: Int) -> String {
        guard start < end else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self).lowercased()
    }

    private func lowercased(_ byte: UInt8) -> UInt8 {
        (byte >= 65 && byte <= 90) ? byte + 32 : byte
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    /// Letters, digits, "-", "_", ":" and "." (what tag names are made of).
    private func isNameByte(_ byte: UInt8) -> Bool {
        SmartLinkText.isASCIIAlphanumeric(byte) || byte == 45 || byte == 95 || byte == 58 || byte == 46
    }

    private func isSpace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    }
}

// MARK: - JSON inside pages

/// Reading the JSON that pages carry in their scripts (YouTube's player data, Pinterest's pin
/// data, structured data). Values come back as Foundation's plain types.
enum JSONText {
    /// The JSON in `text`, or nil when it isn't JSON.
    nonisolated static func parse(_ text: String) -> Any? {
        let data = Data(text.utf8)
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }

    /// The JSON object written right after `marker` in `text` ("ytInitialPlayerResponse = {…}"),
    /// found by matching its braces (a brace inside a string doesn't count). nil when there is none.
    nonisolated static func object(after marker: String, in text: String) -> String? {
        var searchStart = text.startIndex
        while let found = text.range(of: marker, range: searchStart..<text.endIndex) {
            let rest = text.utf8[found.upperBound...]
            if let open = rest.firstIndex(where: { (byte: UInt8) -> Bool in !(byte == 32 || byte == 9 || byte == 10 || byte == 13) }),
               rest[open] == 123 {   // "{"
                let bytes = Array(text.utf8[open...])
                if let close = matchingClose(bytes, from: 0) {
                    return String(decoding: bytes[0...close], as: UTF8.self)
                }
                return nil
            }
            searchStart = found.upperBound
        }
        return nil
    }

    /// The index of the "}" or "]" that closes the "{" or "[" at `open`.
    nonisolated static func matchingClose(_ bytes: [UInt8], from open: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 92 {   // "\"
                    escaped = true
                } else if byte == 34 {   // the closing quote
                    inString = false
                }
            } else if byte == 34 {
                inString = true
            } else if byte == 123 || byte == 91 {
                depth += 1
            } else if byte == 125 || byte == 93 {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// The first object (anywhere inside `root`) that `matches` accepts. Looks at no more than
    /// `limit` values, so a huge page can't keep it busy.
    nonisolated static func firstObject(in root: Any, limit: Int = 400_000,
                                        where matches: ([String: Any]) -> Bool) -> [String: Any]? {
        var stack: [Any] = [root]
        var visited = 0
        while let value = stack.popLast(), visited < limit {
            visited += 1
            if let object = value as? [String: Any] {
                if matches(object) { return object }
                for child in object.values where child is [String: Any] || child is [Any] { stack.append(child) }
            } else if let array = value as? [Any] {
                for child in array.reversed() where child is [String: Any] || child is [Any] { stack.append(child) }
            }
        }
        return nil
    }

    /// The value at a path of keys ("videoDetails", "title"); nil when any step is missing.
    nonisolated static func value(_ root: Any?, _ path: [String]) -> Any? {
        var current = root
        for key in path {
            guard let object = current as? [String: Any] else { return nil }
            current = object[key]
        }
        return current
    }

    /// A non-empty text value, trimmed.
    nonisolated static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A whole number, whether it was written as a number or as text ("12345").
    nonisolated static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double, number.isFinite, abs(number) < 9e18 { return Int(number) }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// A number (seconds and such), whether written as a number or as text.
    nonisolated static func double(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    /// The first `"key":"…"` text value written in `text` that isn't empty (decoded), without
    /// reading the JSON around it — for pages whose JSON can't be read whole.
    nonisolated static func stringValue(forKey key: String, in text: String) -> String? {
        let marker = "\"" + key + "\":\""
        var searchStart = text.startIndex
        while let found = text.range(of: marker, range: searchStart..<text.endIndex) {
            if let value = readString(in: text, from: found.upperBound), SmartLinkText.cleaned(value) != nil {
                return value   // (as written: a description keeps its line breaks)
            }
            searchStart = found.upperBound
        }
        return nil
    }

    /// The JSON text that starts at `start` (just after its opening quote), decoded.
    nonisolated static func readString(in text: String, from start: String.Index) -> String? {
        let utf8 = text.utf8
        var index = start
        var escaped = false
        while index < utf8.endIndex {
            let byte = utf8[index]
            if escaped {
                escaped = false
            } else if byte == 92 {
                escaped = true
            } else if byte == 34 {
                return unescape(String(decoding: utf8[start..<index], as: UTF8.self))
            }
            index = utf8.index(after: index)
        }
        return nil
    }

    /// A JSON (or JavaScript) text's escapes decoded: "\n", "\"", "\\", "\/", "é", "\x3d".
    nonisolated static func unescape(_ raw: String) -> String {
        guard raw.contains("\\") else { return raw }
        let scalars = Array(raw.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\\", index + 1 < scalars.count else {
                result.append(scalar)
                index += 1
                continue
            }
            let code = scalars[index + 1]
            switch code {
            case "n": result.append("\n"); index += 2
            case "t": result.append("\t"); index += 2
            case "r": index += 2
            case "b", "f": index += 2
            case "u":
                let decoded = unicodeEscape(scalars, at: index)
                result.append(decoded.scalar)
                index = decoded.next
            case "x":
                if let value = hexValue(scalars, from: index + 2, digits: 2), let byteScalar = Unicode.Scalar(value) {
                    result.append(byteScalar)
                    index += 4
                } else {
                    result.append(code)
                    index += 2
                }
            default:
                result.append(code)   // "\"", "\\", "\/", "\'"
                index += 2
            }
        }
        return String(result)
    }

    /// "\uXXXX" at `index` (with a second "\uXXXX" when the two make one character).
    private nonisolated static func unicodeEscape(_ scalars: [Unicode.Scalar], at index: Int) -> (scalar: Unicode.Scalar, next: Int) {
        let replacement: Unicode.Scalar = "\u{FFFD}"
        guard let high = hexValue(scalars, from: index + 2, digits: 4) else { return ("u", index + 2) }
        if high >= 0xD800, high <= 0xDBFF {
            if index + 11 < scalars.count, scalars[index + 6] == "\\", scalars[index + 7] == "u",
               let low = hexValue(scalars, from: index + 8, digits: 4), low >= 0xDC00, low <= 0xDFFF {
                let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                return (Unicode.Scalar(combined) ?? replacement, index + 12)
            }
            return (replacement, index + 6)
        }
        return (Unicode.Scalar(high) ?? replacement, index + 6)
    }

    private nonisolated static func hexValue(_ scalars: [Unicode.Scalar], from start: Int, digits: Int) -> UInt32? {
        guard start + digits <= scalars.count else { return nil }
        var value: UInt32 = 0
        for offset in 0..<digits {
            let character = scalars[start + offset]
            guard character.isASCII, let digit = UInt32(String(character), radix: 16) else { return nil }
            value = value * 16 + digit
        }
        return value
    }
}
