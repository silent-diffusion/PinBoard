//
//  DragAndDrop.swift  —  PinBoard
//
//  Dragging and dropping: drop zones (pictures, videos, text, links and the
//  app's own cards) with their outline, the loader that reads what was dropped,
//  and what a dragged pin card carries.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Foundation


// MARK: - Drop zones (pictures, videos, text, links and the app's own cards)

/// Makes a view accept drops: `.modifier(PinDropZone(boardIDs: [id], style: .tile))`.
/// It draws its own dashed outline while something droppable hovers over it —
/// `.page` around a whole screen, `.tile` around one board tile — and only for
/// content it can take. A watchdog clears the outline when hovering stops, so a
/// cancelled drag never leaves it on. Dropped items go to the given boards
/// (none = Unsorted), or straight into Hidden with `hidden: true`.
@MainActor
struct PinDropZone: ViewModifier {
    enum Style { case page, tile }

    let boardIDs: [UUID]
    var style: Style
    var hidden: Bool

    @EnvironmentObject private var importFlow: ImportFlow
    @Environment(\.pinAccent) private var accent
    @StateObject private var hover = DropHover()

    init(boardIDs: [UUID], style: Style = .page, hidden: Bool = false) {
        self.boardIDs = boardIDs
        self.style = style
        self.hidden = hidden
    }

    /// What `DropPayload` can be read from.
    static var acceptedTypes: [UTType] { [.image, .movie, .url, .plainText] }

    func body(content: Content) -> some View {
        let flow = importFlow
        let boards = boardIDs
        let intoHidden = hidden
        return content
            .overlay {
                if hover.isTargeted {
                    outline.allowsHitTesting(false)
                }
            }
            .onDrop(of: PinDropZone.acceptedTypes,
                    delegate: PinDropDelegate(hover: hover, flow: flow, boardIDs: boards, hidden: intoHidden))
    }

    @ViewBuilder
    private var outline: some View {
        switch style {
        case .page:
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .padding(8)
        case .tile:
            RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous)
                .strokeBorder(accent, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
        }
    }
}

/// Whether a drag is hovering over a drop zone. Every hover update is recorded;
/// when none has come for a while the drag has gone (or was cancelled without
/// saying so) and the outline is cleared.
@MainActor
final class DropHover: ObservableObject {
    @Published private(set) var isTargeted = false
    private var lastUpdate = Date.distantPast
    private var watchdog: Task<Void, Never>? = nil

    /// No hover update for this long = nothing is hovering any more. Updates may come
    /// only while the drag moves, so a drag held still must keep its outline this long.
    static let timeout: TimeInterval = 3.5

    func touch() {
        lastUpdate = Date()
        if !isTargeted { isTargeted = true }
        guard watchdog == nil else { return }
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                if Date().timeIntervalSince(self.lastUpdate) > DropHover.timeout {
                    self.watchdog = nil
                    self.isTargeted = false
                    return
                }
            }
        }
    }

    func clear() {
        watchdog?.cancel()
        watchdog = nil
        if isTargeted { isTargeted = false }
    }
}

/// The drop zone's delegate: highlights only for content `DropPayload` can read,
/// keeps the watchdog fed while the drag moves, and loads what is dropped.
/// It keeps plain values (no callback closure), so nothing has to be converted
/// between isolation domains.
struct PinDropDelegate: DropDelegate {
    let hover: DropHover
    let flow: ImportFlow        // where the dropped items go
    let boardIDs: [UUID]        // none = Unsorted
    let hidden: Bool            // true = straight into Hidden

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: PinDropZone.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) { hover.touch() }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            hover.clear()
            return DropProposal(operation: .forbidden)
        }
        hover.touch()
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        hover.clear()
    }

    func performDrop(info: DropInfo) -> Bool {
        hover.clear()
        let providers = info.itemProviders(for: PinDropZone.acceptedTypes)
        guard !providers.isEmpty else { return false }
        DropLoader.load(providers, into: flow, boardIDs: boardIDs, hidden: hidden)
        return true
    }
}

/// Reads dropped items as `DropPayload`s. The app's own cards are recognised by
/// the `pinboard://` link they carry (read alongside, so a card is never
/// imported a second time as a copy of its own picture).
enum DropLoader {
    /// Loads the dropped items and hands them to `flow` once all have arrived.
    @MainActor
    static func load(_ providers: [NSItemProvider], into flow: ImportFlow, boardIDs: [UUID], hidden: Bool) {
        let results = DropResults(slots: providers.count, flow: flow, boardIDs: boardIDs, hidden: hidden)
        let urlType = UTType.url.identifier
        for (index, provider) in providers.enumerated() {
            let offersLink = provider.hasItemConformingToTypeIdentifier(urlType)
            results.expect(index, reference: offersLink)
            if offersLink {
                _ = provider.loadTransferable(type: URL.self) { @Sendable result in
                    let url = try? result.get()
                    results.deliver(index, reference: url.flatMap { DropPayload.pinID(from: $0) })
                }
            }
            _ = provider.loadTransferable(type: DropPayload.self) { @Sendable result in
                results.deliver(index, payload: try? result.get())
            }
        }
    }
}

/// Collects the loads of one drop (they finish on background threads, in any
/// order) and hands the payloads to the import flow, in the dropped order, once
/// all are in. The mutable slots are guarded by `lock`; everything else is a
/// constant Sendable value.
final class DropResults: @unchecked Sendable {
    private struct Slot {
        var waitingForReference = false
        var waitingForPayload = true
        var reference: UUID? = nil
        var payload: DropPayload? = nil
    }

    private let lock = NSLock()
    private var slots: [Slot]
    private let flow: ImportFlow      // a main-actor object: safe to hand across threads
    private let boardIDs: [UUID]
    private let hidden: Bool

    init(slots count: Int, flow: ImportFlow, boardIDs: [UUID], hidden: Bool) {
        slots = Array(repeating: Slot(), count: count)
        self.flow = flow
        self.boardIDs = boardIDs
        self.hidden = hidden
    }

    /// Called before any load starts: whether a link load comes for this slot too.
    func expect(_ index: Int, reference: Bool) {
        lock.lock()
        if slots.indices.contains(index) { slots[index].waitingForReference = reference }
        lock.unlock()
    }

    func deliver(_ index: Int, reference: UUID?) {
        lock.lock()
        if slots.indices.contains(index) {
            slots[index].reference = reference
            slots[index].waitingForReference = false
        }
        lock.unlock()
        finishIfComplete()
    }

    func deliver(_ index: Int, payload: DropPayload?) {
        lock.lock()
        if slots.indices.contains(index) {
            slots[index].payload = payload
            slots[index].waitingForPayload = false
        }
        lock.unlock()
        finishIfComplete()
    }

    private func finishIfComplete() {
        lock.lock()
        let complete = slots.allSatisfy { !$0.waitingForReference && !$0.waitingForPayload }
        let done = complete ? slots : []
        if complete { slots = [] }        // hand over exactly once
        lock.unlock()
        guard complete, !done.isEmpty else { return }
        var payloads: [DropPayload] = []
        for slot in done {
            if let id = slot.reference {
                // One of the app's own cards: the copy of its file is not needed.
                if case .video(let url)? = slot.payload { try? FileManager.default.removeItem(at: url) }
                payloads.append(.pin(id))
            } else if let payload = slot.payload {
                payloads.append(payload)
            }
        }
        let flow = flow
        let boards = boardIDs
        let intoHidden = hidden
        let dropped = payloads
        Task { @MainActor in
            flow.importDropped(dropped, boardIDs: boards, hidden: intoHidden)
        }
    }
}

/// What a dragged card carries, built by hand as an `NSItemProvider` (not SwiftUI's
/// `.draggable`): on the Mac, Finder, Mail and Notes need a real file with a name, and
/// a drag whose data never arrives leaves its picture stuck on screen.
///
/// - Pictures and videos: a *copy* of the stored file, named after the pin's title
///   ("Sunset.jpg"), offered to every app. The stored picture is already a plain
///   re-encoded JPEG with no camera or location data, and nothing is added to it.
///   Only a file that is on this device is offered: one kept in iCloud only isn't,
///   so the drag can never wait on a download (it still works inside the app).
/// - Text pins: their text (the title when there is none). Link pins: nothing more.
/// - Always: the app's own `pinboard://` reference, visible to PinBoard only, so a
///   card dropped on a board moves as itself and other apps never see the link.
enum PinDragOut {
    /// Where the named copies are made. Old ones are swept away on the next drag.
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DragOut", isDirectory: true)
    }

    /// The provider for one card. `file`: the stored picture or video (nil for text and links).
    nonisolated static func provider(for pin: Pin, file: URL?) -> NSItemProvider {
        sweep()
        let provider = NSItemProvider()
        let name = pin.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Pin \(String(pin.id.uuidString.prefix(8)))"
            : pin.title.safeFileName
        provider.suggestedName = name

        switch pin.kind {
        case .image, .video:
            if let file, FileManager.default.fileExists(atPath: file.path) {
                let ext = pin.kind == .video ? (pin.videoExtension ?? "mov").lowercased() : "jpg"
                let type = pin.kind == .video
                    ? (UTType(filenameExtension: ext, conformingTo: .movie) ?? .movie)
                    : .jpeg
                // With the extension, the receiving app keeps ".jpg" / ".mov" (not ".jpeg").
                provider.suggestedName = name + "." + ext
                registerCopy(of: file, as: type, named: name + "." + ext, on: provider)
            }
        case .text:
            let text = pin.textBody.isEmpty ? pin.title : pin.textBody
            if !text.isEmpty { provider.registerObject(text as NSString, visibility: .all) }
        case .link:
            break       // only the app's own reference (spec 6.4): its web address isn't handed out
        }

        provider.registerObject(DropPayload.reference(for: pin.id) as NSURL, visibility: .ownProcess)
        return provider
    }

    /// Offers a named copy of `source`, made only when the app it is dropped on asks for it.
    /// The copy goes in a folder of its own (two drags of same-named pins never clash) and
    /// always ends with the completion being called, so the drag can't hang.
    private nonisolated static func registerCopy(of source: URL, as type: UTType, named fileName: String,
                                                 on provider: NSItemProvider) {
        let folder = folder
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [],
                                            visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let place = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                    let copy = place.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: source, to: copy)
                    progress.completedUnitCount = 1
                    completion(copy, false, nil)
                } catch {
                    progress.completedUnitCount = 1
                    completion(nil, false, error)
                }
            }
            return progress
        }
    }

    /// Removes copies more than an hour old (by then the app they went to has its own).
    private nonisolated static func sweep() {
        let folder = folder
        DispatchQueue.global(qos: .utility).async {
            let manager = FileManager.default
            guard let places = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
            let cutoff = Date().addingTimeInterval(-3600)
            for place in places {
                let made = (try? place.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                if made < cutoff { try? manager.removeItem(at: place) }
            }
        }
    }
}
