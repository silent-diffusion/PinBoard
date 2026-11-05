//
//  LibraryImports.swift  —  PinBoard
//
//  The part of `LibraryStore` that brings things in: reading and checking what was picked, dropped,
//  pasted or typed (step 1) and committing it (step 2), text, link and video pins, highlights and
//  quotes, a pin's source link and link previews, staged file writes (`incoming` / `moveIntoPlace`)
//  and the one-step paths the folder importer uses. It is an extension in its own file so that
//  LibraryStore.swift stays short enough to paste.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

extension LibraryStore {

    // MARK: Importing — step 1: read and check

    /// A near-duplicate already in the library, for a picture about to be imported,
    /// among the pins of the side it is imported into (a hidden pin is never offered
    /// for a normal import, and the other way round).
    func nearDuplicate(ofImageData data: Data, scope: PinScope) async -> (duplicate: Pin?, identical: Pin?) {
        let measured = await Task.detached(priority: .userInitiated) { () -> (UInt64, Double)? in
            guard let image = ImageProcessor.downsample(data, maxPixelSize: 2048),
                  let hash = ImageSignals.differenceHash(image) else { return nil }
            return (hash, Double(max(image.width, 1)) / Double(max(image.height, 1)))
        }.value
        guard let measured, measured.0 != 0 else { return (nil, nil) }
        let hash = measured.0
        let aspect = measured.1
        let hidden = scope == .hidden
        let entries = hashEntries().filter { $0.hidden == hidden }
        // Byte-for-byte one of our own files (a card dragged back in)?
        let close = entries.filter { ImageSignals.hammingDistance(hash, $0.hash) <= 2 }.map { $0.id }
        if !close.isEmpty {
            let files = close.map { location.images.appendingPathComponent("\($0.uuidString).jpg") }
            let matchIndex = await Task.detached(priority: .userInitiated) { () -> Int? in
                for (index, url) in files.enumerated() {
                    if let stored = try? Data(contentsOf: url, options: .mappedIfSafe), stored == data { return index }
                }
                return nil
            }.value
            if let matchIndex, let identical = livePin(close[matchIndex]) { return (nil, identical) }
        }
        if let id = LibraryStore.bestMatch(for: hash, aspect: aspect, id: nil, notDuplicateOf: [], among: entries,
                                           maxDistance: LibraryStore.duplicateHashDistance, hidden: hidden) {
            return (livePin(id), nil)
        }
        return (nil, nil)
    }

    private func duplicateTextPin(title: String, body: String, scope: PinScope) -> Pin? {
        let needle = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return pins(scope: scope).first { $0.isText && $0.textBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle }
    }

    // Every prepare step takes the `scope` the items are imported into (see
    // `importScope(boardIDs:hidden:)`): look-alikes are only looked for on that side, and its
    // progress ("Reading 3 of 10…") is shown as that side's (`setImportStatus`).
    // Reading counts as library work (`isBusyWithLibraryWork`): what is read is committed into
    // this library, onto its boards. Every item remembers that library (`PendingImport.profileID`).

    /// Photos picker items → pending imports (pictures and videos).
    func prepareImports(pickerItems items: [PhotosPickerItem], scope: PinScope = .visible) async -> [PendingImport] {
        beginLibraryWork()
        defer { endLibraryWork() }
        var pending: [PendingImport] = []
        for (index, item) in items.enumerated() {
            setImportStatus("Reading \(index + 1) of \(items.count)…", scope: scope)
            let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            if isMovie {
                if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                    pending.append(contentsOf: await prepareVideo(at: movie.url, title: "", scope: scope))
                }
                continue
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            pending.append(await prepareImage(data, title: "", sourceURL: nil, credit: nil, scope: scope))
        }
        setImportStatus(nil, scope: scope)
        return pending
    }

    /// Files chosen in the Files app (security-scoped URLs): pictures, videos, text files.
    func prepareImports(fileURLs urls: [URL], scope: PinScope = .visible) async -> [PendingImport] {
        beginLibraryWork()
        defer { endLibraryWork() }
        var pending: [PendingImport] = []
        for (index, url) in urls.enumerated() {
            setImportStatus("Reading \(index + 1) of \(urls.count)…", scope: scope)
            let name = url.deletingPathExtension().lastPathComponent
            let type = UTType(filenameExtension: url.pathExtension)
            let accessed = url.startAccessingSecurityScopedResource()
            if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
                // Work on a private copy: the picked file may vanish once access ends.
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(url.pathExtension)")
                let copied = await LibraryStore.copyFile(from: url, to: temp)
                if accessed { url.stopAccessingSecurityScopedResource() }
                if copied { pending.append(contentsOf: await prepareVideo(at: temp, title: cleanFileName(name), scope: scope)) }
                continue
            }
            if type?.conforms(to: .plainText) == true || url.pathExtension.lowercased() == "txt" {
                let text = try? String(contentsOf: url, encoding: .utf8)
                if accessed { url.stopAccessingSecurityScopedResource() }
                if let text { pending.append(prepareText(title: cleanFileName(name), body: text, scope: scope)) }
                continue
            }
            let data = await LibraryStore.readFile(url)
            if accessed { url.stopAccessingSecurityScopedResource() }
            guard let data else { continue }
            pending.append(await prepareImage(data, title: cleanFileName(name), sourceURL: nil, credit: nil, scope: scope))
        }
        setImportStatus(nil, scope: scope)
        return pending
    }

    /// Things dropped onto the app.
    func prepareImports(dropped items: [DropPayload], scope: PinScope = .visible) async -> [PendingImport] {
        beginLibraryWork()
        defer { endLibraryWork() }
        var pending: [PendingImport] = []
        for (index, item) in items.enumerated() {
            setImportStatus("Reading \(index + 1) of \(items.count)…", scope: scope)
            switch item {
            case .image(let data):
                pending.append(await prepareImage(data, title: "", sourceURL: nil, credit: nil, scope: scope))
            case .video(let url):
                pending.append(contentsOf: await prepareVideo(at: url, title: cleanFileName(url.deletingPathExtension().lastPathComponent), scope: scope))
            case .text(let text):
                if let url = LibraryStore.linkURL(in: text) {
                    pending.append(contentsOf: await prepareLinkSmart(url, scope: scope))
                } else {
                    pending.append(prepareText(title: "", body: text, scope: scope))
                }
            case .url(let url):
                pending.append(contentsOf: await prepareLinkSmart(url, scope: scope))
            case .pin:
                break   // one of our own cards: the caller puts it on the board instead
            }
        }
        setImportStatus(nil, scope: scope)
        return pending
    }

    /// Web results → pending imports (downloaded and checked for duplicates). A page
    /// that was saved before comes back as `identicalTo` its pin, so committing it
    /// just puts that pin on the chosen boards.
    func prepareWebImports(_ images: [WebImage], scope: PinScope = .visible) async -> [PendingImport] {
        beginLibraryWork()
        defer { endLibraryWork() }
        var pending: [PendingImport] = []
        for (index, image) in images.enumerated() {
            if images.count > 1 { setImportStatus("Downloading \(index + 1) of \(images.count)…", scope: scope) }
            if let existingID = pinID(forSourceURL: image.pageURL.absoluteString, scope: scope), let existing = livePin(existingID) {
                pending.append(PendingImport(payload: .image(Data(), title: "", sourceURL: nil, credit: nil),
                                             profileID: profileID, identicalTo: existing))
                continue
            }
            var data = try? await WebImageService.download(image.fullURL)
            if data == nil, image.fullURL != image.thumbURL {
                data = try? await WebImageService.download(image.thumbURL)
            }
            guard let data else { continue }
            WebImageService.reportDownload(of: image)   // Unsplash asks to be told of each download
            let title = image.title.map { TitleGenerator.shorten($0, to: 60) } ?? ""
            pending.append(await prepareImage(data, title: title, sourceURL: image.pageURL.absoluteString, credit: image.credit, scope: scope))
        }
        setImportStatus(nil, scope: scope)
        return pending
    }

    /// The clipboard: a picture, a link, or text.
    func prepareImportsFromPasteboard(scope: PinScope = .visible) async -> [PendingImport] {
        beginLibraryWork()
        defer { endLibraryWork() }
        let pasteboard = UIPasteboard.general
        var pending: [PendingImport] = []
        if let gif = pasteboard.data(forPasteboardType: UTType.gif.identifier), AnimatedGIF.isAnimated(gif) {
            // Copied as a GIF: read as it is (the pictures below would be its first frame only).
            setImportStatus("Reading the clipboard…", scope: scope)
            pending.append(await prepareImage(gif, title: "", sourceURL: nil, credit: nil, scope: scope))
        } else if let images = pasteboard.images, !images.isEmpty {
            setImportStatus("Reading the clipboard…", scope: scope)
            for image in images {
                let boxed = LoadedImage(image: image)   // encoded off the main thread
                let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                    boxed.image?.jpegData(compressionQuality: 0.95)
                }.value
                if let data { pending.append(await prepareImage(data, title: "", sourceURL: nil, credit: nil, scope: scope)) }
            }
        } else if let url = pasteboard.url {
            pending.append(contentsOf: await prepareLinkSmart(url, scope: scope))
        } else if let text = pasteboard.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let url = LibraryStore.linkURL(in: text) {
                pending.append(contentsOf: await prepareLinkSmart(url, scope: scope))
            } else {
                pending.append(prepareText(title: "", body: text, scope: scope))
            }
        }
        setImportStatus(nil, scope: scope)
        return pending
    }

    /// A text pin typed in the editor (its title, if any, is the person's own).
    func prepareTextImport(title: String, body: String, scope: PinScope = .visible) -> PendingImport? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return nil }
        var item = prepareText(title: trimmedTitle, body: trimmedBody, scope: scope)
        item.titleFromUser = true
        return item
    }

    /// A single link typed or pasted: read fully when Settings › Links says so (SmartLinks.swift),
    /// so it may come back as a picture or video item instead of a link. nil: not a web address.
    func prepareLinkImport(_ text: String, scope: PinScope = .visible) async -> [PendingImport]? {
        guard let url = LibraryStore.linkURL(in: text) else { return nil }
        beginLibraryWork()
        defer { endLibraryWork() }
        return await prepareLinkSmart(url, scope: scope)
    }

    /// (The item belongs to the library in use when its reading started.)
    func prepareImage(_ data: Data, title: String, sourceURL: String?, credit: String?, scope: PinScope) async -> PendingImport {   // (not private: SmartLinks.swift makes picture items from links)
        // An animated GIF comes in as a video, so it plays, loops and carries on like one (AnimatedGIF.swift).
        if let movie = await AnimatedGIF.videoFile(from: data),
           let video = await prepareVideo(at: movie, title: title, scope: scope).first {
            return video
        }
        let profile = profileID
        let match = await nearDuplicate(ofImageData: data, scope: scope)
        return PendingImport(payload: .image(data, title: title, sourceURL: sourceURL, credit: credit), profileID: profile,
                             duplicateOf: match.duplicate, identicalTo: match.identical)
    }

    /// A video file (a copy the import owns) → a pending import with its poster; [] if unreadable.
    func prepareVideo(at url: URL, title: String, scope: PinScope) async -> [PendingImport] {
        let profile = profileID
        let poster = await LibraryStore.readVideo(at: url)
        guard let poster else { return [] }
        let match = await nearDuplicate(ofImageData: poster.jpegData, scope: scope)
        return [PendingImport(payload: .video(url, poster: poster, title: title), profileID: profile,
                              duplicateOf: match.duplicate ?? match.identical)]
    }

    func prepareText(title: String, body: String, scope: PinScope) -> PendingImport {
        PendingImport(payload: .text(title: title, body: body), profileID: profileID,
                      duplicateOf: duplicateTextPin(title: title, body: body, scope: scope))
    }

    /// Every link typed, pasted, dropped or read from a folder becomes a `.link` item here: without
    /// its tracking when "Clean links" is on (see `keptLink`).
    func prepareLink(_ url: URL, scope: PinScope) -> PendingImport {
        let link = keptLink(url)
        let existing = pinID(forLink: link.absoluteString, scope: scope).flatMap { livePin($0) }
        return PendingImport(payload: .link(link), profileID: profileID, duplicateOf: existing)
    }

    /// The first web address inside a piece of text, if the text is basically a link.
    nonisolated static func linkURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), trimmed.count < 2048 else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    // MARK: Importing — step 2: commit

    /// Imports what was prepared. Duplicates are skipped when asked; PinBoard's own
    /// files dropped back in are put on the board instead of being imported twice.
    /// `hidden`: the new pins go straight into the Hidden section (when no normal board was chosen).
    /// A pin you already have only counts when it is on the side imported into (it is
    /// never unhidden or hidden by an import); otherwise the item is imported as new.
    /// `addExisting`: items the person chose "Add the existing pin" for — their look-alike is
    /// put on the boards instead of importing them.
    /// An item read for another library than the one in use (`PendingImport.profileID`: another
    /// profile was chosen while its duplicate question waited) is dropped, not counted — like a
    /// folder import read for another library (`FolderImportPlan.profileID`).
    /// `keepsStatus`: the caller shows its own count ("Adding 3 of 12 shared items…", ShareInbox.swift),
    /// so this one neither replaces nor clears the status line.
    func commitImports(_ pending: [PendingImport], boardIDs: [UUID], skipDuplicates: Bool,
                       hidden: Bool = false, addExisting: Set<UUID> = [], keepsStatus: Bool = false) async -> ImportSummary {
        let profile = profileID   // the library this import belongs to (see `isCurrentProfile`)
        let side = importScope(boardIDs: boardIDs, hidden: hidden)
        beginLibraryWork()
        defer { endLibraryWork() }
        var summary = ImportSummary()
        beginBoardStampBatch()
        for (index, item) in pending.enumerated() {
            guard isCurrentProfile(profile) else {
                // Another profile now: the rest is dropped (the boards it was meant for are that library's).
                LibraryStore.discardTemporaryCopies(of: Array(pending[index...]))
                break
            }
            guard item.profileID == profile else {
                // Read for another library: its look-alike and its boards are that library's.
                LibraryStore.discardTemporaryCopies(of: [item])
                continue
            }
            if !keepsStatus { setImportStatus("Importing \(index + 1) of \(pending.count)…", scope: side) }
            let outcome = await commitPendingItem(item, batchBoardIDs: boardIDs, batchHidden: hidden,
                                                  skipDuplicates: skipDuplicates, addExisting: addExisting.contains(item.id),
                                                  profile: profile)
            summary.count(outcome)
        }
        endBoardStampBatch()
        if !keepsStatus { setImportStatus(nil, scope: side) }
        guard isCurrentProfile(profile) else { return summary }
        tidyNestedMemberships(for: Set(summary.newPinIDs))   // (boards chosen together: a board and one inside it → the inner one)
        countNewPins(summary.newPinIDs)
        await saveNowAndWait()   // on disk before "done" is shown (see LibrarySaving.swift)
        startAnalysisIfNeeded()
        startVideoMaintenanceIfNeeded(delay: 2)
        // A minute later the new originals iCloud has in full leave this device (MediaStorage.swift).
        if !summary.newPinIDs.isEmpty { scheduleOriginalsUpkeep(after: 60) }
        // Everything is in, each video exactly as imported: now the new videos are made smaller,
        // one at a time in the background (nothing waits for it).
        startConvertingNewVideos(summary.newPinIDs)
        return summary
    }

    /// Imports one prepared item: the one routine behind `commitImports` and `commitFolderImport`,
    /// so the two never disagree. A regular item lands on the batch's boards; a folder item on its
    /// sub-folder's board (made now) or its exported record's boards. A look-alike (`identicalTo`, or
    /// `duplicateOf` with `addExisting`) is put on those boards instead, when it is still live and on
    /// the side the item lands on. Temporary video copies are deleted; a folder's own files never are.
    /// `profile`: the library the import started in (nil = the current one); after a switch to
    /// another profile the item is dropped (`.skipped`).
    func commitPendingItem(_ item: PendingImport, batchBoardIDs: [UUID], batchHidden: Bool,
                           skipDuplicates: Bool, addExisting: Bool, profile: UUID? = nil) async -> PendingImportOutcome {
        let outcome = await commitPendingItemKeepingFiles(item, batchBoardIDs: batchBoardIDs, batchHidden: batchHidden,
                                                          skipDuplicates: skipDuplicates, addExisting: addExisting,
                                                          profile: profile ?? profileID)
        if case .video(let url, _, _) = item.payload { try? FileManager.default.removeItem(at: url) }
        return outcome
    }

    /// Deletes the temporary video copies of prepared items that will not be imported.
    nonisolated static func discardTemporaryCopies(of pending: [PendingImport]) {
        for item in pending {
            if case .video(let url, _, _) = item.payload { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func commitPendingItemKeepingFiles(_ item: PendingImport, batchBoardIDs: [UUID], batchHidden: Bool,
                                               skipDuplicates: Bool, addExisting: Bool, profile: UUID) async -> PendingImportOutcome {
        guard isCurrentProfile(profile) else { return .skipped }
        // An exported record keeps only its links to boards that exist here.
        let draft: Pin? = item.exported.map { exported in
            var record = exported.record
            record.boardIDs = record.boardIDs.filter { board($0) != nil }
            record.boardsBeforeHiding = record.boardsBeforeHiding.filter { board($0) != nil }
            record.deletedAt = nil
            return record
        }
        // The side it lands on. Plain folder items only ever land on normal boards (or the normal Unsorted).
        let side: PinScope
        let intoHidden: Bool
        if let draft {
            side = isHidden(draft) ? .hidden : .visible
            intoHidden = false
        } else if item.destinationPath != nil {
            side = .visible
            intoHidden = false
        } else {
            side = importScope(boardIDs: batchBoardIDs, hidden: batchHidden)
            intoHidden = batchHidden && batchBoardIDs.allSatisfy { secretCache.contains($0) }
        }
        /// The boards the item (or the pin standing in for it) goes on; a folder's board is made now.
        func destination() -> [UUID] {
            if let draft { return draft.boardIDs }
            if let path = item.destinationPath {
                guard !path.isEmpty, let boardID = board(forPath: path, createIfNeeded: true, visibleOnly: true) else { return [] }
                return [boardID]
            }
            return batchBoardIDs
        }
        func putOnBoards(_ existing: Pin) {
            for boardID in destination() where !existing.isOn(boardID) { addPins([existing.id], to: boardID) }
        }

        // A pin already here (a web result saved before, or one of PinBoard's own files).
        if let identicalID = item.identicalTo?.id {
            if let identical = livePin(identicalID), scope(of: identical) == side {
                putOnBoards(identical)
                return .alreadyHad
            }
            // Changed sides (or went away) meanwhile: a web result saved before has no
            // data of its own, so it can't be imported as new here.
            if case .image(let data, _, _, _) = item.payload, data.isEmpty, item.sourceFile == nil {
                return .skipped
            }
        }
        let twin = item.duplicateOf.flatMap { livePin($0.id) }.flatMap { scope(of: $0) == side ? $0 : nil }
        if let twin, addExisting {
            putOnBoards(twin)
            return .addedExisting
        }
        if skipDuplicates, twin != nil {
            return .skipped
        }

        // A new pin (a folder's board is made only once the item is known to be readable).
        if let draft, let exported = item.exported {
            let newID = await importExported(draft, exported, payload: item.payload, sourceFile: item.sourceFile, profile: profile)
            return newID.map { PendingImportOutcome.imported($0) } ?? .skipped
        }
        let id: UUID?
        switch item.payload {
        case .image(var data, let title, let sourceURL, let credit):
            if data.isEmpty, let sourceFile = item.sourceFile {
                data = await LibraryStore.readFile(sourceFile) ?? Data()
                // Another profile now: not even the folder's board is made (it would be made in that library).
                guard isCurrentProfile(profile) else { return .skipped }
            }
            guard !data.isEmpty else { return .skipped }
            id = await storeImage(data, boardIDs: destination(), title: title, sourceURL: sourceURL, credit: credit,
                                  hidden: intoHidden, profile: profile)
        case .video(let url, let poster, let title):
            id = await storeVideo(at: url, poster: poster, boardIDs: destination(), title: title, reusingID: nil,
                                  hidden: intoHidden, profile: profile)
        case .text(let title, let body):
            id = addTextPin(title: title, body: body, boardIDs: destination(), hidden: intoHidden, titleByUser: item.titleFromUser)
        case .link(let url):
            id = await addLinkPin(url, boardIDs: destination(), hidden: intoHidden, resolved: item.resolvedLink)
        }
        // A picture or video that came from a link keeps what reading the link found (SmartLinks.swift).
        if let id, let resolved = item.resolvedLink, isCurrentProfile(profile) {
            switch item.payload {
            case .image, .video: applyLinkExtras(resolved, to: id)
            case .text, .link: break
            }
        }
        return id.map { PendingImportOutcome.imported($0) } ?? .skipped
    }

    /// Re-creates a record from a PinBoard export as it was (ids, tags, notes, boards…). Returns the new pin's id.
    private func importExported(_ draft: Pin, _ exported: ExportedPin, payload: PendingImport.Payload, sourceFile: URL?,
                                profile: UUID) async -> UUID? {
        switch payload {
        case .text:
            return insertImportedTextPin(draft)
        case .link:
            return await insertImportedLinkPin(draft, previewData: exported.previewData, featurePrint: exported.featurePrint)
        case .image(let data, _, _, _):
            var imageData = data
            if imageData.isEmpty, let sourceFile { imageData = await LibraryStore.readFile(sourceFile) ?? Data() }
            guard !imageData.isEmpty else { return nil }
            return await storeExported(draft, exported, imageData: imageData, videoURL: nil, profile: profile)
        case .video(let url, let poster, _):
            return await storeExported(draft, exported, imageData: poster.jpegData, videoURL: url, profile: profile)
        }
    }

    private func storeExported(_ draft: Pin, _ exported: ExportedPin, imageData: Data, videoURL: URL?, profile: UUID) async -> UUID? {
        var record = draft
        record.needsAnalysis = exported.featurePrint == nil || draft.needsAnalysis
        guard let newID = await storeDraft(record, imageData: imageData, featurePrint: exported.featurePrint,
                                           preserveFileMetadata: true, videoURL: videoURL, profile: profile) else { return nil }
        if let exif = exported.exif, let stored = pin(newID) {
            try? exif.write(to: exifFileURL(for: stored), options: .atomic)
        }
        return newID
    }

    // MARK: Text, link and video pins

    /// Adds a text pin. Its tags and (if empty) its title come from the text.
    /// `titleByUser`: the title was typed (it is the person's); otherwise it came from a file.
    @discardableResult
    func addTextPin(title: String, body: String, boardIDs: [UUID] = [], hidden: Bool = false, titleByUser: Bool = false) -> UUID? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty || !trimmedTitle.isEmpty else { return nil }
        var pin = Pin(boardIDs: boardIDs)
        pin.isHidden = hidden
        pin.kind = .text
        if !trimmedTitle.isEmpty {
            if titleByUser { pin.setUserTitle(trimmedTitle) } else { pin.setImportedTitle(trimmedTitle) }
        }
        pin.textBody = trimmedBody
        pin.needsAnalysis = true
        pins.insert(pin, at: 0)
        stampBoards(edited: Set(boardIDs), added: Set(boardIDs))
        scheduleSave()
        startAnalysisIfNeeded()
        return pin.id
    }

    // MARK: Highlights and quotes (an article's marked passages)

    /// Takes a highlight off an article pin. Returns whether one went.
    @discardableResult
    func removeHighlight(_ highlightID: UUID, from id: UUID) -> Bool {
        guard let current = pin(id), current.highlights.contains(where: { (mark: TextHighlight) -> Bool in mark.id == highlightID }) else { return false }
        modify(id) { (pin: inout Pin) in
            pin.highlights.removeAll { (mark: TextHighlight) -> Bool in mark.id == highlightID }
        }
        scheduleSave()
        return true
    }

    /// Replaces an article pin's highlights (a reading that moved the text re-anchors them).
    func setHighlights(_ highlights: [TextHighlight], for id: UUID) {
        guard let current = pin(id), current.highlights != highlights else { return }
        modify(id) { (pin: inout Pin) in pin.highlights = highlights }
        scheduleSave()
    }

    /// "Save as pin" for a passage of an article: a text pin with the quote as its text, named
    /// after the article, on the article's boards (so it sits next to it, hidden when the article
    /// is hidden, kept out of All when it is), pointing back at the article (`quotedFromID`) and
    /// at the article's page (`sourceURL`, so "Open source page" works on it). The AI then tags
    /// it from its text. Returns the new pin's id (nil: nothing to save).
    @discardableResult
    func addQuotePin(from sourceID: UUID, quote: String) -> UUID? {
        let text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let source = pin(sourceID), !source.isDeleted else { return nil }
        var pin = Pin(boardIDs: source.boardIDs)
        pin.kind = .text
        pin.textBody = text
        if !source.title.isEmpty { pin.setImportedTitle(source.title) }
        pin.quotedFromID = sourceID
        pin.sourceURL = source.isLink ? source.linkURL : source.sourceURL
        pin.credit = source.siteName.map { (site: String) -> String in "Read on \(site)" } ?? "Open the article"
        pin.isHidden = source.isHidden   // (on a hidden board it is hidden through the board already)
        // An article hidden with "Hide pin" keeps its normal boards in `boardsBeforeHiding` (its `boardIDs` are
        // only the hidden ones): its quote takes them too, so both come back to the same boards on Unhide.
        if source.isHidden { pin.boardsBeforeHiding = source.boardsBeforeHiding }
        pin.keptOutOfAll = source.keptOutOfAll
        pin.needsAnalysis = true
        pins.insert(pin, at: 0)
        stampBoards(edited: Set(source.boardIDs), added: Set(source.boardIDs))
        scheduleSave()
        startAnalysisIfNeeded()
        return pin.id
    }

    // MARK: Transcripts (the run itself is in VideoTranscripts.swift)

    /// The AI queue is at work now (a transcription run waits until it has ended).
    var isAIQueueBusy: Bool { analysisTask != nil }

    // MARK: A picture's or video's source link

    /// Changes where a picture, video or text pin came from ("Edit link…" / "Add link…" on a pin
    /// that is not a link pin): its `sourceURL`, cleaned of tracking when "Clean links" is on.
    /// An empty address takes the link away. A credit line that named the old site goes when the
    /// address now points at another site. Link pins change their address with `updateLinkPin`,
    /// not here (false). Returns whether anything changed.
    @discardableResult
    func setSourceLink(of id: UUID, to address: String?) -> Bool {
        guard let current = pin(id), !current.isLink, !current.isDeleted else { return false }
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var wanted: String? = nil
        if !trimmed.isEmpty {
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return false }
            wanted = keptLink(url).absoluteString
        }
        guard wanted != current.sourceURL else { return false }
        let oldHost = current.sourceURL.flatMap { (old: String) -> String? in Pin.host(ofLink: old) }
        let newHost = wanted.flatMap { (new: String) -> String? in Pin.host(ofLink: new) }
        modify(id) { (pin: inout Pin) in
            pin.sourceURL = wanted
            if oldHost != newHost { pin.credit = nil }
        }
        scheduleSave()
        return true
    }

    /// Adds a link pin (without its tracking when "Clean links" is on) and, if allowed, fetches
    /// the page's title and preview picture. Until then its title is the site's name, which the
    /// AI may replace.
    /// `resolved`: what reading the link found before the import (SmartLinks.swift); then it is
    /// applied instead of fetching the page again.
    @discardableResult
    func addLinkPin(_ url: URL, boardIDs: [UUID] = [], hidden: Bool = false, resolved: ResolvedLink? = nil) async -> UUID? {
        let url = keptLink(url)
        var pin = Pin(boardIDs: boardIDs)
        pin.isHidden = hidden
        pin.kind = .link
        pin.linkURL = url.absoluteString
        let untitled = TitleState(title: "", isAuto: false, editedByUser: false, lastAITitle: nil)
        pin.setAITitle(pin.linkHost ?? url.absoluteString, replacing: untitled)
        pin.needsAnalysis = false
        pins.insert(pin, at: 0)
        let id = pin.id
        stampBoards(edited: Set(boardIDs), added: Set(boardIDs))
        scheduleSave()
        if let resolved {
            await applyResolvedLink(resolved, to: id)
        } else {
            await fetchLinkPreview(for: id)
        }
        return id
    }

    /// Fetches (or re-fetches) a link pin's title, description and preview picture. What comes
    /// back is written only while the pin still links to the page that was fetched
    /// (`previewStillWanted`): pointed at another page meanwhile (Edit link), it is dropped — that
    /// page's own fetch fills the pin in.
    func fetchLinkPreview(for id: UUID) async {
        let settings = AppSettings.shared
        let profile = profileID
        guard let pin = pin(id), pin.isLink, let text = pin.linkURL, let url = URL(string: text) else { return }
        guard settings.fetchLinkPreviews, !settings.offlineMode else {
            modify(id) { $0.needsAnalysis = true }
            startAnalysisIfNeeded()
            return
        }
        let side = scope(of: pin)   // a link added to Hidden is never mentioned on the normal side
        setImportStatus("Fetching the link…", scope: side)
        // The page, then its picture (a page with none gets its best picture, or — when Settings says so — the
        // first picture a web image search for its title finds; a picture already here is kept, see LinkPictures.swift).
        let preview = await LinkPreviewFetcher.fetch(url, fallbackTitle: pin.title, keepsPicture: pin.hasPreview,
                                                     searchesWeb: side == .visible)   // a hidden link's title never goes to a search service
        setImportStatus(nil, scope: side)
        guard isCurrentProfile(profile), LibraryStore.previewStillWanted(for: self.pin(id), fetched: text) else { return }
        if let preview {
            modify(id) { pin in
                // The page's own title, unless the person has typed one.
                if let title = preview.title, !title.isEmpty, !pin.titleEditedByUser { pin.setImportedTitle(title) }
                pin.aiDescription = preview.description ?? ""
            }
            if let imageData = preview.imageData {
                await attachImage(imageData, to: id, forPage: text)
                guard isCurrentProfile(profile), LibraryStore.previewStillWanted(for: self.pin(id), fetched: text) else { return }
            }
        }
        modify(id) { $0.needsAnalysis = true }
        scheduleSave()
        startAnalysisIfNeeded()
    }

    /// Whether a preview fetched for the address `fetched` may still be written into `pin`: it is
    /// still a link pin, to the same page (the same `pageKey`: other tracking is the same page).
    nonisolated static func previewStillWanted(for pin: Pin?, fetched: String) -> Bool {
        guard let pin, pin.isLink, let link = pin.linkURL else { return false }
        return pageKey(link) == pageKey(fetched)
    }

    /// Stores a picture for a pin that was created without one (link previews).
    /// `keepingDate`: the pin keeps its change date (a re-imported record's preview is part of
    /// re-creating it, not an edit — see `reinsertedDate`).
    /// `forPage`: the address the picture was fetched for. The picture is then made next to the
    /// pin's files and put in their place only while the pin still links to that page
    /// (`previewStillWanted`) — a fetch for the old page that ends late never overwrites the new
    /// page's picture, nor is it left in the pin's files. Whenever it isn't put in place (it
    /// couldn't be made, another profile is in use now, another page), its passing files go.
    /// (Not private only so the tests can reach that clean-up.)
    func attachImage(_ data: Data, to id: UUID, keepingDate: Bool = false, forPage page: String? = nil) async {
        let profile = profileID
        guard let pin = pin(id) else { return }
        let imageURL = location.images.appendingPathComponent(pin.imageFileName)
        let thumbURL = location.thumbs.appendingPathComponent(pin.thumbFileName)
        // (For a fetched page: written under a passing name first, see `LibraryStore.incoming`.)
        let imageTarget = page == nil ? imageURL : LibraryStore.incoming(imageURL)
        let thumbTarget = page == nil ? thumbURL : LibraryStore.incoming(thumbURL)
        /// A fetched page's passing files go. (Without a page the picture was made straight into
        /// the pin's own files, which are never removed here.)
        func dropPassingFiles() {
            guard page != nil else { return }
            try? FileManager.default.removeItem(at: imageTarget)
            try? FileManager.default.removeItem(at: thumbTarget)
        }
        let prepared = try? await Task.detached(priority: .userInitiated) {
            try ImageProcessor.prepare(data: data, imageURL: imageTarget, thumbURL: thumbTarget)
        }.value
        // Not made (it may have written the picture before failing on the thumbnail), or another
        // profile now (the picture was written into that library's folder, for its pin).
        guard let prepared, isCurrentProfile(profile) else {
            dropPassingFiles()
            return
        }
        if let page {
            // Pointed at another page meanwhile: this picture is not the pin's any more.
            guard LibraryStore.previewStillWanted(for: self.pin(id), fetched: page),
                  LibraryStore.moveIntoPlace(imageTarget, imageURL) else {
                dropPassingFiles()
                return
            }
            // No new thumbnail: the old page's must not stay (the picture itself is shown instead).
            if !LibraryStore.moveIntoPlace(thumbTarget, thumbURL) {
                try? FileManager.default.removeItem(at: thumbTarget)
                try? FileManager.default.removeItem(at: thumbURL)
            }
        }
        thumbCache.removeObject(forKey: id.uuidString as NSString)
        fullCache.removeObject(forKey: id.uuidString as NSString)
        let fill: (inout Pin) -> Void = { pin in
            pin.width = prepared.width
            pin.height = prepared.height
            pin.hasPreview = true
            pin.hasFeaturePrint = false
            pin.dhash = nil
            pin.pictureRevision += 1   // a refreshed preview replaces the file: views load it again
        }
        if keepingDate { modifyKeepingDate(id, fill) } else { modify(id, fill) }
    }

    /// Where a file is written before it takes the place of `file` ("<name>.incoming", next to it,
    /// so the move is instant). Its name still starts with the pin's id, so the orphan sweep takes
    /// care of one left behind by a pin erased later (and of any left over for an hour: see
    /// `sweepOrphans`).
    nonisolated static func incoming(_ file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".incoming")
    }

    /// Where a picture an iCloud sync brought waits before it takes the place of `file`
    /// ("<name>.synced.incoming", next to it; see `CloudSync.StagedPicture`). Not the passing name
    /// of a link preview fetched here (`incoming`), so the two never take each other's file.
    nonisolated static func syncIncoming(_ file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".synced.incoming")
    }

    /// Puts `staged` in the place of `file` in one step: the system's rename, which replaces `file`
    /// at once (both are in the same folder). So there is never a moment without the file, and a
    /// rename that fails leaves `file` as it was. (FileManager's own move refuses to replace a file,
    /// and removing the old file first would leave none if the move then failed.) false: `staged`
    /// isn't there, or the rename failed — `file` is untouched either way.
    @discardableResult
    nonisolated static func moveIntoPlace(_ staged: URL, _ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: staged.path) else { return false }
        return rename(staged.path, file.path) == 0
    }

    /// The change date (`updatedAt`) of a record put back with its old id (an export keeps ids):
    /// its own date — so a newer edit made on another device still wins the next iCloud merge —
    /// unless it was erased here after that date: then just after the erase, so that erase (on its
    /// way to the other devices) doesn't erase it again (see `mergeDocuments`).
    nonisolated static func reinsertedDate(_ updatedAt: Date, erasedAt: Date?) -> Date {
        guard let erasedAt else { return updatedAt }
        return max(updatedAt, erasedAt.addingTimeInterval(1))
    }

    /// Re-creates a text pin from an export record (its id is kept when free — no pin has it, and no
    /// other import is putting files under it right now: see `reserveID`). Returns its id.
    /// A pin erased here before comes back for good: its tombstone goes. It keeps its own change
    /// date, moved just past that erase if it was erased here (see `reinsertedDate`).
    @discardableResult
    func insertImportedTextPin(_ record: Pin) -> UUID {
        var pin = record
        pin.kind = .text
        pin.deletedAt = nil
        if self.pin(pin.id) != nil || reservedIDs.contains(pin.id) { pin.id = UUID() }
        pin.updatedAt = LibraryStore.reinsertedDate(record.updatedAt, erasedAt: erased[pin.id])
        pins.insert(pin, at: 0)
        erased[pin.id] = nil
        stampBoards(edited: Set(pin.boardIDs), added: Set(pin.boardIDs))
        scheduleSave()
        if pin.needsAnalysis { startAnalysisIfNeeded() }
        return pin.id
    }

    /// Re-creates a link pin from an export record (preview from the exported picture, if any;
    /// the address without its tracking when "Clean links" is on). Returns its id (kept when free,
    /// as for `insertImportedTextPin`); its change date is kept as for `insertImportedTextPin`.
    /// The record is the pin, as for every record: only the picture facts are the import's. Putting
    /// the preview in place starts a picture's details over (`attachImage`), so the preview's
    /// fingerprint the export kept (`featurePrint`) and its short form (the record's `dhash`) go back
    /// with it — a link that was looked at is not looked at again, and keeps its place in "More like this".
    @discardableResult
    func insertImportedLinkPin(_ record: Pin, previewData: Data?, featurePrint: Data? = nil) async -> UUID {
        let profile = profileID
        var pin = record
        pin.kind = .link
        pin.deletedAt = nil
        pin.hasPreview = false
        if AppSettings.shared.cleanLinks, let link = pin.linkURL { pin.linkURL = LinkCleaner.cleaned(link) }
        if self.pin(pin.id) != nil || reservedIDs.contains(pin.id) { pin.id = UUID() }
        pin.updatedAt = LibraryStore.reinsertedDate(record.updatedAt, erasedAt: erased[pin.id])
        pins.insert(pin, at: 0)
        erased[pin.id] = nil
        stampBoards(edited: Set(pin.boardIDs), added: Set(pin.boardIDs))
        let id = pin.id
        if let previewData {
            await attachImage(previewData, to: id, keepingDate: true)
            if let featurePrint, isCurrentProfile(profile), let attached = self.pin(id), attached.hasPreview {
                try? featurePrint.write(to: printsURL.appendingPathComponent(attached.printFileName), options: .atomic)
                printCache[id] = nil
                printsMissing.remove(id)
                modifyKeepingDate(id) { (restored: inout Pin) -> Void in
                    restored.hasFeaturePrint = true
                    restored.dhash = record.dhash
                }
            }
        }
        scheduleSave()
        startAnalysisIfNeeded()
        return id
    }

    /// The poster frame, length and whether there is sound — read off the main thread.
    nonisolated static func readVideo(at url: URL) async -> VideoPoster? {
        await Task.detached(priority: .userInitiated) { () -> VideoPoster? in
            guard var poster = await VideoTools.poster(for: url) else { return nil }
            poster.hasAudio = await VideoTools.hasAudio(for: url)
            return poster
        }.value
    }

    /// The poster came from `VideoTools.poster`, which already skips black frames (posterChecked).
    /// `profile`: the library the import started in (nil = the current one; see `storeImage`).
    /// The video is put in place first — copied exactly as it is, its original kept when "Keep
    /// originals in a folder" is on (never for a hidden video; MediaStorage.swift) — and only then
    /// is the pin made, so it never shows before its video is there. It is made smaller later, in
    /// the background, when the whole import is in (`startConvertingNewVideos`). Its id is reserved
    /// meanwhile, so no other import takes it. A video that can't be put in place makes no pin
    /// (nil). Its side is looked at again once the pin is made: a board hidden during the wait
    /// means no original.
    private func storeVideo(at url: URL, poster: VideoPoster, boardIDs: [UUID], title: String, reusingID: UUID?,
                            hidden: Bool = false, profile: UUID? = nil) async -> UUID? {
        let owner = profile ?? profileID
        guard isCurrentProfile(owner) else { return nil }
        let newID = reserveID(reusing: reusingID)
        defer { reservedIDs.remove(newID) }
        let side: PinScope = hidden || boardIDs.contains(where: { isSecretBoard($0) }) ? .hidden : .visible
        guard var placed = await placeImportedVideo(from: url, pinID: newID, side: side, profile: owner,
                                                    keepsOriginal: side == .visible) else { return nil }
        // Another profile now: the files belong to no pin here (nor there), so they go.
        guard isCurrentProfile(owner) else {
            discardPlacedVideo(placed)
            return nil
        }
        let ext = placed.outcome.fileExtension ?? StoragePolicy.libraryExtension(of: url)
        guard let id = await storeImage(poster.jpegData, boardIDs: boardIDs, title: title, sourceURL: nil, credit: nil,
                                        reusingID: newID, kind: .video, videoExtension: ext, duration: poster.duration,
                                        hasAudio: poster.hasAudio, hidden: hidden, posterChecked: true, profile: owner) else {
            discardPlacedVideo(placed, unlessTakenBy: newID, owner: owner)
            return nil
        }
        guard id == newID else {
            // Its id was taken meanwhile (an iCloud sync brought a pin with it), so the video's
            // file isn't named after this pin: this pin can't stay.
            erasePins([id])
            discardPlacedVideo(placed, unlessTakenBy: newID, owner: owner)
            return nil
        }
        // Its board was hidden while the video was put in place (or while the pin was made — this
        // comes after every wait): a hidden pin keeps no original the video doesn't need.
        if let made = pin(id), isHidden(made) { placed.dropOriginalUnlessConverted() }
        recordPlacedVideo(placed, for: id)
        scheduleSave()
        return id
    }

    /// `id` when no pin has it (an export's record keeps its id) and no other import is putting
    /// files under it right now, else a new one — reserved either way, until the caller releases
    /// it (`reservedIDs.remove`) once its pin is made or given up. Why: an import places its video
    /// under the id before the pin exists, which can take minutes; the same export imported twice
    /// at once must not end with two pins sharing one file (nor one removing the other's).
    private func reserveID(reusing id: UUID?) -> UUID {
        if let id, pin(id) == nil, !reservedIDs.contains(id) {
            reservedIDs.insert(id)
            return id
        }
        let fresh = UUID()
        reservedIDs.insert(fresh)
        return fresh
    }

    /// `discardPlacedVideo`, unless a pin with `id` exists now in the library the files were put
    /// in (`owner`'s): an iCloud sync brought it while this import was placing them, so the files
    /// under that id are that pin's, and they stay.
    private func discardPlacedVideo(_ placed: PlacedVideo, unlessTakenBy id: UUID, owner: UUID) {
        if !isCurrentProfile(owner) || pin(id) == nil { discardPlacedVideo(placed) }
    }

    /// Copies a (possibly large) file off the main thread. Replaces any file at the destination.
    /// The copy is dated now: a copy can otherwise keep its source's date (it does on iOS), and the
    /// orphan sweep tells a re-imported pin's new file from a leftover of its erase by the date.
    nonisolated static func copyFile(from source: URL, to destination: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return false }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return true
        }.value
    }

    nonisolated static func readFile(_ url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    }

    func videoFileURL(for pin: Pin) -> URL { videosURL.appendingPathComponent(pin.videoFileName) }

    // MARK: Importing — one-step paths (used by the folder importer)

    /// Writes the files and inserts the pin (still to be analyzed). Returns its id.
    /// `profile`: the library the import started in (nil = the current one). If another profile is
    /// in use by the time the picture is written, nothing is inserted (it would land in that
    /// library, on this one's boards): the files just written are removed and nil is returned.
    /// `keptDate`: a re-imported export record's own change date, kept instead of now (see
    /// `reinsertedDate`); nil for a new pin.
    /// `keepOriginal`: a picture's untouched file (`data`, as imported) also goes to the originals
    /// folder when Settings › iCloud & storage › "Keep originals in a folder" is on and the folder can be
    /// reached (MediaStorage.swift). Never for a video's poster frame, not for an export's own copy
    /// (it isn't the original), and never for a picture going into Hidden (anyone who opens the
    /// Files app could see it there) — also when its board is hidden while the copy is made.
    /// `reusingID`: the id to give the pin when no pin has it. If a pin with it arrives while the
    /// picture is being written (an iCloud sync), nothing is inserted (nil): two pins never share an id.
    private func storeImage(_ data: Data,
                            boardIDs: [UUID],
                            title: String,
                            sourceURL: String?,
                            credit: String?,
                            reusingID: UUID? = nil,
                            kind: PinKind = .image,
                            videoExtension: String? = nil,
                            duration: Double? = nil,
                            hasAudio: Bool? = nil,
                            hidden: Bool = false,
                            posterChecked: Bool = false,
                            keepOriginal: Bool = true,
                            keptDate: Date? = nil,
                            profile: UUID? = nil) async -> UUID? {
        let owner = profile ?? profileID
        guard isCurrentProfile(owner) else { return nil }
        var pin = Pin(boardIDs: boardIDs)
        if let reusingID, self.pin(reusingID) == nil { pin.id = reusingID }
        pin.kind = kind
        pin.videoExtension = videoExtension
        pin.duration = duration
        pin.hasAudio = kind == .video ? hasAudio : nil
        pin.posterChecked = kind == .video && posterChecked
        pin.isHidden = hidden
        pin.setImportedTitle(title)   // a file name or a web page's title: neither typed nor the AI's
        pin.sourceURL = sourceURL
        pin.credit = credit
        let imageURL = imagesURL.appendingPathComponent(pin.imageFileName)
        let thumbURL = thumbsURL.appendingPathComponent(pin.thumbFileName)
        let exifFile = exifURL.appendingPathComponent(pin.exifFileName)   // this library's folder, known before the wait
        let prepared = try? await Task.detached(priority: .userInitiated) {
            try ImageProcessor.prepare(data: data, imageURL: imageURL, thumbURL: thumbURL)
        }.value
        guard let prepared else { return nil }
        // A readable picture: its untouched original goes to the originals folder too, when kept —
        // never a hidden one's.
        let intoHidden = hidden || boardIDs.contains(where: { isSecretBoard($0) })
        var kept: KeptOriginal? = nil
        if kind == .image, keepOriginal, !intoHidden, isCurrentProfile(owner) {
            kept = await keepOriginalPicture(data, for: pin.id, profile: owner)
        }
        guard isCurrentProfile(owner) else {
            // Another profile now: no pin points at these files, so they go.
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: thumbURL)
            if let kept { LibraryStore.dropOriginal(kept.name, in: kept.folder) }
            return nil
        }
        // Its board was hidden while the original was being copied: a hidden pin's original never
        // goes to the folder, so the copy goes again. (The picture is in the library as usual — the
        // same as a picture imported into Hidden.)
        if let copied = kept, hidden || boardIDs.contains(where: { isSecretBoard($0) }) {
            LibraryStore.dropOriginal(copied.name, in: copied.folder)
            kept = nil
        }
        // Its reused id was taken meanwhile (an iCloud sync brought that record): nothing is
        // inserted. The files just written stay: they are named after that pin now (the same
        // record's picture), and a leftover is the safe side.
        if let reusingID, pin.id == reusingID, self.pin(reusingID) != nil { return nil }
        pin.originalName = kept?.name
        pin.originalBytes = kept?.bytes
        pin.width = prepared.width
        pin.height = prepared.height
        let metadata = prepared.metadata
        pin.capturedAt = metadata.capturedAt
        pin.cameraModel = metadata.cameraModel
        pin.latitude = metadata.latitude
        pin.longitude = metadata.longitude
        pin.fileKeywords = metadata.keywords
        pin.fileCaption = metadata.caption
        if pin.title.isEmpty, let fileTitle = metadata.title { pin.setImportedTitle(fileTitle) }
        if let plist = metadata.propertiesPlist {
            try? plist.write(to: exifFile, options: .atomic)
        }
        // A re-imported record keeps its own change date (just past its erase here, if it was erased).
        if let keptDate { pin.updatedAt = LibraryStore.reinsertedDate(keptDate, erasedAt: erased[pin.id]) }
        pins.insert(pin, at: 0)
        erased[pin.id] = nil   // a re-imported pin (its old id kept) is no longer erased
        stampBoards(edited: Set(boardIDs), added: Set(boardIDs))
        scheduleSave()
        return pin.id
    }

    /// Saves a web result that was already analyzed as a draft (so the tags,
    /// title and notes chosen on its page are kept, and no re-analysis runs).
    /// `preserveFileMetadata` is used when re-importing an export: the exported JPEG
    /// carries PinBoard's own tags in its metadata, so the record's original values win.
    func importDraft(_ draft: Pin, imageData: Data, featurePrint: Data?, preserveFileMetadata: Bool = false, videoURL: URL? = nil) async -> UUID? {
        let profile = profileID   // the library this save belongs to (the draft's boards are its boards)
        beginLibraryWork()
        defer { endLibraryWork() }
        let id = await storeDraft(draft, imageData: imageData, featurePrint: featurePrint,
                                  preserveFileMetadata: preserveFileMetadata, videoURL: videoURL, profile: profile)
        if let id, isCurrentProfile(profile) {
            tidyNestedMemberships(for: [id])
            countNewPins([id])
            if videoURL != nil { startConvertingNewVideos([id]) }   // its video is made smaller afterwards, in the background
        }
        return id
    }

    /// `importDraft` without counting the pin for the back-up reminder (imports count once at the end).
    /// `profile`: the library the save started in; after a switch to another profile it is dropped (nil).
    /// `preserveFileMetadata` (re-importing an export: the record's id is reused) also keeps the
    /// record's own change date — filling in what the export kept is not an edit (see `reinsertedDate`).
    /// A video is put in place before the pin is made, as in `storeVideo` (copied as it is; made
    /// smaller afterwards), under an id reserved meanwhile (`reserveID`). An export's
    /// own copies are not put in the originals folder by the restore itself: they aren't the
    /// originals. (If such a video is converted later, with "Keep originals" on, the copy the
    /// library holds then is kept as its original first — it is the only full-size copy the person
    /// has, so that is right; round 14, finding R1-10, accepted as it is.) Nor is anything going
    /// into Hidden (`isHidden(draft)`: hidden pins' originals never go to the folder) — looked at
    /// again once the pin is made, in case its board was hidden during the wait.
    private func storeDraft(_ draft: Pin, imageData: Data, featurePrint: Data?, preserveFileMetadata: Bool, videoURL: URL?,
                            profile: UUID) async -> UUID? {
        var hasAudio = draft.hasAudio
        if let videoURL, hasAudio == nil {
            hasAudio = await Task.detached(priority: .userInitiated) { () -> Bool in
                await VideoTools.hasAudio(for: videoURL)
            }.value
        }
        let newID = reserveID(reusing: preserveFileMetadata ? draft.id : nil)
        defer { reservedIDs.remove(newID) }
        let side: PinScope = isHidden(draft) ? .hidden : .visible
        var placed: PlacedVideo? = nil
        if let videoURL {
            guard isCurrentProfile(profile) else { return nil }
            guard let done = await placeImportedVideo(from: videoURL, pinID: newID, side: side, profile: profile,
                                                      keepsOriginal: !preserveFileMetadata && side == .visible) else { return nil }
            guard isCurrentProfile(profile) else {
                discardPlacedVideo(done)
                return nil
            }
            placed = done
        }
        // (storeImage checks the profile before and after its own wait.)
        guard let id = await storeImage(imageData, boardIDs: draft.boardIDs, title: draft.title,
                                        sourceURL: draft.sourceURL, credit: draft.credit,
                                        reusingID: placed != nil || preserveFileMetadata ? newID : nil,
                                        kind: videoURL == nil ? .image : .video,
                                        videoExtension: placed?.outcome.fileExtension,
                                        duration: draft.duration,
                                        hasAudio: hasAudio,
                                        hidden: draft.isHidden,
                                        keepOriginal: !preserveFileMetadata && side == .visible,
                                        keptDate: preserveFileMetadata ? draft.updatedAt : nil,
                                        profile: profile) else {
            if let placed { discardPlacedVideo(placed, unlessTakenBy: newID, owner: profile) }
            return nil
        }
        if var placed {
            guard id == newID else {
                // Its id was taken meanwhile (an iCloud sync brought that record), so the video's
                // file isn't named after this pin: this pin can't stay.
                erasePins([id])
                discardPlacedVideo(placed, unlessTakenBy: newID, owner: profile)
                return nil
            }
            // Its board was hidden while the video was put in place (or the pin was made — this
            // comes after every wait): a hidden pin keeps no original the video doesn't need.
            if let made = pin(id), isHidden(made) { placed.dropOriginalUnlessConverted() }
            recordPlacedVideo(placed, for: id, keepingDate: preserveFileMetadata)
        }
        // Only now touch the record — always by id, never by a remembered position (and only in its own library).
        guard isCurrentProfile(profile), pin(id) != nil else { return nil }
        if let featurePrint {
            try? featurePrint.write(to: printsURL.appendingPathComponent("\(id.uuidString).fp"), options: .atomic)
        }
        let fill: (inout Pin) -> Void = { pin in
            if preserveFileMetadata {
                // A re-imported export record IS the pin (`ExportedRecord`, Export.swift): every field of
                // it comes back — fields added later too, nobody has to remember them — and only what the
                // import found out about the files is put over it.
                pin = ExportedRecord.pin(from: draft, made: pin, hasFeaturePrint: featurePrint != nil)
                return
            }
            // A web result saved from its draft: what its page chose (the rest is what a new pin has).
            pin.titleIsAuto = draft.titleIsAuto
            pin.titleEditedByUser = draft.titleEditedByUser
            pin.lastAITitle = draft.lastAITitle
            pin.titleUndo = draft.titleUndo
            pin.note = draft.note
            pin.tags = draft.tags
            pin.aiTags = draft.aiTags
            pin.colorTags = draft.colorTags
            pin.ocrTags = draft.ocrTags
            pin.ocrText = draft.ocrText
            pin.aiDescription = draft.aiDescription
            pin.aiSearchHint = draft.aiSearchHint
            pin.dhash = draft.dhash
            pin.needsAnalysis = draft.needsAnalysis
            pin.placementReason = draft.placementReason
            pin.notDuplicateOf = draft.notDuplicateOf
            pin.hasFeaturePrint = featurePrint != nil
            pin.isHidden = draft.isHidden
            pin.boardsBeforeHiding = draft.boardsBeforeHiding
            pin.keptOutOfAll = draft.keptOutOfAll
        }
        // A re-imported record keeps the date storeImage gave it (see `keptDate`).
        if preserveFileMetadata { modifyKeepingDate(id, fill) } else { modify(id, fill) }
        if let stored = pin(id), let twin = findDuplicate(of: stored), twin.createdAt <= stored.createdAt {
            let markTwin: (inout Pin) -> Void = { pin in pin.duplicateOfID = twin.id }
            if preserveFileMetadata { modifyKeepingDate(id, markTwin) } else { modify(id, markTwin) }
        }
        scheduleSave()
        startAnalysisIfNeeded()
        return id
    }

    /// "IMG_2041" → "" (useless), "golden-retriever_beach" → "golden retriever beach"
    func cleanFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let letters = cleaned.filter { $0.isLetter }.count
        let digits = cleaned.filter { $0.isNumber }.count
        // Camera-style names (IMG_1234, DSC00012, 20240101_1200) aren't worth keeping.
        if letters < 4 || digits > letters { return "" }
        return cleaned
    }
}
