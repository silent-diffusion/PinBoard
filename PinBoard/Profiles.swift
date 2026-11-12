//
//  Profiles.swift  —  PinBoard
//
//  Profiles (separate libraries you switch between) and the iCloud Drive sync
//  engine. Sync needs the device to be signed in to iCloud with iCloud Drive on.
//

import SwiftUI
import Foundation
import os

// MARK: - Profiles

@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var currentID: UUID

    private static let profilesKey = "profiles"
    private static let currentKey = "currentProfileID"

    /// Documents/PinBoard — every profile lives in a folder inside.
    static var rootURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("PinBoard", isDirectory: true)
    }

    static func location(for profileID: UUID) -> LibraryLocation {
        LibraryLocation(root: rootURL.appendingPathComponent("Profiles", isDirectory: true).appendingPathComponent(profileID.uuidString, isDirectory: true))
    }

    init() {
        let (stored, current) = ProfileManager.launchProfiles()
        profiles = stored
        currentID = current
        // Made once, at launch (see AppServices): no export is being shared any more, so the
        // temporary copies and zips earlier exports left behind can go (in the background).
        Task.detached(priority: .utility) { LibraryExporter.removeTemporaryExports() }
    }

    /// The profiles and the one in use, as stored — on the first run, the existing library becomes
    /// the first profile. Read by ProfileManager and, at launch, by `AppSettings.shared` (which
    /// can't wait for AppServices: making the store reads settings). Saved, so a second call agrees.
    static func launchProfiles() -> (profiles: [Profile], current: UUID) {
        let defaults = UserDefaults.standard
        var stored: [Profile] = []
        if let data = defaults.data(forKey: profilesKey), let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            stored = decoded
        }
        var current = defaults.string(forKey: currentKey).flatMap { UUID(uuidString: $0) }
        if stored.isEmpty {
            // First run with profiles: the existing library becomes the first profile.
            let first = Profile(name: "My library")
            stored = [first]
            current = first.id
            migrateLegacyLibrary(into: location(for: first.id))
        }
        if current == nil || !stored.contains(where: { $0.id == current }) { current = stored[0].id }
        // Settings of their own: once, every profile gets the set they all used to share (ProfileSettings.swift).
        ProfileSettings.moveSharedSettings(to: stored.map { $0.id })
        save(stored, current: current!)
        return (stored, current!)
    }

    /// The old single library folder (Documents/PinBoardLibrary) moves into the first profile.
    private static func migrateLegacyLibrary(into location: LibraryLocation) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacy = documents.appendingPathComponent("PinBoardLibrary", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: location.library.path) else { return }
        try? FileManager.default.createDirectory(at: location.root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: location.root)
        if (try? FileManager.default.moveItem(at: legacy, to: location.root)) == nil {
            // Moving failed (should not happen on the same volume): copy instead.
            try? FileManager.default.copyItem(at: legacy, to: location.root)
        }
    }

    private func persist() {
        ProfileManager.save(profiles, current: currentID)
    }

    private static func save(_ profiles: [Profile], current: UUID) {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: profilesKey) }
        UserDefaults.standard.set(current.uuidString, forKey: currentKey)
    }

    var current: Profile { profiles.first { $0.id == currentID } ?? profiles[0] }

    var currentLocation: LibraryLocation { ProfileManager.location(for: currentID) }

    @discardableResult
    func create(name: String) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let profile = Profile(name: trimmed)
        profiles.append(profile)
        ProfileManager.location(for: profile.id).createFolders()
        persist()
        return profile
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        persist()
    }

    /// Switches the store to another profile, and every setting with it (each profile has its
    /// own: ProfileSettings.swift) — its iCloud sync, Offline mode, keys, look… The Hidden section
    /// locks: another library's hidden pins and boards ask for Face ID again (and nothing unlocked
    /// for the old one stays open). Settings offers no switch while an import writes into the
    /// library (`store.isImporting`); a running sync is stopped (`CloudSync.profileWillChange`).
    func select(_ id: UUID, store: LibraryStore) {
        guard id != currentID, profiles.contains(where: { $0.id == id }) else { return }
        HiddenAccess.shared.lock()
        SettingsSync.shared.stop()   // the old profile's settings stop travelling before the new ones show
        AppServices.shared.cloudSync.profileWillChange()   // a running sync stops; its result is dropped
        currentID = id
        persist()
        let settings = AppSettings.shared
        settings.switchProfile(to: id)
        store.switchTo(location: ProfileManager.location(for: id), profileID: id)
        FeedOrder.shared.useProfile(id)   // its own feed orders, and every feed gets a new order
        SettingsSync.shared.follow(settings, iCloudAvailable: AppServices.shared.cloudSync.isAvailable)
        Task { await OriginalsFolder.shared.refresh(settings: settings) }   // its own originals folder
    }

    /// Deletes a profile and everything in it. The current profile can't be deleted
    /// while it is current, and the last profile never can.
    func delete(_ id: UUID) -> Bool {
        guard profiles.count > 1, id != currentID, profiles.contains(where: { $0.id == id }) else { return false }
        profiles.removeAll { $0.id == id }
        persist()
        // Its originals in its originals folder (only files PinBoard named) go too (OriginalsFolder.swift),
        // then its settings and API keys (ProfileSettings.swift) and which iCloud folder it synced with.
        OriginalsFolder.forgetProfile(id, bookmark: ProfileSettings.defaults(for: id).data(forKey: "originalsBookmark"))
        ProfileSettings.forget(id)
        CloudSync.forgetLink(of: id)
        let folder = ProfileManager.location(for: id).root
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
        return true
    }
}

// MARK: - iCloud Drive sync

/// Keeps a profile's library in the app's iCloud Drive container and merges
/// what other devices put there. Every pin, board and smart board carries an
/// `updatedAt`; the newer copy wins — except a pin's picture, which comes from the device
/// whose picture is newer (the higher `pictureRevision`, see `mergedPin`) — and erased ids are
/// remembered so they don't come back. Files (pictures, videos, fingerprints) are copied whole: a
/// new pin's when it first reaches the other side, and a picture again whenever it changed on
/// one device (turned, cropped, a refreshed or dropped link preview, a new video poster: see
/// `carryChangedPictures`) — always from the newer picture to the older one. A picture for this
/// device is only staged during the sync; the store puts it in place afterwards, if nothing
/// changed that picture here meanwhile (`LibraryStore.applySynced`).
@MainActor
final class CloudSync: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published private(set) var isSyncing = false
    @Published var lastError: String? = nil
    /// "Stop" was tapped (Settings › iCloud & storage): the sync running now ends at its next step.
    @Published private(set) var stopRequested = false
    /// The profile the running sync belongs to (nil: none runs). Settings shows the sync's line and
    /// Stop only for the profile in use: after a switch the old one's never shows.
    @Published private(set) var syncingProfile: UUID? = nil
    /// The running sync's merge (stopped when Stop is tapped or another profile is chosen: its
    /// waits end, and what came so far is kept as usual).
    private var mergeTask: Task<Result<(MergeResult, UUID), Error>, Never>? = nil
    /// The last sync stopped because the device was offline (or iCloud wasn't there): the next one
    /// starts when the connection is back (`NetworkStatus.backOnline`).
    private var waitingForConnection = false
    private var onlineObserver: NSObjectProtocol? = nil
    /// Why the arrivals of the running sync stopped early (CloudArrivals.swift), and how many runs
    /// in a row iCloud sent nothing (the pause before the next try grows: `SyncRetry`).
    var arrivalsStop: SyncStop? = nil
    private var quietRuns = 0

    var containerURL: URL? = nil   // (not private: used by CloudChanges.swift)
    private var pendingTask: Task<Void, Never>? = nil
    /// The quiet download of full files after a sync, and its line in Settings › iCloud & storage (CloudChanges.swift).
    var filesTask: Task<Void, Never>? = nil
    @Published var filesStatus: String? = nil
    /// Told when another device writes the library (CloudChanges.swift).
    var watcher: CloudLibraryWatcher? = nil
    /// The library's `contentVersion` after each profile's last sync: a save of just that starts no new sync.
    var syncedVersion: [UUID: Int] = [:]
    /// How far the running sync itself moved `contentVersion` (what it brought), to tell its own
    /// changes from the ones made meanwhile.
    var ownChanges = 0
    /// Profiles whose iCloud folder was listed in full this launch (`refreshCloudListing`), and
    /// ones whose next sync should list it again (a pin's files weren't in iCloud yet).
    private var listedThisLaunch: Set<UUID> = []
    /// iCloud's query for the folder of the profile being synced (CloudWaiting.swift): runs while a
    /// sync or the quiet download after it runs, and wakes their waits when files come.
    var folderWatch: CloudFolderWatch? = nil
    var watchedFolder: String? = nil

    /// Which iCloud folder each profile here syncs with (see `cloudProfileID`), by profile id.
    private static let linksKey = "cloudProfileLinks"

    /// Looks for the iCloud container (a slow call, done off the main thread) until it is found:
    /// iCloud Drive switched on later is noticed at the next sync.
    func checkAvailability() async {
        _ = NetworkStatus.shared   // starts watching the connection early (the first answer takes a moment)
        guard containerURL == nil else { return }
        let url = await Task.detached(priority: .utility) { () -> URL? in
            guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
            return FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        containerURL = url
        isAvailable = url != nil
        // Offloaded files come back from each profile's iCloud folder, known from the last sync
        // (Offloading.swift) — so they can be opened before the first sync of this launch is done.
        if let url {
            let links = CloudSync.links()
            for profile in AppServices.shared.profiles.profiles {
                OffloadIndex.shared.setCloud(CloudSync.remoteLocation(container: url, profileID: links[profile.id] ?? profile.id),
                                             for: ProfileManager.location(for: profile.id))
            }
        }
        // Found only now (iCloud Drive switched on while the app ran): the settings travel too.
        if url != nil { SettingsSync.shared.follow(AppSettings.shared, iCloudAvailable: true) }
    }

    var explanation: String {
        if isAvailable { return "This profile's library is kept in this app's iCloud Drive folder and merged with your other devices, and its settings follow along. It syncs with the profile of the same name on your other devices. Each profile decides for itself: one with sync off stays on this device only. Columns, Offline mode, the originals folder, the Hidden lock and API keys stay on this device." }
        return "iCloud isn't available. Check that this device is signed in to iCloud with iCloud Drive on, and that PinBoard is allowed to use it (Settings › your name › iCloud › iCloud Drive)."
    }

    /// Settings' "Stop": the running sync ends at its next step (what came stays; the rest comes
    /// at the next sync).
    func stopSoon() {
        guard isSyncing else { return }
        stopRequested = true
        mergeTask?.cancel()
        SyncLog.add("Stop tapped")
    }

    /// Another profile is about to be opened (ProfileManager.select). The sync running for the old
    /// one stops at its next step and its result is dropped (it never writes into the new library:
    /// see `isCurrentProfile`); the old one's quiet download stops too; nothing it said stays on
    /// screen. The library is saved by the switch itself. The new profile syncs on its own.
    func profileWillChange() {
        cancelPending()
        filesTask?.cancel()
        filesStatus = nil
        lastError = nil
        if isSyncing {
            stopRequested = true
            mergeTask?.cancel()
            SyncLog.add("Another profile was chosen: this sync stops")
        }
    }

    /// A sync ended early, or couldn't start (`stop`), or ended with pins still to come (nil):
    /// says why in Settings and plans the next try (`SyncRetry`): when the connection is back,
    /// after a pause, or not at all.
    private func planRetry(after stop: SyncStop?, store: LibraryStore, settings: AppSettings) {
        if stop == .iCloudQuiet { quietRuns += 1 } else if stop == nil { quietRuns = 0 }
        let retry = SyncRetry.after(stop, quietRuns: quietRuns)
        if let stop { lastError = stop.message(retryMinutes: retry.minutes) }
        switch retry {
        case .none:
            break
        case .whenOnline:
            if !waitingForConnection {   // (once, not at every save while offline)
                SyncLog.add(stop == .offline ? "Offline: syncs again when the connection is back" : "iCloud isn't available: syncs again later")
            }
            waitForConnection()
        case .after(let seconds):
            SyncLog.add("Pins still to come: trying again in \(Int(seconds / 60)) minute\(seconds == 60 ? "" : "s")")
            syncSoon(store: store, settings: settings, delay: seconds)
        }
    }

    /// The next sync starts when the device is back online (once).
    private func waitForConnection() {
        waitingForConnection = true
        guard onlineObserver == nil else { return }
        onlineObserver = NotificationCenter.default.addObserver(forName: NetworkStatus.backOnline, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppServices.shared.cloudSync.connectionIsBack() }
        }
    }

    private func connectionIsBack() {
        guard waitingForConnection else { return }
        waitingForConnection = false
        lastError = nil
        SyncLog.add("Back online: syncing again")
        syncSoon(store: AppServices.shared.store, settings: AppSettings.shared, delay: 3)   // the profile in use now
    }

    /// Pull to refresh on a grid: a sync at once (the usual one, with the quick "nothing changed"
    /// look first; no waiting like after a save). Nothing when this profile doesn't sync, Offline
    /// mode is on, iCloud isn't there, or a sync is already running. The pull doesn't wait for it:
    /// the sync shows in its usual pill.
    func syncFromPull(store: LibraryStore, settings: AppSettings) {
        guard settings.iCloudSync, !settings.offlineMode, isAvailable, !isSyncing else { return }
        SyncLog.add("Sync started by pull to refresh")
        pendingTask?.cancel()   // (one waiting for a timer would only repeat it)
        pendingTask = nil
        Task { @MainActor [weak self] in
            await self?.syncNow(store: store, settings: settings)
        }
    }

    /// A sync waiting to start is called off (another profile is chosen: whether it syncs is its own setting).
    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// Runs a sync soon (debounced), if the setting is on and iCloud is there.
    func syncSoon(store: LibraryStore, settings: AppSettings, delay: Double = 20) {
        guard settings.iCloudSync, !settings.offlineMode else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self, weak store] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let store else { return }
            await self.syncNow(store: store, settings: settings)
        }
    }

    /// Pulls the other devices' copy, merges, pushes the result. The sync belongs to the profile it
    /// started in: if another profile is in use by the time the merge is done, its result is
    /// dropped here (it is that library's; its iCloud copy was already written) and the library now
    /// in use is synced soon after instead.
    /// `full`: skip the quick "nothing changed" look ("Sync now" in Settings always does it all).
    func syncNow(store: LibraryStore, settings: AppSettings, full: Bool = false) async {
        await checkAvailability()
        guard settings.iCloudSync, !settings.offlineMode, let container = containerURL, !isSyncing else { return }
        let profile = store.profileID
        // No connection, or signed out of iCloud: no sync that could only wait. It starts again
        // when the connection is back (or at the next save or launch).
        if NetworkStatus.shared.isOffline {
            planRetry(after: .offline, store: store, settings: settings)
            return
        }
        if FileManager.default.ubiquityIdentityToken == nil {
            planRetry(after: .noICloud, store: store, settings: settings)
            return
        }
        waitingForConnection = false
        isSyncing = true
        syncingProfile = profile
        stopRequested = false
        arrivalsStop = nil
        store.syncStatus = "Syncing with iCloud…"
        store.syncRunning = true   // other work of this library waits; switching profiles doesn't (it stops the sync)
        let extraTime = ExtraBackgroundTime()
        extraTime.begin("iCloud sync")   // leaving the app mid-sync: the round that is running ends cleanly
        let began = Date()
        ownChanges = 0
        defer {
            SyncLog.add("Sync ended after \(CloudSync.took(began))")
            extraTime.end()
            stopRequested = false
            isSyncing = false
            syncingProfile = nil
            mergeTask = nil
            stopWatchingFolderIfIdle()   // (the quiet download after it may still use it)
            if store.isCurrentProfile(profile) {
                store.syncStatus = nil
                store.syncRunning = false
            } else if settings.iCloudSync {
                // Another profile was opened during this sync: it syncs now (its own try was turned
                // away while this one wound down).
                syncSoon(store: store, settings: settings, delay: 2)
            }
        }
        let profiles = AppServices.shared.profiles.profiles
        let here = profiles.first { $0.id == profile } ?? Profile(id: profile, name: "My library")
        var links = CloudSync.links()
        // The iCloud folders the other profiles here use (theirs by link or by their own id).
        let takenElsewhere = Set(profiles.filter { $0.id != profile }.flatMap { [$0.id, links[$0.id]].compactMap { $0 } })
        let linked = links[profile]
        let local = store.location
        let localDocument = store.document
        let versionAtStart = store.contentVersion
        watchForChanges(store: store, settings: settings)
        // Nothing changed on either side since the last full sync: done in about a second.
        if !full, let linked, await nothingChanged(store: store, document: localDocument, container: container, cloudID: linked, began: began) {
            lastError = nil
            store.lastSyncAt = Date()
            syncedVersion[profile] = store.contentVersion
            bringFullFilesQuietly(store: store, settings: settings)
            return
        }
        SyncLog.add("Sync began (library here: \(store.pins.count.formatted()) pins)")
        if !listedThisLaunch.contains(profile) {
            // A new device learns of iCloud's lists of profiles and libraries first (a few small files).
            await refreshCloudListing(names: ["profiles.json", "library.json"])
        }
        let finding = Date()
        let found = await Task.detached(priority: .utility) { () -> Result<UUID, Error> in
            do {
                return .success(try await CloudSync.cloudProfileID(for: here, linked: linked,
                                                                   takenElsewhere: takenElsewhere, container: container))
            } catch {
                return .failure(error)
            }
        }.value
        let outcome: Result<(MergeResult, UUID), Error>
        switch found {
        case .failure(let error):
            outcome = .failure(error)
        case .success(let cloudID):
            SyncLog.add("Found this profile's iCloud folder: \(CloudSync.took(finding))")
            let remote = CloudSync.remoteLocation(container: container, profileID: cloudID)
            await Task.detached(priority: .utility) { remote.createFolders() }.value
            // iCloud tells this sync about this profile's folder only: the listing (once per
            // launch) and every finished download, which wakes the waits (CloudWaiting.swift).
            await watchFolder(remote, list: !listedThisLaunch.contains(profile), store: store)
            listedThisLaunch.insert(profile)
            let merging = Task.detached(priority: .utility) { () -> Result<(MergeResult, UUID), Error> in
                do {
                    let merged = try await CloudSync.merge(localDocument: localDocument, local: local, remote: remote)
                    return .success((merged, cloudID))
                } catch {
                    return .failure(error)
                }
            }
            mergeTask = merging
            if stopRequested { merging.cancel() }   // (chosen while the folder was being listed)
            outcome = await merging.value
        }
        guard store.isCurrentProfile(profile) else {
            // Another profile now: this merge is about the other library (merged into this one it
            // would bring that library's pins and boards here). The pictures it staged in that
            // library's folders are thrown away. That one is synced next.
            if case .success(let (result, _)) = outcome { CloudSync.discard(result.pictures) }
            SyncLog.add("Another profile was opened: this sync's result is dropped")
            syncSoon(store: store, settings: settings, delay: 5)
            return
        }
        switch outcome {
        case .success(let (result, cloudID)):
            lastError = nil
            links[profile] = cloudID
            CloudSync.saveLinks(links)
            SettingsSync.shared.follow(settings, iCloudAvailable: true)   // its iCloud folder is known now: its settings travel too
            let remote = CloudSync.remoteLocation(container: container, profileID: cloudID)
            OffloadIndex.shared.setCloud(remote, for: local)
            let before = store.contentVersion
            CloudSync.apply(result, to: store, profile: profile)
            ownChanges += store.contentVersion - before
            store.lastSyncAt = Date()
            // The pins new here (and pictures missing here) come after, thumbnails first (CloudArrivals.swift).
            SyncLog.add("Merged: \(result.libraryTotal.formatted()) pins in all, \(result.arriving.count.formatted()) to come from iCloud, \(result.sent.formatted()) sent")
            var unfinished = false
            if !result.arriving.isEmpty {
                let arrivals = Date()
                unfinished = await bringArrivals(result.arriving, from: remote, store: store, settings: settings,
                                                 profile: profile, libraryTotal: result.libraryTotal)
                SyncLog.add("Pins and thumbnails from iCloud: \(CloudSync.took(arrivals))")
                if unfinished { listedThisLaunch.remove(profile) }   // (list again next time: some weren't in iCloud yet)
            }
            // This device's copies in the iCloud folder go once iCloud has them (the library holds
            // its own). In the background, not holding the pill; only when this device sent files.
            if result.sent > 0 || !unfinished {
                Task.detached(priority: .background) {
                    let notSent = CloudSync.evictUploadedCopies(in: remote)
                    if notSent > 0 { SyncLog.add("\(notSent.formatted()) files from this device are still being sent to iCloud") }
                }
            }
            // Another profile chosen meanwhile: the rest is up to its own settings (its own sync).
            guard store.isCurrentProfile(profile) else { return }
            // Pins still to come: another try — when the connection is back, in two minutes, or
            // later and later while iCloud sends nothing (not after Stop).
            if unfinished {
                planRetry(after: arrivalsStop ?? (stopRequested ? .stopTapped : nil), store: store, settings: settings)
            } else {
                quietRuns = 0
            }
            // "Optimize device storage": full files not used for 30 days live in iCloud only (Offloading.swift).
            await store.offloadIfWanted(settings: settings)
            guard store.isCurrentProfile(profile) else { return }
            await finishSync(store: store, settings: settings, profile: profile, remote: remote,
                             changedMeanwhile: store.contentVersion - versionAtStart > ownChanges, unfinished: unfinished)
        case .failure(let error):
            SyncLog.add("Sync failed: \(error.localizedDescription)")
            if NetworkStatus.shared.isOffline {
                planRetry(after: .offline, store: store, settings: settings)   // again when the connection is back
            } else if stopRequested {
                lastError = nil   // (Stop: no retry, no error)
            } else {
                lastError = error.localizedDescription
                syncSoon(store: store, settings: settings, delay: 120)   // tried again in a while
            }
        }
    }

    /// The quick look before a full sync: has iCloud's library file or this library changed since
    /// the last full sync (see `SyncStamp`)? false: a full sync is needed.
    private func nothingChanged(store: LibraryStore, document: LibraryDocument, container: URL, cloudID: UUID, began: Date) async -> Bool {
        guard let saved = CloudSync.savedStamp(for: store.profileID) else { return false }
        let file = CloudSync.remoteLocation(container: container, profileID: cloudID).library
        guard CloudSync.remoteStamp(of: file) == saved.remote else { return false }
        let localNow = await Task.detached(priority: .userInitiated) { CloudSync.localStamp(document) }.value
        guard localNow == saved.local, store.isCurrentProfile(store.profileID) else { return false }
        SyncLog.add("Nothing changed on either side (checked in \(CloudSync.took(began)))")
        return true
    }

    /// The end of a full sync: changes made here meanwhile go out in a moment; otherwise the
    /// marker for the next quick look is kept (only when nothing is left to come). Then the full
    /// files come quietly.
    private func finishSync(store: LibraryStore, settings: AppSettings, profile: UUID, remote: LibraryLocation,
                            changedMeanwhile: Bool, unfinished: Bool) async {
        if changedMeanwhile {
            syncSoon(store: store, settings: settings, delay: 5)   // push what changed during the sync
            CloudSync.saveStamp(nil, for: profile)
        } else {
            syncedVersion[profile] = store.contentVersion   // saving what the sync brought starts no new sync
            if unfinished {
                CloudSync.saveStamp(nil, for: profile)
            } else {
                let document = store.document
                let localNow = await Task.detached(priority: .utility) { CloudSync.localStamp(document) }.value
                let remoteNow = CloudSync.remoteStamp(of: remote.library)
                let stamp = remoteNow.map { (text: String) -> SyncStamp in SyncStamp(local: localNow, remote: text) }
                if store.isCurrentProfile(profile) { CloudSync.saveStamp(stamp, for: profile) }
            }
        }
        bringFullFilesQuietly(store: store, settings: settings)
    }

    /// The iCloud folder a profile here synced with last (nil: it never synced).
    static func cloudFolder(of profile: UUID) -> UUID? { links()[profile] }

    /// A deleted profile's link goes.
    static func forgetLink(of profile: UUID) {
        var all = links()
        all[profile] = nil
        saveLinks(all)
    }

    /// Which iCloud folder each profile here synced with last.
    private static func links() -> [UUID: UUID] {
        let stored = UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String] ?? [:]
        var links: [UUID: UUID] = [:]
        for (key, value) in stored {
            if let profile = UUID(uuidString: key), let cloud = UUID(uuidString: value) { links[profile] = cloud }
        }
        return links
    }

    private static func saveLinks(_ links: [UUID: UUID]) {
        let stored = Dictionary(uniqueKeysWithValues: links.map { ($0.key.uuidString, $0.value.uuidString) })
        UserDefaults.standard.set(stored, forKey: linksKey)
    }

    nonisolated static func remoteLocation(container: URL, profileID: UUID) -> LibraryLocation {
        LibraryLocation(root: container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("PinBoard", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true))
    }

    /// What a merge brings back for this device.
    struct MergeResult: Sendable {
        var document: LibraryDocument? = nil    // the merged library, when it differs from ours (or pictures came)
        var pictures: [StagedPicture] = []      // iCloud's newer pictures, staged for this device
        var forICloud: LibraryDocument? = nil   // the merged library for iCloud, when it differs from what is there
        /// Pins whose files come from iCloud after the merge (`bringArrivals`): ones new here (left
        /// out of `document` until their files are here) and ones here whose picture or video is missing.
        var arriving: [Pin] = []
        /// How many pins the merged library has (not counting Recently Deleted): the sync's "of 2,500".
        var libraryTotal = 0
        /// How many of this device's pins had their files copied to iCloud in this merge.
        var sent = 0
    }

    /// Reads the remote library (waiting for iCloud to download it), merges it with ours and
    /// copies files both ways (`mergeLibraries`), then writes the merged library to iCloud when it
    /// differs from what is there. If that write fails, the sync stops: the pictures it staged
    /// here are thrown away.
    nonisolated private static func merge(localDocument: LibraryDocument, local: LibraryLocation, remote: LibraryLocation) async throws -> MergeResult {
        var clock = Date()
        let remoteDocument = try await readRemoteDocument(at: remote.library)
        SyncLog.add("Read iCloud's library (\((remoteDocument?.pins.count ?? 0).formatted()) pins): \(took(clock))")
        clock = Date()
        let result = await mergeLibraries(localDocument: localDocument, remoteDocument: remoteDocument,
                                          local: local, remote: remote)
        SyncLog.add("Compared the libraries and sent new files: \(took(clock))")
        if let forICloud = result.forICloud, let data = LibraryStore.encodeDocument(forICloud) {
            clock = Date()
            do {
                try coordinatedWrite(data, to: remote.library)
            } catch {
                discard(result.pictures)
                throw error
            }
            SyncLog.add("Wrote the merged library to iCloud: \(took(clock))")
        }
        // Files of pins erased for good (on any device) that are still in iCloud go now, in the
        // background (CloudErase.swift).
        removeErasedFiles(local: localDocument, remote: remoteDocument, in: remote)
        return result
    }

    /// A sync's work between reading iCloud's library and writing the merged one there: merges the
    /// two libraries, copies new pins' files both ways and carries changed pictures across
    /// (`carryChangedPictures`: iCloud's newer ones are only staged here). Returns what this device
    /// takes and what iCloud gets (see `MergeResult`).
    nonisolated static func mergeLibraries(localDocument: LibraryDocument, remoteDocument: LibraryDocument?,
                                           local: LibraryLocation, remote: LibraryLocation,
                                           patience: Double = 60) async -> MergeResult {
        let merged = mergeDocuments(local: localDocument, remote: remoteDocument)

        // Files: this device's new pins go to iCloud now; iCloud's come here afterwards, in
        // batches (`MergeResult.arriving`), as do pictures and videos missing here.
        let remotePins = Set((remoteDocument?.pins ?? []).map { $0.id })
        let localPins = Set(localDocument.pins.map { $0.id })
        var arriving: [Pin] = []
        var newHere: Set<UUID> = []
        var sent = 0
        for pin in merged.pins where !pin.isDeleted {
            if !localPins.contains(pin.id) {
                arriving.append(pin)
                newHere.insert(pin.id)
            } else if !remotePins.contains(pin.id) {
                copyFiles(of: pin, from: local, to: remote)
                sent += 1
            } else if missesFiles(pin, in: local), !OffloadIndex.shared.isOffloaded(pin.id, in: local) {
                arriving.append(pin)
            }
        }
        // Pictures changed on one side (turned, cropped…) go to the other side too.
        let sides = await carryChangedPictures(merged: merged, local: localDocument, remote: remoteDocument,
                                               localFiles: local, remoteFiles: remote, patience: patience)

        // The merged library goes to iCloud when it differs from what is there, and back to us
        // if anything changed (or a picture waits to be put in place).
        var result = MergeResult(pictures: sides.staged, arriving: arriving,
                                 libraryTotal: sides.local.pins.filter { (pin: Pin) -> Bool in !pin.isDeleted }.count,
                                 sent: sent)
        let remoteIsCurrent = remoteDocument.map { (document: LibraryDocument) -> Bool in sameContent(sides.remote, document) } ?? false
        if !remoteIsCurrent { result.forICloud = sides.remote }
        var forHere = sides.local
        forHere.pins.removeAll { (pin: Pin) -> Bool in newHere.contains(pin.id) }
        let changed = !sides.staged.isEmpty || !sameContent(forHere, localDocument)
        if remoteDocument != nil && changed { result.document = forHere }
        return result
    }

    /// Hands a merge's result to the store (on the main actor, once the background work is done).
    /// The sync can take a while; anything done here meanwhile must win over the snapshot it
    /// started from, so the result is merged once more with the library as it is now: a picture
    /// turned or cropped here meanwhile has the higher revision and stays (the one the sync brought
    /// for that pin is thrown away, see `LibraryStore.applySynced`).
    static func apply(_ result: MergeResult, to store: LibraryStore, profile: UUID) {
        guard let merged = result.document else {
            discard(result.pictures)
            return
        }
        let fresh = mergeDocuments(local: store.document, remote: merged)
        if !result.pictures.isEmpty || !sameContent(fresh, store.document) {
            store.applySynced(fresh, profile: profile, pictures: result.pictures)
        }
    }

    // MARK: Changed pictures

    /// The merged library as each side keeps it (see `carryChangedPictures`).
    struct MergedSides: Sendable {
        var local: LibraryDocument    // what this device keeps (its own picture's details wherever iCloud's newer one isn't in place yet)
        var remote: LibraryDocument   // what goes to iCloud (iCloud's own picture's details wherever this device's couldn't be sent)
        var staged: [StagedPicture] = []   // iCloud's newer pictures, waiting next to this device's files
    }

    /// One picture to carry across: a pin both sides have whose `pictureRevision` differs. It goes
    /// from the side with the higher revision (the newer picture) to the other side.
    struct PictureUpdate: Sendable, Equatable {
        var pinID: UUID
        var toLocal: Bool   // true: iCloud's picture comes to this device; false: this device's goes to iCloud
        /// The newer record has no picture any more (a link whose preview was dropped): the other
        /// side's preview files go, and nothing is copied.
        var dropsPicture: Bool = false
    }

    /// A picture a sync brought for this device. It waits next to the pin's files under passing
    /// names (`LibraryStore.syncIncoming`) until the store puts it in place on the main actor
    /// (`LibraryStore.applySynced`) — only if this device's picture of that pin is still the one
    /// the sync saw (`seenRevision`); otherwise it is thrown away (`discard`).
    struct StagedPicture: Sendable {
        var picture: Pin              // the merged record: the new picture's details are taken from it
        var seenRevision: Int         // this device's picture revision when the sync read the library
        var image: URL? = nil         // the new picture (nil: the newer record has none — this device's preview files go)
        var thumbnail: URL? = nil     // its thumbnail, when it came
        var fingerprint: URL? = nil   // its fingerprint, when it came
        /// The staged files (whatever isn't put in place is thrown away).
        var files: [URL] { [image, thumbnail, fingerprint].compactMap { (file: URL?) -> URL? in file } }
    }

    /// Pins both sides have whose picture differs (another `pictureRevision`: turned, cropped, a
    /// link preview fetched again or dropped, a new video poster — on one device). Copies go only
    /// toward the higher revision: the side with the older picture gets the newer one, whichever
    /// record won the merge otherwise (see `mergedPin`). When the newer record has no picture (a
    /// link pointed at another page without a preview) and the other side still has one, that
    /// side's preview files go instead. Pins new to one side (see `copyFiles`) and pins without a
    /// picture on either side are left out. (Pins in Recently Deleted are included: their files
    /// stay until they are erased, and a restored pin must show the picture its record describes.)
    nonisolated static func pictureUpdates(local: LibraryDocument, remote: LibraryDocument) -> [PictureUpdate] {
        let there = Dictionary(remote.pins.map { (pin: Pin) -> (UUID, Pin) in (pin.id, pin) },
                               uniquingKeysWith: { (first: Pin, _: Pin) -> Pin in first })
        var updates: [PictureUpdate] = []
        var done: Set<UUID> = []
        for mine in local.pins where !done.contains(mine.id) {
            done.insert(mine.id)
            guard let theirs = there[mine.id], theirs.pictureRevision != mine.pictureRevision else { continue }
            let toLocal = theirs.pictureRevision > mine.pictureRevision
            let newer = toLocal ? theirs : mine
            let older = toLocal ? mine : theirs
            if newer.hasImageFile {
                updates.append(PictureUpdate(pinID: mine.id, toLocal: toLocal))
            } else if older.hasImageFile {
                updates.append(PictureUpdate(pinID: mine.id, toLocal: toLocal, dropsPicture: true))
            }
        }
        return updates
    }

    /// Carries the changed pictures across (`pictureUpdates`). This device's newer pictures go to
    /// iCloud straight away (`sendPicture`; a link preview dropped here is removed there). iCloud's
    /// newer pictures are only staged here (`stagePictures`): the store puts them in place later,
    /// if nothing changed them here meanwhile (see `StagedPicture`). Until a picture is in place,
    /// the side without it keeps describing its own picture (`withPictures`: its revision stays
    /// lower, so the next sync tries again) — everything else of the merged record (a new title, a
    /// hide…) reaches it all the same.
    nonisolated static func carryChangedPictures(merged: LibraryDocument, local: LibraryDocument, remote: LibraryDocument?,
                                                 localFiles: LibraryLocation, remoteFiles: LibraryLocation,
                                                 patience: Double = 60) async -> MergedSides {
        guard let remote else { return MergedSides(local: merged, remote: merged) }
        let updates = pictureUpdates(local: local, remote: remote)
        guard !updates.isEmpty else { return MergedSides(local: merged, remote: merged) }
        let winners = Dictionary(merged.pins.map { (pin: Pin) -> (UUID, Pin) in (pin.id, pin) },
                                 uniquingKeysWith: { (first: Pin, _: Pin) -> Pin in first })
        // To iCloud: nothing to wait for.
        var notSent: Set<UUID> = []
        for update in updates where !update.toLocal {
            guard let pin = winners[update.pinID] else { continue }
            if update.dropsPicture {
                removePictureFiles(of: pin, in: remoteFiles)
            } else if !sendPicture(of: pin, from: localFiles, to: remoteFiles) {
                notSent.insert(pin.id)
            }
        }
        // From iCloud: only staged here.
        let incoming: [PictureUpdate] = updates.filter { (update: PictureUpdate) -> Bool in update.toLocal }
        let seen = Dictionary(local.pins.map { (pin: Pin) -> (UUID, Int) in (pin.id, pin.pictureRevision) },
                              uniquingKeysWith: { (first: Int, _: Int) -> Int in first })
        let staged = await stagePictures(incoming, winners: winners, seen: seen,
                                         localFiles: localFiles, remoteFiles: remoteFiles, patience: patience)
        let waiting = Set(incoming.map { (update: PictureUpdate) -> UUID in update.pinID })
        return MergedSides(local: withPictures(of: waiting, from: local, in: merged),
                           remote: withPictures(of: notSent, from: remote, in: merged),
                           staged: staged)
    }

    /// Stages iCloud's newer pictures for this device (`stagePicture`). All downloads are asked for
    /// at once, and up to six pictures are waited for side by side (one slow picture doesn't hold
    /// up the others). A picture is waited for up to `patience` seconds (a minute); once one doesn't
    /// come, the ones not started yet are not waited for (only taken when already there): the next
    /// sync tries them again. A dropped link preview needs no files: it is staged as "no picture".
    nonisolated private static func stagePictures(_ updates: [PictureUpdate], winners: [UUID: Pin], seen: [UUID: Int],
                                                  localFiles: LibraryLocation, remoteFiles: LibraryLocation,
                                                  patience: Double) async -> [StagedPicture] {
        for update in updates where !update.dropsPicture {
            if let pin = winners[update.pinID] { startDownloads(of: pin, in: remoteFiles) }
        }
        let jobs: [(update: PictureUpdate, pin: Pin, revision: Int)] = updates.compactMap { (update: PictureUpdate) in
            guard let pin = winners[update.pinID], let revision = seen[update.pinID] else { return nil }
            return (update, pin, revision)
        }
        let gaveUp = OSAllocatedUnfairLock(initialState: false)
        let staged = await inParallel(jobs, limit: 6) { (job: (update: PictureUpdate, pin: Pin, revision: Int)) -> StagedPicture? in
            if job.update.dropsPicture { return StagedPicture(picture: job.pin, seenRevision: job.revision) }
            let wait = gaveUp.withLock { $0 } ? 0 : patience
            let picture = await stagePicture(of: job.pin, seenRevision: job.revision, from: remoteFiles,
                                             to: localFiles, waitSeconds: wait)
            if picture == nil { gaveUp.withLock { $0 = true } }
            return picture
        }
        return staged.compactMap { $0 }
    }

    /// Asks iCloud for a pin's picture files (the downloads go on by themselves).
    nonisolated private static func startDownloads(of pin: Pin, in location: LibraryLocation) {
        for file in pictureFiles(of: pin, in: location) where isKnownToICloud(file) { startDownload(file) }
    }

    /// Copies iCloud's copy (`source`) of a pin's picture — the picture, and its thumbnail and
    /// fingerprint when they are there — next to `destination`'s files, under passing names
    /// (`LibraryStore.syncIncoming`); nothing of `destination` is replaced here. Nothing is staged
    /// unless the picture has come: it must be downloaded (waited for up to `waitSeconds`) and be
    /// the one the record describes (the same size in pixels, when that can be read: an old copy
    /// iCloud hasn't replaced yet is usually another size, say before a crop or a quarter turn).
    /// nil: it didn't come, or couldn't be copied (nothing is left behind).
    nonisolated static func stagePicture(of pin: Pin, seenRevision: Int, from source: LibraryLocation,
                                         to destination: LibraryLocation, waitSeconds: Double) async -> StagedPicture? {
        let image = source.images.appendingPathComponent(pin.imageFileName)
        let thumb = source.thumbs.appendingPathComponent(pin.thumbFileName)
        let print = source.prints.appendingPathComponent(pin.printFileName)
        if waitSeconds > 0 { await waitForDownload(image, timeout: waitSeconds) }
        guard isDownloaded(image), pictureMatches(pin, at: image),
              let stagedImage = stageCopy(of: image, for: destination.images.appendingPathComponent(pin.imageFileName)) else {
            return nil
        }
        var staged = StagedPicture(picture: pin, seenRevision: seenRevision, image: stagedImage)
        if waitSeconds > 0 {
            // The thumbnail and the fingerprint are waited for side by side.
            let extras = pin.hasFeaturePrint ? [thumb, print] : [thumb]
            let limit = min(10, waitSeconds)
            _ = await inParallel(extras, limit: 2) { (file: URL) -> Bool in await waitForDownload(file, timeout: limit) }
        }
        if isDownloaded(thumb) {
            staged.thumbnail = stageCopy(of: thumb, for: destination.thumbs.appendingPathComponent(pin.thumbFileName))
        }
        if pin.hasFeaturePrint, isDownloaded(print) {
            staged.fingerprint = stageCopy(of: print, for: destination.prints.appendingPathComponent(pin.printFileName))
        }
        return staged
    }

    /// Copies `file` next to `target` under the passing name a sync uses (`LibraryStore.syncIncoming`).
    /// nil: the copy failed (nothing is left behind).
    nonisolated private static func stageCopy(of file: URL, for target: URL) -> URL? {
        let staged = LibraryStore.syncIncoming(target)
        try? FileManager.default.removeItem(at: staged)
        guard (try? FileManager.default.copyItem(at: file, to: staged)) != nil else {
            try? FileManager.default.removeItem(at: staged)
            return nil
        }
        return staged
    }

    /// Replaces iCloud's copy (`destination`) of a pin's picture with this device's (`source`):
    /// the picture, its thumbnail and its fingerprint. Each file is copied under a passing name
    /// next to the old one and then put in its place in one step (`copyIntoPlace`), so a copy that
    /// fails leaves the old file as it was. A thumbnail or fingerprint this device doesn't have
    /// (yet) is not left over from the old picture: without a thumbnail the picture itself is
    /// shown, and a device that gets no fingerprint makes its own (see `LibraryStore.applySynced`).
    /// false: the picture isn't here or couldn't be copied (then iCloud's files are left as they were).
    nonisolated static func sendPicture(of pin: Pin, from source: LibraryLocation, to destination: LibraryLocation) -> Bool {
        let image = source.images.appendingPathComponent(pin.imageFileName)
        guard FileManager.default.fileExists(atPath: image.path),
              copyIntoPlace(image, destination.images.appendingPathComponent(pin.imageFileName)) else { return false }
        let thumb = source.thumbs.appendingPathComponent(pin.thumbFileName)
        let oldThumb = destination.thumbs.appendingPathComponent(pin.thumbFileName)
        if !(FileManager.default.fileExists(atPath: thumb.path) && copyIntoPlace(thumb, oldThumb)) {
            try? FileManager.default.removeItem(at: oldThumb)
        }
        let print = source.prints.appendingPathComponent(pin.printFileName)
        let oldPrint = destination.prints.appendingPathComponent(pin.printFileName)
        if !(pin.hasFeaturePrint && FileManager.default.fileExists(atPath: print.path) && copyIntoPlace(print, oldPrint)) {
            try? FileManager.default.removeItem(at: oldPrint)   // (a fingerprint of the old picture)
        }
        return true
    }

    /// A pin's picture, thumbnail and fingerprint in `location`.
    nonisolated static func pictureFiles(of pin: Pin, in location: LibraryLocation) -> [URL] {
        [location.images.appendingPathComponent(pin.imageFileName),
         location.thumbs.appendingPathComponent(pin.thumbFileName),
         location.prints.appendingPathComponent(pin.printFileName)]
    }

    /// Removes a pin's picture, thumbnail and fingerprint from `location`: a link preview the newer
    /// record no longer has. Nothing else of the pin is touched.
    nonisolated static func removePictureFiles(of pin: Pin, in location: LibraryLocation) {
        for file in pictureFiles(of: pin, in: location) { try? FileManager.default.removeItem(at: file) }
    }

    /// Throws away staged pictures that are not put in place (see `StagedPicture`).
    nonisolated static func discard(_ pictures: [StagedPicture]) {
        for picture in pictures {
            for file in picture.files { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Copies `file` over `target`: under a passing name next to it first, then in its place in one
    /// step (see `LibraryStore.incoming`, `LibraryStore.moveIntoPlace`). false: the copy failed,
    /// and `target` is left as it was.
    nonisolated private static func copyIntoPlace(_ file: URL, _ target: URL) -> Bool {
        let staged = LibraryStore.incoming(target)
        try? FileManager.default.removeItem(at: staged)
        guard (try? FileManager.default.copyItem(at: file, to: staged)) != nil,
              LibraryStore.moveIntoPlace(staged, target) else {
            try? FileManager.default.removeItem(at: staged)
            return false
        }
        return true
    }

    /// The file is here, and it is iCloud's latest copy (a file outside iCloud always is).
    nonisolated private static func isDownloaded(_ url: URL) -> Bool { isFullyHere(url) }

    /// The file is here in full: iCloud's latest copy, downloaded (a file outside iCloud always is).
    /// The answer is read fresh each time, through a new URL: a URL keeps the answers it was given
    /// once, so asking the same URL again would say "not downloaded" for ever — every wait for a
    /// file from iCloud then ran until it gave up (the slow sync and Quick View of build 9).
    nonisolated static func isFullyHere(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let fresh = URL(fileURLWithPath: url.path)
        let status = (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        return status == nil || status == .current
    }

    /// Whether the picture file at `url` has the size `pin`'s record gives it (true when the size
    /// can't be read).
    nonisolated static func pictureMatches(_ pin: Pin, at url: URL) -> Bool {
        guard let size = ImageProcessor.pixelSize(ofImageAt: url) else { return true }
        return size.width == Int(pin.width.rounded()) && size.height == Int(pin.height.rounded())
    }

    /// `document` with the pins `ids` given what `source` has for their picture (see
    /// `Pin.takePictureDetails`): a side that hasn't got the newer picture (yet) keeps describing
    /// its own — its revision stays lower, so the next sync tries again. Everything else of the
    /// record (title, boards, hiding, its change date) stays as in `document`.
    nonisolated static func withPictures(of ids: Set<UUID>, from source: LibraryDocument, in document: LibraryDocument) -> LibraryDocument {
        guard !ids.isEmpty else { return document }
        let named: [Pin] = source.pins.filter { (pin: Pin) -> Bool in ids.contains(pin.id) }
        let own = Dictionary(named.map { (pin: Pin) -> (UUID, Pin) in (pin.id, pin) },
                             uniquingKeysWith: { (first: Pin, _: Pin) -> Pin in first })
        var result = document
        for index in result.pins.indices {
            guard let kept = own[result.pins[index].id] else { continue }
            result.pins[index].takePictureDetails(from: kept)
        }
        return result
    }

    /// iCloud's library (nil: there is none yet). One iCloud has but couldn't bring here stops
    /// the sync (see `readCloudFile`): writing ours in its place would drop the other devices' changes.
    nonisolated private static func readRemoteDocument(at url: URL) async throws -> LibraryDocument? {
        guard let data = try await readCloudFile(at: url) else { return nil }
        return LibraryStore.decodeDocument(data)
    }

    nonisolated static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError? = nil
        var writeError: Error? = nil
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// iCloud shows not-yet-downloaded files as ".name.icloud" placeholders.
    nonisolated static func isUbiquitousPlaceholder(_ url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    // (Waiting for a file from iCloud: `waitForDownload`, CloudWaiting.swift.)

    /// Copies a pin's files that `destination` (iCloud) doesn't have yet from `source` (this device).
    nonisolated private static func copyFiles(of pin: Pin, from source: LibraryLocation, to destination: LibraryLocation) {
        var pairs: [(URL, URL)] = []
        if pin.hasImageFile {
            pairs.append((source.images.appendingPathComponent(pin.imageFileName), destination.images.appendingPathComponent(pin.imageFileName)))
            pairs.append((source.thumbs.appendingPathComponent(pin.thumbFileName), destination.thumbs.appendingPathComponent(pin.thumbFileName)))
        }
        if pin.hasFeaturePrint {
            pairs.append((source.prints.appendingPathComponent(pin.printFileName), destination.prints.appendingPathComponent(pin.printFileName)))
        }
        pairs.append((source.exif.appendingPathComponent(pin.exifFileName), destination.exif.appendingPathComponent(pin.exifFileName)))
        if pin.isVideo {
            pairs.append((source.videos.appendingPathComponent(pin.videoFileName), destination.videos.appendingPathComponent(pin.videoFileName)))
        }
        for (from, to) in pairs {
            if FileManager.default.fileExists(atPath: to.path) || isUbiquitousPlaceholder(to) { continue }
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }

    /// Newest change wins, per pin / board / smart board — except a pin's picture details, which
    /// come from the side whose picture is newer (see `mergedPin`). An erase wins over a record only
    /// when the record was last changed at or before the erase: one changed after it (say
    /// re-imported from an export, with its old id) stays, and its tombstone goes. A board whose
    /// parent vanished in the merge keeps its side (see `keepSides(ofOrphanedBoardsIn:hiddenBefore:boardsBefore:)`).
    nonisolated static func mergeDocuments(local: LibraryDocument, remote: LibraryDocument?) -> LibraryDocument {
        guard let remote else { return local }
        var erased = local.erased
        for (id, date) in remote.erased { erased[id] = max(erased[id] ?? .distantPast, date) }
        let tombstones = erased

        /// `combine`: how a record both sides have is merged (nil: the newer one wins).
        func mergeList<T: Identifiable>(_ mine: [T], _ theirs: [T], updated: (T) -> Date,
                                        combine: ((T, T) -> T)? = nil) -> [T] where T.ID == UUID {
            /// Kept unless it was erased at or after its last change.
            func survives(_ item: T) -> Bool {
                guard let erasedAt = tombstones[item.id] else { return true }
                return erasedAt < updated(item)
            }
            var byID: [UUID: T] = [:]
            var order: [UUID] = []
            for item in mine where survives(item) {
                byID[item.id] = item
                order.append(item.id)
            }
            for item in theirs where survives(item) {
                if let existing = byID[item.id] {
                    if let combine {
                        byID[item.id] = combine(existing, item)
                    } else if updated(item) > updated(existing) {
                        byID[item.id] = item
                    }
                } else {
                    byID[item.id] = item
                    order.append(item.id)
                }
            }
            return order.compactMap { byID[$0] }
        }

        let pins = mergeList(local.pins, remote.pins, updated: { (pin: Pin) -> Date in pin.updatedAt },
                             combine: { (mine: Pin, theirs: Pin) -> Pin in CloudSync.mergedPin(mine, theirs) })
        var merged = LibraryDocument(pins: pins,
                                     boards: mergeList(local.boards, remote.boards, updated: { $0.updatedAt }),
                                     smartBoards: mergeList(local.smartBoards, remote.smartBoards, updated: { $0.updatedAt }),
                                     erased: erased)
        // A record that won over its tombstone is back: the tombstone goes.
        for pin in merged.pins { merged.erased[pin.id] = nil }
        for board in merged.boards { merged.erased[board.id] = nil }
        for board in merged.smartBoards { merged.erased[board.id] = nil }
        // Hidden before the merge, on either device (secret itself or inside a secret board).
        let hiddenBefore = LibraryStore.secretBoardIDs(in: local.boards).union(LibraryStore.secretBoardIDs(in: remote.boards))
        // The boards either device had before the merge (a parent among them vanished in this merge).
        let boardsBefore = Set(local.boards.map { $0.id }).union(remote.boards.map { $0.id })
        CloudSync.keepSides(ofOrphanedBoardsIn: &merged.boards, hiddenBefore: hiddenBefore, boardsBefore: boardsBefore)
        // Each device counts its own visits to a board's page: a board both sides know keeps the higher count.
        // The stamps and the cached palette change without touching updatedAt, so they are merged field by field.
        let localBoards = Dictionary(local.boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteBoards = Dictionary(remote.boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func later(_ a: Date?, _ b: Date?) -> Date? {
            guard let a else { return b }
            guard let b else { return a }
            return max(a, b)
        }
        for index in merged.boards.indices {
            let id = merged.boards[index].id
            if let mine = localBoards[id], let theirs = remoteBoards[id] {
                merged.boards[index].openCount = max(mine.openCount, theirs.openCount)
                merged.boards[index].lastEditedAt = later(mine.lastEditedAt, theirs.lastEditedAt)
                merged.boards[index].lastAddedAt = later(mine.lastAddedAt, theirs.lastAddedAt)
                // The newer palette wins; on a tie the choice must not depend on which side is "mine".
                let mineMade = mine.paletteMadeAt ?? .distantPast
                let theirsMade = theirs.paletteMadeAt ?? .distantPast
                let mineKey = (mine.paletteHex ?? []).joined()
                let theirsKey = (theirs.paletteHex ?? []).joined()
                let palette = (mineMade > theirsMade || (mineMade == theirsMade && mineKey >= theirsKey)) ? mine : theirs
                merged.boards[index].paletteHex = palette.paletteHex
                merged.boards[index].paletteMadeAt = palette.paletteMadeAt
            }
        }
        // A pin may point at a board that only the other device knew and has since erased. A pin
        // such a board kept hidden stays hidden (as when a hidden board is deleted on this device).
        let boardIDs = Set(merged.boards.map { $0.id })
        let gone = (local.boards + remote.boards).filter { !boardIDs.contains($0.id) }
        let secretBefore = LibraryStore.secretBoardIDs(in: merged.boards + gone)
        let secretNow = LibraryStore.secretBoardIDs(in: merged.boards)
        for index in merged.pins.indices where merged.pins[index].boardIDs.contains(where: { !boardIDs.contains($0) }) {
            var pin = merged.pins[index]
            let wasHidden = LibraryStore.isHidden(pin, secretBoards: secretBefore)
            pin.boardIDs.removeAll { !boardIDs.contains($0) }
            if wasHidden, !LibraryStore.isHidden(pin, secretBoards: secretNow) {
                LibraryStore.keepHidden(&pin, secretBoards: secretNow)
            }
            merged.pins[index] = pin
        }
        merged.pins.sort { $0.createdAt > $1.createdAt }
        return merged
    }

    /// One pin both devices have. The newer record wins (`updatedAt`), as for boards — but the
    /// picture's own details (`Pin.takePictureDetails`) come from the device whose picture is newer:
    /// the higher `pictureRevision`. So a picture cropped on one device is never undone because the
    /// other device, which still had the old picture, changed a tag before the two synced: the tag
    /// and the crop both stay, on every device. With equal revisions the newer record is taken
    /// whole, as before. (Ties in the date keep `mine`, as always.)
    nonisolated static func mergedPin(_ mine: Pin, _ theirs: Pin) -> Pin {
        var result = theirs.updatedAt > mine.updatedAt ? theirs : mine
        if theirs.pictureRevision != mine.pictureRevision {
            let newerPicture = theirs.pictureRevision > mine.pictureRevision ? theirs : mine
            result.takePictureDetails(from: newerPicture)
        }
        // An original kept in the originals folder (MediaStorage.swift) is known to the device
        // that kept it; the other device's record must not make the library forget it.
        if result.originalName == nil {
            let keeper = mine.originalName != nil ? mine : theirs
            result.originalName = keeper.originalName
            result.originalBytes = keeper.originalBytes
        }
        return result
    }

    /// A board whose parent vanished in this merge (say erased on one device while a sub-board was
    /// added inside it on the other) would point at nothing: it would show in no list, and — no
    /// longer inside its hidden parent — its pins would turn up on the normal side. It moves to the
    /// top level instead, on its own side: a board that was hidden before the merge (itself, or
    /// inside a hidden board: `hiddenBefore`) becomes a hidden board itself, so it and its pins stay
    /// hidden.
    /// Only a parent one of the devices had before the merge counts (`boardsBefore`: the boards of
    /// both sides). A board whose parent was already missing on both (an old orphan, left by an
    /// earlier version) is left as it is: whether that lost parent was hidden can't be known any
    /// more, and moving it up would list it among the normal boards — a leak if it sat in a hidden one.
    nonisolated static func keepSides(ofOrphanedBoardsIn boards: inout [Board], hiddenBefore: Set<UUID>, boardsBefore: Set<UUID>) {
        let present = Set(boards.map { $0.id })
        for index in boards.indices {
            guard let parentID = boards[index].parentID, !present.contains(parentID) else { continue }
            guard boardsBefore.contains(parentID) else { continue }   // an old orphan: left alone
            boards[index].parentID = nil
            if hiddenBefore.contains(boards[index].id) { boards[index].isSecret = true }
        }
    }

    nonisolated static func sameContent(_ a: LibraryDocument, _ b: LibraryDocument) -> Bool {
        guard a.pins.count == b.pins.count, a.boards.count == b.boards.count, a.smartBoards.count == b.smartBoards.count else { return false }
        // Pins compare their picture revision too: a merge can give a pin the other device's
        // picture without changing its date (see `mergedPin`).
        let aPins = Dictionary(a.pins.map { (pin: Pin) -> (UUID, Pin) in (pin.id, pin) },
                               uniquingKeysWith: { (first: Pin, _: Pin) -> Pin in first })
        for pin in b.pins {
            guard let other = aPins[pin.id],
                  other.updatedAt == pin.updatedAt,
                  other.pictureRevision == pin.pictureRevision else { return false }
        }
        // Boards also compare the fields merged one by one (stamps, open count, palette), which change
        // without touching updatedAt; the merge of them is stable, so this does not upload again and again.
        let aBoards = Dictionary(a.boards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for board in b.boards {
            guard let other = aBoards[board.id],
                  other.updatedAt == board.updatedAt,
                  other.lastEditedAt == board.lastEditedAt,
                  other.lastAddedAt == board.lastAddedAt,
                  other.openCount == board.openCount,
                  other.paletteMadeAt == board.paletteMadeAt,
                  other.paletteHex == board.paletteHex else { return false }
        }
        let aSmart = Dictionary(uniqueKeysWithValues: a.smartBoards.map { ($0.id, $0.updatedAt) })
        for board in b.smartBoards where aSmart[board.id] != board.updatedAt { return false }
        return true
    }
}

/// A little more time when the app leaves the screen in the middle of a job (iOS gives about half
/// a minute), so what came is saved and the job stops at a clean point. iCloud goes on bringing
/// the files that were asked for meanwhile; the job carries on when the app is back.
@MainActor
final class ExtraBackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin(_ name: String) {
        end()
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()   // the time is up: iOS wants it back now
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
