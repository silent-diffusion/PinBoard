//
//  CloudWaiting.swift  —  PinBoard
//
//  Waiting for iCloud without asking it over and over.
//  - `CloudActivity`: iCloud tells the app when files in its folder change (a download finished,
//    new files were listed) through a metadata query; every wait for a file wakes up then and looks
//    again. A slow clock stays as a safety net, so a missed word from iCloud never stalls a wait.
//  - `CloudFolderWatch`: the query for one profile's iCloud folder. It runs while a sync runs: its
//    first gathering is the listing a new device needs (what the other devices put there), and its
//    updates wake the waits.
//  - `CloudFetchProblem`: why a file didn't come from iCloud, in words for the screen.
//  - `NetworkStatus`: whether the device is online (so a page can say "You're offline" at once).
//  - `CloudSync.inParallel`: runs a few waits side by side (about six), not one after another.
//

import Foundation
import Network
import os

// MARK: - iCloud's word that something changed

/// A doorbell for everyone waiting on iCloud files. `poke` wakes every wait; `wait(seconds:)`
/// returns at the next poke, or after `seconds` (the safety net), or when the task is cancelled.
/// Safe from any thread.
final class CloudActivity: Sendable {
    static let shared = CloudActivity()

    private struct State {
        var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// iCloud reported a change: every wait looks again.
    func poke() {
        let all = state.withLock { (state: inout State) -> [CheckedContinuation<Void, Never>] in
            let all = Array(state.waiting.values)
            state.waiting = [:]
            return all
        }
        for continuation in all { continuation.resume() }
    }

    /// Waits for the next poke, `seconds` at most.
    func wait(seconds: Double) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                state.withLock { (state: inout State) in state.waiting[id] = continuation }
                if Task.isCancelled { resume(id) }   // (cancelled before it was registered)
                Task.detached { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0.05, seconds) * 1_000_000_000))
                    self?.resume(id)
                }
            }
        } onCancel: {
            resume(id)
        }
    }

    /// Ends one wait (only once: whoever comes first takes it out).
    private func resume(_ id: UUID) {
        let continuation = state.withLock { (state: inout State) -> CheckedContinuation<Void, Never>? in
            state.waiting.removeValue(forKey: id)
        }
        continuation?.resume()
    }
}

// MARK: - Watching one profile's iCloud folder

/// The metadata query for one profile's folder in iCloud (only that folder: a big library in
/// another profile doesn't slow it down). Its first gathering makes iCloud tell this device about
/// every file there; its updates (downloads finishing, files arriving) wake the waits through
/// `CloudActivity`. Runs on the main thread, where iCloud delivers its news.
@MainActor
final class CloudFolderWatch {
    private var query: NSMetadataQuery? = nil
    private var observers: [NSObjectProtocol] = []
    private var gathered = false
    private var gatherWaiters: [CheckedContinuation<Void, Never>] = []
    /// How many files the query found when it had gathered (for the sync log and the fallback).
    private(set) var found = 0

    /// Starts watching `folder` (a profile's folder in the app's iCloud container). With
    /// `wholeContainer` the query looks at every file of the app's iCloud folder instead (the old
    /// way, used only when the folder query finds nothing).
    func start(folder: URL, wholeContainer: Bool = false) {
        stop()
        gathered = false
        found = 0
        let query = NSMetadataQuery()
        if wholeContainer {
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        } else {
            query.searchScopes = [folder]
        }
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
        query.notificationBatchingInterval = 0.5   // a burst of finished downloads is one wake-up
        let finished = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                              object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didGather() }
        }
        let updated = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate,
                                                             object: query, queue: .main) { _ in
            CloudActivity.shared.poke()
        }
        observers = [finished, updated]
        self.query = query
        if !query.start() {
            SyncLog.add("Couldn't ask iCloud about this profile's folder")
            didGather()
        }
    }

    /// Waits until the first gathering is done, `timeout` seconds at most. true: it was done.
    func waitForGathering(timeout: Double) async -> Bool {
        if gathered { return true }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gatherWaiters.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.releaseGatherWaiters()
            }
        }
        return gathered
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        query?.stop()
        query = nil
        releaseGatherWaiters()
    }

    private func didGather() {
        if let query {
            query.disableUpdates()
            found = query.resultCount
            query.enableUpdates()
        }
        gathered = true
        releaseGatherWaiters()
        CloudActivity.shared.poke()
    }

    private func releaseGatherWaiters() {
        let waiters = gatherWaiters
        gatherWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

// MARK: - Why a file didn't come

/// Why a picture or video couldn't come from iCloud, for the screen that waited for it.
enum CloudFetchProblem: Equatable, Sendable {
    case offline                    // the device has no connection
    case missing                    // iCloud doesn't have the file (any more)
    case iCloudError(String)        // iCloud reported an error for it
    case stillDownloading(Int?)     // it didn't come in time; iCloud is still at it (percent, when known)
    case noICloud                   // iCloud isn't available, or this profile's iCloud folder isn't known

    /// The short line shown in place of the picture.
    var text: String {
        switch self {
        case .offline: return "You're offline. Connect to the internet to get this from iCloud."
        case .missing: return "The file is missing from iCloud. It may have been deleted on another device, or not sent yet."
        case .iCloudError(let reason): return "iCloud couldn't download this file. \(reason)"
        case .stillDownloading(let percent):
            if let percent, percent > 0 { return "Still downloading from iCloud (\(percent)%)" }
            return "Still downloading from iCloud"
        case .noICloud: return "iCloud isn't available on this device right now."
        }
    }

    /// The symbol drawn above the line.
    var symbol: String {
        switch self {
        case .offline: return "wifi.slash"
        case .stillDownloading: return "icloud.and.arrow.down"
        default: return "icloud.slash"
        }
    }
}

// MARK: - Online or not

/// Whether the device has a connection right now (watched by the system, no polling). Any change
/// wakes the waits (`CloudActivity`): going offline ends them at once, coming back starts them
/// again. Coming back is also announced (`backOnline`, on the main thread): a sync that stopped
/// because the device was offline starts again then.
final class NetworkStatus: Sendable {
    static let shared = NetworkStatus(monitoring: true)

    /// Posted on the main thread when the connection comes back after being lost.
    static let backOnline = Notification.Name("PinBoard.backOnline")

    private let monitor = NWPathMonitor()
    private let online = OSAllocatedUnfairLock(initialState: true)   // until the system says otherwise

    /// `monitoring`: false only in tests, which call `update(isOnline:)` themselves.
    init(monitoring: Bool) {
        guard monitoring else { return }
        monitor.pathUpdateHandler = { [weak self] (path: NWPath) in
            self?.update(isOnline: path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "PinBoard.network", qos: .utility))
    }

    /// The system's news. Returns true when it was a change (offline ↔ online).
    @discardableResult
    func update(isOnline: Bool) -> Bool {
        let was = online.withLock { (value: inout Bool) -> Bool in
            defer { value = isOnline }
            return value
        }
        guard was != isOnline else { return false }
        CloudActivity.shared.poke()   // waits look again: offline ends them, online lets them go on
        if isOnline {
            DispatchQueue.main.async { NotificationCenter.default.post(name: NetworkStatus.backOnline, object: self) }
        }
        return true
    }

    var isOffline: Bool { !online.withLock { $0 } }
}

// MARK: - Waiting for files

extension CloudSync {
    /// Asks iCloud to bring a file here. nil: asked (or it is a plain file); otherwise iCloud's
    /// reason for saying no (no account, no such file…), which is written to the sync log too
    /// (unless `log` is false: the caller writes it).
    @discardableResult
    nonisolated static func startDownload(_ url: URL, log: Bool = true) -> Error? {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        } catch {
            // A plain file (not in iCloud, as in a test) can't be "downloaded": that's not a problem.
            if FileManager.default.fileExists(atPath: url.path), !isInICloud(url) { return nil }
            if log { SyncLog.add("iCloud wouldn't download \(url.lastPathComponent): \(error.localizedDescription)") }
            return error
        }
    }

    /// Whether the file is one iCloud looks after (read fresh: see `isFullyHere`).
    nonisolated static func isInICloud(_ url: URL) -> Bool {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    /// The error iCloud reported for a file it was asked to bring (nil: none), read fresh.
    nonisolated static func downloadError(of url: URL) -> Error? {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey]))?.ubiquitousItemDownloadingError
    }

    /// The file is in iCloud (here in full, or listed and waiting to be downloaded).
    nonisolated static func isKnownToICloud(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || isUbiquitousPlaceholder(url)
    }

    /// Waits until iCloud has the file here, or gives up after `timeout` seconds. It looks again
    /// whenever iCloud says something changed (`CloudActivity`), and otherwise now and then: often
    /// at first, then every few seconds (the safety net when iCloud says nothing). Stops at once
    /// when the device goes offline. true: the file is here.
    @discardableResult
    nonisolated static func waitForDownload(_ url: URL, timeout: TimeInterval) async -> Bool {
        // Offline, a file that isn't here can't come: no point waiting out the clock.
        _ = await waitUntil(timeout: timeout) { isFullyHere(url) || NetworkStatus.shared.isOffline }
        return isFullyHere(url)
    }

    /// Waits until `isDone` says yes, looking again at each word from iCloud and on a slowing clock
    /// (0.25 s at first, then up to every 3 s). false: the time ran out or the task was cancelled.
    nonisolated static func waitUntil(timeout: TimeInterval, _ isDone: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var pause = 0.25
        while true {
            if isDone() { return true }
            let left = deadline.timeIntervalSinceNow
            if left <= 0 || Task.isCancelled { return false }
            await CloudActivity.shared.wait(seconds: min(pause, left))
            pause = min(pause * 1.6, 3)
        }
    }

    /// Runs `body` for every item, at most `limit` at a time (a slow one doesn't hold up the
    /// others: the next starts as soon as any one is done). Returns the results in no set order.
    nonisolated static func inParallel<Item: Sendable, Output: Sendable>(
        _ items: [Item], limit: Int, _ body: @escaping @Sendable (Item) async -> Output) async -> [Output] {
        await withTaskGroup(of: Output.self) { (group: inout TaskGroup<Output>) -> [Output] in
            var results: [Output] = []
            var next = 0
            while next < items.count && next < limit {
                let item = items[next]
                group.addTask { await body(item) }
                next += 1
            }
            while let output = await group.next() {
                results.append(output)
                if next < items.count {
                    let item = items[next]
                    group.addTask { await body(item) }
                    next += 1
                }
            }
            return results
        }
    }
}
