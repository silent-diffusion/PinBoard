//
//  OriginalsFolder.swift  —  PinBoard
//
//  The folder you chose in Files for full-size originals (Settings › iCloud & storage › "Keep originals
//  in a folder"): writing, fetching and tidying up (`OriginalsFolder`), how much room the library
//  takes (`LibrarySize`) and the words shown for all of storage (`StorageText`). It is its own
//  file so that MediaStorage.swift holds only what the store does with them.
//

import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - The originals folder

/// Where a pin's full-size original is, as far as can be told without fetching it.
enum OriginalStatus: Equatable, Sendable {
    case none          // no original was kept for it
    case here          // on this device: it opens at once
    case inCloud       // in iCloud and not on this device now: it is fetched when you open it
    case unreachable   // the folder can't be reached now (offline, a drive not connected), or the file is gone
}

/// A kept original: its file name, its size, and the profile's folder it is in.
struct KeptOriginal: Sendable, Equatable {
    var name: String
    var bytes: Int
    var folder: URL
}

/// The folder you chose in Files for the full-size originals (Settings › iCloud & storage › "Keep
/// originals in a folder"). It is kept as a bookmark, so PinBoard may use it again after a
/// relaunch. Each profile has a folder of its own inside it (named after the profile's id), and
/// each original is named after its pin ("<pin id>.heic"), so originals of different profiles
/// never mix. PinBoard only ever writes, removes or evicts files it named itself.
@MainActor
final class OriginalsFolder: ObservableObject {
    static let shared = OriginalsFolder()

    /// The folder exists and can be read (checked again by `refresh`); nil until it was first
    /// checked (Settings then says "Checking…").
    @Published private(set) var isReachable: Bool? = nil
    /// Pins whose original is being fetched right now (views show a spinner and Cancel).
    @Published private(set) var fetching: Set<UUID> = []

    /// How long "Show original" waits for iCloud (Cancel on the pin's page, or closing Quick
    /// Look, stops it sooner).
    nonisolated static let viewerPatience: Double = 600
    /// How long Save to Photos and Share wait for the first original. Once one didn't come, the
    /// others are taken only when they are here already (they would most likely not come either).
    nonisolated static let sharingPatience: Double = 45
    /// A coordinated read (a File Provider — Dropbox… — handing a file over) always gets at least this long.
    nonisolated static let minimumReadTime: Double = 10
    /// A download problem iCloud reports within this many seconds of a new request may be left over
    /// from an earlier try (say from when this device was offline): it is believed only after that.
    nonisolated static let downloadErrorGrace: Double = 2
    /// Originals opened lately stay on this device this long (the tidy-up leaves them alone).
    nonisolated static let recentlyOpenedFor: Double = 600
    /// A tidy-up comes this long after every fetch and after the viewer closes: iCloud goes on
    /// bringing an original after a Cancel or a miss, and one that came stays here — just after it
    /// stops counting as opened lately, it leaves this device again.
    nonisolated static let afterFetchUpkeep: Double = recentlyOpenedFor + 60
    /// Tidy-ups again while originals are still on their way up to iCloud: this often, at most this many times.
    nonisolated static let upkeepRetryDelay: Double = 600
    nonisolated static let upkeepRetries = 6
    /// Copies into the folder are written in the app's temporary folder under names like this first.
    nonisolated static let stagingPrefix = "PinBoard-original-"

    /// The folder the bookmark led to, and the bookmark it came from (resolved once per launch).
    private var resolved: URL? = nil
    private var resolvedFrom: Data? = nil
    /// The folder PinBoard holds access to (kept while the app runs: one folder, so that is fine).
    private var accessing: URL? = nil
    /// A bookmark that couldn't be resolved just now is not tried again for a few seconds.
    private var failedBookmark: Data? = nil
    private var failedAt: Date = .distantPast
    /// The fetches going on now, by pin (two screens can ask for the same original at once),
    /// each under a token of its own — so "Cancel" can stop them all (`cancelFetch`).
    private var fetchJobs: [UUID: [UUID: Task<URL?, Never>]] = [:]
    /// Originals opened lately (file name → when): the tidy-up leaves them on this device a while.
    private var recentlyOpened: [String: Date] = [:]
    /// Originals shown full size right now (file name → how many viewers): never taken off this
    /// device meanwhile, however long a video plays.
    private var onScreen: [String: Int] = [:]
    private var upkeepTask: Task<Void, Never>? = nil

    init() {}

    // MARK: Choosing the folder

    /// The folder picked in Files: remembered as a bookmark, its readable name shown in Settings,
    /// and "Keep originals" turned on. false when it can't be remembered (nothing changes then).
    @discardableResult
    func choose(_ url: URL, settings: AppSettings) -> Bool {
        let started = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            if started { url.stopAccessingSecurityScopedResource() }
            return false
        }
        stopAccessing()
        if started { accessing = url }
        resolved = url
        resolvedFrom = bookmark
        failedBookmark = nil
        settings.originalsBookmark = bookmark
        settings.originalsFolderName = OriginalsFolder.readableName(forPath: url.path)
        settings.keepOriginals = true
        setReachable(true)
        return true
    }

    /// The chosen folder, or nil (none chosen, or its bookmark can't be resolved now — say its
    /// drive isn't connected). The bookmark is resolved once per launch; a stale one is made again.
    func folderURL(settings: AppSettings) -> URL? {
        guard let bookmark = settings.originalsBookmark else { return nil }
        if let resolved, resolvedFrom == bookmark { return resolved }
        if failedBookmark == bookmark, Date().timeIntervalSince(failedAt) < 10 { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            failedBookmark = bookmark
            failedAt = Date()
            return nil
        }
        stopAccessing()
        if url.startAccessingSecurityScopedResource() { accessing = url }
        resolved = url
        resolvedFrom = bookmark
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            resolvedFrom = fresh
            settings.originalsBookmark = fresh
        }
        return url
    }

    private func stopAccessing() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }

    /// Checks again whether the folder can be reached (off the main thread).
    func refresh(settings: AppSettings) async {
        guard let root = folderURL(settings: settings) else {
            setReachable(false)
            return
        }
        let reachable = await Task.detached(priority: .utility) { () -> Bool in
            OriginalsFolder.canReach(root)
        }.value
        setReachable(reachable)
    }

    /// Only a change is published: every imported item asks, and each publish would redraw the
    /// screens watching (Quick Look, the pin's page, Settings).
    private func setReachable(_ reachable: Bool) {
        if isReachable != reachable { isReachable = reachable }
    }

    /// The profile's own folder, ready to be written to (made when it is missing) — nil when
    /// originals aren't kept or the folder can't be reached now. Then nothing is copied.
    func writableFolder(for profileID: UUID, settings: AppSettings) async -> URL? {
        guard settings.keepOriginals, let root = folderURL(settings: settings) else { return nil }
        let folder = OriginalsFolder.profileFolder(in: root, profileID: profileID)
        let ready = await Task.detached(priority: .utility) { () -> Bool in
            OriginalsFolder.prepare(folder, in: root)
        }.value
        setReachable(ready)
        return ready ? folder : nil
    }

    /// The profile's folder when the chosen folder is there (for reading and removing).
    func existingFolder(for profileID: UUID, settings: AppSettings) -> URL? {
        guard let root = folderURL(settings: settings) else { return nil }
        return OriginalsFolder.profileFolder(in: root, profileID: profileID)
    }

    // MARK: Names and places (plain rules; the harness tests them)

    /// "<pin id>.<ext>": the extension in lower case (without a dot); "bin" when there is none.
    nonisolated static func fileName(for pinID: UUID, sourceExtension: String) -> String {
        let cleaned = sourceExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        return "\(pinID.uuidString).\(cleaned.isEmpty ? "bin" : cleaned)"
    }

    /// The folder a profile's originals go in: `root/<profile id>/` (made on first write).
    nonisolated static func profileFolder(in root: URL, profileID: UUID) -> URL {
        root.appendingPathComponent(profileID.uuidString, isDirectory: true)
    }

    /// Whether PinBoard named this file itself ("<pin id>.<ext>", or such a name with a passing
    /// ".partial" after it). Nothing else in the folder is ever touched.
    nonisolated static func isOwnName(_ name: String) -> Bool {
        guard name.count > 37, !name.contains("/"), UUID(uuidString: String(name.prefix(36))) != nil else { return false }
        let rest = name.dropFirst(36)
        return rest.hasPrefix(".") && rest.count > 1
    }

    /// The pin a file of ours belongs to.
    nonisolated static func pinID(ofFileNamed name: String) -> UUID? {
        guard isOwnName(name) else { return nil }
        return UUID(uuidString: String(name.prefix(36)))
    }

    /// The folder's name as Settings shows it: its last two parts, "iCloud Drive › PinBoard
    /// Originals". iCloud Drive's own folder name ("com~apple~CloudDocs") reads "iCloud Drive",
    /// the device's own storage "On this device" (Files calls it "On My iPad" or "On My iPhone"),
    /// and parts that are only long codes are left out.
    nonisolated static func readableName(forPath path: String) -> String {
        var parts = path.split(separator: "/").map { String($0) }
        if let cloud = parts.lastIndex(of: "com~apple~CloudDocs") {
            parts = ["iCloud Drive"] + parts[(cloud + 1)...]
        } else if let local = parts.lastIndex(of: "File Provider Storage") {
            parts = ["On this device"] + parts[(local + 1)...]
        }
        parts = parts.filter { UUID(uuidString: $0) == nil }
        let shown = parts.suffix(2)
        return shown.isEmpty ? "the chosen folder" : shown.joined(separator: " › ")
    }

    // MARK: Writing and removing (off the main thread)

    /// The folder exists and can be read.
    nonisolated static func canReach(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        return FileManager.default.isReadableFile(atPath: folder.path)
    }

    /// Makes the profile's folder inside `root` when it is missing. false when `root` can't be reached.
    nonisolated static func prepare(_ folder: URL, in root: URL) -> Bool {
        guard canReach(root) else { return false }
        if canReach(folder) { return true }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return canReach(folder)
    }

    /// Copies a file into `folder` as `name`, through the system's file coordination (so iCloud
    /// Drive, Dropbox and the like only ever see a finished file): written in full in the app's
    /// own temporary folder first, then moved into place. The byte count, or nil when it couldn't
    /// be written.
    nonisolated static func put(fileAt source: URL, as name: String, in folder: URL) -> Int? {
        guard isOwnName(name) else { return nil }
        return coordinatedWrite(to: folder.appendingPathComponent(name)) { (staged: URL) -> Bool in
            (try? FileManager.default.copyItem(at: source, to: staged)) != nil
        }
    }

    /// The same for bytes already read (a picture as it was imported).
    nonisolated static func put(data: Data, as name: String, in folder: URL) -> Int? {
        guard isOwnName(name) else { return nil }
        return coordinatedWrite(to: folder.appendingPathComponent(name)) { (staged: URL) -> Bool in
            (try? data.write(to: staged)) != nil
        }
    }

    /// `write` fills a new file in the app's own temporary folder (nothing there is uploaded
    /// anywhere, so a half-written file never reaches iCloud), dated now; inside one coordinated
    /// write it then takes `target`'s place (`settle`). The temporary file is gone afterwards.
    nonisolated private static func coordinatedWrite(to target: URL, _ write: (URL) -> Bool) -> Int? {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staged) }
        guard write(staged) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: staged.path)
        var bytes: Int? = nil
        var coordinationError: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { (url: URL) in
            guard OriginalsFolder.settle(staged, at: url) else { return }
            bytes = VideoCompressor.fileBytes(at: url)
        }
        return bytes
    }

    /// Puts a finished file in `url`'s place in one step: a rename when both are on the same disk
    /// (iCloud Drive and "On this device" are), else — a drive — a copy under a passing name next
    /// to it ("<name>.partial"), then a rename. false: `url` is as it was.
    nonisolated private static func settle(_ staged: URL, at url: URL) -> Bool {
        if LibraryStore.moveIntoPlace(staged, url) { return true }
        let partial = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".partial")
        try? FileManager.default.removeItem(at: partial)
        guard (try? FileManager.default.copyItem(at: staged, to: partial)) != nil else {
            try? FileManager.default.removeItem(at: partial)
            return false
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: partial.path)
        guard LibraryStore.moveIntoPlace(partial, url) else {
            try? FileManager.default.removeItem(at: partial)
            return false
        }
        return true
    }

    /// Removes one of our files (a coordinated delete; best effort). Names PinBoard didn't make are left alone.
    nonisolated static func remove(_ name: String, in folder: URL) {
        guard isOwnName(name) else { return }
        var coordinationError: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: folder.appendingPathComponent(name), options: .forDeleting,
                                                         error: &coordinationError) { (url: URL) in
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Fetching an original

    /// The original's place once it is on this device (the folder's own file — no copy is made):
    /// asked for from iCloud when it is only there, waiting up to `patience` seconds (stopping the
    /// task, or `cancelFetch`, stops the wait), then read once through file coordination, so a
    /// File Provider (Dropbox…) has it in full. nil when it isn't there, didn't come or was cancelled.
    func fetch(originalOf pin: Pin, store: LibraryStore, patience: Double = OriginalsFolder.viewerPatience) async -> URL? {
        guard let name = pin.originalName,
              let folder = existingFolder(for: store.profileID, settings: AppSettings.shared) else { return nil }
        let file = folder.appendingPathComponent(name)
        let job = Task.detached(priority: .userInitiated) { () -> URL? in
            await OriginalsFolder.bringHere(file, patience: patience)
        }
        let token = UUID()
        beginFetching(pin.id, token: token, job: job)
        defer { endFetching(pin.id, token: token) }
        let url = await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            job.cancel()
        }
        if url != nil { recentlyOpened[name] = Date() }
        return url
    }

    /// "Cancel" (the pin's page, while its original is being fetched): every fetch of that
    /// original going on now stops, and each ends without it.
    func cancelFetch(_ id: UUID) {
        for job in (fetchJobs[id] ?? [:]).values { job.cancel() }
    }

    private func beginFetching(_ id: UUID, token: UUID, job: Task<URL?, Never>) {
        fetchJobs[id, default: [:]][token] = job
        if !fetching.contains(id) { fetching.insert(id) }
    }

    private func endFetching(_ id: UUID, token: UUID) {
        fetchJobs[id]?[token] = nil
        guard fetchJobs[id]?.isEmpty ?? true else { return }
        fetchJobs[id] = nil
        fetching.remove(id)
    }

    /// Waits until `file` is on this device, then reads it once through file coordination (a File
    /// Provider — Dropbox… — hands it over in full first). `patience`: how many seconds iCloud may
    /// take (0: only a file already here is taken, and iCloud isn't asked for it). Gives up as soon
    /// as iCloud reports a problem (see `givesUpWaiting`);
    /// when iCloud won't even take the request, the coordinated read fetches the file itself. The
    /// read is bounded in time too (at least `minimumReadTime`). Stopping the task stops it all.
    nonisolated static func bringHere(_ file: URL, patience: Double) async -> URL? {
        guard fileExists(file) else { return nil }
        let start = Date()
        if isUbiquitous(file) {
            guard await waitForICloud(file, patience: patience) else { return nil }
        }
        let left = patience - Date().timeIntervalSince(start)
        return await coordinatedRead(file, limit: max(left, minimumReadTime)) ? file : nil
    }

    /// Asks iCloud for `file` and waits up to `patience` seconds for it. true: it is here now — or
    /// iCloud wouldn't take the request (say for a folder outside the app's own iCloud), and the
    /// coordinated read that follows fetches it itself. false: it didn't come in time, iCloud
    /// reported a problem (offline, no room…), or the task was stopped.
    nonisolated private static func waitForICloud(_ file: URL, patience: Double) async -> Bool {
        // No patience: only a file already here is taken. iCloud isn't asked for one nobody will
        // wait for — it would go on bringing it (perhaps gigabytes) long after this.
        guard patience > 0 else { return isOnThisDevice(downloadState(of: file)) }
        guard (try? FileManager.default.startDownloadingUbiquitousItem(at: file)) != nil else { return true }
        let start = Date()
        while !Task.isCancelled {
            let waited = Date().timeIntervalSince(start)
            let state = downloadState(of: file)
            if state == .current { return true }
            // A copy that is here but not iCloud's newest (originals never change, so this is rare) will do after a while.
            if state == .downloaded, waited >= min(15, patience) { return true }
            if givesUpWaiting(waited: waited, patience: patience, reportedError: { () -> Bool in downloadFailed(file) }) {
                return false
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// Whether waiting for iCloud ends here without the file: the time is up, or iCloud reported a
    /// problem (offline, no room…). A problem is believed only `downloadErrorGrace` seconds after
    /// the request — one left over from an earlier try may still show for a moment — and until
    /// then it isn't even asked about.
    nonisolated static func givesUpWaiting(waited: Double, patience: Double, reportedError: () -> Bool) -> Bool {
        if waited >= patience { return true }
        return waited >= downloadErrorGrace && reportedError()
    }

    /// iCloud's download state says the file is on this device (its newest copy, or an older one).
    nonisolated static func isOnThisDevice(_ state: URLUbiquitousItemDownloadingStatus?) -> Bool {
        state == .current || state == .downloaded
    }

    /// iCloud gave up bringing the file (offline, no room…). Read fresh each time.
    nonisolated static func downloadFailed(_ url: URL) -> Bool {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey]))?.ubiquitousItemDownloadingError != nil
    }

    /// Reads `file` once through file coordination (a File Provider hands it over in full first),
    /// for at most `limit` seconds: then the coordination is cancelled (a provider that can't be
    /// reached may never answer). Stopping the task cancels it too.
    nonisolated static func coordinatedRead(_ file: URL, limit: Double) async -> Bool {
        let box = CoordinatorBox()
        let job = Task.detached(priority: .userInitiated) { () -> Bool in box.read(file) }
        let timer = Task.detached(priority: .utility) { () -> Void in
            try? await Task.sleep(nanoseconds: UInt64(max(limit, 0) * 1_000_000_000))
            if !Task.isCancelled { box.coordinator.cancel() }
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            box.coordinator.cancel()
            job.cancel()
        }
    }

    /// A copy of an original in the app's temporary folder, for Photos and the share sheet (they
    /// read the file themselves, and may not be allowed into the chosen folder). Remove it with
    /// `discardTemporaryCopy` when done; leftovers go at the next launch.
    nonisolated static func temporaryCopy(of file: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            let folder = temporaryCopiesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let copy = folder.appendingPathComponent(file.lastPathComponent)
            guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
            var copied = false
            var coordinationError: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { (url: URL) in
                copied = (try? FileManager.default.copyItem(at: url, to: copy)) != nil
            }
            if copied { return copy }
            try? FileManager.default.removeItem(at: folder)
            return nil
        }.value
    }

    /// Removes a copy made by `temporaryCopy` (with the folder made for it).
    nonisolated static func discardTemporaryCopy(_ copy: URL) {
        let folder = copy.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().lastPathComponent == temporaryCopiesFolder.lastPathComponent else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes every temporary copy (at launch: nothing is using them any more).
    nonisolated static func removeTemporaryCopies() {
        try? FileManager.default.removeItem(at: temporaryCopiesFolder)
    }

    nonisolated static var temporaryCopiesFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PinBoard-originals", isDirectory: true)
    }

    // MARK: Status (cheap: only what the file system already knows)

    /// Where a pin's original is (see `OriginalStatus`) — read off the main thread.
    func currentStatus(of pin: Pin, settings: AppSettings, profileID: UUID) async -> OriginalStatus {
        guard let name = pin.originalName else { return .none }
        guard let folder = existingFolder(for: profileID, settings: settings) else { return .unreachable }
        let file = folder.appendingPathComponent(name)
        return await Task.detached(priority: .utility) { () -> OriginalStatus in
            OriginalsFolder.status(ofFileAt: file)
        }.value
    }

    /// The same, right away (it asks the file system, so views call `currentStatus` instead).
    func status(of pin: Pin, settings: AppSettings, profileID: UUID) -> OriginalStatus {
        guard let name = pin.originalName else { return .none }
        guard let folder = existingFolder(for: profileID, settings: settings) else { return .unreachable }
        return OriginalsFolder.status(ofFileAt: folder.appendingPathComponent(name))
    }

    /// Where the file at `file` is.
    nonisolated static func status(ofFileAt file: URL) -> OriginalStatus {
        if isUbiquitous(file) {
            let state = downloadState(of: file)
            return state == .current || state == .downloaded ? .here : .inCloud
        }
        if placeholderExists(file) { return .inCloud }
        return FileManager.default.fileExists(atPath: file.path) ? .here : .unreachable
    }

    /// The file is there, on this device or as iCloud's stand-in for it.
    nonisolated static func fileExists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path) || placeholderExists(file)
    }

    /// Older iCloud folders show a file that isn't downloaded as ".name.icloud".
    nonisolated static func placeholderExists(_ file: URL) -> Bool {
        let placeholder = file.deletingLastPathComponent().appendingPathComponent("." + file.lastPathComponent + ".icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    /// The file (or folder) lives in iCloud Drive. (A new URL each time: answers read before aren't reused.)
    nonisolated static func isUbiquitous(_ url: URL) -> Bool {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    /// iCloud's download state of the file, read fresh (nil outside iCloud).
    nonisolated static func downloadState(of url: URL) -> URLUbiquitousItemDownloadingStatus? {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
    }

    // MARK: Keeping the device light, and tidying up

    /// A moment after launch and after every import (`after` seconds): originals that iCloud
    /// already has in full are taken off this device (they stay in iCloud and come back when
    /// opened), originals of pins erased for good are removed (`tombstones`: when each one was
    /// erased; `known`: every pin the library has), and passing ".partial" files left over an hour
    /// go. Only in the profile's own folder, only files PinBoard named; never an original not
    /// uploaded yet, one opened in the last ten minutes, or one shown right now. While some
    /// original is still on its way up to iCloud, it looks again every ten minutes (six times at
    /// most: `round` counts them), so a big video leaves this device too once it is uploaded.
    func scheduleUpkeep(profileID: UUID, settings: AppSettings, after delay: Double,
                        tombstones: [UUID: Date] = [:], known: Set<UUID> = [], round: Int = 0) {
        guard settings.originalsBookmark != nil else { return }
        upkeepTask?.cancel()
        upkeepTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let waiting = await self.runUpkeep(profileID: profileID, settings: settings, tombstones: tombstones, known: known)
            guard waiting, round < OriginalsFolder.upkeepRetries, !Task.isCancelled else { return }
            // (The erased pins were seen to in this round: the next ones only evict and tidy.)
            self.scheduleUpkeep(profileID: profileID, settings: settings, after: OriginalsFolder.upkeepRetryDelay,
                                round: round + 1)
        }
    }

    /// One tidy-up (see `scheduleUpkeep`). true: some original PinBoard wrote is in iCloud but
    /// not uploaded yet, so it is worth looking again later.
    @discardableResult
    private func runUpkeep(profileID: UUID, settings: AppSettings, tombstones: [UUID: Date], known: Set<UUID>) async -> Bool {
        guard let root = folderURL(settings: settings) else { return false }
        let folder = OriginalsFolder.profileFolder(in: root, profileID: profileID)
        let cutoff = Date().addingTimeInterval(-OriginalsFolder.recentlyOpenedFor)
        recentlyOpened = recentlyOpened.filter { $0.value > cutoff }
        let inUse = Set(recentlyOpened.keys).union(onScreen.keys)
        return await Task.detached(priority: .background) { () -> Bool in
            guard OriginalsFolder.canReach(folder) else { return false }
            OriginalsFolder.removeStalePartials(in: folder)
            if !tombstones.isEmpty { OriginalsFolder.removeErased(in: folder, tombstones: tombstones, known: known) }
            OriginalsFolder.evict(in: folder, root: root, keeping: inUse)
            return OriginalsFolder.waitingForUpload(in: folder)
        }.value
    }

    /// An original shown full size now (`OriginalViewerSheet`): the tidy-up leaves it on this
    /// device until it is closed, and for ten minutes after that.
    func beginShowing(_ name: String) {
        onScreen[name, default: 0] += 1
    }

    func endShowing(_ name: String) {
        let left = (onScreen[name] ?? 1) - 1
        onScreen[name] = left > 0 ? left : nil
        recentlyOpened[name] = Date()
    }

    /// Takes the originals iCloud has in full off this device (see `scheduleUpkeep`). Only when the
    /// folder is in iCloud Drive. Returns how many.
    @discardableResult
    nonisolated static func evict(in folder: URL, root: URL, keeping inUse: Set<String>) -> Int {
        guard isUbiquitous(root) || isUbiquitous(folder) else { return 0 }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return 0 }
        var evicted = 0
        for name in names where isOwnName(name) && !name.hasSuffix(".partial") && !inUse.contains(name) {
            let file = URL(fileURLWithPath: folder.appendingPathComponent(name).path)
            let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey]
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isUbiquitousItem == true, values.ubiquitousItemIsUploaded == true else { continue }
            let state = values.ubiquitousItemDownloadingStatus
            guard state == .current || state == .downloaded else { continue }   // already off this device
            if (try? FileManager.default.evictUbiquitousItem(at: file)) != nil { evicted += 1 }
        }
        return evicted
    }

    /// Some original PinBoard wrote is in iCloud but not uploaded yet (the tidy-up then looks
    /// again later, see `scheduleUpkeep`).
    nonisolated static func waitingForUpload(in folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        for name in names where isOwnName(name) && !name.hasSuffix(".partial") {
            let file = URL(fileURLWithPath: folder.appendingPathComponent(name).path)
            let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey])
            if values?.isUbiquitousItem == true, values?.ubiquitousItemIsUploaded != true { return true }
        }
        return false
    }

    /// Removes the originals of pins erased for good (say on another device), like the library's
    /// own orphan sweep: only when no pin has that id now, the file is older than the erase and
    /// over an hour old. (Passing ".partial" files are `removeStalePartials`' job.)
    @discardableResult
    nonisolated static func removeErased(in folder: URL, tombstones: [UUID: Date], known: Set<UUID>) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let hourAgo = Date().addingTimeInterval(-3600)
        var removed = 0
        for file in files {
            let name = file.lastPathComponent
            guard !name.hasSuffix(".partial"), let id = pinID(ofFileNamed: name) else { continue }
            guard !known.contains(id), let erasedAt = tombstones[id] else { continue }
            let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let written, written < hourAgo, written < erasedAt else { continue }
            remove(name, in: folder)
            removed += 1
        }
        return removed
    }

    /// Removes passing ".partial" files over an hour old: a copy onto a drive that was cut short
    /// (the app was closed in the middle). A copy going on now is never touched: its file's date
    /// moves on while it is written. Every tidy-up does this.
    @discardableResult
    nonisolated static func removeStalePartials(in folder: URL) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let hourAgo = Date().addingTimeInterval(-3600)
        var removed = 0
        for file in files where file.lastPathComponent.hasSuffix(".partial") && isOwnName(file.lastPathComponent) {
            let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let written, written < hourAgo else { continue }
            remove(file.lastPathComponent, in: folder)
            removed += 1
        }
        return removed
    }

    /// Removes a deleted profile's originals: only the files PinBoard named, then its folder if
    /// nothing else is left in it. (For ProfileManager.delete; see ASBUILT_A.)
    /// (`bookmark`: the deleted profile's own originals folder — every profile chooses its own.)
    nonisolated static func forgetProfile(_ profileID: UUID, bookmark: Data?) {
        guard let bookmark else { return }
        Task.detached(priority: .utility) {
            var stale = false
            guard let root = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
            let accessing = root.startAccessingSecurityScopedResource()
            defer { if accessing { root.stopAccessingSecurityScopedResource() } }
            let folder = OriginalsFolder.profileFolder(in: root, profileID: profileID)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names where OriginalsFolder.isOwnName(name) { OriginalsFolder.remove(name, in: folder) }
            if let left = try? FileManager.default.contentsOfDirectory(atPath: folder.path), left.isEmpty {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
}

/// One file coordinator, handed to a background task. @unchecked: Apple documents
/// `NSFileCoordinator.cancel()` as safe to call from any thread, and that is all the other side does.
final class CoordinatorBox: @unchecked Sendable {
    let coordinator = NSFileCoordinator()

    /// Reads `file` once through the coordinator: true when it was there to read.
    func read(_ file: URL) -> Bool {
        var found = false
        var coordinationError: NSError? = nil
        coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { (url: URL) in
            found = FileManager.default.fileExists(atPath: url.path)
        }
        return found && coordinationError == nil
    }
}

// MARK: - How much room the library takes

/// The library's files on this device, in bytes (Settings › iCloud & storage).
struct LibrarySize: Sendable, Equatable {
    /// Pictures and their thumbnails (a video's poster frame is a picture too).
    var pictures: Int64 = 0
    /// Videos.
    var videos: Int64 = 0
    /// Everything else: fingerprints, photo details, the library file and its safety copies.
    var other: Int64 = 0

    var total: Int64 { pictures + videos + other }

    /// "1.3 GB on this device — videos 1 GB · pictures 300 MB".
    var text: String { StorageText.librarySize(pictures: pictures, videos: videos, other: other) }

    /// Adds up the library's folders (off the main thread).
    nonisolated static func measure(_ location: LibraryLocation) async -> LibrarySize {
        await Task.detached(priority: .utility) { () -> LibrarySize in
            let pictures = LibraryStore.folderSize(at: location.images) + LibraryStore.folderSize(at: location.thumbs)
            let videos = LibraryStore.folderSize(at: location.videos)
            let total = LibraryStore.folderSize(at: location.root)
            return LibrarySize(pictures: pictures, videos: videos, other: max(0, total - pictures - videos))
        }.value
    }
}

// MARK: - Words

/// Everything Settings › iCloud & storage, the pin page and the menus say about storage (plain rules;
/// the harness tests them). Always "this device", never "this iPad": the same app runs on iPhone.
enum StorageText {
    /// "1.3 GB on this device — videos 1 GB · pictures 300 MB" (the rest is named only when it
    /// is 10 MB or more).
    nonisolated static func librarySize(pictures: Int64, videos: Int64, other: Int64) -> String {
        let total = pictures + videos + other
        var parts = ["videos \(size(videos))", "pictures \(size(pictures))"]
        if other >= 10_000_000 { parts.append("other \(size(other))") }
        return "\(size(total)) on this device — " + parts.joined(separator: " · ")
    }

    /// Quick Look's info panel: "Original · 48 MB · iCloud Drive › PinBoard Originals".
    nonisolated static func originalLine(bytes: Int?, folderName: String) -> String {
        var parts = ["Original"]
        if let bytes, bytes > 0 { parts.append(StoragePolicy.sizeText(bytes)) }
        parts.append(folderName.isEmpty ? "your originals folder" : folderName)
        return parts.joined(separator: " · ")
    }

    /// The pin page's row: "Original kept in iCloud Drive › PinBoard Originals · 48 MB".
    nonisolated static func originalRowTitle(folderName: String, bytes: Int?) -> String {
        let place = folderName.isEmpty ? "your originals folder" : folderName
        guard let bytes, bytes > 0 else { return "Original kept in \(place)" }
        return "Original kept in \(place) · \(StoragePolicy.sizeText(bytes))"
    }

    /// The line under it (nil status: still being checked).
    nonisolated static func statusLine(_ status: OriginalStatus?) -> String {
        switch status {
        case nil: return "Checking…"
        case .here?: return "On this device"
        case .inCloud?: return "In iCloud — fetched when you open it"
        case .unreachable?, .none?: return "Not reachable now"
        }
    }

    /// Settings' folder row: whether the folder can be reached (nil: not checked yet).
    nonisolated static func folderStatus(_ reachable: Bool?) -> String {
        switch reachable {
        case nil: return "Checking…"
        case true?: return "Reachable"
        case false?: return "Not reachable now"
        }
    }

    /// The symbol of "Show original" — the same in Quick Look's menu and on the pin's page.
    /// (`externaldrive` is for where the original is kept: the row's title, the info line.)
    nonisolated static let showOriginalSymbol = "arrow.up.left.and.arrow.down.right"

    nonisolated static let fetching = "Fetching the original…"
    nonisolated static let fetchFailed = "The original couldn't be fetched (the folder may be offline)."

    /// The status pill while originals are fetched for Save to Photos or Share.
    nonisolated static func fetchingStatus(number: Int, of total: Int) -> String {
        total <= 1 ? fetching : "Fetching originals \(number) of \(total)…"
    }

    /// "Convert 12 videos to 1080p?" — one side's videos (Settings asks about the normal side's,
    /// Hidden's ⋯ menu about the hidden ones).
    nonisolated static func convertQuestion(count: Int, quality: VideoQuality) -> String {
        switch count {
        case 0: return "Convert videos to \(quality.label)?"
        case 1: return "Convert 1 video to \(quality.label)?"
        default: return "Convert \(count) videos to \(quality.label)?"
        }
    }

    /// The question's message in Settings. With originals kept, each one is copied first; without,
    /// it says plainly that the larger versions are gone for good (the button is red then too).
    nonisolated static func convertMessage(quality: VideoQuality, keepsOriginals: Bool) -> String {
        if keepsOriginals {
            return "Videos larger than \(quality.label) are converted to take less room. Each original is copied to your originals folder first. You can stop at any time."
        }
        return "Videos larger than \(quality.label) are replaced by smaller copies. The larger versions are not kept — turn on “Keep originals in a folder” first if you want them. You can stop at any time."
    }

    /// The question's message in Hidden's ⋯ menu (it is only offered while originals aren't kept:
    /// hidden pins' originals are never copied to the folder).
    nonisolated static func hiddenConvertMessage(quality: VideoQuality) -> String {
        "Hidden videos larger than \(quality.label) are replaced by smaller copies, and the larger versions are not kept. You can stop at any time."
    }

    /// Hidden's ⋯ menu: "Convert videos to 1080p…", and "Stop converting" while it runs.
    nonisolated static func convertMenuItem(quality: VideoQuality) -> String {
        "Convert videos to \(quality.label)…"
    }

    nonisolated static let stopConverting = "Stop converting"

    /// The Hidden section's short message when its conversion has ended: "Converted 3 videos.",
    /// "No video needed converting.", "Stopped. Converted 1 video." (never a board's name).
    nonisolated static func conversionDone(converted: Int, stopped: Bool) -> String {
        let count: String
        switch converted {
        case 0: count = stopped ? "" : "No video needed converting."
        case 1: count = "Converted 1 video."
        default: count = "Converted \(converted) videos."
        }
        guard stopped else { return count }
        return count.isEmpty ? "Stopped." : "Stopped. \(count)"
    }

    /// Settings' row while converting: "Converting 3 of 12 (45%)", then "Finishing up…".
    nonisolated static func convertingRow(done: Int, total: Int, percent: Int) -> String {
        guard total > 0, done < total else { return "Finishing up…" }
        return "Converting \(done + 1) of \(total) (\(min(max(percent, 0), 100))%)"
    }

    /// The status pill: "Converting video 3 of 12 (45%)…".
    nonisolated static func convertingStatus(number: Int, of total: Int, percent: Int) -> String {
        "Converting video \(number) of \(max(total, number)) (\(min(max(percent, 0), 100))%)…"
    }

    /// The status pill while an import converts a video: "Importing 3 of 10 — converting video 45%…"
    /// (`base` is what the pill said before: "Importing 3 of 10…").
    nonisolated static func importConverting(base: String?, percent: Int) -> String {
        let clamped = min(max(percent, 0), 100)
        var stem = (base ?? "").trimmingCharacters(in: .whitespaces)
        while stem.hasSuffix("…") || stem.hasSuffix(".") { stem.removeLast() }
        guard !stem.isEmpty else { return "Converting video \(clamped)%…" }
        return "\(stem) — converting video \(clamped)%…"
    }

    /// Why a conversion stopped early: the folder couldn't be reached…
    nonisolated static let originalsUnreachable = "Stopped: the originals folder couldn't be reached, and each original is copied there before its video is converted."
    /// …or it could, but copying the original failed (a full disk, or iCloud storage full).
    nonisolated static let originalCopyFailed = "Stopped: the original couldn't be copied (is there room?), and each original is copied before its video is converted."

    /// Settings › iCloud & storage's footer.
    nonisolated static let footer = "A video is added exactly as it is, at once; afterwards, in the background, those larger than the chosen size are converted so they take less room, and smaller ones are kept as they are. Originals: full-size pictures and videos are copied to the folder you choose — pick one in iCloud Drive to keep them off this device. PinBoard keeps its own smaller copy and fetches the original when you ask for it: “Show original” on a pin's page, Save to Photos and Share. Hidden pins' originals are never copied to the folder; while originals are kept, hidden videos stay as they are."

    /// Asked before another folder replaces the one in use.
    nonisolated static func changeFolderMessage(current: String) -> String {
        let place = current.isEmpty ? "the folder in use now" : "“\(current)”"
        return "The originals already kept stay in \(place). To keep them reachable, move its folders into the new one in the Files app."
    }

    // Deleting says what happens to the originals whenever a folder is set (`folderName` nil:
    // none is). The folder mirrors the library, so its originals go with the pins.

    /// "Clear this profile's library…".
    nonisolated static func clearLibraryMessage(folderName: String?) -> String {
        let base = "This removes all pins from this profile, including Recently Deleted."
        let tail = " Your Photos app is not affected. This cannot be undone."
        guard let folderName else { return base + tail }
        return base + " The full-size originals kept for them in \(place(folderName)) are deleted too." + tail
    }

    /// Settings › Library › Profiles › Delete profile.
    nonisolated static func deleteProfileMessage(folderName: String?) -> String {
        guard let folderName else {
            return "All of that profile's pins and boards are removed from this device. This cannot be undone."
        }
        return "All of that profile's pins and boards are removed from this device, and its full-size originals from \(place(folderName)). This cannot be undone."
    }

    /// Recently Deleted › Erase all now.
    nonisolated static func eraseMessage(folderName: String?) -> String {
        guard let folderName else { return "This cannot be undone." }
        return "Their originals in \(place(folderName)) go too. This cannot be undone."
    }

    /// “iCloud Drive › PinBoard Originals”, or "your originals folder" when its name isn't known.
    nonisolated private static func place(_ folderName: String) -> String {
        folderName.isEmpty ? "your originals folder" : "“\(folderName)”"
    }

    nonisolated private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
