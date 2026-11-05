//
//  ShareFamiliar.swift  —  PinBoard
//
//  Writes what the share sheet's "Looks familiar" check needs (ShareShared.swift has the format):
//  for every normal pin, its picture signature (pictures, videos by their poster, links with a
//  picture), its page (link pins) or a fingerprint of its words (text pins), its boards' names,
//  and a tiny picture (120 px) to show beside the shared one. Never anything of a hidden pin: the
//  share sheet runs inside other apps, where the Hidden side is locked.
//  Written with the share sheet's board list (ShareInbox.swift), into the open profile's own
//  folder: at launch, a few seconds after the library is saved, when PinBoard comes to the front
//  and when another profile is opened.
//  The tiny pictures are made in the background, only for pins that don't have one yet.
//

import Foundation

@MainActor
enum ShareFamiliarWriter {
    /// The longest side of the tiny pictures, in pixels (they are shown about 60 points wide).
    static let thumbSize = 120

    private static var lastWritten: [UUID: Data] = [:]
    private static var running: Task<Void, Never>? = nil

    /// Writes the index of the library open now (only when it changed) and brings the tiny
    /// pictures up to date. A newer call waits for the one before (they would race for the files).
    static func write(store: LibraryStore) {
        let profile = store.profileID
        guard let file = ShareShared.familiarFile(for: profile), let thumbs = ShareShared.thumbsFolder(for: profile) else { return }
        let built = build(store: store)
        let previous = running
        running = Task { @MainActor in
            await previous?.value
            let index = built.index
            let jobs = built.jobs
            let data = await Task.detached(priority: .utility) { () -> Data? in
                try? JSONEncoder().encode(index)
            }.value
            guard let data else { return }
            if data != lastWritten[profile] {
                let written = await Task.detached(priority: .utility) { () -> Bool in
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    return (try? data.write(to: file, options: .atomic)) != nil
                }.value
                if written { lastWritten[profile] = data }
            }
            let size = thumbSize
            await Task.detached(priority: .utility) { ShareFamiliarWriter.makeThumbs(jobs, in: thumbs, size: size) }.value
        }
    }

    /// A tiny picture to make: from the pin's thumbnail (or, failing that, its picture).
    struct ThumbJob: Sendable {
        var from: URL
        var fallback: URL
        var name: String
    }

    /// The index, and the tiny pictures it names.
    private static func build(store: LibraryStore) -> (index: ShareFamiliarIndex, jobs: [ThumbJob]) {
        var known: [ShareFamiliarIndex.Known] = []
        var pictures: [ShareFamiliarIndex.Picture] = []
        var links: [String: UUID] = [:]
        var texts: [String: UUID] = [:]
        var jobs: [ThumbJob] = []
        for pin in store.visiblePins {   // live normal pins: never a hidden one
            var listed = false
            if let hash = pin.dhash, hash != 0 {
                pictures.append(ShareFamiliarIndex.Picture(id: pin.id, hash: ShareFamiliarIndex.hex(hash), aspect: Double(pin.aspectRatio)))
                listed = true
            }
            if pin.isLink, let link = pin.linkURL {
                links[LibraryStore.pageKey(link)] = pin.id
                listed = true
            }
            if pin.isText, !pin.textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts[ShareFamiliarIndex.textKey(pin.textBody)] = pin.id
                listed = true
            }
            guard listed else { continue }
            known.append(knownEntry(for: pin, store: store, jobs: &jobs))
        }
        let index = ShareFamiliarIndex(profileID: store.profileID, pins: known, pictures: pictures, links: links, texts: texts)
        return (index, jobs)
    }

    /// What the share sheet shows of a pin: its kind, title, boards and tiny picture.
    private static func knownEntry(for pin: Pin, store: LibraryStore, jobs: inout [ThumbJob]) -> ShareFamiliarIndex.Known {
        let boards = pin.boardIDs.compactMap { store.board($0) }.filter { (board: Board) -> Bool in !store.isSecretBoard(board.id) }
        var entry = ShareFamiliarIndex.Known(id: pin.id, kind: kindName(pin), title: String(pin.title.prefix(60)),
                                             boardIDs: boards.map { $0.id }, boardNames: boards.map { $0.name })
        if pin.hasImageFile {
            let name = "\(pin.id.uuidString)-\(pin.pictureRevision).jpg"
            entry.thumb = name
            jobs.append(ThumbJob(from: store.thumbsURL.appendingPathComponent(pin.thumbFileName),
                                 fallback: store.imageFileURL(for: pin), name: name))
        }
        return entry
    }

    private static func kindName(_ pin: Pin) -> String {
        switch pin.kind {
        case .image: return "picture"
        case .video: return "video"
        case .link: return "link"
        case .text: return "text"
        }
    }

    /// Makes the tiny pictures that are missing and removes those no pin needs any more.
    nonisolated static func makeThumbs(_ jobs: [ThumbJob], in folder: URL, size: Int) {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let present = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
        let wanted = Set(jobs.map { $0.name })
        for name in present where !wanted.contains(name) {
            try? manager.removeItem(at: folder.appendingPathComponent(name))
        }
        for job in jobs where !present.contains(job.name) {
            autoreleasepool {
                guard let data = (try? Data(contentsOf: job.from)) ?? (try? Data(contentsOf: job.fallback)),
                      let small = ImageProcessor.downsample(data, maxPixelSize: size),
                      let jpeg = ImageProcessor.jpegData(small, quality: 0.7) else { return }
                try? jpeg.write(to: folder.appendingPathComponent(job.name), options: .atomic)
            }
        }
    }
}
