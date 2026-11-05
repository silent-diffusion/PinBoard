//
//  MediaStorage.swift  —  PinBoard
//
//  Keeping the library small (Settings › iCloud & storage): videos larger than the chosen quality are
//  converted — in the background, one at a time, once everything that was being imported is in
//  (an imported video is first copied exactly as it is, so the pin appears at once); full-size
//  originals of pictures and videos can be kept in a folder of your choice (say in iCloud
//  Drive) and fetched when you ask for them.
//
//  What is here, top to bottom:
//    • the store's side (importing, "Convert existing videos…" — the normal side's from
//      Settings, the hidden side's from Hidden's ⋯ menu — and fetching an original);
//    • MediaOriginalRow and OriginalViewerSheet — the original on a pin's page.
//
//  The rest of storage is in two files of its own: VideoCompression.swift (`StoragePolicy`, the
//  plain rules for when a video is converted and to what, and `VideoCompressor`, which converts
//  a video, copies one and puts a file in place) and OriginalsFolder.swift (`OriginalsFolder`,
//  the folder you chose in Files: writing, fetching, tidying up; `LibrarySize`, how much room
//  the library takes on this device; `StorageText`, the words shown for all of this).
//
//  The folder is chosen in Files (any place, iCloud Drive or another drive), so
//  everything here keeps working when it can't be reached (offline, a drive not connected):
//  then nothing is copied, and nothing breaks. Hidden pins' originals are never copied there
//  (anyone who opens the Files app could see them).
//

import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - The store's side

/// A video's copy put in place for a new pin (`file`), and its original when one was kept.
struct PlacedVideo: Sendable, Equatable {
    var outcome: VideoOutcome
    var file: URL?
    var original: KeptOriginal?

    /// For a pin that turned out hidden after all (its board was hidden while the video was put
    /// in place): a hidden pin's original never goes to the folder, where anyone who opens the
    /// Files app could see it. If this device's copy is still the untouched video, the original
    /// isn't needed, so it goes again. If the video was converted, the original stays — without it
    /// the full-size video would be gone — like the original of a pin hidden later.
    mutating func dropOriginalUnlessConverted() {
        guard let kept = original else { return }
        if case .converted = outcome { return }
        LibraryStore.dropOriginal(kept.name, in: kept.folder)
        original = nil
    }
}

/// A run of video conversions while it goes on: the side it converts, the quality, and how far it
/// has got. Its pill is that side's ("Converting video 3 of 12 (45%)…"); the normal side's numbers
/// are also what Settings shows. The hidden side's run shows only in the Hidden section (its row,
/// and "Stop converting" in its ⋯ menu), never in Settings or on the normal side's pill.
///
/// Two kinds of run exist. Settings' "Convert existing videos…" (and Hidden's ⋯ menu) converts
/// every video of a side that still waits, and on the normal side counts as library work. A run
/// started after an import converts just the videos that import made, in the background, and is
/// not library work (profile switching never waits for it). New videos can join a run that is
/// going (`add`), so a second import never starts a second run on the same side.
@MainActor
final class ConversionRun {
    let scope: PinScope
    /// The quality every video of this run is converted to.
    let quality: VideoQuality
    /// The library the run belongs to (a switch to another profile ends it).
    let profile: UUID
    /// Settings' run on the normal side: other work waits for it (see `isBusyWithLibraryWork`).
    let isLibraryWork: Bool
    /// How many videos this run has been given so far (it grows when new ones join).
    private(set) var total: Int
    private(set) var done = 0
    /// The video being converted now (late progress reports about another one are dropped).
    private(set) var currentID: UUID? = nil
    /// The last text this run put on the pill (so it never clears another's).
    var lastStatus: String? = nil
    /// How far the video being converted now has got (0…100), so a joining video doesn't reset it.
    var percent = 0
    /// "Stop" was pressed: new videos no longer join this run.
    private(set) var isStopping = false
    /// The videos still to do, in order.
    private var waiting: [UUID]
    /// Every video the run was given (none is queued twice).
    private var given: Set<UUID>
    /// Videos whose export failed once and were put at the end of the queue again (each gets one
    /// more try: a conversion cut short by leaving the app usually works when the app is back).
    private var retried: Set<UUID> = []

    init(scope: PinScope, quality: VideoQuality, profile: UUID, isLibraryWork: Bool, queue: [UUID]) {
        self.scope = scope
        self.quality = quality
        self.profile = profile
        self.isLibraryWork = isLibraryWork
        self.waiting = queue
        self.given = Set(queue)
        self.total = queue.count
    }

    /// The number of the video being converted now (the "3" of "Converting video 3 of 12").
    var currentNumber: Int { done + 1 }

    /// The next video to convert; nil when none is left.
    func nextWaiting() -> UUID? {
        waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// New videos join the run (those it already has are left out).
    func add(_ ids: [UUID]) {
        for id in ids where !given.contains(id) {
            given.insert(id)
            waiting.append(id)
            total += 1
        }
    }

    func begin(_ id: UUID) {
        currentID = id
    }

    /// A video's export failed (it wasn't stopped): puts it at the end of the queue for one more
    /// try. false when it had its second try already (then it is counted as done and left alone).
    /// The run's total doesn't change, and the video doesn't count as done until it is.
    func requeueOnce(_ id: UUID) -> Bool {
        guard !retried.contains(id) else { return false }
        retried.insert(id)
        waiting.append(id)
        currentID = nil
        return true
    }

    /// This video is having its second try.
    func isRetry(_ id: UUID) -> Bool {
        retried.contains(id)
    }

    func finish() {
        currentID = nil
        done += 1
    }

    func stop() {
        isStopping = true
    }
}

/// New videos that couldn't join the run going on (it converts to another quality, belongs to
/// another profile, or is being stopped): they start when that run has ended.
struct LaterConversion: Sendable, Equatable {
    var profile: UUID
    var quality: VideoQuality
    var ids: [UUID]
}

/// How a run of "Convert existing videos…" went.
struct ConversionSummary: Sendable, Equatable {
    /// Videos made smaller (their smaller copy took the old one's place).
    var converted = 0
    /// It ended early: Stop, another profile, or an original that couldn't be kept.
    var stopped = false
    /// Why it ended early, when that needs saying (Settings shows it).
    var note: String? = nil
}

/// How one video of "Convert existing videos…" went.
private enum ConversionStep {
    case converted           // made smaller: the smaller copy took the old one's place
    case done                // found fine as it is (its quality recorded)
    case skipped             // left alone this time (its file is missing, it changed sides, another job has it…)
    case failed              // the export failed, but nobody stopped it: the run tries it once more at its end
    case stop(String?)       // the run ends here (stopped, another profile, or no original could be kept)
}

/// How keeping a video's original before converting it went.
private enum OriginalKeeping {
    case kept                // copied to the folder and recorded on the pin
    case folderUnreachable   // the folder can't be reached now
    case copyFailed          // it can, but the copy failed (no room?)
    case pinGone             // the pin went away or was hidden meanwhile (or another profile is in use)
}

extension LibraryStore {

    // MARK: Importing

    /// Puts a new video pin's file in place, for the library of `profile`: copied exactly as it
    /// is, at once — nothing is converted here, so the pin can appear quickly; the conversion
    /// comes later, in the background, once the whole import is in (`startConvertingNewVideos`).
    /// The one exception is a kind of file that can't keep its name (not .mov/.mp4/.m4v): it
    /// becomes an .mp4 now, as before (`placeVideoOfOtherKind`).
    /// Its untouched original goes to the originals folder when "Keep originals in a folder" is
    /// on, `keepsOriginal` allows it and the folder can be reached (a failure there just means no
    /// original). nil: the video couldn't be put in place (a kept original is removed again).
    /// A hidden video (`side` .hidden) never gets an original in the folder — anyone who opens the
    /// Files app could see it — and while originals are kept it is never made smaller later
    /// either, so nothing hidden is ever converted without its original.
    func placeImportedVideo(from source: URL, pinID: UUID, side: PinScope, profile: UUID,
                            keepsOriginal: Bool = true) async -> PlacedVideo? {
        let settings = AppSettings.shared
        let folder = videosURL   // (the caller checked that `profile` is the library in use)
        let originals: URL?
        if keepsOriginal, side == .visible {
            originals = await OriginalsFolder.shared.writableFolder(for: profile, settings: settings)
        } else {
            originals = nil
        }
        let ext = StoragePolicy.libraryExtension(of: source)
        let name = OriginalsFolder.fileName(for: pinID, sourceExtension: ext)
        if StoragePolicy.convertsAtImport(extension: ext, quality: settings.videoQuality) {
            return await placeVideoOfOtherKind(from: source, pinID: pinID, originalName: name, originals: originals)
        }
        // The original is copied while the library's copy is made (two copies of one file).
        async let kept: KeptOriginal? = LibraryStore.keepOriginal(ofFileAt: source, as: name, in: originals)
        let target = folder.appendingPathComponent("\(pinID.uuidString).\(ext)")
        let copied = await VideoCompressor.copy(source, to: target)
        let original = await kept
        guard copied else {
            if let original { LibraryStore.dropOriginal(original.name, in: original.folder) }
            return nil
        }
        // Copied as it is, nothing decided: its quality is recorded when it has been looked at.
        return PlacedVideo(outcome: .copied(extension: ext), file: target, original: original)
    }

    /// A new video of a kind that can't keep its name (see `StoragePolicy.convertsAtImport`): put in
    /// place as an .mp4 made at the chosen quality, as before the import went "copy first". If it
    /// can't be read or is small enough already, it is copied as it is. Nothing is converted
    /// without its original while originals are kept: when that original couldn't be kept (a
    /// hidden video, an unreachable folder) the video is copied as it is.
    private func placeVideoOfOtherKind(from source: URL, pinID: UUID, originalName: String, originals: URL?) async -> PlacedVideo? {
        let keepsOriginals = AppSettings.shared.keepOriginals
        let original = await LibraryStore.keepOriginal(ofFileAt: source, as: originalName, in: originals)
        let mayConvert = !keepsOriginals || original != nil
        let quality: VideoQuality = mayConvert ? AppSettings.shared.videoQuality : .original
        let outcome = await VideoCompressor.place(source: source, pinID: pinID, in: videosURL, quality: quality,
                                                  progress: { (_: Double) in })
        guard let placedExtension = outcome.fileExtension else {
            if let original { LibraryStore.dropOriginal(original.name, in: original.folder) }
            return nil
        }
        let target = videosURL.appendingPathComponent("\(pinID.uuidString).\(placedExtension)")
        return PlacedVideo(outcome: outcome, file: target, original: original)
    }

    /// Records where a new video pin's files are (after `placeImportedVideo`). `keepingDate`: a
    /// re-imported export record keeps its own change date (see `reinsertedDate`).
    func recordPlacedVideo(_ placed: PlacedVideo, for id: UUID, keepingDate: Bool = false) {
        let fill: (inout Pin) -> Void = { pin in
            if let ext = placed.outcome.fileExtension { pin.videoExtension = ext }
            pin.videoTier = placed.outcome.tier
            if let original = placed.original {
                pin.originalName = original.name
                pin.originalBytes = original.bytes
            }
        }
        if keepingDate { modifyKeepingDate(id, fill) } else { modify(id, fill) }
    }

    /// Removes a video put in place for a pin that was then not made, and its kept original
    /// (both by the places they were put in, whichever library is in use now).
    func discardPlacedVideo(_ placed: PlacedVideo) {
        if let file = placed.file {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
        }
        if let original = placed.original { LibraryStore.dropOriginal(original.name, in: original.folder) }
    }

    /// Keeps a new picture's untouched file (as imported: HEIC, PNG, JPEG…) in the originals
    /// folder of `profile`'s library when that is on and can be reached. nil: none was kept
    /// (nothing else changes).
    func keepOriginalPicture(_ data: Data, for id: UUID, profile: UUID) async -> KeptOriginal? {
        let settings = AppSettings.shared
        guard settings.keepOriginals,
              let folder = await OriginalsFolder.shared.writableFolder(for: profile, settings: settings) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> KeptOriginal? in
            let name = OriginalsFolder.fileName(for: id, sourceExtension: LibraryStore.pictureExtension(of: data))
            guard let bytes = OriginalsFolder.put(data: data, as: name, in: folder) else { return nil }
            return KeptOriginal(name: name, bytes: bytes, folder: folder)
        }.value
    }

    /// The usual extension for a picture's bytes ("heic", "png", "jpeg"…), read from the bytes
    /// themselves; "jpg" when they don't say.
    nonisolated static func pictureExtension(of data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let ext = UTType(identifier)?.preferredFilenameExtension, !ext.isEmpty else { return "jpg" }
        return ext.lowercased()
    }

    /// Copies a video's original into the originals folder (nil folder: none is kept).
    nonisolated static func keepOriginal(ofFileAt source: URL, as name: String, in folder: URL?) async -> KeptOriginal? {
        guard let folder else { return nil }
        return await Task.detached(priority: .utility) { () -> KeptOriginal? in
            guard let bytes = OriginalsFolder.put(fileAt: source, as: name, in: folder) else { return nil }
            return KeptOriginal(name: name, bytes: bytes, folder: folder)
        }.value
    }

    /// Removes one original again (off the main thread).
    nonisolated static func dropOriginal(_ name: String, in folder: URL) {
        Task.detached(priority: .utility) { OriginalsFolder.remove(name, in: folder) }
    }

    /// Removes the originals of pins erased for good (best effort, in the background). When the
    /// folder can't be reached now, the tidy-up after a later launch removes them (`sweepOrphans`).
    func discardOriginals(_ names: [String]) {
        guard !names.isEmpty, let folder = OriginalsFolder.shared.existingFolder(for: profileID, settings: AppSettings.shared) else { return }
        Task.detached(priority: .utility) {
            guard OriginalsFolder.canReach(folder) else { return }
            for name in names { OriginalsFolder.remove(name, in: folder) }
        }
    }

    /// After launch, after imports and after "Convert existing videos…": originals iCloud has in
    /// full leave this device; originals of pins erased for good (here or on another device) are
    /// removed. See `OriginalsFolder.scheduleUpkeep`.
    func scheduleOriginalsUpkeep(after delay: Double) {
        var tombstones: [UUID: Date] = [:]
        let known = Set(pins.map { $0.id })
        for (id, erasedAt) in erased where !known.contains(id) { tombstones[id] = erasedAt }
        OriginalsFolder.shared.scheduleUpkeep(profileID: profileID, settings: AppSettings.shared, after: delay,
                                              tombstones: tombstones, known: known)
    }

    /// The original of a pin, fetched onto this device (views and the pin menus use this), waiting
    /// up to `patience` seconds for iCloud. nil when it isn't there, didn't come, was cancelled, or
    /// another profile was chosen meanwhile.
    func fetchOriginalURL(for pin: Pin, patience: Double = OriginalsFolder.viewerPatience) async -> URL? {
        let profile = profileID
        let url = await OriginalsFolder.shared.fetch(originalOf: pin, store: self, patience: patience)
        guard isCurrentProfile(profile) else { return nil }
        // Whether it came, didn't or was cancelled, iCloud may have been asked for it — and it goes
        // on bringing it after a Cancel or a miss. A tidy-up a little later takes it off this device
        // again (never one opened in the last ten minutes, nor one on screen). It replaces a tidy-up
        // due sooner (an import's): that one's work is simply done then.
        if pin.originalName != nil { scheduleOriginalsUpkeep(after: OriginalsFolder.afterFetchUpkeep) }
        return url
    }

    /// The originals kept for one side's live pins, in bytes (from what the pins recorded).
    /// Settings asks for the normal side: hidden pins are never counted there.
    func originalsBytes(scope: PinScope) -> Int64 {
        var total: Int64 = 0
        for pin in pins(scope: scope) { total += Int64(pin.originalBytes ?? 0) }
        return total
    }

    // MARK: Converting videos (Settings and Hidden's ⋯ menu for what waits; after each import for the new ones)

    /// Starts converting for one side, so "Stop" can end it. Without `ids`: every video of that
    /// side that waits — the normal side's from Settings ("Convert existing videos…",
    /// `conversionTask`), the hidden side's from Hidden's ⋯ menu (`hiddenConversionTask`; only
    /// while originals aren't kept — hidden pins' originals are never copied to the folder, so
    /// their videos then stay as they are). With `ids` (the videos an import just made): only those,
    /// in the background and one at a time; when a run of that side is already going they join it
    /// instead of starting a second one (see `queueNewVideos`).
    func startConvertingVideos(to quality: VideoQuality, scope: PinScope = .visible, only ids: Set<UUID>? = nil) {
        guard quality != .original else { return }
        if let ids {
            queueNewVideos(ids, to: quality, scope: scope)
            return
        }
        guard !isBusyWithLibraryWork, conversionRuns[scope] == nil else { return }
        switch scope {
        case .visible:
            guard conversionTask == nil, conversionProgress == nil else { return }
        case .hidden:
            guard hiddenConversionTask == nil, !isConvertingHiddenVideos, !AppSettings.shared.keepOriginals else { return }
        }
        launch(everythingWaiting(to: quality, scope: scope))
    }

    /// A run for everything of one side that waits (Settings' and Hidden's own command).
    private func everythingWaiting(to quality: VideoQuality, scope: PinScope) -> ConversionRun {
        let queue: [UUID] = videosWaiting(for: quality, scope: scope).map { (pin: Pin) -> UUID in pin.id }
        return ConversionRun(scope: scope, quality: quality, profile: profileID, isLibraryWork: scope == .visible, queue: queue)
    }

    /// Runs a run as a task kept in `conversionTask` / `hiddenConversionTask`, so "Stop" finds it.
    /// When it has ended, what was held back meanwhile (`laterConversions`) gets its turn.
    private func launch(_ run: ConversionRun) {
        conversionRuns[run.scope] = run
        switch run.scope {
        case .visible:
            conversionTask = Task { @MainActor [weak self] in
                await self?.perform(run)
                self?.conversionTask = nil
                self?.startLaterConversions(for: .visible)
            }
        case .hidden:
            hiddenConversionTask = Task { @MainActor [weak self] () -> ConversionSummary in
                let summary = await self?.perform(run) ?? ConversionSummary()
                self?.hiddenConversionTask = nil
                self?.startLaterConversions(for: .hidden)
                return summary
            }
        }
    }

    /// "Stop" (Settings) or "Stop converting" (Hidden's ⋯ menu): the video being converted now is
    /// stopped (nothing half-written stays); the ones done so far stay done. Videos waiting for
    /// their turn stay as they are (Settings' "Convert existing videos…" takes them up later).
    func cancelConversion(scope: PinScope = .visible) {
        laterConversions[scope] = nil
        conversionRuns[scope]?.stop()
        switch scope {
        case .visible: conversionTask?.cancel()
        case .hidden: hiddenConversionTask?.cancel()
        }
    }

    /// One side's videos not yet at `quality` whose file is there — what the question counts and
    /// what the run then goes through (the same list, so "Convert 2 videos?" converts 2).
    func videosWaiting(for quality: VideoQuality, scope: PinScope) -> [Pin] {
        pins(scope: scope).filter { (pin: Pin) -> Bool in
            pin.isVideo && pin.videoTier != quality && !missingFileIDs.contains(pin.id)
        }
    }

    /// How many of one side's videos are not yet at `quality` (Settings asks for the normal side,
    /// Hidden's ⋯ menu for the hidden one: neither ever counts the other's).
    func videosToConvert(to quality: VideoQuality, scope: PinScope) -> Int {
        videosWaiting(for: quality, scope: scope).count
    }

    /// Converts one side's live videos whose copy is not yet at `quality`: each is looked at
    /// (`VideoTools.facts`); one larger than the quality is converted into a temporary file — its
    /// original copied to the originals folder first when "Keep originals" is on — and the smaller
    /// copy then takes the old one's place in one step, under the same name. One that is fine as
    /// it is just gets `quality` recorded. A video moved to the other side meanwhile is left to
    /// that side. The side's pill says "Converting video 3 of 12 (45%)…"; the normal side's run
    /// also shows in Settings (`conversionProgress`) and counts as library work, the hidden side's
    /// only in the Hidden section (`hiddenConversionProgress`: its row and ⋯ menu). Stops cleanly when
    /// stopped, when another profile is chosen, or when an original can't be kept (nothing is
    /// converted without its original then).
    @discardableResult
    func convertExistingVideos(to quality: VideoQuality, scope: PinScope = .visible) async -> ConversionSummary {
        guard quality != .original, !isBusyWithLibraryWork, !isConverting(scope), conversionRuns[scope] == nil else {
            return ConversionSummary()
        }
        let run = everythingWaiting(to: quality, scope: scope)
        conversionRuns[scope] = run   // claimed at once: nothing starts a second run on this side meanwhile
        return await perform(run)
    }

    /// Goes through a run's videos one after the other (the run's own list: videos may join it
    /// while it goes), then tidies up.
    @discardableResult
    private func perform(_ run: ConversionRun) async -> ConversionSummary {
        var summary = ConversionSummary()
        let profile = run.profile
        beginConversionRun(run)
        while let id = run.nextWaiting() {
            if Task.isCancelled || !isCurrentProfile(profile) {
                summary.stopped = true
                break
            }
            // A second try waits for PinBoard to be on screen: an export cut short by leaving the app
            // would only be cut short again while the app is still in the background.
            if run.isRetry(id) { await waitForForeground(profile: profile) }
            if Task.isCancelled || !isCurrentProfile(profile) {
                summary.stopped = true
                break
            }
            let step = await convertVideo(id, to: run.quality, run: run, profile: profile)
            if case .stop(let why) = step {
                summary.stopped = true
                summary.note = why
                break
            }
            if case .converted = step { summary.converted += 1 }
            // A failed export gets one more try at the end of the run (it counts as done only then).
            if case .failed = step, run.requeueOnce(id) {
                if isCurrentProfile(profile) { showCount(run, percent: 0) }
                continue
            }
            run.finish()
            if isCurrentProfile(profile) { showCount(run, percent: run.percent) }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        endConversionRun(run, note: summary.note)
        if conversionRuns[run.scope] === run { conversionRuns[run.scope] = nil }
        if isCurrentProfile(profile) {
            scheduleSave(after: 1)
            // The originals copied on the way leave this device once iCloud has them.
            scheduleOriginalsUpkeep(after: 60)
            // The videos are in place now (and converted): what is said in them is written down next
            // (VideoTranscripts.swift; it waits for the AI and any other conversion first).
            startTranscribingIfNeeded(delay: 5)
        }
        return summary
    }

    /// Waits (up to ten minutes) until PinBoard is on screen again, or the run is stopped or
    /// another profile is chosen. Returns at once when the app is on screen already.
    private func waitForForeground(profile: UUID) async {
        var seconds = 0
        while UIApplication.shared.applicationState != .active, seconds < 600, !Task.isCancelled, isCurrentProfile(profile) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            seconds += 1
        }
    }

    // MARK: Converting the videos an import made

    /// After an import, or anything else that makes video pins: the new videos are converted to the
    /// chosen quality in the background, one at a time, each replacing its copy in place. Their
    /// pins were there from the start with the video exactly as imported; nothing waits for this.
    /// Each side reports on its own: the normal side's videos on the normal pill (and in Settings),
    /// the hidden side's only in the Hidden section — nothing hidden ever reaches the normal side.
    /// A side whose run is going already takes the new videos into it.
    func startConvertingNewVideos(_ ids: [UUID]) {
        // Whatever the quality: the new videos' words are written down once they are in place (and
        // converted, when they are — a run that starts here keeps the transcription waiting, and
        // its end starts it, see `perform`).
        defer { if !ids.isEmpty { startTranscribingIfNeeded() } }
        let quality = AppSettings.shared.videoQuality
        guard quality != .original, !ids.isEmpty else { return }
        let wanted = Set(ids)
        startConvertingVideos(to: quality, scope: .visible, only: wanted)
        startConvertingVideos(to: quality, scope: .hidden, only: wanted)
    }

    /// Takes a batch of new videos of one side to `quality`: into the run that is going on when it
    /// can have them, held back until that run has ended when it can't (another quality, another
    /// profile, or it is being stopped), or as a run of its own when none is going. Only one run
    /// ever goes on a side. Quality "Original" converts nothing; hidden videos are never converted
    /// while originals are kept.
    private func queueNewVideos(_ ids: Set<UUID>, to quality: VideoQuality, scope: PinScope) {
        guard quality != .original else { return }
        if scope == .hidden, AppSettings.shared.keepOriginals { return }
        let wanted = newVideosToConvert(ids, to: quality, scope: scope)
        guard !wanted.isEmpty else { return }
        let running: Bool = scope == .visible ? conversionTask != nil : hiddenConversionTask != nil
        if let run = conversionRuns[scope] {
            if run.profile == profileID, run.quality == quality, !run.isStopping {
                run.add(wanted)
                showCount(run, percent: run.percent)
            } else {
                holdBack(wanted, quality: quality, scope: scope)
            }
        } else if running {
            holdBack(wanted, quality: quality, scope: scope)
        } else {
            let run = ConversionRun(scope: scope, quality: quality, profile: profileID, isLibraryWork: false, queue: wanted)
            launch(run)
        }
    }

    /// Which of `ids` (new pins) to convert: videos of this side, not yet at `quality`, whose file
    /// is there; oldest first, the order they came in.
    private func newVideosToConvert(_ ids: Set<UUID>, to quality: VideoQuality, scope: PinScope) -> [UUID] {
        let matching: [Pin] = videosWaiting(for: quality, scope: scope).filter { (pin: Pin) -> Bool in ids.contains(pin.id) }
        let oldestFirst: [Pin] = matching.sorted { (a: Pin, b: Pin) -> Bool in a.createdAt < b.createdAt }
        return oldestFirst.map { (pin: Pin) -> UUID in pin.id }
    }

    /// Keeps new videos for later: they start when the run going on has ended (`startLaterConversions`).
    private func holdBack(_ ids: [UUID], quality: VideoQuality, scope: PinScope) {
        var later = laterConversions[scope] ?? LaterConversion(profile: profileID, quality: quality, ids: [])
        if later.profile != profileID || later.quality != quality {
            later = LaterConversion(profile: profileID, quality: quality, ids: [])   // the newest wish replaces an old one
        }
        for id in ids where !later.ids.contains(id) { later.ids.append(id) }
        laterConversions[scope] = later
    }

    /// A run of `scope` has ended: what was held back for it (in this library) now gets its turn.
    private func startLaterConversions(for scope: PinScope) {
        guard let later = laterConversions.removeValue(forKey: scope), isCurrentProfile(later.profile) else { return }
        queueNewVideos(Set(later.ids), to: later.quality, scope: scope)
    }

    /// A run of that side is going on now.
    private func isConverting(_ scope: PinScope) -> Bool {
        scope == .visible ? conversionProgress != nil : isConvertingHiddenVideos
    }

    /// Settings' run on the normal side is library work and shows in Settings; a run after an
    /// import is not (you may switch profiles meanwhile — that stops it); the hidden side's shows
    /// only in the Hidden section (its progress row, and "Stop converting" in its ⋯ menu).
    private func beginConversionRun(_ run: ConversionRun) {
        if run.isLibraryWork { beginLibraryWork() }
        showCount(run)
    }

    private func endConversionRun(_ run: ConversionRun, note: String?) {
        if let shown = run.lastStatus, importStatus == shown { setImportStatus(nil, scope: run.scope) }
        switch run.scope {
        case .visible: setConversionProgress(nil, percent: 0, note: note)
        case .hidden: setHiddenConversionProgress(nil, percent: 0)
        }
        if run.isLibraryWork { endLibraryWork() }
    }

    /// "Converting 3 of 12 (45%)" where the run's side shows it: Settings for the normal side, the
    /// Hidden section for the hidden side — never the other one.
    private func showCount(_ run: ConversionRun, percent: Int = 0) {
        let progress = AnalysisProgress(done: run.done, total: run.total)
        switch run.scope {
        case .visible: setConversionProgress(progress, percent: percent, note: nil)
        case .hidden: setHiddenConversionProgress(progress, percent: percent)
        }
    }

    /// Converts one video (see `convertExistingVideos`).
    private func convertVideo(_ id: UUID, to quality: VideoQuality, run: ConversionRun, profile: UUID) async -> ConversionStep {
        // A poster being written into this video's file (a few seconds for a big file) goes first,
        // then the conversion: the video is not skipped, and its file is replaced by one job at a time.
        await waitForArtworkWrite(of: id, profile: profile)
        if Task.isCancelled { return .stop(nil) }
        guard isCurrentProfile(profile) else { return .stop(nil) }
        guard let video = livePin(id), video.isVideo, video.videoTier != quality else { return .skipped }
        // Moved to the other side since the run began: that side's business now (never announced here).
        guard scope(of: video) == run.scope else { return .skipped }
        let keepsOriginals = AppSettings.shared.keepOriginals
        // A hidden video never gets an original in the folder, so while originals are kept it
        // stays as it is (nothing is converted without its original).
        if keepsOriginals, run.scope == .hidden { return .skipped }
        // The other side's run has it right now (it changed sides while being converted).
        guard !videosBeingConverted.contains(id) else { return .skipped }
        guard await ensureLocal(video) else { return .skipped }   // kept in iCloud only and couldn't come back
        videosBeingConverted.insert(id)
        defer {
            videosBeingConverted.remove(id)
            // A new poster asked for while this conversion had the file is written now (into the new file).
            if artworkWaiting.remove(id) != nil, isCurrentProfile(profile) { scheduleArtwork(for: id) }
        }
        let file = videoFileURL(for: video)
        let fileName = video.videoFileName
        let ext = StoragePolicy.libraryExtension(of: file)
        run.begin(id)
        showConversion(run, percent: 0)
        let look = await LibraryStore.look(at: file)
        guard isCurrentProfile(profile) else { return .stop(nil) }
        let facts: VideoFacts
        switch look {
        case .missing:
            return .skipped   // its file is missing (Settings › Recover library tells about it)
        case .unreadable:
            recordTier(quality, for: id)   // can't be read, so it can't be converted: left as it is
            return .done
        case .read(let found):
            facts = found
        }
        guard case .convert(let preset) = StoragePolicy.decision(for: facts, quality: quality),
              let fileType = StoragePolicy.fileType(forExtension: ext) else {
            recordTier(quality, for: id)   // fine as it is (or a kind of file that is only ever kept)
            return .done
        }
        if keepsOriginals, video.originalName == nil {
            switch await keepOriginalBeforeConverting(file, ext: ext, pinID: id, profile: profile) {
            case .kept:
                break
            case .pinGone:
                return isCurrentProfile(profile) ? .skipped : .stop(nil)
            case .folderUnreachable:
                return .stop(isCurrentProfile(profile) ? StorageText.originalsUnreachable : nil)
            case .copyFailed:
                return .stop(isCurrentProfile(profile) ? StorageText.originalCopyFailed : nil)
            }
        }
        let temporary = VideoCompressor.temporaryFile(extension: ext)
        let reporter = conversionReporter(run: run, id: id)
        let result = await VideoCompressor.convert(file, to: temporary, fileType: fileType, preset: preset,
                                                   sourceBytes: facts.bytes, progress: reporter)
        let stopped = Task.isCancelled
        // Still this library, and still the same pin with the same file? (And a hidden video is
        // only replaced while originals aren't kept: turned on meanwhile, it stays as it is.)
        let hiddenNowKept = run.scope == .hidden && AppSettings.shared.keepOriginals
        guard isCurrentProfile(profile), let current = pin(id), current.videoFileName == fileName, !hiddenNowKept else {
            try? FileManager.default.removeItem(at: temporary)
            return isCurrentProfile(profile) ? .skipped : .stop(nil)
        }
        switch result {
        case .failed:
            try? FileManager.default.removeItem(at: temporary)
            // Not stopped: the export itself failed (leaving the app cuts one short). The run tries it once more.
            return stopped ? .stop(nil) : .failed
        case .notSmaller:
            recordTier(quality, for: id)
            return .done
        case .smaller:
            guard await VideoCompressor.settle(temporary, at: file) else { return .skipped }
            // A fact about the file, not an edit: the pin keeps its change date, so iCloud never
            // lets this win over a real change made on another device meanwhile.
            modifyKeepingDate(id) { (pin: inout Pin) in pin.videoTier = quality }
            VideoFileChanges.replaced(file)   // the file changed under the same name: players showing it open the new copy
            scheduleSave(after: 2)
            return .converted
        }
    }

    /// Waits while a poster is being written into this video's own file (`writeArtwork`), for at
    /// most ten minutes: the conversion then comes after it instead of skipping the video.
    /// Returns at once when no artwork is being written for it.
    private func waitForArtworkWrite(of id: UUID, profile: UUID) async {
        var halfSeconds = 0
        while artworkWriting.contains(id), halfSeconds < 1_200, !Task.isCancelled, isCurrentProfile(profile) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            halfSeconds += 1
        }
    }

    /// Copies a video's current file into the originals folder before it is converted, and
    /// records it on the pin (see `OriginalKeeping` for what else can happen: then the video
    /// isn't converted). The pin is looked at again after each wait: one hidden meanwhile gets no
    /// original in the folder (a copy already made goes again), and its video stays as it is.
    private func keepOriginalBeforeConverting(_ file: URL, ext: String, pinID: UUID, profile: UUID) async -> OriginalKeeping {
        guard let folder = await OriginalsFolder.shared.writableFolder(for: profile, settings: AppSettings.shared) else {
            return .folderUnreachable
        }
        // Hidden (or gone) while the folder was got ready: nothing is copied at all.
        guard mayKeepOriginal(of: pinID, profile: profile) else { return .pinGone }
        let name = OriginalsFolder.fileName(for: pinID, sourceExtension: ext)
        guard let kept = await LibraryStore.keepOriginal(ofFileAt: file, as: name, in: folder) else { return .copyFailed }
        return recordKeptOriginal(kept, for: pinID, profile: profile) ? .kept : .pinGone
    }

    /// Whether a pin may have its original kept in the folder now: it is still there, in the
    /// library in use, and on the normal side (a hidden pin's original never goes to the folder).
    private func mayKeepOriginal(of id: UUID, profile: UUID) -> Bool {
        guard isCurrentProfile(profile), let now = pin(id) else { return false }
        return scope(of: now) == .visible
    }

    /// Records an original just copied into the folder (for "Convert existing videos…") on its pin
    /// — only while the pin may have one (`mayKeepOriginal`: it can have been hidden while the copy
    /// was made). Otherwise the copy goes again and false comes back (the video isn't converted).
    func recordKeptOriginal(_ kept: KeptOriginal, for id: UUID, profile: UUID) -> Bool {
        guard mayKeepOriginal(of: id, profile: profile) else {
            LibraryStore.dropOriginal(kept.name, in: kept.folder)
            return false
        }
        // Where the original is kept is a fact, not an edit: the change date stays (see `convertVideo`).
        modifyKeepingDate(id) { (pin: inout Pin) in
            pin.originalName = kept.name
            pin.originalBytes = kept.bytes
        }
        scheduleSave(after: 2)
        return true
    }

    /// Records that a video was looked at for `quality` (so it isn't looked at again). A fact read
    /// from the file, not an edit: the pin keeps its change date (a newer edit made on another
    /// device still wins the next iCloud merge).
    private func recordTier(_ quality: VideoQuality, for id: UUID) {
        guard pin(id)?.videoTier != quality else { return }
        modifyKeepingDate(id) { (pin: inout Pin) in pin.videoTier = quality }
        scheduleSave(after: 2)
    }

    /// Shows how far the current video has got: on its run's side's pill, and in Settings (the
    /// normal side) or the Hidden section (the hidden side).
    private func showConversion(_ run: ConversionRun, percent: Int) {
        run.percent = percent
        showCount(run, percent: percent)
        guard mayUsePill(for: run) else { return }
        let text = StorageText.convertingStatus(number: run.currentNumber, of: run.total, percent: percent)
        run.lastStatus = text
        setImportStatus(text, scope: run.scope)
    }

    /// A conversion runs in the background, so it never takes the pill from other work — an import
    /// that goes on keeps its "Importing 3 of 10…" — it only uses a free pill, or one showing its
    /// own words. The one exception: the normal side's run may take over words on the hidden
    /// side's pill (the normal side never shows those, so nothing is lost by it).
    private func mayUsePill(for run: ConversionRun) -> Bool {
        guard let shown = importStatus else { return true }
        if shown == run.lastStatus { return true }
        return run.scope == .visible && importStatusScope == .hidden
    }

    /// The progress reports of one video's conversion: late ones, about a video already done, and
    /// ones about a video moved to the other side meanwhile, are dropped.
    private func conversionReporter(run: ConversionRun, id: UUID) -> @Sendable (Double) -> Void {
        let store = self
        return { (fraction: Double) in
            let percent = Int((fraction * 100).rounded(.down))
            Task { @MainActor in
                guard run.currentID == id, let video = store.pin(id), store.scope(of: video) == run.scope else { return }
                store.showConversion(run, percent: percent)
            }
        }
    }

    /// Looks at a library video before converting it (off the main thread).
    nonisolated private static func look(at file: URL) async -> VideoLook {
        await Task.detached(priority: .utility) { () -> VideoLook in
            guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
            guard let facts = await VideoTools.facts(for: file) else { return .unreadable }
            return .read(facts)
        }.value
    }
}

/// What looking at a library video found.
private enum VideoLook: Sendable {
    case missing               // no file
    case unreadable            // a file AVFoundation can't read
    case read(VideoFacts)
}

// MARK: - The original on a pin's page

/// An original ready to be shown (the sheet's item).
struct OriginalFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// On a pin's page, for a picture or video whose full-size original was kept: where it is, whether
/// it is on this device, and "Show original" — which fetches it first when it is only in iCloud (a
/// spinner and Cancel meanwhile) and then shows it full size. When it can't be fetched, a note says so.
struct MediaOriginalRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var originals = OriginalsFolder.shared
    let pin: Pin

    @State private var status: OriginalStatus? = nil   // nil while it is being checked
    @State private var shown: OriginalFile? = nil
    @State private var fetchFailed = false
    @State private var fetchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(StorageText.originalRowTitle(folderName: settings.originalsFolderName, bytes: pin.originalBytes),
                  systemImage: "externaldrive")
                .font(.subheadline.weight(.semibold))
            Text(StorageText.statusLine(status))
                .font(.caption)
                .foregroundStyle(.secondary)
            if fetchFailed {
                Label(StorageText.fetchFailed, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            actionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
        .task(id: pin.originalName ?? "") { await checkStatus() }
        .onDisappear { fetchTask?.cancel() }
        .sheet(item: $shown, onDismiss: { () -> Void in viewerClosed() }) { (file: OriginalFile) in
            OriginalViewerSheet(pin: pin, url: file.url)
                .hiddenPrivacyCover(store.isHidden(pin))   // a hidden pin never shows in the App Switcher
        }
    }

    /// The viewer closed: the original counts as opened lately for ten minutes from now, so the
    /// tidy-up after the fetch may have passed it by. Another one comes just after that.
    private func viewerClosed() {
        store.scheduleOriginalsUpkeep(after: OriginalsFolder.afterFetchUpkeep)
    }

    /// "Show original", or — while the original is being fetched, here or by Share or Save to
    /// Photos — a spinner with Cancel (fetching a big original can take minutes).
    @ViewBuilder
    private var actionRow: some View {
        if originals.fetching.contains(pin.id) {
            HStack(spacing: 8) {
                ProgressView()
                Text(StorageText.fetching)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel") { cancelFetch() }
                    .buttonStyle(.borderless)
            }
            .frame(minHeight: 44)
        } else {
            Button {
                showOriginal()
            } label: {
                Label("Show original", systemImage: StorageText.showOriginalSymbol)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func checkStatus() async {
        status = await originals.currentStatus(of: pin, settings: settings, profileID: store.profileID)
    }

    private func showOriginal() {
        fetchFailed = false
        let current = pin
        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            let url = await store.fetchOriginalURL(for: current)
            if Task.isCancelled { return }
            if let url {
                shown = OriginalFile(url: url)
                status = .here
            } else {
                fetchFailed = true
                await checkStatus()
            }
        }
    }

    /// Cancel: every fetch of this original stops (this page's own quietly; one started by Share
    /// or Save to Photos then uses the copy on this device, as when it doesn't come).
    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        originals.cancelFetch(pin.id)
    }
}

/// The full-size original of a picture or video, fetched from the originals folder: a picture
/// with pinch-to-zoom (Quick Look's zoom view), or the video in PinBoard's own player. Dark, like
/// Quick Look; on iPad a page-sized sheet. Done closes it. While it is on screen, the tidy-up
/// never takes the original off this device (`OriginalsFolder.beginShowing`).
struct OriginalViewerSheet: View {
    let pin: Pin
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var failed = false

    /// The longest side a picture is shown at: plenty to zoom into, while a 48-megapixel photo
    /// never needs 200 MB of memory to be shown.
    static let largestSide = 4096

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                viewer
            }
            .navigationTitle("Original")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .largeSheetSizing()   // the whole picture or video deserves the room (iOS 18 and later)
        .preferredColorScheme(.dark)
        .task(id: url) { await loadPicture() }
        .onAppear { OriginalsFolder.shared.beginShowing(url.lastPathComponent) }
        .onDisappear { OriginalsFolder.shared.endShowing(url.lastPathComponent) }
    }

    @ViewBuilder
    private var viewer: some View {
        if pin.isVideo {
            VideoPlayerView(url: url, playing: true)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ZoomableImageView(image: image, failed: failed)
                .ignoresSafeArea(edges: .bottom)
                .overlay { failureNote }
                .accessibilityLabel(pin.title.isEmpty ? "Original picture" : pin.title)
                .accessibilityAddTraits(.isImage)
        }
    }

    @ViewBuilder
    private var failureNote: some View {
        if failed && image == nil {
            Text("The original couldn't be opened.")
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(24)
                .allowsHitTesting(false)
        }
    }

    /// Decodes the picture off the main thread, at most `largestSide` pixels long.
    private func loadPicture() async {
        guard !pin.isVideo else { return }
        let file = url
        let side = OriginalViewerSheet.largestSide
        let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
            guard let cgImage = OriginalViewerSheet.downsample(file, maxPixelSize: side) else { return LoadedImage(image: nil) }
            return LoadedImage(image: UIImage(cgImage: cgImage))
        }.value
        if Task.isCancelled { return }
        image = loaded.image
        failed = loaded.image == nil
    }

    /// The picture in `file`, decoded straight from the file at most `maxPixelSize` pixels long
    /// and upright. The file is never read into memory whole (a big TIFF or RAW original stays
    /// on disk; only the smaller picture is made).
    nonisolated static func downsample(_ file: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
