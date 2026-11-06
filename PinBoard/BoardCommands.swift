//
//  BoardCommands.swift  —  PinBoard
//
//  Board commands (Rename…, Move into…, Hide board, Delete… and the rest) are defined
//  once, in the table in this file: a tile's touch-and-hold menu, a board page's ⋯ menu and
//  the selection bar all show them from it, and one presenter (BoardCommandPresenter)
//  opens their sheets and questions. The "AI sorting" menu is here too: many screens share it.
//

import SwiftUI
import PhotosUI
import LocalAuthentication
import UIKit
import Foundation

// MARK: - Board commands (one table for every surface)
//
// Each command for boards is defined once, here: its words, its symbol and when it can be used.
// A tile's touch-and-hold menu, a board page's ⋯ menu and the bar while selecting boards all
// show the commands from this table, and BoardCommandPresenter carries them out for all three,
// so they can't drift apart. Smart boards (SmartBoards.swift) follow the same rule for a
// command that can't be used right now.

/// Where board commands are shown. It only decides how a command that can't be used right now
/// looks there — Apple's rule: left out of a context menu, dimmed in a ⋯ menu or a bar.
enum BoardCommandSurface: Hashable, Sendable {
    case contextMenu    // a tile's touch-and-hold menu (boards and smart boards)
    case moreMenu       // a page's ⋯ menu (boards and smart boards)
    case selectionBar   // the bar at the bottom while selecting boards
}

/// What the board command rules need to know about one board. Plain values, so the harness
/// can test the rules; `LibraryStore.boardFacts(_:)` reads them from the library.
struct BoardFacts: Hashable, Sendable {
    var isSecret = false       // hidden by itself: it has its own Hide/Unhide
    var isHidden = false       // hidden by itself, or because a board it is in is hidden
    var isFavorite = false
    var hasPictures = false    // a pin with a picture is on it or on a sub-board (a cover can be chosen)
    /// It sits (at any depth) inside another of the boards asked about together — a selection
    /// holding a board and one of its sub-boards. Always false for a board on its own.
    var isInsideAnother = false
    /// Its own "Keep off Home page" is on (its pins stay out of the Pins tab's All).
    var keepsOut = false
    /// A board it sits in keeps its pins out of All, so this board's pins are kept out whatever
    /// its own setting says.
    var keptOutByParent = false
}

/// One thing you can do with a board — or with the boards selected.
enum BoardCommand: Hashable, CaseIterable, Sendable {
    case select                   // a tile's touch-and-hold menu only: start selecting boards, with this one chosen
    case rename, description, newSubBoard, changeCover, moveInto
    case favorite, share, hide
    case keepOutOfAll             // softer than Hide: the board's pins stay out of the Pins tab's All (and back)
    case merge
    case delete
}

extension BoardCommand {
    /// The command's words on every surface (and what VoiceOver says for a bar button shown as
    /// an icon). Favorites and Hide say what they will do; Hide says "boards" for several. The
    /// ellipsis means a sheet or a question comes first (`asksFirst`).
    func title(for boards: [BoardFacts]) -> String {
        switch self {
        case .select: return "Select"
        case .rename: return "Rename…"
        case .description: return "Description…"
        case .newSubBoard: return "New sub-board…"
        case .changeCover: return "Change cover…"
        case .moveInto: return "Move into…"
        case .favorite: return BoardCommandRules.allFavorite(boards) ? "Remove from favorites" : "Add to favorites"
        case .share: return "Share board…"
        case .hide: return hideTitle(for: boards)
        case .keepOutOfAll: return keepOutTitle(for: boards)
        case .merge: return "Merge…"
        case .delete: return "Delete…"
        }
    }

    /// The SF Symbol, the same on every surface.
    func symbol(for boards: [BoardFacts]) -> String {
        switch self {
        case .rename: return "pencil"
        case .description: return "text.alignleft"
        case .newSubBoard: return "folder.badge.plus"
        case .changeCover: return "photo.on.rectangle"
        case .moveInto: return "arrow.turn.down.right"
        case .favorite: return BoardCommandRules.allFavorite(boards) ? "star.slash" : "star"
        case .share: return "square.and.arrow.up"
        case .select: return "checkmark.circle"
        case .hide: return BoardCommandRules.unhides(boards) ? "lock.open" : "lock"
        // The stack symbols, as the pin menus use for the same command. (The eye is Hide's: it means
        // the secret section, which "Keep off Home page" is not.)
        case .keepOutOfAll: return BoardCommandRules.keptOutAll(boards) ? "rectangle.stack.badge.plus" : "rectangle.stack.badge.minus"
        case .merge: return "arrow.triangle.merge"
        case .delete: return "trash"
        }
    }

    /// The one-word caption under a selection-bar button: the first word of the title ("Move"
    /// for "Move into…", "Unhide" for "Unhide boards"). Short, so the captions fit on an iPhone;
    /// the button's VoiceOver label is the full title. (Commands the bar doesn't show keep
    /// their title.)
    func barCaption(for boards: [BoardFacts]) -> String {
        switch self {
        case .moveInto: return "Move"
        case .hide: return BoardCommandRules.unhides(boards) ? "Unhide" : "Hide"
        case .keepOutOfAll: return BoardCommandRules.keptOutAll(boards) ? "Show" : "Keep off"
        case .merge: return "Merge"
        case .delete: return "Delete"
        default: return title(for: boards)
        }
    }

    /// A sheet or a question comes before anything changes (the title ends with "…").
    var asksFirst: Bool {
        switch self {
        case .favorite, .hide, .select, .keepOutOfAll: return false
        default: return true
        }
    }

    /// Only Delete… destroys something: it is red, and menus show it last, after a divider.
    var isDestructive: Bool { self == .delete }

    /// "Hide board", "Unhide boards"… A board hidden only because the board it is in is hidden
    /// can't be unhidden by itself: its dimmed item says so.
    /// "Keep off Home page", or "Show on Home page" once every board's pins are kept out. A board kept out
    /// only because a board it is in keeps its pins out can't be changed by itself: its dimmed item
    /// says so (like Unhide).
    private func keepOutTitle(for boards: [BoardFacts]) -> String {
        if BoardCommandRules.keptOutOnlyByParents(boards) {
            return boards.count == 1 ? "Show on Home page (kept off with its parent)" : "Show on Home page (kept off with their parents)"
        }
        return BoardCommandRules.keptOutAll(boards) ? "Show on Home page" : "Keep off Home page"
    }

    private func hideTitle(for boards: [BoardFacts]) -> String {
        if BoardCommandRules.hiddenOnlyWithParents(boards) {
            return boards.count == 1 ? "Unhide board (hidden with its parent)" : "Unhide boards (hidden with their parents)"
        }
        let verb = BoardCommandRules.unhides(boards) ? "Unhide" : "Hide"
        let noun = boards.count == 1 ? "board" : "boards"
        return "\(verb) \(noun)"
    }
}

/// Where each board command is listed and when it can be used — plain rules the harness tests.
enum BoardCommandRules {
    /// The board commands a surface lists, top to bottom. A tile's menu and a board page's ⋯ menu
    /// list the same ones in the same order (the page adds its own items, like Select pins and
    /// Settings…, before Delete…); the selection bar has the ones that work on several boards.
    nonisolated static func commands(on surface: BoardCommandSurface, side: PinScope = .visible) -> [BoardCommand] {
        // Keep out of All sits next to Hide, its softer sibling. Not on the hidden side: hidden pins
        // are never in All, so it would change nothing there.
        let keepOut: [BoardCommand] = side == .visible ? [.keepOutOfAll] : []
        switch surface {
        case .contextMenu:
            return [.select, .rename, .description, .newSubBoard, .changeCover, .moveInto, .favorite, .share, .hide] + keepOut + [.delete]
        case .moreMenu:
            return [.rename, .description, .newSubBoard, .changeCover, .moveInto, .favorite, .share, .hide] + keepOut + [.delete]
        case .selectionBar:
            return [.moveInto, .hide] + keepOut + [.merge, .delete]
        }
    }

    /// Whether a command can be used now on these boards: one board (from its tile or its page) or
    /// the boards selected. The answer is the same on every surface.
    nonisolated static func available(_ command: BoardCommand, for boards: [BoardFacts]) -> Bool {
        switch command {
        case .rename, .description, .newSubBoard, .favorite, .share:
            return boards.count == 1
        case .changeCover:
            return boards.count == 1 && boards[0].hasPictures   // the cover is chosen among its pictures
        case .moveInto, .delete, .select:
            return !boards.isEmpty
        case .hide:
            return canHideOrUnhide(boards)
        case .keepOutOfAll:
            return canKeepOutOrShow(boards)
        case .merge:
            return boards.count >= 2 && !nested(boards)
        }
    }

    /// One board (its tile's menu or its page's ⋯ menu).
    nonisolated static func available(_ command: BoardCommand, for board: BoardFacts) -> Bool {
        available(command, for: [board])
    }

    /// Apple's rule for a command that can't be used right now: a context menu leaves it out,
    /// a ⋯ menu or a bar shows it dimmed. (Smart boards follow it too.)
    nonisolated static func shows(available: Bool, on surface: BoardCommandSurface) -> Bool {
        available || surface != .contextMenu
    }

    /// Whether a surface shows this command for these boards at all (dimmed when it can't be used).
    nonisolated static func shows(_ command: BoardCommand, on surface: BoardCommandSurface, for boards: [BoardFacts]) -> Bool {
        applies(command, to: boards) && shows(available: available(command, for: boards), on: surface)
    }

    /// Whether a command means anything for these boards. "Keep off Home page" doesn't for a hidden
    /// board: hidden pins are never in All, so it is left out there (not merely dimmed).
    nonisolated static func applies(_ command: BoardCommand, to boards: [BoardFacts]) -> Bool {
        if command == .keepOutOfAll { return !boards.contains { (board: BoardFacts) -> Bool in board.isHidden } }
        return true
    }

    /// Every board's pins are kept out of All already (by the board itself or by a board it is in),
    /// so the command is Show on Home page (otherwise Keep out of All).
    nonisolated static func keptOutAll(_ boards: [BoardFacts]) -> Bool {
        !boards.isEmpty && boards.allSatisfy { (board: BoardFacts) -> Bool in board.keepsOut || board.keptOutByParent }
    }

    /// Every board is kept out, but none by its own setting — only because a board it is in keeps
    /// its pins out. Show on Home page is dimmed then, and its title gives that reason.
    nonisolated static func keptOutOnlyByParents(_ boards: [BoardFacts]) -> Bool {
        keptOutAll(boards) && !boards.contains { (board: BoardFacts) -> Bool in board.keepsOut }
    }

    /// Keep out works on boards that show in All. Show on Home page only when some board's own setting
    /// keeps it out: one kept out by a board it is in comes back with that board, not on its own.
    nonisolated static func canKeepOutOrShow(_ boards: [BoardFacts]) -> Bool {
        if boards.isEmpty { return false }
        if keptOutAll(boards) { return boards.contains { (board: BoardFacts) -> Bool in board.keepsOut } }
        return true
    }

    /// Every board is hidden, so the command is Unhide (otherwise Hide).
    nonisolated static func unhides(_ boards: [BoardFacts]) -> Bool {
        !boards.isEmpty && boards.allSatisfy { (board: BoardFacts) -> Bool in board.isHidden }
    }

    /// Every board is a favorite, so the command is Remove from favorites.
    nonisolated static func allFavorite(_ boards: [BoardFacts]) -> Bool {
        !boards.isEmpty && boards.allSatisfy { (board: BoardFacts) -> Bool in board.isFavorite }
    }

    /// Hide works on a board that isn't hidden. Unhide only on one hidden by itself: a board
    /// hidden with the board it is in comes back with that board, not on its own.
    nonisolated static func canHideOrUnhide(_ boards: [BoardFacts]) -> Bool {
        if boards.isEmpty { return false }
        if unhides(boards) { return boards.contains { (board: BoardFacts) -> Bool in board.isSecret } }
        return boards.contains { (board: BoardFacts) -> Bool in !board.isHidden }
    }

    /// Every board is hidden, but none by itself — only because a board they are in is hidden.
    /// Unhide is dimmed then, and its title gives that reason.
    nonisolated static func hiddenOnlyWithParents(_ boards: [BoardFacts]) -> Bool {
        unhides(boards) && !boards.contains { (board: BoardFacts) -> Bool in board.isSecret }
    }

    /// One of the boards sits inside another of them. Merge is dimmed then: the library never
    /// merges a board into one it holds, or one it sits in (that would leave the board that
    /// stays inside a deleted board), and the bar's hint says why.
    nonisolated static func nested(_ boards: [BoardFacts]) -> Bool {
        boards.contains { (board: BoardFacts) -> Bool in board.isInsideAnother }
    }
}

/// The delete question's words — the same from a tile, a board's page or the selection bar
/// (its explanation is `boardDeleteMessage(hidden:count:)`).
enum BoardDeleteText {
    /// "Delete “Travel”?", or "Delete 3 boards?". On the hidden side a board is never named
    /// ("Delete this board?"): the question sits above the App Switcher cover.
    nonisolated static func question(name: String, count: Int, hidden: Bool = false) -> String {
        if count != 1 { return "Delete \(count) boards?" }
        return hidden ? "Delete this board?" : "Delete “\(name)”?"
    }

    /// The boards go; their pins stay (on their other boards, or in Unsorted).
    nonisolated static func keepPins(count: Int) -> String {
        count == 1 ? "Delete board, keep its pins" : "Delete boards, keep their pins"
    }

    /// Pins on no other board go to Recently Deleted too.
    nonisolated static func withPins(count: Int) -> String {
        count == 1
            ? "Delete board and move its pins to Recently Deleted"
            : "Delete boards and move their pins to Recently Deleted"
    }
}

/// The short confirmation after Hide or Unhide — the same from a tile, a board's page or the
/// selection bar, since the boards leave the screen they were on. It never names a board: a
/// hidden board's name is not shown outside Hidden, and the message may outlast a visit there.
enum BoardHideText {
    /// "Hid the board. It's in Boards › ⋯ › Hidden." / "Hid 3 boards. They're in …".
    nonisolated static func hid(count: Int) -> String {
        count == 1
            ? "Hid the board. It's in Boards › ⋯ › Hidden."
            : "Hid \(count) boards. They're in Boards › ⋯ › Hidden."
    }

    /// "Unhid the board." / "Unhid 3 boards." (like "Unhid 3 pins.").
    nonisolated static func unhid(count: Int) -> String {
        count == 1 ? "Unhid the board." : "Unhid \(count) boards."
    }
}

/// The short confirmation after "Keep off Home page" / "Show on Home page" on boards — the same from a tile,
/// a board's page or the selection bar. It never names a board.
enum BoardKeepOutText {
    /// "Pins on this board stay off the Home page now. See them in Settings › Pins & boards › Home
    /// page." / "…show on the Home page again." `stillKept`: after Show on Home page, a board they
    /// are in still keeps them off.
    nonisolated static func message(keeping: Bool, count: Int, stillKept: Bool) -> String {
        let which = count == 1 ? "this board" : "\(count) boards"
        if keeping { return "Pins on \(which) stay off the Home page now. See them in \(SettingsCatalog.path(.homePage))." }
        let shown = "Pins on \(which) show on the Home page again."
        return stillKept ? shown + " A board they are in still keeps them off." : shown
    }
}

/// Merge's words about boards it can't merge: a board is never merged into one it holds, or one
/// it sits in. The selection bar dims Merge for such a selection (and says why); if boards were
/// moved meanwhile (say in another window), the merge leaves them out and a short note says so.
enum BoardMergeText {
    /// Under the selection bar's buttons while Merge is dimmed for that reason.
    static let nestedHint = "A board can't be merged with a board inside it."

    /// The note after a merge that left boards out. `names`: those boards; `insideTarget`: the
    /// (first) one sits inside `target`, the board that stays (false: `target` sits inside it).
    /// "“Japan” is inside “Travel”, so it wasn't merged." On the hidden side no board is named
    /// ("One board is inside another, so it wasn't merged."): the note may outlast the visit.
    nonisolated static func leftOut(names: [String], insideTarget: Bool, target: String, hidden: Bool) -> String {
        let count = names.count
        if hidden {
            return count == 1
                ? "One board is inside another, so it wasn't merged."
                : "\(count) boards are inside another or hold one, so they weren't merged."
        }
        guard count == 1, let name = names.first else {
            return "\(count) boards are inside “\(target)” or hold it, so they weren't merged."
        }
        return insideTarget
            ? "“\(name)” is inside “\(target)”, so it wasn't merged."
            : "“\(target)” is inside “\(name)”, so “\(name)” wasn't merged."
    }
}

extension LibraryStore {
    /// What the board command rules need to know about a board.
    func boardFacts(_ board: Board) -> BoardFacts {
        // Stops at the first picture (the cover picker offers the same pins).
        let pictures = pinIDs(in: board.id, includeNested: true).contains { (id: UUID) -> Bool in
            livePin(id)?.hasImageFile == true
        }
        var facts = BoardFacts(isSecret: board.isSecret, isHidden: isSecretBoard(board.id),
                               isFavorite: board.isFavorite, hasPictures: pictures)
        facts.keepsOut = board.keepsPinsOutOfAll
        facts.keptOutByParent = path(to: board.id).dropLast().contains { (parent: Board) -> Bool in parent.keepsPinsOutOfAll }
        return facts
    }

    /// The facts of boards asked about together (the selection bar): each also says whether it
    /// sits inside another of them.
    func boardFacts(_ boards: [Board]) -> [BoardFacts] {
        let ids = Set(boards.map { (board: Board) -> UUID in board.id })
        return boards.map { (board: Board) -> BoardFacts in
            var facts = boardFacts(board)
            let outer = path(to: board.id).dropLast()   // the boards it sits in, outermost first
            facts.isInsideAnother = outer.contains { (parent: Board) -> Bool in ids.contains(parent.id) }
            return facts
        }
    }

    /// After a merge into `target`: the note for the boards asked for that weren't merged — the
    /// library leaves out a board that holds `target` or sits inside it — or nil when none was
    /// left out (boards deleted meanwhile don't count). Named only on the normal side.
    func mergeNote(asked: [UUID], target: UUID, merged: Set<UUID>, hidden: Bool) -> String? {
        guard let kept = board(target) else { return nil }
        let leftOut = asked.filter { (id: UUID) -> Bool in
            id != target && !merged.contains(id) && board(id) != nil
        }
        guard let first = leftOut.first else { return nil }
        let names = leftOut.compactMap { (id: UUID) -> String? in board(id)?.name }
        let insideTarget = descendants(of: target).contains(first)
        return BoardMergeText.leftOut(names: names, insideTarget: insideTarget, target: kept.name, hidden: hidden)
    }
}

/// A board command asked for on a screen: which one, for which boards, on which side of the
/// library. A fresh `id` every time, so the same command asked twice in a row happens twice.
struct BoardCommandRequest: Identifiable {
    let id = UUID()
    let command: BoardCommand
    let boardIDs: [UUID]
    let side: PinScope
    /// The first board's name and description when its sheet opened. Its sheet shows these, so
    /// it never goes blank (and keeps its Cancel) if the board is deleted meanwhile, by a sync say.
    var name: String = ""
    var details: String = ""
}

extension BoardCommandRequest {
    /// A command for one board, on that board's own side of the library.
    @MainActor
    init(_ command: BoardCommand, board boardID: UUID, store: LibraryStore) {
        self.init(command: command, boardIDs: [boardID], side: store.isSecretBoard(boardID) ? .hidden : .visible)
    }
}

/// Board commands as menu items: the table's words and symbols, in its order. What can't be
/// used right now is left out of a context menu and dimmed in a ⋯ menu; Delete… comes after
/// a divider.
struct BoardCommandItems: View {
    let commands: [BoardCommand]
    let boards: [BoardFacts]
    let surface: BoardCommandSurface
    let onCommand: (BoardCommand) -> Void

    var body: some View {
        ForEach(shownCommands, id: \.self) { command in
            if command.isDestructive {
                Divider()
            }
            item(command)
            if command == .select {
                Divider()   // "Select" stands apart from the commands that change the board
            }
        }
    }

    private var shownCommands: [BoardCommand] {
        commands.filter { (command: BoardCommand) -> Bool in
            BoardCommandRules.shows(command, on: surface, for: boards)
        }
    }

    private func item(_ command: BoardCommand) -> some View {
        Button(role: command.isDestructive ? .destructive : nil) {
            onCommand(command)
        } label: {
            Label(command.title(for: boards), systemImage: command.symbol(for: boards))
        }
        .disabled(!BoardCommandRules.available(command, for: boards))
    }
}

/// A board tile's touch-and-hold menu. A view of its own: the board's facts are read in here,
/// when SwiftUI builds the menu, instead of in the grid's body for every tile.
struct BoardTileMenu: View {
    @EnvironmentObject private var store: LibraryStore
    let board: Board
    /// The tile's grid can start selecting boards (then the menu starts with "Select").
    var canSelect: Bool = false
    let onCommand: (BoardCommand) -> Void

    var body: some View {
        BoardCommandItems(commands: commands,
                          boards: [store.boardFacts(board)],
                          surface: .contextMenu,
                          onCommand: onCommand)
    }

    private var commands: [BoardCommand] {
        BoardCommandRules.commands(on: .contextMenu).filter { (command: BoardCommand) -> Bool in
            canSelect || command != .select
        }
    }
}

/// Carries out the board commands of one screen — a grid of board tiles, a board's page or the
/// selection bar: the sheets (rename, description, new sub-board, cover, move, share, merge),
/// the delete question, and the quick ones (favorites, hide). Attach it once with the screen's
/// `request`; the menus set `request`, this does the rest. `onDone` runs once a command changed
/// something (the selection bar then ends selecting; a board's page goes back after a delete,
/// or after hiding its own board).
@MainActor
struct BoardCommandPresenter: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow   // the short confirmation after Hide / Unhide
    @Binding var request: BoardCommandRequest?
    var onDone: (BoardCommand) -> Void = { _ in }

    @State private var sheet: BoardCommandRequest? = nil      // the command whose sheet is up
    @State private var deleting: BoardCommandRequest? = nil   // kept while its question closes
    @State private var askingDelete = false
    @State private var deleteQuestion = ""                    // "Delete “Travel”?", kept too

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { carryOut() }
            .sheet(item: $sheet) { asked in
                // A hidden board's sheet (its name, its pictures) never shows in the App Switcher.
                sheetContent(for: asked)
                    .hiddenPrivacyCover(asked.side == .hidden)
            }
            // (The question sits above any cover: on the hidden side it names no board.)
            .confirmationDialog(deleteQuestion, isPresented: $askingDelete, titleVisibility: .visible) {
                deleteButtons
            } message: {
                Text(boardDeleteMessage(hidden: deleting?.side == .hidden, count: deleteCount))
            }
    }

    private var deleteCount: Int { deleting?.boardIDs.count ?? 1 }

    /// Does what `request` asks for — if the rules allow it for those boards right now.
    private func carryOut() {
        guard let asked = request else { return }
        let boards = asked.boardIDs.compactMap { (id: UUID) -> Board? in store.board(id) }
        let facts = store.boardFacts(boards)
        guard BoardCommandRules.available(asked.command, for: facts) else { return }
        // From here on only the boards that still exist (a sync may have removed a selected one).
        let ids = boards.map { (board: Board) -> UUID in board.id }
        let live = BoardCommandRequest(command: asked.command, boardIDs: ids, side: asked.side,
                                       name: boards.first?.name ?? "", details: boards.first?.details ?? "")
        switch asked.command {
        case .favorite:
            let favorite = !BoardCommandRules.allFavorite(facts)
            for board in boards { store.setFavorite(favorite, for: board.id) }
            onDone(.favorite)
        case .hide:
            hideOrUnhide(boards, facts: facts)
        case .keepOutOfAll:
            keepOutOrShow(boards, facts: facts)
        case .select:
            break   // the tile's grid starts selecting itself (BoardGrid); nothing to present
        case .delete:
            deleting = live
            deleteQuestion = BoardDeleteText.question(name: boards.first?.name ?? "", count: boards.count,
                                                      hidden: asked.side == .hidden)
            askingDelete = true
        default:
            sheet = live   // rename, description, new sub-board, cover, move, share, merge
        }
    }

    /// Hide or Unhide. Only boards whose own setting changes are touched (one hidden with its
    /// parent stays as it is). The boards leave the screen they were on (the Boards tab, or
    /// Hidden), so a short confirmation says where they went — the same from a tile, a page or
    /// the bar.
    private func hideOrUnhide(_ boards: [Board], facts: [BoardFacts]) {
        let hide = !BoardCommandRules.unhides(facts)
        let changing = boards.filter { (board: Board) -> Bool in board.isSecret != hide }
        for board in changing { store.setSecret(hide, for: board.id) }
        if !changing.isEmpty {
            importFlow.flash(hide ? BoardHideText.hid(count: changing.count) : BoardHideText.unhid(count: changing.count))
        }
        onDone(.hide)
    }

    /// Keep out of All / Show on Home page. Only boards whose own setting changes are touched. The
    /// confirmation never names a board and says where kept-out pins are found.
    private func keepOutOrShow(_ boards: [Board], facts: [BoardFacts]) {
        let show = BoardCommandRules.keptOutAll(facts)
        let changing = boards.filter { (board: Board) -> Bool in board.keepsPinsOutOfAll == show }
        for board in changing { store.setBoardKeepsPinsOutOfAll(board.id, !show) }
        if !changing.isEmpty {
            let stillKept = show && changing.contains { (board: Board) -> Bool in store.boardKeepsPinsOutOfAll(board.id) }
            importFlow.flash(BoardKeepOutText.message(keeping: !show, count: changing.count, stillKept: stillKept))
        }
        onDone(.keepOutOfAll)
    }

    /// The sheet a command opens.
    @ViewBuilder
    private func sheetContent(for asked: BoardCommandRequest) -> some View {
        switch asked.command {
        case .rename, .description, .newSubBoard:
            textSheet(for: asked)
        case .changeCover:
            if let id = asked.boardIDs.first {
                CoverPickerSheet(boardID: id)
            }
        case .share:
            if let id = asked.boardIDs.first {
                ShareBoardSheet(boardID: id)
            }
        case .moveInto:
            moveSheet(for: asked)
        case .merge:
            mergeSheet(for: asked)
        default:
            EmptyView()   // the other commands open no sheet
        }
    }

    /// Rename…, Description… and New sub-board… each ask for one piece of text. The sheet shows
    /// the name and description the request carries (it never looks the board up, so it can't
    /// go blank), and Save changes nothing once the board is gone. A name can't be left empty.
    @ViewBuilder
    private func textSheet(for asked: BoardCommandRequest) -> some View {
        switch asked.command {
        case .rename:
            TextEditSheet(title: "Rename board", placeholder: "Board name", initial: asked.name, requiresText: true) { name in
                guard let id = liveBoardID(asked) else { return }
                store.renameBoard(id, to: name)
                onDone(.rename)
            }
        case .description:
            TextEditSheet(title: "Description", placeholder: "What is this board about?",
                          initial: asked.details, multiline: true) { text in
                guard let id = liveBoardID(asked) else { return }
                store.setBoardDetails(text, for: id)
                onDone(.description)
            }
        default:
            TextEditSheet(title: "New sub-board in “\(asked.name)”", placeholder: "Sub-board name", initial: "",
                          requiresText: true) { name in
                guard let id = liveBoardID(asked) else { return }   // never a sub-board of a board that is gone
                store.addBoard(name: name, parentID: id)
                onDone(.newSubBoard)
            }
        }
    }

    /// The request's (first) board, if it still exists.
    private func liveBoardID(_ asked: BoardCommandRequest) -> UUID? {
        guard let id = asked.boardIDs.first, store.board(id) != nil else { return nil }
        return id
    }

    /// Move into…: the boards of the same side, except the moved boards and anything inside them.
    private func moveSheet(for asked: BoardCommandRequest) -> some View {
        let ids = asked.boardIDs
        let inside = ids.flatMap { (id: UUID) -> [UUID] in store.descendants(of: id) }
        return BoardPickerSheet(title: moveTitle(for: asked),
                                noneLabel: asked.side == .hidden ? "Top of Hidden (no parent)" : "Top level (no parent)",
                                excluded: Set(ids).union(inside),
                                scope: asked.side) { parentID in
            for id in ids { store.moveBoard(id, toParent: parentID, staying: asked.side) }
            onDone(.moveInto)
        }
    }

    /// "Move “Travel” into…", or "Move 3 boards into…".
    private func moveTitle(for asked: BoardCommandRequest) -> String {
        if asked.boardIDs.count == 1 { return "Move “\(asked.name)” into…" }
        return "Move \(asked.boardIDs.count) boards into…"
    }

    /// Merge…: the boards in their order; the first one stays (with the name chosen).
    private func mergeSheet(for asked: BoardCommandRequest) -> some View {
        let boards = asked.boardIDs
            .compactMap { (id: UUID) -> Board? in store.board(id) }
            .sorted { (a: Board, b: Board) -> Bool in a.sortIndex < b.sortIndex }
        return MergeBoardsSheet(boards: boards) { targetID, name in
            merge(asked, into: targetID, named: name)
        }
    }

    /// Merges the boards into the one that stays, and gives it the chosen name only if something
    /// was merged into it. A board the library left out (it holds that board or sits inside it —
    /// moved there meanwhile, say in another window) gets a short note. Selecting ends only if
    /// something changed.
    private func merge(_ asked: BoardCommandRequest, into targetID: UUID, named name: String) {
        let merged = store.mergeBoards(Set(asked.boardIDs), into: targetID)
        if !merged.isEmpty { store.renameBoard(targetID, to: name) }
        if let note = store.mergeNote(asked: asked.boardIDs, target: targetID, merged: merged,
                                      hidden: asked.side == .hidden) {
            importFlow.flash(note, symbol: "info.circle")   // a note: those boards stay as they were
        }
        if !merged.isEmpty { onDone(.merge) }
    }

    /// The same two choices wherever boards are deleted from.
    @ViewBuilder
    private var deleteButtons: some View {
        Button(BoardDeleteText.keepPins(count: deleteCount)) { delete(pinsToo: false) }
        Button(BoardDeleteText.withPins(count: deleteCount), role: .destructive) { delete(pinsToo: true) }
        Button("Cancel", role: .cancel) { }
    }

    private func delete(pinsToo: Bool) {
        guard let asked = deleting else { return }
        let ids = Set(asked.boardIDs.filter { (id: UUID) -> Bool in store.board(id) != nil })
        guard !ids.isEmpty else { return }
        store.deleteBoards(ids, deletePinsToo: pinsToo)
        onDone(.delete)
    }
}

// MARK: - AI sorting (boards, tags and names)

/// Which pins an "AI sorting" menu works on: a whole side of the library, or some pins
/// (a board's, a selection, a single pin).
struct AISortingTarget: Equatable {
    var scope: PinScope
    /// nil = every pin on that side of the library.
    var pinIDs: Set<UUID>?

    static func all(_ scope: PinScope) -> AISortingTarget {
        AISortingTarget(scope: scope, pinIDs: nil)
    }

    static func pins(_ ids: Set<UUID>, scope: PinScope) -> AISortingTarget {
        AISortingTarget(scope: scope, pinIDs: ids)
    }

    /// One pin: its actions run straight away (Undo is on its page).
    var isSinglePin: Bool { pinIDs?.count == 1 }
}

/// A question or a result an "AI sorting" menu wants to show (`AISortingDialogs` shows it).
enum AIPrompt: Equatable {
    case rename(target: AISortingTarget, includeYourNames: Bool, count: Int, cloudRequests: Int)
    case undo(NamingRun)
    case message(String)
}

/// "AI sorting": one menu with the AI's helpers for some pins — put them on suggested
/// boards, look at them again (tags, colors, text), name them (keeping names you wrote,
/// or replacing every name), and undo the last naming. A submenu in ⋯ and long-press
/// menus. Attach `AISortingDialogs` (with the same `prompt`) to the screen.
struct AISortingMenu: View {
    let target: AISortingTarget
    @Binding var prompt: AIPrompt?
    /// Replaces the built-in "Sort into boards" (the selection bar has its own, with progress).
    var sortIntoBoards: (() -> Void)? = nil
    /// Runs after an item was chosen (the selection bar ends selecting, for example).
    var onChosen: () -> Void = {}

    var body: some View {
        Menu {
            AISortingMenuItems(target: target, prompt: $prompt, sortIntoBoards: sortIntoBoards, onChosen: onChosen)
        } label: {
            Label("AI sorting", systemImage: "wand.and.stars")
        }
    }
}

/// The items of the "AI sorting" menu (see `AISortingMenu`).
struct AISortingMenuItems: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow   // the short confirmation after sorting
    let target: AISortingTarget
    @Binding var prompt: AIPrompt?
    var sortIntoBoards: (() -> Void)? = nil
    var onChosen: () -> Void = {}

    var body: some View {
        let running = store.namingScope != nil
        Group {
            Button {
                chooseSort()
            } label: {
                Label(sortLabel, systemImage: "tray.and.arrow.down")
            }
            .disabled(store.isAutoSorting)
            Button {
                rerunTags()
            } label: {
                Label("Re-run AI tags", systemImage: "tag")
            }
            Button {
                askToName(includeYourNames: false)
            } label: {
                Label("Name with AI (keeps your names)", systemImage: "character.cursor.ibeam")
            }
            .disabled(running)
            Button {
                askToName(includeYourNames: true)
            } label: {
                Label(target.isSinglePin ? "Rename with AI" : "Rename all with AI…", systemImage: "text.cursor")
            }
            .disabled(running)
        }
        Group {
            if let run = store.lastNamingRun(scope: target.scope), !running {
                Button {
                    prompt = .undo(run)
                } label: {
                    Label("Undo last AI naming (\(run.renamed))", systemImage: "arrow.uturn.backward")
                }
            }
            if store.namingScope == target.scope {
                if let progress = store.namingProgress {
                    Text("Renaming… \(progress.done) of \(progress.total)")
                }
                // A normal button: stopping keeps every name given so far, nothing is destroyed.
                Button {
                    store.stopNaming()
                } label: {
                    Label("Stop renaming", systemImage: "stop.circle")
                }
            }
        }
    }

    private var sortLabel: String {
        if target.pinIDs == nil { return "Sort Unsorted pins into boards" }
        return target.isSinglePin ? "Put on a suggested board" : "Sort into boards"
    }

    /// Puts the pins on the boards the AI suggests (for the whole library: the Unsorted pins).
    /// Pins moved: a short confirmation, as in the pin menus ("Put 3 pins on suggested boards.").
    /// None moved: an alert, because it explains why and what to try.
    private func chooseSort() {
        if let sortIntoBoards {
            sortIntoBoards()   // the caller's own sorting (it ends a selection itself, when done)
            return
        }
        onChosen()
        let ids: Set<UUID> = target.pinIDs ?? Set(store.unsortedPins(scope: target.scope).map { $0.id })
        guard !ids.isEmpty else {
            prompt = .message("There are no Unsorted pins to sort.")
            return
        }
        let hasBoards = !store.rootBoards(scope: target.scope).isEmpty
        let count = ids.count
        let library = store
        let flow = importFlow   // (taken now: the menu is gone by the time the sorting ends)
        Task { @MainActor in
            let moved = await library.autoSort(ids)
            if moved > 0 {
                flow.flash(PinActionText.sorted(moved: moved, of: count))
            } else {
                prompt = .message(AISortingText.sortResult(moved: 0, of: count, hasBoards: hasBoards))
            }
        }
    }

    /// Tags, colors, text (and names the AI wrote) again.
    private func rerunTags() {
        onChosen()
        if let ids = target.pinIDs {
            store.reanalyze(ids)
        } else {
            store.reanalyze(scope: target.scope)
        }
    }

    /// Many pins: asks first (how many, how many cloud requests). One pin: names it now, and says
    /// how it went once it has.
    private func askToName(includeYourNames: Bool) {
        let candidates = store.namingCandidates(scope: target.scope, among: target.pinIDs, includeYourNames: includeYourNames)
        onChosen()
        guard target.isSinglePin else {
            prompt = .rename(target: target, includeYourNames: includeYourNames, count: candidates.count,
                             cloudRequests: candidates.filter { $0.hasImageFile && store.cloudMaySee($0) }.count)
            return
        }
        if candidates.isEmpty {
            let yours = target.pinIDs?.first.flatMap { store.livePin($0) }.map { !$0.titleIsAIOwned } ?? false
            prompt = .message(!includeYourNames && yours
                ? "You wrote this pin's name, so the AI leaves it. Choose “Rename with AI” to replace it."
                : AISortingText.nothingToGoOn)
        } else {
            // One pin: its own Undo is on its page; the last naming run stays undoable.
            let runID = store.rerunNaming(scope: target.scope, among: target.pinIDs, includeYourNames: includeYourNames,
                                          recordsRun: false)
            tellOutcome(of: runID)
        }
    }

    /// Once the run has ended, says what it did (see `AISortingText.showNamingOutcome`).
    private func tellOutcome(of runID: UUID?) {
        guard let runID else { return }
        let library = store
        let flow = importFlow   // (taken now: the menu is gone by the time the naming ends)
        let singlePin = target.isSinglePin
        Task { @MainActor in
            guard let run = await library.namingOutcome(of: runID) else { return }   // stopped
            AISortingText.showNamingOutcome(run, singlePin: singlePin, flow: flow, prompt: $prompt)
        }
    }
}

/// Texts the "AI sorting" menu and the selection bar share.
enum AISortingText {
    static func sortResult(moved: Int, of count: Int, hasBoards: Bool) -> String {
        if moved == 0 {
            return hasBoards
                ? "No confident matches. Try adding more pins to your boards, or move a few by hand to teach it."
                : "Create a board or two first, then the AI can suggest where pins belong."
        }
        return "Put \(moved) of \(count) pin\(count == 1 ? "" : "s") on suggested boards. Each pin's page shows why."
    }

    /// One pin the AI can't name at all: a link without a preview picture.
    static let nothingToGoOn = "There's nothing for the AI to go on: this link has no preview picture."

    /// One pin the AI named again without finding anything better (also for the pin page's Suggest
    /// button, when `LibraryStore.regenerateTitle` returns false).
    static let keptName = "This pin kept its name — nothing better was found."

    /// The end of a naming run: "Renamed 12 pins. 3 kept their names — nothing better was found."
    /// `renamed`: every pin whose name changed (`NamingRun.changed`: a first name for an untitled
    /// pin too); `kept`: the pins that kept theirs (`NamingRun.kept`). `singlePin`: the run was
    /// about one pin.
    static func namingResult(renamed: Int, kept: Int, singlePin: Bool = false) -> String {
        if renamed == 0 {
            if kept == 0 { return "No names were changed." }
            if singlePin { return keptName }
            return kept == 1
                ? "1 pin kept its name — nothing better was found."
                : "\(kept) pins kept their names — nothing better was found."
        }
        let done = "Renamed \(renamed) pin\(renamed == 1 ? "" : "s")."
        if kept == 0 { return done }
        let keptText = kept == 1 ? "1 kept its name" : "\(kept) kept their names"
        return "\(done) \(keptText) — nothing better was found."
    }

    /// Tells how a naming run ended: a short note over the screen when every pin got a new name
    /// (as for a sort); the screen's alert when some kept theirs or nothing changed (it says
    /// why) — or the note after all, when the screen is asking something else just then.
    /// A run on hidden pins is told only in the alert of the (hidden) screen that started it: the
    /// note floats over every screen, and hidden work never shows on the normal side.
    @MainActor
    static func showNamingOutcome(_ run: NamingRun, singlePin: Bool, flow: ImportFlow, prompt: Binding<AIPrompt?>) {
        let text = namingResult(renamed: run.changed, kept: run.kept, singlePin: singlePin)
        if run.hidden {
            if prompt.wrappedValue == nil { prompt.wrappedValue = .message(text) }
        } else if run.changed > 0 && run.kept == 0 {
            flow.flash(text)
        } else if prompt.wrappedValue == nil {
            prompt.wrappedValue = .message(text)
        } else {
            flow.flash(text, symbol: "info.circle")
        }
    }
}

/// The questions and results of the "AI sorting" menu (attach next to the menu, with the same `prompt`).
@MainActor
struct AISortingDialogs: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow   // the short note when a naming run ends
    @Binding var prompt: AIPrompt?
    @State private var lastAsked: AIPrompt? = nil   // keeps the texts steady while a dialog closes

    /// The question being asked (or the one just asked, while its dialog closes).
    private var asked: AIPrompt? { prompt ?? lastAsked }

    // Each dialog clears only its own question when it closes, so a result shown right
    // after it (a message) is not wiped by the closing dialog.
    private var askingRename: Binding<Bool> {
        Binding(get: { if case .rename = prompt { return true } else { return false } },
                set: { if !$0, case .rename = prompt { prompt = nil } })
    }

    private var askingUndo: Binding<Bool> {
        Binding(get: { if case .undo = prompt { return true } else { return false } },
                set: { if !$0, case .undo = prompt { prompt = nil } })
    }

    private var showingMessage: Binding<Bool> {
        Binding(get: { if case .message = prompt { return true } else { return false } },
                set: { if !$0, case .message = prompt { prompt = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(renameTitle, isPresented: askingRename, titleVisibility: .visible) {
                renameActions
            } message: {
                Text(renameMessage)
            }
            .confirmationDialog("Undo the last AI naming?", isPresented: askingUndo, titleVisibility: .visible) {
                undoActions
            } message: {
                Text(undoMessage)
            }
            .alert(messageText, isPresented: showingMessage) {
                Button("OK", role: .cancel) { prompt = nil }
            }
            .onChange(of: prompt) { _, now in
                if let now { lastAsked = now }
            }
    }

    private var messageText: String {
        if case .message(let text) = asked { return text }
        return ""
    }

    private var renameCount: Int {
        if case .rename(_, _, let count, _) = asked { return count }
        return 0
    }

    private var includesYourNames: Bool {
        if case .rename(_, let yours, _, _) = asked { return yours }
        return false
    }

    private var renameTitle: String {
        if renameCount == 0 { return "No names to change" }
        return "Rename \(renameCount) pin\(renameCount == 1 ? "" : "s") with AI?"
    }

    private var renameMessage: String {
        guard renameCount > 0 else {
            return includesYourNames
                ? "These pins are links without a preview picture, so the AI has nothing to name them from."
                : "Every name here was written by you (or belongs to a link without a preview picture), so there is nothing the AI may rename. “Rename all with AI” replaces your names too."
        }
        var text = includesYourNames
            ? "Every one of them gets a new name from the AI — names you wrote too. You can put them all back with “Undo last AI naming” in this menu."
            : "Only names the AI wrote (and pins without a name) change, never one you wrote. You can undo the whole run in this menu."
        text += " When the AI finds nothing better, a pin keeps its name."
        if settings.cloudActive, case .rename(_, _, _, let requests) = asked, requests > 0 {
            text += " The cloud model looks at each picture again (\(requests) request\(requests == 1 ? "" : "s"))."
        }
        return text
    }

    @ViewBuilder
    private var renameActions: some View {
        if renameCount > 0, case .rename(let target, let yours, _, _) = asked {
            Button("Rename \(renameCount) pin\(renameCount == 1 ? "" : "s")") {
                let runID = store.rerunNaming(scope: target.scope, among: target.pinIDs, includeYourNames: yours)
                prompt = nil
                tellOutcome(of: runID, singlePin: target.isSinglePin)
            }
        }
        Button("Cancel", role: .cancel) { prompt = nil }
    }

    /// Once the run has ended, says what it did (see `AISortingText.showNamingOutcome`).
    private func tellOutcome(of runID: UUID?, singlePin: Bool) {
        guard let runID else { return }
        let library = store
        let flow = importFlow
        Task { @MainActor in
            guard let run = await library.namingOutcome(of: runID) else { return }   // stopped
            AISortingText.showNamingOutcome(run, singlePin: singlePin, flow: flow, prompt: $prompt)
        }
    }

    private var undoMessage: String {
        guard case .undo(let run) = asked else { return "" }
        return "Puts back the \(run.renamed) name\(run.renamed == 1 ? "" : "s") the AI changed on \(run.date.formatted(date: .abbreviated, time: .shortened)). Names changed since then stay as they are."
    }

    @ViewBuilder
    private var undoActions: some View {
        if case .undo(let run) = asked {
            Button("Put back the names") {
                let count = store.undoLastNamingRun(scope: run.hidden ? .hidden : .visible)
                prompt = .message(count == 0
                    ? "No names were put back: they had all been changed since."
                    : "Put back \(count) name\(count == 1 ? "" : "s").")
            }
        }
        Button("Cancel", role: .cancel) { prompt = nil }
    }
}
