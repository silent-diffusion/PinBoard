//
//  Models.swift  —  PinBoard
//
//  Data types shared by the whole app, plus the image resizing helpers. Dates in
//  library files are read in today's form or the plain numbers older files used.
//

import SwiftUI
import ImageIO
import UIKit
import Foundation

// MARK: - Models

/// One AI-generated tag with the model's confidence (0…1).
struct TagScore: Codable, Hashable {
    var label: String
    var confidence: Double
}

/// What kind of thing a pin is.
enum PinKind: String, Codable, Sendable, CaseIterable {
    case image, text, video, link

    var label: String {
        switch self {
        case .image: return "Photos"
        case .text: return "Text"
        case .video: return "Videos"
        case .link: return "Links"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .text: return "text.alignleft"
        case .video: return "play.rectangle"
        case .link: return "link"
        }
    }
}

/// A pin's title together with who wrote it (kept so an AI rename can be undone).
struct TitleState: Codable, Hashable, Sendable {
    var title: String
    var isAuto: Bool          // mirrors Pin.titleIsAuto
    var editedByUser: Bool    // mirrors Pin.titleEditedByUser
    var lastAITitle: String?  // mirrors Pin.lastAITitle
}

/// The AI's last rename of one pin.
struct TitleUndo: Codable, Hashable, Sendable {
    var previous: TitleState  // the title (and its flags) before the AI changed it
    var aiTitle: String       // what the AI wrote; Undo applies only while the pin still has exactly this title
    var runID: UUID?          // the "AI sorting → naming" run that made the change (nil = a single rename)
    var date: Date
}

// Read by hand only so its date may be stored either way (see `StoredDate`); written as usual.
extension TitleUndo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        previous = try c.decode(TitleState.self, forKey: .previous)
        aiTitle = try c.decode(String.self, forKey: .aiTitle)
        runID = try c.decodeIfPresent(UUID.self, forKey: .runID)
        guard let stored = c.flexibleDate(forKey: .date) else {
            let context = DecodingError.Context(codingPath: c.codingPath, debugDescription: "No date")
            throw DecodingError.keyNotFound(CodingKeys.date, context)
        }
        date = stored
    }
}

/// What a link turned out to be when PinBoard read it (Settings › Links › "Read links fully").
/// A link that became a picture or video pin keeps this too, so the page can say where it came from.
enum LinkFlavor: String, Codable, Sendable {
    case page        // an ordinary web page: title, description and preview picture
    case article     // a readable article: its text (in `textBody`), writer and date were kept
    case youTube     // a YouTube video: its details and top comments were kept; it plays embedded
    case pinterest   // a Pinterest pin: its picture became the pin itself (a video pin stays a link)
    case imageFile   // a link straight to a picture file: it became a picture pin
    case videoFile   // a link straight to a video file: it became a video pin

    var label: String {
        switch self {
        case .page: return "Web page"
        case .article: return "Article"
        case .youTube: return "YouTube video"
        case .pinterest: return "Pinterest pin"
        case .imageFile: return "Picture from the web"
        case .videoFile: return "Video from the web"
        }
    }
}

/// One comment kept with a pin (a YouTube video's top comments).
struct PinComment: Codable, Hashable, Sendable {
    var author: String
    var text: String
    var likes: Int = 0
    var date: Date? = nil
}

/// How big the copy of a video kept on this device may be (Settings › iCloud & storage › "Video quality").
/// Videos larger than the chosen size are converted when they are added; smaller ones are kept
/// as they are. `original` converts nothing.
enum VideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, uhd, fullHD, hd
    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .uhd: return "4K"
        case .fullHD: return "1080p"
        case .hd: return "720p"
        }
    }

    /// The longest side of a frame at this quality (nil: no limit).
    var maxLongEdge: Int? {
        switch self {
        case .original: return nil
        case .uhd: return 3840
        case .fullHD: return 1920
        case .hd: return 1280
        }
    }
}

/// Where a web search opened from the app is shown (Settings › Explore & web search › "Open web searches in").
/// `.safari` is the stored name of the second choice; what it opens is whatever browser the
/// person made their default (Safari, Chrome…), so it is shown as "Default browser".
enum WebSearchBrowser: String, Codable, CaseIterable, Identifiable, Sendable {
    case inApp, safari
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inApp: return "PinBoard (private)"
        case .safari: return "Default browser"
        }
    }
}

/// How a picture that lives only in the library reaches the search page of a reverse image
/// search (Settings › Explore & web search › "Hand the picture over by"): a search site can't be sent a link
/// to it, so the person uploads it on the page from wherever PinBoard put it.
enum WebSearchPictureHandoff: String, Codable, CaseIterable, Identifiable, Sendable {
    case clipboard, files, photos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: return "Copying it to the clipboard"
        case .files: return "Saving it to Files"
        case .photos: return "Saving it to Photos"
        }
    }
}

/// A passage marked in an article's text ("Read article"): the quote itself, and where it
/// stands in the pin's `textBody` (UTF-16 offsets, as `NSRange` counts). The quote text is kept
/// so the mark can find its place again after the article was read again and its text moved a
/// little (see `ArticleHighlights`, SmartLinksViews.swift). A highlight stays with the pin, so
/// it is there the next time the article is opened, on every device.
struct TextHighlight: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var text: String
    var start: Int
    var length: Int
    var createdAt: Date = Date()
}

/// A reverse image search site ("Search this picture on the web ▸"; see WebBrowser.swift).
enum ReverseImageEngine: String, CaseIterable, Identifiable, Sendable {
    case googleLens, bing, tinEye, yandex
    var id: String { rawValue }
    var label: String {
        switch self {
        case .googleLens: return "Google Lens"
        case .bing: return "Bing"
        case .tinEye: return "TinEye"
        case .yandex: return "Yandex"
        }
    }
}

/// A saved item ("pin"): a picture, a piece of text, a video, or a link.
struct Pin: Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: PinKind = .image
    var textBody: String = ""          // text pins: the text itself (the title is separate)
    var videoExtension: String? = nil  // video pins: "mov", "mp4"… (the poster frame is the pin's image)
    var duration: Double? = nil        // video pins: seconds
    var linkURL: String? = nil         // link pins: the page address (the preview picture is the pin's image, if any)
    var hasPreview: Bool = false       // link pins: a preview picture was stored
    var updatedAt: Date = Date()       // last change (used to merge libraries)
    var title: String = ""
    var titleIsAuto: Bool = false      // true when the AI wrote the title (user edits set it false)
    var note: String = ""
    var tags: [String] = []            // tags you add yourself
    var aiTags: [TagScore] = []        // tags found by on-device (or cloud) AI
    var colorTags: [String] = []       // dominant colours ("blue", "black and white"…)
    var ocrTags: [String] = []         // key words taken from text found in the image
    var ocrText: String = ""           // full text the AI read inside the image
    var aiDescription: String = ""     // one-line description (cloud AI only)
    var aiSearchHint: String? = nil    // compact web query suggested by cloud AI
    var width: Double = 1
    var height: Double = 1
    var boardIDs: [UUID] = []          // a pin can live on several boards; empty = "Unsorted"
    var createdAt: Date = Date()
    var needsAnalysis: Bool = true     // true until the AI has looked at it
    var hasFeaturePrint: Bool = false  // a visual fingerprint file exists on disk
    /// Looked at while hidden with "Include hidden pins in AI" off: only the fixed, rule-based
    /// checks ran (colours, fingerprint, look-alikes), no AI. It gets the AI's look once the AI may
    /// see it (un-hidden, or the switch turned on): `LibraryStore.wakePinsTheAIMaySeeNow`.
    var aiSkipped: Bool = false
    var sourceURL: String? = nil       // web page the image came from, if any
    var credit: String? = nil          // "Photo by … · Pexels", if any
    var deletedAt: Date? = nil         // in "Recently deleted" when set
    var dhash: UInt64? = nil           // perceptual hash, for duplicate detection
    var duplicateOfID: UUID? = nil     // looks identical to this existing pin
    var notDuplicateOf: [UUID] = []    // pins you said are different ("Keep both")
    var placementReason: String? = nil // why auto-sort put it on a board

    // From the photo file itself (EXIF / IPTC), when it had any.
    var capturedAt: Date? = nil
    var cameraModel: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var fileKeywords: [String] = []
    var fileCaption: String? = nil

    /// Hidden on its own ("Hide pin"): it lives in the Hidden section, with or without boards.
    /// (A pin is also hidden when it is on any hidden board — see LibraryStore.isHidden.)
    var isHidden: Bool = false
    /// The normal boards the pin was on when it was hidden; "Unhide" puts it back on them.
    var boardsBeforeHiding: [UUID] = []
    /// Video pins: whether the video has a sound track (nil = not checked yet).
    var hasAudio: Bool? = nil
    /// The person typed or chose this title in the app; the AI never replaces it.
    var titleEditedByUser: Bool = false
    /// The title the AI wrote last (nil = never).
    var lastAITitle: String? = nil
    /// The AI's last rename, for Undo.
    var titleUndo: TitleUndo? = nil
    /// Video pins: the poster was checked for being (nearly) black.
    var posterChecked: Bool = false
    /// Goes up whenever the picture file itself is rewritten (a rotation, a flip, a crop, a new
    /// video poster, a link preview fetched again or dropped — and when a link is pointed at
    /// another page), so every view showing it loads it again (the file name stays the same).
    /// iCloud takes a picture's details from the device with the higher revision (see
    /// `takePictureDetails(from:)`).
    var pictureRevision: Int = 0

    // What a link was read as (see `LinkFlavor`). Text pins and pins that never came from a link
    // leave all of these empty. Link pins keep an article's text (or a video's description) in
    // `textBody`; `aiDescription` stays the short description shown under the title.
    /// What the link turned out to be (nil: never read fully, or a plain link).
    var linkFlavor: LinkFlavor? = nil
    /// An article's writer, a video's channel, a Pinterest pin's creator.
    var author: String? = nil
    /// When the article, video or pin was published (as the page said).
    var publishedAt: Date? = nil
    /// The site's own name ("The Verge", "YouTube"), when the page said it.
    var siteName: String? = nil
    /// The page a pin points on to besides its own: a Pinterest pin's destination link, an
    /// article's canonical address when it differs from `linkURL`.
    var linkedURL: String? = nil
    /// A video's top comments (kept when the link was read with a YouTube API key).
    var comments: [PinComment] = []
    /// A video's view count, as the page or YouTube's service said (nil: unknown).
    var viewCount: Int? = nil

    // Storage (Settings › iCloud & storage). Pictures and videos only.
    /// The full-size original's file name inside the originals folder (nil: no original was kept
    /// — the copy in the library is the only one).
    var originalName: String? = nil
    /// The original's size in bytes, when one was kept (for the storage read-out).
    var originalBytes: Int? = nil
    /// Videos: the quality the copy on this device was converted to (nil: kept as imported).
    var videoTier: VideoQuality? = nil
    /// Kept off the Home page — the Pins tab's All and Unsorted ("Keep off Home page"): it still
    /// shows on its boards, in search, in smart boards and in Settings › Pins & boards › Home page.
    /// Softer than hiding. (The stored name still says "out of All", so libraries and iCloud sync
    /// made before the rename keep working.)
    /// (A pin is also kept out when it is on a board that keeps its pins out — see
    /// `LibraryStore.isKeptOutOfAll`.)
    var keptOutOfAll: Bool = false
    /// Articles: the passages marked while reading (see `TextHighlight`). They go with the text:
    /// pointing the link at another page clears them with it (`clearReading`).
    var highlights: [TextHighlight] = []
    /// A quote saved as a pin from an article ("Save as pin" on a highlight): the article pin it
    /// was taken from, so its page can lead back to the article. nil for every other pin.
    var quotedFromID: UUID? = nil
    /// Videos: what was said in the video, written down by the on-device speech recogniser
    /// (VideoTranscripts.swift). It is also put into the note, where the person reads it; this copy
    /// is what search and the AI use, and what tells that the note already has it.
    var transcript: String? = nil
    /// Videos: the sound was listened to for speech already (a transcript was made, or there was
    /// nothing to write down, or the language isn't supported, or the recogniser failed on it), so it
    /// isn't tried again by itself — only Settings' "Transcribe existing videos" tries it again.
    var transcriptChecked: Bool = false

    var aspectRatio: CGFloat { CGFloat(max(width, 1) / max(height, 1)) }
    var isText: Bool { kind == .text }
    var isVideo: Bool { kind == .video }
    var isLink: Bool { kind == .link }
    /// Pictures and videos have image files (a video's is its poster frame), and
    /// so do links with a stored preview; text pins don't.
    var hasImageFile: Bool {
        switch kind {
        case .image, .video: return true
        case .text: return false
        case .link: return hasPreview
        }
    }
    /// "example.com" for a link pin.
    var linkHost: String? {
        guard let linkURL else { return nil }
        return Pin.host(ofLink: linkURL)
    }
    /// "example.com" for "https://www.example.com/page" (nil when it has no host).
    static func host(ofLink link: String) -> String? {
        guard let host = URL(string: link)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    var videoFileName: String { "\(id.uuidString).\(videoExtension ?? "mov")" }
    var imageFileName: String { "\(id.uuidString).jpg" }
    var thumbFileName: String { "\(id.uuidString)-thumb.jpg" }
    var printFileName: String { "\(id.uuidString).fp" }
    var exifFileName: String { "\(id.uuidString).exif.plist" }
    var isDeleted: Bool { deletedAt != nil }
    var isUnsorted: Bool { boardIDs.isEmpty }
    func isOn(_ boardID: UUID) -> Bool { boardIDs.contains(boardID) }
}

// Custom decoding so a library saved by an older version of the app (with
// fewer fields, or a single `boardID`) still loads. Every field falls back to
// its default.
extension Pin: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, textBody, videoExtension, duration, linkURL, hasPreview, updatedAt
        case title, titleIsAuto, note, tags, aiTags, colorTags, ocrTags, ocrText, aiDescription, aiSearchHint
        case width, height, boardID, boardIDs, createdAt, needsAnalysis, hasFeaturePrint, aiSkipped
        case sourceURL, credit, deletedAt, dhash, duplicateOfID, notDuplicateOf, placementReason
        case capturedAt, cameraModel, latitude, longitude, fileKeywords, fileCaption
        case isHidden, boardsBeforeHiding, hasAudio
        case titleEditedByUser, lastAITitle, titleUndo, posterChecked, pictureRevision
        case linkFlavor, author, publishedAt, siteName, linkedURL, comments, viewCount
        case originalName, originalBytes, videoTier, keptOutOfAll, highlights, quotedFromID
        case transcript, transcriptChecked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = (try? c.decodeIfPresent(PinKind.self, forKey: .kind)) ?? .image
        textBody = (try? c.decodeIfPresent(String.self, forKey: .textBody)) ?? ""
        videoExtension = (try? c.decodeIfPresent(String.self, forKey: .videoExtension)) ?? nil
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? nil
        linkURL = (try? c.decodeIfPresent(String.self, forKey: .linkURL)) ?? nil
        hasPreview = (try? c.decodeIfPresent(Bool.self, forKey: .hasPreview)) ?? false
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        titleIsAuto = (try? c.decodeIfPresent(Bool.self, forKey: .titleIsAuto)) ?? false
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        aiTags = (try? c.decodeIfPresent([TagScore].self, forKey: .aiTags)) ?? []
        colorTags = (try? c.decodeIfPresent([String].self, forKey: .colorTags)) ?? []
        ocrTags = (try? c.decodeIfPresent([String].self, forKey: .ocrTags)) ?? []
        ocrText = (try? c.decodeIfPresent(String.self, forKey: .ocrText)) ?? ""
        aiDescription = (try? c.decodeIfPresent(String.self, forKey: .aiDescription)) ?? ""
        aiSearchHint = (try? c.decodeIfPresent(String.self, forKey: .aiSearchHint)) ?? nil
        width = (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? 1
        height = (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? 1
        if let many = (try? c.decodeIfPresent([UUID].self, forKey: .boardIDs)) ?? nil {
            boardIDs = many
        } else if let single = (try? c.decodeIfPresent(UUID.self, forKey: .boardID)) ?? nil {
            boardIDs = [single]
        } else {
            boardIDs = []
        }
        // Dates: ISO text or an old file's plain number (see `StoredDate`).
        createdAt = c.flexibleDate(forKey: .createdAt) ?? Date()
        updatedAt = c.flexibleDate(forKey: .updatedAt) ?? createdAt
        needsAnalysis = (try? c.decodeIfPresent(Bool.self, forKey: .needsAnalysis)) ?? true
        hasFeaturePrint = (try? c.decodeIfPresent(Bool.self, forKey: .hasFeaturePrint)) ?? false
        aiSkipped = (try? c.decodeIfPresent(Bool.self, forKey: .aiSkipped)) ?? false
        sourceURL = (try? c.decodeIfPresent(String.self, forKey: .sourceURL)) ?? nil
        credit = (try? c.decodeIfPresent(String.self, forKey: .credit)) ?? nil
        deletedAt = c.flexibleDate(forKey: .deletedAt)
        dhash = Pin.decodeHash(from: c)
        duplicateOfID = (try? c.decodeIfPresent(UUID.self, forKey: .duplicateOfID)) ?? nil
        notDuplicateOf = (try? c.decodeIfPresent([UUID].self, forKey: .notDuplicateOf)) ?? []
        placementReason = (try? c.decodeIfPresent(String.self, forKey: .placementReason)) ?? nil
        capturedAt = c.flexibleDate(forKey: .capturedAt)
        cameraModel = (try? c.decodeIfPresent(String.self, forKey: .cameraModel)) ?? nil
        latitude = (try? c.decodeIfPresent(Double.self, forKey: .latitude)) ?? nil
        longitude = (try? c.decodeIfPresent(Double.self, forKey: .longitude)) ?? nil
        fileKeywords = (try? c.decodeIfPresent([String].self, forKey: .fileKeywords)) ?? []
        fileCaption = (try? c.decodeIfPresent(String.self, forKey: .fileCaption)) ?? nil
        isHidden = (try? c.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false
        boardsBeforeHiding = (try? c.decodeIfPresent([UUID].self, forKey: .boardsBeforeHiding)) ?? []
        hasAudio = (try? c.decodeIfPresent(Bool.self, forKey: .hasAudio)) ?? nil
        if c.contains(.titleEditedByUser) {
            titleEditedByUser = (try? c.decodeIfPresent(Bool.self, forKey: .titleEditedByUser)) ?? false
            lastAITitle = (try? c.decodeIfPresent(String.self, forKey: .lastAITitle)) ?? nil
        } else {
            // Saved before titles knew who wrote them: only a title the AI demonstrably wrote
            // stays the AI's; every other title counts as the person's and is never replaced.
            let named = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            titleEditedByUser = named && !titleIsAuto
            lastAITitle = (named && titleIsAuto) ? title : nil
        }
        titleUndo = (try? c.decodeIfPresent(TitleUndo.self, forKey: .titleUndo)) ?? nil
        posterChecked = (try? c.decodeIfPresent(Bool.self, forKey: .posterChecked)) ?? false
        pictureRevision = (try? c.decodeIfPresent(Int.self, forKey: .pictureRevision)) ?? 0
        linkFlavor = (try? c.decodeIfPresent(LinkFlavor.self, forKey: .linkFlavor)) ?? nil
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? nil
        publishedAt = c.flexibleDate(forKey: .publishedAt)
        siteName = (try? c.decodeIfPresent(String.self, forKey: .siteName)) ?? nil
        linkedURL = (try? c.decodeIfPresent(String.self, forKey: .linkedURL)) ?? nil
        comments = (try? c.decodeIfPresent([PinComment].self, forKey: .comments)) ?? []
        viewCount = (try? c.decodeIfPresent(Int.self, forKey: .viewCount)) ?? nil
        originalName = (try? c.decodeIfPresent(String.self, forKey: .originalName)) ?? nil
        originalBytes = (try? c.decodeIfPresent(Int.self, forKey: .originalBytes)) ?? nil
        videoTier = (try? c.decodeIfPresent(VideoQuality.self, forKey: .videoTier)) ?? nil
        keptOutOfAll = (try? c.decodeIfPresent(Bool.self, forKey: .keptOutOfAll)) ?? false
        highlights = (try? c.decodeIfPresent([TextHighlight].self, forKey: .highlights)) ?? []
        quotedFromID = (try? c.decodeIfPresent(UUID.self, forKey: .quotedFromID)) ?? nil
        transcript = (try? c.decodeIfPresent(String.self, forKey: .transcript)) ?? nil
        transcriptChecked = (try? c.decodeIfPresent(Bool.self, forKey: .transcriptChecked)) ?? false
    }

    /// Accepts the hex text this version writes and the plain number older files used.
    private static func decodeHash(from c: KeyedDecodingContainer<CodingKeys>) -> UInt64? {
        if let text = (try? c.decodeIfPresent(String.self, forKey: .dhash)) ?? nil {
            return UInt64(text, radix: 16)
        }
        if let number = (try? c.decodeIfPresent(UInt64.self, forKey: .dhash)) ?? nil {
            return number
        }
        // Some decoders hand back big numbers as doubles; keep what precision there is.
        if let double = (try? c.decodeIfPresent(Double.self, forKey: .dhash)) ?? nil, double >= 0, double < 1.8446744e19 {
            return UInt64(double)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        if kind != .image { try c.encode(kind, forKey: .kind) }
        if !textBody.isEmpty { try c.encode(textBody, forKey: .textBody) }
        try c.encodeIfPresent(videoExtension, forKey: .videoExtension)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(linkURL, forKey: .linkURL)
        if hasPreview { try c.encode(hasPreview, forKey: .hasPreview) }
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(title, forKey: .title)
        try c.encode(titleIsAuto, forKey: .titleIsAuto)
        try c.encode(note, forKey: .note)
        try c.encode(tags, forKey: .tags)
        try c.encode(aiTags, forKey: .aiTags)
        try c.encode(colorTags, forKey: .colorTags)
        try c.encode(ocrTags, forKey: .ocrTags)
        try c.encode(ocrText, forKey: .ocrText)
        try c.encode(aiDescription, forKey: .aiDescription)
        try c.encodeIfPresent(aiSearchHint, forKey: .aiSearchHint)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(boardIDs, forKey: .boardIDs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(needsAnalysis, forKey: .needsAnalysis)
        try c.encode(hasFeaturePrint, forKey: .hasFeaturePrint)
        if aiSkipped { try c.encode(aiSkipped, forKey: .aiSkipped) }
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encodeIfPresent(credit, forKey: .credit)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        // Stored as hex text: JSON decoders on older systems mishandle 64-bit numbers.
        try c.encodeIfPresent(dhash.map { String($0, radix: 16) }, forKey: .dhash)
        try c.encodeIfPresent(duplicateOfID, forKey: .duplicateOfID)
        if !notDuplicateOf.isEmpty { try c.encode(notDuplicateOf, forKey: .notDuplicateOf) }
        try c.encodeIfPresent(placementReason, forKey: .placementReason)
        try c.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try c.encodeIfPresent(cameraModel, forKey: .cameraModel)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encode(fileKeywords, forKey: .fileKeywords)
        try c.encodeIfPresent(fileCaption, forKey: .fileCaption)
        if isHidden { try c.encode(isHidden, forKey: .isHidden) }
        if !boardsBeforeHiding.isEmpty { try c.encode(boardsBeforeHiding, forKey: .boardsBeforeHiding) }
        try c.encodeIfPresent(hasAudio, forKey: .hasAudio)
        // Always written: its presence tells a newer file from one saved before round 8.
        try c.encode(titleEditedByUser, forKey: .titleEditedByUser)
        try c.encodeIfPresent(lastAITitle, forKey: .lastAITitle)
        try c.encodeIfPresent(titleUndo, forKey: .titleUndo)
        if posterChecked { try c.encode(posterChecked, forKey: .posterChecked) }
        if pictureRevision > 0 { try c.encode(pictureRevision, forKey: .pictureRevision) }
        try c.encodeIfPresent(linkFlavor, forKey: .linkFlavor)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try c.encodeIfPresent(siteName, forKey: .siteName)
        try c.encodeIfPresent(linkedURL, forKey: .linkedURL)
        if !comments.isEmpty { try c.encode(comments, forKey: .comments) }
        try c.encodeIfPresent(viewCount, forKey: .viewCount)
        try c.encodeIfPresent(originalName, forKey: .originalName)
        try c.encodeIfPresent(originalBytes, forKey: .originalBytes)
        try c.encodeIfPresent(videoTier, forKey: .videoTier)
        if keptOutOfAll { try c.encode(keptOutOfAll, forKey: .keptOutOfAll) }
        if !highlights.isEmpty { try c.encode(highlights, forKey: .highlights) }
        try c.encodeIfPresent(quotedFromID, forKey: .quotedFromID)
        try c.encodeIfPresent(transcript, forKey: .transcript)
        if transcriptChecked { try c.encode(transcriptChecked, forKey: .transcriptChecked) }
    }
}

// Who wrote a pin's title. Every title change goes through one of the three setters.
extension Pin {
    /// The title and its flags as they are now.
    var titleState: TitleState {
        TitleState(title: title, isAuto: titleIsAuto, editedByUser: titleEditedByUser, lastAITitle: lastAITitle)
    }

    /// The AI may write this title: it is empty (after trimming), or it is still exactly what the AI
    /// wrote (`titleIsAuto && lastAITitle == title`) and nobody edited it (`!titleEditedByUser`).
    var titleIsAIOwned: Bool {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return titleIsAuto && lastAITitle == title && !titleEditedByUser
    }

    /// The AI's last rename can still be undone (the pin still has the title the AI wrote).
    var canUndoAITitle: Bool {
        guard let titleUndo else { return false }
        return titleUndo.aiTitle == title
    }

    /// The person typed or chose this title.
    mutating func setUserTitle(_ newTitle: String) {
        title = newTitle
        titleIsAuto = false
        titleEditedByUser = true
        titleUndo = nil
    }

    /// A title from a file name, photo metadata, a web page or a link preview (neither typed nor AI).
    mutating func setImportedTitle(_ newTitle: String) {
        title = newTitle
        titleIsAuto = false
        titleEditedByUser = false
        titleUndo = nil
    }

    /// The AI (re)named the pin. `before` is the title state from when this naming began (not an
    /// in-between title), so Undo goes back to that. An empty title is ignored. The first title of
    /// an untitled pin can't be undone (there is nothing to go back to).
    mutating func setAITitle(_ newTitle: String, replacing before: TitleState, runID: UUID? = nil) {
        let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        title = cleaned
        titleIsAuto = true
        titleEditedByUser = false
        lastAITitle = cleaned
        if before.title == cleaned {
            return   // nothing new to undo: titleUndo stays as it was
        }
        if before.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            titleUndo = nil
        } else if let kept = titleUndo, kept.aiTitle == before.title, !kept.previous.isAuto,
                  !kept.previous.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The AI renames its own rename of a name it did not write (one the person typed,
            // or one from a file): Undo still goes back to that name — as part of this run,
            // or of the run that replaced it first. A name the person wrote is never lost.
            titleUndo = TitleUndo(previous: kept.previous, aiTitle: cleaned, runID: runID ?? kept.runID, date: Date())
        } else {
            titleUndo = TitleUndo(previous: before, aiTitle: cleaned, runID: runID, date: Date())
        }
    }

    /// Puts back the title from before the AI's last rename (with all its flags), if the pin still
    /// has the title the AI wrote. The undo record is cleared either way. Returns whether a title
    /// was restored.
    @discardableResult
    mutating func undoAITitle() -> Bool {
        guard let undo = titleUndo else { return false }
        titleUndo = nil
        guard undo.aiTitle == title else { return false }
        title = undo.previous.title
        titleIsAuto = undo.previous.isAuto
        titleEditedByUser = undo.previous.editedByUser
        lastAITitle = undo.previous.lastAITitle
        return true
    }
}

// Which of a pin's details belong to its picture. When two devices merge a pin (iCloud), these
// come from the device whose picture is newer (the higher `pictureRevision`); everything else
// comes from the newer record (see `CloudSync.mergedPin`). So a picture cropped on one device is
// never undone because the other device changed, say, a tag before the two synced.
extension Pin {
    /// Takes over everything `other` says about its picture:
    ///   • the picture itself: its revision, its size, whether a link has a preview picture;
    ///   • what is kept on disk with it: whether it has a fingerprint (for "More like this");
    ///   • what was worked out from it: its look-alike hash and look-alike, the AI's tags (a link's
    ///     also carry its page's words), its colours, the text read in it, the cloud model's
    ///     description and search words, whether the AI still has to look at it, and whether a
    ///     video's poster was checked for being black.
    /// For a link that points at another page than `other`, `other`'s address comes along too:
    /// a preview picture shows its page. (The same page with other tracking keeps its own address.)
    /// Everything the person decides stays as it is: title, note, their own tags, boards, hiding,
    /// "Recently deleted", and the look-alikes they said are different ("Keep both" — such a
    /// look-alike is never taken over).
    mutating func takePictureDetails(from other: Pin) {
        pictureRevision = other.pictureRevision
        width = other.width
        height = other.height
        hasPreview = other.hasPreview
        hasFeaturePrint = other.hasFeaturePrint
        dhash = other.dhash
        duplicateOfID = other.duplicateOfID
        needsAnalysis = other.needsAnalysis
        aiSkipped = other.aiSkipped
        aiTags = other.aiTags
        colorTags = other.colorTags
        ocrText = other.ocrText
        ocrTags = other.ocrTags
        aiDescription = other.aiDescription
        aiSearchHint = other.aiSearchHint
        posterChecked = other.posterChecked
        if isLink, let address = other.linkURL, !Pin.samePage(linkURL, address) {
            linkURL = address
            takeReading(from: other)   // what the page was read as belongs to the address
        }
        if isLink, other.kind == .image, other.linkURL == nil {
            // The other device turned this link into its picture ("Read link again", SmartLinks.swift):
            // the picture pin it made comes along, not just the picture.
            kind = .image
            sourceURL = other.sourceURL
            linkURL = nil
            duration = nil
            takeReading(from: other)
        }
        if let twin = duplicateOfID, notDuplicateOf.contains(twin) { duplicateOfID = nil }
    }

    /// Takes over what `other`'s link was read as (SmartLinks.swift): its text, writer, date, site,
    /// linked page, comments and view count. Used when the address changes hands too.
    mutating func takeReading(from other: Pin) {
        textBody = other.textBody
        linkFlavor = other.linkFlavor
        author = other.author
        publishedAt = other.publishedAt
        siteName = other.siteName
        linkedURL = other.linkedURL
        comments = other.comments
        viewCount = other.viewCount
        highlights = other.highlights   // the marks belong to the text they were made in
        if other.isLink { duration = other.duration }
    }

    /// Forgets what the link was read as (the address changed: the new page is read afresh).
    mutating func clearReading() {
        textBody = ""
        linkFlavor = nil
        author = nil
        publishedAt = nil
        siteName = nil
        linkedURL = nil
        comments = []
        viewCount = nil
        duration = nil
        highlights = []
    }

    /// Two link addresses lead to the same page (only their tracking differs, see `LibraryStore.pageKey`).
    static func samePage(_ first: String?, _ second: String?) -> Bool {
        LibraryStore.pageKey(first ?? "") == LibraryStore.pageKey(second ?? "")
    }
}

/// A board. Boards can be nested inside other boards (parentID) to make
/// categories such as  Travel › Beaches › Sunsets.
struct Board: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var coverPinID: UUID? = nil        // chosen cover; otherwise the newest pin
    var sortIndex: Int = 0             // manual order among siblings
    var isSecret: Bool = false         // lives in the Hidden folder; sub-boards follow
    /// Its pins (and its sub-boards' pins) stay out of the Pins tab's All feed ("Keep off Home page").
    var keepsPinsOutOfAll: Bool = false
    var isFavorite: Bool = false       // shown at the top of the Boards page
    var details: String = ""           // the board's description (UI: "Description")
    var lastEditedAt: Date? = nil      // content or description last changed (nil = before round 8)
    var lastAddedAt: Date? = nil       // a pin was last put on this board itself (nil = never / before round 8)
    var openCount: Int = 0             // how often its page was opened (on this device)
    var paletteHex: [String]? = nil    // cached palette, "#RRGGBB" uppercase, most prominent first
    var paletteMadeAt: Date? = nil     // when paletteHex was made
}

extension Board: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, parentID, createdAt, updatedAt, coverPinID, sortIndex, isSecret
        case isFavorite, details, lastEditedAt, lastAddedAt, openCount, paletteHex, paletteMadeAt
        case keepsPinsOutOfAll
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Board"
        parentID = (try? c.decodeIfPresent(UUID.self, forKey: .parentID)) ?? nil
        createdAt = c.flexibleDate(forKey: .createdAt) ?? Date()
        updatedAt = c.flexibleDate(forKey: .updatedAt) ?? createdAt
        coverPinID = (try? c.decodeIfPresent(UUID.self, forKey: .coverPinID)) ?? nil
        sortIndex = (try? c.decodeIfPresent(Int.self, forKey: .sortIndex)) ?? 0
        isSecret = (try? c.decodeIfPresent(Bool.self, forKey: .isSecret)) ?? false
        isFavorite = (try? c.decodeIfPresent(Bool.self, forKey: .isFavorite)) ?? false
        keepsPinsOutOfAll = (try? c.decodeIfPresent(Bool.self, forKey: .keepsPinsOutOfAll)) ?? false
        details = (try? c.decodeIfPresent(String.self, forKey: .details)) ?? ""
        lastEditedAt = c.flexibleDate(forKey: .lastEditedAt)
        lastAddedAt = c.flexibleDate(forKey: .lastAddedAt)
        openCount = max(0, (try? c.decodeIfPresent(Int.self, forKey: .openCount)) ?? 0)
        paletteHex = (try? c.decodeIfPresent([String].self, forKey: .paletteHex)) ?? nil
        paletteMadeAt = c.flexibleDate(forKey: .paletteMadeAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(coverPinID, forKey: .coverPinID)
        try c.encode(sortIndex, forKey: .sortIndex)
        if isSecret { try c.encode(isSecret, forKey: .isSecret) }
        if isFavorite { try c.encode(isFavorite, forKey: .isFavorite) }
        if keepsPinsOutOfAll { try c.encode(keepsPinsOutOfAll, forKey: .keepsPinsOutOfAll) }
        if !details.isEmpty { try c.encode(details, forKey: .details) }
        try c.encodeIfPresent(lastEditedAt, forKey: .lastEditedAt)
        try c.encodeIfPresent(lastAddedAt, forKey: .lastAddedAt)
        if openCount != 0 { try c.encode(openCount, forKey: .openCount) }
        try c.encodeIfPresent(paletteHex, forKey: .paletteHex)
        try c.encodeIfPresent(paletteMadeAt, forKey: .paletteMadeAt)
    }
}

/// How boards are ordered on the Boards page, inside boards and in board pickers.
/// Favorites always come first within any list; this orders each group.
enum BoardSort: String, CaseIterable, Identifiable, Sendable {
    case custom, name, recentlyEdited, recentlyAdded
    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom: return "Custom order"
        case .name: return "Name (A–Z)"
        case .recentlyEdited: return "Recently edited"
        case .recentlyAdded: return "Recently added to"
        }
    }

    var icon: String {
        switch self {
        case .custom: return "hand.point.up.left"
        case .name: return "textformat"
        case .recentlyEdited: return "pencil"
        case .recentlyAdded: return "tray.and.arrow.down"
        }
    }
}

/// One "AI sorting → naming" run: what it did (told when it ends), and — when it renamed at
/// least one pin — what "Undo last AI naming" puts back.
struct NamingRun: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var hidden: Bool      // the side of the library it ran on
    var renamed: Int      // how many pins it renamed that Undo can put back (not first titles of untitled pins)
    /// Pins that kept their name: nothing different from it was found.
    var kept: Int = 0
    /// Untitled pins that got their first name (Undo has nothing to put back for them).
    var firstNames: Int = 0

    /// Every pin whose name changed: renamed, or named for the first time.
    var changed: Int { renamed + firstNames }
}

// Read by hand so a run saved before `kept` and `firstNames` existed still loads (they are 0 then).
extension NamingRun {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        hidden = try c.decode(Bool.self, forKey: .hidden)
        renamed = try c.decode(Int.self, forKey: .renamed)
        kept = (try? c.decodeIfPresent(Int.self, forKey: .kept)) ?? 0
        firstNames = (try? c.decodeIfPresent(Int.self, forKey: .firstNames)) ?? 0
    }
}

/// A board that fills itself from a saved search.
struct SmartBoard: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var query: String = ""
    var filters: SearchFilters = SearchFilters()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortIndex: Int = 0
    var excludedPinIDs: [UUID] = []    // pins you hid from this smart board ("Reset" clears them)
    var isHidden: Bool = false         // lives in the Hidden section and shows hidden pins

    private enum CodingKeys: String, CodingKey {
        case id, name, query, filters, createdAt, updatedAt, sortIndex, excludedPinIDs, isHidden
    }

    init(name: String, query: String = "", filters: SearchFilters = SearchFilters(), isHidden: Bool = false) {
        self.name = name
        self.query = query
        self.filters = filters
        self.isHidden = isHidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Smart board"
        query = (try? c.decodeIfPresent(String.self, forKey: .query)) ?? ""
        filters = (try? c.decodeIfPresent(SearchFilters.self, forKey: .filters)) ?? SearchFilters()
        createdAt = c.flexibleDate(forKey: .createdAt) ?? Date()
        updatedAt = c.flexibleDate(forKey: .updatedAt) ?? createdAt
        sortIndex = (try? c.decodeIfPresent(Int.self, forKey: .sortIndex)) ?? 0
        excludedPinIDs = (try? c.decodeIfPresent([UUID].self, forKey: .excludedPinIDs)) ?? []
        isHidden = (try? c.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(query, forKey: .query)
        try c.encode(filters, forKey: .filters)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(sortIndex, forKey: .sortIndex)
        if !excludedPinIDs.isEmpty { try c.encode(excludedPinIDs, forKey: .excludedPinIDs) }
        if isHidden { try c.encode(isHidden, forKey: .isHidden) }
    }
}

/// One library among several ("Personal", "Work"…).
struct Profile: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
}

/// Everything in library.json.
struct LibraryDocument: Codable {
    static let currentSchema = 7

    var schemaVersion: Int = LibraryDocument.currentSchema
    var pins: [Pin] = []
    var boards: [Board] = []
    var smartBoards: [SmartBoard] = []
    /// Pins erased for good, with when — so another device syncing this library
    /// erases them too instead of bringing them back.
    var erased: [UUID: Date] = [:]
    var savedAt: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pins, boards, smartBoards, erased, savedAt
    }

    init() {}

    init(pins: [Pin], boards: [Board], smartBoards: [SmartBoard], erased: [UUID: Date]) {
        self.pins = pins
        self.boards = boards
        self.smartBoards = smartBoards
        self.erased = erased
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        pins = (try? c.decodeIfPresent([Pin].self, forKey: .pins)) ?? []
        boards = (try? c.decodeIfPresent([Board].self, forKey: .boards)) ?? []
        smartBoards = (try? c.decodeIfPresent([SmartBoard].self, forKey: .smartBoards)) ?? []
        if let map = c.flexibleDateMap(forKey: .erased) {
            var result: [UUID: Date] = [:]
            for (key, date) in map { if let id = UUID(uuidString: key) { result[id] = date } }
            erased = result
        }
        savedAt = c.flexibleDate(forKey: .savedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(pins, forKey: .pins)
        try c.encode(boards, forKey: .boards)
        try c.encode(smartBoards, forKey: .smartBoards)
        var map: [String: Date] = [:]
        for (id, date) in erased { map[id.uuidString] = date }
        try c.encode(map, forKey: .erased)
        try c.encode(savedAt, forKey: .savedAt)
    }
}

// MARK: - Dates in older library files

/// library.json stores dates as ISO 8601 text. Very old files stored them as plain numbers:
/// Swift's own default, seconds since 1 January 2001 (`JSONEncoder`'s `.deferredToDate`).
/// Every date field is read with `flexibleDate(forKey:)` below, which tries the text first and
/// then the number — so an old file keeps its dates, instead of every pin quietly becoming
/// "added now" and every pin in Recently Deleted coming back.
enum StoredDate {
    /// A date stored as a number. Old PinBoard files counted from 2001; a number that would then
    /// land more than a year in the future can only have counted from 1970 (as some tools write).
    ///
    /// The rule, written down: a number is read as seconds since 1 January 2001 unless that date
    /// would be over a year after `now`; only then is it read as seconds since 1970. So a number
    /// that was really counted from 1970 but names a date before about 1997 (the cut-off is 1970
    /// plus the time from 2001 to a year after `now`: the end of September 1996 when read in
    /// September 2026, one year later every year) is read as counted from 2001 — 31 years too
    /// late. It is left that way on purpose: PinBoard never wrote 1970-based numbers, and a pin,
    /// board or tombstone dated before 1997 does not happen in practice.
    static func date(fromNumber seconds: Double, now: Date = Date()) -> Date {
        let since2001 = Date(timeIntervalSinceReferenceDate: seconds)
        let latestPlausible = now.addingTimeInterval(365 * 86_400)
        if since2001 > latestPlausible { return Date(timeIntervalSince1970: seconds) }
        return since2001
    }
}

extension KeyedDecodingContainer {
    /// The date at `key`, stored as ISO text or as a number (see `StoredDate`); nil when the
    /// key is missing or holds neither.
    func flexibleDate(forKey key: Key) -> Date? {
        if let date = (try? decodeIfPresent(Date.self, forKey: key)) ?? nil { return date }
        guard let number = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil else { return nil }
        return StoredDate.date(fromNumber: number)
    }

    /// A map of id text → date (`LibraryDocument.erased`), its dates stored either way.
    func flexibleDateMap(forKey key: Key) -> [String: Date]? {
        if let map = (try? decodeIfPresent([String: Date].self, forKey: key)) ?? nil { return map }
        guard let numbers = (try? decodeIfPresent([String: Double].self, forKey: key)) ?? nil else { return nil }
        var result: [String: Date] = [:]
        for (id, seconds) in numbers { result[id] = StoredDate.date(fromNumber: seconds) }
        return result
    }
}

struct BoardSuggestion: Identifiable, Hashable {
    var board: Board
    var score: Double          // 0…1
    var reason: String         // "board name matches its tags"
    var evidence: [String]     // the words that made the match, for display
    var id: UUID { board.id }
}

struct BoardRow: Identifiable {
    var board: Board
    var depth: Int
    var id: UUID { board.id }
}

/// Typeface choices for text pins.
enum TextFontChoice: String, CaseIterable, Identifiable, Sendable {
    case system, serif, rounded, monospaced
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Standard"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

/// How text pins look (from Settings → Text pins).
struct TextCardStyle: Equatable, Sendable {
    var font: TextFontChoice = .system
    var boardSize: Double = 15        // point size on the boards (at the standard text size)
    var pageSize: Double = 20         // point size on the pin's page (at the standard text size)
    var linesOnBoard: Int = 6         // how much of the text a card shows
    var showsTitleOnBoard: Bool = true
    var cardPadding: CGFloat = 14

    static let titleScale: Double = 1.12

    /// A size from Settings as it is drawn right now: it grows and shrinks with the text size
    /// the person chose in iOS (Dynamic Type), exactly like body text does. Both fonts below
    /// use it, so the measured height of a card always matches the drawn text.
    static func scaled(_ size: Double) -> Double {
        Double(UIFontMetrics(forTextStyle: .body).scaledValue(for: CGFloat(size)))
    }

    /// The font used for measuring (UIKit). `size` is the Settings size; it is scaled here.
    func uiFont(size: Double, weight: UIFont.Weight = .regular) -> UIFont {
        let points = CGFloat(TextCardStyle.scaled(size))
        let base = UIFont.systemFont(ofSize: points, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(font.uiDesign) {
            return UIFont(descriptor: descriptor, size: points)
        }
        return base
    }

    /// The font used for drawing (SwiftUI): the same scaled size as `uiFont`. Views using it
    /// read the environment's text size, so they are redrawn when it changes.
    func swiftFont(size: Double, weight: Font.Weight = .regular) -> Font {
        Font.system(size: TextCardStyle.scaled(size), weight: weight, design: font.design)
    }

    /// Measured heights, so a grid full of text cards is not re-measured on every
    /// layout pass (text measuring is the slow part). Layout happens on the main thread.
    @MainActor private static var heightCache: [String: CGFloat] = [:]

    /// The exact height of a text card at the given width, so the grid can lay
    /// it out before it is drawn.
    @MainActor
    func cardHeight(title: String, body: String, width: CGFloat) -> CGFloat {
        // The scaled size carries the current text size, so after the person changes the
        // text size every card is measured again instead of keeping its old height.
        let textSize = TextCardStyle.scaled(boardSize)
        let key = "\(font.rawValue)|\(textSize)|\(linesOnBoard)|\(showsTitleOnBoard)|\(Int(width))|\(title)|\(body.hashValue)|\(body.count)"
        if let known = TextCardStyle.heightCache[key] { return known }
        let inner = max(10, width - cardPadding * 2)
        var height = cardPadding * 2
        if showsTitleOnBoard, !title.isEmpty {
            let titleFont = uiFont(size: boardSize * TextCardStyle.titleScale, weight: .semibold)
            height += TextCardStyle.measure(title, font: titleFont, width: inner, maxLines: 2) + 6
        }
        let bodyFont = uiFont(size: boardSize)
        let bodyText = body.isEmpty ? " " : body
        height += TextCardStyle.measure(bodyText, font: bodyFont, width: inner, maxLines: linesOnBoard)
        let result = ceil(height)
        if TextCardStyle.heightCache.count > 4000 { TextCardStyle.heightCache = [:] }
        TextCardStyle.heightCache[key] = result
        return result
    }

    /// Height of `text` wrapped to `width`, capped at `maxLines` lines.
    static func measure(_ text: String, font: UIFont, width: CGFloat, maxLines: Int) -> CGFloat {
        let lineHeight = ceil(font.lineHeight)
        let cap = lineHeight * CGFloat(max(1, maxLines))
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: font],
                                                     context: nil)
        return min(cap, max(lineHeight, ceil(bounds.height)))
    }
}

/// How a feed (the Pins tab's All, Hidden › All, board pages) is ordered — see FeedOrder.
enum PinSortMode: String, CaseIterable, Sendable {
    case shuffled, newestFirst, oldestFirst
}

/// Optional narrowing for the Search tab (and the rule of a smart board).
struct SearchFilters: Equatable, Hashable, Sendable, Codable {
    enum DateRange: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, week, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any time"
            case .week: return "Past week"
            case .month: return "Past month"
            case .year: return "Past year"
            }
        }
    }
    enum Sort: String, CaseIterable, Identifiable, Sendable, Codable {
        case relevance, newest, oldest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .relevance: return "Best match"
            case .newest: return "Newest first"
            case .oldest: return "Oldest first"
            }
        }
    }
    /// How long a video is.
    enum DurationRange: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, under10, from10to30, from30to60, from1to5min, over5min
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any length"
            case .under10: return "Under 10 s"
            case .from10to30: return "10–30 s"
            case .from30to60: return "30–60 s"
            case .from1to5min: return "1–5 min"
            case .over5min: return "5+ min"
            }
        }
        /// Bucket edges: [0,10), [10,30), [30,60), [60,300), [300,∞). `.any` contains everything.
        func contains(_ seconds: Double) -> Bool {
            switch self {
            case .any: return true
            case .under10: return seconds >= 0 && seconds < 10
            case .from10to30: return seconds >= 10 && seconds < 30
            case .from30to60: return seconds >= 30 && seconds < 60
            case .from1to5min: return seconds >= 60 && seconds < 300
            case .over5min: return seconds >= 300
            }
        }
    }
    /// Whether a video has a sound track.
    enum SoundFilter: String, CaseIterable, Identifiable, Sendable, Codable {
        case any, withSound, withoutSound
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any sound"
            case .withSound: return "With sound"
            case .withoutSound: return "Without sound"
            }
        }
    }
    var boardID: UUID? = nil            // restrict to a board (and its sub-boards)
    var boardScopeIDs: Set<UUID> = []   // resolved by the store: boardID + descendants (not saved)
    var unsortedOnly = false
    var untaggedOnly = false            // no tags of your own
    var withTextOnly = false            // has text read from the image
    var duplicatesOnly = false
    var dateRange: DateRange = .any
    var kinds: Set<PinKind> = []        // empty = every kind
    var sort: Sort = .relevance
    var duration: DurationRange = .any  // videos only, when set
    var sound: SoundFilter = .any       // videos only, when set

    var isActive: Bool {
        boardID != nil || unsortedOnly || untaggedOnly || withTextOnly || duplicatesOnly || dateRange != .any || !kinds.isEmpty
            || duration != .any || sound != .any
    }

    private enum CodingKeys: String, CodingKey {
        case boardID, unsortedOnly, untaggedOnly, withTextOnly, duplicatesOnly, dateRange, kinds, sort
        case duration, sound
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        boardID = (try? c.decodeIfPresent(UUID.self, forKey: .boardID)) ?? nil
        unsortedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .unsortedOnly)) ?? false
        untaggedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .untaggedOnly)) ?? false
        withTextOnly = (try? c.decodeIfPresent(Bool.self, forKey: .withTextOnly)) ?? false
        duplicatesOnly = (try? c.decodeIfPresent(Bool.self, forKey: .duplicatesOnly)) ?? false
        dateRange = (try? c.decodeIfPresent(DateRange.self, forKey: .dateRange)) ?? .any
        kinds = Set((try? c.decodeIfPresent([PinKind].self, forKey: .kinds)) ?? [])
        sort = (try? c.decodeIfPresent(Sort.self, forKey: .sort)) ?? .relevance
        duration = (try? c.decodeIfPresent(DurationRange.self, forKey: .duration)) ?? .any
        sound = (try? c.decodeIfPresent(SoundFilter.self, forKey: .sound)) ?? .any
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(boardID, forKey: .boardID)
        try c.encode(unsortedOnly, forKey: .unsortedOnly)
        try c.encode(untaggedOnly, forKey: .untaggedOnly)
        try c.encode(withTextOnly, forKey: .withTextOnly)
        try c.encode(duplicatesOnly, forKey: .duplicatesOnly)
        try c.encode(dateRange, forKey: .dateRange)
        try c.encode(Array(kinds).sorted { $0.rawValue < $1.rawValue }, forKey: .kinds)
        try c.encode(sort, forKey: .sort)
        try c.encode(duration, forKey: .duration)
        try c.encode(sound, forKey: .sound)
    }
}

struct SearchHit: Identifiable, Sendable {
    var pin: Pin
    var score: Double
    var matches: [String]
    var id: UUID { pin.id }
}

struct AnalysisProgress: Equatable {
    var done: Int
    var total: Int
}

/// The list a pin page was opened from, so swiping on the image can move to
/// the previous / next item of that list.
struct PinContext: Hashable {
    var ids: [UUID]

    static let none = PinContext(ids: [])

    /// Keeps the list a sensible size around the opened pin.
    init(ids: [UUID], around id: UUID? = nil, limit: Int = 400) {
        if ids.count <= limit || id == nil {
            self.ids = Array(ids.prefix(limit))
        } else if let id, let index = ids.firstIndex(of: id) {
            let start = max(0, index - limit / 2)
            let end = min(ids.count, start + limit)
            self.ids = Array(ids[start..<end])
        } else {
            self.ids = Array(ids.prefix(limit))
        }
    }
}

/// Which part of the library a list covers: the normal library, or the Hidden section.
enum PinScope: Hashable, Sendable {
    case visible, hidden
}

/// Screens the Hidden section opens (its own Duplicates, Recently Deleted and Tags).
enum HiddenScreen: Hashable {
    case duplicates, recentlyDeleted, tags
}

/// Where navigation can go.
enum Route: Hashable {
    case pin(UUID, PinContext)
    case board(UUID)
    case smartBoard(UUID)
    case webImage(WebImage, [WebImage], boardIDs: [UUID], hidden: Bool)   // a web result, the feed it came from, the boards its feed saves to, and whether that feed is Hidden's
    case hidden                           // the Hidden section (behind the Face ID gate)
    case hiddenScreen(HiddenScreen)       // a screen inside the Hidden section
}

/// One item of Quick Look: a stored pin or a web result.
enum ViewerItem: Identifiable, Hashable {
    case pin(Pin)
    case web(WebImage)

    var id: String {
        switch self {
        case .pin(let pin): return "pin-\(pin.id.uuidString)"
        case .web(let image): return "web-\(image.id)"
        }
    }

    var title: String {
        switch self {
        case .pin(let pin): return pin.title
        case .web(let image): return image.title ?? ""
        }
    }
}

enum ImportError: Error {
    case unreadableImage
}

/// Metadata read from a photo file when it is imported.
struct FileMetadata: Sendable {
    var capturedAt: Date? = nil
    var cameraModel: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var keywords: [String] = []
    var caption: String? = nil
    var title: String? = nil
    /// The complete property dictionary, kept for export (as a plist).
    var propertiesPlist: Data? = nil
}

// MARK: - Image processing (resizing / thumbnails, memory-friendly)

enum ImageProcessor {
    struct Prepared: Sendable {
        var width: Double
        var height: Double
        var metadata: FileMetadata
    }

    /// Decodes `data` straight into a downsized CGImage (this also fixes the
    /// photo's rotation), without ever loading the full-size bitmap into memory.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegData(_ cgImage: CGImage, quality: CGFloat) -> Data? {
        UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }

    /// The picture turned by quarter turns (clockwise) and/or mirrored.
    static func transformed(_ image: CGImage, quarterTurns: Int, flipHorizontally: Bool) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 || flipHorizontally else { return image }
        let swapped = turns % 2 == 1
        let width = swapped ? image.height : image.width
        let height = swapped ? image.width : image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        if flipHorizontally { context.scaleBy(x: -1, y: 1) }
        context.rotate(by: -CGFloat(turns) * .pi / 2)   // Core Graphics turns the other way round
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }

    /// The part of the picture inside `unitRect` (see `pixelRect`).
    static func cropped(_ image: CGImage, to unitRect: CGRect) -> CGImage? {
        image.cropping(to: pixelRect(for: unitRect, width: image.width, height: image.height))
    }

    /// The pixels of a picture `width` × `height` that `unitRect` covers. `unitRect` is in parts of
    /// the picture's width and height (0…1, top-left origin, as the crop editor hands it over).
    /// The result stays inside the picture, covers at least 1% of each side (and one pixel), lies
    /// on whole pixels, and is never empty. A rectangle that isn't made of numbers means the whole
    /// picture.
    static func pixelRect(for unitRect: CGRect, width: Int, height: Int) -> CGRect {
        let across = pixelSpan(from: Double(unitRect.minX), to: Double(unitRect.maxX), length: max(width, 1))
        let down = pixelSpan(from: Double(unitRect.minY), to: Double(unitRect.maxY), length: max(height, 1))
        return CGRect(x: across.start, y: down.start, width: across.end - across.start, height: down.end - down.start)
    }

    /// One side of `pixelRect`: `from`…`to` (parts of the side, 0…1) as whole pixels of a side
    /// `length` pixels long — rounded outwards, kept inside, at least 1% and one pixel.
    private static func pixelSpan(from: Double, to: Double, length: Int) -> (start: Int, end: Int) {
        guard from.isFinite, to.isFinite else { return (0, length) }
        var low = min(max(min(from, to), 0), 1)
        var high = min(max(max(from, to), 0), 1)
        if high - low < 0.01 {
            high = min(low + 0.01, 1)
            low = high - 0.01
        }
        // (A hair of slack, so 0.25 × 400 is pixel 100 even when the sum comes out a little off.)
        let first = Int((low * Double(length) + 1e-9).rounded(.down))
        let last = Int((high * Double(length) - 1e-9).rounded(.up))
        let start = min(max(first, 0), length - 1)
        let end = min(max(last, start + 1), length)
        return (start, end)
    }

    /// The size in pixels of the picture file at `url`, read from its header (the picture itself
    /// is not decoded). nil when it can't be read.
    static func pixelSize(ofImageAt url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        return (width, height)
    }

    /// Reads the EXIF / IPTC / GPS information a photo file carries.
    static func readMetadata(_ data: Data) -> FileMetadata {
        var result = FileMetadata()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return result
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                result.capturedAt = formatter.date(from: stamp)
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let make = (tiff[kCGImagePropertyTIFFMake as String] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let model = (tiff[kCGImagePropertyTIFFModel as String] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !model.isEmpty {
                result.cameraModel = model.lowercased().hasPrefix(make.lowercased()) || make.isEmpty ? model : "\(make) \(model)"
            }
            if let description = tiff[kCGImagePropertyTIFFImageDescription as String] as? String,
               !description.trimmingCharacters(in: .whitespaces).isEmpty {
                result.caption = description.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
            result.latitude = latRef == "S" ? -latitude : latitude
            result.longitude = lonRef == "W" ? -longitude : longitude
        }
        if let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            if let keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String] {
                result.keywords = keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            }
            if let caption = iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String, !caption.isEmpty {
                result.caption = caption
            }
            if let name = iptc[kCGImagePropertyIPTCObjectName as String] as? String, !name.isEmpty {
                result.title = name
            }
        }
        // Keep everything for a faithful export later (only plist-safe values survive).
        if let plist = try? PropertyListSerialization.data(fromPropertyList: plistSafe(properties), format: .binary, options: 0) {
            result.propertiesPlist = plist
        }
        return result
    }

    /// Drops anything a property list can't hold (CGImage properties are
    /// mostly strings, numbers, arrays and dictionaries, but not always).
    static func plistSafe(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            var cleaned: [String: Any] = [:]
            for (key, inner) in dictionary {
                let safe = plistSafe(inner)
                if !(safe is NSNull) { cleaned[key] = safe }
            }
            return cleaned
        case let array as [Any]:
            return array.map { plistSafe($0) }.filter { !($0 is NSNull) }
        case is String, is NSNumber, is Date, is Data, is Bool, is Int, is Double:
            return value
        default:
            return NSNull()
        }
    }

    /// Writes a full-size (max 2048 px) JPEG and a small thumbnail to disk,
    /// and returns the size plus whatever metadata the file carried.
    static func prepare(data: Data, imageURL: URL, thumbURL: URL) throws -> Prepared {
        guard let full = downsample(data, maxPixelSize: 2048),
              let fullData = jpegData(full, quality: 0.9) else {
            throw ImportError.unreadableImage
        }
        try fullData.write(to: imageURL, options: .atomic)

        let thumb = downsample(data, maxPixelSize: 700) ?? full
        if let thumbData = jpegData(thumb, quality: 0.8) {
            try thumbData.write(to: thumbURL, options: .atomic)
        }
        return Prepared(width: Double(full.width), height: Double(full.height), metadata: readMetadata(data))
    }
}

/// A tiny wrapper so a decoded image can be handed back from a background task.
struct LoadedImage: @unchecked Sendable {
    let image: UIImage?
}

// MARK: - Small utilities

/// A repeatable random number generator, so the Pins tab keeps one shuffled
/// order until it is opened again.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// "golden retriever" → "Golden Retriever"
    var titleCased: String {
        split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Removes HTML tags ("<a href=…>Name</a>" → "Name").
    var strippingHTML: String {
        var result = ""
        var insideTag = false
        for character in self {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { result.append(character) }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Something safe to use as a file or folder name: no characters a file system refuses, at most 80
    /// characters and at most 200 bytes. The bytes matter because a file system counts bytes, not
    /// characters (a name may be 255 at most, and the caller adds an extension or a number): 80 emoji
    /// are 320 bytes. The cut is at a whole character, never in the middle of one.
    var safeFileName: String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty else { return "Untitled" }
        var result = String(cleaned.prefix(80))
        // (`removeLast` takes a whole character off. A single character of more than 200 bytes, a stack of
        // combining marks, goes entirely and leaves nothing: the name is then "Untitled".)
        while result.utf8.count > 200, !result.isEmpty { result.removeLast() }
        return result.isEmpty ? "Untitled" : result
    }
}
