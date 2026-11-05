//
//  WidgetSnapshotWriter.swift  —  PinBoard
//
//  Keeps the widgets' snapshot (WidgetShared.swift) up to date: about 30 seconds after the library
//  is saved, at launch, and when another profile is opened. It holds the boards' names, a fresh
//  sample of pictures — up to 30 from each board and 90 from the whole library, as small JPEGs made
//  from the thumbnails (so a picture kept in iCloud only is there too) — and every text pin.
//  Nothing hidden: only the normal library's pins and boards (never a hidden board, nor a board
//  inside one). Then the widgets are told to look again.
//

import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// How many pictures the snapshot keeps from each board, and from the whole library.
    static let perBoard = 30
    static let fromEverything = 90
    /// The longest side of a widget's picture, in pixels (a large widget is about 700 points wide at 3×,
    /// but the snapshot's pictures are kept small: widgets have little memory).
    static let pictureSize = 640
    static let maxQuotes = 1000

    private var pending: Task<Void, Never>? = nil

    /// Writes the snapshot after `delay` seconds (another call meanwhile starts the wait again).
    func refreshSoon(store: LibraryStore, delay: Double = 30) {
        guard WidgetShared.folder != nil else { return }   // no App Group
        pending?.cancel()
        pending = Task { [weak self, weak store] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, let store else { return }
            await self.refresh(store: store)
        }
    }

    /// Writes the snapshot now and has the widgets look again.
    func refresh(store: LibraryStore) async {
        guard let folder = WidgetShared.folder, let picturesFolder = WidgetShared.picturesFolder,
              let snapshotFile = WidgetShared.snapshotFile else { return }
        let secret = store.hiddenBoardIDs
        let boards = store.boards.filter { !secret.contains($0.id) }
        let visible = store.visiblePins   // live pins of the normal library: never a hidden one
        let visibleIDs = Set(visible.map { $0.id })

        // Which (normal) boards' pages show each pin; a sub-board's pins count for its parents.
        var boardsOf: [UUID: [UUID]] = [:]
        for board in boards {
            for pin in store.pins(in: board.id, includeNested: true) where visibleIDs.contains(pin.id) {
                boardsOf[pin.id, default: []].append(board.id)
            }
        }

        // A fresh sample of pictures: some from the whole library, and some from every board.
        let withPictures = visible.filter { $0.hasImageFile }
        var chosen = Set(withPictures.shuffled().prefix(WidgetSnapshotWriter.fromEverything).map { $0.id })
        for board in boards {
            let inBoard = withPictures.filter { boardsOf[$0.id]?.contains(board.id) == true }
            chosen.formUnion(inBoard.shuffled().prefix(WidgetSnapshotWriter.perBoard).map { $0.id })
        }
        var photos: [WidgetSnapshot.Photo] = []
        var sources: [(from: URL, fallback: URL, to: URL)] = []
        for pin in withPictures where chosen.contains(pin.id) {
            let name = WidgetShared.pictureName(pin.id, revision: pin.pictureRevision)
            photos.append(WidgetSnapshot.Photo(id: pin.id, file: name, title: pin.title, boardIDs: boardsOf[pin.id] ?? []))
            sources.append((store.thumbsURL.appendingPathComponent(pin.thumbFileName),
                            store.imageFileURL(for: pin),
                            picturesFolder.appendingPathComponent(name)))
        }

        let quotes: [WidgetSnapshot.Quote] = visible
            .filter { $0.kind == .text && !$0.textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(WidgetSnapshotWriter.maxQuotes)
            .map { WidgetSnapshot.Quote(id: $0.id, text: $0.textBody, title: $0.title, boardIDs: boardsOf[$0.id] ?? []) }

        let snapshot = WidgetSnapshot(made: Date(),
                                      boards: boards.map { WidgetSnapshot.Board(id: $0.id, name: $0.name) }
                                          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                                      photos: photos, quotes: Array(quotes))
        let size = WidgetSnapshotWriter.pictureSize
        let jobs = sources
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: picturesFolder, withIntermediateDirectories: true)
            // Pictures: new ones made from the thumbnail (or the picture), old ones left out go.
            let keep = Set(jobs.map { $0.to.lastPathComponent })
            for job in jobs where !FileManager.default.fileExists(atPath: job.to.path) {
                guard let data = (try? Data(contentsOf: job.from)) ?? (try? Data(contentsOf: job.fallback)),
                      let small = ImageProcessor.downsample(data, maxPixelSize: size),
                      let jpeg = ImageProcessor.jpegData(small, quality: 0.8) else { continue }
                try? jpeg.write(to: job.to, options: .atomic)
            }
            for file in (try? FileManager.default.contentsOfDirectory(at: picturesFolder, includingPropertiesForKeys: nil)) ?? []
            where !keep.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: snapshotFile, options: .atomic) }
        }.value
        WidgetCenter.shared.reloadAllTimelines()
    }
}
