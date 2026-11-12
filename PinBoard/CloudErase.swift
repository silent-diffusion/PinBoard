//
//  CloudErase.swift  —  PinBoard
//
//  Making "erase" stick in iCloud. Moving a pin to Recently Deleted changes nothing here (its
//  files stay, so it can be put back). When a pin is erased for good — Recently Deleted emptied,
//  "Erase now", or after 30 days — its files in this profile's iCloud folder are deleted at once,
//  each through a file coordinator (the way iCloud wants a deletion told), so no other device can
//  bring the pin back from them. The record of the erase (a "tombstone": the pin's id and when it
//  was erased) travels in library.json as before and is kept for two years, so a device that was
//  offline for a long time still learns of the erase instead of sending the pin back.
//  Erased while iCloud couldn't be reached (Offline mode, sync off for a moment, an older version
//  of the app on another device)? Each full sync also removes the iCloud files of pins erased on
//  any device (`removeErasedFiles`).
//  Nothing about the files' format changes: older versions simply find the files gone, as if the
//  sync had removed them.
//

import Foundation
import os

extension CloudSync {
    /// Every file a pin may have in a library folder (any of them may be absent): picture,
    /// thumbnail, fingerprint, photo details, video.
    nonisolated static func allFiles(of pin: Pin, in location: LibraryLocation) -> [URL] {
        var files = [location.images.appendingPathComponent(pin.imageFileName),
                     location.thumbs.appendingPathComponent(pin.thumbFileName),
                     location.prints.appendingPathComponent(pin.printFileName),
                     location.exif.appendingPathComponent(pin.exifFileName)]
        if pin.isVideo { files.append(location.videos.appendingPathComponent(pin.videoFileName)) }
        return files
    }

    /// Deletes files in iCloud for good, each through a file coordinator. A file iCloud knows of
    /// but hasn't brought here (a ".name.icloud" placeholder) is deleted the same way. Only files
    /// last changed before `before` go (see `removeErasedFiles`; pass `.distantFuture` for all).
    /// Returns how many were deleted. Can take a moment: call it off the main thread.
    @discardableResult
    nonisolated static func deleteFromICloud(_ files: [URL], before: Date = .distantFuture) -> Int {
        var deleted = 0
        for file in files {
            let placeholder = file.deletingLastPathComponent().appendingPathComponent("." + file.lastPathComponent + ".icloud")
            let target: URL
            if FileManager.default.fileExists(atPath: file.path) {
                target = file
            } else if FileManager.default.fileExists(atPath: placeholder.path) {
                target = placeholder
            } else {
                continue   // not in iCloud (any more)
            }
            if before != .distantFuture {
                // A file whose date can't be read is kept (the safe side).
                let fresh = URL(fileURLWithPath: target.path)
                guard let changed = (try? fresh.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      changed < before else { continue }
            }
            if coordinatedDelete(target) { deleted += 1 }
        }
        return deleted
    }

    /// Deletes one file the way iCloud wants to be told (a coordinated write "for deleting").
    nonisolated static func coordinatedDelete(_ url: URL) -> Bool {
        var coordinationError: NSError? = nil
        var removed = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) { (deleteURL: URL) in
            removed = (try? FileManager.default.removeItem(at: deleteURL)) != nil
        }
        if let coordinationError {
            SyncLog.add("Couldn't delete \(url.lastPathComponent) from iCloud: \(coordinationError.localizedDescription)")
        }
        return removed
    }

    /// Only one clean-up at a time (a second sync while one runs skips it; the next one catches up).
    private nonisolated static let cleaning = OSAllocatedUnfairLock(initialState: false)

    /// During a full sync: removes from iCloud the files of pins that were erased for good on any
    /// device — those with a tombstone on either side that neither library has as a pin any more.
    /// Only files last changed before their erase go: a pin imported again later with its old id
    /// (from an export) has newer files, and they stay. Runs in the background; never holds up
    /// the sync.
    nonisolated static func removeErasedFiles(local: LibraryDocument, remote: LibraryDocument?, in folder: LibraryLocation) {
        var tombstones = local.erased
        for (id, date) in remote?.erased ?? [:] { tombstones[id] = max(tombstones[id] ?? .distantPast, date) }
        for pin in local.pins { tombstones[pin.id] = nil }
        for pin in remote?.pins ?? [] { tombstones[pin.id] = nil }
        guard !tombstones.isEmpty else { return }
        let erasedAt = tombstones
        let started = cleaning.withLock { (running: inout Bool) -> Bool in
            if running { return false }
            running = true
            return true
        }
        guard started else { return }
        Task.detached(priority: .utility) {
            defer { cleaning.withLock { $0 = false } }
            var deleted = 0
            for directory in folder.allFolders {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
                for name in names {
                    // "ID…" or the placeholder ".ID….icloud" of a file not downloaded here.
                    let bare = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(7)) : name
                    guard let id = UUID(uuidString: String(bare.prefix(36))), let erased = erasedAt[id] else { continue }
                    deleted += deleteFromICloud([directory.appendingPathComponent(bare)], before: erased)
                }
            }
            if deleted > 0 { SyncLog.add("Removed \(deleted.formatted()) files of erased pins from iCloud") }
        }
    }
}

extension LibraryStore {
    /// Right after pins are erased for good here: their files in this profile's iCloud folder go
    /// too (in the background). Only when this profile syncs and isn't in Offline mode; otherwise
    /// the next sync does it (`CloudSync.removeErasedFiles`).
    func eraseFromICloud(_ erased: [Pin]) {
        guard !erased.isEmpty else { return }
        let settings = AppSettings.shared
        guard settings.profileID == profileID, settings.iCloudSync, !settings.offlineMode,
              let cloud = OffloadIndex.shared.cloud(for: location) else { return }
        let files = erased.flatMap { (pin: Pin) -> [URL] in CloudSync.allFiles(of: pin, in: cloud) }
        let count = erased.count
        Task.detached(priority: .utility) {
            let deleted = CloudSync.deleteFromICloud(files)
            SyncLog.add("Erased \(count.formatted()) pins: \(deleted.formatted()) of their files deleted from iCloud")
        }
    }
}
