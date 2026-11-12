//
//  Offloading.swift  —  PinBoard
//
//  "Optimize device storage" (Settings › iCloud & storage, needs iCloud sync). Full-size pictures and
//  videos that iCloud holds in full, and that weren't added or opened in the last 30 days, leave
//  this device; their thumbnails, posters, fingerprints and details stay, so the grid, search,
//  boards and "More like this" work as before, offline too. Opening one brings it back from iCloud
//  (the thumbnail shows meanwhile). Anything that needs the full file — sharing, saving to Photos,
//  exporting, cropping or turning, the AI — brings it back first.
//
//  Which pins are offloaded is kept per library in "offloaded.json" next to library.json (this
//  device only; never synced). The iCloud copy a file comes back from is the library's folder in
//  the app's iCloud container (see `CloudSync`), which iCloud keeps whether or not it is here.
//

import Foundation
import SwiftUI
import os

/// The pins whose full file is in iCloud only, per library, with the dates they were last opened
/// here. Safe from any thread.
final class OffloadIndex: Sendable {
    static let shared = OffloadIndex()

    /// How long a pin stays on the device after it was added or last opened.
    static let keepDays: Double = 30

    private struct Library: Codable {
        var offloaded: [UUID: Int64] = [:]   // pin → bytes the file took here
        var opened: [UUID: Date] = [:]
        /// Pins that came with a sync whose full file hasn't come yet (they are in `offloaded` too):
        /// the quiet download after a sync brings them (CloudChanges.swift). Optional: older files lack it.
        var arriving: Set<UUID>? = nil
    }

    private struct State {
        var libraries: [String: Library] = [:]   // by library folder path
        var clouds: [String: LibraryLocation] = [:]   // each library's iCloud folder, when known
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private static func key(_ location: LibraryLocation) -> String { location.root.standardizedFileURL.path }
    private static func file(_ location: LibraryLocation) -> URL { location.root.appendingPathComponent("offloaded.json") }

    /// The library's record, read from disk the first time it is asked for.
    private func library(_ location: LibraryLocation, in state: inout State) -> Library {
        let key = OffloadIndex.key(location)
        if let known = state.libraries[key] { return known }
        let read = (try? Data(contentsOf: OffloadIndex.file(location))).flatMap { try? JSONDecoder().decode(Library.self, from: $0) } ?? Library()
        state.libraries[key] = read
        return read
    }

    private func change(_ location: LibraryLocation, _ body: (inout Library) -> Void) {
        let data: Data? = state.withLockUnchecked { (state: inout State) -> Data? in   // (runs `body` right here)
            var record = library(location, in: &state)
            body(&record)
            state.libraries[OffloadIndex.key(location)] = record
            return try? JSONEncoder().encode(record)
        }
        if let data { try? data.write(to: OffloadIndex.file(location), options: .atomic) }
    }

    func isOffloaded(_ id: UUID, in location: LibraryLocation) -> Bool {
        state.withLock { (state: inout State) -> Bool in library(location, in: &state).offloaded[id] != nil }
    }

    func offloadedIDs(in location: LibraryLocation) -> Set<UUID> {
        state.withLock { (state: inout State) -> Set<UUID> in Set(library(location, in: &state).offloaded.keys) }
    }

    /// Bytes of the files kept in iCloud only.
    func offloadedBytes(in location: LibraryLocation) -> Int64 {
        state.withLock { (state: inout State) -> Int64 in library(location, in: &state).offloaded.values.reduce(0, +) }
    }

    func lastOpened(_ id: UUID, in location: LibraryLocation) -> Date? {
        state.withLock { (state: inout State) -> Date? in library(location, in: &state).opened[id] }
    }

    func markOffloaded(_ id: UUID, bytes: Int64, in location: LibraryLocation) {
        change(location) { $0.offloaded[id] = bytes }
    }

    func markHere(_ id: UUID, in location: LibraryLocation) {
        change(location) { (record: inout Library) in
            record.offloaded[id] = nil
            record.arriving?.remove(id)
        }
    }

    /// Pins a sync just brought without their full file (picture or video; bytes: its size in
    /// iCloud): kept as "in iCloud only" until the quiet download brings it. One write for all.
    func markArriving(_ files: [UUID: Int64], in location: LibraryLocation) {
        guard !files.isEmpty else { return }
        change(location) { (record: inout Library) in
            var arriving = record.arriving ?? []
            for (id, bytes) in files {
                record.offloaded[id] = bytes
                arriving.insert(id)
            }
            record.arriving = arriving
        }
    }

    /// The pins whose full file is still to come after a sync.
    func arrivingIDs(in location: LibraryLocation) -> Set<UUID> {
        state.withLock { (state: inout State) -> Set<UUID> in library(location, in: &state).arriving ?? [] }
    }

    /// These pins' full files are no longer waited for: they stay in iCloud only (Optimize device
    /// storage keeps old ones there) until opened.
    func stopArriving(_ ids: Set<UUID>, in location: LibraryLocation) {
        guard !ids.isEmpty else { return }
        change(location) { (record: inout Library) in record.arriving?.subtract(ids) }
    }

    func noteOpened(_ id: UUID, in location: LibraryLocation) {
        change(location) { $0.opened[id] = Date() }
    }

    /// Forgets pins that are no longer in the library (erased).
    func keepOnly(_ ids: Set<UUID>, in location: LibraryLocation) {
        change(location) { (record: inout Library) in
            record.offloaded = record.offloaded.filter { ids.contains($0.key) }
            record.opened = record.opened.filter { ids.contains($0.key) }
            record.arriving = record.arriving?.filter { ids.contains($0) }
        }
    }

    func setCloud(_ remote: LibraryLocation, for location: LibraryLocation) {
        state.withLock { $0.clouds[OffloadIndex.key(location)] = remote }
    }

    func cloud(for location: LibraryLocation) -> LibraryLocation? {
        state.withLock { $0.clouds[OffloadIndex.key(location)] }
    }

    // MARK: Files

    /// The one file of a pin that leaves the device: a video's video (its poster stays), else its picture.
    static func offloadableFile(of pin: Pin, in location: LibraryLocation) -> URL? {
        if pin.isVideo { return location.videos.appendingPathComponent(pin.videoFileName) }
        if pin.kind == .image, pin.hasImageFile { return location.images.appendingPathComponent(pin.imageFileName) }
        return nil
    }

    /// The same file in the library's iCloud folder.
    static func cloudFile(for file: URL, local: LibraryLocation, cloud: LibraryLocation) -> URL {
        let folder = file.deletingLastPathComponent().lastPathComponent   // "images" or "videos"
        return cloud.root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(file.lastPathComponent)
    }

    /// Brings an offloaded pin's file back from iCloud, waiting up to `patience` seconds (a minute
    /// for a picture, ten for a video). nil: it is here (or was already); otherwise why it isn't —
    /// the device is offline, iCloud doesn't have the file, iCloud reported an error, or it is still
    /// coming when the time is up. iCloud's errors are never swallowed: they end the wait at once.
    /// It looks again whenever iCloud says a file changed (CloudWaiting.swift), not on a fast clock.
    static func bringBack(_ id: UUID, file: URL, from cloudFile: URL, in location: LibraryLocation,
                          patience: Double) async -> CloudFetchProblem? {
        if FileManager.default.fileExists(atPath: file.path) {
            shared.markHere(id, in: location)
            return nil
        }
        // A file this device hasn't heard of yet: a few seconds for iCloud's list to bring it (the
        // screen waiting for it, or the sync, asks iCloud about it).
        if !CloudSync.isKnownToICloud(cloudFile) {
            let known = await CloudSync.waitUntil(timeout: min(10, patience)) { CloudSync.isKnownToICloud(cloudFile) }
            if !known { return NetworkStatus.shared.isOffline ? .offline : .missing }
        }
        if let problem = askICloud(for: cloudFile) { return problem }
        let deadline = Date().addingTimeInterval(patience)
        var askedAt = Date()
        var pause = 0.25
        while !isHere(cloudFile) {
            if let error = CloudSync.downloadError(of: cloudFile) { return problem(from: error) }
            if NetworkStatus.shared.isOffline { return .offline }
            if Task.isCancelled || Date() > deadline { return .stillDownloading(nil) }
            if Date().timeIntervalSince(askedAt) > 15 {
                // Asked again now and then, in case iCloud let the first request go (the app was away).
                if let problem = askICloud(for: cloudFile) { return problem }
                askedAt = Date()
            }
            await CloudActivity.shared.wait(seconds: min(pause, max(0.05, deadline.timeIntervalSinceNow)))
            pause = min(pause * 1.6, 3)
        }
        return place(cloudFile, at: file, id: id, in: location)
            ? nil : .iCloudError("It came, but couldn't be copied into the library.")
    }

    /// Asks iCloud for the file. nil: asked; otherwise why iCloud said no.
    private static func askICloud(for cloudFile: URL) -> CloudFetchProblem? {
        guard let error = CloudSync.startDownload(cloudFile) else { return nil }
        return problem(from: error)
    }

    /// iCloud's error, as a reason for the screen ("no such file" means it's missing from iCloud).
    private static func problem(from error: Error) -> CloudFetchProblem {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError {
            return .missing
        }
        if NetworkStatus.shared.isOffline { return .offline }
        return .iCloudError(error.localizedDescription)
    }

    /// The same, for code that can't wait in steps (an export on its own thread): the coordinated
    /// read has iCloud bring the file and waits for it.
    static func bringBackNow(_ id: UUID, file: URL, from cloudFile: URL, in location: LibraryLocation) -> Bool {
        if FileManager.default.fileExists(atPath: file.path) { return true }
        var error: NSError? = nil
        var placed = false
        NSFileCoordinator().coordinate(readingItemAt: cloudFile, options: [], error: &error) { (readURL: URL) in
            placed = place(readURL, at: file, id: id, in: location)
        }
        return placed
    }

    /// Copies iCloud's file into the library (under a passing name, then into place) and lets go
    /// of the iCloud folder's copy on this device.
    private static func place(_ cloudFile: URL, at file: URL, id: UUID, in location: LibraryLocation) -> Bool {
        let incoming = LibraryStore.incoming(file)
        try? FileManager.default.removeItem(at: incoming)
        guard (try? FileManager.default.copyItem(at: cloudFile, to: incoming)) != nil,
              LibraryStore.moveIntoPlace(incoming, file) else {
            try? FileManager.default.removeItem(at: incoming)
            return false
        }
        try? FileManager.default.evictUbiquitousItem(at: cloudFile)
        shared.markHere(id, in: location)
        return true
    }

    private static func isHere(_ file: URL) -> Bool { CloudSync.isFullyHere(file) }

    /// For code on its own thread (an export): brings the pin's full file back from iCloud first
    /// when it was offloaded. `libraryRoot`: the library's folder.
    static func bringBackIfOffloaded(_ pin: Pin, libraryRoot: URL) {
        let location = LibraryLocation(root: libraryRoot)
        guard shared.isOffloaded(pin.id, in: location), let file = offloadableFile(of: pin, in: location),
              let cloud = shared.cloud(for: location) else { return }
        _ = bringBackNow(pin.id, file: file, from: cloudFile(for: file, local: location, cloud: cloud), in: location)
    }

    /// Whether iCloud holds the file in full (uploaded), so the copy here may go.
    /// (A plain file — not in iCloud, as in a test — counts when it is there.)
    static func cloudHasInFull(_ cloudFile: URL) -> Bool {
        let fresh = URL(fileURLWithPath: cloudFile.path)   // (answers read fresh: see `CloudSync.isFullyHere`)
        guard let values = try? fresh.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .isUbiquitousItemKey]) else { return false }
        if values.isUbiquitousItem != true { return FileManager.default.fileExists(atPath: cloudFile.path) }
        return values.ubiquitousItemIsUploaded == true
    }
}

// MARK: - The store's side

/// Fetches in progress, so two views asking for the same file share one download, and why the
/// last one of each pin didn't come (for the screen that waited: `LibraryStore.cloudProblem`).
@MainActor
private enum BringingBack {
    static var running: [String: Task<CloudFetchProblem?, Never>] = [:]
    static var problems: [String: CloudFetchProblem] = [:]
}

extension LibraryStore {
    /// The pin's full picture or video is in iCloud only right now.
    func isOffloaded(_ pin: Pin) -> Bool {
        OffloadIndex.shared.isOffloaded(pin.id, in: location)
    }

    /// Makes sure the pin's full file is on this device, bringing it back from iCloud when it was
    /// offloaded, and notes that it was opened (it then stays for another 30 days). false: it
    /// couldn't be brought back now (`cloudProblem` says why).
    @discardableResult
    func ensureLocal(_ pin: Pin) async -> Bool {
        await ensureLocalReporting(pin) == nil
    }

    /// `ensureLocal`, saying why the file couldn't come (nil: it is here).
    func ensureLocalReporting(_ pin: Pin) async -> CloudFetchProblem? {
        OffloadIndex.shared.noteOpened(pin.id, in: location)
        guard OffloadIndex.shared.isOffloaded(pin.id, in: location),
              let file = OffloadIndex.offloadableFile(of: pin, in: location) else { return nil }
        return await fetchFromICloud(pin, file: file)
    }

    /// For the screens that show a pin (Quick View): like `ensureLocal`, and a picture or video
    /// missing here that iCloud still has (say a sync gave up waiting for it) is fetched too.
    func ensureLocalForViewing(_ pin: Pin) async -> CloudFetchProblem? {
        if let file = OffloadIndex.offloadableFile(of: pin, in: location),
           !OffloadIndex.shared.isOffloaded(pin.id, in: location),
           !FileManager.default.fileExists(atPath: file.path),
           let cloud = OffloadIndex.shared.cloud(for: location),
           CloudSync.isKnownToICloud(OffloadIndex.cloudFile(for: file, local: location, cloud: cloud)) {
            OffloadIndex.shared.noteOpened(pin.id, in: location)
            return await fetchFromICloud(pin, file: file)
        }
        return await ensureLocalReporting(pin)
    }

    /// Why the pin's last fetch from iCloud didn't work (nil: it worked, or none was needed).
    func cloudProblem(for pin: Pin) -> CloudFetchProblem? {
        BringingBack.problems[location.root.path + "/" + pin.id.uuidString]
    }

    /// Where a pin's full file would come from in iCloud, when Quick View may have to fetch it:
    /// offloaded, or missing here while iCloud has it (nil: it is here, or iCloud's folder isn't known).
    func cloudFileToFetch(_ pin: Pin) -> URL? {
        guard let file = OffloadIndex.offloadableFile(of: pin, in: location),
              let cloud = OffloadIndex.shared.cloud(for: location) else { return nil }
        let cloudFile = OffloadIndex.cloudFile(for: file, local: location, cloud: cloud)
        if isOffloaded(pin) { return cloudFile }
        if !FileManager.default.fileExists(atPath: file.path), CloudSync.isKnownToICloud(cloudFile) { return cloudFile }
        return nil
    }

    /// Asks iCloud for the pin's file once more (Retry while it is still coming).
    func askICloudAgain(for pin: Pin) {
        guard let cloudFile = cloudFileToFetch(pin) else { return }
        Task.detached(priority: .userInitiated) { CloudSync.startDownload(cloudFile) }
    }

    /// Brings the pin's full file from this profile's iCloud folder (one fetch per pin at a time).
    private func fetchFromICloud(_ pin: Pin, file: URL) async -> CloudFetchProblem? {
        let location = self.location
        let key = location.root.path + "/" + pin.id.uuidString
        if let running = BringingBack.running[key] { return await running.value }
        guard let cloud = OffloadIndex.shared.cloud(for: location) else {
            BringingBack.problems[key] = .noICloud
            return .noICloud
        }
        let cloudFile = OffloadIndex.cloudFile(for: file, local: location, cloud: cloud)
        let id = pin.id
        let patience: Double = pin.isVideo ? 600 : 60
        let task = Task.detached(priority: .userInitiated) { () -> CloudFetchProblem? in
            await OffloadIndex.bringBack(id, file: file, from: cloudFile, in: location, patience: patience)
        }
        BringingBack.running[key] = task
        let problem = await task.value
        BringingBack.running[key] = nil
        BringingBack.problems[key] = problem
        if problem == nil {
            fullCache.removeObject(forKey: id.uuidString as NSString)
            missingFileIDs.remove(id)
            objectWillChange.send()   // views asking `isOffloaded` look again
        } else if let problem {
            SyncLog.add("Couldn't bring \(file.lastPathComponent) from iCloud: \(problem.text)")
        }
        return problem
    }

    /// `ensureLocal` for several pins, one after another. Returns how many couldn't come.
    func ensureLocal(_ pins: [Pin]) async -> Int {
        var missing = 0
        for pin in pins where !(await ensureLocal(pin)) { missing += 1 }
        return missing
    }

    /// Where an offloaded pin's full file comes back from (nil: it is here, or iCloud's folder isn't known).
    func cloudFileIfOffloaded(_ pin: Pin) -> URL? {
        guard isOffloaded(pin), let file = OffloadIndex.offloadableFile(of: pin, in: location),
              let cloud = OffloadIndex.shared.cloud(for: location) else { return nil }
        return OffloadIndex.cloudFile(for: file, local: location, cloud: cloud)
    }

    /// Bytes kept in iCloud only (Settings › iCloud & storage).
    var offloadedBytes: Int64 { OffloadIndex.shared.offloadedBytes(in: location) }
    var offloadedCount: Int { OffloadIndex.shared.offloadedIDs(in: location).count }

    /// The pins whose full file may leave this device now: a picture the AI has looked at (with
    /// its thumbnail here) or a video whose length, sound and poster are known, added and last
    /// opened more than 30 days ago, not offloaded already.
    func offloadCandidates(now: Date = Date()) -> [(id: UUID, file: URL)] {
        let cutoff = now.addingTimeInterval(-OffloadIndex.keepDays * 86_400)
        let index = OffloadIndex.shared
        let already = index.offloadedIDs(in: location)
        var result: [(id: UUID, file: URL)] = []
        for pin in pins where !already.contains(pin.id) && pin.createdAt < cutoff {
            if let opened = index.lastOpened(pin.id, in: location), opened >= cutoff { continue }
            guard let file = OffloadIndex.offloadableFile(of: pin, in: location) else { continue }
            if pin.isVideo {
                guard (pin.duration ?? 0) > 0, pin.hasAudio != nil, pin.posterChecked,
                      pin.hasAudio == false || pin.transcript != nil || pin.transcriptChecked else { continue }
            } else {
                guard !pin.needsAnalysis,
                      FileManager.default.fileExists(atPath: thumbsURL.appendingPathComponent(pin.thumbFileName).path) else { continue }
            }
            result.append((pin.id, file))
        }
        return result
    }

    /// Lets the full files that may go (`offloadCandidates`) leave this device — only those iCloud
    /// holds in full. Run after each sync while "Optimize device storage" is on. Returns how many went.
    @discardableResult
    func offloadIfWanted(settings: AppSettings, now: Date = Date()) async -> Int {
        guard settings.optimizeStorage, settings.iCloudSync, !settings.offlineMode,
              let cloud = OffloadIndex.shared.cloud(for: location) else { return 0 }
        let location = self.location
        let profile = profileID
        let candidates = offloadCandidates(now: now)
        guard !candidates.isEmpty else { return 0 }
        let gone = await Task.detached(priority: .background) { () -> [UUID] in
            var gone: [UUID] = []
            for (id, file) in candidates {
                let cloudFile = OffloadIndex.cloudFile(for: file, local: location, cloud: cloud)
                guard FileManager.default.fileExists(atPath: file.path),
                      OffloadIndex.cloudHasInFull(cloudFile) else { continue }
                let bytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                OffloadIndex.shared.markOffloaded(id, bytes: bytes, in: location)   // first, so nothing calls it missing
                if (try? FileManager.default.removeItem(at: file)) != nil {
                    gone.append(id)
                } else {
                    OffloadIndex.shared.markHere(id, in: location)
                }
            }
            return gone
        }.value
        guard isCurrentProfile(profile) else { return gone.count }
        for id in gone { fullCache.removeObject(forKey: id.uuidString as NSString) }
        if !gone.isEmpty { objectWillChange.send() }
        return gone.count
    }

    /// "Download everything": brings every offloaded file back, four side by side.
    /// `progress(done, total)` after each one. Returns how many couldn't come.
    func bringEverythingBack(progress: (Int, Int) -> Void) async -> Int {
        let ids = OffloadIndex.shared.offloadedIDs(in: location)
        let offloaded = pins.filter { ids.contains($0.id) }
        var missing = 0
        var done = 0
        var next = 0
        progress(0, offloaded.count)
        await withTaskGroup(of: Bool.self) { (group: inout TaskGroup<Bool>) in
            while next < offloaded.count && next < 4 {
                let pin = offloaded[next]
                group.addTask { await self.ensureLocal(pin) }
                next += 1
            }
            while let came = await group.next() {
                done += 1
                if !came { missing += 1 }
                progress(done, offloaded.count)
                if Task.isCancelled {
                    group.cancelAll()
                } else if next < offloaded.count {
                    let pin = offloaded[next]
                    group.addTask { await self.ensureLocal(pin) }
                    next += 1
                }
            }
        }
        progress(offloaded.count, offloaded.count)
        return missing
    }
}

// MARK: - How far a download has got

/// Watches how far iCloud has got with bringing one file down (0–100), for the screens that wait
/// for it ("Getting the picture from iCloud… 40%"). It asks iCloud's own file list (which also
/// makes iCloud tell this device about the file, if it didn't know of it yet); when iCloud says
/// nothing, the screens just show the spinner. Each word from iCloud wakes the wait for the file.
@MainActor
final class CloudDownloadWatch {
    private var query: NSMetadataQuery? = nil
    private var observers: [NSObjectProtocol] = []
    private var file: URL? = nil
    private var onChange: (Double) -> Void = { _ in }

    /// Starts watching `file` (a file in the app's iCloud folder); `onChange` gets each new percentage.
    func start(_ file: URL, onChange: @escaping (Double) -> Void) {
        stop()
        self.file = file
        self.onChange = onChange
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, file.lastPathComponent)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
                CloudActivity.shared.poke()   // the wait for this file looks again (CloudWaiting.swift)
            }
            observers.append(observer)
        }
        self.query = query
        if !query.start() { stop() }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        query?.stop()
        query = nil
    }

    /// Reads the percentage of the one result that is this file (same folder and name).
    private func read() {
        guard let query, let file else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let folder = file.deletingLastPathComponent().lastPathComponent
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  path.hasSuffix("/" + folder + "/" + file.lastPathComponent),
                  let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double else { continue }
            onChange(percent)
            return
        }
    }
}

/// The line under a picture or video that is coming from iCloud: "Getting the picture from
/// iCloud… 40%" (the percentage once iCloud says how far it is).
struct FromICloudNote: View {
    let what: String          // "picture" or "video"
    let percent: Double?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(text)
                .font(.footnote)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        guard let percent, percent > 0 else { return "Getting the \(what) from iCloud…" }
        return "Getting the \(what) from iCloud… \(Int(percent.rounded()))%"
    }
}

/// Why a picture or video didn't come from iCloud, over the page that waited for it, with Retry:
/// "You're offline…", "The file is missing from iCloud…", "iCloud couldn't download this file…",
/// "Still downloading from iCloud (40%)".
struct CloudProblemNote: View {
    let problem: CloudFetchProblem
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: problem.symbol)
                .font(.title3)
                .accessibilityHidden(true)
            Text(problem.text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Views

/// Shows `content` (a video player) once the pin's video is on this device. While a video kept
/// in iCloud only comes back, its poster shows with a spinner; if it can't come, a short line says so.
struct BroughtBack<Content: View>: View {
    let pin: Pin
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var store: LibraryStore
    @State private var phase: Phase = .checking
    @State private var poster: UIImage? = nil
    @State private var percent: Double? = nil
    @State private var problem: CloudFetchProblem? = nil   // why it couldn't come
    @State private var attempt = 0                 // "Retry" counts up, which starts it anew
    @State private var watch = CloudDownloadWatch()

    private enum Phase { case checking, ready, failed }

    var body: some View {
        Group {
            if phase == .ready || (phase == .checking && store.cloudFileToFetch(pin) == nil) {
                content()
            } else {
                waiting
            }
        }
        .task(id: "\(pin.id)|\(attempt)") {
            if let cloudFile = store.cloudFileToFetch(pin) {   // in iCloud only, or missing here
                phase = .checking
                percent = nil
                problem = nil
                watch.start(cloudFile) { (value: Double) in percent = value }
                poster = await store.thumbnail(for: pin)
            }
            problem = await store.ensureLocalForViewing(pin)   // (notes it as opened, too)
            watch.stop()
            phase = problem == nil ? .ready : .failed
        }
        .onDisappear { watch.stop() }
    }

    private var waiting: some View {
        ZStack {
            Color.black
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.6)
            }
            VStack(spacing: 10) {
                if phase == .failed {
                    CloudProblemNote(problem: problem ?? .stillDownloading(percent.map { Int($0.rounded()) })) { attempt += 1 }
                } else {
                    FromICloudNote(what: "video", percent: percent)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}

/// Settings › iCloud & storage: "Optimize device storage", how much lives in iCloud only, and "Download
/// everything" (with its progress and Stop).
struct OptimizeStorageRows: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @State private var bringing: (done: Int, total: Int)? = nil
    @State private var bringTask: Task<Void, Never>? = nil
    @State private var note: String? = nil

    private var canOptimize: Bool { settings.iCloudSync && !settings.offlineMode }

    var body: some View {
        Toggle(SettingsCatalog.title(.optimizeStorage), isOn: Binding(
            get: { settings.optimizeStorage && canOptimize },
            set: { (on: Bool) in
                settings.optimizeStorage = on
                if on { Task { await store.offloadIfWanted(settings: settings) } }
            }))
            .disabled(!canOptimize)
            .settingsRow(.optimizeStorage)
        Text(explanation)
            .font(.footnote)
            .foregroundStyle(.secondary)
        if store.offloadedCount > 0 || bringing != nil {
            HStack {
                Text("In iCloud only")
                Spacer()
                Text("\(store.offloadedCount.formatted()) · \(StoragePolicy.sizeText(Int(store.offloadedBytes)))")
                    .foregroundStyle(.secondary)
            }
            downloadRow
        }
        if let note {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var explanation: String {
        if !settings.iCloudSync { return "Needs “\(SettingsCatalog.title(.iCloudSync))” (above)." }
        if settings.offlineMode { return "Not while Offline mode is on." }
        return "Full-size pictures and videos you haven't added or opened in \(Int(OffloadIndex.keepDays)) days are kept in iCloud only. Thumbnails stay, so browsing and search work offline; opening one gets it from iCloud."
    }

    @ViewBuilder
    private var downloadRow: some View {
        if let bringing {
            HStack(spacing: 8) {
                WorkProgressLine(text: "Downloading \(bringing.done.formatted()) of \(bringing.total.formatted())…")
                Spacer()
                Button("Stop") { bringTask?.cancel() }
                    .buttonStyle(.borderless)
            }
        } else {
            Button("Download everything") { downloadEverything() }
        }
    }

    /// Brings every offloaded file back (say before a trip). With the switch on, files not used
    /// for 30 days leave again after a later sync.
    private func downloadEverything() {
        note = nil
        bringing = (0, store.offloadedCount)
        bringTask = Task { @MainActor in
            let missing = await store.bringEverythingBack { (done: Int, total: Int) in bringing = (done, total) }
            bringing = nil
            bringTask = nil
            if missing > 0 { note = PinActionText.notFromICloud(missing) }
            else if settings.optimizeStorage { note = "Everything is on this device. With the switch on, what you don't use leaves again after a while." }
        }
    }
}
