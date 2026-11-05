//
//  ArticleHighlights.swift  —  PinBoard
//
//  The plain rules behind highlighting in the article reader (SmartLinksViews.swift), kept
//  apart from the screen so the tests can check them without one:
//    ArticleText         the article's text as the reader shows it (no "## " in front of a
//                        heading, no "> " in front of a quote), and how a place in it maps to
//                        the same place in the saved text (`pin.textBody`) and back;
//    ResolvedHighlight   a saved highlight and where it stands in the shown text right now;
//    ArticleHighlights   finding saved highlights again after the article was read again,
//                        making a highlight from a selection, which highlights a selection
//                        touches, and the list of highlights after one more was added.
//  Every place is a count of UTF-16 units — what `NSRange` and the text view count in — so
//  emoji and accented letters stay in the right place.
//  Nothing here draws anything or touches the library: it needs Foundation only.
//

import Foundation

// MARK: - The article as the reader shows it

/// The article's text as the reader shows it: the paragraphs of `ArticleParagraph.split`, a blank
/// line between them, without the "## " of a heading or the "> " of a quote. A list item keeps its
/// "• " (the reader shows that bullet as a letter of the text, so the text on screen is exactly
/// `string` and nothing has to be counted twice).
///
/// Highlights are saved as places in the saved text (`pin.textBody`) but chosen on the shown text,
/// so this keeps, for every paragraph, where its words stand in both.
struct ArticleText: Sendable, Equatable {
    /// One paragraph of the article.
    struct Part: Sendable, Equatable {
        let kind: ArticleParagraph.Kind
        /// Where its words stand in the saved text (a list item's include its "• ").
        let bodyRange: NSRange
        /// Where its words stand in `string` (the same length as `bodyRange`).
        let displayRange: NSRange
    }

    /// What the reader shows.
    let string: String
    /// The paragraphs, in order.
    let parts: [Part]
    /// The length of `string` in UTF-16 units.
    let length: Int
    /// The length of the saved text in UTF-16 units.
    let bodyLength: Int

    /// An article with no text.
    nonisolated static let empty = ArticleText(string: "", parts: [], length: 0, bodyLength: 0)

    /// What a paragraph of this kind starts with in the saved text ("## ", "• ", "> " or nothing).
    /// It is the same list `ArticleParagraph.split` goes by (a test keeps the two in step).
    nonisolated static func marker(for kind: ArticleParagraph.Kind) -> String {
        switch kind {
        case .plain: return ""
        case .heading: return "## "
        case .bullet: return "• "
        case .quote: return "> "
        }
    }

    /// The text of the bullet in front of a list item.
    nonisolated static let bulletLength = 2

    /// The saved text `body` as the reader shows it.
    nonisolated static func display(from body: String) -> ArticleText {
        let paragraphs = ArticleParagraph.split(body)
        let source = NSString(string: body)
        let bodyLength = source.length
        var shown = ""
        var shownLength = 0
        var parts: [Part] = []
        var cursor = 0   // where in the saved text the next paragraph can start
        for paragraph in paragraphs {
            let marker = ArticleText.marker(for: paragraph.kind)
            let piece = marker + paragraph.text
            let pieceLength = piece.utf16.count
            let keepsMarker = paragraph.kind == .bullet
            let markerLength = keepsMarker ? 0 : marker.utf16.count
            // Only spaces and line breaks lie between one paragraph and the next, so the first
            // match after the end of the last one is where this one stands.
            let remaining = NSRange(location: cursor, length: max(bodyLength - cursor, 0))
            let found = source.range(of: piece, options: .literal, range: remaining)
            let start = found.location == NSNotFound ? cursor : found.location
            cursor = min(start + pieceLength, bodyLength)
            let textLength = pieceLength - markerLength
            if !parts.isEmpty {
                shown += "\n\n"
                shownLength += 2
            }
            shown += keepsMarker ? piece : paragraph.text
            let bodyRange = NSRange(location: start + markerLength, length: textLength)
            let displayRange = NSRange(location: shownLength, length: textLength)
            parts.append(Part(kind: paragraph.kind, bodyRange: bodyRange, displayRange: displayRange))
            shownLength += textLength
        }
        return ArticleText(string: shown, parts: parts, length: shownLength, bodyLength: bodyLength)
    }

    // MARK: Mapping places

    /// Which paragraph holds `offset` (its first letter, and the place just after its last one,
    /// count as inside), found by halving the list. nil for a place between two paragraphs.
    private nonisolated func partIndex(holding offset: Int, inDisplay: Bool) -> Int? {
        var low = 0
        var high = parts.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = inDisplay ? parts[middle].displayRange : parts[middle].bodyRange
            if offset < range.location {
                high = middle - 1
            } else if offset > range.location + range.length {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }

    /// The place in the saved text for a place in the shown text (nil: it is between paragraphs).
    nonisolated func bodyOffset(forDisplay offset: Int) -> Int? {
        guard let index = partIndex(holding: offset, inDisplay: true) else { return nil }
        let part = parts[index]
        return part.bodyRange.location + (offset - part.displayRange.location)
    }

    /// The place in the shown text for a place in the saved text (nil: it is on a "## " or "> "
    /// that isn't shown, or between paragraphs).
    nonisolated func displayOffset(forBody offset: Int) -> Int? {
        guard let index = partIndex(holding: offset, inDisplay: false) else { return nil }
        let part = parts[index]
        return part.displayRange.location + (offset - part.bodyRange.location)
    }

    /// The part of the saved text that a part of the shown text is. nil when an end of the range
    /// is not in any paragraph's words. A range that runs over several paragraphs maps when both
    /// of its ends do (what lies between them in the saved text — the "## " and such — is inside it).
    nonisolated func bodyRange(forDisplay range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length >= 0, let stop = ArticleText.end(of: range),
              let start = bodyOffset(forDisplay: range.location),
              let end = bodyOffset(forDisplay: stop) else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The part of the shown text that a part of the saved text is (see `bodyRange(forDisplay:)`).
    nonisolated func displayRange(forBody range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length >= 0, let stop = ArticleText.end(of: range),
              let start = displayOffset(forBody: range.location),
              let end = displayOffset(forBody: stop) else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// Where a range ends, or nil when adding its two numbers would overflow. A highlight read from
    /// a damaged or hand-made library file can hold any numbers; adding them up must never crash.
    private nonisolated static func end(of range: NSRange) -> Int? {
        let (sum, overflowed) = range.location.addingReportingOverflow(range.length)
        return overflowed ? nil : sum
    }

    // MARK: Reading the shown text

    /// Spaces, tabs and line breaks (what `ArticleParagraph.split` trims, too).
    nonisolated static let spaces = CharacterSet.whitespacesAndNewlines

    /// Whether a UTF-16 unit is a space or a line break.
    nonisolated static func isSpace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return spaces.contains(scalar)
    }

    /// The words of `range` of the shown text (nothing for a range that isn't inside it).
    nonisolated func slice(_ range: NSRange) -> String {
        guard range.location >= 0, range.length > 0, range.location + range.length <= length else { return "" }
        let units = string.utf16
        let start = units.index(units.startIndex, offsetBy: range.location)
        let end = units.index(start, offsetBy: range.length)
        return String(decoding: Array(units[start..<end]), as: UTF16.self)
    }

    /// A selection in the shown text cut down to its words: without the spaces and line breaks
    /// around it, and without the bullet of a list item it starts or ends in. nil when nothing
    /// is left.
    nonisolated func trimmedRange(_ selection: NSRange) -> NSRange? {
        var start = max(selection.location, 0)
        var end = min(selection.location + selection.length, length)
        guard end > start else { return nil }
        let units = string.utf16
        /// The letter (UTF-16 unit) at `offset` of the shown text.
        func unit(_ offset: Int) -> UInt16 {
            units[units.index(units.startIndex, offsetBy: offset)]
        }
        while start < end {
            if ArticleText.isSpace(unit(start)) {
                start += 1
            } else if let afterBullet = endOfBullet(containing: start) {
                start = afterBullet
            } else {
                break
            }
        }
        while end > start {
            if ArticleText.isSpace(unit(end - 1)) {
                end -= 1
            } else if let beforeBullet = startOfBullet(endingIn: end - 1) {
                end = beforeBullet
            } else {
                break
            }
        }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// Where the bullet of a list item ends, when the unit at `offset` is part of that bullet.
    private nonisolated func endOfBullet(containing offset: Int) -> Int? {
        guard let index = partIndex(holding: offset, inDisplay: true), parts[index].kind == .bullet else { return nil }
        let first = parts[index].displayRange.location
        return offset < first + ArticleText.bulletLength ? first + ArticleText.bulletLength : nil
    }

    /// Where the bullet of a list item starts, when the unit at `offset` is part of that bullet.
    private nonisolated func startOfBullet(endingIn offset: Int) -> Int? {
        guard let index = partIndex(holding: offset, inDisplay: true), parts[index].kind == .bullet else { return nil }
        let first = parts[index].displayRange.location
        return offset < first + ArticleText.bulletLength ? first : nil
    }
}

// MARK: - A saved highlight, found again

/// A saved highlight and where it stands in the shown text now. `mark` is the highlight as it
/// should be saved: when the article was read again and the passage moved, it has the new place
/// (`moved`); `displayRange` is nil when the passage isn't in the article any more ("text changed":
/// it is still listed, just not drawn).
struct ResolvedHighlight: Sendable, Equatable, Identifiable {
    let mark: TextHighlight
    let displayRange: NSRange?
    let moved: Bool

    var id: UUID { mark.id }
}

/// The article text without its spaces and line breaks, with where each remaining letter stood.
/// It lets a passage be found again when the article's spacing or line breaks changed.
private struct CompactText {
    private(set) var units: [UInt16] = []
    /// For each unit of `units`: its place in the shown text.
    private(set) var offsets: [Int] = []

    /// Goes through the shown text once, keeping every letter that isn't a space or a line break.
    nonisolated init(_ text: ArticleText) {
        units.reserveCapacity(text.length)
        offsets.reserveCapacity(text.length)
        var offset = 0
        for unit in text.string.utf16 {
            if !ArticleText.isSpace(unit) {
                units.append(unit)
                offsets.append(offset)
            }
            offset += 1
        }
    }

    /// A passage's letters without its spaces and line breaks.
    nonisolated static func units(of passage: String) -> [UInt16] {
        passage.utf16.filter { (unit: UInt16) -> Bool in !ArticleText.isSpace(unit) }
    }

    /// Where `needle` starts in `units` (at most `limit` places).
    nonisolated func occurrences(of needle: [UInt16], limit: Int) -> [Int] {
        guard let first = needle.first, needle.count <= units.count else { return [] }
        var found: [Int] = []
        let lastStart = units.count - needle.count
        var start = 0
        while start <= lastStart && found.count < limit {
            if units[start] == first && matches(needle, at: start) { found.append(start) }
            start += 1
        }
        return found
    }

    /// Whether the rest of `needle` (after its first letter, which the caller checked) follows at `start`.
    private nonisolated func matches(_ needle: [UInt16], at start: Int) -> Bool {
        var index = 1
        while index < needle.count {
            if units[start + index] != needle[index] { return false }
            index += 1
        }
        return true
    }
}

// MARK: - Highlights

/// The rules for highlights in the reader.
enum ArticleHighlights {
    /// The most places looked at when a passage turns up many times.
    nonisolated static let searchLimit = 200

    // MARK: Finding highlights again

    /// Every saved highlight, in the same order, with its place in the shown text. A highlight is
    /// where it says it is when the words there are still its words. Otherwise (the article was
    /// read again and its text changed a little) its words are looked for in the article, ignoring
    /// spaces and line breaks; when they turn up more than once, the one nearest to the old place
    /// is taken. Words that are gone are listed without a place.
    nonisolated static func resolve(_ marks: [TextHighlight], in text: ArticleText) -> [ResolvedHighlight] {
        var compact: CompactText? = nil
        var result: [ResolvedHighlight] = []
        for mark in marks {
            if let range = storedRange(of: mark, in: text) {
                result.append(ResolvedHighlight(mark: mark, displayRange: range, moved: false))
                continue
            }
            let table = compact ?? CompactText(text)
            compact = table
            if let found = findAgain(mark, in: text, table: table) {
                result.append(found)
            } else {
                result.append(ResolvedHighlight(mark: mark, displayRange: nil, moved: false))
            }
        }
        return result
    }

    /// Where a highlight says it is, in the shown text — when its words really are there.
    /// A place that can't lie inside the saved text (a damaged or hand-made library file, a hostile
    /// import) is "not there" at once: adding up a huge start and length would overflow and crash the
    /// pin page and the reader every time they are drawn.
    private nonisolated static func storedRange(of mark: TextHighlight, in text: ArticleText) -> NSRange? {
        guard mark.start >= 0, mark.length > 0, !mark.text.isEmpty,
              mark.start <= text.bodyLength, mark.length <= text.bodyLength - mark.start else { return nil }
        let stored = NSRange(location: mark.start, length: mark.length)
        guard let range = text.displayRange(forBody: stored), range.length > 0 else { return nil }
        return text.slice(range) == mark.text ? range : nil
    }

    /// A highlight whose words are somewhere else now: the highlight with its new place.
    private nonisolated static func findAgain(_ mark: TextHighlight, in text: ArticleText, table: CompactText) -> ResolvedHighlight? {
        let needle = CompactText.units(of: mark.text)
        guard !needle.isEmpty else { return nil }
        var best: (range: NSRange, body: NSRange, distance: Int)? = nil
        for first in table.occurrences(of: needle, limit: searchLimit) {
            let start = table.offsets[first]
            let end = table.offsets[first + needle.count - 1] + 1
            let range = NSRange(location: start, length: end - start)
            guard let body = text.bodyRange(forDisplay: range) else { continue }
            // The old place is pulled into the text first, so an absurd stored start can't overflow the subtraction.
            let distance = abs(body.location - min(max(mark.start, 0), text.bodyLength))
            if best == nil || distance < (best?.distance ?? Int.max) { best = (range, body, distance) }
        }
        guard let best else { return nil }
        let moved = TextHighlight(id: mark.id, text: text.slice(best.range), start: best.body.location,
                                  length: best.body.length, createdAt: mark.createdAt)
        return ResolvedHighlight(mark: moved, displayRange: best.range, moved: true)
    }

    /// The highlights to save when some were found at a new place (the reader writes them back
    /// once, so the next opening finds them where they say they are). nil when none moved.
    nonisolated static func updated(_ marks: [TextHighlight], with resolved: [ResolvedHighlight]) -> [TextHighlight]? {
        var corrected: [UUID: TextHighlight] = [:]
        for item in resolved where item.moved { corrected[item.mark.id] = item.mark }
        guard !corrected.isEmpty else { return nil }
        return marks.map { (mark: TextHighlight) -> TextHighlight in corrected[mark.id] ?? mark }
    }

    /// The highlights in the order the passages stand in the article; the ones that can't be found
    /// again come last.
    nonisolated static func inReadingOrder(_ items: [ResolvedHighlight]) -> [ResolvedHighlight] {
        items.sorted { (first: ResolvedHighlight, second: ResolvedHighlight) -> Bool in
            switch (first.displayRange, second.displayRange) {
            case let (one?, two?):
                if one.location != two.location { return one.location < two.location }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            if first.mark.createdAt != second.mark.createdAt { return first.mark.createdAt < second.mark.createdAt }
            return first.mark.id.uuidString < second.mark.id.uuidString
        }
    }

    // MARK: Making and finding highlights

    /// The words of a selection in the shown text, as a quote: without the spaces and line
    /// breaks around it. nil when nothing is left.
    nonisolated static func quote(for selection: NSRange, in text: ArticleText) -> String? {
        guard let range = text.trimmedRange(selection) else { return nil }
        let words = text.slice(range)
        return words.isEmpty ? nil : words
    }

    /// The highlight for a selection in the shown text (cut down to its words). nil when it is
    /// empty or can't be placed in the saved text.
    nonisolated static func make(selection: NSRange, in text: ArticleText) -> TextHighlight? {
        guard let range = text.trimmedRange(selection), let body = text.bodyRange(forDisplay: range), body.length > 0 else { return nil }
        let words = text.slice(range)
        guard !words.isEmpty else { return nil }
        return TextHighlight(text: words, start: body.location, length: body.length)
    }

    /// The highlights a selection touches (for "Remove highlight"). A selection with no length
    /// (a tap) touches the highlight it is in.
    nonisolated static func touching(_ selection: NSRange, resolved: [ResolvedHighlight]) -> [ResolvedHighlight] {
        resolved.filter { (item: ResolvedHighlight) -> Bool in
            guard let range = item.displayRange else { return false }
            if selection.length == 0 { return range.location <= selection.location && selection.location < range.location + range.length }
            return NSIntersectionRange(selection, range).length > 0
        }
    }

    /// The highlight under the letter at `index` of the shown text (the shortest, when several
    /// lie over each other).
    nonisolated static func highlight(atDisplayIndex index: Int, in resolved: [ResolvedHighlight]) -> ResolvedHighlight? {
        var best: ResolvedHighlight? = nil
        var bestLength = Int.max
        for item in resolved {
            guard let range = item.displayRange, range.location <= index, index < range.location + range.length else { continue }
            if range.length < bestLength {
                best = item
                bestLength = range.length
            }
        }
        return best
    }

    /// Two places in the text that overlap or touch.
    private nonisolated static func joins(_ first: NSRange, _ second: NSRange) -> Bool {
        NSIntersectionRange(first, second).length > 0
            || first.location + first.length == second.location
            || second.location + second.length == first.location
    }

    /// All the highlights after highlighting `selection`: the new one, with every highlight it
    /// overlaps or touches folded into it (so two passages never lie over each other and a
    /// highlight can grow by marking a bit more). nil when there is nothing to add: the selection
    /// is empty, or is already inside one highlight.
    nonisolated static func adding(selection: NSRange, to resolved: [ResolvedHighlight], in text: ArticleText) -> [TextHighlight]? {
        guard let wanted = text.trimmedRange(selection) else { return nil }
        for item in resolved {
            guard let range = item.displayRange else { continue }
            if range.location <= wanted.location && wanted.location + wanted.length <= range.location + range.length { return nil }
        }
        var union = wanted
        var folded = Set<UUID>()
        var grew = true
        while grew {
            grew = false
            for item in resolved where !folded.contains(item.mark.id) {
                guard let range = item.displayRange, joins(range, union) else { continue }
                union = NSUnionRange(union, range)
                folded.insert(item.mark.id)
                grew = true
            }
        }
        guard let mark = make(selection: union, in: text) else { return nil }
        var marks: [TextHighlight] = []
        for item in resolved where !folded.contains(item.mark.id) { marks.append(item.mark) }
        marks.append(mark)
        return marks
    }
}
