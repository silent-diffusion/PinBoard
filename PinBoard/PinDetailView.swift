//
//  PinDetailView.swift  —  PinBoard
//
//  One pin — yours, or a web result shown exactly like one (a "draft" that
//  is analyzed on the device and can be saved). Swipe on the picture to move
//  to the previous / next item of the list it was opened from. Underneath:
//  "More like this" from your library, then, on request, results from the web
//  in the same scroll. This file holds the page itself (its state, layout,
//  toolbar and actions); its media box, info sections and bottom feeds are in
//  PinPageContent.swift, the duplicate pair card and its merge sheet in
//  DuplicatePairs.swift.
//

import SwiftUI
import UIKit
import Foundation

enum PinFeedMode: String, CaseIterable, Identifiable {
    case related, web
    var id: String { rawValue }
}

/// "Use this frame as thumbnail" on a pin's page (plain rules; the harness tests them).
enum PinPageFrameThumbnail {
    /// Offered for a video pin that is stored (not a web result) while its player is paused on a
    /// frame (`canUseFrame`: paused, loaded, not failed).
    nonisolated static func isOffered(kind: PinKind, isDraft: Bool, canUseFrame: Bool) -> Bool {
        kind == .video && !isDraft && canUseFrame
    }

    /// The short message afterwards (the same words Quick Look's item uses).
    nonisolated static func message(changed: Bool) -> String {
        changed ? "Thumbnail changed" : "Couldn't change the thumbnail"
    }
}

/// The two rows of a pin's page that say where the pin came from (plain rules; the harness tests them).
enum PinPageSourceRows {
    /// The pencil beside "Open source page": a stored picture, video or text pin can have its link
    /// changed from there (the address sheet in PinActions.swift). A link pin has its own pencil
    /// beside its link panel, so it gets none here, and a web result that isn't saved yet has no
    /// link of its own to change.
    nonisolated static func offersEditLink(kind: PinKind, isDraft: Bool) -> Bool {
        !isDraft && kind != .link
    }

    /// The words of the row on a quote pin (an article's highlight saved as a pin): "From the
    /// article “Why cats purr”", or just "From the article" when the article has no title, or is not
    /// to be named here (gone, or on the other side of the hidden line).
    nonisolated static func quoteRowText(articleTitle: String?) -> String {
        let title = articleTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "From the article" : "From the article “\(title)”"
    }

    /// The article a quote pin's row may name and open: only one that is still in the library (not
    /// deleted) and on the same side of the hidden line as the page `pageScope`. Otherwise nil, and
    /// the row is plain text — the title of a hidden article must never show on the normal side
    /// (say, when it was hidden after the quote was saved), nor the other way round.
    @MainActor
    static func articleToName(for pin: Pin, in store: LibraryStore, pageScope: PinScope) -> Pin? {
        guard let articleID = pin.quotedFromID, let article = store.livePin(articleID) else { return nil }
        return store.scope(of: article) == pageScope ? article : nil
    }
}

/// Where the two small marks over the media box sit: the corner "expand" mark that shows a picture
/// opens Quick Look, and the "Swipe for next" hint (plain rules; the harness tests them).
///
/// One column: the bottom corners, as they always were. Two columns: a picture or video fills its
/// whole column and can be much taller than the window (up to 2.5 × its width), so a mark at the
/// bottom would be below the fold when the page opens, and the hint would never be seen. There they
/// go to the top corners. A text pin keeps its hint at the bottom even then: its words start at the
/// top, and a mark there would cover the first line.
enum PinPageMediaMarks {
    /// The picture's corner mark (only pictures have one).
    nonisolated static func quickLookMark(columns: PinPageLayout.Columns) -> Alignment {
        columns == .two ? .topTrailing : .bottomTrailing
    }

    /// The "Swipe for next" / "Swipe back" hint over a picture, text or link (a video's hint sits
    /// under its player, where its controls are).
    nonisolated static func swipeHint(columns: PinPageLayout.Columns, isText: Bool) -> Alignment {
        (columns == .two && !isText) ? .topLeading : .bottomLeading
    }
}

/// Which board picker the pin page has open (a web result's "Save to board…"; a stored
/// pin's pickers are PinActions.swift's).
enum PinBoardPicker: String, Identifiable {
    case save
    var id: String { rawValue }
}

// MARK: - Draft pins (web results before they are saved)

@MainActor
final class DraftPinModel: ObservableObject {
    enum Status: Equatable {
        case idle, loading, analyzing, ready
        case failed(String)
    }

    @Published var pin = Pin()
    @Published var image: UIImage? = nil
    @Published var status: Status = .idle
    @Published var savedID: UUID? = nil
    var imageData: Data? = nil
    var featurePrintData: Data? = nil
    private var loadedFor: String = ""
    private var loadToken = UUID()      // one per load: an older load that is still running stops touching state

    /// Forgets the previous item the moment the page moves on, so nothing of it
    /// shows while the next one loads.
    func prepare(for web: WebImage) {
        guard loadedFor != web.id else { return }
        loadedFor = ""
        savedID = nil
        image = nil
        imageData = nil
        featurePrintData = nil
        status = .idle
    }

    /// Starts over for the same web image (after a failed download).
    func retry(_ web: WebImage, scope: PinScope, boardIDs: [UUID], store: LibraryStore, settings: AppSettings) async {
        loadedFor = ""
        status = .idle
        await load(web, scope: scope, boardIDs: boardIDs, store: store, settings: settings)
    }

    /// Downloads the web image and runs the same analysis a saved pin gets. `scope`: the side of
    /// the library the result would be saved to (Hidden for a result from a hidden feed).
    /// `boardIDs`: the boards its feed saves to (a board page's feed: that board). The draft
    /// starts out on them, so the page shows them and Save puts it there.
    func load(_ web: WebImage, scope: PinScope, boardIDs: [UUID], store: LibraryStore, settings: AppSettings) async {
        guard loadedFor != web.id else { return }
        loadedFor = web.id
        let token = UUID()
        loadToken = token
        savedID = nil
        image = nil
        imageData = nil
        featurePrintData = nil

        // Already on this side of the library? Show the real pin instead. A pin saved on the
        // other side never shows up here.
        if let existing = store.pinID(forSourceURL: web.pageURL.absoluteString, scope: scope) {
            savedID = existing
            status = .ready
            return
        }

        var draft = Pin()
        draft.isHidden = scope == .hidden   // suggestions, "More like this" and saving stay on its side
        draft.boardIDs = boardIDs
        // The web page's own title is kept as it is (it counts as imported, not typed
        // and not the AI's); the AI only titles untitled pictures.
        let webTitle = web.title.map { TitleGenerator.shorten($0, to: 60) } ?? ""
        if !webTitle.isEmpty { draft.setImportedTitle(webTitle) }
        draft.sourceURL = web.pageURL.absoluteString
        draft.credit = web.credit
        draft.width = web.width
        draft.height = web.height
        pin = draft
        status = .loading

        let url = web.fullURL
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString).jpg")
        let accurate = settings.accurateOCR
        // A result from a hidden feed becomes a hidden pin: no AI looks at it unless "Include hidden
        // pins in AI" is on (the fixed checks still run; it is marked to get the AI's look later).
        let usesAI = scope == .visible || settings.aiIncludesHidden
        struct Loaded: @unchecked Sendable { var data: Data?; var image: UIImage?; var analysis: AnalysisResult?; var width: Double; var height: Double }
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            guard let data = try? await WebImageService.download(url),
                  let full = ImageProcessor.downsample(data, maxPixelSize: 2048),
                  let jpeg = ImageProcessor.jpegData(full, quality: 0.9) else {
                return Loaded(data: nil, image: nil, analysis: nil, width: 1, height: 1)
            }
            try? jpeg.write(to: tempURL, options: .atomic)
            let analysis = VisionAnalyzer.analyze(imageURL: tempURL, accurateText: accurate, usesAI: usesAI)
            try? FileManager.default.removeItem(at: tempURL)
            return Loaded(data: jpeg, image: UIImage(cgImage: full), analysis: analysis, width: Double(full.width), height: Double(full.height))
        }.value
        guard loadToken == token, !Task.isCancelled else { return }
        guard let data = loaded.data, let image = loaded.image, let analysis = loaded.analysis else {
            status = .failed("This image couldn't be downloaded.")
            return
        }
        self.image = image
        imageData = data
        featurePrintData = analysis.featurePrint
        pin.width = loaded.width
        pin.height = loaded.height
        pin.aiTags = analysis.tags
        pin.colorTags = analysis.colorTags
        pin.ocrText = analysis.text
        pin.ocrTags = analysis.ocrTags
        pin.dhash = analysis.dhash
        pin.needsAnalysis = false
        pin.aiSkipped = !usesAI
        pin.hasFeaturePrint = analysis.featurePrint != nil
        pin.duplicateOfID = store.findDuplicate(of: pin)?.id
        status = .analyzing

        // The title before the AI touches it, so an AI title can be undone back to it.
        let before = pin.titleState
        if usesAI, settings.autoTitle, pin.titleIsAIOwned {
            let quick = TitleGenerator.tagBasedTitle(tags: analysis.tags, ocrText: analysis.text)
            if !quick.isEmpty {
                pin.setAITitle(quick, replacing: before)
            }
        }
        // A result from a hidden feed goes to the cloud model only with "Include hidden pins in Cloud AI".
        if usesAI, settings.cloudActive {
            let provider = settings.cloudProvider
            let model = settings.cloudModel
            let key = settings.cloudKey
            let cloud = try? await CloudAI.analyze(imageData: data, boardNames: [], userTags: [], provider: provider, model: model, apiKey: key)
            guard loadToken == token, !Task.isCancelled else { return }
            if let cloud {
                var merged = cloud.tags
                for tag in pin.aiTags where !merged.contains(where: { $0.label == tag.label }) {
                    merged.append(TagScore(label: tag.label, confidence: tag.confidence * 0.8))
                }
                pin.aiTags = Array(merged.prefix(24))
                // Checked after the wait: a title typed meanwhile is never replaced.
                if pin.titleIsAIOwned, let title = cloud.title {
                    pin.setAITitle(title, replacing: before)
                }
                pin.aiDescription = cloud.description ?? ""
                pin.aiSearchHint = cloud.searchQuery
            }
        } else if usesAI, settings.appleIntelligenceActive, pin.titleIsAIOwned {
            let smart = await AppleIntelligence.generateTitle(tags: analysis.tags.map { $0.label }, text: analysis.text)
            // Checked whatever came back: a stale draft must never mark the next one ready.
            guard loadToken == token, !Task.isCancelled else { return }
            if let smart, pin.titleIsAIOwned {   // a title typed meanwhile wins
                pin.setAITitle(smart, replacing: before)
            }
        }
        status = .ready
    }
}

// MARK: - The page

struct PinDetailView: View {
    enum Source {
        case stored(UUID)
        case draft(WebImage)
    }

    @EnvironmentObject var store: LibraryStore   // (not private: used by PinPageContent.swift)
    @EnvironmentObject var settings: AppSettings   // (not private: used by PinPageContent.swift)
    @EnvironmentObject var router: AppRouter   // (not private: used by PinPageContent.swift)
    @EnvironmentObject var importFlow: ImportFlow   // its short messages (a web result saved) (not private: used by PinPageContent.swift)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isInsideSettings) var isInsideSettings   // (not private: used by PinPageContent.swift)
    /// Compact on a phone in landscape: in one column the media area is kept lower there (`mediaHeightLimit`).
    @Environment(\.verticalSizeClass) var verticalSizeClass   // (not private: used by PinPageContent.swift)
    /// Regular on an iPad (a wide window): the page may use two columns (PinPageLayout.swift).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The text size. Read in `body`, so a new size measures a text pin's panel anew.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let source: Source
    let pinContext: PinContext
    let webContext: [WebImage]
    /// A web result's side of the library: Hidden when it came from a hidden feed (a hidden
    /// board's or a hidden pin's ideas from the web), else the normal library.
    let draftScope: PinScope
    /// The boards a web result's feed saves to (a board page's feed: that board; a pin page's
    /// feed: the pin's boards; Explore: none). Saving from this page lands there too (Save, an
    /// AI suggestion, Quick Look); "Save to board…" is a free choice. See `feedBoards`.
    let feedBoardIDs: [UUID]

    @StateObject var draft = DraftPinModel()   // (not private: used by PinPageContent.swift)
    /// The pin actions of the ⋯ menu and of every "More like this" card (PinActions.swift).
    @StateObject var pinActions = PinActions()   // (not private: used by PinPageContent.swift)
    /// The page's line to its video player (VideoControls.swift): whether it is paused on a frame, and where.
    @StateObject var playerHandle = VideoPlayerHandle()   // (not private: used by PinPageContent.swift)
    @State private var currentID: UUID
    @State var currentWeb: WebImage? = nil   // (not private: used by PinPageContent.swift)

    @State var image: UIImage? = nil          // a web result's downloaded picture (Save to Photos, Share) (not private: used by PinPageContent.swift)
    @State var newTag = ""   // (not private: used by PinPageContent.swift)
    @State var editingText = false          // text pins: the editor sheet (not private: used by PinPageContent.swift)
    @State var mediaOnScreen = true         // video pins: the media box is scrolled into view (not private: used by PinPageContent.swift)
    /// The page's height between its bars (under the navigation bar, above the tab bar or the
    /// home indicator), as if the keyboard were down; 0 until measured. See `pageBody`.
    @State var heightBetweenBars: CGFloat = 0   // (not private: used by PinPageContent.swift)
    @State var retitling = false   // (not private: used by PinPageContent.swift)
    @State var boardPicker: PinBoardPicker? = nil   // (not private: used by PinPageContent.swift)
    @State var editingTitle = false   // (not private: used by PinPageContent.swift)
    @State var editingNote = false   // (not private: used by PinPageContent.swift)
    /// The note as it was when "Edit note" was pressed. The sheet starts from it (and compares with it to
    /// know whether anything was typed), and Save hands it to the store, so that a video's transcript written
    /// into the note while the sheet is open is kept. (Reading `pin.note` live would change under the sheet
    /// when the transcript lands: the sheet would think it had been edited and refuse a swipe down.)
    @State var noteWhenOpened = ""   // (not private: used by PinPageContent.swift)
    @State var suggestions: [BoardSuggestion] = []   // (not private: used by PinPageContent.swift)
    @State var showSuggestionsAnyway = false   // (not private: used by PinPageContent.swift)
    @State var related: [Pin] = []   // (not private: used by PinPageContent.swift)
    @State var relatedLimit = 40   // (not private: used by PinPageContent.swift)
    @State var viewer: QuickLookRequest? = nil   // (not private: used by PinPageContent.swift)
    @State private var saving = false
    /// The side of the library this page was opened on (fixed once it appears): it
    /// shows only pins of that side, and a pin that changes sides leaves the page.
    @State private var openedScope: PinScope? = nil

    // Bottom feed
    @State var feedMode: PinFeedMode = .related   // (not private: used by PinPageContent.swift)
    @State var feedBarVisible = false       // the tabs float at the top once the feeds reach it (not private: used by PinPageContent.swift)
    @State var feedTabsHeight: CGFloat = 48   // (not private: used by PinPageContent.swift)
    @State var webWanted = false   // (not private: used by PinPageContent.swift)
    @State var webQuery = ""   // (not private: used by PinPageContent.swift)
    @State var webThinking = false   // (not private: used by PinPageContent.swift)
    @State var webUsedAI = false   // (not private: used by PinPageContent.swift)
    @State var webVariant = 0   // (not private: used by PinPageContent.swift)
    @State var editingWebQuery = false   // (not private: used by PinPageContent.swift)
    @State var webTask: Task<Void, Never>? = nil   // (not private: used by PinPageContent.swift)

    init(pinID: UUID, context: PinContext = .none) {
        source = .stored(pinID)
        pinContext = context
        webContext = []
        draftScope = .visible
        feedBoardIDs = []
        _currentID = State(initialValue: pinID)
    }

    init(webImage: WebImage, context: [WebImage], boardIDs: [UUID] = [], hidden: Bool) {
        source = .draft(webImage)
        pinContext = .none
        webContext = context.isEmpty ? [webImage] : context
        draftScope = hidden ? .hidden : .visible
        feedBoardIDs = boardIDs
        _currentID = State(initialValue: UUID())
        _currentWeb = State(initialValue: webImage)
    }

    // MARK: Which pin is on screen

    var isDraft: Bool {   // (not private: used by PinPageContent.swift)
        if case .draft = source { return draft.savedID == nil }
        return false
    }

    var pin: Pin? {   // (not private: used by PinPageContent.swift)
        switch source {
        case .stored:
            // A pin moved to Recently Deleted, or to the other side of the hidden line, is gone from here.
            return isShown(currentID) ? store.livePin(currentID) : nil
        case .draft:
            if let saved = draft.savedID {
                guard let stored = store.pin(saved), store.scope(of: stored) == draftScope else { return nil }
                return stored
            }
            if case .failed = draft.status { return nil }   // show the "Couldn't load" placeholder
            return draft.status == .idle ? nil : draft.pin
        }
    }

    /// The side of the library this page belongs to: the side of the pin it was opened
    /// with, or the web result's (see `draftScope`).
    var pageScope: PinScope {   // (not private: used by PinPageContent.swift)
        if let openedScope { return openedScope }
        if case .stored(let id) = source, let first = store.pin(id) { return store.scope(of: first) }
        return draftScope
    }

    /// A live pin on this page's side of the library.
    private func isShown(_ id: UUID) -> Bool {
        guard let live = store.livePin(id) else { return false }
        return store.scope(of: live) == pageScope
    }

    /// Changes whenever the page shows a different item.
    private var pageKey: String {
        switch source {
        case .stored: return "pin-\(currentID)"
        case .draft: return "web-\(currentWeb?.id ?? "")|\(draft.savedID?.uuidString ?? "")"
        }
    }

    /// The list this page was opened from (stored pins that still exist on this page's side).
    var storedItems: [UUID] {   // (not private: used by PinPageContent.swift)
        let ids = pinContext.ids.isEmpty ? [currentID] : pinContext.ids
        let live = ids.filter { isShown($0) }
        return live.isEmpty ? [currentID] : live
    }

    var itemCount: Int {   // (not private: used by PinPageContent.swift)
        switch source {
        case .stored: return storedItems.count
        case .draft: return webContext.count
        }
    }

    /// The pager's position: reading it finds the current item; setting it
    /// moves to another item and clears everything that belonged to the old one.
    var pagerIndex: Binding<Int> {   // (not private: used by PinPageContent.swift)
        Binding(
            get: {
                switch source {
                case .stored: return storedItems.firstIndex(of: currentID) ?? 0
                case .draft: return currentWeb.flatMap { webContext.firstIndex(of: $0) } ?? 0
                }
            },
            set: { i in
                switch source {
                case .stored:
                    let list = storedItems
                    guard list.indices.contains(i), list[i] != currentID else { return }
                    resetPageState()
                    currentID = list[i]
                case .draft:
                    guard webContext.indices.contains(i), webContext[i] != currentWeb else { return }
                    resetPageState()
                    draft.prepare(for: webContext[i])
                    currentWeb = webContext[i]
                }
            })
    }

    var body: some View {
        let alive = isStoredPinAlive
        // Read here so that a new text size runs this again: a text pin's panel is measured in
        // points (`textPanelHeight`), and those change with the text size.
        let _ = dynamicTypeSize
        gated(pageContent)
            .task(id: pageKey) {
                if case .draft = source, let web = currentWeb {
                    await draft.load(web, scope: draftScope, boardIDs: feedBoards, store: store, settings: settings)
                }
            }
            .modifier(SoundScreenPresence())   // a grid card that had sound goes quiet under this page
            .onAppear {
                if openedScope == nil { openedScope = pageScope }
            }
            .onChange(of: alive) { _, stillThere in
                // Deleted, hidden or unhidden (on this page, in Quick Look, or by a duplicate
                // merge): move on to a neighbour on this page's side, or leave.
                if !stillThere { moveOnFromGonePin() }
            }
            .onChange(of: store.contentVersion) {
                // Saved from Quick Look (or elsewhere) meanwhile: this page shows the real pin now.
                if case .draft = source, draft.savedID == nil, let web = currentWeb,
                   let existing = store.pinID(forSourceURL: web.pageURL.absoluteString, scope: draftScope) {
                    draft.savedID = existing
                }
            }
    }

    /// The page of the pin on screen, or what shows while there is none. The picture's Quick Look
    /// and the pin actions hang on this rather than on one pin's page, so they stay up while the
    /// page moves on to another pin (after a delete or a hide inside Quick Look, say).
    private var pageContent: some View {
        // A ZStack (a real container, unlike Group) so the covers below belong to it, not to
        // whichever branch is showing.
        ZStack {
            if let pin {
                page(for: pin)
            } else if case .draft = source, draft.savedID == nil {
                draftPlaceholder
            } else if store.livePin(currentPinID) == nil {
                EmptyStateView(icon: "pin.slash", title: "This pin was deleted", message: "")
            } else {
                Color.clear   // hidden or unhidden just now: the page moves on or goes back
            }
        }
        .fullScreenCover(item: $viewer) { request in
            QuickLookView(request: request)
        }
        // The page's own Quick Look (a tap on the picture) is up: the "More like this" previews stop
        // meanwhile, as they do under the pin actions' Quick Look (`.pinActions` sets the same value).
        .environment(\.quickLookIsUp, viewer != nil || pinActions.isShowingQuickLook)
        // The pin actions of ⋯ and of "More like this". After a delete or a hide the page
        // moves on by itself (`moveOnFromGonePin`).
        .pinActions(pinActions)
    }

    /// A hidden pin's page asks to unlock, like the Hidden section — with its Quick Look,
    /// sheets and questions inside the gate too, so locking closes them.
    @ViewBuilder
    private func gated<Content: View>(_ content: Content) -> some View {
        if pageScope == .hidden {
            content.hiddenGate()
        } else {
            content
        }
    }

    /// The pin on screen still belongs here: live, and on this page's side of the library
    /// (a web result's saved pin: live-or-deleted as before, but only on the result's side).
    private var isStoredPinAlive: Bool {
        switch source {
        case .stored:
            return isShown(currentID)
        case .draft:
            guard let saved = draft.savedID, let stored = store.pin(saved) else { return true }
            return store.scope(of: stored) == draftScope
        }
    }

    /// The pin on screen was moved to Recently Deleted or to the other side of the
    /// hidden line: show the next one of this page's side from the list this page came
    /// from (nearest after, else nearest before), or go back.
    private func moveOnFromGonePin() {
        let ids = pinContext.ids
        guard let position = ids.firstIndex(of: currentID) else {
            dismiss()
            return
        }
        let after = ids[(position + 1)...].first { isShown($0) }
        let before = ids[..<position].last { isShown($0) }
        if let next = after ?? before {
            resetPageState()
            currentID = next
        } else {
            dismiss()
        }
    }

    /// Forgets everything that belongs to the item that was on screen.
    private func resetPageState() {
        webTask?.cancel()
        webTask = nil
        image = nil
        related = []
        relatedLimit = 40
        suggestions = []
        showSuggestionsAnyway = false
        newTag = ""
        retitling = false
        webWanted = false
        webQuery = ""
        webUsedAI = false
        webVariant = 0
        webThinking = false
        feedMode = .related
        feedBarVisible = false
        saving = false
    }

    private var draftPlaceholder: some View {
        VStack(spacing: 12) {
            if case .failed(let text) = draft.status {
                EmptyStateView(icon: "wifi.exclamationmark", title: "Couldn't load", message: text)
                if let web = currentWeb {
                    Button("Try again") {
                        Task { @MainActor in
                            await draft.retry(web, scope: draftScope, boardIDs: feedBoards, store: store, settings: settings)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView()
                Text("Fetching this image…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("From the web")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Layout

    private func page(for pin: Pin) -> some View {
        // A hidden pin's page: its sheets are covered too while the app is not in front (the
        // page itself is, with the Hidden section it sits in; see `hiddenPrivacyCover`).
        let hiddenPage = pageScope == .hidden
        return pageBody(pin)
        .sheet(isPresented: $editingText) {
            TextPinEditorSheet(heading: "Edit text", title: pin.title, body: pin.textBody) { newTitle, newBody in
                if isDraft { return }
                if newTitle != pin.title { store.setTitle(newTitle, for: pin.id) }
                store.setTextBody(newBody, for: pin.id)
            }
            .hiddenPrivacyCover(hiddenPage)
        }
        .navigationTitle(pageTitle(pin))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent(pin) }
        .sheet(item: $boardPicker) { _ in
            // A web result: save it on a board of its side, or with none (a free choice: the
            // feed's boards are not added).
            BoardPickerSheet(title: "Save to…", scope: draftScope) { boardID in
                saveDraft(to: boardID.map { [$0] } ?? [])
            }
            .hiddenPrivacyCover(hiddenPage)
        }
        .sheet(isPresented: $editingTitle) {
            TextEditSheet(title: "Title", placeholder: "Title", initial: pin.title) { text in
                setTitle(text)
            }
            .hiddenPrivacyCover(hiddenPage)
        }
        .sheet(isPresented: $editingNote) {
            TextEditSheet(title: "Note", placeholder: "Anything you want to remember about this pin.", initial: noteWhenOpened, multiline: true) { text in
                setNote(text)
            }
            .hiddenPrivacyCover(hiddenPage)
        }
        .sheet(isPresented: $editingWebQuery) {
            TextEditSheet(title: "Search the web for", placeholder: "Search words", initial: webQuery) { text in
                if !text.isEmpty {
                    webQuery = text
                    webUsedAI = false
                }
            }
            .hiddenPrivacyCover(hiddenPage)
        }
        .task(id: "\(pageKey)|\(draft.status == .ready)|\(draft.image == nil)|\(pin.pictureRevision)") {
            if isDraft { image = draft.image }   // a web result hands its picture over
        }
        .task(id: refreshKey(for: pin)) {
            let printOverride = isDraft ? draft.featurePrintData.flatMap { store.featurePrintObservation(from: $0) } : nil
            let limit = relatedLimit
            let insights = await store.insights(for: pin, relatedLimit: limit, suggestionLimit: 3, printOverride: printOverride)
            if Task.isCancelled { return }
            suggestions = insights.suggestions
            related = insights.related
        }
    }

    /// The page's title: the pin's own, else what it is — one "Photo", "Video", "Text" or
    /// "Link" (the words the cards use; the filters' "Photos" is for many).
    private func pageTitle(_ pin: Pin) -> String {
        if !pin.title.isEmpty { return pin.title }
        if isDraft { return "From the web" }
        return PinCardView.kindName(pin.kind)
    }

    /// Changes whenever something that affects the suggestions changes (a new picture file too:
    /// turned, flipped or cropped, it may look like other pins now).
    private func refreshKey(for pin: Pin) -> String {
        "\(pageKey)|\(pin.tags.joined(separator: ","))|\(pin.aiTags.count)|\(pin.boardIDs.map { $0.uuidString }.joined())|\(pin.needsAnalysis)|\(pin.pictureRevision)|\(store.boards.count)|\(store.pins.count)|\(draft.status == .ready)|\(relatedLimit)"
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ pin: Pin) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isDraft {
                Button {
                    saveDraft(to: pin.boardIDs)   // the feed's boards (see DraftPinModel.load), or none
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(saving || draft.status != .ready)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if isDraft {
                    draftMenuItems(pin)
                } else {
                    // The pin actions (PinActions.swift) but Delete, then this page's own items.
                    PinActionMenuItems(pins: [pin.id], side: pageScope, place: .pinPage, actions: pinActions,
                                       except: [.delete])
                    Divider()
                    pageMenuItems(pin)
                }
                if !isInsideSettings {   // (a pin page reached from Settings › Possible duplicates is inside it already)
                    Divider()
                    Button {
                        router.showSettings = true
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                }
                if !isDraft {
                    // The one destructive item comes last, on its own.
                    Divider()
                    deleteMenuButton(pin)
                }
            } label: {
                MoreMenuLabel()
            }
            .accessibilityLabel("More")
        }
    }

    /// ⋯ › Delete, in red at the very end of the menu. It asks first (PinActions.swift); after
    /// a delete the page moves on to the next pin (`moveOnFromGonePin`).
    private func deleteMenuButton(_ pin: Pin) -> some View {
        let label = PinAction.delete.label(count: 1)
        return Button(role: .destructive) {
            pinActions.perform(.delete, on: [pin.id], side: pageScope, place: .pinPage)
        } label: {
            Label(label.text, systemImage: label.icon)
        }
    }

    /// A stored pin's own ⋯ items: reading its link again (or its link preview) and the web page
    /// it came from.
    @ViewBuilder
    private func pageMenuItems(_ pin: Pin) -> some View {
        // The page the picture came from sits first, close to the pin actions' "Open link" above.
        sourcePageLink(pin)
        if isFrameOffered(pin) {
            // A video paused on a frame: that frame can be its thumbnail.
            Button {
                useFrameAsThumbnail(pin)
            } label: {
                Label("Use this frame as thumbnail", systemImage: "photo.badge.checkmark")
            }
        }
        if pin.isLink, settings.readsLinksFully {
            Button {
                Task { @MainActor in await store.readLink(for: pin.id) }
            } label: {
                Label("Read link again", systemImage: "arrow.clockwise")
            }
        } else if pin.isLink, settings.webAllowed, settings.fetchLinkPreviews {
            Button {
                Task { @MainActor in await store.fetchLinkPreview(for: pin.id) }
            } label: {
                Label(pin.hasPreview ? "Refresh link preview" : "Fetch link preview", systemImage: "arrow.clockwise")
            }
        }
    }

    /// A web result's ⋯ items: save it (on a board), save or share its downloaded picture.
    @ViewBuilder
    private func draftMenuItems(_ pin: Pin) -> some View {
        Button {
            boardPicker = .save
        } label: {
            Label("Save to board…", systemImage: "folder.badge.plus")
        }
        .disabled(draft.status != .ready)
        Divider()
        Button {
            saveDraftImageToPhotos()
        } label: {
            Label("Save to Photos", systemImage: "square.and.arrow.down")
        }
        .disabled(image == nil)
        if let image {
            ShareLink(item: Image(uiImage: image), preview: SharePreview(pin.title.isEmpty ? "Image" : pin.title, image: Image(uiImage: image))) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        sourcePageLink(pin)
    }

    /// "Open source page", for a pin that came from a web page.
    @ViewBuilder
    private func sourcePageLink(_ pin: Pin) -> some View {
        if let sourceString = pin.sourceURL, let url = URL(string: sourceString) {
            Link(destination: url) {
                Label("Open source page", systemImage: "safari")
            }
        }
    }

    // MARK: Actions (work for stored pins and drafts alike)

    private func setTitle(_ text: String) {
        if isDraft {
            draft.pin.setUserTitle(text)   // typed here: the AI never replaces it
        } else {
            store.setTitle(text, for: currentPinID)
        }
    }

    /// Puts back the title the AI replaced last.
    func undoAITitle() {   // (not private: used by PinPageContent.swift)
        if isDraft {
            draft.pin.undoAITitle()
        } else {
            store.undoAITitle(for: currentPinID)
        }
    }

    /// Save in the note sheet. A stored pin goes through the store with the note the sheet opened with, so a
    /// transcript that landed meanwhile is not written over; a web result's draft just takes the text.
    private func setNote(_ text: String) {
        if isDraft {
            draft.pin.note = text
        } else {
            store.setNote(text, for: currentPinID, openedWith: noteWhenOpened)
        }
    }

    func addTags(_ tags: [String]) {   // (not private: used by PinPageContent.swift)
        if isDraft {
            for tag in tags.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) where !tag.isEmpty && !draft.pin.tags.contains(tag) {
                draft.pin.tags.append(tag)
            }
        } else {
            store.addTags(tags, to: [currentPinID])
        }
    }

    func removeTag(_ tag: String) {   // (not private: used by PinPageContent.swift)
        if isDraft { draft.pin.tags.removeAll { $0 == tag } } else { store.removeTag(tag, from: [currentPinID]) }
    }

    var currentPinID: UUID {   // (not private: used by PinPageContent.swift)
        if let saved = draft.savedID { return saved }
        return currentID
    }

    /// An AI suggestion was tapped: a stored pin is added to that board; a draft is saved there,
    /// and on the boards it already shows (its feed's), as a stored pin would keep its boards.
    func chooseSuggested(_ boardID: UUID, for pin: Pin) {   // (not private: used by PinPageContent.swift)
        settings.lastBoardID = boardID
        if isDraft {
            var boards = pin.boardIDs
            if !boards.contains(boardID) { boards.append(boardID) }
            saveDraft(to: boards)
        } else {
            store.addPins([pin.id], to: boardID)
        }
    }

    /// The boards among `ids` that still exist on this result's side of the library. A board
    /// deleted, hidden or unhidden since the feed was shown is left out, so saving from here
    /// never puts a pin across the hidden line.
    private func onDraftSide(_ ids: [UUID]) -> [UUID] {
        let hidden = draftScope == .hidden
        return ids.filter { id in store.board(id) != nil && store.isSecretBoard(id) == hidden }
    }

    /// The boards this result's feed saves to (see `feedBoardIDs`), as far as they still exist here.
    var feedBoards: [UUID] { onDraftSide(feedBoardIDs) }   // (not private: used by PinPageContent.swift)

    private func saveDraft(to chosenBoards: [UUID]) {
        guard isDraft, !saving, let web = currentWeb, let data = draft.imageData else { return }
        let boardIDs = onDraftSide(chosenBoards)
        // Saved meanwhile (Quick Look, another page)? Just put that pin on the boards.
        // (Only a pin on this page's side: saving here never moves one across the hidden line.)
        if let existing = store.pinID(forSourceURL: web.pageURL.absoluteString, scope: draftScope) {
            for boardID in boardIDs { store.addPins([existing], to: boardID) }
            draft.savedID = existing
            return
        }
        saving = true
        var toSave = draft.pin
        toSave.boardIDs = boardIDs
        // From a hidden feed: into Hidden. With a hidden board the board does the hiding, so a
        // later "Unhide board" brings the pin out with it (as for the feed's own + button).
        toSave.isHidden = draftScope == .hidden && boardIDs.isEmpty
        let webID = web.id
        Task { @MainActor in
            let newID = await store.importDraft(toSave, imageData: data, featurePrint: draft.featurePrintData)
            // The page may have moved on to another result while this ran.
            guard currentWeb?.id == webID else { return }
            saving = false
            // Told with a short message, like every other result that needs no answer. It names the
            // board, except on the hidden side: the message may outlast your visit to Hidden.
            if let newID {
                draft.savedID = newID
                WebImageService.reportDownload(of: web)   // Unsplash asks to be told of each download
                let names = store.boardNames(for: store.pin(newID) ?? toSave)
                importFlow.flash(PinActionText.savedWebResult(boardNames: names, hidden: draftScope == .hidden))
            } else {
                importFlow.flash("Sorry — the image couldn't be saved.", symbol: "exclamationmark.triangle")
            }
        }
    }

    /// Saves a web result's downloaded picture to Photos (a stored pin's is saved by PinActions),
    /// and says so with a short message.
    private func saveDraftImageToPhotos() {
        guard let image else { return }
        Task { @MainActor in
            if await PhotosSaver.save(image) {
                importFlow.flash("Saved to Photos.")
            } else {
                importFlow.flash(PhotosSaver.problem("Photos didn't take the picture."), symbol: "exclamationmark.triangle")
            }
        }
    }

    var hasNeighbors: Bool { itemCount > 1 }   // (not private: used by PinPageContent.swift)

    // MARK: Sections

    private func draftBanner(_ pin: Pin) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
            VStack(alignment: .leading, spacing: 2) {
                Text("From the web — not saved yet")
                    .font(.subheadline.weight(.semibold))
                Text(draft.status == .ready
                     ? "Edit the title or tags if you like, then tap Save."
                     : (draft.status == .analyzing ? "Looking at the image…" : "Downloading…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The scrolling page: the details column, then the feeds, with the feed
    /// tabs floating at the top once they have been scrolled up to it.
    private func pageBody(_ pin: Pin) -> some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(columns: settings.columnCount(forWidth: geometry.size.width),
                                      width: geometry.size.width - PinTheme.gridSpacing * 2,
                                      visibleHeight: GridMetrics.visibleHeight(in: geometry))
            let scrollTop = geometry.frame(in: .global).minY
            let sizing = pageSizing(width: geometry.size.width)
            // The page's height as it is with the keyboard down. The keyboard makes the page
            // shorter but its bottom safe area as much taller, so the sum stays the same (the
            // same sum GridMetrics.visibleHeight uses).
            let stableHeight = geometry.size.height + geometry.safeAreaInsets.bottom
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        detailsColumn(pin, sizing: sizing, scrollTop: scrollTop,
                                      viewportHeight: geometry.size.height, stableHeight: stableHeight)
                        feedSection(pin, metrics: metrics, proxy: proxy, scrollTop: scrollTop, viewportHeight: geometry.size.height)
                            .padding(.horizontal, PinTheme.gridSpacing)
                            .padding(.bottom, 24)
                    }
                }
                .overlay(alignment: .top) {
                    if feedBarVisible {
                        feedTabs(pin, proxy: proxy)
                            .background(.bar)
                            .overlay(alignment: .bottom) { Divider() }
                            .transition(.opacity)
                    }
                }
            }
        }
        .background {
            // The same page measured between its bars, the keyboard ignored: it keeps its height
            // while you type, and leaves out the tab bar and home indicator the page's own height
            // (with its bottom safe area) takes in. A phone in landscape caps the media by it.
            GeometryReader { room in
                Color.clear
                    .onAppear { noteHeightBetweenBars(room.size.height) }
                    .onChange(of: room.size.height) { _, height in noteHeightBetweenBars(height) }
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    /// Keeps the height between the bars. Not animated: it only changes when the page is first
    /// measured or the phone is turned, and the media area shouldn't glide after that.
    private func noteHeightBetweenBars(_ height: CGFloat) {
        guard height != heightBetweenBars else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { heightBetweenBars = height }
    }

    /// How the page is arranged at this width: one column or two, and how wide each is
    /// (PinPageLayout.swift). Worked out from the page's own width and the size class, below
    /// the page's state, so a resize keeps the pager's page and a playing video.
    private func pageSizing(width: CGFloat) -> PinPageLayout.Sizing {
        let columns = PinPageLayout.columns(sizeClass: horizontalSizeClass, width: width,
                                            largeText: dynamicTypeSize.isAccessibilitySize)
        return PinPageLayout.sizing(columns: columns, available: width)
    }

    /// Everything about the pin, in a comfortable reading column — or, on a wide page, the media on
    /// the left and the rest on the right (`PinPageColumns`). A web result's banner runs over both.
    /// `viewportHeight`: the page's scroll view as it is now; `stableHeight`: the same with the
    /// keyboard down.
    private func detailsColumn(_ pin: Pin, sizing: PinPageLayout.Sizing, scrollTop: CGFloat, viewportHeight: CGFloat,
                               stableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: PinPageLayout.stackGap) {
            if isDraft { draftBanner(pin) }
            PinPageColumns(sizing: sizing) {
                mediaSection(pin, columns: sizing.columns, width: sizing.mediaWidth, scrollTop: scrollTop,
                             viewportHeight: viewportHeight, stableHeight: stableHeight)
            } details: {
                infoColumn(pin)
            }
        }
        .padding()
        .frame(maxWidth: sizing.pageWidth)
        .frame(maxWidth: .infinity)
    }

    /// Everything about the pin but its picture or video: title and note, the link's panels,
    /// boards, tags, the text in the image, details, source, and Delete.
    private func infoColumn(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: PinPageLayout.stackGap) {
            Group {
                titleSection(pin)
                if pin.isLink {
                    linkSection(pin)
                    if !isDraft {
                        PlatformVideoNote(pin: pin)   // once: how to get a TikTok or Instagram video into PinBoard
                    }
                }
                if !isDraft, LinkDetailsPanel.hasContent(for: pin) {
                    // What reading its link found (SmartLinksViews.swift): an article's byline,
                    // a video's details and comments, where a picture from a link came from.
                    LinkDetailsPanel(pin: pin)
                }
                if !isDraft, pin.originalName != nil {
                    // The full-size original kept in the originals folder (Settings › iCloud & storage): MediaStorage.swift.
                    MediaOriginalRow(pin: pin)
                }
                boardSection(pin)
            }
            Group {
                yourTagsSection(pin)
                aiTagsSection(pin)
                textSection(pin)
                infoSection(pin)
                sourceSection(pin)
            }
            if !isDraft {
                Button(role: .destructive) {
                    pinActions.perform(.delete, on: [pin.id], side: pageScope, place: .pinPage)   // asks first
                } label: {
                    Label("Delete pin", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // The media box and its pager, the info sections and the bottom feeds: PinPageContent.swift.
}
