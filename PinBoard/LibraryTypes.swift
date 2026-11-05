//
//  LibraryTypes.swift  —  PinBoard
//
//  The small types that go with `LibraryStore`: what an import did (`ImportSummary`) and the items
//  waiting for it (`PendingImport`), the library's folders and backups, `LibraryWriter` (saves
//  library.json in order), the nested-board rule, how the AI looks at a pin, and what can be
//  dropped onto the app. None of them needs the store itself, so they are a file of their own.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

/// A board the "Start here" card offers to create from the library's own tags.
struct BoardProposal: Identifiable, Hashable {
    var name: String
    var tag: String
    var pinIDs: [UUID]
    var id: String { tag }
}

/// What happened to a batch of imports.
struct ImportSummary: Sendable {
    var imported = 0
    var skipped = 0        // duplicates the person chose to skip, or unreadable items
    var alreadyHad = 0     // PinBoard's own cards dropped back in (put on the board instead)
    var addedExisting = 0  // look-alikes the person chose to put on the boards instead of importing
    var boardsCreated = 0  // folder imports: boards made for sub-folders / re-created from an export
    var newPinIDs: [UUID] = []   // the pins made (the back-up reminder counts the normal ones among them)
}

/// What became of one prepared item (see `LibraryStore.commitPendingItem`); `.imported` carries
/// the new pin's id.
enum PendingImportOutcome: Sendable {
    case imported(UUID), alreadyHad, addedExisting, skipped
}

extension ImportSummary {
    mutating func count(_ outcome: PendingImportOutcome) {
        switch outcome {
        case .imported(let id):
            imported += 1
            newPinIDs.append(id)
        case .alreadyHad: alreadyHad += 1
        case .addedExisting: addedExisting += 1
        case .skipped: skipped += 1
        }
    }
}

/// A PinBoard export's original record, re-created as it was (ids, tags, notes, boards…).
struct ExportedPin: Sendable {
    var record: Pin
    var featurePrint: Data?
    var exif: Data?
    var previewData: Data?   // link pins: the exported preview picture
}

/// One thing waiting to be imported, after it was read and checked for duplicates.
struct PendingImport: Identifiable, @unchecked Sendable {
    enum Payload {
        case image(Data, title: String, sourceURL: String?, credit: String?)
        case video(URL, poster: VideoPoster, title: String)
        case text(title: String, body: String)
        case link(URL)
    }
    let id = UUID()
    var payload: Payload
    /// The library (profile) it was read for, set by every `prepare…` step. It is committed only
    /// into that library: its look-alike and its boards are that library's (see `commitImports`).
    /// Why: a batch waiting for its duplicate question is not library work, so another window can
    /// switch profiles meanwhile.
    var profileID: UUID
    var duplicateOf: Pin? = nil      // a pin that looks the same (near-duplicate)
    var identicalTo: Pin? = nil      // byte-for-byte one of PinBoard's own files (a card dropped back in)
    /// Folder imports: the picture is still in the chosen folder (the .image payload's data is
    /// empty) and is read when committed. That file is never changed or deleted.
    var sourceFile: URL? = nil
    /// Folder imports: the sub-folder names that become the board (created on commit);
    /// [] = Unsorted; nil = the batch's boards.
    var destinationPath: [String]? = nil
    /// Folder imports of a PinBoard export: the original record.
    var exported: ExportedPin? = nil
    /// The title was typed (the text-pin editor).
    var titleFromUser: Bool = false
    /// What reading the link found (Settings › Links › "Read links fully", see SmartLinks.swift):
    /// an article's text, a video's details, a Pinterest pin's links… Set only for links that were
    /// read before the import (a `.link` payload, or the `.image` / `.video` payload the link's
    /// picture or video became); nil for everything else. Applied when the item is committed.
    var resolvedLink: ResolvedLink? = nil

    var isDuplicate: Bool { duplicateOf != nil }
}

extension PendingImport {
    /// Whether the item lands on at least one board (so "Add the existing pin" makes sense):
    /// a non-empty batchBoardIDs, a non-empty destinationPath, or an exported record with boards.
    func landsOnBoard(batchBoardIDs: [UUID]) -> Bool {
        if let exported { return !exported.record.boardIDs.isEmpty }
        if let destinationPath { return !destinationPath.isEmpty }
        return !batchBoardIDs.isEmpty
    }
}

/// The current profile's folders.
struct LibraryLocation: Sendable {
    var root: URL
    var images: URL { root.appendingPathComponent("images", isDirectory: true) }
    var thumbs: URL { root.appendingPathComponent("thumbs", isDirectory: true) }
    var prints: URL { root.appendingPathComponent("prints", isDirectory: true) }
    var exif: URL { root.appendingPathComponent("exif", isDirectory: true) }
    var videos: URL { root.appendingPathComponent("videos", isDirectory: true) }
    var library: URL { root.appendingPathComponent("library.json") }
    var previousBackup: URL { root.appendingPathComponent("library.previous.json") }
    var dailyBackup: URL { root.appendingPathComponent("library.daily.json") }
    /// The list as it was just before the last "Restore" (see `LibraryStore.restore`).
    var beforeRestoreBackup: URL { root.appendingPathComponent("library.before-restore.json") }
    var allFolders: [URL] { [images, thumbs, prints, exif, videos] }

    func createFolders() {
        for url in [root] + allFolders {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

/// A backup file the person can restore.
struct LibraryBackup: Identifiable, Sendable {
    var id: String { url.path }
    var url: URL
    var label: String
    var savedAt: Date
    var pinCount: Int
}

/// Writes library.json: one save at a time, and never an older save over a newer one.
///
/// Why: a save is encoded in the background (a big library takes a moment), while the save made
/// when the app goes to the background is written straight away. Without this, an older
/// background save that finished encoding late could land on top of the newer file. Every save
/// has a number that counts up (its generation); the writer remembers the newest one it wrote
/// for each library file and drops anything older. Both save paths call `write`, which holds a
/// lock while it checks, keeps the safety copies and writes — so two writes never overlap, and
/// the synchronous save simply waits for a background write that is already under way.
/// Each save also says it is coming (`announce`) before it waits for that lock: an older save
/// that gets the lock first, while a newer one is waiting, then skips its writing altogether
/// (instead of writing a file that the newer save replaces a moment later).
final class LibraryWriter: @unchecked Sendable {   // @unchecked: `lock` guards `newestWritten`, `requestLock` guards `newestRequested`
    private let lock = NSLock()            // one write at a time (held while writing)
    private let requestLock = NSLock()     // held only for a moment, never while writing
    private var newestWritten: [String: Int] = [:]     // library.json path → generation written last
    private var newestRequested: [String: Int] = [:]   // library.json path → newest generation on its way

    /// Notes that a save of `generation` is on its way to `target`. `write` does this first thing,
    /// before it waits for the lock.
    func announce(_ generation: Int, for target: LibraryLocation) {
        requestLock.lock()
        defer { requestLock.unlock() }
        let key = target.library.path
        newestRequested[key] = max(newestRequested[key] ?? generation, generation)
    }

    /// The newest generation announced for a library file (0: none).
    private func newestAnnounced(for key: String) -> Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        return newestRequested[key] ?? 0
    }

    /// Writes `data` (generation `generation`) as `target`'s library, unless a newer generation
    /// was written there already or is on its way (then this one is skipped before it touches the
    /// disk: the newer one is written instead). Returns whether it wrote.
    @discardableResult
    func write(_ data: Data, generation: Int, to target: LibraryLocation) -> Bool {
        announce(generation, for: target)   // before waiting: an older save that is waiting too skips its writing
        lock.lock()
        defer { lock.unlock() }
        let key = target.library.path
        if let newest = newestWritten[key], newest >= generation { return false }
        if newestAnnounced(for: key) > generation { return false }
        LibraryWriter.keepSafetyCopies(at: target)
        guard (try? data.write(to: target.library, options: .atomic)) != nil else { return false }
        newestWritten[key] = generation
        return true
    }

    /// Writes `data` (the list as it is now) as `target`'s "Before the last restore" copy — under
    /// the same lock, so it never lands in the middle of a save. Returns whether it was written.
    @discardableResult
    func keepCopyBeforeRestore(_ data: Data, at target: LibraryLocation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let copy = target.beforeRestoreBackup
        guard (try? data.write(to: copy, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)
        return true
    }

    /// Keeps a copy from about ten minutes ago ("Earlier today") and one from the day before
    /// ("Daily copy"), so a bad save or a mistake is never the only version. When a copy was made
    /// is read from its own file date (set when it is made), so the copies are replaced by their
    /// age alone — not by the first save after every launch, and the same for every profile.
    private static func keepSafetyCopies(at target: LibraryLocation) {
        guard FileManager.default.fileExists(atPath: target.library.path) else { return }
        let now = Date()
        if age(of: target.previousBackup, now: now) > 600 {
            replace(target.previousBackup, withCopyOf: target.library, now: now)
        }
        if age(of: target.dailyBackup, now: now) > 86_400 {
            replace(target.dailyBackup, withCopyOf: target.library, now: now)
        }
    }

    /// Seconds since a copy was made. A missing copy, or one dated in the future (the clock was
    /// changed), counts as old, so it is made again.
    private static func age(of copy: URL, now: Date) -> TimeInterval {
        let attributes = try? FileManager.default.attributesOfItem(atPath: copy.path)
        guard let made = attributes?[.modificationDate] as? Date else { return .infinity }
        let seconds = now.timeIntervalSince(made)
        return seconds < 0 ? .infinity : seconds
    }

    private static func replace(_ copy: URL, withCopyOf source: URL, now: Date) {
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else { return }
        // The copy's date records when it was made (a copy can otherwise keep its source's date).
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: copy.path)
    }
}

/// The rule for pins on nested boards (owner's idea 4): a pin on a sub-board counts as being on its
/// parent boards already, so it is never listed as on both — adding a pin to a board it is already
/// inside (on a sub-board) changes nothing, and adding it to a sub-board of a board it is on moves
/// it down (the parent membership goes). Plain functions on values, so the harness can test them.
/// A board and a sub-board that are on different sides of the hidden line (a normal board with a
/// hidden sub-board) are never treated as nested: what is hidden stays out of the normal side's
/// words and counts.
enum BoardMembership {
    /// What adding a pin to a board does.
    enum Kind: Sendable, Equatable {
        case alreadyOn      // it is on that board: nothing to do
        case alreadyBelow   // it is on a sub-board of it: covered, nothing is added
        case added          // put on the board; it leaves no other board
        case movedDown      // put on the board and taken off a board the target sits in
    }

    /// The outcome for one pin: what happened, the pin's boards afterwards, and the boards it left.
    struct Change: Sendable, Equatable {
        var kind: Kind
        var boardIDs: [UUID]
        var left: [UUID]
    }

    /// Whether `ancestor` and `descendant` (one inside the other) count as nested for the rule:
    /// not when a normal board holds a hidden sub-board (that is across the hidden line).
    nonisolated static func areNested(ancestor: UUID, descendant: UUID, secret: Set<UUID>) -> Bool {
        secret.contains(ancestor) || !secret.contains(descendant)
    }

    /// What adding a pin on `current` boards to `target` does. `below`: every board inside the
    /// target; `above`: every board the target sits in; `secret`: the hidden boards.
    nonisolated static func adding(to target: UUID, current: [UUID], below: Set<UUID>, above: Set<UUID>,
                                   secret: Set<UUID>) -> Change {
        if current.contains(target) { return Change(kind: .alreadyOn, boardIDs: current, left: []) }
        let covering = current.contains { (id: UUID) -> Bool in
            below.contains(id) && areNested(ancestor: target, descendant: id, secret: secret)
        }
        if covering { return Change(kind: .alreadyBelow, boardIDs: current, left: []) }
        let leaving = current.filter { (id: UUID) -> Bool in
            above.contains(id) && areNested(ancestor: id, descendant: target, secret: secret)
        }
        let kept = current.filter { (id: UUID) -> Bool in !leaving.contains(id) }
        return Change(kind: leaving.isEmpty ? .added : .movedDown, boardIDs: kept + [target], left: leaving)
    }

    /// Each board's parents, nearest first (a damaged file with a loop can't hang it).
    nonisolated static func ancestors(of boards: [Board]) -> [UUID: [UUID]] {
        var parentOf: [UUID: UUID] = [:]
        for board in boards {
            if let parent = board.parentID { parentOf[board.id] = parent }
        }
        var result: [UUID: [UUID]] = [:]
        for board in boards {
            var chain: [UUID] = []
            var current = parentOf[board.id]
            while let id = current, chain.count < 50, !chain.contains(id), id != board.id {
                chain.append(id)
                current = parentOf[id]
            }
            result[board.id] = chain
        }
        return result
    }

    /// A pin's boards with the nested ones dropped: a board goes when the pin is also on one of
    /// the boards inside it (the deepest stay). Order is kept. `ancestors`: see `ancestors(of:)`.
    /// A damaged tree can have a loop (two devices moved A into B and B into A before they synced):
    /// two boards that are each other's parent are not "one inside the other", so a pin on both
    /// keeps both, and a pin never ends up with fewer boards than it needs (never none). A pin that
    /// is on a board and on one inside it, with a loop elsewhere above them, is still tidied.
    nonisolated static func deepest(_ boardIDs: [UUID], ancestors: [UUID: [UUID]], secret: Set<UUID>) -> [UUID] {
        guard boardIDs.count > 1 else { return boardIDs }
        var covered: Set<UUID> = []
        for inner in boardIDs {
            for outer in ancestors[inner] ?? [] where boardIDs.contains(outer) {
                let eachOther: Bool = (ancestors[outer] ?? []).contains(inner)   // a loop: neither is the deeper one
                if eachOther { continue }
                if areNested(ancestor: outer, descendant: inner, secret: secret) { covered.insert(outer) }
            }
        }
        // (Never drop every board: a hidden pin with no hidden board would fall into the normal library.)
        if covered.isEmpty || covered.count >= boardIDs.count { return boardIDs }
        return boardIDs.filter { (id: UUID) -> Bool in !covered.contains(id) }
    }
}

/// How the AI looks at a pin and what it names and tags it from (owner's bug 16: a link's own text
/// must be part of it — the most important part, when there is text). Plain values, so the harness
/// can test the choice.
enum AnalysisPath: Sendable, Equatable {
    /// A text pin, or a link with no picture: its text alone (tags are its key words).
    case text
    /// A link with a preview picture and text (an article, a video's description): the picture is
    /// looked at too, but the name and the tags come from the text first, the picture's second.
    case pictureAndText
    /// Everything else with a picture: named and tagged from what is seen in it.
    case picture
}

/// What can be dropped onto the app: pictures, videos, text, links — and the
/// app's own pins (a card dragged onto a board tile carries a `pinboard://` link).
enum DropPayload: Transferable, Sendable {
    case image(Data)
    case video(URL)
    case text(String)
    case url(URL)
    case pin(UUID)

    static let referenceScheme = "pinboard"

    /// The link a dragged card carries so the app recognises its own pins.
    static func reference(for pinID: UUID) -> URL {
        URL(string: "\(referenceScheme)://pin/\(pinID.uuidString)") ?? URL(fileURLWithPath: "/")
    }

    static func pinID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == referenceScheme else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    static var transferRepresentation: some TransferRepresentation {
        // Pictures first (a picture dragged from Safari also offers its address).
        DataRepresentation(importedContentType: .image) { (data: Data) -> DropPayload in
            DropPayload.image(data)
        }
        // The app's own cards are recognised by their reference before their file is copied.
        ProxyRepresentation(importing: { (url: URL) -> DropPayload in
            if let id = DropPayload.pinID(from: url) { return DropPayload.pin(id) }
            return DropPayload.url(url)
        })
        FileRepresentation(importedContentType: .movie) { (received: ReceivedTransferredFile) -> DropPayload in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("dropped-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return DropPayload.video(copy)
        }
        ProxyRepresentation(importing: { (text: String) -> DropPayload in
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let id = DropPayload.pinID(from: url) {
                return DropPayload.pin(id)
            }
            return DropPayload.text(text)
        })
    }
}
