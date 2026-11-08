//
//  CloudChanges.swift  —  PinBoard
//
//  Keeping iCloud sync quick when little or nothing changed.
//  - A change marker per profile: after a full sync, a short fingerprint of this device's library
//    and the date and size of iCloud's library file are kept. The next sync looks at both first;
//    when neither changed it is done in about a second ("Nothing changed"), without comparing
//    every pin or asking about every file.
//  - A watcher: iCloud tells the app when another device wrote its library file, so a sync starts
//    by itself (no polling). The app's own write doesn't start one (its marker matches).
//  - The quiet download: pins arrive with their thumbnail first (CloudArrivals.swift); their full
//    pictures and videos come afterwards, a few at a time, without holding the "Syncing" pill.
//    Progress shows in Settings › iCloud & storage ("Bringing full pictures and videos: 120 of 900").
//

import Foundation
import CryptoKit
import SwiftUI

/// What a profile's library looked like on both sides after its last full sync.
struct SyncStamp: Codable, Equatable, Sendable {
    var local: String    // fingerprint of this device's library (see `CloudSync.localStamp`)
    var remote: String   // date and size of iCloud's library file (see `CloudSync.remoteStamp`)
}

extension CloudSync {
    private static let stampsKey = "cloudSyncStamps"

    /// The marker kept after the profile's last full sync (nil: none, or something was left to do).
    static func savedStamp(for profile: UUID) -> SyncStamp? {
        guard let data = UserDefaults.standard.data(forKey: stampsKey),
              let all = try? JSONDecoder().decode([String: SyncStamp].self, from: data) else { return nil }
        return all[profile.uuidString]
    }

    /// Keeps (or with nil forgets) the profile's marker.
    static func saveStamp(_ stamp: SyncStamp?, for profile: UUID) {
        var all: [String: SyncStamp] = [:]
        if let data = UserDefaults.standard.data(forKey: stampsKey),
           let read = try? JSONDecoder().decode([String: SyncStamp].self, from: data) { all = read }
        all[profile.uuidString] = stamp
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: stampsKey) }
    }

    /// iCloud's library file as this device knows it: its date and size, read fresh. nil when it
    /// isn't here in full (a newer copy is waiting in iCloud, or there is none): that counts as changed.
    nonisolated static func remoteStamp(of file: URL) -> String? {
        guard isFullyHere(file) else { return nil }
        let fresh = URL(fileURLWithPath: file.path)
        guard let values = try? fresh.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate else { return nil }
        return "\(date.timeIntervalSince1970)|\(values.fileSize ?? 0)"
    }

    /// A short fingerprint of a library: the same library always gives the same text (keys sorted),
    /// any change gives another. About a tenth of a second for a few thousand pins.
    nonisolated static func localStamp(_ document: LibraryDocument) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return UUID().uuidString }   // (never matches)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// "0.4 s" since `start`, for the sync log.
    nonisolated static func took(_ start: Date) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(start))
    }

    // MARK: Told about changes

    /// Starts watching iCloud's library files (once): when another device writes this profile's
    /// library, a sync starts a few seconds later. Nothing happens for the app's own writes.
    func watchForChanges(store: LibraryStore, settings: AppSettings) {
        guard watcher == nil else { return }
        let watcher = CloudLibraryWatcher()
        watcher.start { [weak self, weak store] in
            guard let self, let store else { return }
            self.remoteMayHaveChanged(store: store, settings: settings)
        }
        self.watcher = watcher
    }

    /// iCloud reported a change to a library file: if this profile's differs from what the last
    /// sync left there, a sync is due.
    private func remoteMayHaveChanged(store: LibraryStore, settings: AppSettings) {
        guard !isSyncing, let container = containerURL, let cloudID = CloudSync.cloudFolder(of: store.profileID) else { return }
        let file = CloudSync.remoteLocation(container: container, profileID: cloudID).library
        let saved = CloudSync.savedStamp(for: store.profileID)
        guard CloudSync.remoteStamp(of: file) != saved?.remote else { return }
        SyncLog.add("iCloud says the library changed on another device")
        syncSoon(store: store, settings: settings, delay: 3)
    }

    /// The library here was saved. A sync follows in a while — unless the save only holds what a
    /// sync just brought (that would make the devices set each other off, over and over).
    func librarySaved(store: LibraryStore, settings: AppSettings) {
        if isSyncing { return }   // (changes made during a sync are noticed at its end)
        if syncedVersion[store.profileID] == store.contentVersion { return }
        syncSoon(store: store, settings: settings)
    }

    // MARK: The quiet download

    /// Brings the full pictures and videos of pins that came with a sync (thumbnail first), a few
    /// at a time, in the background of the app. With Optimize device storage on, the ones it would
    /// keep in iCloud anyway (not added or opened for 30 days) aren't downloaded at all. Stops when
    /// another profile is opened, sync is switched off or Offline mode is on; the rest comes after
    /// the next sync (or when opened).
    func bringFullFilesQuietly(store: LibraryStore, settings: AppSettings) {
        guard filesTask == nil else { return }
        let location = store.location
        let waiting = OffloadIndex.shared.arrivingIDs(in: location)
        guard !waiting.isEmpty else { return }
        let profile = store.profileID
        filesTask = Task { @MainActor [weak self, weak store] in
            guard let store else { return }
            await self?.runQuietDownload(waiting, store: store, settings: settings, profile: profile)
            self?.filesTask = nil
            self?.filesStatus = nil
            self?.stopWatchingFolderIfIdle()
        }
    }

    private func runQuietDownload(_ waiting: Set<UUID>, store: LibraryStore, settings: AppSettings, profile: UUID) async {
        let location = store.location
        guard let cloud = OffloadIndex.shared.cloud(for: location) else { return }
        let cutoff = Date().addingTimeInterval(-OffloadIndex.keepDays * 86_400)
        var keepInICloud: Set<UUID> = []
        var pins: [Pin] = []
        for pin in store.pins where waiting.contains(pin.id) {
            let opened = OffloadIndex.shared.lastOpened(pin.id, in: location)
            let old = pin.createdAt < cutoff && (opened ?? .distantPast) < cutoff
            if settings.optimizeStorage && old { keepInICloud.insert(pin.id) } else { pins.append(pin) }
        }
        OffloadIndex.shared.stopArriving(keepInICloud, in: location)
        if !keepInICloud.isEmpty { SyncLog.add("\(keepInICloud.count.formatted()) old pins stay in iCloud only (Optimize device storage)") }
        guard !pins.isEmpty else { return }
        let start = Date()
        // What to fetch: each pin's full file and its copy in iCloud.
        let jobs: [QuietFetch] = pins.compactMap { (pin: Pin) -> QuietFetch? in
            guard let file = OffloadIndex.offloadableFile(of: pin, in: location) else { return nil }
            return QuietFetch(id: pin.id, file: file, cloudFile: OffloadIndex.cloudFile(for: file, local: location, cloud: cloud),
                              patience: pin.isVideo ? CloudSync.videoWait : CloudSync.pictureWait)
        }
        guard !jobs.isEmpty else { return }
        SyncLog.add("Bringing \(jobs.count.formatted()) full pictures and videos")
        await watchFolder(cloud, list: false, store: store)   // iCloud wakes the waits when files come
        // Six at a time; as soon as one is done the next starts, and the count goes up by one.
        var done = 0
        var failed = 0
        var next = 0
        var problems: [String] = []
        filesStatus = "Bringing full pictures and videos: 0 of \(jobs.count.formatted())"
        await withTaskGroup(of: CloudFetchProblem?.self) { (group: inout TaskGroup<CloudFetchProblem?>) in
            func startNext() {
                let job = jobs[next]
                next += 1
                group.addTask {
                    await OffloadIndex.bringBack(job.id, file: job.file, from: job.cloudFile, in: location, patience: job.patience)
                }
            }
            while next < jobs.count && next < CloudSync.quietDownloads { startNext() }
            while let problem = await group.next() {
                done += 1
                if let problem {
                    failed += 1
                    if problems.count < 3 { problems.append(problem.text) }
                } else {
                    store.objectWillChange.send()   // views showing "in iCloud only" look again
                }
                filesStatus = "Bringing full pictures and videos: \(done.formatted()) of \(jobs.count.formatted())"
                let goOn = store.isCurrentProfile(profile) && settings.iCloudSync && !settings.offlineMode && !Task.isCancelled
                if goOn && next < jobs.count { startNext() }
            }
        }
        for problem in problems { SyncLog.add("A full file didn't come: \(problem)") }
        SyncLog.add("Full files: \(done - failed) came, \(failed) didn't, \(jobs.count - done) not tried (\(CloudSync.took(start)))")
    }

    /// How many full files the quiet download fetches side by side.
    nonisolated static let quietDownloads = 6

    /// One full file the quiet download fetches.
    private struct QuietFetch: Sendable {
        var id: UUID
        var file: URL
        var cloudFile: URL
        var patience: Double
    }
}

/// Watches iCloud's library files ("library.json" of every profile) and calls back when iCloud
/// reports a change to one. The query runs while the app is open; iCloud does the watching.
@MainActor
final class CloudLibraryWatcher {
    private var query: NSMetadataQuery? = nil
    private var observer: NSObjectProtocol? = nil
    private var onChange: () -> Void = {}

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "library.json")
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
        self.query = query
        if !query.start() { SyncLog.add("Couldn't watch iCloud for changes") }
    }
}
