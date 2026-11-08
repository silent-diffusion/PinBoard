//
//  CloudProfiles.swift  —  PinBoard
//
//  Which iCloud folder a profile syncs with. Every device makes its own first profile ("My
//  library") with its own new id, so the id alone would give each device a folder of its own in
//  iCloud and they would never meet. iCloud keeps a list of the profiles it has
//  (Documents/PinBoard/profiles.json); a profile here syncs with the one in that list that has
//  its id or, failing that, the same name. A profile with no match is added to the list.
//  Also: the sync log (Settings › iCloud & storage › Sync log), a short diary of the last syncs.
//

import Foundation
import SwiftUI
import os

/// One profile in iCloud's list.
struct CloudProfile: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
}

extension CloudSync {
    /// iCloud's list of profiles, next to their folders.
    nonisolated static func profileListURL(container: URL) -> URL {
        container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("PinBoard", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    /// The id of the iCloud folder `profile` syncs with, in this order: the one it synced with
    /// before (`linked`, if iCloud's list still has it), its own id (if the list has it), a profile
    /// in the list with the same name that no other profile here syncs with (`takenElsewhere`),
    /// or — none of those — its own id, added to the list.
    /// Two devices adding themselves at the same moment can leave only one of them in the list;
    /// the other finds that one by its name at its next sync, and its library merges in there.
    nonisolated static func cloudProfileID(for profile: Profile, linked: UUID?, takenElsewhere: Set<UUID>,
                                           container: URL) async throws -> UUID {
        let listURL = profileListURL(container: container)
        var list = try await readProfileList(at: listURL)
        let ids = Set(list.map { (entry: CloudProfile) -> UUID in entry.id })
        if let linked, ids.contains(linked) { return linked }
        if ids.contains(profile.id) { return profile.id }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = list.first(where: { (entry: CloudProfile) -> Bool in
            !takenElsewhere.contains(entry.id)
                && entry.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }) {
            return match.id
        }
        list.append(CloudProfile(id: profile.id, name: name))
        try FileManager.default.createDirectory(at: listURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try coordinatedWrite(data, to: listURL) }
        return profile.id
    }

    /// iCloud's list of profiles (empty when there is none yet). A list iCloud knows about but
    /// can't bring here is an error: starting a new list would split the devices again.
    nonisolated private static func readProfileList(at url: URL) async throws -> [CloudProfile] {
        guard let data = try await readCloudFile(at: url) else { return [] }
        return (try? JSONDecoder().decode([CloudProfile].self, from: data)) ?? []
    }

    /// Reads a file in iCloud, waiting up to 30 seconds for it to come down. nil: iCloud has no
    /// such file. Throws when iCloud has it but it didn't come.
    nonisolated static func readCloudFile(at url: URL) async throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) || isUbiquitousPlaceholder(url) else { return nil }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        await waitForDownload(url, timeout: 30)
        // Not here after the wait: the read below would wait for iCloud with no end (build 10's
        // sync could hang there for good), so this sync stops and the next one tries again.
        guard isFullyHere(url) else {
            SyncLog.add("\(url.lastPathComponent) didn't come from iCloud in 30 s")
            throw CloudSyncError.notDownloaded(url.lastPathComponent)
        }
        var data: Data? = nil
        var coordinationError: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        if let coordinationError { throw coordinationError }
        guard let data else { throw CloudSyncError.notDownloaded(url.lastPathComponent) }
        return data
    }

    /// Has iCloud bring this device the list of some files in the app's iCloud folder — those
    /// named `names` (say every profile's library.json), or every file when `names` is nil — so a
    /// new device knows of files the others put there (a file it doesn't know of would look
    /// missing). Waits up to `timeout` seconds; nothing is downloaded here.
    func refreshCloudListing(names: [String]? = nil, timeout: Double = 15) async {
        let started = Date()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        if let names {
            query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: names.map { (name: String) -> NSPredicate in
                NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, name)
            })
        } else {
            query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")   // every file: pictures too
        }
        let gathered = OneShot()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gathered.continuation = continuation
            gathered.observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { _ in
                MainActor.assumeIsolated { gathered.finish() }
            }
            if !query.start() { gathered.finish() }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                gathered.finish()
            }
        }
        query.stop()
        SyncLog.add("Listed \(names?.joined(separator: ", ") ?? "every file") in iCloud: \(CloudSync.took(started))")
    }

    /// Starts iCloud's query for this profile's folder (`CloudFolderWatch`), unless it already
    /// runs. With `list` (the first sync of this launch) it waits until iCloud has told this device
    /// about every file there — up to a minute, as a safety net; Stop ends the wait. If the folder's
    /// query finds nothing at all, the whole iCloud folder is watched the old way instead.
    func watchFolder(_ remote: LibraryLocation, list: Bool, store: LibraryStore) async {
        let key = remote.root.standardizedFileURL.path
        if watchedFolder != key || folderWatch == nil {
            folderWatch?.stop()
            let watch = CloudFolderWatch()
            watch.start(folder: remote.root)
            folderWatch = watch
            watchedFolder = key
        }
        guard list, let watch = folderWatch else { return }
        let started = Date()
        store.syncStatus = "Syncing with iCloud… looking at iCloud's files"
        var done = false
        for _ in 0..<60 where !done && !stopRequested {
            done = await watch.waitForGathering(timeout: 1)
        }
        SyncLog.add("Listed this profile's iCloud folder (\(watch.found.formatted()) files): \(CloudSync.took(started))\(done ? "" : ", not finished")")
        if done && watch.found == 0 && !stopRequested {
            // The folder's query found nothing (not even its library.json): the old way, every file
            // of the app's iCloud folder, 15 s at most. It stays on to wake the waits.
            let wide = Date()
            watch.start(folder: remote.root, wholeContainer: true)
            let finished = await watch.waitForGathering(timeout: 15)
            SyncLog.add("Listed every file in iCloud instead (\(watch.found.formatted()) files): \(CloudSync.took(wide))\(finished ? "" : ", not finished")")
        }
        store.syncStatus = "Syncing with iCloud…"
    }

    /// Stops the folder's query once neither a sync nor the quiet download needs it.
    func stopWatchingFolderIfIdle() {
        guard !isSyncing, filesTask == nil else { return }
        folderWatch?.stop()
        folderWatch = nil
        watchedFolder = nil
    }
}

/// Ends a wait once: whichever comes first, the query being done or the time running out.
@MainActor
private final class OneShot {
    var continuation: CheckedContinuation<Void, Never>? = nil
    var observer: NSObjectProtocol? = nil

    func finish() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation?.resume()
        continuation = nil
    }
}

/// Why a sync stopped.
enum CloudSyncError: LocalizedError {
    case notDownloaded(String)

    var errorDescription: String? {
        switch self {
        case .notDownloaded(let name): return "iCloud hasn't brought \(name) to this device yet. It tries again next time."
        }
    }
}

// MARK: - The sync log

/// A short diary of the last syncs on this device (Settings › iCloud & storage › Sync log): when each began
/// and ended, how many pins came per round, what is waiting and why a run stopped. It helps tell
/// what a slow or stuck sync is doing. It stays on this device (never synced, never sent) and
/// keeps only the last 400 lines. Safe from any thread.
enum SyncLog {
    nonisolated static let maxLines = 400
    private static let lines = OSAllocatedUnfairLock<[String]?>(initialState: nil)

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("sync-log.txt")
    }

    /// Adds a line, with the time, and saves the log.
    nonisolated static func add(_ text: String) {
        let stamp = Date().formatted(date: .numeric, time: .standard)
        let saved: String = lines.withLock { (state: inout [String]?) -> String in
            var all = state ?? readFile()
            all.append(stamp + "  " + text)
            if all.count > maxLines { all.removeFirst(all.count - maxLines) }
            state = all
            return all.joined(separator: "\n")
        }
        let target = file
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? saved.data(using: .utf8)?.write(to: target, options: .atomic)
    }

    /// Every line, oldest first.
    nonisolated static func all() -> [String] {
        lines.withLock { (state: inout [String]?) -> [String] in
            let all = state ?? readFile()
            state = all
            return all
        }
    }

    nonisolated static func clear() {
        lines.withLock { (state: inout [String]?) in state = [] }
        try? FileManager.default.removeItem(at: file)
    }

    private static func readFile() -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n")
    }
}

/// Settings › iCloud & storage › Sync log: the diary, newest first, with Copy (to paste into a message) and Clear.
struct SyncLogPage: View {
    @State private var lines: [String] = []

    var body: some View {
        List {
            if lines.isEmpty {
                Text("Nothing yet. Each sync writes a few lines here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { (_, line: String) in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Sync log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Copy") { UIPasteboard.general.string = SyncLog.all().joined(separator: "\n") }
                    .disabled(lines.isEmpty)
                Button("Clear", role: .destructive) {
                    SyncLog.clear()
                    lines = []
                }
                .disabled(lines.isEmpty)
            }
        }
        .task {
            // Read again every few seconds while open, so a running sync can be watched.
            while !Task.isCancelled {
                lines = SyncLog.all().reversed()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
