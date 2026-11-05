//
//  CloudArrivals.swift  —  PinBoard
//
//  Bringing iCloud's pins to this device quickly. After a sync's merge, the pins new here (and
//  pins here whose picture or video is missing) come through a rolling window: the small files of
//  up to 200 pins are asked for at once, a pin joins the library as soon as its thumbnail is here,
//  and each pin that arrives makes room for the next one — so one slow file never holds up the
//  others. The grid fills in every few seconds. A photo's or video's full file isn't waited for:
//  the pin is "in iCloud only" until the quiet download after the sync brings it (or it is
//  opened first; see CloudChanges.swift and Offloading.swift). Files a pin doesn't have are never waited
//  for. Each file copied into the library is let go from the iCloud folder on this device (it
//  stays in iCloud), so the device doesn't keep every file twice.
//

import Foundation

extension CloudSync {
    /// How many pins' files are asked for at once.
    nonisolated static let arrivalWindow = 200
    /// How often (seconds) the pins that arrived join the library and the count goes up.
    nonisolated static let arrivalRound: Double = 3
    /// A pin still waiting after this long (seconds) is set aside so the window can take others —
    /// longer for a video (one big file can take a while). Set-aside pins get one more try at the
    /// end of the run, then wait for the next sync.
    nonisolated static let pictureWait: Double = 90
    nonisolated static let videoWait: Double = 900
    /// The run stops when nothing at all has come for this long (iCloud isn't sending now); the
    /// next sync, two minutes later, carries on.
    nonisolated static let quietToStop: Double = 300

    /// Brings `pins`' files from iCloud (`remote`) into the library through the rolling window,
    /// adding each pin to the library once its files are here (see the top of this file). Stops
    /// when another profile is opened, sync is switched off, Stop is tapped, or iCloud sends
    /// nothing for five minutes; what is left comes next time (an interrupted run picks up there:
    /// pins already in the library are not asked for again, and files already copied in count as
    /// here at once). Every wait has an end: a pin that doesn't come is set aside (`pictureWait`,
    /// `videoWait`, or at once when iCloud reports an error for its file) so it never blocks the rest.
    /// The pill counts the whole library — "Syncing with iCloud… 2,100 of 2,500": the pins here out
    /// of `libraryTotal` — so it only ever counts up, also across syncs.
    /// Returns true when pins are still to come (the caller tries again in a while).
    func bringArrivals(_ pins: [Pin], from remote: LibraryLocation, store: LibraryStore,
                       settings: AppSettings, profile: UUID, libraryTotal: Int) async -> Bool {
        let local = store.location
        var stillToCome = Set(pins.map { (pin: Pin) -> UUID in pin.id }).subtracting(store.pins.map { $0.id })
        let overall = max(libraryTotal, stillToCome.count)
        var queue = pins
        var next = 0
        var window: [Wanted] = []
        var setAside: [Pin] = []
        var secondTry = false
        var notInICloud = 0
        var lastArrival = Date()
        var lastLog = Date.distantPast
        while true {
            let stepStart = Date()
            guard store.isCurrentProfile(profile), settings.iCloudSync, !settings.offlineMode else {
                SyncLog.add("Arrivals stopped: profile changed, sync off or Offline mode")
                return true
            }
            if stopRequested { return true }
            let here = overall - stillToCome.count
            var status = "Syncing with iCloud… \(here.formatted()) of \(overall.formatted())"
            if Date().timeIntervalSince(lastArrival) > 30 { status += " · waiting for iCloud" }
            store.syncStatus = status
            // Room in the window: the next pins' files are asked for.
            if window.count < CloudSync.arrivalWindow && next < queue.count {
                let end = min(next + CloudSync.arrivalWindow - window.count, queue.count)
                let more = Array(queue[next..<end])
                next = end
                let asked = await Task.detached(priority: .utility) {
                    CloudSync.askForFiles(of: more, from: remote, to: local)
                }.value
                notInICloud += more.count - asked.count
                window.append(contentsOf: asked)
            }
            if window.isEmpty && next >= queue.count {
                // The queue is done: the set-aside pins get one more try, then the run ends.
                if secondTry || setAside.isEmpty {
                    let left = stillToCome.count
                    SyncLog.add("Arrivals done: \(left.formatted()) still to come (\(notInICloud.formatted()) not in iCloud yet, \(setAside.count.formatted()) didn't come)")
                    return left > 0
                }
                SyncLog.add("Trying the \(setAside.count.formatted()) set-aside pins once more")
                queue = setAside
                setAside = []
                next = 0
                secondTry = true
                continue
            }
            if window.isEmpty { continue }
            let waiting = window
            let round = await Task.detached(priority: .utility) {
                await CloudSync.collectArrived(waiting, to: local, seconds: CloudSync.arrivalRound)
            }.value
            guard store.isCurrentProfile(profile) else { return true }
            window = round.left
            setAside.append(contentsOf: round.setAside.map { (item: Wanted) -> Pin in item.pin })
            for reason in round.reasons { SyncLog.add(reason) }
            stillToCome.subtract(round.came.map { $0.id })
            // First: their full files count as "in iCloud only" (so nothing calls them missing).
            OffloadIndex.shared.markArriving(round.fullFilesLater, in: local)
            if !round.came.isEmpty {
                lastArrival = Date()
                // Only these pins are added; everything else of the library stays as it is now.
                let partial = LibraryDocument(pins: round.came, boards: [], smartBoards: [], erased: [:])
                let ids = Set(round.came.map { (pin: Pin) -> UUID in pin.id })
                let before = store.contentVersion
                store.applySynced(CloudSync.mergeDocuments(local: store.document, remote: partial), profile: profile)
                ownChanges += store.contentVersion - before   // (the sync's own change: no new sync for it)
                store.forgetCachedPictures(changedSince: [:], placed: ids)
                store.missingFileIDs.subtract(ids)
            }
            // The app was away (iOS pauses it): that time doesn't count as waiting.
            let away = Date().timeIntervalSince(stepStart) - CloudSync.arrivalRound - 20
            if away > 0 {
                SyncLog.add("The app was away for about \(Int(away)) s")
                lastArrival = lastArrival.addingTimeInterval(away)
                window = window.map { (item: Wanted) -> Wanted in item.shifted(by: away) }
            }
            if Date().timeIntervalSince(lastLog) > 60 {
                lastLog = Date()
                SyncLog.add("\((overall - stillToCome.count).formatted()) of \(overall.formatted()) here; \(window.count) waiting, \(setAside.count) set aside, next \(next) of \(queue.count)")
            }
            if Date().timeIntervalSince(lastArrival) > CloudSync.quietToStop {
                SyncLog.add("Nothing came from iCloud for 5 minutes: this run stops")
                return true
            }
        }
    }

    /// One pin waiting in the window: the files it can't do without (its picture, its video), the
    /// extras taken when they are there (thumbnail, fingerprint, photo details), and when its
    /// needed files were all here (the extras get a few more seconds from then).
    struct Wanted: Sendable {
        var pin: Pin
        var needed: [FilePair]
        var extras: [FilePair]
        var later: FilePair? = nil   // the full picture or video, brought after the sync
        var neededHereAt: Date? = nil
        var askedAt = Date()

        /// The same, as if asked `seconds` later (time the app spent away doesn't count).
        func shifted(by seconds: Double) -> Wanted {
            var item = self
            item.askedAt = askedAt.addingTimeInterval(seconds)
            item.neededHereAt = neededHereAt?.addingTimeInterval(seconds)
            return item
        }
    }

    /// A file in the iCloud folder and where it goes in the library.
    struct FilePair: Sendable {
        var from: URL
        var to: URL
    }

    /// What one round brought: the pins whose files are now in the library (records as they should
    /// be kept here), and the pins still waiting.
    struct Arrived: Sendable {
        var came: [Pin] = []
        var left: [Wanted] = []
        var setAside: [Wanted] = []   // waited too long, or iCloud reported an error: tried later
        var fullFilesLater: [UUID: Int64] = [:]   // pins whose full file comes after the sync (its size)
        var reasons: [String] = []    // for the sync log
    }

    /// Asks iCloud for the files of `pins` (see `bringArrivals`). A pin whose picture or video isn't
    /// in iCloud at all yet (the other device is still sending it) is skipped at once.
    nonisolated static func askForFiles(of pins: [Pin], from remote: LibraryLocation, to local: LibraryLocation) -> [Wanted] {
        var wanted: [Wanted] = []
        for pin in pins {
            let item = wantedFiles(of: pin, from: remote, to: local)
            guard item.needed.allSatisfy({ (pair: FilePair) -> Bool in inCloud(pair.from) }) else { continue }
            for pair in item.needed + item.extras { try? FileManager.default.startDownloadingUbiquitousItem(at: pair.from) }
            wanted.append(item)
        }
        return wanted
    }

    /// The files of one pin still to come (those already in the library are left out; extras
    /// iCloud doesn't have are not waited for). A photo or video waits only for its thumbnail; its
    /// full file is `later`. Without a thumbnail in iCloud (or for a link's preview) the picture
    /// itself is needed, as before.
    nonisolated private static func wantedFiles(of pin: Pin, from remote: LibraryLocation, to local: LibraryLocation) -> Wanted {
        func pair(_ folder: KeyPath<LibraryLocation, URL>, _ name: String) -> FilePair {
            FilePair(from: remote[keyPath: folder].appendingPathComponent(name), to: local[keyPath: folder].appendingPathComponent(name))
        }
        var needed: [FilePair] = []
        var extras: [FilePair] = []
        var later: FilePair? = nil
        let thumb = pair(\.thumbs, pin.thumbFileName)
        let thumbFirst = pin.hasImageFile && OffloadIndex.offloadableFile(of: pin, in: local) != nil && inCloud(thumb.from)
        if pin.hasImageFile {
            let image = pair(\.images, pin.imageFileName)
            if thumbFirst {
                needed.append(thumb)
                if pin.isVideo { extras.append(image) } else { later = image }   // (a video's poster is small)
            } else {
                needed.append(image)
                extras.append(thumb)
            }
        }
        if pin.isVideo {
            let video = pair(\.videos, pin.videoFileName)
            if thumbFirst { later = video } else { needed.append(video) }
        }
        if pin.hasFeaturePrint { extras.append(pair(\.prints, pin.printFileName)) }
        extras.append(pair(\.exif, pin.exifFileName))
        needed.removeAll { (pair: FilePair) -> Bool in FileManager.default.fileExists(atPath: pair.to.path) }
        extras.removeAll { (pair: FilePair) -> Bool in
            FileManager.default.fileExists(atPath: pair.to.path) || !inCloud(pair.from)
        }
        if let file = later, FileManager.default.fileExists(atPath: file.to.path) || !inCloud(file.from) { later = nil }
        return Wanted(pin: pin, needed: needed, extras: extras, later: later)
    }

    /// Looks over the window for up to `seconds` and copies in every pin whose files are here
    /// (returning early once a good handful has come). A pin's extras get five seconds after its
    /// needed files are here; any still missing then are made again here or done without.
    nonisolated static func collectArrived(_ window: [Wanted], to local: LibraryLocation, seconds: Double) async -> Arrived {
        var waiting = window
        var result = Arrived()
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            var still: [Wanted] = []
            for var item in waiting {
                if item.neededHereAt == nil {
                    if item.needed.allSatisfy({ (pair: FilePair) -> Bool in isHere(pair.from) }) { item.neededHereAt = Date() }
                }
                guard let neededAt = item.neededHereAt else {
                    if let reason = giveUpReason(item) {
                        result.setAside.append(item)
                        if result.reasons.count < 5 { result.reasons.append(reason) }
                    } else {
                        still.append(item)
                    }
                    continue
                }
                let extrasHere = item.extras.allSatisfy { (pair: FilePair) -> Bool in isHere(pair.from) }
                if !extrasHere && Date().timeIntervalSince(neededAt) < 5 {
                    still.append(item)
                    continue
                }
                if let pin = copyIn(item, to: local) {
                    result.came.append(pin)
                    if let later = item.later { result.fullFilesLater[pin.id] = cloudSize(of: later.from) }
                } else {
                    // The copy failed: set aside (tried later), never retried round after round.
                    result.setAside.append(item)
                    if result.reasons.count < 5 { result.reasons.append("Couldn't copy the files of a pin into the library") }
                }
            }
            waiting = still
            if waiting.isEmpty || Date() >= deadline || result.came.count >= 50 { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        result.left = waiting
        return result
    }

    /// Why a pin still waiting should be set aside now (nil: it keeps waiting): iCloud reported an
    /// error for one of its files, or it has waited longer than `pictureWait` / `videoWait`.
    /// (The error is looked at only after 20 seconds, to keep each round light.)
    nonisolated private static func giveUpReason(_ item: Wanted) -> String? {
        let waited = Date().timeIntervalSince(item.askedAt)
        if waited < 20 { return nil }
        for pair in item.needed {
            let fresh = URL(fileURLWithPath: pair.from.path)
            let values = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
            if let error = values?.ubiquitousItemDownloadingError {
                return "iCloud couldn't send \(pair.from.lastPathComponent): \(error.localizedDescription)"
            }
        }
        let limit = item.pin.isVideo ? videoWait : pictureWait
        if waited > limit { return "Set aside after \(Int(waited)) s: \(item.needed.first?.from.lastPathComponent ?? "a pin")" }
        return nil
    }

    /// Copies one pin's files into the library. nil: a needed file couldn't be copied.
    nonisolated private static func copyIn(_ item: Wanted, to local: LibraryLocation) -> Pin? {
        for pair in item.needed where !copyOut(pair.from, to: pair.to) { return nil }
        for pair in item.extras where isHere(pair.from) { _ = copyOut(pair.from, to: pair.to) }
        var pin = item.pin
        let print = local.prints.appendingPathComponent(pin.printFileName)
        if pin.hasFeaturePrint && !FileManager.default.fileExists(atPath: print.path) {
            // Its fingerprint didn't come: made again here, as in `LibraryStore.placeFiles`.
            pin.hasFeaturePrint = false
            pin.needsAnalysis = true
        }
        return pin
    }

    /// A file's size in iCloud (also when it isn't downloaded), for Settings › iCloud & storage. 0: unknown.
    nonisolated private static func cloudSize(of file: URL) -> Int64 {
        let fresh = URL(fileURLWithPath: file.path)
        let values = try? fresh.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        return Int64(values?.fileSize ?? values?.totalFileSize ?? 0)
    }

    /// The file is in iCloud (here in full, or listed and waiting to be downloaded).
    nonisolated private static func inCloud(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path) || isUbiquitousPlaceholder(file)
    }

    /// The file is here in full: iCloud's latest copy, downloaded (read fresh: see `isFullyHere`).
    nonisolated private static func isHere(_ file: URL) -> Bool { isFullyHere(file) }

    /// Copies a file from the iCloud folder into the library, then lets go of the iCloud folder's
    /// copy on this device (it stays in iCloud). false: the copy failed.
    nonisolated private static func copyOut(_ file: URL, to target: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: target.path) {
            guard (try? FileManager.default.copyItem(at: file, to: target)) != nil else { return false }
        }
        try? FileManager.default.evictUbiquitousItem(at: file)
        return true
    }

    /// Whether a pin here is missing its picture or video (say an earlier sync gave up waiting).
    nonisolated static func missesFiles(_ pin: Pin, in location: LibraryLocation) -> Bool {
        if pin.hasImageFile, !FileManager.default.fileExists(atPath: location.images.appendingPathComponent(pin.imageFileName).path) { return true }
        if pin.isVideo, !FileManager.default.fileExists(atPath: location.videos.appendingPathComponent(pin.videoFileName).path) { return true }
        return false
    }

    /// Lets go of this device's copies of the files in the iCloud folder that iCloud already has in
    /// full (they stay in iCloud; the library keeps its own copy). Library lists stay: every sync reads them.
    /// Returns how many files here are still waiting to be sent to iCloud (for the sync log: the
    /// other devices can't get those yet).
    @discardableResult
    nonisolated static func evictUploadedCopies(in remote: LibraryLocation) -> Int {
        let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey]
        var notSent = 0
        for folder in remote.allFolders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
            for file in files where !file.lastPathComponent.hasPrefix(".") {
                guard let values = try? file.resourceValues(forKeys: keys) else { continue }
                let here = values.ubiquitousItemDownloadingStatus == .current
                if here && values.ubiquitousItemIsUploaded == false { notSent += 1 }
                guard values.ubiquitousItemIsUploaded == true, here else { continue }
                try? FileManager.default.evictUbiquitousItem(at: file)
            }
        }
        return notSent
    }
}
