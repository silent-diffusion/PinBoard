//
//  PinActions.swift  —  PinBoard
//
//  Everything you can do with pins, in one place, for all five pin menus: a
//  grid card's long-press menu, the selection bar, Quick Look, a pin's page and
//  "More like this". PinActionRules decides which actions a menu offers,
//  PinActionMenuItems shows them, and `.pinActions(_:)` carries them out (board
//  pickers, tag editor, share sheet, colors, questions and messages).
//
//  Every pin menu offers everything: a grid card's long-press menu, a "More like this"
//  card's, Quick Look's ⋯, a pin page's ⋯ and the selection bar's "More" list the same
//  commands in the same order (only what makes no sense in a place is left out: "Select"
//  is in a grid card's menu only). To keep the long list readable, related commands sit in
//  submenus: "Boards ▸", "Edit picture ▸", "Thumbnail ▸" (videos), "Search on the web ▸"
//  and "AI sorting ▸". A link pin also gets "Open link"; one picture gets "Crop…" at the top of
//  "Edit picture ▸" (the crop screen is in CropEditor.swift).
//
//  Links: every single pin gets "Edit link…" when it has a link (a link pin's address, or the
//  page a picture, video or text came from) and "Add link…" when it has none. A link pin's
//  address is changed in the link editor (LinkPins.swift); any other pin's in the small address
//  sheet `SourceLinkEditor` (SourceLinks.swift).
//
//  "Search on the web ▸" for a picture that lives only in the library hands the picture over the
//  way Settings › Explore & web search › "Hand the picture over by" says: on the clipboard, in a folder in Files,
//  or in Photos (the rules are `WebSearchHandoff`, in SourceLinks.swift; `searchWeb`, further down,
//  carries them out). A hidden pin's picture always goes to the clipboard.
//
//  How results are told: something done, or something that failed, is a short
//  message at the bottom of the screen (a toast). An alert only when it explains
//  what to do next. Turning a picture says nothing when it works: you see it turn.
//
//  Save to Photos and Share use a pin's full-size original when one was kept
//  (Settings › iCloud & storage): it is fetched first, and when it can't be, the copy on
//  this device is used and the message says so.
//
//  A sheet opened here looks like the screen it was opened from (Quick Look is
//  always dark), its UIKit parts too — otherwise a text field in it could draw
//  black text on a dark list. The crop screen is not a sheet but a full-screen
//  cover, always dark, like Photos' editor. A sheet or cover for one pin whose pin
//  is deleted while it is up says "This pin is gone", with Close.
//

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - What you can do with pins

/// Where a pin menu is shown: decides the few actions that only make sense in one place.
enum PinMenuPlace: Hashable, Sendable {
    case grid        // a grid card's long-press menu (the only place with "Select")
    case selection   // the selection bar (its buttons and its "More" menu)
    case quickLook   // Quick Look's ⋯ and long-press menu
    case pinPage     // a pin page's ⋯ menu
    case related     // a "More like this" card's long-press menu
}

/// One thing you can do with pins.
enum PinAction: Hashable, Sendable {
    case select                       // a grid card's long-press menu: start selecting, with this pin chosen
    case quickLook
    case openLink                     // one link pin: its page in the default browser
    case addToBoard, moveToBoard, editTags
    case editLink                     // one pin with a link: a link pin's address (and title) in the link editor, any other pin's source page in the address sheet
    case addLink                      // one pin with no link at all: the address sheet, empty
    case removeFromThisBoard(UUID)    // the board the grid shows (when some of the pins are on it)
    case removeFromBoard(UUID)        // one pin: one of its boards, listed in "Remove from board ▸"
    case removeFromSmartBoard(UUID)   // the smart board the grid shows
    case useAsCover(UUID)             // one board (several candidates: the menu lists them as a submenu)
    case crop                         // one picture: the crop screen (CropEditor.swift)
    case rotateLeft, rotateRight, flipHorizontally
    case newThumbnail                 // videos: another frame of the video becomes the poster
    case thumbnailFromPhotos          // one video: a picture from Photos becomes the poster
    case thumbnailFromPin             // one video: a picture pin becomes the poster
    case searchWeb(ReverseImageEngine) // one pin with a picture: a reverse image search on the web
    case saveToPhotos, share, generateColors
    case sortIntoBoards               // AI sorting › Sort into boards (with progress and a result)
    case hide, unhide
    case keepOutOfAll                 // softer than Hide: the pin stays out of the Pins tab's All
    case showInAll                    // ... and comes back into it
    case keptOutByBoard               // only a dimmed note: a board keeps the pin out (nothing to do here)
    case delete
}

/// The parts of a pin menu, top to bottom. The rules list the actions in this order too (the
/// harness checks it), so every menu shows them in the same order.
enum PinMenuPart: Int, CaseIterable, Comparable, Sendable {
    case select        // Select (a grid card's menu only)
    case look          // Quick look, Open link
    case boardButtons  // Add to board…, Move to board…, Remove from this board      (in "Boards ▸")
    case boards        // "Remove from board ▸" (one pin's boards)                   (in "Boards ▸")
    case covers        // "Use as board cover" (a button, or a submenu for several)  (in "Boards ▸")
    case smartBoard    // Remove from this smart board
    case picture       // Crop…, Rotate left, Rotate right, Flip horizontally         (in "Edit picture ▸")
    case thumbnail     // Pick another frame, Choose from Photos…, Use a picture pin… (in "Thumbnail ▸")
    case web           // Google Lens, Bing, TinEye, Yandex                           (in "Search on the web ▸")
    case edit          // Edit link… or Add link…, Edit tags…, Generate colors
    case keep          // Save to Photos, Share…
    case ai            // "AI sorting" ▸ (Sort into boards is in it)
    case hide          // Hide pin / Unhide pin
    case keepOut       // Keep out of All / Show on Home page
    case delete        // Delete

    static func < (a: PinMenuPart, b: PinMenuPart) -> Bool { a.rawValue < b.rawValue }

    /// The submenu this part belongs to (nil: its items sit at the top level).
    nonisolated var group: PinMenuGroup? {
        switch self {
        case .boardButtons, .boards, .covers: return .boards
        case .picture: return .editPicture
        case .thumbnail: return .thumbnail
        case .web: return .searchWeb
        default: return nil
        }
    }
}

/// A submenu of the pin menus.
enum PinMenuGroup: Hashable, Sendable {
    case boards, editPicture, thumbnail, searchWeb

    var title: String {
        switch self {
        case .boards: return "Boards"
        case .editPicture: return "Edit picture"
        case .thumbnail: return "Thumbnail"
        case .searchWeb: return ReverseSearchMenu.title   // one wording everywhere (Explore, Quick Look): "Search this picture on the web"
        }
    }

    var icon: String {
        switch self {
        case .boards: return "folder"
        case .editPicture: return "crop.rotate"
        case .thumbnail: return "photo"
        case .searchWeb: return "magnifyingglass"   // the same symbol Explore and Quick Look use
        }
    }
}

extension PinAction {
    /// The part of the menu the action sits in.
    nonisolated var menuPart: PinMenuPart {
        switch self {
        case .select: return .select
        case .quickLook, .openLink: return .look
        case .addToBoard, .moveToBoard, .removeFromThisBoard: return .boardButtons
        case .removeFromBoard: return .boards
        case .useAsCover: return .covers
        case .removeFromSmartBoard: return .smartBoard
        case .crop, .rotateLeft, .rotateRight, .flipHorizontally: return .picture
        case .newThumbnail, .thumbnailFromPhotos, .thumbnailFromPin: return .thumbnail
        case .searchWeb: return .web
        case .editLink, .addLink, .editTags, .generateColors: return .edit
        case .saveToPhotos, .share: return .keep
        case .sortIntoBoards: return .ai
        case .hide, .unhide: return .hide
        case .keepOutOfAll, .showInAll, .keptOutByBoard: return .keepOut
        case .delete: return .delete
        }
    }
}

/// Which actions apply to these pins in this place — a plain rule (the harness tests it).
enum PinActionRules {
    /// The actions in menu order. For one pin the menu also works out `pinBoards`, the boards
    /// it is on (a normal pin's hidden boards are never among them), and `coverBoards`, the boards
    /// it may be the cover of (only boards of `side`); `keptOutByBoard` says which of the pins a
    /// board keeps out of All (their own flag is in the pin). No pins, no actions.
    ///
    /// Every place gets the whole list — a card's long-press menu is the same as the ⋯ menu. What
    /// differs: "Select" only in a grid card's menu, no "Quick look" where Quick Look or the
    /// selection bar is the place itself, "Keep off Home page" and its kin only for the normal side
    /// (hidden pins are never in All), and the dimmed note "Kept off by its board" only in the
    /// places that show dimmed items (a long-press menu leaves it out, as Apple asks).
    /// One link pin gets "Open link" (when its address is a web page). One pin of any kind gets
    /// "Edit link…" when it has a link and "Add link…" when it has none (see `linkActions`).
    /// `onABoard` says whether at least one of the pins is on a board of its side: when none is,
    /// "Move to board…" is left out (there is nothing to move it from; "Add to board…" does it).
    nonisolated static func actions(for pins: [Pin], side: PinScope, place: PinMenuPlace,
                                    boardID: UUID?, smartBoardID: UUID?,
                                    pinBoards: [UUID], coverBoards: [Board],
                                    keptOutByBoard: Set<UUID> = [],
                                    onABoard: Bool = true) -> [PinAction] {
        guard let first = pins.first else { return [] }
        let single = pins.count == 1
        var list: [PinAction] = []
        if single, place == .grid { list.append(.select) }
        if single, place != .quickLook, place != .selection { list.append(.quickLook) }
        if single, linkToOpen(first) != nil { list.append(.openLink) }
        list += boardActions(pins, boardID: boardID, pinBoards: pinBoards, coverBoards: coverBoards,
                             onABoard: onABoard)
        if let smartBoardID { list.append(.removeFromSmartBoard(smartBoardID)) }
        list += pictureActions(pins)
        list += thumbnailActions(pins)
        if single { list += webSearchActions(first) }
        list += linkActions(pins)
        list.append(.editTags)
        if pins.contains(where: { $0.hasImageFile }) { list.append(.generateColors) }
        if pins.contains(where: { $0.hasImageFile || $0.isVideo }) { list.append(.saveToPhotos) }
        list.append(.share)
        list.append(side == .hidden ? .unhide : .hide)
        if side == .visible {
            list += keepOutActions(pins, place: place, keptOutByBoard: keptOutByBoard)
        }
        list.append(.delete)
        return list
    }

    /// A card's long-press menu (the dimmed items that say why something can't be done are left out).
    private nonisolated static func isLongPress(_ place: PinMenuPlace) -> Bool {
        place == .grid || place == .related
    }

    /// Add, move, remove — and the covers: "Boards ▸".
    private nonisolated static func boardActions(_ pins: [Pin], boardID: UUID?,
                                                 pinBoards: [UUID], coverBoards: [Board],
                                                 onABoard: Bool) -> [PinAction] {
        var list: [PinAction] = onABoard ? [.addToBoard, .moveToBoard] : [.addToBoard]
        if let boardID, pins.contains(where: { $0.isOn(boardID) }) { list.append(.removeFromThisBoard(boardID)) }
        guard pins.count == 1, let pin = pins.first else { return list }
        for pinBoard in pinBoards where pinBoard != boardID { list.append(.removeFromBoard(pinBoard)) }
        if pin.hasImageFile {
            for board in coverBoards { list.append(.useAsCover(board.id)) }
        }
        return list
    }

    /// "Edit picture ▸": Crop… for one picture, then turning and flipping, which work on several
    /// pictures at once. Only pictures (a video or a link preview is never changed).
    private nonisolated static func pictureActions(_ pins: [Pin]) -> [PinAction] {
        guard pins.contains(where: { $0.kind == .image }) else { return [] }
        var list: [PinAction] = pins.count == 1 ? [.crop] : []
        list += [.rotateLeft, .rotateRight, .flipHorizontally]
        return list
    }

    /// "Thumbnail ▸": another frame when every pin is a video (one video, or a whole board of
    /// videos); a picture from Photos or a picture pin only for one video.
    private nonisolated static func thumbnailActions(_ pins: [Pin]) -> [PinAction] {
        guard !pins.isEmpty, pins.allSatisfy({ $0.isVideo }) else { return [] }
        var list: [PinAction] = [.newThumbnail]
        if pins.count == 1 { list += [.thumbnailFromPhotos, .thumbnailFromPin] }
        return list
    }

    /// "Search on the web ▸": one search site each, for a pin that has a picture (a picture, a
    /// video's poster, a link's preview).
    private nonisolated static func webSearchActions(_ pin: Pin) -> [PinAction] {
        guard pin.hasImageFile else { return [] }
        return ReverseImageEngine.allCases.map { (engine: ReverseImageEngine) -> PinAction in .searchWeb(engine) }
    }

    /// "Edit link…" when the one pin has a link, "Add link…" when it has none; several pins get
    /// neither (an address belongs to one pin). A link pin always gets "Edit link…" — its address
    /// is what the pin is — even if its address were ever missing.
    private nonisolated static func linkActions(_ pins: [Pin]) -> [PinAction] {
        guard pins.count == 1, let pin = pins.first else { return [] }
        if pin.isLink || hasLink(pin) { return [.editLink] }
        return [.addLink]
    }

    /// Whether the pin has a link at all: a link pin's address, or — for a picture, video or text —
    /// the page it came from. An address that is only blanks counts as none.
    nonisolated static func hasLink(_ pin: Pin) -> Bool {
        guard let address = pin.isLink ? pin.linkURL : pin.sourceURL else { return false }
        return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The web address in a piece of text: http or https, with a host. Anything else (no scheme,
    /// "mailto:", "javascript:", "file:") is not one. The one rule behind "Open link" and the address
    /// sheet's Save; the store's `setSourceLink` applies the same.
    nonisolated static func webAddress(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// "Keep off Home page" when some pin still shows in All; "Show on Home page" when some pin's own flag
    /// keeps it out. A pin kept out only by its board can't be changed here: where dimmed items are
    /// shown, a dimmed note says so.
    private nonisolated static func keepOutActions(_ pins: [Pin], place: PinMenuPlace,
                                                   keptOutByBoard: Set<UUID>) -> [PinAction] {
        var list: [PinAction] = []
        if pins.contains(where: { !$0.keptOutOfAll && !keptOutByBoard.contains($0.id) }) { list.append(.keepOutOfAll) }
        if pins.contains(where: { $0.keptOutOfAll }) { list.append(.showInAll) }
        if list.isEmpty, !isLongPress(place) { list.append(.keptOutByBoard) }
        return list
    }

    /// The web page "Open link" opens: a link pin's address, when it is an http or https address
    /// with a host. Anything else (no address, "mailto:", "javascript:"…) is never opened.
    nonisolated static func linkToOpen(_ pin: Pin) -> URL? {
        guard pin.isLink, let text = pin.linkURL else { return nil }
        return webAddress(in: text)
    }

    /// The pins Quick Look pages through when it opens from a grid: the grid's list, in the grid's
    /// order. Only when the pin that was opened is in it (a list from an older state of the grid
    /// would put Quick Look on the wrong pin); otherwise nil, and Quick Look pages through related
    /// pins as it does from a pin page.
    nonisolated static func quickLookPages(_ list: [UUID]?, seed: UUID) -> [UUID]? {
        guard let list, list.contains(seed) else { return nil }
        return list
    }

    /// The pin whose page is open right under Quick Look: only when Quick Look was opened from that
    /// page's own ⋯ menu. (A "More like this" card's menu opens Quick Look on another pin, so the page
    /// under it is not that pin's.)
    nonisolated static func pinPageUnder(place: PinMenuPlace, pin: UUID) -> UUID? {
        place == .pinPage ? pin : nil
    }

    /// How many entries a submenu has in a menu: each plain action is one, "Remove from board ▸"
    /// is one, and "Use as board cover" is one (a button or a submenu). A submenu with only one
    /// entry is not worth a level: the menu shows that entry itself.
    nonisolated static func entryCount(of group: PinMenuGroup, in list: [PinAction]) -> Int {
        var count = 0
        var hasRemoveFromBoard = false
        var hasCover = false
        for action in list where action.menuPart.group == group {
            switch action.menuPart {
            case .boards: hasRemoveFromBoard = true
            case .covers: hasCover = true
            default: count += 1
            }
        }
        return count + (hasRemoveFromBoard ? 1 : 0) + (hasCover ? 1 : 0)
    }

    /// Actions that change a picture or a thumbnail, or fetch and save a file, wait while another
    /// such job (a turn, a save, new thumbnails) is running.
    nonisolated static func waitsForBusy(_ action: PinAction) -> Bool {
        switch action.menuPart {
        case .picture, .thumbnail: return true
        default: return action == .saveToPhotos
        }
    }
}

/// The words of the questions and short messages (plain rules; the harness tests them).
enum PinActionText {
    /// Files kept in iCloud only that couldn't come back (Offloading.swift).
    static func notFromICloud(_ count: Int) -> String {
        count == 1 ? "Couldn't get it from iCloud. Check your connection." : "\(count) couldn't come from iCloud. Check your connection."
    }

    /// "1 pin", "3 pins".
    static func pinCount(_ count: Int) -> String {
        "\(count) pin\(count == 1 ? "" : "s")"
    }

    /// The delete question, as Photos and Files ask it: "Delete this pin?" / "Delete 3 pins?",
    /// and where the pins go. `days`: how long Recently Deleted keeps them.
    static func deleteQuestion(count: Int, days: Int) -> (title: String, message: String) {
        if count == 1 {
            return ("Delete this pin?", "It stays in Recently Deleted for \(days) days.")
        }
        return ("Delete \(count) pins?", "They stay in Recently Deleted for \(days) days.")
    }

    /// After hiding: "Hid 1 pin. It's in Boards › ⋯ › Hidden."
    static func hid(_ count: Int) -> String {
        count == 1
            ? "Hid 1 pin. It's in Boards › ⋯ › Hidden."
            : "Hid \(count) pins. They're in Boards › ⋯ › Hidden."
    }

    /// After AI sorting put pins on boards: "Put 3 pins on suggested boards." (with "3 of 5"
    /// when some stayed where they were).
    static func sorted(moved: Int, of count: Int) -> String {
        if moved == 1, count == 1 { return "Put 1 pin on a suggested board." }
        if moved < count { return "Put \(moved) of \(count) pins on suggested boards." }
        return "Put \(moved) pins on suggested boards."
    }

    /// After saving to Photos: "Saved 3 items to Photos.", or nil when nothing could be saved.
    static func saved(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "Saved \(count) item\(count == 1 ? "" : "s") to Photos."
    }

    /// After saving to Photos, when `fellBack` of the pins had a kept original that couldn't be
    /// fetched (Settings › iCloud & storage), so the copy on this device was saved instead: "Saved the copy
    /// on this device; the original wasn't reachable." for one; for several, how many. nil when
    /// nothing could be saved.
    static func savedToPhotos(_ saved: Int, fellBack: Int) -> String? {
        guard saved > 0 else { return nil }
        guard fellBack > 0 else { return self.saved(saved) }
        if saved == 1 { return "Saved the copy on this device; the original wasn't reachable." }
        if fellBack == 1 {
            return "Saved \(saved) items to Photos. 1 original wasn't reachable, so its copy on this device was saved."
        }
        return "Saved \(saved) items to Photos. \(fellBack) originals weren't reachable, so their copies on this device were saved."
    }

    /// Share, when `fellBack` kept originals couldn't be fetched: the copies on this device are shared.
    static func sharingCopies(_ fellBack: Int) -> String {
        fellBack == 1
            ? "Sharing the copy on this device; the original wasn't reachable."
            : "\(fellBack) originals weren't reachable: their copies on this device are shared instead."
    }

    /// After turning or flipping: nothing when every picture turned (you can see it), else
    /// what went wrong.
    static func turnProblem(done: Int, of count: Int) -> String? {
        if done >= count { return nil }
        if done == 0 { return "Nothing could be turned." }
        return "\(count - done) of \(count) pictures couldn't be turned."
    }

    /// After "Crop": "Cropped.", or that it didn't work.
    static func cropped(_ done: Bool) -> String {
        done ? "Cropped." : "The picture couldn't be cropped."
    }

    /// After "Edit link…" was saved: "Link updated.", or "Link unchanged." when nothing changed.
    static func linkUpdated(_ changed: Bool) -> String {
        changed ? "Link updated." : "Link unchanged."
    }

    /// "Use as board cover" when only one board can get the picture: it names that board (its
    /// full path, "Travel › Beaches", when it sits inside another), because in Quick Look or on a
    /// pin's page no board is on screen to say which one.
    static func coverOf(_ boardPath: String) -> String {
        "Use as cover of “\(boardPath)”"
    }

    /// The pill while thumbnails are picked: "Picking a new thumbnail…", or "Picking new thumbnails 2 of 5…".
    static func pickingThumbnails(number: Int, of total: Int) -> String {
        total <= 1 ? "Picking a new thumbnail…" : "Picking new thumbnails \(number) of \(total)…"
    }

    /// After picking new thumbnails: "Changed 5 thumbnails." / "Changed 3 of 5 thumbnails." / a
    /// problem when none could be changed. `problem`: the message is about something that went wrong.
    static func thumbnailsChanged(_ changed: Int, of count: Int) -> (text: String, problem: Bool) {
        if changed <= 0 {
            return (count == 1 ? "The thumbnail couldn't be changed." : "No thumbnail could be changed.", true)
        }
        if changed < count { return ("Changed \(changed) of \(count) thumbnails.", true) }
        return ("Changed \(changed) thumbnail\(changed == 1 ? "" : "s").", false)
    }

    /// After a thumbnail was chosen from Photos or from a picture pin.
    static func thumbnailSet(_ done: Bool) -> String {
        done ? "Thumbnail changed." : "The thumbnail couldn't be changed."
    }

    /// "Search on the web" for a picture whose file can't be read (still in iCloud, or gone): said
    /// instead of opening the search site's empty upload page.
    static let pictureUnreadable = "Couldn't read this picture."

    /// After "Keep off Home page": "Kept 3 pins off the Home page. See them in Settings › Pins &
    /// boards › Home page." (The Home page is the Pins tab; the tab keeps its name "Pins".)
    static func keptOut(_ count: Int) -> String {
        let place = SettingsCatalog.path(.homePage)
        return count == 1
            ? "Kept 1 pin off the Home page. See it in \(place)."
            : "Kept \(count) pins off the Home page. See them in \(place)."
    }

    /// After "Show on Home page": "3 pins show on the Home page again." `stillKept`: how many of
    /// them a board still keeps off (only their own setting changed): "1 is still kept off by its board."
    static func shownInAll(_ count: Int, stillKept: Int) -> String {
        var text = count == 1 ? "1 pin shows on the Home page again." : "\(count) pins show on the Home page again."
        if stillKept > 0 {
            text += stillKept == 1 ? " 1 is still kept off by its board." : " \(stillKept) are still kept off by their boards."
        }
        return text
    }

    /// The dimmed "Kept off by its board" item, when it is chosen anyway (VoiceOver, a keyboard).
    static let keptOutByBoardNote = "A board keeps this pin off the Home page. Change it on the board: ⋯ › Show on Home page."

    /// After pins were put on a board: what really happened (see `BoardAddPlan`). A pin already
    /// on one of the board's sub-boards counts as on the board: it stays there, never twice.
    static func addedToBoard(_ plan: BoardAddPlan, board: String) -> String {
        let changed = plan.added + plan.movedDown
        if changed == 0 {
            if plan.alreadyBelow == 1, plan.alreadyThere == 0 { return "It's already on a sub-board of \(board), so it stays there." }
            if plan.alreadyBelow > 0 { return "They're already on \(board) or its sub-boards." }
            return plan.alreadyThere == 1 ? "It's already on \(board)." : "They're already on \(board)."
        }
        var text = "Added \(pinCount(changed)) to \(board)."
        if plan.movedDown > 0 {
            text += plan.movedDown == 1 ? " It moved down from a board this one is in." : " \(plan.movedDown) moved down from boards this one is in."
        }
        if plan.alreadyBelow > 0 {
            text += plan.alreadyBelow == 1 ? " 1 was already on a sub-board, so it stays there." : " \(plan.alreadyBelow) were already on sub-boards, so they stay there."
        }
        return text
    }

    /// After a web result was saved from its page: where it went. A hidden board is never named
    /// (the message may still show after you leave Hidden): "Saved to a hidden board.", or
    /// "Saved to Hidden." without a board.
    static func savedWebResult(boardNames: [String], hidden: Bool) -> String {
        if hidden {
            return boardNames.isEmpty ? "Saved to Hidden." : "Saved to a hidden board."
        }
        if boardNames.isEmpty { return "Saved to your library." }
        return "Saved to \(boardNames.joined(separator: ", "))."
    }
}

/// What putting pins on a board did, for the message. The numbers are the store's own answer
/// (`LibraryStore.addPins`: it is the one place that knows the rule "a pin is never on a board and
/// on one of its sub-boards"), so the words can never disagree with what happened: a pin already on
/// a sub-board of the board is covered and stays there; a pin on a board the target sits inside
/// moves down into the target. Plain numbers, so the harness can test it.
struct BoardAddPlan: Equatable, Sendable {
    var added = 0          // put on the board
    var movedDown = 0      // were on a board this one is inside: they leave it and go on this one
    var alreadyBelow = 0   // already on a sub-board of this board: nothing is added
    var alreadyThere = 0   // already on the board itself
}

extension BoardAddPlan {
    /// From `addPins`' answer. `asked`: how many pins were still in the library when it was
    /// asked; the ones the store did not count (not added, not covered, not moved) were on the
    /// board already.
    nonisolated init(result: (added: Int, alreadyBelow: Int, movedDown: Int), asked: Int) {
        let counted = result.added + result.alreadyBelow + result.movedDown
        self.init(added: result.added, movedDown: result.movedDown, alreadyBelow: result.alreadyBelow,
                  alreadyThere: max(0, asked - counted))
    }
}

// MARK: - Asking for an action

/// One request from a menu: what to do, with which pins, on which side, from where. It gets a
/// fresh `id` every time, so the same action asked for twice in a row happens twice.
struct PinActionRequest: Identifiable {   // (not private: PinActionsPresenter.swift reads and makes them)
    let id = UUID()
    let action: PinAction
    let ids: Set<UUID>
    let side: PinScope
    let place: PinMenuPlace
    let boardID: UUID?
    /// A web search's address: the page to open (only `.searchWeb` carries one).
    var url: URL? = nil
    /// Only for a web search that hands its picture over through Files: the temporary file the folder
    /// picker saves. With it the sheet is that picker, and `url` is the page to open after it; without
    /// it the sheet is the browser showing `url`.
    var handoffFile: URL? = nil
}

/// The pin actions of one screen: the menus ask it to do something; `.pinActions(_:)` (attached once to
/// the screen) carries the request out — sheets, questions, results. A screen owns one (`@StateObject`)
/// and hands it to every pin menu it shows.
@MainActor
final class PinActions: ObservableObject {
    /// A turn, save or sort is running (the selection bar shows a spinner and disables its buttons).
    @Published var isBusy = false   // (not private(set): PinActionsPresenter.swift sets it)
    /// Quick Look is up (shown by this module): a pin page pauses its own video meanwhile.
    @Published var isShowingQuickLook = false   // (not private(set): PinActionsPresenter.swift sets it)
    /// Something of this screen's is up over it: a sheet, a full-screen cover, a question, a picker.
    /// Quick Look turns its Space and arrow-key shortcuts off meanwhile, so typing in a sheet's
    /// text field (a title, a note, tags) is never taken as "pause" or "skip".
    @Published var isPresenting = false   // (not private(set): PinActionsPresenter.swift sets it)
    /// The pins Quick Look pages through when it opens from this screen, in the order the screen
    /// shows them (a grid sets it; asked when Quick Look opens). nil: Quick Look pages through
    /// related pins, as it does from a pin page.
    var quickLookPages: (() -> [UUID])? = nil
    /// The AI sorting menu's questions and results for this screen.
    @Published var aiPrompt: AIPrompt? = nil
    /// The last request. `.pinActions` carries it out as soon as it changes.
    @Published var request: PinActionRequest? = nil   // (not private: PinActionsPresenter.swift takes the requests)

    init() {}

    /// Asks for an action on these pins (on this side), from a menu or button in `place`. `boardID`:
    /// the board the menu's grid shows (where "Generate colors › Save as pin" goes). Nothing happens
    /// for an empty set.
    func perform(_ action: PinAction, on ids: Set<UUID>, side: PinScope, place: PinMenuPlace, boardID: UUID? = nil) {
        guard !ids.isEmpty else { return }
        request = PinActionRequest(action: action, ids: ids, side: side, place: place, boardID: boardID)
    }
}

// MARK: - The menu items

/// The pin-action items for some pins: a section of any menu (include it inside a `Menu` or a
/// `.contextMenu`). Uses PinActionRules. Related commands sit in submenus — "Boards ▸" (add,
/// move, remove, covers), "Edit picture ▸", "Thumbnail ▸", "Search on the web ▸" and "AI sorting ▸"
/// (AISortingMenu from BoardCommands.swift with `prompt: $actions.aiPrompt` and `sortIntoBoards:` →
/// `.sortIntoBoards` for pin targets) — and a submenu with only one entry left shows that entry
/// itself. `except` leaves out actions that the place shows elsewhere (the selection bar's
/// buttons, the pin page's own Delete at the end of its menu).
struct PinActionMenuItems: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var actions: PinActions
    private let ids: Set<UUID>
    private let side: PinScope
    private let place: PinMenuPlace
    private let boardID: UUID?
    private let smartBoardID: UUID?
    private let except: [PinAction]

    init(pins ids: Set<UUID>, side: PinScope, place: PinMenuPlace, actions: PinActions,
         boardID: UUID? = nil, smartBoardID: UUID? = nil, except: [PinAction] = []) {
        self.ids = ids
        self.side = side
        self.place = place
        self._actions = ObservedObject(wrappedValue: actions)
        self.boardID = boardID
        self.smartBoardID = smartBoardID
        self.except = except
    }

    var body: some View {
        let list = shownActions
        if !list.isEmpty {
            Group {
                selectItem(list)
                buttons(list, .look)
                submenu(.boards, list)
                buttons(list, .smartBoard)
                submenu(.editPicture, list)
                submenu(.thumbnail, list)
                submenu(.searchWeb, list)
                buttons(list, .edit)
            }
            Group {
                Divider()
                buttons(list, .keep)
                if !except.contains(.sortIntoBoards) { aiSortingMenu }
                buttons(list, .hide)
                buttons(list, .keepOut)
                if list.contains(.delete) {
                    Divider()
                    button(.delete)
                }
            }
        }
    }

    /// What the rules offer here, minus what the place shows elsewhere.
    private var shownActions: [PinAction] {
        let pins = ids.compactMap { store.livePin($0) }
        return PinActionRules.actions(for: pins, side: side, place: place, boardID: boardID,
                                      smartBoardID: smartBoardID, pinBoards: pinBoards(for: pins),
                                      coverBoards: coverBoards(for: pins),
                                      keptOutByBoard: keptOutByBoard(among: pins),
                                      onABoard: store.isAnyOnABoard(pins))
            .filter { !except.contains($0) }
    }

    /// The boards of the one pin that "Remove from board ▸" lists (a normal pin's hidden boards never).
    private func pinBoards(for pins: [Pin]) -> [UUID] {
        guard pins.count == 1, let pin = pins.first else { return [] }
        return store.shownBoardIDs(for: pin)
    }

    /// The boards the one pin may be the cover of — only boards of this side of the library.
    private func coverBoards(for pins: [Pin]) -> [Board] {
        guard pins.count == 1, let pin = pins.first, pin.hasImageFile else { return [] }
        let hidden = side == .hidden
        return store.coverCandidates(for: pin).filter { store.isSecretBoard($0.id) == hidden }
    }

    /// The pins that a board (or a board they are in) keeps out of All.
    private func keptOutByBoard(among pins: [Pin]) -> Set<UUID> {
        var kept: Set<UUID> = []
        for pin in pins where pin.boardIDs.contains(where: { (id: UUID) -> Bool in store.boardKeepsPinsOutOfAll(id) }) {
            kept.insert(pin.id)
        }
        return kept
    }

    /// "Select", and a line under it (a grid card's menu only).
    @ViewBuilder
    private func selectItem(_ list: [PinAction]) -> some View {
        if list.contains(.select) {
            button(.select)
            Divider()
        }
    }

    /// Plain buttons for the actions of one part of the menu, in the rules' order.
    private func buttons(_ list: [PinAction], _ part: PinMenuPart) -> some View {
        ForEach(list.filter { $0.menuPart == part }, id: \.self) { action in
            button(action)
        }
    }

    private func button(_ action: PinAction) -> some View {
        let label = action.label(count: ids.count)
        return Button(role: action == .delete ? .destructive : nil) {
            run(action)
        } label: {
            Label(label.text, systemImage: label.icon)
        }
        .disabled(isDimmed(action))
    }

    /// Dimmed: a job that changes pictures or saves files is running, or it is only a note
    /// ("Kept off by its board").
    private func isDimmed(_ action: PinAction) -> Bool {
        if action == .keptOutByBoard { return true }
        return actions.isBusy && PinActionRules.waitsForBusy(action)
    }

    // The submenus

    /// One submenu of related commands (see `PinMenuGroup`). With only one entry it is not worth a
    /// level: that entry sits in the menu itself. Off while a turn, save or sort is running, when
    /// all it offers waits for that.
    @ViewBuilder
    private func submenu(_ group: PinMenuGroup, _ list: [PinAction]) -> some View {
        let members = list.filter { $0.menuPart.group == group }
        let entries = PinActionRules.entryCount(of: group, in: list)
        if entries == 1 {
            groupEntries(group, members)
        } else if entries > 1 {
            Menu {
                groupEntries(group, members)
            } label: {
                Label(group.title, systemImage: group.icon)
            }
            .disabled(actions.isBusy && members.allSatisfy { PinActionRules.waitsForBusy($0) })
        }
    }

    /// What a submenu holds. "Boards" has buttons (add, move, remove from this board), then the
    /// submenus for the pin's other boards and for the covers; the others are plain buttons.
    @ViewBuilder
    private func groupEntries(_ group: PinMenuGroup, _ members: [PinAction]) -> some View {
        if group == .boards {
            buttons(members, .boardButtons)
            removeMenu(members)
            coverItems(members)
        } else {
            ForEach(members, id: \.self) { action in
                button(action)
            }
        }
    }

    /// "Remove from board ▸" with one entry per board of the one pin (its full path). Next to
    /// "Remove from this board" it reads "Remove from another board ▸".
    @ViewBuilder
    private func removeMenu(_ list: [PinAction]) -> some View {
        let boardIDs = list.compactMap { action -> UUID? in
            if case .removeFromBoard(let boardID) = action { return boardID }
            return nil
        }
        if let firstBoard = boardIDs.first {
            let label = PinAction.removeFromBoard(firstBoard).label(count: ids.count)
            Menu {
                ForEach(boardIDs, id: \.self) { boardID in
                    Button(store.boardPath(boardID) ?? "Board") { run(.removeFromBoard(boardID)) }
                }
            } label: {
                Label(offersThisBoard(list) ? "Remove from another board" : label.text, systemImage: label.icon)
            }
        }
    }

    /// "Remove from this board" is in the menu too.
    private func offersThisBoard(_ list: [PinAction]) -> Bool {
        list.contains { action in
            if case .removeFromThisBoard = action { return true }
            return false
        }
    }

    /// "Use as board cover": one board → a plain button that names it, "Use as cover of “Travel”"
    /// (the grid's own board, or the only board the pin could be the cover of); several → a
    /// submenu with each board's full path.
    @ViewBuilder
    private func coverItems(_ list: [PinAction]) -> some View {
        let covers = list.filter { $0.menuPart == .covers }
        if covers.count == 1, let only = covers.first {
            Button {
                run(only)
            } label: {
                Label(PinActionText.coverOf(coverBoardPath(only)), systemImage: only.label(count: ids.count).icon)
            }
        } else if let firstCover = covers.first {
            let label = firstCover.label(count: ids.count)
            Menu {
                ForEach(covers, id: \.self) { action in
                    Button(coverBoardPath(action)) { run(action) }
                }
            } label: {
                Label(label.text, systemImage: label.icon)
            }
        }
    }

    /// The full path of a cover action's board ("Travel › Beaches").
    private func coverBoardPath(_ action: PinAction) -> String {
        if case .useAsCover(let boardID) = action { return store.boardPath(boardID) ?? "Board" }
        return "Board"
    }

    /// "AI sorting" ▸ — its "Sort into boards" runs here, with progress and a result.
    private var aiSortingMenu: some View {
        AISortingMenu(target: .pins(ids, scope: side), prompt: $actions.aiPrompt,
                      sortIntoBoards: { run(.sortIntoBoards) })
    }

    private func run(_ action: PinAction) {
        actions.perform(action, on: ids, side: side, place: place, boardID: boardID)
    }
}

extension PinAction {
    /// The command's one name and symbol, for every menu and for the selection bar's buttons.
    /// An ellipsis means the command asks for something more (a board, tags, where to share)
    /// before it is done; Delete asks only "are you sure?", so it has none (as in Photos and
    /// Files). Hide and Unhide say "pins" when there are several.
    func label(count: Int) -> (text: String, icon: String) {
        switch self {
        case .select: return ("Select", "checkmark.circle")
        case .quickLook: return ("Quick look", "arrow.up.left.and.arrow.down.right")
        case .openLink: return ("Open link", "safari")
        case .addToBoard: return ("Add to board…", "folder.badge.plus")
        case .moveToBoard: return ("Move to board…", "arrow.turn.up.right")
        case .editLink: return ("Edit link…", "pencil")
        case .addLink: return ("Add link…", "link.badge.plus")
        case .editTags: return ("Edit tags…", "tag")
        case .removeFromThisBoard: return ("Remove from this board", "folder.badge.minus")
        case .removeFromBoard: return ("Remove from board", "folder.badge.minus")   // its submenu shows board paths
        case .removeFromSmartBoard: return ("Remove from this smart board", "minus.circle")
        case .useAsCover: return ("Use as board cover", "photo.on.rectangle")
        case .crop: return ("Crop…", "crop")
        case .rotateLeft: return ("Rotate left", "rotate.left")
        case .rotateRight: return ("Rotate right", "rotate.right")
        case .flipHorizontally: return ("Flip horizontally", "arrow.left.and.right.righttriangle.left.righttriangle.right")
        case .newThumbnail: return ("Pick another frame", "shuffle")
        case .thumbnailFromPhotos: return ("Choose from Photos…", "photo.on.rectangle")
        case .thumbnailFromPin: return ("Use a picture pin…", "pin")
        case .searchWeb(let engine): return (engine.label, "magnifyingglass")
        case .saveToPhotos: return ("Save to Photos", "square.and.arrow.down")
        case .share: return ("Share…", "square.and.arrow.up")
        case .generateColors: return ("Generate colors", "paintpalette")
        case .sortIntoBoards: return ("Sort into boards", "tray.and.arrow.down")
        case .hide: return (count == 1 ? "Hide pin" : "Hide pins", "eye.slash")
        case .unhide: return (count == 1 ? "Unhide pin" : "Unhide pins", "eye")
        case .keepOutOfAll: return ("Keep off Home page", "rectangle.stack.badge.minus")
        case .showInAll: return ("Show on Home page", "rectangle.stack.badge.plus")
        case .keptOutByBoard: return ("Kept off by its board", "rectangle.stack.badge.minus")
        case .delete: return ("Delete", "trash")
        }
    }
}

extension LibraryStore {
    /// Whether at least one of these pins is on a board of its own side (a hidden pin's
    /// out-of-sight normal boards don't count). Without one, menus offer "Add to board…" but
    /// not "Move to board…".
    func isAnyOnABoard(_ pins: [Pin]) -> Bool {
        pins.contains { (pin: Pin) -> Bool in !shownBoardIDs(for: pin).isEmpty }
    }
}
