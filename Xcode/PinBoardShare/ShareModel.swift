//
//  ShareModel.swift  —  PinBoard share extension
//
//  What the share sheet holds while it is open: the shared things (copied into an unfinished
//  inbox folder as they are read), the profile (library) they go to — the one open in PinBoard to
//  begin with — and that profile's boards, the boards suggested and the look-alikes found there,
//  the board chosen (always "No board" to begin with), boards made here, the note typed. Save
//  finishes the folder and tells PinBoard; Cancel throws the folder away.
//

import Foundation
import UIKit
import ImageIO

@MainActor
final class ShareModel: ObservableObject {
    /// One shared thing with its preview picture.
    struct Shown: Identifiable {
        var item: ShareInboxEntry.Item
        var thumbnail: UIImage? = nil
        var id: UUID { item.id }
    }

    enum Phase: Equatable {
        case loading(String)   // what it is reading ("Getting 2 of 5…")
        case ready
        case nothing           // nothing shared is something PinBoard can keep
        case failed            // the inbox couldn't be written
        case saved(title: String, text: String)   // said for a moment, then closed (quick save, another profile)
    }

    @Published var phase: Phase = .loading("Getting ready…")
    @Published var shown: [Shown] = []
    @Published var boardID: UUID? = nil {
        didSet {
            // "Add the existing pin to this board" needs a board: without one it goes back to the
            // first answer, as the app offers it only for an item that lands on a board.
            guard boardID == nil else { return }
            for (id, choice) in choices where choice == .addExisting { choices[id] = .saveNew }
        }
    }
    @Published var note = ""
    /// Up to 3 boards the first shared thing fits (ShareSuggester.swift); empty: nothing fits.
    @Published var suggestions: [ShareSuggestion] = []
    /// Shared things that look like pins you already have (ShareFamiliarCheck.swift), by item id.
    @Published var familiar: [UUID: FamiliarMatch] = [:]
    /// What to do with each look-alike (default "Save as a new pin"), by item id.
    @Published var choices: [UUID: ShareChoice] = [:]
    /// The tiny pictures of the pins they look like, by pin id.
    @Published var existingThumbs: [UUID: UIImage] = [:]

    /// The profiles (nil: PinBoard hasn't written the list yet — an older PinBoard, or not opened).
    let profiles: ShareProfiles?
    /// The profile the share goes to (nil: no profile list; the share goes to whichever is open).
    @Published private(set) var profileID: UUID? = nil
    /// That profile's boards in the app's order, with boards made in the share sheet that PinBoard
    /// hasn't made yet (nil: none written for it yet — it hasn't been open since this update).
    @Published private(set) var boardList: ShareBoardList? = nil
    /// Boards made in this sheet (kept only if the share is saved onto one of them).
    private var madeHere: [ShareNewBoard] = []
    /// Boards made in earlier shares that PinBoard hasn't made yet.
    private var madeBefore: [ShareNewBoard] = []
    private var pageTitle: String? = nil
    /// The board the last share of this profile went to: only for the "Last used" row (a share
    /// always starts on "No board").
    @Published private(set) var lastUsedID: UUID? = nil
    /// Settings › Pins & boards › "Choose a board when sharing" is off for the open profile: the
    /// share goes straight to no board there, asking only about a look-alike.
    let quickSave: Bool
    private var stagingReady = false
    /// Called when the sheet should close (true: saved).
    var finish: (Bool) -> Void = { _ in }

    private let entryID = UUID()
    private let staging: URL?
    private let finished: URL?

    init() {
        profiles = ShareShared.readProfiles()
        quickSave = profiles.flatMap { ShareShared.readProfileSettings(profile: $0.current) }.map { !$0.chooseBoard } ?? false
        let inbox = ShareShared.inboxFolder
        staging = inbox?.appendingPathComponent(ShareShared.unfinishedPrefix + entryID.uuidString, isDirectory: true)
        finished = inbox?.appendingPathComponent(entryID.uuidString, isDirectory: true)
        if let current = profiles?.current { useProfile(current) }
    }

    // MARK: Profiles

    /// More than one profile: the sheet shows a "Profile" row.
    var showsProfiles: Bool { (profiles?.profiles.count ?? 0) > 1 }

    /// The name of the profile chosen ("" when unknown).
    var profileName: String {
        guard let profileID else { return "" }
        return profiles?.profiles.first { $0.id == profileID }?.name ?? ""
    }

    /// The chosen profile is the one open in PinBoard (its shares are taken in at once).
    var isOpenProfile: Bool { profileID == nil || profileID == profiles?.current }

    /// Another profile: everything that depends on the library is swapped — its boards (in its
    /// order, its hidden ones never listed), what is suggested, the look-alikes — and the board
    /// goes back to "No board".
    func chooseProfile(_ id: UUID) {
        guard id != profileID else { return }
        useProfile(id)
        boardID = nil
        madeHere = []
        familiar = [:]
        choices = [:]
        existingThumbs = [:]
        suggestions = []
        guard stagingReady, let staging else { return }
        Task { @MainActor in
            await checkFamiliar(in: staging)
            await suggestBoards(in: staging, pageTitle: pageTitle)
        }
    }

    private func useProfile(_ id: UUID) {
        profileID = id
        madeBefore = ShareShared.readNewBoards(profile: id)
        lastUsedID = ShareShared.readLastBoard(profile: id)
        rebuildBoardList()
    }

    /// The "Last used" board, if it is still among this profile's boards.
    var lastUsedBoard: ShareBoardList.Board? {
        guard let lastUsedID else { return nil }
        return boardList?.boards.first { $0.id == lastUsedID }
    }

    /// The written board list with the boards made in the share sheet added where they go (a board
    /// PinBoard has made by now, same name in the same place, isn't added twice).
    private func rebuildBoardList() {
        guard let profileID else {
            boardList = nil
            return
        }
        let written = ShareShared.readBoardList(profile: profileID)
        var list = written ?? ShareBoardList(profileID: profileID, profileName: profileName,
                                             profileCount: profiles?.profiles.count ?? 1, boards: [])
        for new in madeBefore + madeHere {
            ShareModel.insert(new, into: &list.boards)
        }
        hasWrittenList = written != nil
        boardList = list
    }

    /// PinBoard has written this profile's boards (false: it hasn't been open since this update).
    @Published private(set) var hasWrittenList = false

    /// Puts a board made in the share sheet after its parent's other sub-boards (or at the end).
    private static func insert(_ new: ShareNewBoard, into boards: inout [ShareBoardList.Board]) {
        let isThere = boards.contains { (board: ShareBoardList.Board) -> Bool in
            board.id == new.id || (board.parentID == new.parentID && ShareModel.sameName(board.name, new.name))
        }
        guard !isThere else { return }
        var depth = 0
        var at = boards.count
        if let parent = new.parentID {
            guard let index = boards.firstIndex(where: { $0.id == parent }) else { return }
            depth = boards[index].depth + 1
            at = index + 1
            while at < boards.count, boards[at].depth >= depth { at += 1 }
        }
        boards.insert(ShareBoardList.Board(id: new.id, name: new.name, parentID: new.parentID, depth: depth), at: at)
    }

    // MARK: New boards

    /// A new board (inside `parent`, or at the top): listed and chosen at once. PinBoard makes it
    /// when it takes the share in (never a hidden one: the share sheet never lists those).
    @discardableResult
    func makeBoard(named name: String, inside parent: UUID?) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profileID != nil else { return nil }
        let new = ShareNewBoard(id: UUID(), name: trimmed, parentID: parent)
        madeHere.append(new)
        rebuildBoardList()
        boardID = new.id
        return new.id
    }

    /// A board of this profile whose name is `words`, capitals and accents aside (no duplicate is offered).
    func existingBoard(named words: String) -> ShareBoardList.Board? {
        guard !words.isEmpty else { return nil }
        return boardList?.boards.first { (board: ShareBoardList.Board) -> Bool in ShareModel.sameName(board.name, words) }
    }

    /// Whether two board names are the same, ignoring capitals and accents ("cafe" = "Café"), as the app does.
    nonisolated static func sameName(_ name: String, _ other: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(other.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// The boards made in the share sheet that the chosen board needs (itself and new parents), outermost first.
    private func newBoardsNeeded() -> [ShareNewBoard] {
        let made = madeBefore + madeHere
        var chain: [ShareNewBoard] = []
        var next = boardID
        while let id = next, let new = made.first(where: { $0.id == id }), chain.count < 30 {
            chain.insert(new, at: 0)
            next = new.parentID
        }
        return chain
    }

    var canSave: Bool { phase == .ready && !shown.isEmpty }

    /// Saved for a profile that isn't open (the sheet says so for a moment, then closes).
    var isSaved: Bool {
        if case .saved = phase { return true }
        return false
    }

    /// Reads every shared thing, one at a time (so little memory is used at once). `pageTitle`: the
    /// title the other app gave what it shares (Safari: the page's), which helps the suggestions.
    func load(_ providers: [NSItemProvider], pageTitle: String?) async {
        guard let staging else {
            phase = .failed
            return
        }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            phase = .failed
            return
        }
        for (index, provider) in providers.enumerated() {
            if providers.count > 1 { phase = .loading("Getting \(index + 1) of \(providers.count)…") }
            if let item = await ShareLoader.load(provider, into: staging) { shown.append(Shown(item: item)) }
        }
        dropRepeats()
        self.pageTitle = pageTitle
        stagingReady = true
        if quickSave, !shown.isEmpty {
            // Quick save: no board, the open profile; only a look-alike is asked about.
            phase = .loading("Saving…")
            await checkFamiliar(in: staging)
            phase = .ready
            if similarItems.isEmpty {
                save()
                return
            }
            await makeThumbnails(in: staging)
            return
        }
        phase = shown.isEmpty ? .nothing : .ready
        await checkFamiliar(in: staging)
        await suggestBoards(in: staging, pageTitle: pageTitle)
        await makeThumbnails(in: staging)
    }

    /// "Looks familiar": each shared thing against the index the app wrote (only when it was written
    /// for the profile the boards are from — the same library).
    private func checkFamiliar(in folder: URL) async {
        guard let profileID, let index = ShareShared.readFamiliarIndex(profile: profileID) else { return }
        let thumbs = ShareShared.thumbsFolder(for: profileID)
        let items = shown.map { (each: Shown) -> ShareInboxEntry.Item in each.item }
        let found = await Task.detached(priority: .userInitiated) { () -> [UUID: FamiliarMatch] in
            await ShareFamiliarCheck.check(items, in: folder, index: index)
        }.value
        var found2: [UUID: UIImage] = [:]
        for match in found.values where found2[match.existing.id] == nil {
            if let image = ShareFamiliarCheck.thumbnail(of: match.existing, in: thumbs) { found2[match.existing.id] = image }
        }
        guard profileID == self.profileID else { return }   // another profile was chosen meanwhile
        for (id, match) in found where !match.exact { choices[id] = .saveNew }
        existingThumbs = found2
        familiar = found
    }

    /// The look-alikes (the person chooses), in the order shared.
    var similarItems: [Shown] { shown.filter { familiar[$0.id].map { !$0.exact } ?? false } }
    /// The same links or texts already in PinBoard, in the order shared.
    var exactItems: [Shown] { shown.filter { familiar[$0.id]?.exact ?? false } }

    /// The existing pin is on the chosen board already.
    func isOnChosenBoard(_ match: FamiliarMatch) -> Bool {
        guard let boardID else { return false }
        return match.existing.boardIDs.contains(boardID)
    }

    /// The same answer for every look-alike ("Save all N as new", "Add all N existing", "Skip all N").
    func chooseForAll(_ choice: ShareChoice) {
        for item in similarItems { choices[item.id] = choice }
    }

    /// "Suggested": from the first shared thing only (with many, looking at each would cost memory
    /// and time, and the first is usually like the rest). Worked out away from the screen.
    private func suggestBoards(in folder: URL, pageTitle: String?) async {
        guard let first = shown.first?.item, let boards = boardList?.boards, !boards.isEmpty else { return }
        let profile = profileID
        let found = await Task.detached(priority: .userInitiated) { () -> [ShareSuggestion] in
            let features = await ShareModel.features(of: first, in: folder, pageTitle: pageTitle)
            return ShareSuggester.suggest(features, boards: boards)
        }.value
        guard profile == profileID else { return }   // another profile was chosen meanwhile
        suggestions = found
    }

    /// What the suggestions compare: a link's site and words, a text's words, a picture's tags.
    nonisolated private static func features(of item: ShareInboxEntry.Item, in folder: URL,
                                             pageTitle: String?) async -> ShareSuggester.Features {
        switch item.kind {
        case .link:
            return ShareSuggester.features(link: item.url ?? "", title: pageTitle)
        case .text:
            return ShareSuggester.features(text: item.text ?? "")
        case .picture, .gif:
            guard let file = item.file else { return .init() }
            let url = folder.appendingPathComponent(file)
            var features = ShareSuggester.Features()
            if let small = ShareSuggester.smallPicture(url) { features = ShareSuggester.features(picture: small) }
            features.tags = ShareSuggester.combined(features.tags, ShareSuggester.storedWords(of: url))
            return features
        case .video:
            guard let file = item.file,
                  let frame = await ShareLoader.thumbnail(of: folder.appendingPathComponent(file), kind: .video),
                  let source = CGImageSourceCreateWithData(frame as CFData, nil),
                  let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .init() }
            return ShareSuggester.features(picture: picture)
        }
    }

    /// Safari and other apps often share a page's address twice (as a link and as text, or as two
    /// links that differ only by a "/" at the end): kept once. Links count as the same page as the
    /// app counts them (capitals, "http"/"https" and a trailing "/" don't matter).
    private func dropRepeats() {
        var pages: Set<String> = []
        var texts: Set<String> = []
        shown = shown.filter { (each: Shown) -> Bool in
            if each.item.kind == .link, let url = each.item.url {
                return pages.insert(ShareFamiliarIndex.normalized(url)).inserted
            }
            return true
        }
        shown = shown.filter { (each: Shown) -> Bool in
            guard each.item.kind == .text, let text = each.item.text else { return true }
            if pages.contains(ShareFamiliarIndex.normalized(text)) { return false }
            return texts.insert(text).inserted
        }
    }

    private func makeThumbnails(in folder: URL) async {
        for index in shown.indices {
            let item = shown[index].item
            guard let file = item.file else { continue }
            let url = folder.appendingPathComponent(file)
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                await ShareLoader.thumbnail(of: url, kind: item.kind)
            }.value
            if let data, index < shown.count { shown[index].thumbnail = UIImage(data: data) }
        }
    }

    /// Writes the share's description, makes the folder a finished one (the app takes in only
    /// those), tells PinBoard and closes.
    func save() {
        guard canSave, let staging, let finished else { return }
        let needed = newBoardsNeeded()
        var entry = ShareInboxEntry(id: entryID, profileID: profileID, boardID: boardID,
                                    note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: Date(),
                                    items: shown.map { (each: Shown) -> ShareInboxEntry.Item in withChoice(each.item) })
        entry.newBoards = needed.isEmpty ? nil : needed
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: staging.appendingPathComponent(ShareShared.entryFileName), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: finished)
        } catch {
            phase = .failed
            return
        }
        rememberNewBoards(needed)
        if let boardID, let profileID { ShareShared.writeLastBoard(boardID, profile: profileID) }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(ShareShared.inboxChangedNotice as CFString), nil, nil, true)
        if quickSave {
            // As little to do as possible: a moment's "Saved to PinBoard", then it closes by itself.
            sayAndClose(title: "Saved to PinBoard", text: "", seconds: 1.2)
        } else if isOpenProfile {
            finish(true)
        } else {
            // Another profile's share waits until that profile is open in PinBoard: said plainly.
            sayAndClose(title: "Saved", text: "It'll appear in “\(profileName)” the next time you open that profile in PinBoard.",
                        seconds: 1.8)
        }
    }

    private func sayAndClose(title: String, text: String, seconds: Double) {
        phase = .saved(title: title, text: text)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            finish(true)
        }
    }

    /// Boards made here that this share uses are kept for the next shares, until PinBoard made them.
    private func rememberNewBoards(_ needed: [ShareNewBoard]) {
        guard let profileID, let file = ShareShared.newBoardsFile(for: profileID) else { return }
        let fresh = needed.filter { (new: ShareNewBoard) -> Bool in !madeBefore.contains(where: { $0.id == new.id }) }
        guard !fresh.isEmpty, let data = try? JSONEncoder().encode(madeBefore + fresh) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// An item with what was decided about its look-alike: an exact copy always puts the pin you
    /// have on the board (as before); a look-alike gets the answer chosen here.
    private func withChoice(_ item: ShareInboxEntry.Item) -> ShareInboxEntry.Item {
        guard let match = familiar[item.id] else { return item }
        var item = item
        item.existingPinID = match.existing.id
        item.choice = match.exact ? .addExisting : (choices[item.id] ?? .saveNew)
        return item
    }

    func cancel() {
        if let staging { try? FileManager.default.removeItem(at: staging) }
        finish(false)
    }

    // MARK: Words

    /// "3 pictures and 1 video".
    var summary: String {
        var parts: [String] = []
        let kinds: [(ShareInboxEntry.Kind, String, String)] = [
            (.picture, "picture", "pictures"), (.gif, "GIF", "GIFs"), (.video, "video", "videos"),
            (.link, "link", "links"), (.text, "text", "texts"),
        ]
        for (kind, one, many) in kinds {
            let count = shown.filter { (each: Shown) -> Bool in each.item.kind == kind }.count
            if count == 1 { parts.append("1 \(one)") }
            if count > 1 { parts.append("\(count) \(many)") }
        }
        guard let last = parts.popLast() else { return "" }
        return parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
    }

    /// The board row's value: "Travel › Japan", or "No board".
    var boardTitle: String {
        guard let boardID, let path = boardList?.path(of: boardID) else { return "No board" }
        return path
    }
}
