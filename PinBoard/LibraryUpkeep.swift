//
//  LibraryUpkeep.swift  —  PinBoard
//
//  The part of `LibraryStore` that looks after what is already in the library: Recently deleted,
//  the sweep for leftover and missing files, duplicates, video upkeep (length, sound, black
//  posters), turning pictures, loading pictures for display, and look-alikes (feature prints).
//  It is an extension in its own file so that LibraryStore.swift stays short enough to paste.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

extension LibraryStore {

    // MARK: Recently deleted

    /// Moves pins to "Recently deleted"; files stay until they are erased.
    /// A hidden pin is kept hidden on its own (see `keepHidden`), so it stays in the hidden
    /// list of Recently Deleted (and stays hidden when restored) even if its hidden boards go away.
    func deletePins(_ ids: Set<UUID>) {
        let now = Date()
        let secret = secretCache
        let leaving = ids.compactMap { pin($0) }.filter { !$0.isDeleted }
        stampBoards(edited: Set(leaving.flatMap { shownBoardIDs(for: $0) }))
        modify(ids) { pin in
            if LibraryStore.isHidden(pin, secretBoards: secret) { LibraryStore.keepHidden(&pin, secretBoards: secret) }
            pin.deletedAt = now
        }
        // Nothing should point at a trashed pin as its duplicate, and no board should show it as a cover.
        dropDuplicateLinks(pointingAt: ids)
        for board in boards where board.coverPinID != nil && ids.contains(board.coverPinID!) {
            setCover(nil, for: board.id)
        }
        scheduleSave()
    }

    func restorePins(_ ids: Set<UUID>) {
        let returning = ids.compactMap { pin($0) }.filter { $0.isDeleted }
        stampBoards(edited: Set(returning.flatMap { shownBoardIDs(for: $0) }))
        modify(ids) { $0.deletedAt = nil }
        scheduleSave()
        Task { await refreshDuplicates() }
    }

    /// Removes pins and their files for good — with their kept originals in the originals folder
    /// (Settings › iCloud & storage), when it can be reached. (Recently Deleted keeps everything.)
    func erasePins(_ ids: Set<UUID>) {
        let now = Date()
        var urls: [URL] = []
        var originals: [String] = []
        for pin in pins where ids.contains(pin.id) {
            urls.append(imagesURL.appendingPathComponent(pin.imageFileName))
            urls.append(thumbsURL.appendingPathComponent(pin.thumbFileName))
            urls.append(printsURL.appendingPathComponent(pin.printFileName))
            urls.append(exifURL.appendingPathComponent(pin.exifFileName))
            if pin.isVideo { urls.append(videosURL.appendingPathComponent(pin.videoFileName)) }
            OffloadIndex.shared.markHere(pin.id, in: location)   // (no longer counted as kept in iCloud)
            if let original = pin.originalName { originals.append(original) }
            thumbCache.removeObject(forKey: pin.id.uuidString as NSString)
            fullCache.removeObject(forKey: pin.id.uuidString as NSString)
            printCache[pin.id] = nil
            erased[pin.id] = now
        }
        let doomed = urls
        Task.detached(priority: .utility) {
            for url in doomed { try? FileManager.default.removeItem(at: url) }
        }
        discardOriginals(originals)   // (off the main thread, see MediaStorage.swift)
        var remaining = pins
        remaining.removeAll { ids.contains($0.id) }
        for index in remaining.indices {
            if let twin = remaining[index].duplicateOfID, ids.contains(twin) { remaining[index].duplicateOfID = nil }
            remaining[index].notDuplicateOf.removeAll { ids.contains($0) }
        }
        pins = remaining
        for board in boards where board.coverPinID != nil && ids.contains(board.coverPinID!) {
            setCover(nil, for: board.id)
        }
        missingFileIDs.subtract(ids)
        scheduleSave()
    }

    /// Erases the Recently Deleted pins of one scope (the normal library by default).
    func emptyTrash(scope: PinScope = .visible) {
        erasePins(Set(deletedPins(scope: scope).map { $0.id }))
    }

    /// Erases anything that has sat in "Recently deleted" for over 30 days.
    func purgeOldDeleted() {   // (not private: used by LibraryStore.swift)
        let cutoff = Date().addingTimeInterval(-Double(LibraryStore.trashRetentionDays) * 86_400)
        let old = pins.filter { ($0.deletedAt ?? .distantFuture) < cutoff }.map { $0.id }
        if !old.isEmpty { erasePins(Set(old)) }
    }

    /// Tombstones older than 90 days are no longer needed.
    func pruneTombstones() {   // (not private: used by LibraryStore.swift)
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        erased = erased.filter { $0.value > cutoff }
    }

    func reanalyze(_ ids: Set<UUID>) {
        modify(ids) { $0.needsAnalysis = true }
        scheduleSave()
        startAnalysisIfNeeded()
    }

    /// Runs the AI again on every live pin of a scope — also what "Re-run the cloud model on all
    /// pins" in Settings does. Settings is the normal side, so it asks for `.visible` (the default):
    /// a hidden pin is never queued, sent or counted from there.
    func reanalyze(scope: PinScope = .visible) {
        reanalyze(Set(pins(scope: scope).map { $0.id }))
    }

    /// Removes every pin, board and smart board of this profile.
    func clearLibrary() {
        analysisTask?.cancel()
        analysisTask = nil
        clearAnalysisProgress()
        namingTask?.cancel()
        namingTask = nil
        activeNamingRun = nil
        namingRunRecorded = false
        namingProgress = nil
        namingScope = nil
        forgetNamingRuns()   // the pins they renamed are gone
        maintenanceTask?.cancel()
        maintenanceTask = nil
        cancelTranscription()   // (the videos it listens to are gone)
        erasePins(Set(pins.map { $0.id }))
        let now = Date()
        for board in boards { erased[board.id] = now }
        for board in smartBoards { erased[board.id] = now }
        boards = []
        smartBoards = []
        thumbCache.removeAllObjects()
        fullCache.removeAllObjects()
        printCache = [:]
        analysingNow = []
        lookingBeforeNaming = []
        looksOutsideQueue = []
        pageKeyCache = [:]
        saveNow()
    }

    /// "1.3 GB on this device — videos 1 GB · pictures 300 MB" (see `LibrarySize`, OriginalsFolder.swift).
    func librarySizeDescription() async -> String {
        await LibrarySize.measure(location).text
    }

    /// Adds up every file under `root`. Plain synchronous code, because
    /// FileManager's enumerator can't be iterated from an async function.
    nonisolated static func folderSize(at root: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }
            if let values = try? url.resourceValues(forKeys: Set(keys)),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: Orphan sweep and missing files

    /// Deletes the files left behind by pins that were erased for good, and notes pins whose
    /// files are gone.
    ///
    /// A file is deleted only when its pin was erased for good (its id is in `erased`, say by
    /// another device through iCloud, or the app stopped before an erase had removed the files),
    /// no pin has that id now, the file is older than that erase and over an hour old — never
    /// just because no pin points at it. After restoring an earlier copy, or when a damaged
    /// library file was replaced by a backup at launch, the pins added since that copy are missing
    /// from the list, yet their pictures and videos are still theirs (and come back with a newer
    /// copy or an export): deleting "files of no pin" would lose those photos for good.
    /// "Older than the erase": an export keeps its pins' ids, so an erased pin can be imported
    /// again — its new files are dated after the erase (imports date what they write now, see
    /// `copyFile`), and an older copy of the list restored later still has that id's tombstone.
    /// Leftovers of an import that crashed may stay: the safe side. The one other kind of file
    /// removed: one still under a passing name ("….incoming") after an hour — never a pin's picture.
    func sweepOrphans() async {
        let profile = profileID
        let known = Set(pins.map { $0.id })
        // When each id that no pin has now was erased for good.
        var tombstones: [UUID: Date] = [:]
        for (id, erasedAt) in erased where !known.contains(id) { tombstones[id] = erasedAt }
        let erasedAt = tombstones
        let target = location
        let offloaded = OffloadIndex.shared.offloadedIDs(in: target)   // in iCloud only: not missing (Offloading.swift)
        let checks: [(UUID, URL)] = pins.compactMap { pin in
            guard !pin.isDeleted, !offloaded.contains(pin.id) else { return nil }
            switch pin.kind {
            case .text: return nil
            case .link: return pin.hasPreview ? (pin.id, target.images.appendingPathComponent(pin.imageFileName)) : nil
            case .image: return (pin.id, target.images.appendingPathComponent(pin.imageFileName))
            case .video: return (pin.id, target.videos.appendingPathComponent(pin.videoFileName))
            }
        }
        let result = await Task.detached(priority: .utility) { () -> (removed: Int, missing: Set<UUID>) in
            var removed = 0
            let cutoff = Date().addingTimeInterval(-3600)
            for folder in target.allFolders {
                guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for file in files {
                    let name = file.lastPathComponent
                    // A file still under a passing name ("….incoming": a fetched preview or a
                    // picture from iCloud waiting to be put in place) an hour later is a leftover:
                    // the app was closed in between. It is never any pin's picture.
                    if name.hasSuffix(".incoming") {
                        let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        if let written, written < cutoff, (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
                        continue
                    }
                    // Only the files of a pin erased for good that no pin has now (see above).
                    guard let id = UUID(uuidString: String(name.prefix(36))), let erasedOn = erasedAt[id] else { continue }
                    // A file whose date can't be read is kept (the safe side).
                    guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
                    guard modified < erasedOn else { continue }   // written after the erase: a re-import's
                    guard modified < cutoff else { continue }     // an import may still be finishing
                    if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
                }
            }
            var missing: Set<UUID> = []
            for (id, url) in checks where !FileManager.default.fileExists(atPath: url.path) { missing.insert(id) }
            return (removed, missing)
        }.value
        // Switched to another profile meanwhile: that library's findings don't apply here.
        guard isCurrentProfile(profile) else { return }
        missingFileIDs = result.missing
    }

    /// "Remove pins whose files are missing" (Settings → Recover library): moves them to Recently
    /// Deleted, like any delete (30 days to change your mind) — never erased for good, which would
    /// erase them on your other devices too. Only pins of `scope` are touched: Settings is the
    /// normal side, so a hidden pin is never moved (or counted) from there.
    func removeMissingFilePins(scope: PinScope = .visible) {
        let ids = missingFilePinIDs(scope: scope)
        guard !ids.isEmpty else { return }
        deletePins(ids)
        missingFileIDs.subtract(ids)
    }

    /// How many live pins of one side have a missing file (for the rows in Settings).
    func missingFileCount(scope: PinScope) -> Int {
        missingFilePinIDs(scope: scope).count
    }

    /// The live pins of one side among `missingFileIDs`.
    private func missingFilePinIDs(scope: PinScope) -> Set<UUID> {
        let wantHidden = scope == .hidden
        var result: Set<UUID> = []
        for id in missingFileIDs {
            guard let pin = livePin(id), isHidden(pin) == wantHidden else { continue }
            result.insert(id)
        }
        return result
    }

    // MARK: Duplicates

    /// The small, cheap description of every live pin that duplicate checks need.
    struct HashEntry: Sendable {   // (not private: used by LibraryImports.swift)
        var id: UUID
        var hash: UInt64
        var aspect: Double
        var createdAt: Date
        var notDuplicateOf: [UUID]
        var hidden: Bool
    }

    func hashEntries() -> [HashEntry] {   // (not private: used by LibraryImports.swift)
        livePins.compactMap { pin in
            guard let hash = pin.dhash, hash != 0 else { return nil }
            return HashEntry(id: pin.id, hash: hash, aspect: Double(pin.aspectRatio), createdAt: pin.createdAt,
                             notDuplicateOf: pin.notDuplicateOf, hidden: isHidden(pin))
        }
    }

    /// The closest look-alike among the entries of one side of the library only
    /// (`hidden`: among hidden pins; otherwise among normal pins) — a pair never spans the hidden line.
    nonisolated static func bestMatch(for hash: UInt64, aspect: Double, id: UUID?, notDuplicateOf: [UUID],   // (not private: used by LibraryImports.swift)
                                      among entries: [HashEntry], maxDistance: Int, hidden: Bool) -> UUID? {
        guard hash != 0 else { return nil }
        var best: (UUID, Int)? = nil
        for entry in entries where entry.id != id {
            if entry.hidden != hidden { continue }
            if let id, entry.notDuplicateOf.contains(id) { continue }
            if notDuplicateOf.contains(entry.id) { continue }
            let distance = ImageSignals.hammingDistance(hash, entry.hash)
            guard distance <= maxDistance else { continue }
            let ratio = entry.aspect / max(aspect, 0.01)
            guard ratio > 0.85 && ratio < 1.18 else { continue }
            if best == nil || distance < best!.1 { best = (entry.id, distance) }
        }
        return best?.0
    }

    /// An existing live pin that looks identical to `pin` (perceptual hash), on the
    /// pin's own side of the library (a draft or new pin counts as a normal one).
    func findDuplicate(of pin: Pin) -> Pin? {
        guard let hash = pin.dhash else { return nil }
        let hidden = isHidden(pin)
        guard let id = LibraryStore.bestMatch(for: hash, aspect: Double(pin.aspectRatio), id: pin.id, notDuplicateOf: pin.notDuplicateOf,
                                              among: hashEntries(), maxDistance: LibraryStore.duplicateHashDistance, hidden: hidden) else { return nil }
        return livePin(id)
    }

    var duplicatePins: [Pin] { duplicatePins(scope: .visible) }

    /// Pins of a scope that look identical to an older pin of the same scope
    /// (a pair with one pin on each side of the hidden line is never listed).
    func duplicatePins(scope: PinScope) -> [Pin] {
        let hiddenIDs = scopeSplit.hiddenIDs
        let wantHidden = scope == .hidden
        return pins(scope: scope).filter { pin in
            guard let twin = pin.duplicateOfID, livePin(twin) != nil else { return false }
            return hiddenIDs.contains(twin) == wantHidden
        }
    }

    /// The live look-alike a pin points at, only when both are on the same side of the library.
    func duplicateTwin(of pin: Pin) -> Pin? {
        guard let twinID = pin.duplicateOfID, let twin = livePin(twinID), isHidden(twin) == isHidden(pin) else { return nil }
        return twin
    }

    /// "Keep both": remembers that these two are different, so re-checks skip the pair.
    func keepBoth(_ newerID: UUID, _ originalID: UUID) {
        modify(newerID) { pin in
            if pin.duplicateOfID == originalID { pin.duplicateOfID = nil }
            if !pin.notDuplicateOf.contains(originalID) { pin.notDuplicateOf.append(originalID) }
        }
        scheduleSave()
    }

    /// Forgets every "Keep both" decision, then checks everything again.
    func resetDuplicateDecisions() async {
        let all = Set(pins.map { $0.id })
        modify(all) { $0.notDuplicateOf = [] }
        await refreshDuplicates()
    }

    /// Re-checks every pin (after imports or restores). The comparison runs
    /// off the main thread on small values, so big libraries don't freeze.
    func refreshDuplicates() async {
        let profile = profileID
        let entries = hashEntries()
        let maxDistance = LibraryStore.duplicateHashDistance
        // Only the newer of a pair is marked, so the original stays clean.
        let matches: [UUID: UUID] = await Task.detached(priority: .utility) {
            var found: [UUID: UUID] = [:]
            let created: [UUID: Date] = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.createdAt) })
            for entry in entries {
                if let match = LibraryStore.bestMatch(for: entry.hash, aspect: entry.aspect, id: entry.id, notDuplicateOf: entry.notDuplicateOf,
                                                      among: entries, maxDistance: maxDistance, hidden: entry.hidden),
                   let otherCreated = created[match], otherCreated <= entry.createdAt {
                    found[entry.id] = match
                }
            }
            return found
        }.value
        // Another profile now: these matches are about the other library's pins (applied here they
        // would clear every duplicate mark of this one).
        guard isCurrentProfile(profile) else { return }
        let changed = Set(livePins.filter { matches[$0.id] != $0.duplicateOfID }.map { $0.id })
        guard !changed.isEmpty else { return }
        modify(changed) { pin in pin.duplicateOfID = matches[pin.id] }
        scheduleSave()
    }

    /// Keeps one of a duplicate pair with everything the other had (boards, tags),
    /// then moves the other to Recently Deleted. `title`/`note` pick the winner's wording.
    func mergeDuplicates(keep keepID: UUID, remove removeID: UUID, title: String? = nil, note: String? = nil) {
        guard let removed = pin(removeID), let kept = pin(keepID) else { return }
        let before = Set(shownBoardIDs(for: kept))
        modify(keepID) { pin in
            for boardID in removed.boardIDs where !pin.boardIDs.contains(boardID) { pin.boardIDs.append(boardID) }
            for tag in removed.tags where !pin.tags.contains(tag) { pin.tags.append(tag) }
            if let title { pin.setUserTitle(title) }   // chosen by the person
            if let note { pin.note = note }
            if pin.title.isEmpty, !removed.title.isEmpty {
                // The kept copy had no title: it takes the other one's, with who wrote it.
                pin.title = removed.title
                pin.titleIsAuto = removed.titleIsAuto
                pin.titleEditedByUser = removed.titleEditedByUser
                pin.lastAITitle = removed.lastAITitle
                pin.titleUndo = nil
            }
            if pin.note.isEmpty { pin.note = removed.note }
            // A listened-to video's note is its transcript: when the note the kept video ends up with
            // holds those words, the kept video knows it ("transcript" says the note has them). Without
            // it the AI and search would take the recogniser's words for the person's own note, and the
            // next run would listen again and could add a second "Transcript:" block.
            if pin.isVideo, pin.transcript == nil, let words = removed.transcript,
               TranscriptNotes.squeezed(pin.note).contains(TranscriptNotes.squeezed(words)) {
                pin.transcript = words
                pin.transcriptChecked = true
            }
            pin.duplicateOfID = nil
            pin.notDuplicateOf.removeAll { $0 == removeID }
        }
        // Stamped: boards that show the kept pin now and didn't before (never a normal board
        // a hidden pin is only filed on, out of sight).
        tidyNestedMemberships(for: [keepID])   // (the two pins' boards together: a board and one inside it → the inner one)
        let joined = Set(pin(keepID).map { shownBoardIDs(for: $0) } ?? []).subtracting(before)
        stampBoards(edited: joined, added: joined)
        deletePins([removeID])
    }

    // MARK: Video upkeep (length, sound, black posters)

    /// For a video pin whose sound was never checked (hasAudio == nil): looks at the
    /// file's audio tracks off the main thread and stores the answer. Cheap to call
    /// repeatedly (one check per pin at a time; nothing happens once it is known).
    func ensureAudioInfo(for id: UUID) async {
        guard let current = pin(id), current.isVideo, current.hasAudio == nil, !audioChecks.contains(id) else { return }
        let profile = profileID
        audioChecks.insert(id)
        defer { audioChecks.remove(id) }
        let url = videoFileURL(for: current)
        let found = await Task.detached(priority: .utility) { () -> Bool? in
            // A file that is not there (yet) is asked about again later.
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return await VideoTools.hasAudio(for: url)
        }.value
        guard let found, isCurrentProfile(profile), let index = index(of: id), pins[index].hasAudio == nil else { return }
        // Worked out from the file itself, so it doesn't count as an edit (updatedAt stays,
        // and a sync never lets this win over a real change made on another device).
        pins[index].hasAudio = found
        scheduleSave()
        if found { startTranscribingIfNeeded() }   // a sound track: its words are written down in the background
    }

    /// A video pin whose length or sound is not known yet, or whose poster was never checked
    /// for being (nearly) black.
    private func needsVideoUpkeep(_ pin: Pin) -> Bool {
        pin.isVideo && !pin.isDeleted && !missingFileIDs.contains(pin.id)
            && ((pin.duration ?? 0) <= 0 || pin.hasAudio == nil || !pin.posterChecked)
    }

    /// Fills in what video pins are missing, one video at a time in the background, starting
    /// `delay` seconds from now. Nothing runs when there is nothing to do, it never holds up
    /// launch, and it waits while the AI queue is busy.
    func startVideoMaintenanceIfNeeded(delay: Double = 8) {
        guard maintenanceTask == nil, pins.contains(where: { needsVideoUpkeep($0) }) else { return }
        maintenanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.runVideoMaintenance()
            guard !Task.isCancelled else { return }
            self?.maintenanceTask = nil
            // The sound check may have found sound tracks: those videos' words are written down next.
            self?.startTranscribingIfNeeded(delay: 5)
        }
    }

    private func runVideoMaintenance() async {
        var tried: Set<UUID> = []
        while !Task.isCancelled {
            // The AI queue goes first: both read files and keep the processor busy.
            while analysisTask != nil {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
            }
            guard let next = pins.first(where: { !tried.contains($0.id) && needsVideoUpkeep($0) }) else { return }
            tried.insert(next.id)
            await upkeep(next)
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// What the background look at one video found (plain values only).
    private struct VideoUpkeep: Sendable {
        var fileFound = false
        var duration: Double? = nil
        var hasAudio: Bool? = nil
        var posterChecked = false
        var betterPoster: Data? = nil    // a new poster that is less dark than the stored one
    }

    private func upkeep(_ pin: Pin) async {
        guard !isOffloaded(pin) else { return }   // only videos whose upkeep is done are offloaded
        let id = pin.id
        let profile = profileID
        let videoURL = videoFileURL(for: pin)
        let posterURL = imageFileURL(for: pin)
        let wantsLength = (pin.duration ?? 0) <= 0
        let wantsSound = pin.hasAudio == nil
        let wantsPoster = !pin.posterChecked
        let found = await Task.detached(priority: .utility) { () -> VideoUpkeep in
            await LibraryStore.inspectVideo(at: videoURL, posterURL: posterURL,
                                            length: wantsLength, sound: wantsSound, poster: wantsPoster)
        }.value
        guard !Task.isCancelled, isCurrentProfile(profile), found.fileFound, let index = index(of: id) else { return }
        // Read from the file itself, so not an edit: updatedAt stays (as in ensureAudioInfo).
        var current = pins[index]
        var changed = false
        if let seconds = found.duration, seconds > 0, (current.duration ?? 0) <= 0 { current.duration = seconds; changed = true }
        if let sound = found.hasAudio, current.hasAudio == nil { current.hasAudio = sound; changed = true }
        if found.posterChecked, found.betterPoster == nil, !current.posterChecked { current.posterChecked = true; changed = true }
        if changed { pins[index] = current }
        if let poster = found.betterPoster {
            await replacePoster(of: id, with: poster)
        }
        if changed { scheduleSave(after: 3) }
    }

    /// Writes a better poster for a video pin; the AI then looks at the pin again. true: the
    /// poster was changed (false: the pin isn't a video any more, another profile is in use now,
    /// or the picture couldn't be written — the pin's poster check counts as done then).
    @discardableResult
    func replacePoster(of id: UUID, with poster: Data) async -> Bool {   // (not private: VideoPosters.swift changes posters too)
        guard let current = pin(id), current.isVideo else { return false }
        let profile = profileID
        let imageURL = imageFileURL(for: current)
        let thumbURL = thumbsURL.appendingPathComponent(current.thumbFileName)
        let printURL = printsURL.appendingPathComponent(current.printFileName)
        let size = await Task.detached(priority: .utility) { () -> (Double, Double)? in
            guard let prepared = try? ImageProcessor.prepare(data: poster, imageURL: imageURL, thumbURL: thumbURL) else { return nil }
            try? FileManager.default.removeItem(at: printURL)
            return (prepared.width, prepared.height)
        }.value
        guard isCurrentProfile(profile), let index = index(of: id) else { return false }
        guard let size else {
            // Couldn't be written: the check still ran, so it isn't tried again.
            pins[index].posterChecked = true
            scheduleSave(after: 3)
            return false
        }
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
            pin.posterChecked = true
            pin.pictureRevision += 1   // the poster file was rewritten: views (and iCloud) take the new one
        }
        scheduleSave()
        startAnalysisIfNeeded()
        return true
    }

    /// Looks at one video off the main thread: its length and sound when asked, and whether the
    /// stored poster is (nearly) black — then a new poster is picked and kept if it is less dark.
    nonisolated private static func inspectVideo(at videoURL: URL, posterURL: URL,
                                                 length: Bool, sound: Bool, poster: Bool) async -> VideoUpkeep {
        var result = VideoUpkeep()
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return result }
        result.fileFound = true
        if length { result.duration = await VideoTools.duration(for: videoURL) }
        if sound { result.hasAudio = await VideoTools.hasAudio(for: videoURL) }
        guard poster else { return result }
        // A poster that can't be read counts as black, so a new one is made.
        let stored = LibraryStore.darkness(ofImageAt: posterURL) ?? (black: true, share: 2)
        if stored.black, let fresh = await VideoTools.poster(for: videoURL) {
            if let freshShare = LibraryStore.darkness(ofImageData: fresh.jpegData)?.share, freshShare < stored.share {
                result.betterPoster = fresh.jpegData
            }
            if (result.duration ?? 0) <= 0, fresh.duration > 0 { result.duration = fresh.duration }
        }
        result.posterChecked = true
        return result
    }

    /// Whether a picture is (nearly) black, and its share of black pixels, from a tiny copy.
    nonisolated private static func darkness(ofImageAt url: URL) -> (black: Bool, share: Double)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return darkness(ofImageData: data)
    }

    nonisolated private static func darkness(ofImageData data: Data) -> (black: Bool, share: Double)? {
        guard let image = ImageProcessor.downsample(data, maxPixelSize: 64) else { return nil }
        return (VideoTools.isMostlyBlack(image), VideoTools.darkFraction(of: image))
    }

    // MARK: Image tools

    /// Turns or flips the stored picture (and its thumbnail); the AI looks again afterwards.
    /// The file keeps its name, so `pictureRevision` goes up: views showing it load it again.
    func transformImage(_ id: UUID, quarterTurns: Int, flipHorizontally: Bool) async -> Bool {
        guard let pin = pin(id), pin.hasImageFile, !pin.isVideo, await ensureLocal(pin) else { return false }
        let profile = profileID
        let imageURL = imageFileURL(for: pin)
        let thumbURL = thumbsURL.appendingPathComponent(pin.thumbFileName)
        let printURL = printsURL.appendingPathComponent(pin.printFileName)
        let size = await Task.detached(priority: .userInitiated) { () -> (Double, Double)? in
            guard let data = try? Data(contentsOf: imageURL),
                  let source = ImageProcessor.downsample(data, maxPixelSize: 2048),
                  let turned = ImageProcessor.transformed(source, quarterTurns: quarterTurns, flipHorizontally: flipHorizontally),
                  let fullData = ImageProcessor.jpegData(turned, quality: 0.9) else { return nil }
            try? fullData.write(to: imageURL, options: .atomic)
            if let thumb = ImageProcessor.downsample(fullData, maxPixelSize: 700), let thumbData = ImageProcessor.jpegData(thumb, quality: 0.8) {
                try? thumbData.write(to: thumbURL, options: .atomic)
            }
            try? FileManager.default.removeItem(at: printURL)
            return (Double(turned.width), Double(turned.height))
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
            pin.pictureRevision += 1
        }
        scheduleSave()
        startAnalysisIfNeeded()
        return true
    }

    // MARK: Loading images for display / export

    func imageFileURL(for pin: Pin) -> URL { imagesURL.appendingPathComponent(pin.imageFileName) }
    func exifFileURL(for pin: Pin) -> URL { exifURL.appendingPathComponent(pin.exifFileName) }

    func thumbnail(for pin: Pin) async -> UIImage? {
        guard pin.hasImageFile else { return nil }
        let key = pin.id.uuidString as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let url = thumbsURL.appendingPathComponent(pin.thumbFileName)
        let fallback = imagesURL.appendingPathComponent(pin.imageFileName)
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
            let data = (try? Data(contentsOf: url)) ?? (try? Data(contentsOf: fallback))
            guard let data, let cgImage = ImageProcessor.downsample(data, maxPixelSize: 700) else {
                return LoadedImage(image: nil)
            }
            return LoadedImage(image: UIImage(cgImage: cgImage))
        }.value
        if let image = loaded.image { thumbCache.setObject(image, forKey: key) }
        return loaded.image
    }

    /// The small picture if it is already decoded (no waiting).
    func cachedThumbnail(for pin: Pin) -> UIImage? {
        thumbCache.object(forKey: pin.id.uuidString as NSString)
    }

    func fullImage(for pin: Pin) async -> UIImage? {
        guard pin.hasImageFile else { return nil }
        let key = pin.id.uuidString as NSString
        if let cached = fullCache.object(forKey: key) { return cached }
        guard await ensureLocal(pin) else { return nil }   // offloaded: back from iCloud first (Offloading.swift)
        let url = imagesURL.appendingPathComponent(pin.imageFileName)
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
            guard let data = try? Data(contentsOf: url),
                  let cgImage = ImageProcessor.downsample(data, maxPixelSize: 2048) else {
                return LoadedImage(image: nil)
            }
            return LoadedImage(image: UIImage(cgImage: cgImage))
        }.value
        if let image = loaded.image { fullCache.setObject(image, forKey: key) }
        return loaded.image
    }

    /// The full picture if it has already been decoded (no waiting, no disk).
    func cachedFullImage(for pin: Pin) -> UIImage? {
        fullCache.object(forKey: pin.id.uuidString as NSString)
    }

    // MARK: Visual similarity (feature prints)

    /// A feature print that can be handed to a background task.
    private struct PrintBox: @unchecked Sendable {
        let id: UUID
        let observation: VNFeaturePrintObservation
    }

    /// Makes sure the prints of these pins are in memory (read off the main thread).
    private func loadPrints(for candidates: [Pin]) async {
        let missing = candidates.filter { $0.hasFeaturePrint && printCache[$0.id] == nil && !printsMissing.contains($0.id) }
        guard !missing.isEmpty else { return }
        let folder = printsURL
        let names = missing.map { ($0.id, $0.printFileName) }
        let loaded = await Task.detached(priority: .userInitiated) { () -> [PrintBox] in
            var result: [PrintBox] = []
            for (id, name) in names {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                      let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) else { continue }
                result.append(PrintBox(id: id, observation: observation))
            }
            return result
        }.value
        let found = Set(loaded.map { $0.id })
        for box in loaded { printCache[box.id] = box.observation }
        for (id, _) in names where !found.contains(id) { printsMissing.insert(id) }
    }

    /// Unarchives a feature print that isn't stored on disk (draft pins).
    func featurePrintObservation(from data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// 0…1 visual similarity from `pin` to every other visible pin, computed
    /// off the main thread. Relative to this library, but a nearest neighbour
    /// that is not really close scores low (so "nothing similar" is possible).
    func visualSimilarities(from pin: Pin, printOverride: VNFeaturePrintObservation?, among candidates: [Pin]) async -> [UUID: Double] {   // (not private: used by LibraryBoards.swift)
        await loadPrints(for: candidates + [pin])
        guard let print = printOverride ?? printCache[pin.id] else { return [:] }
        let others = candidates.compactMap { other -> PrintBox? in
            guard other.id != pin.id, let observation = printCache[other.id] else { return nil }
            return PrintBox(id: other.id, observation: observation)
        }
        guard !others.isEmpty else { return [:] }
        let mine = PrintBox(id: pin.id, observation: print)
        return await Task.detached(priority: .userInitiated) { () -> [UUID: Double] in
            var distances: [UUID: Float] = [:]
            for other in others {
                var d: Float = 0
                if (try? mine.observation.computeDistance(&d, to: other.observation)) != nil { distances[other.id] = d }
            }
            let sorted = distances.values.sorted()
            guard let closest = sorted.first else { return [:] }
            let median = sorted[sorted.count / 2]
            guard median > closest else { return [:] }
            // How much closer than the crowd the nearest one is decides how strong
            // the whole scale is: a "nearest" that is barely nearer scores little.
            // (Small steps with explicit types, so the compiler checks them quickly.)
            let spread: Float = median - closest
            let crowd: Float = max(median * 0.5, 0.0001)
            let rawStrength: Float = spread / crowd
            let strength = Double(min(Float(1), max(Float(0), rawStrength)))
            var result: [UUID: Double] = [:]
            for (id, d) in distances {
                let rawRelative: Float = (median - d) / spread
                let relative = Double(max(Float(0), min(Float(1), rawRelative)))
                result[id] = relative * strength
            }
            return result
        }.value
    }

    /// Weighted set of a pin's tags for overlap comparisons.
    nonisolated private static func tagWeights(of pin: Pin) -> [String: Double] {
        var weights: [String: Double] = [:]
        for tag in pin.tags { weights[tag.lowercased()] = 1.0 }
        for tag in pin.aiTags { weights[tag.label] = max(weights[tag.label] ?? 0, 0.4 + 0.6 * tag.confidence) }
        for tag in pin.ocrTags { weights[tag] = max(weights[tag] ?? 0, 0.5) }
        for tag in pin.fileKeywords { weights[tag] = max(weights[tag] ?? 0, 0.8) }
        return weights
    }

    nonisolated private static func tagOverlap(_ a: [String: Double], _ b: [String: Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var shared = 0.0
        for (tag, weight) in a {
            if let other = b[tag] { shared += min(weight, other) }
        }
        let total = max(a.values.reduce(0, +), b.values.reduce(0, +))
        return total > 0 ? min(1, shared / total * 2) : 0
    }

    /// What a pin page needs in one go: related pins and board suggestions.
    struct PinInsights: Sendable {
        var related: [Pin]
        var suggestions: [BoardSuggestion]
    }

    /// Pins that look like this one or share its subject, plus which boards it
    /// would fit. Computed off the main thread. `printOverride` serves draft pins.
    /// A hidden pin is compared with hidden pins only (and offered hidden boards only).
    func insights(for pin: Pin, relatedLimit: Int, suggestionLimit: Int = 3, printOverride: VNFeaturePrintObservation? = nil) async -> PinInsights {
        let candidates = pins(scope: scope(of: pin))
        let visual = await visualSimilarities(from: pin, printOverride: printOverride, among: candidates)
        let related = await relatedPins(to: pin, limit: relatedLimit, visual: visual, among: candidates)
        let suggestions = await suggestBoards(for: pin, limit: suggestionLimit, visual: visual, among: candidates)
        return PinInsights(related: related, suggestions: suggestions)
    }

    /// Pins like this one among the pins of its own scope (a hidden pin → hidden pins),
    /// optionally only pins of one kind (nil = any kind), best match first.
    func relatedPins(to pin: Pin, limit: Int, kind: PinKind? = nil, printOverride: VNFeaturePrintObservation? = nil) async -> [Pin] {
        var candidates = pins(scope: scope(of: pin))
        if let kind { candidates = candidates.filter { $0.kind == kind } }
        guard candidates.contains(where: { $0.id != pin.id }) else { return [] }
        let visual = await visualSimilarities(from: pin, printOverride: printOverride, among: candidates)
        return await relatedPins(to: pin, limit: limit, visual: visual, among: candidates)
    }

    private func relatedPins(to pin: Pin, limit: Int, visual: [UUID: Double], among candidates: [Pin]) async -> [Pin] {
        let mine = LibraryStore.tagWeights(of: pin)
        let others = candidates.filter { $0.id != pin.id }
        let pinID = pin.id
        return await Task.detached(priority: .userInitiated) { () -> [Pin] in
            var scored: [(pin: Pin, score: Double)] = []
            for other in others where other.id != pinID {
                let v = visual[other.id] ?? 0
                let t = LibraryStore.tagOverlap(mine, LibraryStore.tagWeights(of: other))
                let score = 0.6 * v + 0.4 * t
                if score >= 0.12 { scored.append((pin: other, score: score)) }
            }
            return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.pin }
        }.value
    }
}
