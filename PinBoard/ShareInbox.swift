//
//  ShareInbox.swift  —  PinBoard
//
//  The app's side of the share sheet (the share extension in Xcode/PinBoardShare, and
//  ShareShared.swift for what the two share):
//    • ShareBoardListWriter writes the open profile's boards for the share sheet — never a hidden
//      board, nor one inside the Hidden section — at launch, a few seconds after a save and when
//      another profile is opened. With each board go what its "Suggested" needs: its name's words,
//      its pins' common tags and the sites they come from (never anything of a hidden pin). The
//      "Looks familiar" check's index is written at the same times (ShareFamiliar.swift).
//    • ShareInbox takes in what was shared: at launch, when the app comes back to the front, and
//      when the share sheet says it saved something (so an open PinBoard on iPad takes it in at
//      once). Each item goes through the same reading and saving as every other import, so links
//      get their preview, the AI tags the new pins and iCloud sync picks them up. The status line
//      counts: "Adding 3 of 12 shared items…".
//  A share made while another profile was open waits in the inbox until that profile is open
//  again (its board belongs to that library).
//

import Foundation
import UIKit

// MARK: - The board list for the share sheet

@MainActor
enum ShareBoardListWriter {
    /// What was written last for each profile, so an unchanged list is not written again after every save.
    private static var lastWritten: [UUID: Data] = [:]
    private static var lastProfiles: Data? = nil
    private static var pending: Task<Void, Never>? = nil
    /// How many tags of a board the share sheet gets (the most common ones).
    static let tagsPerBoard = 40

    /// Writes the list a few seconds after the last save (saves come in bursts while you work).
    static func writeSoon(store: LibraryStore, profiles: ProfileManager) {
        guard ShareShared.shareFolder != nil else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak store, weak profiles] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let store, let profiles else { return }
            write(store: store, profiles: profiles)
        }
    }

    /// Writes the board list of the library open now (only when it changed) into that profile's
    /// own folder, and the list of profiles. Every other profile keeps what was written while it
    /// was open (so the share sheet can save into any of them); a deleted profile's folder goes.
    static func write(store: LibraryStore, profiles: ProfileManager) {
        guard let file = ShareShared.boardListFile(for: store.profileID) else { return }   // no App Group
        writeProfiles(profiles, current: store.profileID)
        writeSettings(profile: store.profileID)
        ShareFamiliarWriter.write(store: store)   // and what "Looks familiar" compares with (ShareFamiliar.swift)
        // In the app's own order (the one its board pickers use): favorites first at every level,
        // then the sort chosen on the Boards page (your own order, A–Z, recently edited or added),
        // each sub-board right after its parent. The share sheet keeps this order as it is.
        let rows = store.boardRows(scope: .visible, sort: AppSettings.shared.boardSort)
        var boards = rows.map { (row: BoardRow) -> ShareBoardList.Board in
            ShareBoardList.Board(id: row.board.id, name: row.board.name, parentID: row.board.parentID, depth: row.depth,
                                 pinCount: store.pinCount(in: row.board.id))
        }
        // The normal side's rows never hold a hidden board (nor one inside the Hidden section);
        // this second look makes sure no hidden board can ever reach the share sheet.
        let secret = store.hiddenBoardIDs
        boards = boards.filter { (board: ShareBoardList.Board) -> Bool in !secret.contains(board.id) }
        addSuggestionSignals(to: &boards, store: store)
        let profile = profiles.profiles.first { (each: Profile) -> Bool in each.id == store.profileID }
        let list = ShareBoardList(profileID: store.profileID, profileName: profile?.name ?? "",
                                  profileCount: profiles.profiles.count, boards: boards)
        guard let data = try? JSONEncoder().encode(list), data != lastWritten[store.profileID] else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: file, options: .atomic)) != nil { lastWritten[store.profileID] = data }
    }

    /// The settings the share sheet follows for this profile (only when changed).
    private static func writeSettings(profile: UUID) {
        guard let file = ShareShared.settingsFile(for: profile) else { return }
        let settings = ShareProfileSettings(chooseBoard: AppSettings.shared.chooseBoardWhenSharing)
        guard ShareShared.readProfileSettings(profile: profile) != settings, let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The profiles (names as in Settings › Library › Profiles) and which one is open. Folders of profiles
    /// that no longer exist go, and so do the files of the first share sheet (one library only).
    private static func writeProfiles(_ profiles: ProfileManager, current: UUID) {
        guard let folder = ShareShared.shareFolder, let file = ShareShared.profilesFile else { return }
        let list = ShareProfiles(profiles: profiles.profiles.map { ShareProfiles.Profile(id: $0.id, name: $0.name) },
                                 current: current)
        guard let data = try? JSONEncoder().encode(list), data != lastProfiles else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        lastProfiles = data
        let known = Set(list.profiles.map { $0.id.uuidString })
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let isOld = ["boards.json", "familiar.json", "thumbs"].contains(name)
            let isGoneProfile = UUID(uuidString: name) != nil && !known.contains(name)
            if isOld || isGoneProfile { try? manager.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }

    /// What "Suggested" compares with, for each board — the signals of the app's own suggestions
    /// (`LibraryStore.scoreBoards`): the name's words, and the tags of the pins on the board. In place
    /// of the app's look-alike check (the share sheet can't compare pictures with the library) it
    /// gets the sites the board's pins come from. Only normal pins count: never a hidden one.
    private static func addSuggestionSignals(to boards: inout [ShareBoardList.Board], store: LibraryStore) {
        let visible = Set(store.visiblePins.map { (pin: Pin) -> UUID in pin.id })
        let membership = store.membership
        for index in boards.indices {
            let id = boards[index].id
            boards[index].nameWords = nameWords(of: id, store: store)
            let members = (membership[id] ?? []).filter { visible.contains($0) }.compactMap { store.livePin($0) }
            guard !members.isEmpty else { continue }
            boards[index].tags = tagShares(of: members)
            boards[index].sites = siteShares(of: members)
        }
    }

    /// The board's name words (1) and its parents' (0.6), in their base form ("Beaches" → "beach").
    private static func nameWords(of id: UUID, store: LibraryStore) -> [String: Double] {
        var words: [String: Double] = [:]
        let path = store.path(to: id)
        for (index, board) in path.enumerated() {
            let weight = index == path.count - 1 ? 1.0 : 0.6
            for word in SemanticMatcher.tokenize(board.name) where !SemanticMatcher.stopWords.contains(word) {
                let lemma = SemanticMatcher.lemmatize(word)
                words[lemma] = max(words[lemma] ?? 0, weight)
            }
        }
        return words
    }

    /// Each tag's share of the pins (as the app counts them: the AI's fairly sure tags, your own
    /// tags, words read in the picture, keywords in the file), the most common ones only.
    private static func tagShares(of members: [Pin]) -> [String: Double] {
        var counts: [String: Int] = [:]
        for pin in members {
            var seen: Set<String> = []
            for tag in pin.aiTags where tag.confidence > 0.3 { seen.insert(tag.label) }
            for tag in pin.tags + pin.ocrTags + pin.fileKeywords { seen.insert(tag.lowercased()) }
            for tag in seen { counts[tag, default: 0] += 1 }
        }
        let common = counts.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }.prefix(tagsPerBoard)
        return shares(Array(common), of: members.count)
    }

    /// Each site's share of the pins (a link pin's page, a web picture's page).
    private static func siteShares(of members: [Pin]) -> [String: Double] {
        var counts: [String: Int] = [:]
        for pin in members {
            guard let address = pin.linkURL ?? pin.sourceURL, let site = ShareBoardList.site(of: address) else { continue }
            counts[site, default: 0] += 1
        }
        let common = counts.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }.prefix(20)
        return shares(Array(common), of: members.count)
    }

    /// Counts → shares of `total`, rounded (so an unchanged board writes the same file).
    private static func shares(_ counts: [(key: String, value: Int)], of total: Int) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, count) in counts {
            result[key] = (Double(count) / Double(max(total, 1)) * 100).rounded() / 100
        }
        return result
    }
}

// MARK: - Taking in the inbox

@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()

    /// Shared items waiting for a profile that isn't open, by profile (Settings › Library › Profiles says so
    /// on that profile's row). They are taken in when that profile is opened: adding them now would
    /// need a second library store with another profile's settings, which could mix the two.
    @Published private(set) var waiting: [UUID: Int] = [:]
    /// What the last note about waiting items said (so it isn't repeated at every return).
    private var toldWaiting: [UUID: Int] = [:]

    /// An inbox folder with its share description.
    struct Found: Sendable {
        var folder: URL
        var entry: ShareInboxEntry
    }

    /// What one take-in did, for the confirmation at the end.
    private struct Tally {
        var added = 0
        var alreadyHad = 0
        var addedExisting = 0   // "Add the existing pin" chosen in the share sheet
        var skippedByChoice = 0 // "Skip this one" chosen there
        var unreadable = 0
        var boards: Set<UUID?> = []
        var anyHidden = false
    }

    private var running = false
    private var again = false
    private var listening = false
    /// The window whose confirmations show the result (the last one that asked).
    private weak var flow: ImportFlow? = nil

    /// Listens for the share sheet's "I saved something" (once per launch).
    func listen() {
        guard !listening, ShareShared.groupFolder != nil else { return }
        listening = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
            Task { @MainActor in ShareInbox.shared.takeIn(flow: nil) }
        }, ShareShared.inboxChangedNotice as CFString, nil, .deliverImmediately)
    }

    /// Takes in what the share sheet left. While a take-in is going, a new call only asks it to
    /// look once more when it is done (so nothing is taken in twice).
    func takeIn(flow: ImportFlow?) {
        if let flow { self.flow = flow }
        guard ShareShared.inboxFolder != nil else { return }
        if running {
            again = true
            return
        }
        running = true
        Task { @MainActor in
            repeat {
                again = false
                await run()
            } while again
            running = false
        }
    }

    private func run() async {
        guard let inbox = ShareShared.inboxFolder else { return }
        let services = AppServices.shared
        let store = services.store
        let profile = store.profileID
        let known = Set(services.profiles.profiles.map { (each: Profile) -> UUID in each.id })
        let everything = await Task.detached(priority: .utility) { ShareInbox.readEntries(in: inbox) }.value
        // This profile's shares, and those made before PinBoard wrote a board list (or for a
        // profile that was deleted since). Another profile's wait until it is open.
        let mine = everything.filter { (found: Found) -> Bool in
            guard let owner = found.entry.profileID else { return true }
            return owner == profile || !known.contains(owner)
        }
        noteWaiting(everything, current: profile, known: known)
        guard !mine.isEmpty else {
            reportWaiting(store: store, alone: true)
            return
        }
        let total = mine.reduce(0) { (sum: Int, found: Found) -> Int in sum + found.entry.items.count }
        store.beginLibraryWork()   // the profile isn't switched while this goes on
        defer { store.endLibraryWork() }
        var tally = Tally()
        var done = 0
        var finishedAll = true
        for found in mine {
            let finished = await takeIn(found, store: store, profile: profile, done: &done, total: total, tally: &tally)
            if !finished {   // another profile is open now: the rest waits
                finishedAll = false
                break
            }
        }
        store.setImportStatus(nil, scope: .visible)
        if finishedAll {
            // The boards made in the share sheet are real boards now (in the board list written next).
            if let file = ShareShared.newBoardsFile(for: profile) { try? FileManager.default.removeItem(at: file) }
            ShareBoardListWriter.write(store: store, profiles: services.profiles)
        }
        report(tally, store: store)
        reportWaiting(store: store, alone: false)
    }

    /// Counts the items waiting for profiles that aren't open.
    private func noteWaiting(_ everything: [Found], current: UUID, known: Set<UUID>) {
        var counts: [UUID: Int] = [:]
        for found in everything {
            guard let owner = found.entry.profileID, owner != current, known.contains(owner) else { continue }
            counts[owner, default: 0] += found.entry.items.count
        }
        waiting = counts
    }

    /// "2 shared items are waiting for “Work”. Open that profile to add them." — once for each new
    /// count (not again at every return to the app). `alone`: nothing else was said this time.
    private func reportWaiting(store: LibraryStore, alone: Bool) {
        guard let flow, waiting != toldWaiting else { return }
        let names = AppServices.shared.profiles.profiles
        var parts: [String] = []
        for (id, count) in waiting.sorted(by: { $0.key.uuidString < $1.key.uuidString }) where (toldWaiting[id] ?? 0) < count {
            guard let name = names.first(where: { $0.id == id })?.name else { continue }
            let items = count == 1 ? "1 shared item is" : "\(count) shared items are"
            parts.append("\(items) waiting for “\(name)”. Open that profile to add \(count == 1 ? "it" : "them").")
        }
        toldWaiting = waiting
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: " ")
        if alone || flow.toast == nil {
            flow.flash(text, symbol: "tray.full")
        } else {
            Task { @MainActor [weak flow] in
                try? await Task.sleep(nanoseconds: 3_600_000_000)   // after the take-in's own confirmation
                flow?.flash(text, symbol: "tray.full")
            }
        }
    }

    /// Takes in one share, item by item. Each item is crossed off the share's description as soon
    /// as it is in, so an interrupted take-in never adds anything twice. false: another profile
    /// was opened meanwhile (what is left stays in the inbox).
    private func takeIn(_ found: Found, store: LibraryStore, profile: UUID, done: inout Int, total: Int,
                        tally: inout Tally) async -> Bool {
        var entry = found.entry
        // Boards made in the share sheet are made now (or found, if made before), so its board id
        // may stand for a board that exists only from here on.
        let made = makeNewBoards(entry, store: store, profile: profile)
        // The board is this library's only if the share was made for it (a board that is gone: Unsorted).
        var boardIDs: [UUID] = []
        let chosen = entry.boardID.map { made[$0] ?? $0 }
        if let board = chosen, entry.profileID == profile, store.board(board) != nil { boardIDs = [board] }
        let scope = store.importScope(boardIDs: boardIDs, hidden: false)
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        while let item = entry.items.first {
            done += 1
            let plural = total == 1 ? "" : "s"
            store.setImportStatus("Adding \(done) of \(total) shared item\(plural)…", scope: scope)
            // What was chosen in the share sheet about a look-alike: skip it, or put the pin you
            // already have on the board — carried out here, without reading the item at all.
            if let handled = carryOutChoice(item, boardIDs: boardIDs, store: store, scope: scope, tally: &tally) {
                if handled {
                    entry.items.removeFirst()
                    let left = entry
                    let folder = found.folder
                    await Task.detached(priority: .utility) { ShareInbox.crossOff(item, leaving: left, in: folder) }.value
                    continue
                }
            }
            let pending = await prepare(item, in: found.folder, store: store, scope: scope)
            guard store.isCurrentProfile(profile) else {
                LibraryStore.discardTemporaryCopies(of: pending)
                return false
            }
            // The same link or text is already a pin: that pin goes on the board (no second copy) —
            // unless "Save as a new pin" was chosen in the share sheet.
            let savesNew = item.choice == .saveNew
            let existing = savesNew ? [] : pending.filter { (each: PendingImport) -> Bool in ShareInbox.usesExistingPin(each) }
            let summary = await store.commitImports(pending, boardIDs: boardIDs, skipDuplicates: false,
                                                    addExisting: Set(existing.map { $0.id }), keepsStatus: true)
            guard store.isCurrentProfile(profile) else { return false }
            if !note.isEmpty {
                for id in summary.newPinIDs { store.setNote(note, for: id) }
            }
            if scope == .hidden {
                tally.anyHidden = true
            } else {
                tally.added += summary.imported
                tally.alreadyHad += summary.alreadyHad + summary.addedExisting
                tally.unreadable += pending.isEmpty ? 1 : summary.skipped
                tally.boards.insert(boardIDs.first)
            }
            entry.items.removeFirst()
            let left = entry
            let folder = found.folder
            await Task.detached(priority: .utility) { ShareInbox.crossOff(item, leaving: left, in: folder) }.value
        }
        return true
    }

    /// Makes the boards a share made in the share sheet, outermost first: a normal board with the
    /// same name in the same place (capitals and accents don't count) is used instead, so a board
    /// two shares made before PinBoard opened is made once. Never a hidden board: one whose parent
    /// is hidden (or gone) by now is made at the top level instead. Returns stand-in id → board.
    private func makeNewBoards(_ entry: ShareInboxEntry, store: LibraryStore, profile: UUID) -> [UUID: UUID] {
        var made: [UUID: UUID] = [:]
        guard entry.profileID == profile, let wanted = entry.newBoards else { return made }
        for new in wanted {
            var parent = new.parentID.map { made[$0] ?? $0 }
            if let id = parent, store.board(id) == nil || store.isSecretBoard(id) { parent = nil }
            let siblings = store.children(of: parent).filter { (board: Board) -> Bool in !store.isSecretBoard(board.id) }
            if let same = siblings.first(where: { (board: Board) -> Bool in BoardPickerSheet.name(board.name, isSameAs: new.name) }) {
                made[new.id] = same.id
            } else if let board = store.addBoard(name: new.name, parentID: parent) {
                made[new.id] = board.id
            }
        }
        // The share sheet's "Last used" may be one of these: it now names the real board.
        if let last = ShareShared.readLastBoard(profile: profile), let real = made[last] {
            ShareShared.writeLastBoard(real, profile: profile)
        }
        return made
    }

    /// Carries out "Skip this one" or "Add the existing pin" from the share sheet (the merge the
    /// app's own import does: the pin you have is put on the board, `addPins`). nil: nothing to do
    /// here (no choice, or "Save as a new pin"); true: done; false: the existing pin is gone or
    /// hidden by now, so the item is saved as new after all.
    private func carryOutChoice(_ item: ShareInboxEntry.Item, boardIDs: [UUID], store: LibraryStore, scope: PinScope,
                                tally: inout Tally) -> Bool? {
        guard let choice = item.choice, choice != .saveNew else { return nil }
        if choice == .skip {
            if scope == .visible { tally.skippedByChoice += 1 }
            return true
        }
        guard let id = item.existingPinID, let pin = store.livePin(id), !store.isHidden(pin) else { return false }
        for board in boardIDs where !pin.isOn(board) { store.addPins([id], to: board) }
        guard scope == .visible else { return true }
        if boardIDs.isEmpty {
            tally.alreadyHad += 1   // no board chosen: the pin you have simply stays as it is
        } else {
            tally.addedExisting += 1
            tally.boards.insert(boardIDs.first)
        }
        return true
    }

    /// One shared thing → what the import reads from it (nothing: it couldn't be read).
    private func prepare(_ item: ShareInboxEntry.Item, in folder: URL, store: LibraryStore,
                         scope: PinScope) async -> [PendingImport] {
        let file = item.file.map { folder.appendingPathComponent($0) }
        let title = ShareInbox.title(fromFileName: item.name, store: store)
        switch item.kind {
        case .picture, .gif:
            // An animated GIF becomes a video pin here, as every other import does (AnimatedGIF.swift).
            guard let file, let data = await LibraryStore.readFile(file) else { return [] }
            return [await store.prepareImage(data, title: title, sourceURL: nil, credit: nil, scope: scope)]
        case .video:
            // The import owns (and finally deletes) its copy; the inbox's file goes when crossed off.
            guard let file else { return [] }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-\(UUID().uuidString).\(file.pathExtension)")
            guard await LibraryStore.copyFile(from: file, to: copy) else { return [] }
            return await store.prepareVideo(at: copy, title: title, scope: scope)
        case .link:
            guard let text = item.url, let url = LibraryStore.linkURL(in: text) else { return [] }
            return await store.prepareLinkSmart(url, scope: scope)
        case .text:
            let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            if let url = LibraryStore.linkURL(in: text) { return await store.prepareLinkSmart(url, scope: scope) }
            return [store.prepareText(title: "", body: text, scope: scope)]
        }
    }

    /// A link or a text that is already a pin (the same address, the same words).
    nonisolated static func usesExistingPin(_ item: PendingImport) -> Bool {
        guard item.duplicateOf != nil else { return false }
        switch item.payload {
        case .link, .text: return true
        case .image, .video: return false
        }
    }

    /// A shared file's name as a title — not a camera's name (IMG_1234) or the name Photos gives
    /// an edited picture ("FullSizeRender").
    private static func title(fromFileName name: String?, store: LibraryStore) -> String {
        guard let name, !name.lowercased().hasPrefix("fullsizerender") else { return "" }
        return store.cleanFileName(name)
    }

    /// "Added 3 shared items to Travel." The normal side's confirmation only: a share that went
    /// to a board that has been hidden since is never mentioned.
    private func report(_ tally: Tally, store: LibraryStore) {
        guard let flow else { return }
        var parts: [String] = []
        if tally.added > 0 {
            let what = tally.added == 1 ? "1 shared item" : "\(tally.added) shared items"
            var board = ""
            if tally.boards.count == 1, let only = tally.boards.first, let id = only, let found = store.board(id) {
                board = " to \(found.name)"
            }
            parts.append("Added \(what)\(board).")
        }
        if tally.addedExisting > 0 {
            let pins = tally.addedExisting == 1 ? "1 existing pin" : "\(tally.addedExisting) existing pins"
            var board = "their boards"
            if tally.boards.count == 1, let only = tally.boards.first, let id = only, let found = store.board(id) { board = found.name }
            parts.append("Put \(pins) on \(board).")
        }
        if tally.skippedByChoice > 0 {
            parts.append("Skipped \(tally.skippedByChoice) duplicate\(tally.skippedByChoice == 1 ? "" : "s").")
        }
        if tally.alreadyHad > 0 {
            parts.append(tally.alreadyHad == 1 ? "1 was already in your library." : "\(tally.alreadyHad) were already in your library.")
        }
        if tally.unreadable > 0 {
            parts.append(tally.unreadable == 1 ? "1 couldn't be read." : "\(tally.unreadable) couldn't be read.")
        }
        guard !parts.isEmpty else { return }
        let nothingNew = tally.added == 0 && tally.addedExisting == 0
        flow.flash(parts.joined(separator: " "), symbol: nothingNew ? "info.circle" : "checkmark.circle")
    }

    // MARK: The inbox's files (off the main thread)

    /// Every finished share in the inbox, oldest first. Unfinished folders (a share sheet that was
    /// closed by the system halfway) are cleared after a day; unreadable descriptions are cleared.
    nonisolated static func readEntries(in inbox: URL) -> [Found] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let folders = try? manager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: keys) else { return [] }
        var found: [Found] = []
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        for folder in folders {
            let name = folder.lastPathComponent
            if name.hasPrefix(ShareShared.unfinishedPrefix) {
                let changed = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let changed, changed < dayAgo { try? manager.removeItem(at: folder) }
                continue
            }
            if name.hasPrefix(".") { continue }
            let file = folder.appendingPathComponent(ShareShared.entryFileName)
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(ShareInboxEntry.self, from: data), !entry.items.isEmpty else {
                try? manager.removeItem(at: folder)
                continue
            }
            found.append(Found(folder: folder, entry: entry))
        }
        return found.sorted { (a: Found, b: Found) -> Bool in a.entry.date < b.entry.date }
    }

    /// An item is in the library: its file goes, and the description keeps only what is left
    /// (the whole folder goes with the last item).
    nonisolated static func crossOff(_ item: ShareInboxEntry.Item, leaving entry: ShareInboxEntry, in folder: URL) {
        let manager = FileManager.default
        if entry.items.isEmpty {
            try? manager.removeItem(at: folder)
            return
        }
        if let file = item.file { try? manager.removeItem(at: folder.appendingPathComponent(file)) }
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: folder.appendingPathComponent(ShareShared.entryFileName), options: .atomic)
        }
    }
}
