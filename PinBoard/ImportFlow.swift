//
//  ImportFlow.swift  —  PinBoard
//
//  Adding pins: the import flow (photos, files, camera, clipboard, text, links,
//  web results, drops and folders) with its "you already have this" questions,
//  where those questions appear, and the "+" menu that starts an import.
//

import SwiftUI
#if canImport(Accessibility)   // AccessibilityNotification (VoiceOver reads the confirmations) lives there
import Accessibility
#endif
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Foundation


// MARK: - Importing (photos, files, camera, clipboard, drops) with duplicate questions

/// Runs every import: reads what was chosen, asks about anything that looks like
/// a pin you already have ("Save as a new pin" / "Add the existing pin" / "Skip" —
/// or for all the rest at once), then commits. Every window has one of its own (made in
/// ContentView), so its questions and confirmations show in that window; all of them
/// add to the one library the app shares.
/// A batch belongs to the library (profile) it was read for: if another profile is opened
/// (in any window) before it is committed, the batch is dropped, never committed into the
/// library now open — its look-alikes and boards are the other library's.
@MainActor
final class ImportFlow: ObservableObject {
    /// The questions still to answer for one batch.
    struct Review: Identifiable {
        let id = UUID()
        var pending: [PendingImport]
        var boardIDs: [UUID]
        var hidden: Bool                  // the new pins go straight into Hidden
        var scope: PinScope               // the side the new pins land on (only its pins are shown)
        var profileID: UUID               // the library the batch was read for (committed only into it)
        var duplicateIDs: [UUID]          // pending items that need a decision, in order
        var position = 0
        var skipped: Set<UUID> = []
        /// Items whose look-alike (the pin already here) goes on the boards instead.
        var addExisting: Set<UUID> = []
        /// "Import a folder…": the folder being imported (nil for every other import).
        var folder: FolderImportPlan? = nil

        var current: PendingImport? {
            guard position < duplicateIDs.count else { return nil }
            return pending.first { $0.id == duplicateIDs[position] }
        }
        var remaining: Int { max(0, duplicateIDs.count - position) }

        /// The questions not answered yet (the current one first).
        var remainingItems: [PendingImport] {
            guard position < duplicateIDs.count else { return [] }
            let ids = Set(duplicateIDs[position...])
            return pending.filter { ids.contains($0.id) }
        }
    }

    enum Decision { case add, skip, addExisting, addAllRemaining, skipAllRemaining, addExistingAllRemaining, cancel }

    /// What "Add the existing pin" can do for one question.
    enum ExistingChoice: Equatable {
        case unavailable            // the item lands on no board (e.g. Unsorted): nothing to add it to
        case available(boards: Int) // the look-alike can be put on this many boards
        case alreadyThere           // the look-alike is already on every board the item goes to
    }

    @Published var review: Review? = nil
    @Published var message: String? = nil
    @Published var showMessage = false
    @Published private(set) var isWorking = false
    private var workingCount = 0 { didSet { isWorking = workingCount > 0 } }   // imports can overlap
    /// A short confirmation ("Added 3 pins to Travel.") floating over the screen for a few seconds,
    /// and the symbol shown next to it (set together with `toast`, which redraws it).
    @Published private(set) var toast: String? = nil
    private(set) var toastSymbol = "checkmark.circle"
    /// How many screens that show the flow themselves (Quick Look, Settings) are up. The root
    /// presenter and the tabs' confirmations stay quiet while one is, because nothing they show
    /// would appear above it; that screen shows the questions, results and confirmations
    /// itself (see `importFlowCover()`).
    @Published fileprivate var coverDepth = 0
    /// The review whose sheet is actually on screen (so dismissing an old sheet
    /// never cancels a newer batch).
    fileprivate var presentedReviewID: UUID? = nil

    private let store: LibraryStore
    private var toastTask: Task<Void, Never>? = nil

    init(store: LibraryStore) {
        self.store = store
    }

    // Entry points. `hidden`: what is added goes straight into the Hidden section
    // (used by the Hidden section's "+" menu and drop target).

    func importPicked(_ items: [PhotosPickerItem], boardIDs: [UUID], hidden: Bool = false) {
        guard !items.isEmpty else { return }
        run(nothingText: "Those items couldn't be read.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareImports(pickerItems: items, scope: scope)
        }
    }

    func importFiles(_ urls: [URL], boardIDs: [UUID], hidden: Bool = false) {
        guard !urls.isEmpty else { return }
        run(nothingText: "Those files couldn't be read as pictures, videos or text.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareImports(fileURLs: urls, scope: scope)
        }
    }

    func importDropped(_ items: [DropPayload], boardIDs: [UUID], hidden: Bool = false) {
        guard !items.isEmpty else { return }
        // The app's own cards: put them on the board (or into Hidden), nothing to import.
        let ownPins = Set(items.compactMap { item -> UUID? in
            if case .pin(let id) = item { return id }
            return nil
        })
        if !ownPins.isEmpty {
            let live = ownPins.filter { store.livePin($0) != nil }
            if !boardIDs.isEmpty {
                putDroppedPins(live, on: boardIDs)
            } else if hidden {
                let toHide = live.filter { id in store.livePin(id).map { !store.isHidden($0) } ?? false }
                if toHide.isEmpty {
                    flash("Already hidden.", symbol: "info.circle")   // nothing to do: a note, not a checkmark
                } else {
                    store.hidePins(toHide)
                    flash("Hid \(toHide.count) pin\(toHide.count == 1 ? "" : "s").")
                }
            } else {
                flash("Drop pins onto a board to put them there.", symbol: "info.circle")   // a hint
            }
        }
        let rest = items.filter { item in
            if case .pin = item { return false }
            return true
        }
        guard !rest.isEmpty else { return }
        run(nothingText: "Nothing droppable was found — try an image, a video, text or a link.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareImports(dropped: rest, scope: scope)
        }
    }

    /// Puts the app's own dropped cards on the boards and says what really happened: the store's
    /// answer (`addPins`) tells how many were put on a board, how many were left because they are on
    /// one of its sub-boards already, and how many moved down out of a board it sits in. Pins that
    /// were on the board already are none of those three.
    private func putDroppedPins(_ live: Set<UUID>, on boardIDs: [UUID]) {
        guard !live.isEmpty else {
            flash("Those pins are no longer in your library.", symbol: "info.circle")
            return
        }
        // A hidden board is never named (the message may outlast your visit to Hidden).
        let hiddenTarget = boardIDs.contains { store.isSecretBoard($0) }
        var results: [BoardPutResult] = []
        for boardID in boardIDs {
            let answer = store.addPins(live, to: boardID)
            let name = hiddenTarget ? "a hidden board" : (store.board(boardID)?.name ?? "the board")
            results.append(BoardPutResult(name: name, pins: live.count, added: answer.added,
                                          alreadyBelow: answer.alreadyBelow, movedDown: answer.movedDown))
        }
        let said = ImportFlow.putOnBoardsText(results)
        flash(said.text, symbol: said.changedAnything ? "checkmark.circle" : "info.circle")
    }

    /// What dropping cards on one board did (see `LibraryStore.addPins`): `pins` were dropped.
    struct BoardPutResult: Equatable, Sendable {
        var name: String
        var pins: Int
        var added: Int
        var alreadyBelow: Int
        var movedDown: Int

        /// Pins that are on the board now because of this drop.
        var changed: Int { added + movedDown }
    }

    /// The confirmation for dropped cards: "Put 3 pins on Travel." — and, when something else
    /// happened, how many moved down from a board this one is in or stayed on a sub-board; when
    /// nothing changed, why ("They're already on Travel."). Boards that all went the same way are
    /// named together; otherwise each board gets its own sentence. `changedAnything`: some pin was
    /// put on some board (the checkmark; otherwise the note symbol).
    nonisolated static func putOnBoardsText(_ results: [BoardPutResult]) -> (text: String, changedAnything: Bool) {
        guard let first = results.first else { return ("", false) }
        let changedAnything = results.contains { (result: BoardPutResult) -> Bool in result.changed > 0 }
        let allTheSame = results.allSatisfy { (result: BoardPutResult) -> Bool in
            result.pins == first.pins && result.added == first.added && result.alreadyBelow == first.alreadyBelow
                && result.movedDown == first.movedDown
        }
        var sentences: [String] = []
        if allTheSame {
            var names: [String] = []
            for result in results where !names.contains(result.name) { names.append(result.name) }
            sentences.append(putOnBoardText(first, board: names.joined(separator: ", ")))
        } else {
            for result in results {
                let sentence = putOnBoardText(result, board: result.name)
                if !sentences.contains(sentence) { sentences.append(sentence) }
            }
        }
        return (sentences.joined(separator: " "), changedAnything)
    }

    private nonisolated static func putOnBoardText(_ result: BoardPutResult, board: String) -> String {
        if result.changed == 0 {
            if result.alreadyBelow > 0 {
                return result.pins == 1 && result.alreadyBelow == 1
                    ? "It's already on a sub-board of \(board), so it stays there."
                    : "They're already on \(board) or its sub-boards."
            }
            return result.pins == 1 ? "It's already on \(board)." : "They're already on \(board)."
        }
        var text = "Put \(result.changed) pin\(result.changed == 1 ? "" : "s") on \(board)."
        if result.movedDown > 0 {
            if result.changed == 1 {
                text += " It moved down from a board this one is in."
            } else {
                text += " \(result.movedDown) moved down from \(result.movedDown == 1 ? "a board" : "boards") this one is in."
            }
        }
        if result.alreadyBelow > 0 {
            text += result.alreadyBelow == 1 ? " 1 was already on a sub-board, so it stays there."
                                             : " \(result.alreadyBelow) were already on sub-boards, so they stay there."
        }
        return text
    }

    func importPasteboard(boardIDs: [UUID], hidden: Bool = false) {
        run(nothingText: "Nothing usable on the clipboard (a picture, text or a link).", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareImportsFromPasteboard(scope: scope)
        }
    }

    /// A link typed or pasted in the link sheet. It is read first when Settings › Links says so
    /// (an article's text, a Pinterest pin's picture… see SmartLinks.swift), which takes a moment:
    /// the status pill says "Reading the link…" meanwhile ("Downloading the video…" for a link
    /// that is itself a video file, .mp4 or .mov; a video on a social site or inside a page is never
    /// downloaded, it stays a link with its picture). A link that can't be read is still added, as a
    /// plain link (its preview is fetched after), and a video file that can't be downloaded becomes
    /// a plain link — the report says so (`lostVideosText`).
    /// So the only thing that can go wrong here is an address that isn't one.
    func importLink(_ url: URL, boardIDs: [UUID], hidden: Bool = false) {
        guard LibraryStore.linkURL(in: url.absoluteString) != nil else {
            presentSoon { $0.message = "That doesn't look like a web address."; $0.showMessage = true }
            return
        }
        let text = url.absoluteString
        run(nothingText: "That link couldn't be added.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareLinkImport(text, scope: scope) ?? []
        }
    }

    /// Web results (Explore, board feeds, a pin's web feed, Quick Look).
    func importWeb(_ images: [WebImage], boardIDs: [UUID], hidden: Bool = false) {
        guard !images.isEmpty else { return }
        run(nothingText: images.count == 1 ? "This image couldn't be downloaded." : "None of those images could be downloaded.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            await store.prepareWebImports(images, scope: scope)
        }
    }

    /// A text pin typed in the editor (asks if the same text is already a pin).
    func importText(title: String, body: String, boardIDs: [UUID], hidden: Bool = false) {
        guard let pending = store.prepareTextImport(title: title, body: body, scope: store.importScope(boardIDs: boardIDs, hidden: hidden)) else { return }
        review([pending], boardIDs: boardIDs, hidden: hidden, profile: store.profileID, nothingText: "")
    }

    /// A photo just taken with the camera.
    func importCaptured(_ image: UIImage, boardIDs: [UUID], hidden: Bool = false) {
        let boxed = LoadedImage(image: image)
        run(nothingText: "The photo couldn't be saved.", boardIDs: boardIDs, hidden: hidden) { store, scope in
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                boxed.image?.jpegData(compressionQuality: 0.92)
            }.value
            guard let data else { return [] }
            return await store.prepareImports(dropped: [.image(data)], scope: scope)
        }
    }

    // The flow

    /// `prepare` gets the side of the library the items go to, so look-alikes are only looked for there.
    /// The batch belongs to the library in use when it starts (see `review`).
    private func run(nothingText: String, boardIDs: [UUID], hidden: Bool, _ prepare: @escaping @MainActor (LibraryStore, PinScope) async -> [PendingImport]) {
        let store = store
        let scope = store.importScope(boardIDs: boardIDs, hidden: hidden)
        let profile = store.profileID
        workingCount += 1
        Task { @MainActor in
            let pending = await prepare(store, scope)
            workingCount -= 1
            review(pending, boardIDs: boardIDs, hidden: hidden, profile: profile, nothingText: nothingText)
        }
    }

    /// Commits straight away when nothing looks familiar; otherwise starts the questions.
    /// Only pins on the side imported into are ever asked about (a hidden pin never
    /// shows up in a normal import's question, and the other way round).
    /// `profile`: the library the batch was read for. Another one open by now: dropped.
    private func review(_ pending: [PendingImport], boardIDs: [UUID], hidden: Bool, profile: UUID, nothingText: String) {
        let scope = store.importScope(boardIDs: boardIDs, hidden: hidden)
        guard store.profileID == profile else {
            ImportFlow.discardTemporaryFiles(of: pending)
            noteOtherProfile(scope: scope)
            return
        }
        guard !pending.isEmpty else {
            if !nothingText.isEmpty { presentSoon { $0.message = nothingText; $0.showMessage = true } }
            return
        }
        let checked = pending.map { item -> PendingImport in
            var item = item
            if let other = item.duplicateOf, !isOnSide(other, scope) { item.duplicateOf = nil }
            if let other = item.identicalTo, !isOnSide(other, scope) { item.identicalTo = nil }
            return item
        }
        let duplicates = checked.filter { $0.isDuplicate && $0.identicalTo == nil }.map { $0.id }
        if duplicates.isEmpty {
            commit(checked, boardIDs: boardIDs, hidden: hidden, skippedByChoice: 0)
        } else {
            let questions = Review(pending: checked, boardIDs: boardIDs, hidden: hidden, scope: scope, profileID: profile,
                                   duplicateIDs: duplicates)
            presentSoon { $0.show(questions) }
        }
    }

    /// Puts a batch's questions up — unless another profile was opened while they waited to
    /// appear (then the batch is dropped, see `dropQuestionsOfOtherProfile`).
    private func show(_ questions: Review) {
        guard questions.profileID == store.profileID else {
            drop(questions)
            noteOtherProfile(scope: questions.scope)
            return
        }
        review = questions
    }

    /// The pin still exists and is on this side of the library.
    private func isOnSide(_ pin: Pin, _ scope: PinScope) -> Bool {
        guard let current = store.livePin(pin.id) else { return false }
        return store.scope(of: current) == scope
    }

    /// The sheet or alert goes up a moment later, so whatever started the import
    /// (a picker, the link sheet, the camera) has finished closing first.
    private func presentSoon(_ change: @escaping @MainActor (ImportFlow) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self else { return }
            change(self)
        }
    }

    func decide(_ decision: Decision) {
        guard var current = review else { return }
        guard current.position < current.duplicateIDs.count || decision == .cancel else { return }
        switch decision {
        case .add:
            current.position += 1
        case .skip:
            current.skipped.insert(current.duplicateIDs[current.position])
            current.position += 1
        case .addExisting:
            current.addExisting.insert(current.duplicateIDs[current.position])
            current.position += 1
        case .addAllRemaining:
            current.position = current.duplicateIDs.count
        case .skipAllRemaining:
            for id in current.duplicateIDs[current.position...] { current.skipped.insert(id) }
            current.position = current.duplicateIDs.count
        case .addExistingAllRemaining:
            for id in current.duplicateIDs[current.position...] { current.addExisting.insert(id) }
            current.position = current.duplicateIDs.count
        case .cancel:
            review = nil
            drop(current)
            if current.folder != nil {
                // Nothing in the library or in the folder was changed. A folder import is a big
                // step, so a short note says so (a confirmation, not an alert to tap away).
                flash("Folder import cancelled. Nothing was changed.", symbol: "info.circle")
            }
            // Any other import: you chose Cancel yourself, so there is nothing to tell you.
            return
        }
        if current.position >= current.duplicateIDs.count {
            review = nil
            // Another profile was opened while the question was up: the batch is that library's.
            guard current.profileID == store.profileID else {
                drop(current)
                noteOtherProfile(scope: current.scope)
                return
            }
            let kept = current.pending.filter { !current.skipped.contains($0.id) }
            let addExisting = current.addExisting.subtracting(current.skipped)
            ImportFlow.discardTemporaryFiles(of: current.pending.filter { current.skipped.contains($0.id) })
            if let plan = current.folder {
                commitFolder(plan, keeping: kept, addExisting: addExisting, skippedByChoice: current.skipped.count)
            } else {
                commit(kept, boardIDs: current.boardIDs, hidden: current.hidden, addExisting: addExisting,
                       skippedByChoice: current.skipped.count)
            }
        } else {
            review = current
        }
    }

    /// Whether "Add the existing pin" makes sense for `item` of `review`, and to how many boards.
    func existingChoice(for item: PendingImport, in review: Review) -> ExistingChoice {
        guard item.landsOnBoard(batchBoardIDs: review.boardIDs),
              let twin = item.duplicateOf.flatMap({ store.livePin($0.id) }),
              store.scope(of: twin) == review.scope else { return .unavailable }
        // The boards the item would go on. A folder's board may not exist yet (then the
        // look-alike is certainly not on it).
        let destination: [UUID?]
        if let exported = item.exported {
            destination = exported.record.boardIDs.map { Optional($0) }
        } else if let path = item.destinationPath {
            destination = [store.board(forPath: path, createIfNeeded: false, visibleOnly: true)]
        } else {
            destination = review.boardIDs.map { Optional($0) }
        }
        let missing = destination.filter { id in id.map { !twin.isOn($0) } ?? true }
        return missing.isEmpty ? .alreadyThere : .available(boards: destination.count)
    }

    /// The sheet went away without an answer (it can't be swiped away, but the screen it was
    /// shown over can close): the same as Cancel — for the batch that sheet belonged to,
    /// never for a newer one.
    func reviewDismissed() {
        guard let review, review.id == presentedReviewID else { return }
        presentedReviewID = nil
        decide(.cancel)
    }

    /// Another profile was opened (in this window or another one) while a question was up: that
    /// batch was read for the other library — its look-alikes and boards are that library's — so
    /// it is dropped instead of waiting for an answer that would commit it here. The presenters
    /// call this when `store.profileID` changes; `decide` checks again before committing.
    func dropQuestionsOfOtherProfile() {
        guard let current = review, current.profileID != store.profileID else { return }
        review = nil
        drop(current)
        noteOtherProfile(scope: current.scope)
    }

    /// Drops a batch without importing anything: its temporary video copies go, and a folder
    /// import's access to its folder stops.
    private func drop(_ batch: Review) {
        ImportFlow.discardTemporaryFiles(of: batch.pending)
        if let plan = batch.folder { store.cancelFolderImport(plan) }
    }

    /// Says that an import was dropped because another profile was opened — only for the normal
    /// side (an import into Hidden is never mentioned where the normal side shows).
    private func noteOtherProfile(scope: PinScope) {
        guard scope == .visible else { return }
        flash("Import cancelled: another profile was opened.", symbol: "info.circle")
    }

    private func commit(_ pending: [PendingImport], boardIDs: [UUID], hidden: Bool, addExisting: Set<UUID> = [],
                        skippedByChoice: Int) {
        let store = store
        // Links whose video couldn't be downloaded were made into their picture or a plain link
        // (see SmartLinks.swift); the report says so, so a video never turns into a picture unnoticed.
        let lostVideos = ImportFlow.lostVideoCount(in: pending, addExisting: addExisting)
        workingCount += 1   // straight away, so "saving" spinners stay on across the hand-over
        Task { @MainActor in
            let summary = await store.commitImports(pending, boardIDs: boardIDs, skipDuplicates: false, hidden: hidden,
                                                    addExisting: addExisting)
            workingCount -= 1
            report(summary, skippedByChoice: skippedByChoice, boardIDs: boardIDs, hidden: hidden, lostVideos: lostVideos)
        }
    }

    /// How many of the batch's links lost their video. Only items that are saved as a new pin count:
    /// one that goes on the boards as the pin you already have ("Add the existing pin", or a card
    /// saved before) is not saved again, so there is nothing to say about it.
    nonisolated static func lostVideoCount(in pending: [PendingImport], addExisting: Set<UUID>) -> Int {
        pending.filter { (item: PendingImport) -> Bool in
            item.resolvedLink?.videoFailed == true && item.identicalTo == nil && !addExisting.contains(item.id)
        }.count
    }

    /// What the report adds when videos from links couldn't be downloaded (only for pins that were added).
    nonisolated static func lostVideosText(_ lostVideos: Int, imported: Int) -> String? {
        guard lostVideos > 0, imported > 0 else { return nil }
        if lostVideos == 1 { return "The video file couldn't be downloaded, so its link was saved instead." }
        return "\(lostVideos) videos couldn't be downloaded, so their links were saved instead."
    }

    /// Whether a report is only a confirmation (a toast) and not something worth an alert. Items you
    /// chose to skip are no surprise: "Skipped 1 duplicate." is a confirmation too. Something that
    /// couldn't be read (or nothing at all) is worth an alert — and so is a video that wasn't saved,
    /// because a confirmation is gone after three seconds.
    nonisolated static func isConfirmation(_ summary: ImportSummary, skippedByChoice: Int, lostVideosNote: String?) -> Bool {
        guard summary.skipped == 0, lostVideosNote == nil else { return false }
        return summary.imported > 0 || summary.alreadyHad > 0 || summary.addedExisting > 0 || skippedByChoice > 0
    }

    private func report(_ summary: ImportSummary, skippedByChoice: Int, boardIDs: [UUID], hidden: Bool, lostVideos: Int = 0) {
        var parts: [String] = []
        // A hidden board is never named: the message may outlast your visit to Hidden.
        let hiddenTarget = boardIDs.contains { store.isSecretBoard($0) }
        let boardNames = hiddenTarget ? "a hidden board" : boardIDs.compactMap { store.board($0)?.name }.joined(separator: ", ")
        let names = boardNames.isEmpty && hidden ? "Hidden" : boardNames
        if summary.imported > 0 {
            parts.append("Added \(summary.imported) pin\(summary.imported == 1 ? "" : "s")" + (names.isEmpty ? "." : " to \(names)."))
        }
        if summary.addedExisting > 0 {
            parts.append("Put \(summary.addedExisting) existing pin\(summary.addedExisting == 1 ? "" : "s") on "
                         + (boardNames.isEmpty ? "the board." : "\(boardNames)."))
        }
        if summary.alreadyHad > 0 {
            // Pins you already had are only put on the chosen boards (they are not moved into Hidden).
            parts.append(summary.alreadyHad == 1 ? "1 was already in your library" + (boardNames.isEmpty ? "." : " (now on \(boardNames) too).")
                                                 : "\(summary.alreadyHad) were already in your library" + (boardNames.isEmpty ? "." : " (now on \(boardNames) too)."))
        }
        if skippedByChoice > 0 {
            parts.append("Skipped \(skippedByChoice) duplicate\(skippedByChoice == 1 ? "" : "s").")
        }
        let lostNote = ImportFlow.lostVideosText(lostVideos, imported: summary.imported)
        if let lostNote { parts.append(lostNote) }
        // Skipped items are never handed to the store, so everything it skipped couldn't be read.
        let unreadable = summary.skipped
        if unreadable > 0 {
            parts.append("\(unreadable) couldn't be read.")
        }
        if parts.isEmpty { parts.append("Nothing was added.") }
        let text = parts.joined(separator: " ")
        let ordinary = ImportFlow.isConfirmation(summary, skippedByChoice: skippedByChoice, lostVideosNote: lostNote)
        // The checkmark when something was added or put on a board; the note symbol when nothing
        // was (every look-alike skipped, or it was all in the library already).
        let didSomething = summary.imported > 0 || summary.addedExisting > 0
            || (summary.alreadyHad > 0 && !boardIDs.isEmpty)
        if ordinary {
            flash(text, symbol: didSomething ? "checkmark.circle" : "info.circle")
        } else {
            presentSoon { $0.message = text; $0.showMessage = true }   // anything surprising is worth an alert
        }
    }

    // "Import a folder…" (Settings)

    /// Reads the folder, asks the same questions as every import, then commits. The result
    /// is always reported with an alert (a folder's summary is worth reading in full).
    func importFolder(_ folder: URL) {
        let store = store
        workingCount += 1
        Task { @MainActor in
            let plan = await store.prepareFolderImport(folder, scope: .visible)
            workingCount -= 1
            reviewFolder(plan)
        }
    }

    /// Like `review(...)`, for the items of a folder (always the normal side of the library).
    private func reviewFolder(_ plan: FolderImportPlan) {
        let profile = plan.profileID ?? store.profileID
        guard profile == store.profileID else {
            // Read for a library that is no longer open: nothing is imported here.
            store.cancelFolderImport(plan)
            ImportFlow.discardTemporaryFiles(of: plan.items)
            noteOtherProfile(scope: .visible)
            return
        }
        guard !plan.items.isEmpty || !plan.restoreIDs.isEmpty else {
            store.cancelFolderImport(plan)
            ImportFlow.discardTemporaryFiles(of: plan.items)
            var text = "Nothing to import in that folder."
            if plan.alreadyHere > 0 {
                text += plan.alreadyHere == 1 ? " 1 was already in your library." : " \(plan.alreadyHere) were already in your library."
            }
            if plan.unreadable > 0 { text += " \(plan.unreadable) couldn't be read." }
            presentSoon { $0.message = text; $0.showMessage = true }
            return
        }
        let checked = plan.items.map { item -> PendingImport in
            var item = item
            if let other = item.duplicateOf, !isOnSide(other, .visible) { item.duplicateOf = nil }
            if let other = item.identicalTo, !isOnSide(other, .visible) { item.identicalTo = nil }
            return item
        }
        let duplicates = checked.filter { $0.isDuplicate && $0.identicalTo == nil }.map { $0.id }
        if duplicates.isEmpty {
            commitFolder(plan, keeping: checked, addExisting: [], skippedByChoice: 0)
        } else {
            let questions = Review(pending: checked, boardIDs: [], hidden: false, scope: .visible, profileID: profile,
                                   duplicateIDs: duplicates, folder: plan)
            presentSoon { $0.show(questions) }
        }
    }

    private func commitFolder(_ plan: FolderImportPlan, keeping kept: [PendingImport], addExisting: Set<UUID>,
                              skippedByChoice: Int) {
        let store = store
        workingCount += 1
        Task { @MainActor in
            let summary = await store.commitFolderImport(plan, keeping: kept, addExisting: addExisting)
            workingCount -= 1
            reportFolder(summary, skippedByChoice: skippedByChoice)
        }
    }

    /// "Added 12 pins, created 3 boards. 2 were already in your library. Skipped 1 duplicate. 1 couldn't be read."
    private func reportFolder(_ summary: ImportSummary, skippedByChoice: Int) {
        var parts: [String] = []
        let added = "\(summary.imported) pin\(summary.imported == 1 ? "" : "s")"
        let created = "\(summary.boardsCreated) board\(summary.boardsCreated == 1 ? "" : "s")"
        if summary.imported > 0, summary.boardsCreated > 0 {
            parts.append("Added \(added), created \(created).")
        } else if summary.imported > 0 {
            parts.append("Added \(added).")
        } else if summary.boardsCreated > 0 {
            parts.append("Created \(created).")
        }
        if summary.addedExisting > 0 {
            parts.append("Put \(summary.addedExisting) existing pin\(summary.addedExisting == 1 ? "" : "s") on \(summary.addedExisting == 1 ? "its board" : "their boards").")
        }
        if summary.alreadyHad > 0 {
            parts.append(summary.alreadyHad == 1 ? "1 was already in your library." : "\(summary.alreadyHad) were already in your library.")
        }
        if skippedByChoice > 0 {
            parts.append("Skipped \(skippedByChoice) duplicate\(skippedByChoice == 1 ? "" : "s").")
        }
        if summary.skipped > 0 {
            parts.append("\(summary.skipped) couldn't be read.")
        }
        if parts.isEmpty { parts.append("Nothing was added.") }
        let text = parts.joined(separator: " ")
        presentSoon { $0.message = text; $0.showMessage = true }
    }

    /// The app is going to the background: a question about an import into Hidden is dropped,
    /// with that import, so it never comes up over the normal side once Hidden has locked.
    func dropHiddenQuestions() {
        guard let review, review.scope == .hidden else { return }
        decide(.cancel)
    }

    /// Takes the confirmation away at once (the app is going to the background).
    func clearToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    /// Shows a short confirmation over whatever screen is up. `symbol`: the SF Symbol shown
    /// next to it — the checkmark for something done, "info.circle" for a note or a hint
    /// (nothing was done), or another one for a failure.
    /// VoiceOver reads the text out as well, half a second later, so a menu that is still
    /// closing doesn't cut it off. If another confirmation has taken its place by then (or it
    /// was taken away), this one is not read out.
    func flash(_ text: String, symbol: String = "checkmark.circle") {
        toastTask?.cancel()
        toastSymbol = symbol
        toast = text
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }   // replaced or cleared meanwhile
            AccessibilityNotification.Announcement(text).post()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    nonisolated private static func discardTemporaryFiles(of pending: [PendingImport]) {
        for item in pending {
            if case .video(let url, _, _) = item.payload {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// The duplicate questions, the result alerts and the short confirmations. The questions and
/// results are attached at the root (active while no screen that shows them itself is up) and
/// inside Quick Look and Settings; the confirmations to each tab and, again, inside those two.
extension View {
    /// The app's root: import questions and results show here while neither Quick Look nor
    /// Settings is up (they show them themselves, see `importFlowCover()`). Confirmations
    /// show in each tab instead (see `confirmationToast()`).
    func importFlowRoot() -> some View {
        modifier(ImportFlowRoot())
    }

    /// A screen shown over the tabs that shows the flow itself (Quick Look, Settings): import
    /// questions, results and confirmations show over it while it is up. The flow keeps count
    /// of these screens by itself. `toastAboveControls`: the screen has its own controls along
    /// the bottom (Quick Look's video controls), so confirmations float higher.
    func importFlowCover(toastAboveControls: Bool = false) -> some View {
        modifier(ImportFlowCover(toastAboveControls: toastAboveControls))
    }

    /// A tab's root screen: short confirmations ("Added 3 pins to Travel.") float over it, a
    /// small gap above the bottom of its safe area. Apply it outside the tab's NavigationStack
    /// and inside the TabView: there the safe area already leaves out the tab bar wherever it
    /// sits (at the bottom on an iPhone and in a narrow iPad window, at the top on a wider
    /// iPad, at the side on other devices), the home indicator and the keyboard. So the
    /// confirmation never needs to know which device it is on, and pages pushed inside the
    /// tab get it too. It stays away while Quick Look or Settings is up (they show it).
    func confirmationToast() -> some View {
        modifier(ConfirmationToast())
    }
}

private struct ImportFlowRoot: ViewModifier {
    @EnvironmentObject private var importFlow: ImportFlow

    func body(content: Content) -> some View {
        content.modifier(ImportFlowPresenter(active: importFlow.coverDepth == 0, toastGap: nil))
    }
}

private struct ImportFlowCover: ViewModifier {
    @EnvironmentObject private var importFlow: ImportFlow
    var toastAboveControls: Bool = false

    func body(content: Content) -> some View {
        content
            .modifier(ImportFlowPresenter(active: true, toastGap: toastAboveControls ? 96 : 12))
            .onAppear { importFlow.coverDepth += 1 }
            .onDisappear { importFlow.coverDepth -= 1 }
    }
}

private struct ConfirmationToast: ViewModifier {
    @EnvironmentObject private var importFlow: ImportFlow

    func body(content: Content) -> some View {
        content.overlay {
            if importFlow.coverDepth == 0 {
                ToastOverlay(bottomGap: 12)
            }
        }
    }
}

/// Shows the flow's questions (a sheet), its results (an alert) and, on Quick Look and
/// Settings, its confirmations. It also notices another profile being opened (in any window):
/// a question about the old library's batch is then dropped (see `dropQuestionsOfOtherProfile`).
private struct ImportFlowPresenter: ViewModifier {
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var store: LibraryStore
    /// The look of the screen the questions show over (dark over Quick Look): the question sheet takes it.
    @Environment(\.colorScheme) private var colorScheme
    var active: Bool = true
    /// How far above the bottom of the safe area confirmations float. Nil: this presenter
    /// shows none (the root: each tab shows them, see `confirmationToast()`).
    var toastGap: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .overlay {
                if active, let toastGap { ToastOverlay(bottomGap: toastGap) }
            }
            .sheet(item: Binding(get: { active ? importFlow.review : nil },
                                 set: { importFlow.review = $0 }),
                   onDismiss: { importFlow.reviewDismissed() }) { review in
                ImportDuplicateSheet()
                    .onAppear { importFlow.presentedReviewID = review.id }
                    // A question about an import into Hidden shows a hidden pin: never in the App Switcher.
                    .hiddenPrivacyCover(review.scope == .hidden)
                    // Looks like the screen under it, its UIKit parts too (over Quick Look: dark).
                    .preferredColorScheme(colorScheme)
            }
            .alert(importFlow.message ?? "", isPresented: Binding(get: { active && importFlow.showMessage },
                                                                  set: { importFlow.showMessage = $0 })) {
                Button("OK", role: .cancel) { }
            }
            .onChange(of: store.profileID) {
                importFlow.dropQuestionsOfOtherProfile()
            }
    }
}

/// The flow's short confirmations, `bottomGap` points above the bottom of the safe area it is
/// placed in — the layout, not the device, decides where that is. Taps go through it.
private struct ToastOverlay: View {
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bottomGap: CGFloat

    var body: some View {
        VStack {
            if let toast = importFlow.toast {
                ToastCapsule(text: toast, symbol: importFlow.toastSymbol, accent: settings.accentColor)
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomGap)
                    .transition(appearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.25), value: importFlow.toast)
        .allowsHitTesting(false)
    }

    /// Slides up from the bottom while fading in; with Reduce Motion on, it only fades.
    private var appearance: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

/// One confirmation: its symbol and text on a rounded box. On iOS 26 the box is Liquid Glass,
/// like the system's own controls floating over the content (glass casts no shadow of its
/// own); before that, a frosted material with a soft shadow.
/// The box is a rounded rectangle, not a capsule: a capsule's round ends would cut into the
/// corners of a text that wraps onto two or three lines (large text sizes). A one-line
/// confirmation still looks almost like a capsule (its corners are about half its height).
private struct ToastCapsule: View {
    let text: String
    let symbol: String
    let accent: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        if #available(iOS 26, *) {
            label
                .glassEffect(.regular, in: shape)
        } else {
            label
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
            Text(text)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// "This looks like a pin you already have": the new item next to the old one.
struct ImportDuplicateSheet: View {
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                if let review = importFlow.review, let item = review.current {
                    question(review, item: item)
                        .padding()
                } else {
                    ProgressView().padding(40)
                }
            }
            .navigationTitle("Looks familiar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel import") { importFlow.decide(.cancel) }
                }
            }
        }
        .presentationDetents([.large])
        // A swipe down would cancel the whole import; "Cancel import" is the way out.
        .interactiveDismissDisabled()
    }

    /// One question: the new item next to the pin already here, the answers, and a note.
    /// (Split out of `body` so it type-checks quickly.)
    private func question(_ review: ImportFlow.Review, item: PendingImport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(heading(for: item))
                .font(.title3.weight(.semibold))
            if review.duplicateIDs.count > 1 {
                Text("Question \(review.position + 1) of \(review.duplicateIDs.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            comparison(review, item: item)
            choices(review: review, item: item)
            Text(footnote(for: review))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "New" beside "Already in your library". Only a pin on the side being imported into
    /// is shown (never one from across the hidden line).
    private func comparison(_ review: ImportFlow.Review, item: PendingImport) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                PendingPreview(item: item)
            }
            .frame(maxWidth: .infinity)
            if let existing = item.duplicateOf.flatMap({ store.livePin($0.id) }),
               store.scope(of: existing) == review.scope {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.scope == .hidden ? "Already in Hidden" : "Already in your library").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    PinCardView(pin: existing)
                    if !store.boardNames(for: existing).isEmpty {
                        Text("On: " + store.boardNames(for: existing).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The note under the answers.
    private func footnote(for review: ImportFlow.Review) -> String {
        let others = review.pending.count - review.duplicateIDs.count
        if others == 1 { return "The other 1 item is new and will be added." }
        if others > 1 { return "The other \(others) items are new and will be added." }
        return "Skipped items are not added. A pin you already have only changes if you add it to a board here."
    }

    /// The answers: save it as a new pin, put the pin you already have on the board(s)
    /// instead, or skip it — for this one, or for all the questions left.
    private func choices(review: ImportFlow.Review, item: PendingImport) -> some View {
        let existing = importFlow.existingChoice(for: item, in: review)
        return VStack(spacing: 8) {
            Button {
                importFlow.decide(.add)
            } label: {
                Text("Save as a new pin").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            existingButton(existing)
            Button {
                importFlow.decide(.skip)
            } label: {
                Text("Skip this one").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if review.remaining > 1 {
                allRemainingButtons(review: review)
            }
        }
    }

    @ViewBuilder
    private func existingButton(_ choice: ImportFlow.ExistingChoice) -> some View {
        switch choice {
        case .unavailable:
            EmptyView()
        case .available(let boards):
            Button {
                importFlow.decide(.addExisting)
            } label: {
                Text(boards > 1 ? "Add the existing pin to these boards" : "Add the existing pin to this board")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .alreadyThere:
            Text("The existing pin is already on this board.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func allRemainingButtons(review: ImportFlow.Review) -> some View {
        let left = review.remaining
        // "Add all existing" only when every question left has a board to put its pin on.
        let everyLandsOnBoard = review.remainingItems.allSatisfy { $0.landsOnBoard(batchBoardIDs: review.boardIDs) }
        return ViewThatFits(in: .horizontal) {
            HStack { allRemainingButtonRow(left: left, withExisting: everyLandsOnBoard) }
            VStack(spacing: 6) { allRemainingButtonRow(left: left, withExisting: everyLandsOnBoard) }
        }
    }

    @ViewBuilder
    private func allRemainingButtonRow(left: Int, withExisting: Bool) -> some View {
        Button("Save all \(left) as new") { importFlow.decide(.addAllRemaining) }
            .buttonStyle(.bordered)
            .controlSize(.small)
        if withExisting {
            Button("Add all \(left) existing") { importFlow.decide(.addExistingAllRemaining) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        Button("Skip all \(left)") { importFlow.decide(.skipAllRemaining) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func heading(for item: PendingImport) -> String {
        switch item.payload {
        case .image: return "This picture looks like one you already have"
        case .video: return "This video looks like one you already have"
        case .text: return "This text is already a pin"
        case .link: return "This link is already in your library"
        }
    }
}

/// A small rendering of something about to be imported.
private struct PendingPreview: View {
    @EnvironmentObject private var settings: AppSettings
    let item: PendingImport
    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            switch item.payload {
            case .image(let data, _, _, _):
                // A folder import leaves the picture in the folder (empty data + `sourceFile`).
                picture(data: data, file: data.isEmpty ? item.sourceFile : nil)
            case .video(_, let poster, _):
                picture(data: poster.jpegData, file: nil)
                    .overlay(alignment: .bottomLeading) {
                        Label(VideoTools.durationText(poster.duration) ?? "Video", systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
            case .text(let title, let body):
                TextCardView(pin: PendingPreview.textPin(title: title, body: body), style: settings.textStyle, color: settings.textPinColor)
            case .link(let url):
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    Text(url.absoluteString).font(.footnote).lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
            }
        }
    }

    private static func textPin(title: String, body: String) -> Pin {
        var pin = Pin()
        pin.kind = .text
        pin.title = title
        pin.textBody = body
        return pin
    }

    /// `file`: read the picture from there instead of `data` (off the main thread).
    private func picture(data: Data, file: URL?) -> some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(image.map { CardMetrics.clamped($0.size.width / max($0.size.height, 1)) } ?? 1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
            .task(id: item.id) {
                let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
                    let bytes = file.flatMap { try? Data(contentsOf: $0) } ?? data
                    guard let cg = ImageProcessor.downsample(bytes, maxPixelSize: 700) else { return LoadedImage(image: nil) }
                    return LoadedImage(image: UIImage(cgImage: cg))
                }.value
                image = loaded.image
            }
    }
}

// MARK: - The "+" menu (Photos, Camera, Files, Clipboard, Text, Link)

/// The flags behind the "+" menu. The menu sits in the toolbar; the pickers and
/// sheets it opens are attached to the screen's content (see `AddPinPresenters`).
@MainActor
final class AddPinFlags: ObservableObject {
    @Published var showPhotos = false
    @Published var showCamera = false
    @Published var showFiles = false
    @Published var showText = false
    @Published var showLink = false
    @Published var pickerItems: [PhotosPickerItem] = []
    /// Bumped when "Clipboard" is chosen; the presenter reacts.
    @Published var pasteRequested = 0
    @Published var message: String? = nil
    @Published var showMessage = false
}

struct AddPinMenu: View {
    @ObservedObject var flags: AddPinFlags
    @EnvironmentObject private var importFlow: ImportFlow

    var body: some View {
        Menu {
            Button {
                flags.showPhotos = true
            } label: {
                Label("Photos…", systemImage: "photo.on.rectangle")
            }
            Button {
                if CameraCaptureView.isAvailable {
                    flags.showCamera = true
                } else {
                    flags.message = "This device has no camera."
                    flags.showMessage = true
                }
            } label: {
                Label("Camera", systemImage: "camera")
            }
            Button {
                flags.showFiles = true
            } label: {
                Label("Files… (pictures, videos, text)", systemImage: "folder")
            }
            Button {
                flags.pasteRequested += 1
            } label: {
                Label("Clipboard (picture, text or link)", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button {
                flags.showText = true
            } label: {
                Label("Text pin", systemImage: "text.alignleft")
            }
            Button {
                flags.showLink = true
            } label: {
                Label("Link pin", systemImage: "link")
            }
        } label: {
            // While an import is working, a small spinner takes the "+"'s place, so an import
            // started here (on a board page too) shows its progress where it began.
            if importFlow.isWorking {
                ProgressView()
            } else {
                AddMenuLabel()
            }
        }
        .accessibilityLabel("Add")
        .accessibilityValue(importFlow.isWorking ? "Importing" : "")
    }
}

/// The pickers and sheets the "+" menu opens, attached to a screen's content.
/// `hidden`: what is added goes straight into the Hidden section.
struct AddPinPresenters: ViewModifier {
    @ObservedObject var flags: AddPinFlags
    let boardIDs: [UUID]
    var hidden: Bool = false
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    /// What is added here lands on the hidden side (Hidden's "+", or a hidden board's).
    @MainActor private var addsToHidden: Bool {
        store.importScope(boardIDs: boardIDs, hidden: hidden) == .hidden
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $flags.showPhotos, selection: $flags.pickerItems, maxSelectionCount: 100, matching: .any(of: [.images, .videos]))
            .onChange(of: flags.pickerItems) { _, items in
                guard !items.isEmpty else { return }
                flags.pickerItems = []
                importFlow.importPicked(items, boardIDs: boardIDs, hidden: hidden)
            }
            .onChange(of: flags.pasteRequested) {
                importFlow.importPasteboard(boardIDs: boardIDs, hidden: hidden)
            }
            .fullScreenCover(isPresented: $flags.showCamera) {
                CameraCaptureView(onCapture: { image in
                    importFlow.importCaptured(image, boardIDs: boardIDs, hidden: hidden)
                }, onFinish: {
                    flags.showCamera = false
                })
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $flags.showFiles, allowedContentTypes: [.image, .movie, .video, .plainText], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    importFlow.importFiles(urls, boardIDs: boardIDs, hidden: hidden)
                case .failure(let error):
                    flags.message = error.localizedDescription
                    flags.showMessage = true
                }
            }
            // What is typed for Hidden (its "+", a hidden board's) never shows in the App Switcher.
            .sheet(isPresented: $flags.showText) {
                TextPinEditorSheet(heading: "New text pin") { title, body in
                    importFlow.importText(title: title, body: body, boardIDs: boardIDs, hidden: hidden)
                }
                .hiddenPrivacyCover(addsToHidden)
            }
            .sheet(isPresented: $flags.showLink) {
                LinkPinEditorSheet { url in
                    importFlow.importLink(url, boardIDs: boardIDs, hidden: hidden)
                }
                .hiddenPrivacyCover(addsToHidden)
            }
            .alert(flags.message ?? "", isPresented: $flags.showMessage) {
                Button("OK", role: .cancel) { }
            }
    }
}
