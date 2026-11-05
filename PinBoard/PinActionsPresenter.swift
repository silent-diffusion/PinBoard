//
//  PinActionsPresenter.swift  —  PinBoard
//
//  Carrying the pin actions out: `.pinActions(_:)` attaches `PinActionsPresenter` to a screen, and it
//  does what the menus asked for — board pickers, the tag and link editors, the crop screen, the share
//  sheet, colours, questions and messages, thumbnails, web searches, Quick Look. What the menus offer
//  and how they are drawn is in PinActions.swift; this file is the doing. Split out of PinActions.swift
//  so each file stays a comfortable size to paste.
//

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - Carrying the actions out

extension View {
    /// Carries out the screen's pin actions: board pickers, tag editor, link editor, crop screen,
    /// share sheet, palette, delete question, Photos help, results, AI sorting dialogs, Quick Look,
    /// opening a link, thumbnails, web searches. `onSelectionDone` runs once an action asked for from
    /// the selection bar is done (the grid ends selection mode with it); `onSelect` runs for a card's
    /// "Select" (the grid starts selecting with that pin chosen).
    func pinActions(_ actions: PinActions, onSelectionDone: @escaping () -> Void = {},
                    onSelect: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(PinActionsPresenter(actions: actions, onSelectionDone: onSelectionDone, onSelect: onSelect))
    }
}

/// Does what the menus asked for. It reads the store, the settings and the import flow (for its
/// short messages), so `PinActions` itself needs none of them.
@MainActor
private struct PinActionsPresenter: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow
    /// The look of the screen the actions are asked for on (dark in Quick Look). Its sheets take it.
    @Environment(\.colorScheme) private var colorScheme
    /// Opens "Open link"'s page (in the default browser).
    @Environment(\.openURL) private var openURL
    @ObservedObject var actions: PinActions
    let onSelectionDone: () -> Void
    let onSelect: (UUID) -> Void

    /// The symbol of a short message that says something went wrong.
    private static let warning = "exclamationmark.triangle"

    @State private var sheet: PinActionRequest? = nil             // add, move, tags, link, share, colors, a web search's page or its Files picker
    @State private var cover: PinActionRequest? = nil             // crop: a full-screen editor, like Photos'
    @State private var quickLook: QuickLookRequest? = nil
    /// The delete asked about ("Delete this pin?"). Kept after the answer, so the question's
    /// title doesn't change while it closes; the next delete replaces it.
    @State private var toDelete: PinActionRequest? = nil
    @State private var askingDelete = false
    @State private var result: String? = nil
    @State private var showResult = false
    /// "Thumbnail ▸ Choose from Photos…" is waiting for a picture (see `PosterPhotoPicker`).
    @State private var posterPhoto: PinActionRequest? = nil
    @State private var showingPhotoPicker = false
    /// Originals fetched for the share sheet: temporary copies, by pin (see `share`).
    @State private var shareFiles: [UUID: URL] = [:]
    /// A web search that hands its picture over through Files: the temporary file the folder picker is
    /// saving (removed a few seconds after the picker has closed), and, once a place was chosen, the
    /// search that opens its page when the picker is gone (see `filePicked` and `goOnAfterPicker`).
    @State private var handoffFile: URL? = nil
    @State private var afterPicker: PinActionRequest? = nil
    /// The Files picker that has answered already (its request's id): a second answer is ignored.
    @State private var answeredPicker: UUID? = nil

    func body(content: Content) -> some View {
        content
            // The cards of this screen (grid video previews) stop decoding while Quick Look covers
            // them. Set on the screen's content only, not on the sheets and covers it presents.
            .environment(\.quickLookIsUp, actions.isShowingQuickLook)
            .onChange(of: actions.request?.id) { carryOut() }
            .sheet(item: $sheet, onDismiss: { sheetClosed() }) { request in
                sheetContent(for: request)
                    .hiddenPrivacyCover(request.side == .hidden)   // hidden pins never show in the App Switcher
                    // The sheet looks like the screen it came from, its UIKit parts too (a sheet
                    // over Quick Look would otherwise draw its text fields in the window's look).
                    .preferredColorScheme(colorScheme)
            }
            .fullScreenCover(item: $cover) { request in
                onePinScreen(for: request)
                    .hiddenPrivacyCover(request.side == .hidden)
                    .preferredColorScheme(.dark)   // a picture editor is dark (as in Photos), its bars too
            }
            .fullScreenCover(item: quickLookItem) { request in
                QuickLookView(request: request)
                    .onDisappear { actions.isShowingQuickLook = false }   // however it closed
            }
            .confirmationDialog(deleteQuestion.title, isPresented: $askingDelete, titleVisibility: .visible) {
                Button(PinAction.delete.label(count: deleteCount).text, role: .destructive) { delete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deleteQuestion.message)
            }
            .modifier(PinActionMessages(result: result, showResult: $showResult))
            .modifier(AISortingDialogs(prompt: $actions.aiPrompt))
            .modifier(PosterPhotoPicker(request: $posterPhoto, isShown: $showingPhotoPicker) { (asked: PinActionRequest, data: Data?) -> Void in
                posterPicked(asked, data: data)
            })
            .onChange(of: isPresentingAnything) { actions.isPresenting = isPresentingAnything }
    }

    /// Anything of this presenter's is up over the screen (see `PinActions.isPresenting`).
    private var isPresentingAnything: Bool {
        let questions = askingDelete || showResult || showingPhotoPicker
        return sheet != nil || cover != nil || quickLook != nil || questions || actions.aiPrompt != nil
    }

    /// How many pins the delete question is about.
    private var deleteCount: Int { toDelete?.ids.count ?? 1 }

    private var deleteQuestion: (title: String, message: String) {
        PinActionText.deleteQuestion(count: deleteCount, days: LibraryStore.trashRetentionDays)
    }

    /// Quick Look's cover. Closing it also tells the screen that Quick Look is gone.
    private var quickLookItem: Binding<QuickLookRequest?> {
        Binding(get: { quickLook }, set: { new in
            quickLook = new
            if new == nil { actions.isShowingQuickLook = false }
        })
    }

    /// The share sheet closes itself when sharing is done.
    private var sharePresented: Binding<Bool> {
        Binding(get: { sheet?.action == .share }, set: { shown in if !shown { sheet = nil } })
    }

    /// The sheet of an add, move, tags, link, share, colors or web search request.
    @ViewBuilder
    private func sheetContent(for request: PinActionRequest) -> some View {
        let count = PinActionText.pinCount(request.ids.count)
        switch request.action {
        case .addToBoard:
            BoardPickerSheet(title: "Add \(count) to…", noneLabel: nil, scope: request.side,
                             suggestFor: request.ids) { boardID in
                if let boardID { add(request, to: boardID) }
            }
        case .moveToBoard:
            BoardPickerSheet(title: "Move \(count) to…", noneLabel: "No board (Unsorted)", scope: request.side,
                             suggestFor: request.ids) { boardID in
                move(request, to: boardID)
            }
        case .editTags:
            TagEditorSheet(pinIDs: request.ids)
        case .share:
            ActivityShareSheet(items: shareItems(request.ids), isPresented: sharePresented)
                .presentationDetents([.medium, .large])
        case .generateColors:
            // Colors of exactly these pins ("Save as pin" goes to the grid's board, if any).
            PaletteSheet(title: count, pinIDs: Array(request.ids), boardID: request.boardID, scope: request.side)
        case .editLink, .addLink:
            onePinScreen(for: request)
        case .thumbnailFromPin:
            // A picture pin of the pin's own side: its picture becomes the video's thumbnail.
            PosterPinPickerSheet(side: request.side) { (pictureID: UUID) -> Void in
                posterFromPin(request, pictureID: pictureID)
            }
        case .searchWeb:
            searchSheet(for: request)
        default:
            EmptyView()   // the other actions open no sheet (Crop… opens a full-screen cover)
        }
    }

    /// A web search's sheet: Files' folder picker while the picture is being saved there, then (or
    /// from the start, for the other hand-overs) PinBoard's private browser. A hidden pin's sheet is
    /// covered in the App Switcher like every other hidden sheet (the sheet's own modifier does it).
    @ViewBuilder
    private func searchSheet(for request: PinActionRequest) -> some View {
        if let file = request.handoffFile {
            FolderExportPicker(url: file) { (saved: Bool) -> Void in
                filePicked(request, saved: saved)
            }
        } else if let url = request.url {
            PrivateBrowserSheet(url: url, hidden: request.side == .hidden)
        }
    }

    /// The screens that change one pin: "Edit link…" and "Add link…" (a sheet) and "Crop…" (a
    /// full-screen cover). A link pin's address is changed in the link editor; any other pin's link
    /// — the page it came from — in the small address sheet. (Chosen each time the sheet draws, from
    /// the pin as it is now.) If the pin is deleted while one of them is up (in another window, or
    /// merged away as a duplicate), it says so, with Close, instead of turning into an empty screen.
    @ViewBuilder
    private func onePinScreen(for request: PinActionRequest) -> some View {
        if let pin = onlyPin(request) {
            if request.action == .crop {
                CropEditorSheet(pin: pin) { finished(request) }
            } else if pin.isLink {
                EditLinkSheet(pin: pin) { url, title in
                    updateLink(request, url: url, title: title)
                }
            } else {
                SourceLinkEditor(pin: pin) { (address: String) -> Void in
                    saveSourceLink(request, address: address)
                }
            }
        } else {
            PinGoneNote()
        }
    }

    /// The one pin of a request for one pin (still in the library).
    private func onlyPin(_ request: PinActionRequest) -> Pin? {
        guard request.ids.count == 1, let id = request.ids.first else { return nil }
        return store.livePin(id)
    }

    // What each action does

    /// Carries out the request `perform` has just recorded.
    private func carryOut() {
        guard let request = actions.request else { return }
        switch request.action {
        case .select:
            if let id = request.ids.first { onSelect(id) }
        case .quickLook:
            openQuickLook(request)
        case .openLink:
            openLink(request)
        case .addToBoard, .moveToBoard, .editTags, .editLink, .addLink, .generateColors, .thumbnailFromPin:
            sheet = request
        case .newThumbnail:
            pickNewThumbnails(request)
        case .thumbnailFromPhotos:
            posterPhoto = request
        case .searchWeb(let engine):
            searchWeb(request, engine: engine)
        case .keepOutOfAll:
            setKeptOut(request, true)
        case .showInAll:
            setKeptOut(request, false)
        case .keptOutByBoard:
            importFlow.flash(PinActionText.keptOutByBoardNote, symbol: "info.circle")
        case .share:
            share(request)
        case .crop:
            cover = request
        case .removeFromThisBoard(let boardID), .removeFromBoard(let boardID):
            remove(request, from: boardID)
        case .removeFromSmartBoard(let smartBoardID):
            for id in request.ids { store.excludePin(id, fromSmartBoard: smartBoardID) }
            let name = request.side == .hidden ? "a hidden smart board" : (store.smartBoard(smartBoardID)?.name ?? "the smart board")
            importFlow.flash("Removed \(PinActionText.pinCount(request.ids.count)) from \(name).")
            finished(request)
        case .useAsCover(let boardID):
            if request.ids.count == 1, let id = request.ids.first { store.setCover(id, for: boardID) }
            finished(request)
        case .rotateLeft:
            turn(request, quarterTurns: -1, flip: false)
        case .rotateRight:
            turn(request, quarterTurns: 1, flip: false)
        case .flipHorizontally:
            turn(request, quarterTurns: 0, flip: true)
        case .saveToPhotos:
            saveToPhotos(request)
        case .sortIntoBoards:
            sortIntoBoards(request)
        case .hide, .unhide:
            setHidden(request, request.action == .hide)
        case .delete:
            toDelete = request   // asked first; see `delete()`
            askingDelete = true
        }
    }

    /// An action is done: one asked for from the selection bar ends selecting.
    private func finished(_ request: PinActionRequest) {
        if request.place == .selection { onSelectionDone() }
    }

    /// A board's name for a confirmation. On the hidden side it is just "a hidden board", so a
    /// confirmation still showing after you leave Hidden never names one.
    private func boardName(_ boardID: UUID?, side: PinScope) -> String {
        guard let boardID else { return "Unsorted" }
        if side == .hidden { return "a hidden board" }
        return store.board(boardID)?.name ?? "the board"
    }

    /// Opens Quick Look on the pin. From a grid it pages through the grid's pins in the grid's order
    /// (when the pin is among them; otherwise through related pins). From a pin's own page it
    /// says which pin that page is, so ⋯ › Show info on that same video just closes Quick Look
    /// instead of putting a second copy of the page on top of the first.
    private func openQuickLook(_ request: PinActionRequest) {
        guard let id = request.ids.first, let pin = store.livePin(id) else { return }
        actions.isShowingQuickLook = true
        let pages: [UUID]? = PinActionRules.quickLookPages(actions.quickLookPages?(), seed: id)
        let pageUnder: UUID? = PinActionRules.pinPageUnder(place: request.place, pin: id)
        quickLook = .library(seed: pin, pages: pages, pinPageUnder: pageUnder)
    }

    /// "Open link": the link pin's web page, in the default browser. (The menus offer it only for
    /// an http or https address, see `PinActionRules.linkToOpen`.)
    private func openLink(_ request: PinActionRequest) {
        guard let pin = onlyPin(request), let url = PinActionRules.linkToOpen(pin) else { return }
        openURL(url)
        finished(request)
    }

    /// "Edit link…" was saved: the store changes the address (and the title, when one is given)
    /// and fetches the page's title and preview again in the background where that is allowed.
    /// The action is done now — selecting ends at once — and a short message says whether anything
    /// changed as soon as the store has changed it, never waiting for the page to load.
    private func updateLink(_ request: PinActionRequest, url: URL, title: String?) {
        guard let id = request.ids.first else { return }
        finished(request)
        Task { @MainActor in
            let changed = await store.updateLinkPin(id, url: url, title: title)
            importFlow.flash(PinActionText.linkUpdated(changed), symbol: changed ? "checkmark.circle" : "info.circle")
        }
    }

    /// The address sheet's Save (`SourceLinkEditor`: "Edit link…" on a picture, video or text,
    /// "Add link…" on any pin): the store changes the pin's source link — "" takes it away — and
    /// a short message says what happened, in the words of the store's own answer. Nothing is
    /// fetched, so there is nothing to wait for.
    private func saveSourceLink(_ request: PinActionRequest, address: String) {
        guard let id = request.ids.first, let pin = store.livePin(id) else { return }
        let hadLink = PinActionRules.hasLink(pin)
        let changed = store.setSourceLink(of: id, to: address)
        let outcome = SourceLinkOutcome.of(hadLink: hadLink, typed: address, changed: changed)
        importFlow.flash(outcome.text, symbol: outcome.symbol)
        finished(request)
    }

    /// A sheet of this presenter has closed (however it closed): the share sheet's copies and the
    /// Files hand-over's temporary picture go, and a web search that was waiting for the Files
    /// picker to be gone goes on (see `filePicked`).
    private func sheetClosed() {
        discardShareFiles()
        discardHandoffFile()
        goOnAfterPicker()
    }

    /// A web search whose picture was saved through Files' folder picker opens its page and says so —
    /// once the picker is gone. A moment after it is gone, so the page's sheet never comes up while the
    /// picker is still closing (two sheets at once would fight; only one of them would show), and only
    /// if no other sheet came up meanwhile. Called when the sheet has closed and when the picker has
    /// answered: whichever comes last starts it, and a second call finds nothing waiting.
    private func goOnAfterPicker() {
        guard let waiting = afterPicker else { return }
        afterPicker = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard sheet == nil else { return }
            importFlow.flash(WebSearchHandoff.savedToFilesNote, symbol: "checkmark.circle")
            if let page = waiting.url { openSearch(page, for: waiting) }
            finished(waiting)
        }
    }

    /// Puts the pins on the board. The message says what really happened (a pin on one of the
    /// board's sub-boards is covered already; one on a board this one is inside moves down), in the
    /// words of the store's own answer.
    private func add(_ request: PinActionRequest, to boardID: UUID) {
        let asked = request.ids.filter { (id: UUID) -> Bool in store.pin(id) != nil }.count
        let result = store.addPins(request.ids, to: boardID)
        let plan = BoardAddPlan(result: result, asked: asked)
        settings.lastBoardID = boardID
        importFlow.flash(PinActionText.addedToBoard(plan, board: boardName(boardID, side: request.side)))
        finished(request)
    }

    /// Takes the pins off every other board (nil = Unsorted).
    private func move(_ request: PinActionRequest, to boardID: UUID?) {
        store.movePins(request.ids, to: boardID)
        if let boardID { settings.lastBoardID = boardID }
        importFlow.flash("Moved \(PinActionText.pinCount(request.ids.count)) to \(boardName(boardID, side: request.side)).")
        finished(request)
    }

    /// Takes the pins off one board (they stay on their other boards).
    private func remove(_ request: PinActionRequest, from boardID: UUID) {
        let onIt = request.ids.filter { store.pin($0)?.isOn(boardID) == true }
        store.removePins(request.ids, from: boardID)
        if !onIt.isEmpty {
            importFlow.flash("Removed \(PinActionText.pinCount(onIt.count)) from \(boardName(boardID, side: request.side)).")
        }
        finished(request)
    }

    /// "Hide pin" on the normal side, "Unhide pin" on the hidden side.
    private func setHidden(_ request: PinActionRequest, _ hide: Bool) {
        if hide {
            store.hidePins(request.ids)
            importFlow.flash(PinActionText.hid(request.ids.count))
        } else {
            store.unhidePins(request.ids)
            importFlow.flash("Unhid \(PinActionText.pinCount(request.ids.count)).")
        }
        finished(request)
    }

    /// After "Delete" in the question: the pins go to Recently Deleted.
    private func delete() {
        guard let request = toDelete else { return }
        store.deletePins(request.ids)
        finished(request)
    }

    /// "Keep out of All" / "Show in All". A pin's own setting changes; a pin that a board keeps out
    /// stays out after "Show in All", and the message says so. (Only the normal side: hidden pins
    /// are never in All.)
    private func setKeptOut(_ request: PinActionRequest, _ keep: Bool) {
        guard request.side == .visible else { return }
        let pins = request.ids.compactMap { store.livePin($0) }
        if keep {
            let showing = pins.filter { (pin: Pin) -> Bool in !store.isKeptOutOfAll(pin) }
            store.setKeptOutOfAll(Set(pins.filter { (pin: Pin) -> Bool in !pin.keptOutOfAll }.map { (pin: Pin) -> UUID in pin.id }), true)
            if !showing.isEmpty { importFlow.flash(PinActionText.keptOut(showing.count)) }
        } else {
            let own = pins.filter { (pin: Pin) -> Bool in pin.keptOutOfAll }
            let ids = Set(own.map { (pin: Pin) -> UUID in pin.id })
            store.setKeptOutOfAll(ids, false)
            let stillKept = ids.filter { (id: UUID) -> Bool in
                store.livePin(id).map { (pin: Pin) -> Bool in store.isKeptOutOfAll(pin) } ?? false
            }
            if !ids.isEmpty { importFlow.flash(PinActionText.shownInAll(ids.count, stillKept: stillKept.count)) }
        }
        finished(request)
    }

    /// "Thumbnail ▸ Pick another frame": a new poster for each video, one after the other, so the
    /// pill (on the pins' side) can say "Picking new thumbnails 2 of 5…". A short message at the end.
    private func pickNewThumbnails(_ request: PinActionRequest) {
        let videos = request.ids.filter { (id: UUID) -> Bool in store.pin(id)?.isVideo == true }
        guard !videos.isEmpty, !actions.isBusy else { return }
        actions.isBusy = true
        let side = request.side
        Task { @MainActor in
            var changed = 0
            var shown: String? = nil
            for (index, id) in videos.enumerated() {
                let status = PinActionText.pickingThumbnails(number: index + 1, of: videos.count)
                shown = status
                store.setImportStatus(status, scope: side)
                changed += await store.pickAnotherPoster(for: [id])
            }
            if let shown, store.importStatus == shown { store.setImportStatus(nil, scope: side) }
            actions.isBusy = false
            let outcome = PinActionText.thumbnailsChanged(changed, of: videos.count)
            importFlow.flash(outcome.text, symbol: outcome.problem ? PinActionsPresenter.warning : "checkmark.circle")
            finished(request)
        }
    }

    /// "Thumbnail ▸ Choose from Photos…": the picture the person chose becomes the video's poster.
    private func posterPicked(_ request: PinActionRequest, data: Data?) {
        guard let id = request.ids.first, let data else {
            importFlow.flash(PinActionText.thumbnailSet(false), symbol: PinActionsPresenter.warning)
            return
        }
        Task { @MainActor in
            let done = await store.setPoster(for: id, imageData: data)
            importFlow.flash(PinActionText.thumbnailSet(done), symbol: done ? "checkmark.circle" : PinActionsPresenter.warning)
            finished(request)
        }
    }

    /// "Thumbnail ▸ Use a picture pin…": that pin's picture becomes the video's poster.
    private func posterFromPin(_ request: PinActionRequest, pictureID: UUID) {
        guard let id = request.ids.first else { return }
        Task { @MainActor in
            let done = await store.setPoster(for: id, fromPictureOf: pictureID)
            importFlow.flash(PinActionText.thumbnailSet(done), symbol: done ? "checkmark.circle" : PinActionsPresenter.warning)
            finished(request)
        }
    }

    /// "Search on the web ▸": a reverse image search for the one pin's picture (a picture, a
    /// video's poster, a link's preview). The picture lives only in the library, so it has no web
    /// address and the search site can't be sent a link to it: its file is read (off the main
    /// thread) and handed over the way Settings › Explore & web search › "Hand the picture over by" says — on the
    /// clipboard (two minutes, this device only), in a folder in Files, or in Photos — and the
    /// site's upload page opens, in PinBoard's private browser or in the default browser, as
    /// chosen in Settings. A hidden pin's picture always goes on the clipboard, whatever is chosen
    /// (a copy in Photos or Files would stay for good). The person then uploads the picture there.
    private func searchWeb(_ request: PinActionRequest, engine: ReverseImageEngine) {
        guard let pin = onlyPin(request), pin.hasImageFile else { return }
        if store.isOffloaded(pin) {
            // Kept in iCloud only: it comes back first (Offloading.swift).
            Task { @MainActor in
                if await store.ensureLocal(pin) {
                    searchWeb(request, engine: engine)
                } else {
                    importFlow.flash(PinActionText.notFromICloud(1), symbol: PinActionsPresenter.warning)
                }
            }
            return
        }
        let file = store.imageFileURL(for: pin)
        // A hidden pin's picture goes to the clipboard only, whatever Settings says (`WebSearchHandoff.plan`).
        // Both the side the menu was opened on and the pin itself are asked, so no path can miss it.
        let hidden = request.side == .hidden || store.isHidden(pin)
        let step = WebSearchHandoff.plan(setting: settings.webSearchPictureHandoff, hidden: hidden)
        Task { @MainActor in
            let data = await PinActionsPresenter.readPicture(at: file)
            guard store.livePin(pin.id) != nil else { return }   // deleted meanwhile (or another profile's library now)
            // A picture that can't be read (a file still in iCloud, a file gone) would open an empty
            // upload page and say nothing: say so and stay where we are.
            guard let data else {
                importFlow.flash(PinActionText.pictureUnreadable, symbol: PinActionsPresenter.warning)
                finished(request)
                return
            }
            switch step {
            case .clipboard:
                handOverByClipboard(request, engine: engine, data: data, note: nil)
            case .photos:
                await handOverByPhotos(request, engine: engine, data: data)
            case .files:
                await handOverByFiles(request, engine: engine, pin: pin, hidden: hidden, data: data)
            }
        }
    }

    /// The picture goes on the clipboard (for two minutes, on this device only) and the site's
    /// upload page opens; the person pastes it there. `note`: said instead of the usual clipboard
    /// message when there is more to tell.
    private func handOverByClipboard(_ request: PinActionRequest, engine: ReverseImageEngine, data: Data, note: String?) {
        let target = WebSearchOpening.destination(engine, imageURL: nil, pictureData: data)
        // Bytes that aren't a picture: nothing went to the clipboard, so the page would be empty too.
        guard target.copiedPicture else {
            importFlow.flash(PinActionText.pictureUnreadable, symbol: PinActionsPresenter.warning)
            finished(request)
            return
        }
        openSearch(target.url, for: request)
        if let note {
            importFlow.flash(note, symbol: "info.circle")
        } else if let copied = WebSearchOpening.copiedNote(target.copiedPicture) {
            importFlow.flash(copied, symbol: "doc.on.clipboard")
        }
        finished(request)
    }

    /// The picture is saved to Photos (it lands in Recents, as the newest picture) and the site's
    /// upload page opens; the person picks it there. If Photos doesn't take it (access refused),
    /// that is said and no page opens — it would have nothing to upload.
    private func handOverByPhotos(_ request: PinActionRequest, engine: ReverseImageEngine, data: Data) async {
        guard let image = UIImage(data: data) else {
            importFlow.flash(PinActionText.pictureUnreadable, symbol: PinActionsPresenter.warning)
            finished(request)
            return
        }
        let saved = await PhotosSaver.save(image)
        guard saved else {
            importFlow.flash(PhotosSaver.problem(WebSearchHandoff.photosRefusedNote), symbol: PinActionsPresenter.warning)
            finished(request)
            return
        }
        openSearch(ReverseImageSearch.uploadURL(engine), for: request)
        importFlow.flash(WebSearchHandoff.savedToPhotosNote, symbol: "photo.badge.checkmark")
        finished(request)
    }

    /// The picture is written to a temporary file and Files' folder picker comes up (a sheet of
    /// this presenter, so a hidden pin's is covered in the App Switcher like the others): the
    /// person chooses where it goes. When a place was chosen the page opens, after the picker has
    /// closed (see `filePicked` and `goOnAfterPicker`); Cancel opens nothing.
    private func handOverByFiles(_ request: PinActionRequest, engine: ReverseImageEngine, pin: Pin, hidden: Bool, data: Data) async {
        // Bytes that aren't a picture would save a file nobody can open.
        guard UIImage(data: data) != nil else {
            importFlow.flash(PinActionText.pictureUnreadable, symbol: PinActionsPresenter.warning)
            finished(request)
            return
        }
        // (A hidden pin never reaches Files, but if it ever did, its title must not become a file name.)
        let name = WebSearchHandoff.fileName(title: pin.title, hidden: hidden)
        guard let file = await PinActionsPresenter.writeHandoffFile(data, named: name) else {
            importFlow.flash(WebSearchHandoff.filesFailedNote, symbol: PinActionsPresenter.warning)
            finished(request)
            return
        }
        guard sheet == nil else {   // (another sheet came up meanwhile: two at once would fight)
            WebSearchHandoff.discard(file)
            return
        }
        handoffFile = file
        sheet = PinActionRequest(action: request.action, ids: request.ids, side: request.side, place: request.place,
                        boardID: request.boardID, url: ReverseImageSearch.uploadURL(engine), handoffFile: file)
    }

    /// Files' folder picker has answered: a place was chosen (`saved`) or not (Cancel). The picker
    /// closes first; the page and the message follow once it is gone (`goOnAfterPicker`), because the
    /// picker and the browser's sheet can't be up at once. The picker may close itself a moment before
    /// it says so (then nothing is left to close here) — either way the page opens once, and only after
    /// a save. Told twice: the second answer is ignored.
    private func filePicked(_ request: PinActionRequest, saved: Bool) {
        guard answeredPicker != request.id else { return }
        answeredPicker = request.id
        if saved { afterPicker = request }
        if sheet?.id == request.id {
            sheet = nil            // closes the picker; `sheetClosed` goes on from there
        } else {
            goOnAfterPicker()      // the picker had closed already
        }
    }

    /// Removes the picture that was written for the Files picker. A few seconds after the picker has
    /// closed, not at that very moment: Files makes its copy while the picker closes, and the copy
    /// must never lose its original half way.
    private func discardHandoffFile() {
        guard let file = handoffFile else { return }
        handoffFile = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            WebSearchHandoff.discard(file)
        }
    }

    /// The picture file's bytes, read off the main thread (nil when it can't be read).
    nonisolated private static func readPicture(at url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            try? Data(contentsOf: url)
        }.value
    }

    /// Writes the picture to a temporary file for the Files picker, off the main thread (nil when
    /// it can't be written). Pictures left over from an earlier run are cleared away first.
    nonisolated private static func writeHandoffFile(_ data: Data, named name: String) async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            WebSearchHandoff.removeOldFiles()
            return WebSearchHandoff.writeTemporaryFile(data, named: name)
        }.value
    }

    /// Opens a search page: in the default browser, or in PinBoard's private browser (a sheet; a
    /// hidden pin's sheet is covered in the App Switcher like every other one).
    private func openSearch(_ url: URL, for request: PinActionRequest) {
        if settings.webSearchBrowser == .safari {   // (the stored name of "Default browser")
            UIApplication.shared.open(url)
        } else {
            sheet = PinActionRequest(action: request.action, ids: request.ids, side: request.side,
                            place: request.place, boardID: request.boardID, url: url)
        }
    }

    /// Turns or flips the pictures among the pins (other kinds stay as they are). Nothing is said
    /// when it works — the pictures visibly turn; a short message says what couldn't be turned.
    private func turn(_ request: PinActionRequest, quarterTurns: Int, flip: Bool) {
        let targets = request.ids.filter { store.pin($0)?.kind == .image }
        guard !targets.isEmpty, !actions.isBusy else { return }
        actions.isBusy = true
        Task { @MainActor in
            var done = 0
            for id in targets {
                if await store.transformImage(id, quarterTurns: quarterTurns, flipHorizontally: flip) { done += 1 }
            }
            actions.isBusy = false
            if let problem = PinActionText.turnProblem(done: done, of: targets.count) {
                importFlow.flash(problem, symbol: PinActionsPresenter.warning)
            }
            finished(request)
        }
    }

    /// Saves the pictures and videos among the pins to Photos (add-only access: iOS asks the
    /// first time). A pin whose full-size original was kept (Settings › iCloud & storage) saves the original —
    /// fetched first, "Fetching the original…" on the pin's side — or, when it can't be fetched,
    /// the copy on this device (the message then says so). How it went is a short message.
    private func saveToPhotos(_ request: PinActionRequest) {
        guard !actions.isBusy else { return }
        let targets = request.ids.compactMap { store.livePin($0) }.filter { $0.hasImageFile || $0.isVideo }
        actions.isBusy = true
        Task { @MainActor in
            let outcome = await saveEach(targets, side: request.side)
            actions.isBusy = false
            if let done = PinActionText.savedToPhotos(outcome.saved, fellBack: outcome.fellBack) {
                importFlow.flash(done, symbol: outcome.fellBack > 0 ? PinActionsPresenter.warning : "checkmark.circle")
            } else {
                importFlow.flash(PhotosSaver.problem("Nothing could be saved to Photos."), symbol: PinActionsPresenter.warning)
            }
            finished(request)
        }
    }

    /// Saves the pins to Photos one at a time. A pin with a kept original: the original is
    /// fetched, copied, saved, and the copy removed before the next pin — so only one original's
    /// copy ever takes room here (ten 2 GB videos never need 40 GB at once). One that doesn't come
    /// (`fellBack`) saves the copy on this device instead. How long each is waited for: see
    /// `OriginalFetcher`.
    private func saveEach(_ pins: [Pin], side: PinScope) async -> (saved: Int, fellBack: Int) {
        var saved = 0
        var fellBack = 0
        var fetcher = OriginalFetcher(total: pins.filter(PinActionsPresenter.hasOriginal).count, side: side)
        for pin in pins {
            if PinActionsPresenter.hasOriginal(pin) {
                if let copy = await fetcher.copy(of: pin, store: store) {
                    let done = await PinActionsPresenter.saveOriginal(copy, isVideo: pin.isVideo)
                    OriginalsFolder.discardTemporaryCopy(copy)
                    if done {
                        saved += 1
                        continue
                    }
                } else {
                    fellBack += 1
                }
            }
            if await saveDeviceCopy(of: pin) { saved += 1 }
        }
        fetcher.finish(store: store)
        return (saved, fellBack)
    }

    /// Saves the copy kept on this device: a picture as it is shown, a video as it is.
    private func saveDeviceCopy(of pin: Pin) async -> Bool {
        guard await store.ensureLocal(pin) else { return false }   // kept in iCloud only and couldn't come back
        if pin.isVideo { return await PhotosSaver.saveVideo(at: store.videoFileURL(for: pin)) }
        guard let image = await store.fullImage(for: pin) else { return false }
        return await PhotosSaver.save(image)
    }

    /// Saves a fetched original's copy (the file itself, so Photos gets it exactly as it was).
    private static func saveOriginal(_ copy: URL, isVideo: Bool) async -> Bool {
        if isVideo { return await PhotosSaver.saveVideo(at: copy) }
        return await PhotosSaver.saveImageFile(at: copy)
    }

    /// A picture or video whose full-size original was kept (Settings › iCloud & storage).
    nonisolated private static func hasOriginal(_ pin: Pin) -> Bool {
        pin.originalName != nil && (pin.kind == .image || pin.isVideo)
    }

    /// "Share…": a picture or video whose full-size original was kept shares the original —
    /// fetched first ("Fetching the original…" on the pin's side), then the share sheet opens.
    /// One that can't be fetched shares the copy on this device, and a short message says so.
    private func share(_ request: PinActionRequest) {
        // Pictures and videos kept in iCloud only come back first (Offloading.swift).
        let offloaded = request.ids.compactMap { store.livePin($0) }.filter { store.isOffloaded($0) }
        guard !offloaded.isEmpty else {
            shareHere(request)
            return
        }
        guard !actions.isBusy else { return }
        actions.isBusy = true
        Task { @MainActor in
            let missing = await store.ensureLocal(offloaded)
            actions.isBusy = false
            if missing > 0 { importFlow.flash(PinActionText.notFromICloud(missing), symbol: PinActionsPresenter.warning) }
            shareHere(request)
        }
    }

    /// "Share…" once every file is on this device.
    private func shareHere(_ request: PinActionRequest) {
        discardShareFiles()
        let withOriginals = request.ids.compactMap { store.livePin($0) }.filter(PinActionsPresenter.hasOriginal)
        guard !withOriginals.isEmpty else {
            sheet = request
            return
        }
        guard !actions.isBusy else { return }
        actions.isBusy = true
        Task { @MainActor in
            let originals = await fetchOriginalCopies(of: withOriginals, side: request.side)
            actions.isBusy = false
            shareFiles = originals.files
            sheet = request
            if originals.missing > 0 {
                importFlow.flash(PinActionText.sharingCopies(originals.missing), symbol: PinActionsPresenter.warning)
            }
        }
    }

    /// Fetches the originals of `pins` and copies each one for the share sheet (it reads the files
    /// itself: see `OriginalsFolder.temporaryCopy`), one after another (see `OriginalFetcher`).
    /// The pill of `side` says "Fetching the original…" meanwhile. `missing`: how many didn't come.
    private func fetchOriginalCopies(of pins: [Pin], side: PinScope) async -> FetchedOriginals {
        var fetched = FetchedOriginals()
        var fetcher = OriginalFetcher(total: pins.count, side: side)
        for pin in pins {
            if let copy = await fetcher.copy(of: pin, store: store) {
                fetched.files[pin.id] = copy
            } else {
                fetched.missing += 1
            }
        }
        fetcher.finish(store: store)
        return fetched
    }

    /// The share sheet's temporary copies go once it has closed — half a minute later, so an app
    /// still reading one (AirDrop, Mail) isn't cut off. Leftovers go at the next launch.
    private func discardShareFiles() {
        let files = Array(shareFiles.values)
        shareFiles = [:]
        guard !files.isEmpty else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            for file in files { OriginalsFolder.discardTemporaryCopy(file) }
        }
    }

    /// AI sorting › Sort into boards: puts each pin on the board the AI suggests. Pins moved: a
    /// short message. None moved: an alert, because it explains why and what to try.
    private func sortIntoBoards(_ request: PinActionRequest) {
        guard !actions.isBusy else { return }
        actions.isBusy = true
        Task { @MainActor in
            let moved = await store.autoSort(request.ids)
            actions.isBusy = false
            if moved > 0 {
                importFlow.flash(PinActionText.sorted(moved: moved, of: request.ids.count))
                finished(request)
            } else {
                show(AISortingText.sortResult(moved: 0, of: request.ids.count,
                                              hasBoards: !store.rootBoards(scope: request.side).isEmpty))
            }
        }
    }

    /// Files and text for the share sheet, newest pin first. A picture or video shares its
    /// fetched original when there is one (`shareFiles`), else the copy on this device. A link whose
    /// address can't be read is shared as its title (so the sheet is never empty).
    private func shareItems(_ ids: Set<UUID>) -> [Any] {
        let pins = ids.compactMap { store.livePin($0) }.sorted { $0.createdAt > $1.createdAt }
        return pins.compactMap { pin -> Any? in
            switch pin.kind {
            case .text: return pin.textBody.isEmpty ? pin.title : pin.textBody
            case .link:
                if let url = pin.linkURL.flatMap({ URL(string: $0) }) { return url }
                return pin.title.isEmpty ? pin.linkURL : pin.title
            case .video: return shareFiles[pin.id] ?? (store.isOffloaded(pin) ? nil : store.videoFileURL(for: pin))
            case .image: return shareFiles[pin.id] ?? (store.isOffloaded(pin) ? nil : store.imageFileURL(for: pin))
            }
        }
    }

    /// An alert that explains something (a sort that moved nothing says why).
    private func show(_ text: String) {
        result = text
        showResult = true
    }
}

/// "Thumbnail ▸ Choose from Photos…": shows the system photo picker (one picture) when a request
/// comes in, and hands the picture's bytes (nil when it couldn't be loaded) back with the request.
@MainActor
private struct PosterPhotoPicker: ViewModifier {
    @Binding var request: PinActionRequest?
    /// Whether the picker is up (the presenter reads it for `PinActions.isPresenting`).
    @Binding var isShown: Bool
    let onPicked: (PinActionRequest, Data?) -> Void

    @State private var item: PhotosPickerItem? = nil
    /// The request the picker was opened for (the binding is cleared as soon as it opens).
    @State private var pending: PinActionRequest? = nil

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isShown, selection: $item, matching: .images)
            .onChange(of: request?.id) { open() }
            .onChange(of: item) { _, picked in
                guard let picked, let asked = pending else { return }
                item = nil
                pending = nil
                Task { @MainActor in
                    let data = try? await picked.loadTransferable(type: Data.self)
                    onPicked(asked, data)
                }
            }
    }

    private func open() {
        guard let asked = request else { return }
        pending = asked
        request = nil
        isShown = true
    }
}

/// Originals fetched for the share sheet: a temporary copy per pin, and how many didn't come (the
/// copies on this device are used for those).
private struct FetchedOriginals {
    var files: [UUID: URL] = [:]
    var missing = 0
}

/// Fetches originals one after another for Save to Photos or Share, saying "Fetching originals 2
/// of 5…" on the pill of `side`. The first is waited for up to 45 seconds
/// (`OriginalsFolder.sharingPatience`); once one didn't come, the rest are taken only when they are
/// here already — they would most likely not come either (offline), and each would wait again.
/// (The pin page's Cancel stops a fetch too: it then counts as not come.)
@MainActor
private struct OriginalFetcher {
    let total: Int
    let side: PinScope
    private var number = 0
    private var patience = OriginalsFolder.sharingPatience
    private var shown: String? = nil

    init(total: Int, side: PinScope) {
        self.total = total
        self.side = side
    }

    /// A temporary copy of `pin`'s original for Photos or the share sheet; nil when it didn't come
    /// (or couldn't be copied: no room).
    mutating func copy(of pin: Pin, store: LibraryStore) async -> URL? {
        number += 1
        let status = StorageText.fetchingStatus(number: number, of: total)
        shown = status
        store.setImportStatus(status, scope: side)
        guard let url = await store.fetchOriginalURL(for: pin, patience: patience) else {
            patience = 0
            return nil
        }
        return await OriginalsFolder.temporaryCopy(of: url)
    }

    /// Clears the pill, when it still shows these words.
    func finish(store: LibraryStore) {
        if let shown, store.importStatus == shown { store.setImportStatus(nil, scope: side) }
    }
}

/// A sort that moved nothing (the alert says why), and what to do when saving to Photos isn't
/// set up yet. Everything else is told with a short message (ImportFlow's `flash`).
@MainActor
private struct PinActionMessages: ViewModifier {
    let result: String?
    @Binding var showResult: Bool

    func body(content: Content) -> some View {
        content
            .alert(result ?? "", isPresented: $showResult) {
                Button("OK", role: .cancel) { }
            }
    }
}

/// "Edit link…": the link editor (LinkPins.swift) for one link pin. Saving hands over the new
/// address and the title — nil when the title is to stay as it is.
struct EditLinkSheet: View {
    let pin: Pin
    let onSave: (_ url: URL, _ title: String?) -> Void

    var body: some View {
        LinkPinEditorSheet(editing: pin, onSave: onSave)
    }
}

/// What a sheet or cover for one pin (Edit link…, Crop…) shows when its pin was deleted while it
/// was up: a short note and Close, instead of an empty screen. On an iPad keyboard, Escape closes.
struct PinGoneNote: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "pin.slash", title: "This pin is gone", message: "")
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
