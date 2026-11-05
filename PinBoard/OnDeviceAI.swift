//
//  OnDeviceAI.swift  —  PinBoard
//
//  Everything "intelligent" that runs on the device itself:
//    • Vision            → image tagging, text reading (OCR), visual fingerprints,
//                          faces (count only), animals
//    • CoreGraphics      → dominant colours and a perceptual hash (duplicates)
//    • NaturalLanguage   → word meanings for search, lemmatization
//    • FoundationModels  → (optional) Apple Intelligence for titles and web
//                          searches. Only used when the device has it.
//

import SwiftUI
import Vision
import NaturalLanguage
import UIKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Vision

struct AnalysisResult: Sendable {
    var tags: [TagScore]
    var colorTags: [String]
    var text: String
    var ocrTags: [String]
    var featurePrint: Data?
    var dhash: UInt64?
}

enum VisionAnalyzer {

    /// Runs the on-device analysis on the image at `imageURL`. `usesAI` false (a hidden pin while
    /// "Include hidden pins in AI" is off): only the fixed checks run — the fingerprint used to find
    /// look-alikes, the colours and the perceptual hash — no recognition of things, text, faces or animals.
    static func analyze(imageURL: URL, accurateText: Bool, usesAI: Bool = true) -> AnalysisResult {
        guard let image = UIImage(contentsOfFile: imageURL.path),
              let cgImage = image.cgImage else {
            return AnalysisResult(tags: [], colorTags: [], text: "", ocrTags: [], featurePrint: nil, dhash: nil)
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1. What is in the picture?  (≈1,300 built-in categories)
        var tags: [TagScore] = []
        let classify = VNClassifyImageRequest()
        if usesAI, (try? handler.perform([classify])) != nil, let observations = classify.results {
            tags = pickTags(observations)
        }

        // 2. A visual fingerprint, used to compare images with each other (look-alikes, duplicates).
        //    Kept for hidden pins too, as the duplicate check needs it — though it is made by one of
        //    Vision's models (see the owner's note in the spec, 20.1).
        var printData: Data? = nil
        let featurePrint = VNGenerateImageFeaturePrintRequest()
        if (try? handler.perform([featurePrint])) != nil, let observation = featurePrint.results?.first {
            printData = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        }

        // 3. Any text inside the image (signs, screenshots, memes…).
        var text = ""
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = accurateText ? .accurate : .fast
        textRequest.usesLanguageCorrection = true
        if usesAI, (try? handler.perform([textRequest])) != nil, let observations = textRequest.results {
            text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }

        // 4. People — only how many, never who.
        let faces = VNDetectFaceRectanglesRequest()
        if usesAI, (try? handler.perform([faces])) != nil, let count = faces.results?.count, count > 0 {
            let label: String
            switch count {
            case 1: label = "portrait"
            case 2...4: label = "people"
            default: label = "crowd"
            }
            if let existing = tags.firstIndex(where: { $0.label == label }) {
                tags[existing].confidence = max(tags[existing].confidence, 0.9)
            } else {
                tags.append(TagScore(label: label, confidence: 0.9))
            }
            if count == 1, !tags.contains(where: { $0.label == "person" }) {
                tags.append(TagScore(label: "person", confidence: 0.85))
            }
        }

        // 5. Cats and dogs, via Vision's dedicated animal recognizer.
        let animals = VNRecognizeAnimalsRequest()
        if usesAI, (try? handler.perform([animals])) != nil, let observations = animals.results {
            for observation in observations {
                for label in observation.labels.prefix(1) where label.confidence > 0.5 {
                    let name = label.identifier.lowercased()
                    if !tags.contains(where: { $0.label == name }) {
                        tags.append(TagScore(label: name, confidence: Double(label.confidence)))
                    }
                }
            }
        }

        // 6. Colours and a small perceptual hash, from a tiny copy of the image.
        let colors = ImageSignals.dominantColorTags(cgImage)
        let hash = ImageSignals.differenceHash(cgImage)

        return AnalysisResult(tags: tags,
                              colorTags: colors,
                              text: text,
                              ocrTags: keywords(fromText: text),
                              featurePrint: printData,
                              dhash: hash)
    }

    /// Keeps the classifications Apple considers precise, then tops up with the
    /// most confident remaining ones so every image gets a handful of tags.
    static func pickTags(_ observations: [VNClassificationObservation]) -> [TagScore] {
        let sorted = observations.sorted { $0.confidence > $1.confidence }
        var picked = sorted.filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
        if picked.count < 6 {
            for observation in sorted where observation.confidence > 0.2 {
                if !picked.contains(where: { $0.identifier == observation.identifier }) {
                    picked.append(observation)
                }
                if picked.count >= 6 { break }
            }
        }
        return picked.prefix(15).map {
            TagScore(label: $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased(),
                     confidence: Double($0.confidence))
        }
    }

    /// Turns text found in an image into a few useful tags: real words that
    /// appear often or are known English words, without numbers or noise.
    static func keywords(fromText text: String, limit: Int = 8) -> [String] {
        guard !text.isEmpty else { return [] }
        let matcher = SemanticMatcher.shared
        var counts: [String: Int] = [:]
        var order: [String] = []
        for word in SemanticMatcher.tokenize(text) {
            guard word.count >= 3, word.count <= 24,
                  !SemanticMatcher.stopWords.contains(word),
                  word.rangeOfCharacter(from: .decimalDigits) == nil,
                  word.rangeOfCharacter(from: .letters) != nil else { continue }
            if counts[word] == nil { order.append(word) }
            counts[word, default: 0] += 1
        }
        let good = order.filter { (counts[$0] ?? 0) >= 2 || matcher.isKnownWord($0) }
        let ranked = good.sorted { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return a.count > b.count
        }
        return Array(ranked.prefix(limit))
    }
}

// MARK: - Pixel-level signals (colours, perceptual hash)

enum ImageSignals {

    /// Draws the image into a tiny RGBA bitmap and returns the raw bytes.
    private static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colorSpace, bitmapInfo: info) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? buffer : nil
    }

    /// A 64-bit "difference hash": near-identical images get near-identical hashes.
    static func differenceHash(_ image: CGImage) -> UInt64? {
        guard let rgba = pixels(image, width: 9, height: 8) else { return nil }
        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<8 {
            for column in 0..<8 {
                let left = luminance(rgba, index: (row * 9 + column) * 4)
                let right = luminance(rgba, index: (row * 9 + column + 1) * 4)
                if left > right { hash |= (1 << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }

    /// Number of differing bits between two hashes (0 = identical).
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private static func luminance(_ rgba: [UInt8], index: Int) -> Double {
        0.299 * Double(rgba[index]) + 0.587 * Double(rgba[index + 1]) + 0.114 * Double(rgba[index + 2])
    }

    /// Names the colours that cover a meaningful part of the image.
    static func dominantColorTags(_ image: CGImage) -> [String] {
        let size = 24
        guard let rgba = pixels(image, width: size, height: size) else { return [] }
        var counts: [String: Int] = [:]
        var lowSaturation = 0
        let total = size * size
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let r = Double(rgba[index]) / 255
            let g = Double(rgba[index + 1]) / 255
            let b = Double(rgba[index + 2]) / 255
            let (name, saturated) = colorName(r: r, g: g, b: b)
            counts[name, default: 0] += 1
            if !saturated { lowSaturation += 1 }
        }
        var tags: [String] = []
        if Double(lowSaturation) / Double(total) > 0.92 {
            tags.append("black and white")
        }
        let ranked = counts.sorted { $0.value > $1.value }
        for (name, count) in ranked where Double(count) / Double(total) >= 0.18 && name != "gray" && name != "white" && name != "black" {
            tags.append(name)
            if tags.count >= 3 { break }
        }
        if tags.isEmpty, let top = ranked.first { tags.append(top.key) }
        return tags
    }

    private static func colorName(r: Double, g: Double, b: Double) -> (String, Bool) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        let brightness = maxC
        let saturation = maxC == 0 ? 0 : delta / maxC
        if brightness < 0.16 { return ("black", false) }
        if saturation < 0.16 {
            return (brightness > 0.85 ? "white" : "gray", false)
        }
        var hue: Double
        if delta == 0 {
            hue = 0
        } else if maxC == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        let name: String
        switch hue {
        case ..<15, 345...: name = "red"
        case 15..<40: name = brightness < 0.6 && saturation > 0.4 ? "brown" : "orange"
        case 40..<70: name = "yellow"
        case 70..<165: name = "green"
        case 165..<200: name = "teal"
        case 200..<255: name = "blue"
        case 255..<290: name = "purple"
        default: name = "pink"
        }
        return (name, true)
    }
}

// MARK: - Language understanding for search

/// Compares words by spelling *and* meaning (using Apple's on-device word
/// embeddings), so "puppy" can match "dog" and "coast" can match "beach".
final class SemanticMatcher: @unchecked Sendable {
    static let shared = SemanticMatcher()

    private let embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)
    private var cache: [String: Double] = [:]
    private let lock = NSLock()

    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "with", "and", "or", "in", "on", "at", "to", "for", "from", "by",
        "my", "me", "i", "show", "find", "search", "photos", "photo", "pictures", "picture", "pics",
        "pic", "images", "image", "that", "this", "some", "any", "all", "where", "which", "have",
        "has", "is", "are", "it", "its", "like", "look", "looks", "looking", "featuring",
        "containing", "contains", "something", "things", "thing", "want", "see", "get", "near",
        "about", "kind", "type", "pins", "pin", "one", "ones", "very", "really", "please",
        "you", "your", "our", "we", "was", "were", "be", "been", "not", "but", "if", "so", "as",
        "can", "will", "just", "than", "then", "there", "here", "what", "when", "who", "how",
        "http", "https", "www", "com"
    ]

    /// "Puppies on the Beach!" → ["puppies", "on", "the", "beach"]
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    /// Search words worth matching: stop words removed, plurals/verbs reduced
    /// to their base form ("puppies" → "puppy", "running" → "run").
    static func queryTerms(_ query: String) -> [String] {
        let raw = tokenize(query).filter { !stopWords.contains($0) }
        var result: [String] = []
        for word in raw {
            let lemma = lemmatize(word)
            if !result.contains(lemma) { result.append(lemma) }
        }
        return result
    }

    private static let lemmaLock = NSLock()   // NSLock is Sendable on iOS; it guards the cache below
    nonisolated(unsafe) private static var lemmaCache: [String: String] = [:]

    static func lemmatize(_ word: String) -> String {
        lemmaLock.lock()
        let known = lemmaCache[word]
        lemmaLock.unlock()
        if let known { return known }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        var result = word
        if let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty {
            result = lemma
        } else if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
            result = String(word.dropLast())
        }
        lemmaLock.lock()
        if lemmaCache.count > 20_000 { lemmaCache = [:] }
        lemmaCache[word] = result
        lemmaLock.unlock()
        return result
    }

    /// True when the on-device dictionary knows this word.
    func isKnownWord(_ word: String) -> Bool {
        embedding?.contains(word) ?? false
    }

    /// 1.0 = identical, 0 = unrelated.
    func similarity(_ a: String, _ b: String, allowSemantic: Bool = true) -> Double {
        if a == b { return 1 }
        let key = (a < b ? "\(a)|\(b)" : "\(b)|\(a)") + (allowSemantic ? "" : "#")
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return cached }

        var best = 0.0
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        if short.count >= 3 {
            // "dog" ≈ "dogs" / "doggy", but "car" is not "carpet": only a short
            // ending may differ for a spelling match.
            if long.hasPrefix(short), long.count - short.count <= 2 {
                best = 0.85
            } else if short.count >= 5, long.contains(short) {
                best = 0.6
            }
        }
        if allowSemantic, best < 0.7, let embedding, embedding.contains(a), embedding.contains(b) {
            // Cosine distance: ≈0.7–0.9 for closely related words, ≈1.3 for unrelated.
            let distance = embedding.distance(between: a, and: b)
            let semantic = max(0, min(1, (1.15 - distance) / 0.55)) * 0.85
            best = max(best, semantic)
        }
        lock.lock()
        if cache.count > 60_000 { cache = [:] }   // never grows without bound
        cache[key] = best
        lock.unlock()
        return best
    }
}

// MARK: - Titles

/// What the person themselves wrote about a pin — the context any title is chosen
/// with, on the device or in the cloud (a title never just repeats it).
struct TitleContext: Sendable {
    var userTags: [String] = []
    var boardNames: [String] = []
    var note: String = ""
    var fileKeywords: [String] = []
    var fileCaption: String? = nil
    /// Board names that only help to spot a title that merely repeats the person's words: they are
    /// never a word of a title and never told to a language model. A hidden pin's boards (hidden
    /// boards) go here (see `LibraryStore.titleContext(for:)`), so no title can carry a hidden
    /// board's name to the normal side after Unhide.
    var echoOnlyBoardNames: [String] = []

    /// Nothing to tell a language model (`echoOnlyBoardNames` are never told).
    var isEmpty: Bool { userTags.isEmpty && boardNames.isEmpty && note.isEmpty && fileKeywords.isEmpty && (fileCaption ?? "").isEmpty }

    /// Lines for a language model, most important first.
    var promptLines: [String] {
        var lines: [String] = []
        if !userTags.isEmpty { lines.append("Tags the person gave it: \(userTags.joined(separator: ", "))") }
        if !boardNames.isEmpty { lines.append("Boards the person filed it under: \(boardNames.joined(separator: "; "))") }
        if !note.isEmpty { lines.append("The person's note: \(TitleGenerator.shorten(note, to: 200))") }
        if !fileKeywords.isEmpty { lines.append("Keywords stored in the file: \(fileKeywords.joined(separator: ", "))") }
        if let caption = fileCaption, !caption.isEmpty { lines.append("Caption stored in the file: \(TitleGenerator.shorten(caption, to: 160))") }
        return lines
    }
}

enum TitleGenerator {
    /// Vision labels that are too vague to make a good title on their own.
    static let genericLabels: Set<String> = [
        "outdoor", "indoor", "structure", "material", "texture", "pattern", "object",
        "background", "abstract", "light", "daytime", "nighttime", "adult", "people",
        "person", "man", "woman", "photo", "image", "closeup", "close up", "color",
        "portrait", "crowd", "black and white", "gray", "white", "black"
    ]

    /// Labels that suggest the image is mostly text, so its first line is a
    /// better title than the tags.
    static let textyLabels: Set<String> = [
        "text", "document", "screenshot", "paper", "menu", "sign", "poster", "book",
        "newspaper", "magazine", "letter", "receipt", "whiteboard", "handwriting"
    ]

    /// A title from what was recognized in the pin, chosen with the help of the person's
    /// own words (their tags, the boards they filed it under, keywords in the file) but
    /// not made of them: those words are shown next to the title already. At most one of
    /// the (up to two) parts may be one of the person's words, and at least one part comes
    /// from what was recognized. Only when nothing was recognized is the title made of the
    /// person's words alone. Works on every device.
    static func tagBasedTitle(tags: [TagScore], ocrText: String, context: TitleContext = TitleContext()) -> String {
        let personal = contextWords(context)
        var parts: [String] = []
        func add(_ word: String) {
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, parts.count < 2 else { return }
            let lower = cleaned.lowercased()
            guard !parts.contains(where: { $0.lowercased().contains(lower) || lower.contains($0.lowercased()) }) else { return }
            parts.append(cleaned.titleCased)
        }

        // 1. Pictures that are mostly text are best titled by their first line.
        let firstLine = ocrText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 3 } ?? ""
        let wordCount = SemanticMatcher.tokenize(ocrText).count
        let looksLikeText = tags.contains { textyLabels.contains($0.label) && $0.confidence > 0.3 } || wordCount >= 12
        if looksLikeText, !firstLine.isEmpty, !isEcho(firstLine, contextWords: personal) {
            return shorten(firstLine, to: 50)
        }

        // 2. What Vision recognized, without the person's own words again (see `recognizedLabels`).
        let ranked: [TagScore] = recognizedLabels(tags, personal: personal)
        for candidate in ranked where parts.count < 2 {
            if !parts.isEmpty && candidate.confidence < 0.4 { continue }
            add(candidate.label)
        }

        // 3. One of the person's words may complete a single recognized part
        //    (their tags or file keywords; board names are shared by too many pins).
        if parts.count == 1 {
            for word in context.userTags + context.fileKeywords where parts.count < 2 { add(word) }
            return parts.joined(separator: " · ")
        }
        if !parts.isEmpty { return parts.joined(separator: " · ") }

        // 4. Nothing was recognized: the person's words are all there is. (A hidden board's name is
        //    never among `boardNames`: see `TitleContext.echoOnlyBoardNames`.)
        for tag in context.userTags { add(tag) }
        if parts.count < 2 { for keyword in context.fileKeywords { add(keyword) } }
        if parts.count == 1, let board = context.boardNames.first { add(board) }
        if parts.isEmpty, let any = tags.sorted(by: { $0.confidence > $1.confidence }).first { add(any.label) }
        return parts.joined(separator: " · ")
    }

    /// What Vision recognized that a title can be made of, best first: no vague labels
    /// (`genericLabels`) and none of the person's own words. Labels related to those words come
    /// first ("sea" for a pin tagged "beach"), so they still help.
    /// (Written as small steps with explicit types, so the compiler checks it quickly.)
    static func recognizedLabels(_ tags: [TagScore], personal: Set<String>) -> [TagScore] {
        var scored: [(tag: TagScore, score: Double)] = []
        for tag in tags {
            if genericLabels.contains(tag.label) { continue }
            if isEcho(tag.label, contextWords: personal) { continue }
            let boost: Double = 1.0 + relatedness(of: tag.label, to: personal)
            scored.append((tag: tag, score: tag.confidence * boost))
        }
        scored.sort { (a: (tag: TagScore, score: Double), b: (tag: TagScore, score: Double)) -> Bool in
            if a.score != b.score { return a.score > b.score }
            return a.tag.label < b.tag.label
        }
        return scored.map { (item: (tag: TagScore, score: Double)) -> TagScore in item.tag }
    }

    // MARK: Naming again

    /// Other titles for a pin, best first — for when the person asks the AI to name a pin again
    /// and the usual title is the one it has already. Pure: the same pin always gets the same
    /// list. In this order:
    ///   • the usual title (`tagBasedTitle`; for a text pin (`preferText`) the first line of its
    ///     text that isn't only the person's words, then the text's key words),
    ///   • the same made of the next-best labels (the best one left out, then the best two),
    ///   • the first lines of the text (read in the picture; a text pin's other lines),
    ///   • the best recognized labels on their own,
    ///   • with the person's own words allowed (their tags and file keywords): the best label with
    ///     one of their words, then their words alone.
    /// Titles that only repeat the person's own words (`isEcho`) come after all the others.
    /// Never an empty title, never `current`, never the same title twice (`sameTitle`), never a
    /// title without a real word (`isUsableTitle`: no "and", "---" or "·"), and never made of a
    /// board's name: board names only help to spot echoes (`boardNamesForEchoOnly`) — a name shared
    /// by a whole board says nothing about this pin, and a hidden board's name must never show.
    static func alternativeTitles(tags: [TagScore], text: String, context: TitleContext = TitleContext(),
                                  current: String = "", preferText: Bool = false) -> [String] {
        let personal = contextWords(context)
        let material = boardNamesForEchoOnly(context)   // (the same words for spotting echoes)
        let labels: [TagScore] = recognizedLabels(tags, personal: personal)
        let lines: [String] = titleLines(of: text, minimumLength: preferText ? 1 : 3)
        var found: [String] = []
        if preferText {
            let own = lines.first { (line: String) -> Bool in isUsableTitle(line) && !isEcho(line, contextWords: personal) }
            if let first = own ?? lines.first { found.append(first) }
            found.append(tagBasedTitle(tags: tags, ocrText: "", context: material))
        } else {
            found.append(tagBasedTitle(tags: tags, ocrText: text, context: material))
        }
        found += nextBestTitles(tags: tags, labels: labels, context: material)
        found += preferText ? lines : Array(lines.prefix(2))
        found += labels.prefix(2).map { (label: TagScore) -> String in label.label.titleCased }
        found += titlesWithPersonalWords(labels: labels, context: material)
        return distinctTitles(found, current: current, personal: personal)
    }

    /// `context` with its board names moved to `echoOnlyBoardNames`: they still tell which titles
    /// only repeat the person's words, but no title is made of them.
    static func boardNamesForEchoOnly(_ context: TitleContext) -> TitleContext {
        var copy = context
        copy.echoOnlyBoardNames += copy.boardNames
        copy.boardNames = []
        return copy
    }

    /// A title worth writing: at least one word that carries meaning (not a stop word such as
    /// "and" or "the", see `contentWords`) with at least three letters — so never "---", "·",
    /// "the" or "4th". (In Chinese, Japanese or Korean, where two characters already make a word,
    /// two letters are enough.)
    nonisolated static func isUsableTitle(_ title: String) -> Bool {
        let words: [String] = SemanticMatcher.tokenize(title).filter { (word: String) -> Bool in
            !SemanticMatcher.stopWords.contains(word)
        }
        return words.contains { (word: String) -> Bool in
            let letters = word.filter { (character: Character) -> Bool in character.isLetter }.count
            return letters >= 3 || (letters >= 2 && isEastAsian(word))
        }
    }

    /// Written (partly) in an East Asian script: CJK characters, kana or hangul.
    nonisolated private static func isEastAsian(_ word: String) -> Bool {
        word.unicodeScalars.contains { (scalar: Unicode.Scalar) -> Bool in scalar.value >= 0x2E80 && scalar.value <= 0xD7FF }
    }

    /// `tagBasedTitle` with the best recognized label left out, then the best two — each only
    /// while a recognized label is left to make the title of.
    private static func nextBestTitles(tags: [TagScore], labels: [TagScore], context: TitleContext) -> [String] {
        var titles: [String] = []
        for skipped in 1...2 where labels.count > skipped {
            let left: Set<String> = Set(labels.prefix(skipped).map { (label: TagScore) -> String in label.label })
            let rest: [TagScore] = tags.filter { (tag: TagScore) -> Bool in !left.contains(tag.label) }
            titles.append(tagBasedTitle(tags: rest, ocrText: "", context: context))
        }
        return titles
    }

    /// The first five lines of a text (trimmed, at least `minimumLength` characters long), each
    /// shortened to a title's length.
    static func titleLines(of text: String, minimumLength: Int) -> [String] {
        let lines: [String] = text.components(separatedBy: .newlines)
            .map { (line: String) -> String in line.trimmingCharacters(in: .whitespaces) }
            .filter { (line: String) -> Bool in line.count >= max(minimumLength, 1) }
        return lines.prefix(5).map { (line: String) -> String in shorten(line, to: 50) }
    }

    /// Titles that use the person's own words — their tags and file keywords, never a board's name:
    /// the best recognized label with the first of their words that isn't the same word, then two
    /// of their words, then one.
    private static func titlesWithPersonalWords(labels: [TagScore], context: TitleContext) -> [String] {
        var words: [String] = []
        for phrase in context.userTags + context.fileKeywords {
            let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = cleaned.lowercased()
            if cleaned.isEmpty || words.contains(where: { (word: String) -> Bool in word.lowercased() == lower }) { continue }
            words.append(cleaned)
        }
        guard let firstWord = words.first else { return [] }
        var titles: [String] = []
        if let best = labels.first?.label.lowercased() {
            let other = words.first { (word: String) -> Bool in
                !word.lowercased().contains(best) && !best.contains(word.lowercased())
            }
            if let other { titles.append(best.titleCased + " · " + other.titleCased) }
        }
        if words.count >= 2 { titles.append(words[0].titleCased + " · " + words[1].titleCased) }
        titles.append(firstWord.titleCased)
        return titles
    }

    /// `titles` without empty or wordless ones (`isUsableTitle`), repeats (`sameTitle`) and
    /// `current`, the ones that only repeat the person's own words moved to the end (each group in
    /// its order); at most ten.
    private static func distinctTitles(_ titles: [String], current: String, personal: Set<String>) -> [String] {
        var kept: [String] = []
        for title in titles {
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isUsableTitle(cleaned) || sameTitle(cleaned, current) { continue }
            if kept.contains(where: { (other: String) -> Bool in sameTitle(other, cleaned) }) { continue }
            kept.append(cleaned)
        }
        let fresh: [String] = kept.filter { (title: String) -> Bool in !isEcho(title, contextWords: personal) }
        let echoes: [String] = kept.filter { (title: String) -> Bool in isEcho(title, contextWords: personal) }
        return Array((fresh + echoes).prefix(10))
    }

    /// The words of a title, for comparing titles: lowercased, without spaces or punctuation.
    nonisolated static func titleWords(_ title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { (word: String) -> Bool in !word.isEmpty }
    }

    /// Two titles are the same to a reader when they have the same words in the same order,
    /// whatever the case, spacing or punctuation ("Sunset · Sea" is "sunset sea").
    nonisolated static func sameTitle(_ a: String, _ b: String) -> Bool {
        let first = titleWords(a)
        let second = titleWords(b)
        if first.isEmpty && second.isEmpty {
            return a.trimmingCharacters(in: .whitespacesAndNewlines) == b.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return first == second
    }

    /// The title a request to name a pin again writes: the first of `candidates` (best first)
    /// that differs from `current` (`sameTitle`), has a real word (`isUsableTitle`) and doesn't
    /// only repeat the person's own words — or, when every different one does, the first of those
    /// whose every word is one of their tags or file keywords or one of the `labels` the AI
    /// recognized in the pin: repeating their words is no veto, only the last choice. A recognized
    /// label that happens to be a board's name is still the AI's word ("Dog" for a dog on the board
    /// "Dogs", "Garden" for a garden on the hidden board "Garden"). But a board's name never makes
    /// a title on its own (nor with a tag) when nothing was recognized that says it: it is shared
    /// by the whole board, and a hidden board's name must never show. nil = nothing differs (the
    /// pin keeps its name).
    nonisolated static func bestNewTitle(from candidates: [String], current: String, context: TitleContext,
                                         labels: [String] = []) -> String? {
        let personal = contextWords(context)
        var allowed = ownWords(context)
        for label in labels { allowed.formUnion(contentWords(label)) }
        var ownWordsTitle: String? = nil
        for candidate in candidates {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isUsableTitle(cleaned) || sameTitle(cleaned, current) { continue }
            if isEcho(cleaned, contextWords: personal) {
                if ownWordsTitle == nil, isEcho(cleaned, contextWords: allowed) { ownWordsTitle = cleaned }
                continue
            }
            return cleaned
        }
        return ownWordsTitle
    }

    /// A language model's reply made into a title: without quotes, a "Title:" label or a full
    /// stop at the end. nil when it can't be one: empty, more than one line, or longer than
    /// 80 characters.
    nonisolated static func modelTitle(from reply: String) -> String? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("title:") { text = String(text.dropFirst(6)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’«».!"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.count > 80 { return nil }
        if text.rangeOfCharacter(from: .newlines) != nil { return nil }
        if !isUsableTitle(text) { return nil }   // "The", "---": no real word
        return text
    }

    /// What the on-device model is asked for a title (see `AppleIntelligence.generateTitle`).
    /// `avoiding`: the title the item has now — the model is asked for a different one. Only then
    /// (the person asked for a name) may it fall back on the person's own words; the automatic
    /// naming (`avoiding` nil) is not told so.
    nonisolated static func titlePrompt(tags: [String], text: String, context: TitleContext, avoiding: String?,
                                        textSource: TitleTextSource = .picture) -> String {
        var lines: [String] = []
        let personal = context.promptLines
        if !personal.isEmpty {
            lines.append("What the person wrote (to understand the item, not to copy):")
            lines += personal
            if avoiding != nil { lines.append("The person's own words may be used when nothing better fits.") }
        }
        lines += detectedLines(tags: tags, text: text, textSource: textSource)
        let now = (avoiding ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if now.isEmpty {
            lines.append("Write the title.")
        } else {
            lines.append("Its title now is \"\(now)\". Write a different title.")
        }
        return lines.joined(separator: "\n")
    }

    /// Where the text handed to a title request comes from: read in the item's picture (the usual
    /// case: a small hint after what was detected), or the item's own text — an article's, a video's
    /// description (then it is the main thing the title is made from, and what was detected in the
    /// link's preview picture only comes second).
    enum TitleTextSource: Sendable {
        case picture
        case page
    }

    /// The lines of a title request about what software found: for a picture the detected words
    /// first and the text read in it after; for a page's own text, that text first and the words
    /// detected in the preview picture second.
    nonisolated static func detectedLines(tags: [String], text: String, textSource: TitleTextSource) -> [String] {
        let detected: String? = tags.isEmpty ? nil : tags.prefix(8).joined(separator: ", ")
        switch textSource {
        case .picture:
            var lines: [String] = []
            if let detected { lines.append("Detected by software: \(detected).") }
            if !text.isEmpty { lines.append("Text visible in the picture: \"\(shorten(text, to: 200))\".") }
            return lines
        case .page:
            var lines: [String] = []
            if !text.isEmpty { lines.append("The item's own text (the main thing to name it from): \"\(shorten(text, to: 800))\".") }
            if let detected { lines.append("Detected in its preview picture (second to the text): \(detected).") }
            return lines
        }
    }

    /// The words of a title or phrase that carry meaning: lowercased, no stop words, base forms.
    nonisolated static func contentWords(_ text: String) -> [String] {
        SemanticMatcher.tokenize(text)
            .filter { !SemanticMatcher.stopWords.contains($0) }
            .map { SemanticMatcher.lemmatize($0) }
    }

    /// Every meaningful word of the person's own tags, board names (`echoOnlyBoardNames` too) and
    /// file keywords.
    nonisolated static func contextWords(_ context: TitleContext) -> Set<String> {
        var words: Set<String> = ownWords(context)
        for phrase in context.boardNames + context.echoOnlyBoardNames {
            words.formUnion(contentWords(phrase))
        }
        return words
    }

    /// Every meaningful word of the person's own tags and file keywords (not the board names).
    nonisolated static func ownWords(_ context: TitleContext) -> Set<String> {
        var words: Set<String> = []
        for phrase in context.userTags + context.fileKeywords {
            words.formUnion(contentWords(phrase))
        }
        return words
    }

    /// True when a title only repeats the person's own words: every non-stop-word of the title
    /// (lowercased, in its base form) is among the words of their tags, board names and file keywords.
    nonisolated static func isEcho(_ title: String, context: TitleContext) -> Bool {
        isEcho(title, contextWords: contextWords(context))
    }

    nonisolated static func isEcho(_ title: String, contextWords: Set<String>) -> Bool {
        guard !contextWords.isEmpty else { return false }
        let words = contentWords(title)
        return !words.isEmpty && words.allSatisfy { contextWords.contains($0) }
    }

    /// 0…1: how closely a label is related to the person's words (the same word does not count).
    nonisolated static func relatedness(of label: String, to contextWords: Set<String>) -> Double {
        guard !contextWords.isEmpty else { return 0 }
        let matcher = SemanticMatcher.shared
        var best = 0.0
        for word in contentWords(label) {
            for personal in contextWords where personal != word {
                best = max(best, matcher.similarity(word, personal))
            }
        }
        return best
    }

    static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}

// MARK: - Apple Intelligence (optional)

/// Uses the on-device language model when the device offers it. On every
/// other device these calls simply return nil / false and the app carries on.
enum AppleIntelligence {

    // What the on-device model is told before each kind of request. Each is a list of
    // lines joined once: a long chain of `+` between string pieces is too slow for the
    // compiler to type-check ("unable to type-check this expression in reasonable time").

    /// Before it writes a title.
    static let titleInstructions: String = [
        "You write short, natural titles (2 to 6 words) for items in a personal collection.",
        "What the person wrote themselves (their tags, the boards they filed the item under, their note)",
        "tells you what the item is about: use it to understand the item and to pick precise words,",
        "but do not simply repeat it. A title that is only one of their tags, only a board name,",
        "or a list of them is wrong, because those are already shown next to the title.",
        "Describe this particular item, using what was detected in it.",
        "When the item comes with text of its own (an article, a video's description), name it from that text first:",
        "what was detected in its preview picture comes second.",
        "Reuse one of the person's words only when it is the natural name of the subject.",
        "Things detected by software (objects, text read from the picture) must never contradict the person's words.",
        "Reply with the title only: no quotes, no explanation, no punctuation at the end."
    ].joined(separator: " ")

    /// Before it writes a web image-search query.
    static let queryInstructions: String = [
        "You write web image-search queries for a personal mood-board app.",
        "Reply with ONE query of one or two words (never more) that captures the essence of the image or board,",
        "the way a person would type it into an image search.",
        "Trust what the user wrote far more than what software guessed: the board name comes first,",
        "then the user's own tags, then the user's title or note. Machine-recognized objects, colours",
        "and text read from the image are hints only.",
        "Reply with the query only: no quotes, no punctuation, no explanation."
    ].joined(separator: " ")

    /// Before it lists words related to a search.
    static let relatedWordsInstructions: String = [
        "You help search a personal photo library. Given a search, list up to 6 single English words",
        "that describe what such photos would contain or be tagged with (synonyms, categories, related objects).",
        "Reply with the words only, separated by commas."
    ].joined(separator: " ")

    /// True when Apple Intelligence's on-device model can be used right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Asked once more when a title reply can't be used as it is (too long, several lines).
    static let shorterTitleRequest = "Reply with just the title, on one line, in 2 to 6 words."
    /// Asked once more when the reply is the title the item has already.
    static let differentTitleRequest = "That is the title it has now. Write a different title."
    /// Asked once more when the reply only repeats the person's own words.
    static let ownWordsTitleRequest = "That only repeats the person's own words. Write a title that describes this particular item."

    /// A short, natural title for an item, e.g. "Golden retriever playing in the surf". What the
    /// person wrote about the item (tags, boards, note) tells the model what it is about.
    /// `avoiding`: the title the item has now — the model is asked for a different one, and that
    /// title (`TitleGenerator.sameTitle`) is never returned.
    /// The model is asked once more when its first reply can't be used as it is (the request
    /// failed, or the reply is too long or more than one line), is the title the item has
    /// already, or only repeats the person's own words (`TitleGenerator.isEcho`). Such a title is
    /// no longer refused: it is returned when the second reply is no better. (The automatic
    /// naming still leaves it out; a naming the person asked for ranks it last.)
    /// `textSource`: `.page` when `text` is the item's own text (a link's article or description): it
    /// is then the main input and `tags` (what was detected in the preview picture) come second.
    /// nil = no usable title (no model on this device, nothing to go on, or no usable reply).
    static func generateTitle(tags: [String], text: String, context: TitleContext = TitleContext(),
                              avoiding: String? = nil, textSource: TitleGenerator.TitleTextSource = .picture) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            guard !tags.isEmpty || !text.isEmpty || !context.isEmpty else { return nil }
            let prompt = TitleGenerator.titlePrompt(tags: tags, text: text, context: context, avoiding: avoiding, textSource: textSource)
            var session = LanguageModelSession(instructions: AppleIntelligence.titleInstructions)
            var request = prompt
            var ownWords: String? = nil   // a different title made of the person's own words: the last choice
            for _ in 0..<2 {
                let reply: String
                do {
                    reply = try await session.respond(to: request).content
                } catch {
                    // A hiccup (or a refusal): once more from the start, in a new session.
                    session = LanguageModelSession(instructions: AppleIntelligence.titleInstructions)
                    request = prompt
                    continue
                }
                guard let title = TitleGenerator.modelTitle(from: reply) else {
                    request = AppleIntelligence.shorterTitleRequest
                    continue
                }
                if let avoiding, TitleGenerator.sameTitle(title, avoiding) {
                    request = AppleIntelligence.differentTitleRequest
                    continue
                }
                if TitleGenerator.isEcho(title, context: context) {
                    if ownWords == nil { ownWords = title }
                    request = AppleIntelligence.ownWordsTitleRequest
                    continue
                }
                return title
            }
            return ownWords
        }
        #endif
        return nil
    }

    /// A compact web image-search query (one or two words) built from what is
    /// known about an image or a board. The model only sees text, never the pixels.
    static func webSearchQuery(subject: String, details: [String], avoid: String?) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(instructions: AppleIntelligence.queryInstructions)
            var prompt = subject + "\n" + details.joined(separator: "\n")
            if let avoid, !avoid.isEmpty { prompt += "\nGive a different query than \"\(avoid)\"." }
            do {
                let response = try await session.respond(to: prompt)
                let cleaned = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.!:"))
                let words = cleaned.split(separator: " ")
                if words.isEmpty || words.count > 5 || cleaned.contains("\n") { return nil }
                return WebQueryBuilder.limit(cleaned)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Extra search words related to the query ("puppy" → dog, retriever, pet…).
    static func relatedSearchWords(for query: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return [] }
            let session = LanguageModelSession(instructions: AppleIntelligence.relatedWordsInstructions)
            do {
                let response = try await session.respond(to: "Search: \(query)")
                return response.content
                    .lowercased()
                    .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                    .filter { !$0.isEmpty && !$0.contains(" ") && $0.count <= 20 }
                    .prefix(6)
                    .map { $0 }
            } catch {
                return []
            }
        }
        #endif
        return []
    }
}

// MARK: - Web search queries

/// Decides what to search the web for, for a pin or a board. What the user
/// wrote (board names, own tags, title, note) always outranks what software
/// guessed. `variant` cycles through alternatives ("Different ideas").
enum WebQueryBuilder {

    /// Every query the app sends to the web is at most this many words.
    static let maximumWords = 2

    /// Keeps only the first `maximumWords` real words ("golden retriever puppy beach" → "golden retriever").
    static func limit(_ query: String) -> String {
        let words = query.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        return words.prefix(maximumWords).joined(separator: " ")
    }

    /// Everything known about a pin, in priority order, as lines for the model.
    static func details(for pin: Pin, boardNames: [String]) -> [String] {
        var details: [String] = []
        if !boardNames.isEmpty { details.append("Board(s) the user put it on (most important): \(boardNames.joined(separator: "; "))") }
        if !pin.tags.isEmpty { details.append("Tags the user added (very important): \(pin.tags.joined(separator: ", "))") }
        if !pin.title.isEmpty, !pin.titleIsAuto { details.append("Title written by the user: \(pin.title)") }
        // (The person's own words only: a video's transcript is handed over as the pin's text, not as the note.)
        if !pin.personalNote.isEmpty { details.append("Note written by the user: \(TitleGenerator.shorten(pin.personalNote, to: 300))") }
        if !pin.fileKeywords.isEmpty { details.append("Keywords stored in the photo file: \(pin.fileKeywords.joined(separator: ", "))") }
        if let caption = pin.fileCaption, !caption.isEmpty { details.append("Caption stored in the photo file: \(TitleGenerator.shorten(caption, to: 200))") }
        if !pin.aiDescription.isEmpty { details.append("Description from AI: \(pin.aiDescription)") }
        if !pin.title.isEmpty, pin.titleIsAuto { details.append("Title written by AI: \(pin.title)") }
        let ai = pin.aiTags.sorted { $0.confidence > $1.confidence }.prefix(10)
            .map { "\($0.label) (\(Int($0.confidence * 100))%)" }
        if !ai.isEmpty { details.append("Objects and scenes recognized by software, with confidence: \(ai.joined(separator: ", "))") }
        if !pin.colorTags.isEmpty { details.append("Dominant colours: \(pin.colorTags.joined(separator: ", "))") }
        if !pin.ocrText.isEmpty { details.append("Text visible in the image: \(TitleGenerator.shorten(pin.ocrText, to: 200))") }
        if let camera = pin.cameraModel { details.append("Camera: \(camera)") }
        if let taken = pin.capturedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            details.append("Taken on \(formatter.string(from: taken))")
        }
        return details
    }

    static func query(for pin: Pin, boardNames: [String], variant: Int, avoid: String?, useAI: Bool) async -> String {
        let fallback = fallbackQuery(for: pin, boardNames: boardNames, variant: variant)
        // A query the cloud model already composed while looking at the image.
        if variant == 0, avoid == nil, let hint = pin.aiSearchHint, !hint.isEmpty { return limit(hint) }
        guard useAI else { return fallback }
        let details = details(for: pin, boardNames: boardNames)
        guard !details.isEmpty else { return fallback }
        let smart = await AppleIntelligence.webSearchQuery(subject: "Find more images like this one.", details: details, avoid: avoid)
        return limit(smart ?? fallback)
    }

    static func query(forBoardNamed name: String, parents: [String], tags: [String], titles: [String], variant: Int, avoid: String?, useAI: Bool) async -> String {
        let fallback = fallbackQuery(forBoardNamed: name, tags: tags, variant: variant)
        guard useAI else { return fallback }

        var details: [String] = ["Board name (most important): \(name)"]
        if !parents.isEmpty { details.append("It is inside the board(s): \(parents.joined(separator: " › "))") }
        if !tags.isEmpty { details.append("Most common tags of the images on it: \(tags.joined(separator: ", "))") }
        let sample = titles.filter { !$0.isEmpty }.prefix(6)
        if !sample.isEmpty { details.append("Some image titles on it: \(sample.joined(separator: "; "))") }

        let smart = await AppleIntelligence.webSearchQuery(subject: "Find more images that belong on this board.", details: details, avoid: avoid)
        return limit(smart ?? fallback)
    }

    /// Compact tag-based query that works on every device: the user's own words
    /// first, then the most specific machine tag.
    static func fallbackQuery(for pin: Pin, boardNames: [String], variant: Int) -> String {
        // Words the user wrote (board names, own tags), then words software found.
        var userWords: [String] = []
        for name in boardNames {
            let words = SemanticMatcher.tokenize(name).filter { !SemanticMatcher.stopWords.contains($0) }
            let phrase = words.prefix(maximumWords).joined(separator: " ")
            if !phrase.isEmpty, !userWords.contains(phrase) { userWords.append(phrase) }
        }
        for tag in pin.tags.map({ $0.lowercased() }) where !tag.isEmpty && !userWords.contains(tag) { userWords.append(tag) }

        var machineWords: [String] = []
        var candidates: [String] = []
        if !pin.titleIsAuto {
            candidates += SemanticMatcher.tokenize(pin.title).filter { !SemanticMatcher.stopWords.contains($0) && $0.count > 2 }
        }
        candidates += pin.fileKeywords
        candidates += pin.aiTags.sorted { $0.confidence > $1.confidence }
            .map { $0.label }
            .filter { !TitleGenerator.genericLabels.contains($0) }
        for word in candidates where !word.isEmpty && !userWords.contains(word) && !machineWords.contains(word) {
            machineWords.append(word)
        }

        let unique = userWords + machineWords
        guard !unique.isEmpty else {
            let fromTitle = limit(pin.title)
            return fromTitle.isEmpty ? "inspiration" : fromTitle
        }

        // Two words at most: a user word plus one machine word when both exist.
        let userCount = userWords.count
        let start = variant % unique.count
        let first = unique[start]
        if unique.count == 1 { return limit(first) }
        if start < userCount, userCount < unique.count {
            let machine = unique[userCount + (variant % (unique.count - userCount))]
            return limit(machine.contains(first) || first.contains(machine) ? first : "\(first) \(machine)")
        }
        return limit(first)
    }

    static func fallbackQuery(forBoardNamed name: String, tags: [String], variant: Int) -> String {
        let nameWords = SemanticMatcher.tokenize(name).filter { !SemanticMatcher.stopWords.contains($0) }
        var base = nameWords.isEmpty ? limit(name) : nameWords.prefix(maximumWords).joined(separator: " ")
        if base.isEmpty { base = "inspiration" }
        let usable = tags.filter { !nameWords.contains($0) && !TitleGenerator.genericLabels.contains($0) }
        guard !usable.isEmpty else { return base }
        let start = variant % (usable.count + 1)
        if start == 0 { return base }
        // A name word plus a tag from the board's images.
        return limit("\(nameWords.first ?? base) \(usable[start - 1])")
    }
}
