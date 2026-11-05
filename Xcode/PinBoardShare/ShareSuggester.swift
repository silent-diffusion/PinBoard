//
//  ShareSuggester.swift  —  PinBoard share extension
//
//  "Suggested" in the share sheet's board list: up to 3 boards the shared item fits, by the same
//  rules as the app's own suggestions (LibraryStore.scoreBoards in LibraryBoards.swift):
//    • the board's name (and its parents') against the item's words or tags   — 55%
//    • the item's tags against the tags common on the board                   — 25%
//    • the app compares pictures with the board's pins (35%); the share sheet can't, so a link
//      from a site the board's pins come from counts there instead.
//  A board scoring under 0.2 is never suggested. The app writes what each board needs (ShareShared.swift);
//  here only the first shared item is looked at, cheaply: a link's site, address and page title, a
//  text's words, and for a picture or video Apple's on-device picture classifier on a small copy.
//  Nothing leaves the device. Word matching is by spelling only (the app's word meanings would
//  take more memory than the share sheet has).
//

import Foundation
import NaturalLanguage
import Vision
import CoreML
import ImageIO
import UIKit

/// One suggested board, with a few words on why.
struct ShareSuggestion: Identifiable, Sendable, Equatable {
    var board: ShareBoardList.Board
    var score: Double
    var reason: String
    var id: UUID { board.id }
}

enum ShareSuggester {
    /// What the first shared item says about itself: weighted words or tags, and its site.
    struct Features: Sendable {
        var tags: [(label: String, weight: Double)] = []
        var site: String? = nil

        var isEmpty: Bool { tags.isEmpty && site == nil }
    }

    nonisolated static let minimumScore = 0.2
    nonisolated static let limit = 3

    /// Words never worth matching (the app's list, SemanticMatcher.stopWords).
    nonisolated static let stopWords: Set<String> = [
        "a", "an", "the", "of", "with", "and", "or", "in", "on", "at", "to", "for", "from", "by",
        "my", "me", "i", "show", "find", "search", "photos", "photo", "pictures", "picture", "pics",
        "pic", "images", "image", "that", "this", "some", "any", "all", "where", "which", "have",
        "has", "is", "are", "it", "its", "like", "look", "looks", "looking", "featuring",
        "containing", "contains", "something", "things", "thing", "want", "see", "get", "near",
        "about", "kind", "type", "pins", "pin", "one", "ones", "very", "really", "please",
        "you", "your", "our", "we", "was", "were", "be", "been", "not", "but", "if", "so", "as",
        "can", "will", "just", "than", "then", "there", "here", "what", "when", "who", "how",
        "http", "https", "www", "com", "org", "net", "html", "htm", "php", "index", "amp",
    ]

    // MARK: The shared item

    /// A link: its site, the words of its address and its page title (when the other app gave one).
    nonisolated static func features(link address: String, title: String?) -> Features {
        var features = Features()
        features.site = ShareBoardList.site(of: address)
        var words: [(String, Double)] = []
        if let title { for word in importantWords(title, limit: 10) { words.append((word, 0.9)) } }
        if let url = URL(string: address) {
            let siteName = (features.site ?? "").components(separatedBy: ".").first ?? ""
            for word in importantWords(siteName + " " + url.path, limit: 10) { words.append((word, 0.7)) }
        }
        features.tags = merged(words)
        return features
    }

    /// Text: its most frequent real words.
    nonisolated static func features(text: String) -> Features {
        var features = Features()
        let sample = String(text.prefix(4000))
        features.tags = merged(importantWords(sample, limit: 12).map { ($0, 0.9) })
        return features
    }

    /// A picture (or a video's first frame): what Apple's classifier sees, kept as the app keeps its
    /// AI tags (VisionAnalyzer.pickTags), weighted by how sure it is. The picture is a small copy.
    nonisolated static func features(picture: CGImage) -> Features {
        var features = Features()
        guard let observations = classify(picture) else { return features }
        let sorted = observations.sorted { $0.confidence > $1.confidence }
        var picked = sorted.filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
        if picked.count < 6 {
            for observation in sorted where observation.confidence > 0.2 {
                if !picked.contains(where: { $0.identifier == observation.identifier }) { picked.append(observation) }
                if picked.count >= 6 { break }
            }
        }
        features.tags = picked.prefix(15).map { (observation: VNClassificationObservation) -> (label: String, weight: Double) in
            let label = observation.identifier.replacingOccurrences(of: "_", with: " ").lowercased()
            return (label: label, weight: 0.5 + 0.5 * Double(observation.confidence))
        }
        return features
    }

    /// Apple's classifier, on the device's fastest chip; when that can't start (the simulator has
    /// none it can use) it runs again on the processor, which is fine for one small picture.
    private nonisolated static func classify(_ picture: CGImage) -> [VNClassificationObservation]? {
        let handler = VNImageRequestHandler(cgImage: picture, orientation: .up, options: [:])
        let request = VNClassifyImageRequest()
        if (try? handler.perform([request])) != nil, let results = request.results { return results }
        let again = VNClassifyImageRequest()
        if #available(iOS 17, *) {
            let cpu = MLComputeDevice.allComputeDevices.first { (device: MLComputeDevice) -> Bool in
                if case .cpu = device { return true }
                return false
            }
            if let cpu { again.setComputeDevice(cpu, for: .main) }
        }
        guard (try? handler.perform([again])) != nil else { return nil }
        return again.results
    }

    /// What a picture file says about itself, as the app reads it on import: its stored keywords
    /// (0.8) and the words of its stored title (0.9; a camera's name such as "DSC_0001" is skipped).
    nonisolated static func storedWords(of file: URL) -> [(label: String, weight: Double)] {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] else { return [] }
        var words: [(String, Double)] = []
        if let keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String] {
            for keyword in keywords.prefix(15) {
                let cleaned = keyword.trimmingCharacters(in: .whitespaces).lowercased()
                if !cleaned.isEmpty { words.append((cleaned, 0.8)) }
            }
        }
        if let title = iptc[kCGImagePropertyIPTCObjectName as String] as? String {
            let letters = title.filter { $0.isLetter }.count
            let digits = title.filter { $0.isNumber }.count
            if letters >= 4, digits <= letters {
                for word in importantWords(title, limit: 6) { words.append((word, 0.9)) }
            }
        }
        return merged(words)
    }

    /// Two lists of words or tags as one (the same one twice keeps its highest weight).
    nonisolated static func combined(_ first: [(label: String, weight: Double)],
                                     _ second: [(label: String, weight: Double)]) -> [(label: String, weight: Double)] {
        merged((first + second).map { ($0.label, $0.weight) })
    }

    /// A small copy of a picture file (the longest side at most `size` pixels), for the classifier.
    nonisolated static func smallPicture(_ file: URL, size: Int = 360) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Scoring (the app's rule)

    /// The boards that fit, best first (at most 3, none under 0.2).
    nonisolated static func suggest(_ features: Features, boards: [ShareBoardList.Board]) -> [ShareSuggestion] {
        guard !features.isEmpty else { return [] }
        let focus = Array(features.tags.sorted { $0.weight > $1.weight }.prefix(8))
        var found: [ShareSuggestion] = []
        for board in boards {
            let name = nameScore(board, features.tags)
            let tags = tagScore(board, focus)
            let site = features.site.flatMap { board.sites[$0] }.map { min(1, 0.6 + $0) } ?? 0
            let weightedName = 0.55 * name.score
            let weightedTags = 0.25 * tags
            let weightedSite = 0.35 * site
            let score = min(1, weightedName + weightedTags + weightedSite)
            guard score >= minimumScore else { continue }
            let reason: String
            if weightedSite >= weightedName && weightedSite >= weightedTags, let site = features.site {
                reason = "pins from \(site) are here"
            } else if weightedName >= weightedTags, let word = name.word {
                reason = "its name matches “\(word)”"
            } else {
                reason = "like the pins already here"
            }
            found.append(ShareSuggestion(board: board, score: score, reason: reason))
        }
        let ordered = found.sorted { (a: ShareSuggestion, b: ShareSuggestion) -> Bool in
            a.score != b.score ? a.score > b.score : a.board.name.localizedStandardCompare(b.board.name) == .orderedAscending
        }
        return Array(ordered.prefix(limit))
    }

    /// The board's name words against the item's words: the best single match, and the item's word.
    private nonisolated static func nameScore(_ board: ShareBoardList.Board,
                                              _ tags: [(label: String, weight: Double)]) -> (score: Double, word: String?) {
        var best = 0.0
        var bestWord: String? = nil
        for (nameWord, nameWeight) in board.nameWords {
            for (label, tagWeight) in tags {
                var similar = similarity(nameWord, label)
                for part in tokenize(label) where part != label {
                    similar = max(similar, similarity(nameWord, part) * 0.95)
                }
                let scored = similar * nameWeight * (0.6 + 0.4 * tagWeight)
                if scored > best {
                    best = scored
                    bestWord = label
                }
            }
        }
        return (best, bestWord)
    }

    /// How common the item's main tags are on the board (each counts up to a share of 2 in 3).
    private nonisolated static func tagScore(_ board: ShareBoardList.Board, _ focus: [(label: String, weight: Double)]) -> Double {
        guard !board.tags.isEmpty else { return 0 }
        var numerator = 0.0
        var denominator = 0.0
        for (label, weight) in focus {
            numerator += weight * min(1, (board.tags[label] ?? 0) * 1.5)
            denominator += weight
        }
        return denominator > 0 ? numerator / denominator : 0
    }

    /// The app's spelling match (SemanticMatcher.similarity without word meanings): the same word 1,
    /// a short ending apart ("beach" / "beaches") 0.85, one inside the other ("cake" in "cupcakes") 0.6.
    nonisolated static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard short.count >= 3 else { return 0 }
        if long.hasPrefix(short), long.count - short.count <= 2 { return 0.85 }
        if short.count >= 5, long.contains(short) { return 0.6 }
        return 0
    }

    // MARK: Words

    nonisolated static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    /// The words worth matching, in their base form, most frequent (then longest) first.
    nonisolated static func importantWords(_ text: String, limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for word in tokenize(text) where word.count >= 3 && !stopWords.contains(word) {
            guard word.rangeOfCharacter(from: .letters) != nil, word.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
            counts[lemma(word), default: 0] += 1
        }
        let ranked = counts.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
            a.value != b.value ? a.value > b.value : a.key.count > b.key.count
        }
        return ranked.prefix(limit).map { $0.key }
    }

    /// "beaches" → "beach", "running" → "run" (as the app does it).
    nonisolated static func lemma(_ word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        if let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty { return lemma }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// The same word twice keeps its highest weight.
    private nonisolated static func merged(_ words: [(String, Double)]) -> [(label: String, weight: Double)] {
        var result: [(label: String, weight: Double)] = []
        for (word, weight) in words {
            if let index = result.firstIndex(where: { $0.label == word }) {
                result[index].weight = max(result[index].weight, weight)
            } else {
                result.append((label: word, weight: weight))
            }
        }
        return result
    }
}
