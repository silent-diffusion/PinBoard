//
//  Export.swift  —  PinBoard
//
//  Export the whole library as a folder (or a zip of it) organised by board,
//  with every pin's title, tags and notes written into the JPEG's own
//  metadata; import such a folder back; save single images to Photos.
//  Each export is built in a temporary folder of its own (`ExportFolders`), can be
//  cancelled (its task), and leaves nothing behind when it is.
//

import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Photos
import Foundation

// MARK: - Export

struct ExportOutcome: Sendable {
    var folderURL: URL
    var pinCount: Int              // pins actually written (not those left out for a missing file)
    var fileCount: Int
    var missingFileCount: Int = 0  // pins left out because their picture file is missing
}

extension ExportOutcome {
    /// What Settings says once the export is made: "Ready: 12 pins in 14 files.", followed by
    /// `missingFilesNote` when pins had to be left out.
    var readyMessage: String {
        let pins = "\(pinCount) pin\(pinCount == 1 ? "" : "s")"
        let files = "\(fileCount) file\(fileCount == 1 ? "" : "s")"
        let ready = "Ready: \(pins) in \(files)."
        guard let note = missingFilesNote else { return ready }
        return ready + " " + note
    }

    /// "2 pins were left out: their files are missing." (nil when none were).
    var missingFilesNote: String? {
        if missingFileCount <= 0 { return nil }
        if missingFileCount == 1 { return "1 pin was left out: its file is missing." }
        return "\(missingFileCount) pins were left out: their files are missing."
    }
}

enum LibraryExporter {
    static let hiddenFolder = "_pinboard"   // feature prints + original EXIF, for a faithful re-import
    /// Files a folder import takes: pictures and videos (plus .txt and .url).
    static let folderImageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff"]
    static let folderVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Every export is built inside this folder (in the temporary folder), one sub-folder per kind:
    /// "Library" for Settings → Export, "Boards" for Share board…. Inside that, each export works in
    /// a folder of its own, named by a new UUID, which holds its copy and its zip: so two exports at
    /// once (in two windows, or a share cancelled and started again) never touch each other's files.
    /// The earlier exports of a kind are removed when a new one of that kind has *finished* (its zip
    /// is made) — never before, and never one still at work or started later (see `ExportFolders`).
    /// At launch the app removes what an earlier run left (`removeTemporaryExports`).
    nonisolated static var exportsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PinBoard Exports", isDirectory: true)
    }

    /// The kind folder an export builds in: a board's share (`folderName` given) or the whole library.
    nonisolated static func workFolder(forBoardShare boardShare: Bool) -> URL {
        exportsFolder.appendingPathComponent(boardShare ? "Boards" : "Library", isDirectory: true)
    }

    /// At launch: every export an earlier run of the app left (its copy and its zip — no share sheet
    /// can be offering them any more), also those that older versions left straight in the temporary
    /// folder ("PinBoard Export …", "… (PinBoard)", and their zips). An export started since launch
    /// is never touched (this runs in the background while the app is already in use).
    nonisolated static func removeTemporaryExports() {
        let files = FileManager.default
        let kinds: [URL] = [workFolder(forBoardShare: false), workFolder(forBoardShare: true)]
        let kindNames = Set(kinds.map { (kind: URL) -> String in kind.lastPathComponent })
        // Anything else in the exports folder is an older layout's.
        for entry in ExportFolders.entries(in: exportsFolder) where !kindNames.contains(entry.lastPathComponent) {
            try? files.removeItem(at: entry)
        }
        for kind in kinds { ExportFolders.shared.removeLeftovers(in: kind) }
        let temporary = files.temporaryDirectory
        guard let names = try? files.contentsOfDirectory(atPath: temporary.path) else { return }
        for name in names where name.hasPrefix("PinBoard Export ") || name.hasSuffix(" (PinBoard)") || name.hasSuffix(" (PinBoard).zip") {
            try? files.removeItem(at: temporary.appendingPathComponent(name))
        }
    }

    /// Stops an export whose task was cancelled (say its screen was closed): throws
    /// `CancellationError`. Checked before every pin and every file.
    nonisolated static func stopIfCancelled() throws {
        if Task.isCancelled { throw CancellationError() }
    }

    /// Builds "PinBoard Export <date>" (or `folderName`) in a folder of its own (see
    /// `exportsFolder`). Runs off the main thread; pass plain values in (for an export without
    /// hidden content, `LibraryStore.exportPins(includeHidden: false)` and `hiddenBoardIDs`).
    /// `progress` is called with (pins done, pins in total) as each pin is written,
    /// on the thread doing the work.
    /// Cancelling the task it runs in stops it at the next pin or file: it throws
    /// `CancellationError`, and its folder is removed with whatever was written (so is a failed one).
    /// The export counts as finished once `zip(folder:)` has made its zip.
    nonisolated static func buildFolder(pins: [Pin],
                                        boards: [Board],
                                        imagesURL: URL,
                                        printsURL: URL,
                                        exifURL: URL,
                                        videosURL: URL,
                                        libraryJSON: Data?,
                                        hiddenBoardIDs: Set<UUID> = [],
                                        folderName: String? = nil,
                                        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) throws -> ExportOutcome {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let name = folderName ?? "PinBoard Export \(formatter.string(from: Date()))"
        try stopIfCancelled()
        // This export's own folder: <kind>/<UUID>/<name>, its zip later next to <name>.
        let own = try ExportFolders.shared.makeFolder(in: workFolder(forBoardShare: folderName != nil))
        do {
            let root = own.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let outcome = try writeExport(into: root, pins: pins, boards: boards, imagesURL: imagesURL, printsURL: printsURL,
                                          exifURL: exifURL, videosURL: videosURL, libraryJSON: libraryJSON,
                                          hiddenBoardIDs: hiddenBoardIDs, progress: progress)
            try stopIfCancelled()
            return outcome
        } catch {
            // Cancelled (or failed): nothing half-built is left behind.
            ExportFolders.shared.discard(own)
            throw error
        }
    }

    /// Writes the export's files into `root` (see `buildFolder`).
    nonisolated private static func writeExport(into root: URL,
                                                pins: [Pin],
                                                boards: [Board],
                                                imagesURL: URL,
                                                printsURL: URL,
                                                exifURL: URL,
                                                videosURL: URL,
                                                libraryJSON: Data?,
                                                hiddenBoardIDs: Set<UUID>,
                                                progress: @Sendable (Int, Int) -> Void) throws -> ExportOutcome {
        // Folder for every board, nested like the boards themselves.
        var folderForBoard: [UUID: URL] = [:]
        func folder(for boardID: UUID) -> URL? {
            if let known = folderForBoard[boardID] { return known }
            guard let board = boards.first(where: { $0.id == boardID }) else { return nil }
            let parent: URL
            if let parentID = board.parentID, let parentFolder = folder(for: parentID) {
                parent = parentFolder
            } else {
                parent = root
            }
            var candidate = parent.appendingPathComponent(board.name.safeFileName, isDirectory: true)
            var counter = 2
            while folderForBoard.values.contains(candidate) {
                candidate = parent.appendingPathComponent("\(board.name.safeFileName) \(counter)", isDirectory: true)
                counter += 1
            }
            try? FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
            folderForBoard[boardID] = candidate
            return candidate
        }
        for board in boards where !hiddenBoardIDs.contains(board.id) { _ = folder(for: board.id) }
        let unsorted = root.appendingPathComponent("Unsorted", isDirectory: true)

        let boardNameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0.name) })
        var usedNames: Set<String> = []
        var fileMap: [String: String] = [:]     // pin id → relative path of its first copy
        var fileCount = 0
        var exportedPins = 0                    // "Ready: N pins" counts only the pins written
        var missingFiles = 0
        let total = pins.filter { !$0.isDeleted }.count
        var done = 0
        progress(0, total)
        for pin in pins where !pin.isDeleted {
            defer {
                done += 1
                progress(done, total)
            }
            try stopIfCancelled()
            // Pins on hidden boards only are left out entirely (when hidden boards are excluded).
            let shownBoards = pin.boardIDs.filter { !hiddenBoardIDs.contains($0) }
            if !pin.boardIDs.isEmpty, shownBoards.isEmpty { continue }
            // A file kept in iCloud only comes back first (Offloading.swift).
            OffloadIndex.bringBackIfOffloaded(pin, libraryRoot: imagesURL.deletingLastPathComponent())
            let source = imagesURL.appendingPathComponent(pin.imageFileName)
            if pin.hasImageFile, !FileManager.default.fileExists(atPath: source.path) {
                missingFiles += 1               // its picture is gone: left out (and not counted)
                continue
            }
            exportedPins += 1
            var targets = shownBoards.compactMap { folder(for: $0) }
            if targets.isEmpty {
                try? FileManager.default.createDirectory(at: unsorted, withIntermediateDirectories: true)
                targets = [unsorted]
            }
            let baseName = pin.title.isEmpty ? "Pin \(String(pin.id.uuidString.prefix(8)))" : pin.title.safeFileName
            for target in targets {
                try stopIfCancelled()
                var name = baseName
                var counter = 2
                while usedNames.contains(target.path + "/" + name) {
                    name = "\(baseName) \(counter)"
                    counter += 1
                }
                usedNames.insert(target.path + "/" + name)
                let relative: (URL) -> String = { $0.path.replacingOccurrences(of: root.path + "/", with: "") }

                if pin.isText {
                    // Text pins become plain text files: the title, a blank line, the text.
                    let destination = target.appendingPathComponent(name + ".txt")
                    // First line: the title (may be empty), then a blank line, then the text.
                    let contents = pin.title + "\n\n" + pin.textBody + "\n"
                    try? contents.write(to: destination, atomically: true, encoding: .utf8)
                    fileCount += 1
                    if fileMap[pin.id.uuidString] == nil { fileMap[pin.id.uuidString] = relative(destination) }
                    continue
                }
                if pin.isLink {
                    // Links become internet-shortcut files (they open on any computer),
                    // with the preview picture next to them when there is one.
                    let destination = target.appendingPathComponent(name + ".url")
                    let contents = "[InternetShortcut]\r\nURL=\(pin.linkURL ?? "")\r\n"
                    try? contents.write(to: destination, atomically: true, encoding: .utf8)
                    fileCount += 1
                    if fileMap[pin.id.uuidString] == nil { fileMap[pin.id.uuidString] = relative(destination) }
                    if pin.hasPreview {
                        let preview = target.appendingPathComponent(name + ".preview.jpg")
                        let boardPaths = shownBoards.compactMap { boardNameByID[$0] }
                        if !writeJPEG(from: source, to: preview, pin: pin, boardNames: boardPaths, originalProperties: nil) {
                            try? FileManager.default.copyItem(at: source, to: preview)
                        }
                        fileCount += 1
                        if fileMap[pin.id.uuidString + "#preview"] == nil { fileMap[pin.id.uuidString + "#preview"] = relative(preview) }
                    }
                    continue
                }

                let destination = target.appendingPathComponent(name + (pin.isVideo ? ".poster.jpg" : ".jpg"))
                let exifPlist = try? Data(contentsOf: exifURL.appendingPathComponent(pin.exifFileName))
                let boardPaths = shownBoards.compactMap { boardNameByID[$0] }
                if !writeJPEG(from: source, to: destination, pin: pin, boardNames: boardPaths, originalProperties: exifPlist) {
                    try? FileManager.default.copyItem(at: source, to: destination)
                }
                fileCount += 1
                if fileMap[pin.id.uuidString] == nil { fileMap[pin.id.uuidString] = relative(destination) }

                if pin.isVideo {
                    // The video itself, next to its poster frame.
                    let videoSource = videosURL.appendingPathComponent(pin.videoFileName)
                    let videoDestination = target.appendingPathComponent(name + "." + (pin.videoExtension ?? "mov"))
                    if (try? FileManager.default.copyItem(at: videoSource, to: videoDestination)) != nil {
                        fileCount += 1
                        if fileMap[pin.id.uuidString + "#video"] == nil { fileMap[pin.id.uuidString + "#video"] = relative(videoDestination) }
                    }
                }
            }
        }

        // Machine-readable copies, so the folder can be imported back exactly.
        let hidden = root.appendingPathComponent(hiddenFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: hidden.appendingPathComponent("prints"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden.appendingPathComponent("exif"), withIntermediateDirectories: true)
        for pin in pins where !pin.isDeleted {
            try stopIfCancelled()
            let print = printsURL.appendingPathComponent(pin.printFileName)
            if FileManager.default.fileExists(atPath: print.path) {
                try? FileManager.default.copyItem(at: print, to: hidden.appendingPathComponent("prints").appendingPathComponent(pin.printFileName))
            }
            let exif = exifURL.appendingPathComponent(pin.exifFileName)
            if FileManager.default.fileExists(atPath: exif.path) {
                try? FileManager.default.copyItem(at: exif, to: hidden.appendingPathComponent("exif").appendingPathComponent(pin.exifFileName))
            }
        }
        try stopIfCancelled()
        if let libraryJSON {
            try libraryJSON.write(to: root.appendingPathComponent("library.json"))
        }
        if let map = try? JSONSerialization.data(withJSONObject: fileMap, options: [.prettyPrinted, .sortedKeys]) {
            try map.write(to: root.appendingPathComponent("files.json"))
        }
        let readme = """
        PinBoard export

        Folders match your boards (sub-boards are nested folders); "Unsorted" holds pins that were on no board.
        A pin on several boards appears in each of them.
        Each JPEG carries its title (IPTC Object Name), tags (IPTC Keywords), note (IPTC Caption) and a full JSON
        record in the EXIF User Comment. Camera EXIF from the original photo is kept where it existed.
        Text pins are .txt files (title, blank line, text). Videos sit next to a ".poster.jpg" still that carries their metadata.
        Links are .url shortcut files, with a ".preview.jpg" picture when one was fetched.
        library.json, files.json and the _pinboard folder let PinBoard re-import everything exactly.
        """
        try readme.write(to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        return ExportOutcome(folderURL: root, pinCount: exportedPins, fileCount: fileCount, missingFileCount: missingFiles)
    }

    /// The most of a note that is written into a picture's own metadata (its caption, and the record
    /// in its user comment). That metadata is a convenience for other apps — library.json holds
    /// every word — and a picture's metadata blocks are small (64 KB): a long transcript in a video's
    /// note, in a script that takes three bytes a letter, would make the whole write fail, and the
    /// picture would then be copied with no metadata at all.
    nonisolated static let metadataNoteLimit = 8_000

    /// `note` as written into a picture's metadata: at most `metadataNoteLimit` characters, cut at
    /// the end of a word, with "…" when it was cut.
    nonisolated static func metadataNote(_ note: String) -> String {
        TranscriptText.shortened(note, to: metadataNoteLimit)
    }

    /// Re-encodes the stored JPEG with the pin's information in its metadata.
    nonisolated static func writeJPEG(from source: URL, to destination: URL, pin: Pin, boardNames: [String], originalProperties: Data?) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let target = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }

        var properties: [String: Any] = [:]
        if let originalProperties,
           let original = (try? PropertyListSerialization.propertyList(from: originalProperties, options: [], format: nil)) as? [String: Any] {
            properties = original
        }
        // Don't carry over pixel-size or orientation values from the original file.
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            properties[key as String] = nil
        }

        var keywords: [String] = pin.tags
        for tag in pin.aiTags where tag.confidence >= 0.5 && !keywords.contains(tag.label) { keywords.append(tag.label) }
        for tag in pin.fileKeywords where !keywords.contains(tag) { keywords.append(tag) }
        for tag in pin.colorTags where !keywords.contains(tag) { keywords.append(tag) }

        var iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        if !pin.title.isEmpty { iptc[kCGImagePropertyIPTCObjectName as String] = pin.title }
        if !keywords.isEmpty { iptc[kCGImagePropertyIPTCKeywords as String] = keywords }
        let caption = pin.note.isEmpty ? pin.aiDescription : metadataNote(pin.note)
        if !caption.isEmpty { iptc[kCGImagePropertyIPTCCaptionAbstract as String] = caption }
        if let credit = pin.credit { iptc[kCGImagePropertyIPTCCredit as String] = credit }
        properties[kCGImagePropertyIPTCDictionary as String] = iptc

        var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        if !pin.title.isEmpty { tiff[kCGImagePropertyTIFFImageDescription as String] = pin.title }
        tiff[kCGImagePropertyTIFFSoftware as String] = "PinBoard"
        // The stored copy was already rotated upright when it was imported, so the
        // original's orientation flag must not be written back (it would rotate twice).
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        // Original pixel sizes no longer apply to the resized copy.
        exif[kCGImagePropertyExifPixelXDimension as String] = nil
        exif[kCGImagePropertyExifPixelYDimension as String] = nil
        var record: [String: Any] = [
            "id": pin.id.uuidString,
            "title": pin.title,
            "note": metadataNote(pin.note),
            "tags": pin.tags,
            "aiTags": pin.aiTags.map { ["label": $0.label, "confidence": $0.confidence] },
            "colorTags": pin.colorTags,
            "textTags": pin.ocrTags,
            "text": pin.ocrText,
            "description": pin.aiDescription,
            "boards": boardNames,
            "created": ISO8601DateFormatter().string(from: pin.createdAt)
        ]
        if let sourceURL = pin.sourceURL { record["source"] = sourceURL }
        if let credit = pin.credit { record["credit"] = credit }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            exif[kCGImagePropertyExifUserComment as String] = json
        }
        properties[kCGImagePropertyExifDictionary as String] = exif

        if let latitude = pin.latitude, let longitude = pin.longitude,
           properties[kCGImagePropertyGPSDictionary as String] == nil {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: abs(latitude),
                kCGImagePropertyGPSLatitudeRef as String: latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude as String: abs(longitude),
                kCGImagePropertyGPSLongitudeRef as String: longitude < 0 ? "W" : "E"
            ]
        }

        CGImageDestinationAddImageFromSource(target, imageSource, 0, properties as CFDictionary)
        return CGImageDestinationFinalize(target)
    }

    /// Compresses a folder into a .zip next to it (iOS does this natively). For an export made by
    /// `buildFolder` this finishes it: only now are the earlier exports of its kind removed (see
    /// `ExportFolders`). Cancelled (checked before and after zipping) or failed, the export is
    /// removed with everything made so far, and `CancellationError` (or the error) is thrown.
    nonisolated static func zip(folder: URL) throws -> URL {
        // The export's own folder around `folder`, when `buildFolder` made it in this run.
        let own = folder.deletingLastPathComponent()
        let isExport = ExportFolders.shared.isFromThisRun(own)
        do {
            try stopIfCancelled()
            let destination = try makeZip(of: folder)
            try stopIfCancelled()   // cancelled while zipping: the zip is not handed out
            if isExport {
                ExportFolders.shared.finish(own)
                ExportFolders.shared.removeEarlier(than: own)
            }
            return destination
        } catch {
            if isExport { ExportFolders.shared.discard(own) }
            throw error
        }
    }

    /// The zip itself: the system zips a folder when it is read "for uploading"; that copy is kept.
    nonisolated private static func makeZip(of folder: URL) throws -> URL {
        let destination = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".zip")
        try? FileManager.default.removeItem(at: destination)
        var coordinationError: NSError? = nil
        var copyError: Error? = nil
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }
}

/// The export folders this run of the app has made: in which order their exports started, and
/// which of them are still at work (being built or zipped).
///
/// Why: every export works in a folder of its own (see `LibraryExporter.exportsFolder`), and the
/// earlier ones must go without ever pulling a folder out from under an export that is still at
/// work, or one that started later (it may be on its way to a share sheet in another window).
/// A folder this list doesn't know was left by an earlier launch: nothing can be using it now.
/// A lock guards the list: exports run off the main thread, sometimes two at once.
final class ExportFolders: @unchecked Sendable {   // @unchecked: `lock` guards `started`, `order` and `working`
    static let shared = ExportFolders()

    private let lock = NSLock()
    private var started = 0                 // exports started so far (numbers them in order)
    private var order: [String: Int] = [:]  // folder name (a UUID) → its export's number
    private var working: Set<String> = []   // folders whose export is still being built or zipped

    /// Makes a new folder for one export inside `kind`, noted as at work. It is noted before it
    /// exists, so the launch clean-up (which removes what this list doesn't know) never takes it.
    func makeFolder(in kind: URL) throws -> URL {
        let name = UUID().uuidString
        lock.lock()
        started += 1
        order[name] = started
        working.insert(name)
        lock.unlock()
        let folder = kind.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            discard(folder)
            throw error
        }
        return folder
    }

    /// Whether `folder` is an export folder this run made (and has not removed).
    func isFromThisRun(_ folder: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return order[folder.lastPathComponent] != nil
    }

    /// The export in `folder` is done (its zip is made): it is no longer at work.
    func finish(_ folder: URL) {
        lock.lock()
        defer { lock.unlock() }
        working.remove(folder.lastPathComponent)
    }

    /// Removes an export's folder with everything in it (cancelled, failed, or replaced by a later one).
    func discard(_ folder: URL) {
        lock.lock()
        order[folder.lastPathComponent] = nil
        working.remove(folder.lastPathComponent)
        lock.unlock()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Once the export in `folder` is done: removes the exports of its kind that started before it
    /// and are no longer at work, and whatever an earlier launch left there. A later export, or one
    /// still at work, is never touched.
    func removeEarlier(than folder: URL) {
        let kind = folder.deletingLastPathComponent()
        for entry in ExportFolders.entries(in: kind) where isEarlier(entry, than: folder) {
            discard(entry)
        }
    }

    /// At launch: removes everything in `kind` that this run didn't make.
    func removeLeftovers(in kind: URL) {
        for entry in ExportFolders.entries(in: kind) where !isFromThisRun(entry) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Whether `entry` (next to `folder`) may go now that the export in `folder` is done.
    private func isEarlier(_ entry: URL, than folder: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let name = entry.lastPathComponent
        guard name != folder.lastPathComponent, !working.contains(name) else { return false }
        guard let number = order[name] else { return true }   // left by an earlier launch
        guard let current = order[folder.lastPathComponent] else { return false }
        return number < current
    }

    /// What a folder holds (nothing when it doesn't exist).
    static func entries(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }
}

// MARK: - Sharing one board

/// Everything "Share board…" exports, as plain values read on the main actor.
struct BoardExportJob: Sendable {
    var boardName: String
    var pins: [Pin]
    var boards: [Board]
    var imagesURL: URL
    var printsURL: URL
    var exifURL: URL
    var videosURL: URL
    var libraryJSON: Data?
}

extension LibraryStore {
    /// The board (and, when asked, its sub-boards on the same side) with its pins, ready to export
    /// so that it imports back exactly. A normal board never takes hidden sub-boards or hidden pins
    /// along, and nothing in the copy is marked hidden. nil if the board is gone.
    func boardExportJob(boardID: UUID, includeSubBoards: Bool) -> BoardExportJob? {
        guard let root = board(boardID) else { return nil }
        let hidden = hiddenBoardIDs
        let rootIsHidden = hidden.contains(boardID)
        var chosen: [Board] = [root]
        if includeSubBoards {
            for id in descendants(of: boardID) where hidden.contains(id) == rootIsHidden {
                if let child = board(id) { chosen.append(child) }
            }
        }
        let boardIDs = Set(chosen.map { $0.id })
        // Pins on the exported boards themselves: a pin that is on a normal board only through a
        // hidden sub-board stays out too.
        let shown = rootIsHidden ? livePins : visiblePins
        let chosenPins = shown.filter { pin in pin.boardIDs.contains { boardIDs.contains($0) } }
        let pinIDs = Set(chosenPins.map { $0.id })

        let exportedBoards: [Board] = chosen.map { board in
            var copy = board
            if copy.id == boardID { copy.parentID = nil }
            copy.isSecret = false
            copy.openCount = 0
            if let cover = copy.coverPinID, !pinIDs.contains(cover) { copy.coverPinID = nil }
            return copy
        }
        let exportedPins: [Pin] = chosenPins.map { pin in
            var copy = pin
            copy.isHidden = false
            copy.boardsBeforeHiding = []
            copy.boardIDs = pin.boardIDs.filter { boardIDs.contains($0) }
            if let twin = copy.duplicateOfID, !pinIDs.contains(twin) { copy.duplicateOfID = nil }
            if let article = copy.quotedFromID, !pinIDs.contains(article) { copy.quotedFromID = nil }   // (a quote whose article is on another board)
            copy.notDuplicateOf.removeAll { !pinIDs.contains($0) }
            return copy
        }
        let document = LibraryDocument(pins: exportedPins, boards: exportedBoards, smartBoards: [], erased: [:])
        return BoardExportJob(boardName: root.name,
                              pins: exportedPins,
                              boards: exportedBoards,
                              imagesURL: imagesURL,
                              printsURL: printsURL,
                              exifURL: exifURL,
                              videosURL: videosURL,
                              libraryJSON: LibraryStore.encodeDocument(document, pretty: true))
    }
}

extension LibraryExporter {
    /// Builds "<board name> (PinBoard)" in a folder of its own with `buildFolder` and zips it;
    /// returns the .zip's address. Runs off the main thread. Cancelling its task stops it
    /// (`CancellationError`) and leaves nothing behind.
    nonisolated static func exportBoard(_ job: BoardExportJob,
                                        progress: @escaping @Sendable (Int, Int) -> Void,
                                        zipping: @escaping @Sendable (Int64) -> Void = { _ in }) throws -> URL {
        let outcome = try buildFolder(pins: job.pins,
                                      boards: job.boards,
                                      imagesURL: job.imagesURL,
                                      printsURL: job.printsURL,
                                      exifURL: job.exifURL,
                                      videosURL: job.videosURL,
                                      libraryJSON: job.libraryJSON,
                                      hiddenBoardIDs: [],
                                      folderName: "\(job.boardName.safeFileName) (PinBoard)",
                                      progress: progress)
        zipping(LibraryStore.folderSize(at: outcome.folderURL))   // the bar's last part (ExportProgress)
        return try zip(folder: outcome.folderURL)
    }
}

// MARK: - Import

/// What "Import a folder…" found (step 1). Nothing in the library is changed until commitFolderImport.
struct FolderImportPlan: Identifiable, Sendable {
    let id: UUID
    var folder: URL
    var isPinBoardExport: Bool     // library.json + files.json were found
    var items: [PendingImport]     // look-alikes carry duplicateOf / identicalTo (normal side only)
    var boards: [Board]            // PinBoard export: boards to re-create (ids kept), parents first
    var smartBoards: [SmartBoard]  // PinBoard export: smart boards not in the library yet
    var restoreIDs: Set<UUID>      // PinBoard export: pins sitting in Recently Deleted here
    var alreadyHere: Int           // PinBoard export: pins already live here (left alone)
    var unreadable: Int            // files that could not be read
    var profileID: UUID? = nil     // the library it was read for (committed only into that one)
}

/// A file found in a plain folder, with the names of the sub-folders it sits in.
private struct FolderEntry: Sendable {
    let url: URL
    let path: [String]
}

/// A PinBoard export's library.json and files.json (pin id → the file's path in the folder).
private struct ExportManifest: Sendable {
    var document: LibraryDocument
    var files: [String: String]
}

/// The machine-readable extras an export keeps for one pin.
private struct ExportedExtras: Sendable {
    var featurePrint: Data?
    var exif: Data?
    var preview: Data?
}

/// What a record of a PinBoard export becomes when it is imported (round 15, owner's standing rule:
/// "all of the information attached to a pin should be saved in a full export and kept in an
/// import"). The exported record IS the pin: every field it has comes back as it was — also any
/// field added to `Pin` later, because nothing here lists them — and only what the import itself
/// found out about the files it put in place is written over it. The one list in this file is that
/// short one, the file-derived fields, so a field nobody thought of is kept by default instead of lost.
enum ExportedRecord {

    /// The pin a re-imported picture or video record becomes. `record`: the exported record (its
    /// boards already narrowed to the ones that exist here). `made`: the pin as the import made it
    /// from the files — the id it was given, the picture's size, where the video file is, the change
    /// date `reinsertedDate` chose. `hasFeaturePrint`: the export's fingerprint file was put in place.
    ///
    /// Taken from `made` (what the files say): `id`, `kind`, `videoExtension`, `width`, `height`,
    /// `hasPreview`, `pictureRevision`, `originalName`, `originalBytes` (no original of the export's
    /// copy is kept here), `videoTier` (the conversion's when the video was looked at or converted on
    /// import, else the record's: the file was taken as it is), `duration` and `hasAudio` (the
    /// record's when it knew, else what was found in the file), `boardIDs`, `updatedAt`. Decided here:
    /// `hasFeaturePrint`, `deletedAt` (a record comes back live) and `duplicateOfID` (looked for among
    /// the pins of this library once the pin is in place: the record's twin may not exist here).
    /// Everything else — also `dhash`, the fingerprint's short form, which is of the same picture —
    /// is the record's.
    nonisolated static func pin(from record: Pin, made: Pin, hasFeaturePrint: Bool) -> Pin {
        var result = record
        result.id = made.id
        result.kind = made.kind
        result.videoExtension = made.videoExtension
        result.width = made.width
        result.height = made.height
        result.hasPreview = made.hasPreview
        result.pictureRevision = made.pictureRevision
        result.originalName = made.originalName
        result.originalBytes = made.originalBytes
        result.videoTier = made.videoTier ?? record.videoTier
        result.duration = made.duration ?? record.duration
        result.hasAudio = made.hasAudio ?? record.hasAudio
        result.boardIDs = made.boardIDs
        result.updatedAt = made.updatedAt
        result.hasFeaturePrint = hasFeaturePrint
        result.deletedAt = nil
        result.duplicateOfID = nil
        return result
    }
}

extension LibraryStore {

    /// Finds (or creates) the board for a folder path like ["Travel", "Beaches"].
    /// `visibleOnly`: only normal boards are matched (a hidden board with the same name is
    /// never used), so a folder import lands on the normal side.
    func board(forPath names: [String], createIfNeeded: Bool, visibleOnly: Bool = false) -> UUID? {
        var parentID: UUID? = nil
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let candidates = visibleOnly ? visibleChildren(of: parentID).filter { !isSecretBoard($0.id) } : children(of: parentID)
            if let existing = candidates.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                parentID = existing.id
            } else if createIfNeeded, let board = addBoard(name: trimmed, parentID: parentID) {
                parentID = board.id
            } else {
                return nil
            }
        }
        return parentID
    }

    /// Re-creates a board from an export with its own id (so pins and covers keep pointing at it).
    /// It keeps its own change date (see `insertBoard`), unless it had to move to the top level
    /// here (its parent is not in this library): that move is a change made now.
    private func adoptBoard(_ record: Board, parentID: UUID?) -> UUID {
        if let existing = board(record.id) {
            _ = existing
            return record.id
        }
        var board = record
        board.parentID = parentID
        if board.lastEditedAt == nil { board.lastEditedAt = record.updatedAt }
        if parentID != record.parentID { board.updatedAt = Date() }
        insertBoard(board)
        return board.id
    }

    // MARK: Folder import, step 1: read and check

    /// Starts reading `folder` (a PinBoard export, or any folder whose sub-folders become boards) and
    /// checks every picture, video, text and link for look-alikes among the pins of `scope`, like any
    /// import. Access to the folder stays open until `commitFolderImport` or `cancelFolderImport`.
    /// Shows "Reading 12 of 300…" as `scope`'s progress (`setImportStatus`). Every item belongs to
    /// the library in use now (`PendingImport.profileID`, like the plan's own `profileID`).
    func prepareFolderImport(_ folder: URL, scope: PinScope = .visible) async -> FolderImportPlan {
        beginLibraryWork()   // a folder import is library work (see `isBusyWithLibraryWork`)
        defer { endLibraryWork() }
        let planID = UUID()
        if folder.startAccessingSecurityScopedResource() { folderImportAccess[planID] = folder }
        let base = FolderImportPlan(id: planID, folder: folder, isPinBoardExport: false, items: [], boards: [],
                                    smartBoards: [], restoreIDs: [], alreadyHere: 0, unreadable: 0, profileID: profileID)
        setImportStatus("Reading the folder…", scope: scope)
        let manifest = await Task.detached(priority: .userInitiated) { () -> ExportManifest? in
            LibraryStore.readExportManifest(in: folder)
        }.value
        let plan: FolderImportPlan
        if let manifest {
            plan = await planExportedFolder(manifest, base: base, scope: scope)
        } else {
            plan = await planPlainFolder(base: base, scope: scope)
        }
        setImportStatus(nil, scope: scope)
        return plan
    }

    /// A PinBoard export: every record is re-created as it was. Records already here are left
    /// alone (or brought back from Recently Deleted); only records on the side of `scope` are
    /// checked for look-alikes.
    private func planExportedFolder(_ manifest: ExportManifest, base: FolderImportPlan, scope: PinScope) async -> FolderImportPlan {
        var plan = base
        plan.isPinBoardExport = true
        let folder = plan.folder
        let files = manifest.files
        let document = manifest.document
        let profile = base.profileID ?? profileID   // every item belongs to the plan's library
        plan.boards = LibraryStore.parentsFirst(document.boards.filter { board($0.id) == nil }, existing: Set(boards.map { $0.id }))
        plan.smartBoards = document.smartBoards.filter { smartBoard($0.id) == nil }
        let willBeHidden = hiddenBoards(adding: plan.boards)
        let knownBoards = Set(boards.map { $0.id }).union(plan.boards.map { $0.id })
        let extrasFolder = folder.appendingPathComponent(LibraryExporter.hiddenFolder, isDirectory: true)
        let records = document.pins.filter { !$0.isDeleted }
        for (index, record) in records.enumerated() {
            setImportStatus("Reading \(index + 1) of \(records.count)…", scope: scope)
            if let existing = pin(record.id) {
                if existing.isDeleted { plan.restoreIDs.insert(record.id) } else { plan.alreadyHere += 1 }
                continue
            }
            var placed = record
            placed.boardIDs = record.boardIDs.filter { knownBoards.contains($0) }
            let checks = (LibraryStore.isHidden(placed, secretBoards: willBeHidden) ? PinScope.hidden : .visible) == scope
            let extras = await Task.detached(priority: .userInitiated) { () -> ExportedExtras in
                LibraryStore.readExportedExtras(of: record, in: folder, extrasFolder: extrasFolder, files: files)
            }.value
            let exported = ExportedPin(record: record, featurePrint: extras.featurePrint, exif: extras.exif, previewData: extras.preview)
            switch record.kind {
            case .text:
                var item = PendingImport(payload: .text(title: record.title, body: record.textBody), profileID: profile, exported: exported)
                if checks { item.duplicateOf = prepareText(title: record.title, body: record.textBody, scope: scope).duplicateOf }
                plan.items.append(item)
            case .link:
                guard let text = record.linkURL, let url = URL(string: text) else { plan.unreadable += 1; continue }
                // Shown as it will be saved: without its tracking when "Clean links" is on
                // (`insertImportedLinkPin` cleans the record's address the same way).
                var item = PendingImport(payload: .link(keptLink(url)), profileID: profile, exported: exported)
                if checks { item.duplicateOf = prepareLink(url, scope: scope).duplicateOf }
                plan.items.append(item)
            case .image:
                guard let relative = files[record.id.uuidString] else { plan.unreadable += 1; continue }
                let file = folder.appendingPathComponent(relative)
                // The picture stays in the folder until the import is committed.
                guard let data = await LibraryStore.readFile(file) else { plan.unreadable += 1; continue }
                var item = PendingImport(payload: .image(Data(), title: record.title, sourceURL: record.sourceURL, credit: record.credit),
                                         profileID: profile, sourceFile: file, exported: exported)
                if checks {
                    let match = await nearDuplicate(ofImageData: data, scope: scope)
                    item.duplicateOf = match.duplicate
                    item.identicalTo = match.identical
                }
                plan.items.append(item)
            case .video:
                guard let posterPath = files[record.id.uuidString], let videoPath = files[record.id.uuidString + "#video"],
                      let posterData = await LibraryStore.readFile(folder.appendingPathComponent(posterPath)) else {
                    plan.unreadable += 1
                    continue
                }
                // A private copy the import owns (the folder's own file is never touched).
                let source = folder.appendingPathComponent(videoPath)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import-\(UUID().uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)")
                guard await LibraryStore.copyFile(from: source, to: temp) else { plan.unreadable += 1; continue }
                let poster = VideoPoster(jpegData: posterData, duration: record.duration ?? 0, hasAudio: record.hasAudio)
                var item = PendingImport(payload: .video(temp, poster: poster, title: record.title), profileID: profile, exported: exported)
                if checks {
                    let match = await nearDuplicate(ofImageData: posterData, scope: scope)
                    item.duplicateOf = match.duplicate ?? match.identical
                }
                plan.items.append(item)
            }
        }
        return plan
    }

    /// Any folder: every picture, video, text file and link, its sub-folders naming the board.
    private func planPlainFolder(base: FolderImportPlan, scope: PinScope) async -> FolderImportPlan {
        var plan = base
        let folder = plan.folder
        let profile = base.profileID ?? profileID   // every item belongs to the plan's library
        let entries = await Task.detached(priority: .userInitiated) { () -> [FolderEntry] in
            LibraryStore.plainFolderEntries(in: folder)
        }.value
        for (index, entry) in entries.enumerated() {
            setImportStatus("Reading \(index + 1) of \(entries.count)…", scope: scope)
            let url = entry.url
            let destination = entry.path == ["Unsorted"] ? [] : entry.path
            let ext = url.pathExtension.lowercased()
            let fileTitle = url.deletingPathExtension().lastPathComponent
            if ext == "txt" {
                guard let text = await LibraryStore.readText(url) else { plan.unreadable += 1; continue }
                let split = LibraryStore.splitTextFile(text)
                let title = split.title ?? cleanFileName(fileTitle)
                guard !title.isEmpty || !split.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    plan.unreadable += 1
                    continue
                }
                var item = prepareText(title: title, body: split.body, scope: scope)
                item.destinationPath = destination
                plan.items.append(item)
                continue
            }
            if ext == "url" {
                guard let text = await LibraryStore.readText(url),
                      let line = text.components(separatedBy: .newlines).first(where: { $0.uppercased().hasPrefix("URL=") }),
                      let link = LibraryStore.linkURL(in: String(line.dropFirst(4))) else {
                    plan.unreadable += 1
                    continue
                }
                var item = prepareLink(link, scope: scope)
                item.destinationPath = destination
                plan.items.append(item)
                continue
            }
            if LibraryExporter.folderVideoExtensions.contains(ext) {
                // Work on a private copy, as for any picked file (the folder's own file is never touched).
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(ext)")
                guard await LibraryStore.copyFile(from: url, to: temp) else { plan.unreadable += 1; continue }
                guard var item = await prepareVideo(at: temp, title: cleanFileName(fileTitle), scope: scope).first else {
                    try? FileManager.default.removeItem(at: temp)
                    plan.unreadable += 1
                    continue
                }
                item.destinationPath = destination
                plan.items.append(item)
                continue
            }
            // An animated GIF comes in as a video (AnimatedGIF.swift), made now from the folder's file.
            if ext == "gif", let gif = await LibraryStore.readFile(url), let movie = await AnimatedGIF.videoFile(from: gif) {
                guard var item = await prepareVideo(at: movie, title: cleanFileName(fileTitle), scope: scope).first else {
                    try? FileManager.default.removeItem(at: movie)
                    plan.unreadable += 1
                    continue
                }
                item.destinationPath = destination
                plan.items.append(item)
                continue
            }
            // A picture: measured now, read again from the folder when committed.
            let read = await Task.detached(priority: .userInitiated) { () -> (data: Data, title: String?)? in
                guard let data = try? Data(contentsOf: url), ImageProcessor.downsample(data, maxPixelSize: 32) != nil else { return nil }
                let title = ImageProcessor.readMetadata(data).title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (data, title)
            }.value
            guard let read else { plan.unreadable += 1; continue }
            let match = await nearDuplicate(ofImageData: read.data, scope: scope)
            let title = (read.title?.isEmpty ?? true) ? cleanFileName(fileTitle) : (read.title ?? "")
            plan.items.append(PendingImport(payload: .image(Data(), title: title, sourceURL: nil, credit: nil), profileID: profile,
                                            duplicateOf: match.duplicate, identicalTo: match.identical,
                                            sourceFile: url, destinationPath: destination))
        }
        return plan
    }

    // MARK: Folder import, step 2: commit (or cancel)

    /// Re-creates the export's boards and smart boards, brings back `restoreIDs`, then imports `kept`
    /// (the plan's items minus the skipped ones; items in `addExisting` put their look-alike on the
    /// boards instead, as in commitImports). Stops the folder access, re-checks duplicates and starts
    /// the AI. The folder's own files are never changed or deleted.
    /// It belongs to the library the plan was read for: if another profile is in use (when it starts,
    /// or by the time an item is reached) nothing more is imported here — the rest is dropped.
    func commitFolderImport(_ plan: FolderImportPlan, keeping kept: [PendingImport],
                            addExisting: Set<UUID> = []) async -> ImportSummary {
        let profile = profileID
        var summary = ImportSummary()
        guard plan.profileID.map({ isCurrentProfile($0) }) ?? true else {
            // Read for another library: its look-alikes and pins to bring back are that library's.
            // Nothing is imported ("Nothing was added.").
            stopFolderAccess(for: plan)
            LibraryStore.discardTemporaryCopies(of: kept)
            return summary
        }
        beginLibraryWork()
        defer { endLibraryWork() }
        let boardsBefore = boards.count
        beginBoardStampBatch()
        // The export's boards and smart boards as they were (ids kept), parents first.
        for record in plan.boards {
            let parentID = record.parentID.flatMap { board($0) != nil ? $0 : nil }
            _ = adoptBoard(record, parentID: parentID)
        }
        for record in plan.smartBoards where smartBoard(record.id) == nil {
            insertSmartBoard(record)
        }
        // Pins that were in Recently Deleted here come back.
        let restoring = Set(plan.restoreIDs.filter { pin($0)?.isDeleted == true })
        if !restoring.isEmpty {
            restorePins(restoring)
            summary.imported += restoring.count
        }
        for (index, item) in kept.enumerated() {
            guard isCurrentProfile(profile) else {
                // Another profile now: the rest is dropped (see above).
                LibraryStore.discardTemporaryCopies(of: Array(kept[index...]))
                break
            }
            // (Started from Settings, the normal side: its progress is the normal side's.)
            setImportStatus("Importing \(index + 1) of \(kept.count)…", scope: .visible)
            let outcome = await commitPendingItem(item, batchBoardIDs: [], batchHidden: false,
                                                  skipDuplicates: false, addExisting: addExisting.contains(item.id),
                                                  profile: profile)
            summary.count(outcome)
        }
        endBoardStampBatch()
        stopFolderAccess(for: plan)
        summary.alreadyHad += plan.alreadyHere
        summary.skipped += plan.unreadable
        setImportStatus(nil, scope: .visible)
        guard isCurrentProfile(profile) else { return summary }
        summary.boardsCreated = max(0, boards.count - boardsBefore)
        tidyNestedMemberships(for: Set(summary.newPinIDs))   // (an export's record may name a board and one inside it)
        countNewPins(summary.newPinIDs)   // the pins brought back from Recently Deleted are not new
        await saveNowAndWait()   // on disk before "done" is shown (see LibrarySaving.swift)
        await refreshDuplicates()
        startAnalysisIfNeeded()
        startVideoMaintenanceIfNeeded(delay: 2)
        // A minute later the new originals iCloud has in full leave this device (MediaStorage.swift).
        if !summary.newPinIDs.isEmpty, isCurrentProfile(profile) { scheduleOriginalsUpkeep(after: 60) }
        // Everything is in, each video exactly as imported: now the new videos are made smaller,
        // one at a time in the background.
        if isCurrentProfile(profile) { startConvertingNewVideos(summary.newPinIDs) }
        return summary
    }

    /// Cancel: stops the folder access (exactly once per plan). Temporary video copies of the
    /// plan's items are the caller's to discard.
    func cancelFolderImport(_ plan: FolderImportPlan) {
        stopFolderAccess(for: plan)
    }

    private func stopFolderAccess(for plan: FolderImportPlan) {
        if let folder = folderImportAccess.removeValue(forKey: plan.id) {
            folder.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: Folder import helpers

    /// Boards that will be hidden once `newBoards` are added: hidden themselves or inside a hidden
    /// board (the new boards' own flags, this library's flags for the boards it has).
    private func hiddenBoards(adding newBoards: [Board]) -> Set<UUID> {
        let all = boards + newBoards
        var parentOf: [UUID: UUID] = [:]
        var marked: Set<UUID> = []
        for board in all {
            if let parentID = board.parentID { parentOf[board.id] = parentID }
            if board.isSecret { marked.insert(board.id) }
        }
        var result: Set<UUID> = []
        for board in all {
            var current: UUID? = board.id
            var steps = 0
            while let id = current, steps < 50 {
                if marked.contains(id) {
                    result.insert(board.id)
                    break
                }
                current = parentOf[id]
                steps += 1
            }
        }
        return result
    }

    /// Boards ordered so that every parent comes before its children. A board whose parent is
    /// neither in the library nor among them goes to the top level.
    nonisolated fileprivate static func parentsFirst(_ records: [Board], existing: Set<UUID>) -> [Board] {
        var ordered: [Board] = []
        var placed = existing
        var remaining = records
        while !remaining.isEmpty {
            let ready = remaining.filter { record in record.parentID.map { placed.contains($0) } ?? true }
            if !ready.isEmpty {
                ordered.append(contentsOf: ready)
                placed.formUnion(ready.map { $0.id })
                remaining.removeAll { placed.contains($0.id) }
                continue
            }
            // Parents missing from the export: those boards go to the top level
            // (all of what is left when a damaged file loops).
            let waiting = Set(remaining.map { $0.id })
            var orphans = remaining.filter { record in !(record.parentID.map { waiting.contains($0) } ?? false) }
            if orphans.isEmpty { orphans = remaining }
            for record in orphans {
                var moved = record
                moved.parentID = nil
                ordered.append(moved)
                placed.insert(moved.id)
            }
            remaining.removeAll { placed.contains($0.id) }
        }
        return ordered
    }

    nonisolated fileprivate static func readExportManifest(in folder: URL) -> ExportManifest? {
        guard let manifestData = try? Data(contentsOf: folder.appendingPathComponent("library.json")),
              let document = LibraryStore.decodeDocument(manifestData),
              let mapData = try? Data(contentsOf: folder.appendingPathComponent("files.json")),
              let files = (try? JSONSerialization.jsonObject(with: mapData)) as? [String: String] else { return nil }
        return ExportManifest(document: document, files: files)
    }

    nonisolated fileprivate static func readExportedExtras(of record: Pin, in folder: URL, extrasFolder: URL,
                                                           files: [String: String]) -> ExportedExtras {
        let featurePrint = try? Data(contentsOf: extrasFolder.appendingPathComponent("prints").appendingPathComponent(record.printFileName))
        let exif = try? Data(contentsOf: extrasFolder.appendingPathComponent("exif").appendingPathComponent(record.exifFileName))
        let preview = record.isLink ? files[record.id.uuidString + "#preview"].flatMap { try? Data(contentsOf: folder.appendingPathComponent($0)) } : nil
        return ExportedExtras(featurePrint: featurePrint, exif: exif, preview: preview)
    }

    /// Every file a plain folder import can use (README.txt, link previews and the export's
    /// own "_pinboard" folder are left out), with the sub-folders it sits in, in name order.
    nonisolated fileprivate static func plainFolderEntries(in folder: URL) -> [FolderEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var found: [FolderEntry] = []
        while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard LibraryExporter.folderImageExtensions.contains(ext) || LibraryExporter.folderVideoExtensions.contains(ext) || ext == "txt" || ext == "url" else { continue }
            if url.lastPathComponent == "README.txt" { continue }
            if url.lastPathComponent.lowercased().hasSuffix(".preview.jpg") { continue }
            let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            var parts: [String]
            if components.count > base.count, Array(components.prefix(base.count)) == base {
                parts = Array(components.dropFirst(base.count))
            } else {
                parts = url.path.replacingOccurrences(of: folder.path + "/", with: "").components(separatedBy: "/")
            }
            parts.removeLast()
            if parts.first == LibraryExporter.hiddenFolder { continue }
            found.append(FolderEntry(url: url, path: parts))
        }
        return found.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    nonisolated static func readText(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { try? String(contentsOf: url, encoding: .utf8) }.value
    }

    /// PinBoard writes a text pin as its title, a blank line, then the text (an untitled pin
    /// starts with the blank line). Anything else is all text, with no title (nil).
    nonisolated static func splitTextFile(_ text: String) -> (title: String?, body: String) {
        let parts = text.components(separatedBy: "\n\n")
        let firstLine = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasTitleLine = parts.count > 1 && firstLine.count <= 80 && !firstLine.contains("\n")
        guard hasTitleLine else { return (nil, text) }
        return (firstLine, parts.dropFirst().joined(separator: "\n\n"))
    }
}

// MARK: - Saving to Photos

/// Saving into Photos. PinBoard only ever asks for add-only access ("Add Photos Only"): it adds
/// new pictures and videos when the person asks, and never needs to see the rest of the library.
enum PhotosSaver {
    /// Asks iOS for add-only access to Photos (the first time, iOS shows its question; after
    /// that the answer comes straight back). True when PinBoard may add to Photos.
    @MainActor
    static func mayAdd() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// The person said no to adding to Photos (or a parental restriction does).
    @MainActor
    static var isRefused: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .denied || status == .restricted
    }

    /// Said when access to Photos was refused: where to allow it.
    static let refusedText = "PinBoard isn't allowed to add to Photos. You can allow it in the Settings app › Apps › PinBoard › Photos."

    /// What to say when Photos didn't take something: where to allow it when access was refused,
    /// else `otherwise`.
    @MainActor
    static func problem(_ otherwise: String) -> String {
        isRefused ? refusedText : otherwise
    }

    /// Saves a picture into Photos and says whether Photos took it (false when access was
    /// refused or the save failed — so "Saved" is only ever said when it is true).
    @MainActor
    static func save(_ image: UIImage) async -> Bool {
        guard await mayAdd() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.creationRequestForAsset(from: image)   // (UIImage is Sendable)
            }
            return true
        } catch {
            return false
        }
    }

    /// Saves a picture file into Photos exactly as it is (a kept original: HEIC, PNG, JPEG… with
    /// all its details), rather than a picture drawn again. Add-only access, as above.
    @MainActor
    static func saveImageFile(at url: URL) async -> Bool {
        guard await mayAdd() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }

    /// Saves a video file into Photos (add-only access, as for pictures).
    @MainActor
    static func saveVideo(at url: URL) async -> Bool {
        guard await mayAdd() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Document picker (export a folder to Files)

struct FolderExportPicker: UIViewControllerRepresentable {
    let url: URL
    /// Called when the picker closes: `saved` is true only when a place was chosen (Cancel: false).
    var onFinish: (_ saved: Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (_ saved: Bool) -> Void
        init(onFinish: @escaping (_ saved: Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}
