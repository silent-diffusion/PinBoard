//
//  LibraryPins.swift  —  PinBoard
//
//  The part of `LibraryStore` that changes pins: `modify` (the one door every edit goes through),
//  titles, notes, tags (and the tag manager), a crop, a link pin's address, the text the AI names
//  and tags a pin from, which boards a pin is on, and hiding single pins. It is an extension in
//  its own file so that LibraryStore.swift stays short enough to paste.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

extension LibraryStore {

    // MARK: Editing pins

    /// Every change to a pin goes through here (it stamps `updatedAt` for sync).
    func modify(_ id: UUID, _ change: (inout Pin) -> Void) {   // (not private: used by the extensions in MediaStorage.swift and SmartLinks.swift)
        guard let index = index(of: id) else { return }
        var pin = pins[index]
        change(&pin)
        pin.updatedAt = Date()
        pins[index] = pin
    }

    /// Like `modify`, but the pin keeps its change date: for what is not an edit — re-creating a
    /// record from an export (filling in what the export kept, see `reinsertedDate`), and a fact
    /// found out about the file itself (a video's sound was listened to and held no words:
    /// `transcriptChecked`, see VideoTranscripts.swift).
    func modifyKeepingDate(_ id: UUID, _ change: (inout Pin) -> Void) {
        guard let index = index(of: id) else { return }
        var pin = pins[index]
        change(&pin)
        pins[index] = pin
    }

    func modify(_ ids: Set<UUID>, _ change: (inout Pin) -> Void) {   // (not private: used by LibraryStore.swift, LibraryBoards.swift, LibraryUpkeep.swift and LibraryAnalysis.swift)
        rebuildIndexIfNeeded()
        var updated = pins
        var touched = false
        for id in ids {
            guard let index = indexByID[id] else { continue }
            change(&updated[index])
            updated[index].updatedAt = Date()
            touched = true
        }
        if touched { pins = updated }
    }

    func update(_ pin: Pin) {
        modify(pin.id) { $0 = pin }
        scheduleSave()
    }

    /// A title the person typed or chose: from now on the AI never replaces it.
    func setTitle(_ title: String, for id: UUID) {
        guard let pin = pin(id), pin.title != title else { return }
        modify(id) { $0.setUserTitle(title) }
        scheduleSave()
    }

    /// Puts back the title from before the AI's last rename of this pin (see `Pin.undoAITitle`).
    @discardableResult
    func undoAITitle(for id: UUID) -> Bool {
        guard let current = pin(id), current.titleUndo != nil else { return false }
        var restored = false
        modify(id) { restored = $0.undoAITitle() }
        scheduleSave()
        return restored
    }

    func setNote(_ note: String, for id: UUID) {
        guard let pin = pin(id), pin.note != note else { return }
        modify(id) { $0.note = note }
        scheduleSave()
    }

    /// A note the person edited in a sheet. `opened`: the note as it was when the sheet opened. A
    /// video's transcript that was written into the stored note while the sheet was open is kept
    /// (the person's text comes first; `TranscriptNotes.merged` adds nothing when the words are in
    /// `text` already — so a block the person cut on purpose, which was there when the sheet
    /// opened, is not put back).
    func setNote(_ text: String, for id: UUID, openedWith opened: String) {
        var note = text
        if let current = pin(id), current.note != opened, let words = current.transcript {
            let wasThere = TranscriptNotes.squeezed(opened).contains(TranscriptNotes.squeezed(words))
            if !wasThere { note = TranscriptNotes.merged(note: text, transcript: words) }
        }
        setNote(note, for: id)
    }

    /// Changes the text of a text pin (its tags are worked out again).
    func setTextBody(_ body: String, for id: UUID) {
        guard let pin = pin(id), pin.isText, pin.textBody != body else { return }
        modify(id) { $0.textBody = body; $0.needsAnalysis = true }
        scheduleSave()
        startAnalysisIfNeeded()
    }

    /// A tag the tag field can offer while you type.
    struct TagSuggestion: Identifiable, Hashable {
        var tag: String
        var isUser: Bool     // one of your own tags (offered first), or one the AI found
        var id: String { tag }
    }

    /// Tags that start with (or contain) what has been typed so far: your own
    /// tags first, then tags the AI has found, most used first.
    func tagSuggestions(matching typed: String, excluding: [String] = [], limit: Int = 12, scope: PinScope = .visible) -> [TagSuggestion] {
        let needle = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let excluded = Set(excluding.map { $0.lowercased() })
        var userCounts: [String: Int] = [:]
        var aiCounts: [String: Int] = [:]
        for pin in pins(scope: scope) {
            for tag in pin.tags { userCounts[tag.lowercased(), default: 0] += 1 }
            for tag in pin.aiTags where tag.confidence >= 0.3 { aiCounts[tag.label, default: 0] += 1 }
            for tag in pin.fileKeywords { aiCounts[tag.lowercased(), default: 0] += 1 }
        }
        func ranked(_ counts: [String: Int]) -> [String] {
            let matching = counts.filter { $0.key.contains(needle) && !excluded.contains($0.key) && $0.key != needle }
            return matching.sorted {
                let aPrefix = $0.key.hasPrefix(needle), bPrefix = $1.key.hasPrefix(needle)
                if aPrefix != bPrefix { return aPrefix }
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }.map { $0.key }
        }
        var result: [TagSuggestion] = ranked(userCounts).map { TagSuggestion(tag: $0, isUser: true) }
        let seen = Set(result.map { $0.tag })
        result += ranked(aiCounts).filter { !seen.contains($0) }.map { TagSuggestion(tag: $0, isUser: false) }
        return Array(result.prefix(limit))
    }

    /// "Suggest a title" (the pin page): writes a fresh AI title — one that differs from the title
    /// the pin has, whoever wrote it (the pin page then offers Undo). A pin the AI hasn't looked
    /// at yet (new, or turned or cut since) is looked at first (`lookFirst`: when the AI queue is
    /// looking at it already, that look is waited for). Returns whether the title changed:
    /// false = it keeps its name, because nothing different was found (see `explicitTitle`) — or
    /// because it was renamed meanwhile, or another profile was chosen. A link without a preview
    /// picture gives false at once: there is nothing to name it from (naming runs leave such
    /// links out too, see `namingCandidates`).
    @discardableResult
    func regenerateTitle(for id: UUID) async -> Bool {
        let profile = profileID
        let settings = AppSettings.shared
        guard let found = pin(id), !(found.isLink && !found.hasPreview), aiMaySee(found) else { return false }
        var before = found.titleState
        var fromCloud: String? = nil
        if found.needsAnalysis {
            let look = await lookFirst(id, settings: settings)
            guard look.going, isCurrentProfile(profile) else { return false }
            // The cloud model looks too when it is on, as the AI queue would: its title goes first.
            // (When the queue took the look, it asks the cloud model itself.)
            if look.lookedHere, let looked = pin(id), cloudMaySee(looked), looked.hasImageFile {
                if case .title(let title) = await cloudTitle(for: looked, mergingTags: true) { fromCloud = title }
                guard isCurrentProfile(profile) else { return false }
            }
            // Named by the AI queue meanwhile (its own title after its look): that one is replaced.
            if let looked = pin(id), looked.title != before.title, looked.titleIsAIOwned { before = looked.titleState }
        }
        guard let current = pin(id), current.title == before.title else { return false }
        let title = await explicitTitle(for: current, first: fromCloud, settings: settings)
        // Typed meanwhile? Then the person's title stays. (Another profile now? Then it isn't this pin.)
        guard isCurrentProfile(profile), let title, let again = pin(id), again.title == before.title else { return false }
        modify(id) { $0.setAITitle(title, replacing: before) }
        scheduleSave()
        return true
    }

    /// Cuts a picture down to `unitRect` (0…1 of its width and height, top-left origin — see
    /// `ImageProcessor.pixelRect`), writing the file in place as a rotation does: the thumbnail is
    /// made again, the fingerprint and look-alike check start over and the AI looks at it again.
    /// Only picture pins (not videos, not link previews). Returns whether the picture changed
    /// (false for the whole picture, an unreadable file, or another profile chosen meanwhile).
    func cropImage(_ id: UUID, to unitRect: CGRect) async -> Bool {
        guard let pin = pin(id), pin.kind == .image, pin.hasImageFile, await ensureLocal(pin) else { return false }
        let profile = profileID
        let imageURL = imageFileURL(for: pin)
        let thumbURL = thumbsURL.appendingPathComponent(pin.thumbFileName)
        let printURL = printsURL.appendingPathComponent(pin.printFileName)
        // Plain numbers go to the background (they are Sendable everywhere).
        let area = (x: Double(unitRect.origin.x), y: Double(unitRect.origin.y),
                    width: Double(unitRect.size.width), height: Double(unitRect.size.height))
        let size = await Task.detached(priority: .userInitiated) { () -> (Double, Double)? in
            let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            guard let data = try? Data(contentsOf: imageURL),
                  let source = ImageProcessor.downsample(data, maxPixelSize: 2048),
                  let cut = ImageProcessor.cropped(source, to: rect),
                  cut.width != source.width || cut.height != source.height,   // the whole picture: nothing to do
                  let fullData = ImageProcessor.jpegData(cut, quality: 0.9),
                  (try? fullData.write(to: imageURL, options: .atomic)) != nil else { return nil }
            if let thumb = ImageProcessor.downsample(fullData, maxPixelSize: 700), let thumbData = ImageProcessor.jpegData(thumb, quality: 0.8) {
                try? thumbData.write(to: thumbURL, options: .atomic)
            }
            try? FileManager.default.removeItem(at: printURL)
            return (Double(cut.width), Double(cut.height))
        }.value
        guard let size, isCurrentProfile(profile) else { return false }
        thumbCache.removeObject(forKey: id.uuidString as NSString)
        fullCache.removeObject(forKey: id.uuidString as NSString)
        printCache[id] = nil
        modify(id) { pin in
            pin.width = size.0
            pin.height = size.1
            pin.hasFeaturePrint = false
            pin.dhash = nil
            pin.duplicateOfID = nil
            pin.needsAnalysis = true
            pin.pictureRevision += 1   // every view showing the picture loads it again
        }
        // Another picture now: no pin is a look-alike of it any more (the AI's look checks again).
        dropDuplicateLinks(pointingAt: [id])
        scheduleSave()
        startAnalysisIfNeeded()
        return true
    }

    /// Changes a link pin's address (cleaned when "Clean links" is on) and, when `title` is given,
    /// its title: a non-empty one becomes the person's title; "" means the person cleared the title
    /// (theirs, the AI's or the page's): the site's name comes back as the AI's title, as for a new
    /// link, and — when previews are allowed — the page is fetched again so its own title replaces
    /// it. Another page's address (not just other tracking) drops everything the old page was:
    /// its preview picture and description, and what reading it found (its text, kind — article,
    /// YouTube… — writer, date, site, comments, views and length: `Pin.clearReading`). The new page
    /// is then read like a new link (`readLink`: read fully when that is on, else its preview is
    /// fetched), the title too unless the person typed one; its `pictureRevision` goes up, with or
    /// without a preview picture.
    /// Returns at once whether anything changed: the change is saved straight away, and the
    /// reading goes on in the background (a reading still under way for the old page is dropped
    /// when it ends, see `previewStillWanted`).
    @discardableResult
    func updateLinkPin(_ id: UUID, url: URL, title: String?) async -> Bool {
        guard let pin = pin(id), pin.isLink, !pin.isDeleted else { return false }
        let address = keptLink(url).absoluteString
        let old = pin.linkURL ?? ""
        let samePage = LibraryStore.pageKey(old) == LibraryStore.pageKey(address)
        let typed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle: String? = (typed?.isEmpty ?? true) ? nil : typed
        let siteName = LibraryStore.siteName(of: address)
        // Cleared: back to the site's name, unless that is the AI's title already (nothing to do).
        let clearsTitle = typed?.isEmpty == true && !(pin.titleIsAIOwned && pin.title == siteName)
        let retitles = newTitle.map { (wanted: String) -> Bool in wanted != pin.title || !pin.titleEditedByUser } ?? false
        guard address != old || retitles || clearsTitle else { return false }
        if !samePage { dropPreview(of: id) }
        let hadPreview = pin.hasPreview
        modify(id) { pin in
            pin.linkURL = address
            if let newTitle {
                pin.setUserTitle(newTitle)
            } else if clearsTitle || (!samePage && !pin.titleEditedByUser) {
                // Not the person's title: the site's name until the page's own title is fetched.
                let untitled = TitleState(title: "", isAuto: false, editedByUser: false, lastAITitle: nil)
                pin.setAITitle(siteName, replacing: untitled)
            }
            if !samePage {
                pin.aiDescription = ""
                pin.aiSearchHint = nil
                // What the old page was read as never stays with the new address (a recipe link
                // would otherwise show the old video's channel, views and comments).
                pin.clearReading()
                // Another page is another picture, even with no preview yet (dropping one counted
                // already): iCloud then carries the address with the picture (see `Pin.takePictureDetails`).
                if !hadPreview { pin.pictureRevision += 1 }
            }
        }
        scheduleSave()
        // Another page: read (or its preview fetched; with previews off, looked at again by the AI).
        // A cleared title on the same page: read again only when previews are allowed (nothing to
        // look at otherwise). `readLink` falls back to the preview by itself (SmartLinks.swift).
        let settings = AppSettings.shared
        let previewsAllowed = settings.fetchLinkPreviews && !settings.offlineMode
        if !samePage || (clearsTitle && previewsAllowed) {
            Task { @MainActor [weak self] in await self?.readLink(for: id) }
        }
        return true
    }

    /// "example.com" for a link's address (what a new link pin is called until its page's title
    /// is fetched); the address itself when it has no host.
    nonisolated static func siteName(of address: String) -> String {
        Pin.host(ofLink: address) ?? address
    }

    /// Forgets a link pin's preview picture (the pin now points at another page): its files go,
    /// with everything worked out from that picture (its colours, the text read in it, its
    /// fingerprint and look-alike links), and the card shows the address until the new page's
    /// preview is fetched.
    private func dropPreview(of id: UUID) {
        guard let pin = pin(id), pin.isLink, pin.hasPreview else { return }
        let files = [imageFileURL(for: pin), thumbsURL.appendingPathComponent(pin.thumbFileName),
                     printsURL.appendingPathComponent(pin.printFileName)]
        for file in files { try? FileManager.default.removeItem(at: file) }
        thumbCache.removeObject(forKey: id.uuidString as NSString)
        fullCache.removeObject(forKey: id.uuidString as NSString)
        printCache[id] = nil
        modify(id) { pin in
            pin.hasPreview = false
            pin.width = 1
            pin.height = 1
            pin.hasFeaturePrint = false
            pin.dhash = nil
            pin.duplicateOfID = nil
            pin.colorTags = []
            pin.ocrText = ""
            pin.ocrTags = []
            pin.pictureRevision += 1
        }
        dropDuplicateLinks(pointingAt: [id])
    }

    /// No other pin points at these as its look-alike any more (they are gone, or their picture
    /// changed: a crop, a dropped link preview).
    func dropDuplicateLinks(pointingAt ids: Set<UUID>) {
        let pointing = Set(pins.filter { (pin: Pin) -> Bool in
            guard let twin = pin.duplicateOfID else { return false }
            return ids.contains(twin)
        }.map { (pin: Pin) -> UUID in pin.id })
        guard !pointing.isEmpty else { return }
        modify(pointing) { $0.duplicateOfID = nil }
    }

    /// "Clean existing links" (Settings › Links): takes the tracking out of the address of every
    /// link pin on one side of the library (the page stays the same, so its title and preview do
    /// too). Each is saved in the same form a link added now is (see `cleanedLink`). Only real
    /// changes count and are made (`LinkCleaner.hasTracking`): a host merely written in capitals
    /// is left as it is. Returns how many addresses changed.
    @discardableResult
    func cleanAllLinks(scope: PinScope = .visible) -> Int {
        var cleanedLinks: [UUID: String] = [:]
        for pin in pins(scope: scope) where pin.isLink {
            guard let link = pin.linkURL, LinkCleaner.hasTracking(link), let url = URL(string: link) else { continue }
            let kept = LibraryStore.cleanedLink(url).absoluteString
            if kept != link { cleanedLinks[pin.id] = kept }
        }
        guard !cleanedLinks.isEmpty else { return 0 }
        modify(Set(cleanedLinks.keys)) { pin in
            if let cleaned = cleanedLinks[pin.id] { pin.linkURL = cleaned }
        }
        scheduleSave()
        return cleanedLinks.count
    }

    nonisolated static func firstLine(of text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    /// The text a title can be taken from: a text pin's text, a link's text (an article's, or its
    /// description — with no Markdown marks, see `plainLines`), what is said in a video (the start
    /// of its transcript, which says what it is about), or the text read in a picture.
    nonisolated static func titleText(of pin: Pin) -> String {
        if pin.isText { return pin.textBody }
        if pin.isLink { return LibraryStore.plainLines(of: LibraryStore.linkText(of: pin)) }
        if pin.hasSpokenWords { return pin.spokenText(limit: TranscriptText.titleLimit) }
        return pin.ocrText
    }

    /// `text` as plain lines: no `#`, `>`, `-`, `*` marks at the start of a line, no bold or code
    /// marks, links written `[words](address)` reduced to their words, lines that are only a web address left
    /// out — so a title made of a line of an article never shows "## Flour" or a bare address.
    nonisolated static func plainLines(of text: String) -> String {
        let opening = CharacterSet(charactersIn: "#>*-_•").union(.whitespaces)   // (a "#" at the end stays: "C#")
        let closing = CharacterSet(charactersIn: "*_").union(.whitespaces)
        let lines: [String] = text.components(separatedBy: .newlines).compactMap { (raw: String) -> String? in
            var linked = raw.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            for emphasis in ["**", "__", "`"] { linked = linked.replacingOccurrences(of: emphasis, with: "") }
            let start = linked.unicodeScalars.firstIndex { !opening.contains($0) } ?? linked.unicodeScalars.endIndex
            let line = String(linked.unicodeScalars[start...]).trimmingCharacters(in: closing)
            if line.isEmpty { return nil }
            let isAddress = line.hasPrefix("http") && !line.contains(" ")
            return isAddress ? nil : line
        }
        return lines.joined(separator: "\n")
    }

    /// Whether a link pin has text to go on (`linkText(of:)` is not empty, blanks aside).
    nonisolated static func hasLinkText(_ pin: Pin) -> Bool {
        pin.isLink && !linkText(of: pin).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the AI names and tags a pin from (see `AnalysisPath`). The rule of owner's bug 16:
    /// a link with a preview picture and text is named and tagged from that text first; a link
    /// with no text keeps the picture's way; a text pin or a link with no picture has only text.
    /// A video with a transcript (round 15, VideoTranscripts.swift) is treated like a link with
    /// text: what is said in it comes first, its poster second.
    nonisolated static func analysisPath(for pin: Pin) -> AnalysisPath {
        if pin.isText || (pin.isLink && !pin.hasPreview) { return .text }
        return hasLinkText(pin) || pin.hasSpokenWords ? .pictureAndText : .picture
    }

    /// How sure the AI is of a word taken from a pin's own text (a link's, or what is said in a
    /// video): above the picture's usual tags, below what the person wrote themselves.
    nonisolated static let linkTextTagConfidence: Double = 0.8

    /// The text a pin's own key words (its tags) are taken from first: a link's text, or what is
    /// said in a video — with the small words and the "um"s of speech left out, so a talk's tags
    /// say what it is about and not how it is said (`TranscriptText.keywordText`).
    nonisolated static func tagText(of pin: Pin) -> String {
        if pin.isVideo { return TranscriptText.keywordText(of: pin.spokenText(limit: TranscriptText.tagLimit)) }
        return linkText(of: pin)
    }

    /// A pin's tags when it has text of its own (a link's, or a video's transcript): the key words
    /// of the text (and the title's words) first, the picture's own tags after them — none of them
    /// twice. A link with no text: the picture's tags, then the words of the page's title (as
    /// before), a little less sure.
    nonisolated static func linkTags(of pin: Pin, pictureTags: [TagScore]) -> [TagScore] {
        let words = VisionAnalyzer.keywords(fromText: tagText(of: pin) + "\n" + pin.title)
        var result: [TagScore] = []
        if analysisPath(for: pin) == .pictureAndText {
            result = words.map { (word: String) -> TagScore in TagScore(label: word, confidence: linkTextTagConfidence) }
            for tag in pictureTags where !result.contains(where: { (own: TagScore) -> Bool in own.label == tag.label }) {
                result.append(tag)
            }
            return result
        }
        result = pictureTags
        for word in words where !result.contains(where: { (own: TagScore) -> Bool in own.label == word }) {
            result.append(TagScore(label: word, confidence: 0.55))
        }
        return result
    }

    /// The words of a pin's tags that came from the picture, not from its text (a link's tags hold
    /// both, text first): what the title request calls "detected in the preview picture".
    nonisolated static func pictureLabels(of pin: Pin) -> [String] {
        let own = Set(VisionAnalyzer.keywords(fromText: tagText(of: pin) + "\n" + pin.title))
        return pin.aiTags.map { (tag: TagScore) -> String in tag.label }.filter { (label: String) -> Bool in !own.contains(label) }
    }

    /// The link's text that goes to the cloud model with the picture ("" when the pin isn't named
    /// from its text, see `analysisPath`), at most `CloudAI.maximumPageText` characters. Only a
    /// link's: what is said in a video is written down on the device and goes nowhere (the
    /// Settings text says so), so the cloud model only ever sees a video's poster.
    nonisolated static func textForCloud(of pin: Pin) -> String {
        guard pin.isLink, analysisPath(for: pin) == .pictureAndText else { return "" }
        return String(titleText(of: pin).prefix(CloudAI.maximumPageText))
    }

    /// A link's description after the cloud model answered: a link's description is the page's
    /// own words (the AI names and tags the link from it, see `linkText`), so the model's never
    /// goes in it — the model would otherwise read its own sentence back as "the page's text" at
    /// the next look. For every other kind of pin the model's description is the one kept.
    nonisolated static func descriptionAfterCloud(current: String, cloud: String?, isLink: Bool) -> String {
        if isLink { return current }
        return cloud ?? ""
    }

    /// The text a link pin has to go on: the article's text (or a video's description) when the
    /// link was read fully, else its short description. Capped, so a long article never slows the
    /// AI or a search down (the whole text still shows on the pin's page).
    nonisolated static func linkText(of pin: Pin, limit: Int = 4000) -> String {
        let body = pin.textBody
        if body.isEmpty { return pin.aiDescription }
        return body.count > limit ? String(body.prefix(limit)) : body
    }

    /// The on-device title for a pin. A text pin is titled by the first line of its text that
    /// doesn't only repeat the person's own words; a link with text (`.pictureAndText`) the same
    /// from the first lines of its text (when all of them only repeat the person's words: from its
    /// tags, which start with the text's key words); everything else by `TitleGenerator.tagBasedTitle`
    /// — also a video with a transcript: the first line of a talk is a greeting, not a name, so it is
    /// named from the key words of what is said (they lead its tags, see `linkTags`).
    func quickTitle(for pin: Pin, tags: [TagScore], text: String, context: TitleContext) -> String {   // (not private: used by LibraryAnalysis.swift)
        let fromLink = pin.isLink && LibraryStore.analysisPath(for: pin) == .pictureAndText
        guard pin.isText || fromLink else {
            return TitleGenerator.tagBasedTitle(tags: tags, ocrText: text, context: context)
        }
        let lines = (pin.isText ? pin.textBody : LibraryStore.titleText(of: pin)).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
        let personal = TitleGenerator.contextWords(context)
        let fresh = lines.first(where: { !TitleGenerator.isEcho($0, contextWords: personal) })
        // (A text pin's own first line is its title even when it repeats the person's words.)
        if let line = fresh ?? (pin.isText ? lines.first : nil) {
            return TitleGenerator.shorten(line, to: 50)
        }
        // No usable line: the tags (a link's start with its text's words), else the person's words.
        return TitleGenerator.tagBasedTitle(tags: tags, ocrText: "", context: context)
    }

    func addTags(_ newTags: [String], to ids: Set<UUID>) {
        let cleaned = newTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        modify(ids) { pin in
            for tag in cleaned where !pin.tags.contains(tag) { pin.tags.append(tag) }
        }
        scheduleSave()
    }

    func removeTag(_ tag: String, from ids: Set<UUID>) {
        modify(ids) { $0.tags.removeAll { $0 == tag } }
        scheduleSave()
    }

    // MARK: Tag manager

    /// Your own tags with how many pins of the scope carry each, most used first.
    func userTagCounts(scope: PinScope = .visible) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pin in pins(scope: scope) { for tag in pin.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { (tag: $0.key, count: $0.value) }
    }

    /// Every pin of a scope, including the ones in Recently Deleted (tag edits reach those too).
    private func allPins(scope: PinScope) -> [Pin] {
        let secret = secretCache
        let wantHidden = scope == .hidden
        return pins.filter { LibraryStore.isHidden($0, secretBoards: secret) == wantHidden }
    }

    func renameTag(_ tag: String, to newName: String, scope: PinScope = .visible) {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty, target != tag else { return }
        mergeTags([tag], into: target, scope: scope)
    }

    /// Replaces every listed tag with `target` on every pin of the scope (duplicates collapse).
    func mergeTags(_ tags: [String], into target: String, scope: PinScope = .visible) {
        let cleaned = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return }
        let sources = Set(tags)
        let affected = Set(allPins(scope: scope).filter { pin in pin.tags.contains { sources.contains($0) } }.map { $0.id })
        modify(affected) { pin in
            var replaced: [String] = []
            for existing in pin.tags {
                let value = sources.contains(existing) ? cleaned : existing
                if !replaced.contains(value) { replaced.append(value) }
            }
            pin.tags = replaced
        }
        scheduleSave()
    }

    func deleteTag(_ tag: String, scope: PinScope = .visible) {
        let affected = Set(allPins(scope: scope).filter { $0.tags.contains(tag) }.map { $0.id })
        modify(affected) { $0.tags.removeAll { $0 == tag } }
        scheduleSave()
    }

    // MARK: Board membership (a pin can be on several boards)

    /// Puts the pins on a board in addition to the boards they are already on. On a normal
    /// board a pin hidden on its own becomes a normal pin again; one that is on a hidden board
    /// stays hidden (filed on the normal board out of sight).
    /// Nested boards (owner's idea 4, see `BoardMembership`): a pin already on a sub-board of this
    /// board is not added (it counts as on this board already), and a pin on a board this one sits
    /// in moves down — the parent membership goes. Nothing is ever on both. The answer says how
    /// many pins were put on the board plainly, how many were left alone because they are on a
    /// sub-board, and how many moved down (for the callers' toasts).
    @discardableResult
    func addPins(_ ids: Set<UUID>, to boardID: UUID, reason: String? = nil) -> (added: Int, alreadyBelow: Int, movedDown: Int) {
        let secret = secretCache
        let visibleTarget = !secret.contains(boardID)
        let changes = membershipChanges(for: ids, adding: boardID)
        // Stamped only when the board will show one of its newcomers.
        let newcomers = ids.compactMap { pin($0) }.filter { (pin: Pin) -> Bool in
            guard let kind = changes[pin.id]?.kind else { return false }
            return kind == .added || kind == .movedDown
        }
        let showsNewcomer = newcomers.contains { newcomer in
            !visibleTarget || !newcomer.boardIDs.contains { secret.contains($0) }
        }
        var leftBoards: Set<UUID> = []
        for change in changes.values { leftBoards.formUnion(change.left) }
        modify(ids) { pin in
            if let change = changes[pin.id], change.kind == .added || change.kind == .movedDown {
                pin.boardIDs = change.boardIDs
                if let reason { pin.placementReason = reason }
            }
            if visibleTarget, !pin.boardIDs.contains(where: { secret.contains($0) }) {
                pin.isHidden = false
                pin.boardsBeforeHiding = []
            }
        }
        if showsNewcomer { stampBoards(edited: leftBoards.union([boardID]), added: [boardID]) }
        scheduleSave()
        return LibraryStore.count(changes)
    }

    /// How each of these pins' boards would change if it were added to `boardID`.
    private func membershipChanges(for ids: Set<UUID>, adding boardID: UUID) -> [UUID: BoardMembership.Change] {
        let secret = secretCache
        let below = Set(descendants(of: boardID))
        let above = Set(path(to: boardID).map { $0.id }).subtracting([boardID])
        var changes: [UUID: BoardMembership.Change] = [:]
        for id in ids {
            guard let found = pin(id) else { continue }
            changes[id] = BoardMembership.adding(to: boardID, current: found.boardIDs, below: below, above: above, secret: secret)
        }
        return changes
    }

    private static func count(_ changes: [UUID: BoardMembership.Change]) -> (added: Int, alreadyBelow: Int, movedDown: Int) {
        var result = (added: 0, alreadyBelow: 0, movedDown: 0)
        for change in changes.values {
            switch change.kind {
            case .added: result.added += 1
            case .alreadyBelow: result.alreadyBelow += 1
            case .movedDown: result.movedDown += 1
            case .alreadyOn: break
            }
        }
        return result
    }

    /// Keeps only the deepest boards of pins that are on a board and on one inside it (the rule
    /// above, for data made before it existed, brought by an iCloud sync or an import, or left by
    /// merging): the parent membership goes, the pin shows on the parent through its sub-board.
    /// Without `ids`, every pin is looked at. It is a tidy-up, not an edit: pins keep their change
    /// dates (a newer edit on another device still wins in iCloud). Returns how many pins changed.
    @discardableResult
    func tidyNestedMemberships(for ids: Set<UUID>? = nil) -> Int {
        let ancestors = BoardMembership.ancestors(of: boards)
        let secret = secretCache
        var updated = pins
        var changed = 0
        for index in updated.indices {
            let boardIDs = updated[index].boardIDs
            guard boardIDs.count > 1, ids?.contains(updated[index].id) ?? true else { continue }
            let tidy = BoardMembership.deepest(boardIDs, ancestors: ancestors, secret: secret)
            guard tidy != boardIDs else { continue }
            updated[index].boardIDs = tidy
            changed += 1
        }
        if changed > 0 { pins = updated }
        return changed
    }

    /// Replaces every board membership with this one board (nil = Unsorted of the
    /// pin's own scope: a hidden pin stays hidden). On a normal board a hidden pin
    /// becomes a normal pin again.
    func movePins(_ ids: Set<UUID>, to boardID: UUID?) {
        let secret = secretCache
        let visibleTarget = boardID.map { !secret.contains($0) } ?? false
        let moving = ids.compactMap { pin($0) }
        var left = Set(moving.flatMap { shownBoardIDs(for: $0) })   // a board that never showed a pin isn't touched
        if let boardID {
            left.remove(boardID)
            if moving.contains(where: { !$0.isOn(boardID) }) { stampBoards(edited: left, added: [boardID]) } else { stampBoards(edited: left) }
        } else {
            stampBoards(edited: left)
        }
        modify(ids) { pin in
            let wasHidden = LibraryStore.isHidden(pin, secretBoards: secret)
            if wasHidden, !visibleTarget {
                // Moved within Hidden: only its hidden boards are replaced. Normal boards it is
                // filed on out of sight stay as they are (for Unhide, or for when its board is
                // unhidden), and with no hidden board left it stays hidden on its own.
                let outOfSight = pin.boardIDs.filter { !secret.contains($0) }
                pin.boardIDs = (boardID.map { [$0] } ?? []) + outOfSight
                if boardID == nil { pin.isHidden = true }
            } else {
                pin.boardIDs = boardID.map { [$0] } ?? []
                if visibleTarget {
                    pin.isHidden = false
                    pin.boardsBeforeHiding = []
                }
            }
            pin.placementReason = nil
        }
        scheduleSave()
    }

    /// Takes the pins off one board. A hidden pin taken off its last hidden board stays hidden
    /// (see `keepHidden`): nothing done on the hidden side drops a pin into the normal library.
    func removePins(_ ids: Set<UUID>, from boardID: UUID) {
        let secret = secretCache
        if ids.contains(where: { id in pin(id).map { shownBoardIDs(for: $0).contains(boardID) } ?? false }) {
            stampBoards(edited: [boardID])
        }
        modify(ids) { pin in
            let wasHidden = LibraryStore.isHidden(pin, secretBoards: secret)
            pin.boardIDs.removeAll { $0 == boardID }
            if pin.boardIDs.isEmpty { pin.placementReason = nil }
            if wasHidden, !LibraryStore.isHidden(pin, secretBoards: secret) {
                LibraryStore.keepHidden(&pin, secretBoards: secret)
            }
        }
        scheduleSave()
    }

    // MARK: Hiding single pins

    /// Hides pins: each one remembers the normal boards it was on (for Unhide),
    /// leaves them (hidden boards stay), and goes to the Hidden section.
    func hidePins(_ ids: Set<UUID>) {
        let secret = secretCache
        let left = Set(ids.compactMap { pin($0) }.flatMap { $0.boardIDs }.filter { !secret.contains($0) })
        stampBoards(edited: left)
        modify(ids) { pin in
            LibraryStore.keepHidden(&pin, secretBoards: secret)
        }
        // A normal board must not keep a hidden pin as its cover.
        for board in boards where !secret.contains(board.id) {
            if let cover = board.coverPinID, ids.contains(cover) { setCover(nil, for: board.id) }
        }
        separateDuplicatesAcrossHiddenLine(refresh: true)
        scheduleSave()
    }

    /// Brings hidden pins back: onto the remembered boards that still exist. A pin on a
    /// hidden board would stay hidden, so it leaves its hidden boards (keeping its normal
    /// ones, or going to the normal Unsorted): Unhide always shows it again.
    func unhidePins(_ ids: Set<UUID>) {
        let secret = secretCache
        let existing = Set(boards.map { $0.id })
        var returnedTo: Set<UUID> = []
        // Back onto the remembered boards that still exist and are still normal ones. Stamped:
        // the normal boards that show the pins again, and the hidden boards they leave.
        let returnable = existing.subtracting(secret)
        var leftHidden: Set<UUID> = []
        for coming in ids.compactMap({ self.pin($0) }) {
            for boardID in coming.boardsBeforeHiding where returnable.contains(boardID) && !coming.isOn(boardID) { returnedTo.insert(boardID) }
            for boardID in coming.boardIDs {
                if secret.contains(boardID) { leftHidden.insert(boardID) } else { returnedTo.insert(boardID) }
            }
        }
        stampBoards(edited: returnedTo.union(leftHidden), added: returnedTo)
        modify(ids) { pin in
            for boardID in pin.boardsBeforeHiding where returnable.contains(boardID) && !pin.boardIDs.contains(boardID) {
                pin.boardIDs.append(boardID)
            }
            pin.boardsBeforeHiding = []
            pin.isHidden = false
            // Any hidden board would keep it hidden: it leaves those boards (and goes to
            // the normal Unsorted when no board is left).
            if pin.boardIDs.contains(where: { secret.contains($0) }) {
                pin.boardIDs.removeAll { secret.contains($0) }
                if pin.boardIDs.isEmpty { pin.placementReason = nil }
            }
        }
        tidyNestedMemberships(for: ids)   // (a remembered parent board and a sub-board: only the inner one stays)
        separateDuplicatesAcrossHiddenLine(refresh: true)
        scheduleSave()
    }

    /// A duplicate pair never spans the hidden line: links between a hidden and a
    /// normal pin (either direction) are dropped. With `refresh` (or when a link was
    /// dropped) everything is checked again, each side on its own.
    func separateDuplicatesAcrossHiddenLine(refresh: Bool) {   // (not private: used by LibraryBoards.swift)
        let hiddenIDs = scopeSplit.hiddenIDs
        let crossing = Set(livePins.compactMap { pin -> UUID? in
            guard let twin = pin.duplicateOfID else { return nil }
            return hiddenIDs.contains(pin.id) != hiddenIDs.contains(twin) ? pin.id : nil
        })
        if !crossing.isEmpty { modify(crossing) { $0.duplicateOfID = nil } }
        if refresh || !crossing.isEmpty { scheduleDuplicateRefresh() }
    }

    /// One re-check a moment later, however many changes come in a row (e.g. hiding several boards).
    private func scheduleDuplicateRefresh() {
        duplicateRefreshTask?.cancel()
        duplicateRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshDuplicates()
        }
    }
}
