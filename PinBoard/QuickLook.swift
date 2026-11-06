//
//  QuickLook.swift  —  PinBoard
//
//  Quick Look: a full-screen vertical feed of pins (or web results) — swipe
//  up and down, left to right to close, in from the right edge for the info
//  panel. The info panel, the pages (zoomable pictures, videos, text, links
//  with an "Open link" button) and the zoom view are in QuickLookPage.swift.
//  Quick Look is always dark, and so are the sheets it opens. A picture turned,
//  flipped or cropped here shows its new look at once (its pages load again on
//  `Pin.pictureRevision`).
//  A pin whose full-size original was kept (Settings › iCloud & storage) has "Show
//  original" in ⋯, and a line about it in the info panel (MediaStorage.swift).
//  Videos: holding a finger on one for a second plays it at 2× (drag down while holding to
//  lock it), ⋯ › Speed picks a speed, ⋯ › Show info opens the pin's own page, and while a
//  video is paused ⋯ can make its frame the thumbnail (VideoControls.swift). A video has no
//  long-press menu here — the hold is for speed — so ⋯ is its only menu. Two quick taps skip
//  (upper left back, upper right forward; in the bottom third the other way round). A video swiped to carries on from where it was left,
//  with its controls hidden until it is tapped.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Foundation


// MARK: - Quick Look (a vertical feed of pins or web results)

/// What Quick Look shows.
/// • `.library(seed:pages:pinPageUnder:)` — the pin, then pins like it of the same kind (More
///   like this), loading more as the end comes near; or, when `pages` is given, exactly the
///   pins of that list (the grid's own order) with the pin in its place and nothing more.
/// • `.web(images:startIndex:loadMore:boardIDs:hidden:)` — web results, starting at
///   one of them; near the end `loadMore` is asked for more (it may return images
///   already shown — they are skipped); nothing new means the end of the feed.
///   Saving puts a result where the feed saves: on `boardIDs` (none = Unsorted),
///   or straight into Hidden with `hidden: true` and no boards.
struct QuickLookRequest: Identifiable {
    enum Source {
        case library(seed: Pin)
        case web(images: [WebImage], startIndex: Int, loadMore: (@MainActor () async -> [WebImage])?,
                 boardIDs: [UUID], hidden: Bool)
    }

    let id = UUID()
    let source: Source
    /// A library feed only: the pins to page through, in this order — the order of the grid it was
    /// opened from. Quick Look then shows exactly these (the live ones on the seed's side of the
    /// library, the seed where it stands in the list) and never looks for "more like this". nil
    /// means the old way: the seed, then pins like it.
    let pages: [UUID]?
    /// The pin whose page is open right under this Quick Look (it was opened from that page), if
    /// any. ⋯ › Show info on that very pin then just closes Quick Look: its page is already there.
    let pinPageUnder: UUID?

    init(_ source: Source, pages: [UUID]? = nil, pinPageUnder: UUID? = nil) {
        self.source = source
        self.pages = pages
        self.pinPageUnder = pinPageUnder
    }

    /// `pages` and `pinPageUnder` are both optional, so every older call keeps compiling.
    static func library(seed: Pin, pages: [UUID]? = nil, pinPageUnder: UUID? = nil) -> QuickLookRequest {
        QuickLookRequest(.library(seed: seed), pages: pages, pinPageUnder: pinPageUnder)
    }

    static func web(images: [WebImage], startIndex: Int, loadMore: (@MainActor () async -> [WebImage])? = nil,
                    boardIDs: [UUID] = [], hidden: Bool = false) -> QuickLookRequest {
        QuickLookRequest(.web(images: images, startIndex: startIndex, loadMore: loadMore, boardIDs: boardIDs, hidden: hidden))
    }
}

/// What ⋯ › Show info does. A video's info is its own page (the owner's wish: a tap on a video
/// goes straight to full screen, and "Show info" is the way to the page); everything else keeps
/// the side panel. Pure, so it can be tested.
enum QuickLookInfoPlan: Equatable {
    /// The side panel (pictures, text, links, web results).
    case panel
    /// A video: close Quick Look and open its page, with the pins Quick Look has so far as the
    /// list to swipe through.
    case pinPage(Route)
    /// A video whose page is already open under Quick Look: closing Quick Look is enough.
    case alreadyThere

    /// `feed`: the items Quick Look has loaded so far. `pinPageUnder`: the pin whose page is open
    /// under Quick Look (`QuickLookRequest.pinPageUnder`). `insideSettings`: Quick Look was opened
    /// from a page inside Settings — a page pushed in the tab would end up behind the Settings
    /// sheet, where nobody sees it, so the panel is shown instead.
    static func make(for item: ViewerItem, feed: [ViewerItem], pinPageUnder: UUID?,
                     insideSettings: Bool = false) -> QuickLookInfoPlan {
        guard case .pin(let pin) = item, pin.isVideo else { return .panel }
        if pin.id == pinPageUnder { return .alreadyThere }
        if insideSettings { return .panel }
        let ids: [UUID] = feed.compactMap { (entry: ViewerItem) -> UUID? in
            if case .pin(let other) = entry { return other.id }
            return nil
        }
        return .pinPage(.pin(pin.id, PinContext(ids: ids, around: pin.id)))
    }

    /// How long after Quick Look starts closing its page is opened. The cover has to be gone first:
    /// UIKit drops a push that arrives while the cover is still sliding away.
    static let pageOpenDelayMilliseconds = 450
}

/// The list a library Quick Look pages through when the screen it was opened from handed one over
/// (`QuickLookRequest.pages`). Plain rules, so they can be tested.
@MainActor
enum QuickLookPages {
    /// How many pins are kept on each side of the one that was tapped. Quick Look holds whole pins
    /// in memory and looks through them at every change, so a library of tens of thousands is cut
    /// to a window around the tapped pin (nobody swipes through a thousand pictures in one go).
    /// (`nonisolated`: a plain number read by `ids`' default argument, which the compiler on the
    /// device evaluates outside the main actor.)
    nonisolated static let reach = 1_000

    /// The ids to page through: `pages` in its order without repeats, at most `reach` on each side
    /// of `seed`. The seed is always in it — first, when the list no longer holds it.
    static func ids(seed: UUID, pages: [UUID], reach: Int = QuickLookPages.reach) -> [UUID] {
        var seen: Set<UUID> = []
        var ordered: [UUID] = []
        ordered.reserveCapacity(pages.count)
        for id in pages where seen.insert(id).inserted {
            ordered.append(id)
        }
        guard let at = ordered.firstIndex(of: seed) else {
            return [seed] + Array(ordered.prefix(reach))
        }
        let start = max(0, at - reach)
        let end = min(ordered.count, at + reach + 1)
        return Array(ordered[start..<end])
    }

    /// The feed's items: the pins of `ids(...)` that are still live and on `scope`'s side of the
    /// library, in the list's order. The seed stays even when `livePin` no longer has it (Quick
    /// Look's first refresh deals with that, like it does for a feed without a list).
    static func items(seed: Pin, pages: [UUID], scope: PinScope,
                      livePin: (UUID) -> Pin?, scopeOf: (Pin) -> PinScope) -> [ViewerItem] {
        var result: [ViewerItem] = []
        for id in ids(seed: seed.id, pages: pages) {
            if id == seed.id {
                result.append(.pin(livePin(id) ?? seed))
            } else if let pin = livePin(id), scopeOf(pin) == scope {
                result.append(.pin(pin))
            }
        }
        return result
    }
}

/// Whether Quick Look's keys (↑ ↓ Esc, and Space ← → for a video) may act. They must not while
/// something is on top of Quick Look — a sheet with a text field, the web search — or a key that
/// types (Space) would pause the video behind it instead of reaching the field. Plain rule.
enum QuickLookKeys {
    /// `sheetUp`: one of Quick Look's own sheets (Edit title, Edit note, Save to…, Share, the
    /// original). `searchUp`: the web search sheet. `actionsUp`: a sheet of the pin actions (tags,
    /// boards, link) — PinActions' `isPresenting`.
    static func areLive(sheetUp: Bool, searchUp: Bool, actionsUp: Bool) -> Bool {
        !sheetUp && !searchUp && !actionsUp
    }
}

/// A pin page, Quick Look or Settings came up: the grid card that had sound is covered now,
/// so it goes quiet. (The sound switch itself stays as the person set it.)
@MainActor
struct SoundScreenPresence: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { SoundState.shared.gridSoundPinID = nil }
    }
}

struct QuickLookView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var router: AppRouter   // ⋯ › Show info opens a video's page through it
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Quick Look opened from a page inside Settings: a video's page can't be pushed in a tab then
    /// (it would sit behind the Settings sheet), so ⋯ › Show info shows the panel (`QuickLookInfoPlan`).
    @Environment(\.isInsideSettings) private var isInsideSettings

    /// More-like-this pins are asked for in steps of this many.
    static let libraryStep = 40
    /// More is loaded when the page in front is this close to the end.
    static let loadAhead = 6

    /// The sheets Quick Look opens over itself (a stored pin's actions open theirs through
    /// `actions`, see PinActions.swift).
    private enum Sheet: Identifiable {
        case saveWeb(WebImage), shareWeb(WebImage)
        case editTitle(Pin), editNote(Pin)
        case original(Pin, URL)   // the full-size original, fetched (⋯ › Show original)
        var id: String {
            switch self {
            case .saveWeb(let image): return "web-\(image.id)"
            case .shareWeb(let image): return "share-\(image.id)"
            case .editTitle(let pin): return "title-\(pin.id)"
            case .editNote(let pin): return "note-\(pin.id)"
            case .original(let pin, _): return "original-\(pin.id)"
            }
        }
    }

    /// What a drag on Quick Look turned out to be. Decided once per drag, when it has
    /// moved far enough to tell, and kept until the finger lifts.
    private enum DragKind {
        case ignored      // up or down (the feed pages), on a video's scrub bar, or on a zoomed picture
        case closeFeed    // left to right: closes Quick Look
        case openPanel    // from the right edge to the left: pulls the info panel in
        case closePanel   // left to right while the info panel is open: pushes it away
    }

    let request: QuickLookRequest
    @State private var items: [ViewerItem]          // the feed so far, refreshed when the library changes
    @State private var currentKey: String
    @State private var feedScope: PinScope? = nil   // library feeds stay within the seed's side of the library
    @State private var askedFor = 0                 // how many related pins were last asked for
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var zoomed = false
    @State private var swipe: CGFloat = 0           // how far the feed has been pulled to the right
    @State private var infoOpen = false             // the info panel is showing
    @State private var panelShift: CGFloat = 0      // how far the info panel is being dragged in (or out)
    @State private var dragKind: DragKind? = nil    // what the drag in progress is
    @State private var dragTouchedScrubber = false  // the drag in progress started on a video's scrub bar, or is a hold on a video
    @State private var sheet: Sheet? = nil
    @State private var webSearchPage: WebSearchPage? = nil   // ⋯ › Search this picture on the web, in PinBoard's own browser
    /// A feed that comes with its list (`request.pages`) is put together when Quick Look appears
    /// (it needs the store); until then nothing is drawn, so the pager starts at the right pin
    /// instead of starting at the seed alone and moving. A feed without a list is ready at once.
    @State private var feedReady: Bool
    @StateObject private var actions = PinActions()  // what the menus ask for a stored pin
    /// The videos' speed (⋯ › Speed, the hold), the one in front and whether it is paused. It lives
    /// as long as Quick Look, so every speed is back to 1× when Quick Look closes.
    @StateObject private var video = VideoPlayerHandle(speedControls: true)
    /// Originals being fetched (⋯ shows a spinner meanwhile; see MediaStorage.swift).
    @ObservedObject private var originals = OriginalsFolder.shared
    /// ⋯ › Show original's fetch, kept so it stops when the pin changes or Quick Look closes (a
    /// fetch from iCloud can take minutes; it never opens the sheet over another pin afterwards).
    @State private var originalTask: Task<Void, Never>? = nil

    init(request: QuickLookRequest) {
        self.request = request
        let start: [ViewerItem]
        let startIndex: Int
        switch request.source {
        case .library(let seed):
            start = [.pin(seed)]
            startIndex = 0
        case .web(let images, let index, _, _, _):
            start = images.map { .web($0) }
            startIndex = min(max(index, 0), max(start.count - 1, 0))
        }
        _items = State(initialValue: start)
        _currentKey = State(initialValue: start.isEmpty ? "" : start[startIndex].id)
        _feedReady = State(initialValue: request.pages == nil)
    }

    private var index: Binding<Int> {
        Binding(
            get: { items.firstIndex { $0.id == currentKey } ?? 0 },
            set: { i in
                if items.indices.contains(i) { currentKey = items[i].id }
            })
    }

    private var current: ViewerItem? {
        items.first { $0.id == currentKey }
    }

    /// Whether Quick Look's own swipes (close, info panel) may run now: not while a
    /// picture is zoomed in (the drag pans it). Over videos they work too — a drag that
    /// starts on the player's scrub bar is left alone (see `dragChanged`).
    private var closeSwipeAllowed: Bool { !zoomed }

    /// The info panel's width: a narrow column on an iPad, most of the screen on a phone.
    static func panelWidth(for width: CGFloat) -> CGFloat {
        width < 600 ? width * 0.85 : min(380, max(300, width * 0.36))
    }

    /// Text pages move beside the open info panel only if at least this much width is left.
    static let minReadingWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geometry in
            layers(size: geometry.size, safeArea: geometry.safeAreaInsets)
        }
        .preferredColorScheme(.dark)
        .defersSystemGestures(on: .trailing)          // a swipe in from the right edge opens the info panel
        .importFlowCover(toastAboveControls: true)   // import questions, alerts and confirmations show above this cover
        // Hidden pins never show in the App Switcher. Applied after the import cover, so it lies
        // over its confirmations too.
        .hiddenPrivacyCover(showsHiddenSide)
        .modifier(SoundScreenPresence())
        .onAppear {
            if case .library(let seed) = request.source, feedScope == nil {
                feedScope = store.scope(of: store.livePin(seed.id) ?? seed)
            }
            putTogetherPages()
            refreshItems()
            loadMoreIfNeeded()
        }
        .onChange(of: store.contentVersion) {
            refreshItems()
        }
        .onChange(of: currentKey) {
            zoomed = false
            stopFetchingOriginal()   // an original asked for on the pin before isn't wanted any more
            loadMoreIfNeeded()
        }
        .onDisappear {
            stopFetchingOriginal()
            video.reset()            // back to 1×: a speed lasts only as long as Quick Look is open
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .hiddenPrivacyCover(showsHiddenSide)
                // Dark like Quick Look, its UIKit parts too (the text field of Title and Note).
                .preferredColorScheme(.dark)
        }
        // A pin deleted, hidden or unhidden here leaves the feed through `refreshItems`.
        .pinActions(actions)
        // ⋯ › Search this picture on the web (a web result), shown in PinBoard's own browser.
        .webSearchSheet($webSearchPage, hidden: showsHiddenSide)
    }

    /// Everything on screen. `size` and `safeArea` are the cover's: the video controls
    /// stay inside the safe area (and beside the info panel while it is open).
    private func layers(size: CGSize, safeArea: EdgeInsets) -> some View {
        let panelWidth = QuickLookView.panelWidth(for: size.width + safeArea.leading + safeArea.trailing)
        let insets = EdgeInsets(top: safeArea.top, leading: safeArea.leading, bottom: safeArea.bottom,
                                trailing: safeArea.trailing + (infoOpen ? panelWidth : 0))
        // Words stay inside the safe area too. They move beside the open panel only when that
        // leaves a column wide enough to read; on a phone in portrait the panel covers them.
        let roomBeside = size.width - panelWidth >= QuickLookView.minReadingWidth
        let wordsInsets = EdgeInsets(top: safeArea.top, leading: safeArea.leading, bottom: safeArea.bottom,
                                     trailing: safeArea.trailing + (infoOpen && roomBeside ? panelWidth : 0))
        let dimming: Double = max(0.25, 1.0 - Double(swipe) / 500.0)
        return ZStack(alignment: .topLeading) {
            Color.black
                .opacity(dimming)
                .ignoresSafeArea()
            feed(controlsInsets: insets, textInsets: wordsInsets)
            infoPanelLayer(width: panelWidth)
            closeButton
            moreButton
            // Up / down arrows and Escape on an iPad keyboard.
            keyboardShortcuts(count: items.count)
        }
        // One drag handler for the close swipe and the info panel (see `DragKind`). Switched
        // off while a picture is zoomed in, so it never competes with the picture's panning.
        .simultaneousGesture(dragGesture(width: size.width, panelWidth: panelWidth),
                             including: closeSwipeAllowed ? .all : .subviews)
    }

    /// Up and down through the feed; the first item just bounces when pulled down.
    @ViewBuilder
    private func feed(controlsInsets: EdgeInsets, textInsets: EdgeInsets) -> some View {
        let list = items
        let position = index.wrappedValue
        if !feedReady {
            Color.clear   // the list is being put together (see `feedReady`): one frame at most
        } else if list.isEmpty {
            EmptyStateView(icon: "photo", title: "Nothing to show", message: "")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // While a finger holds on a video (2× until it lifts) the feed must not page.
            MediaPager(count: list.count, index: index, orientation: .vertical,
                       isPagingLocked: video.hold.isHolding, pageID: { i in list[i].id }) { i in
                pageWithMenu(for: list[i],
                             QuickLookPage(item: list[i],
                                           distance: abs(i - position),
                                           isCurrent: i == position,
                                           number: i + 1,
                                           count: list.count,
                                           controlsInsets: controlsInsets,
                                           textAreaInsets: textInsets,
                                           videoHandle: video,
                                           onZoomChange: { zoomed = $0 },
                                           onTap: { closeInfo() }))
            }
            .ignoresSafeArea()
            .offset(x: swipe)
            // A tap on the picture or video closes the info panel. Alongside the page's own
            // taps (the video shows or hides its controls), never instead of them.
            .simultaneousGesture(TapGesture().onEnded { closeInfo() })
        }
    }

    /// A page with its long-press menu — except a video's: there the long press is the hold that
    /// plays at 2×, and ⋯ is the only menu.
    @ViewBuilder
    private func pageWithMenu(for item: ViewerItem, _ page: QuickLookPage) -> some View {
        if isVideo(item) {
            page
        } else {
            page.contextMenu { menu(for: item) }
        }
    }

    /// The item is a stored video (a web result or any other pin is not).
    private func isVideo(_ item: ViewerItem) -> Bool {
        if case .pin(let pin) = item { return pin.isVideo }
        return false
    }

    /// The info panel on the trailing side (while it is open or being dragged). Opened or closed
    /// by a button or a tap it slides in and out — or, with Reduce Motion on, fades. A drag
    /// moves it with the finger either way.
    @ViewBuilder
    private func infoPanelLayer(width: CGFloat) -> some View {
        if let item = current, infoOpen || panelShift > 0 {
            QuickLookInfoPanel(item: item, webSaved: isSaved(item)) { action in
                handleInfo(action, for: item)
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .offset(x: infoOpen ? panelShift : width - panelShift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .transition(panelTransition)
        }
    }

    /// How the info panel comes and goes: sliding from the trailing edge, or a crossfade with
    /// Reduce Motion on.
    private var panelTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 8)
        .opacity(swipe == 0 ? 1 : 0)
        .accessibilityLabel("Close")
    }

    /// The same actions as touching and holding, always reachable. Hidden while the info
    /// panel is open (the panel has its own buttons and a close button).
    @ViewBuilder
    private var moreButton: some View {
        if let item = current, !infoOpen {
            Menu {
                menu(for: item)
            } label: {
                moreLabel(for: item)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            // Drawn as a plain button, like ✕: the menu's own style paints its label in the app's
            // accent colour (red on iPhone) over the white. The menu's items keep their usual colours.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(swipe == 0 ? 1 : 0)
            .accessibilityLabel("More")
            .accessibilityValue(isFetchingOriginal(of: item) ? "Fetching the original" : "")
        }
    }

    /// ⋯, or a spinner while the pin's original is being fetched (⋯ › Show original).
    @ViewBuilder
    private func moreLabel(for item: ViewerItem) -> some View {
        if isFetchingOriginal(of: item) {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: "ellipsis")
        }
    }

    /// The item is a pin whose original is being fetched now.
    private func isFetchingOriginal(of item: ViewerItem) -> Bool {
        guard case .pin(let pin) = item else { return false }
        return originals.fetching.contains(pin.id)
    }

    // Swipes: close (left to right), info panel (in from the right edge, out to the right)

    private func dragGesture(width: CGFloat, panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in dragChanged(value, width: width, panelWidth: panelWidth) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value, width: CGFloat, panelWidth: CGFloat) {
        // A finger on a video's scrub bar only scrubs, and one that has held on a video (2× until it
        // lifts) only speeds it up or locks it: the whole drag is ignored, even after it wanders off.
        if PlayerScrubbing.isActive || video.hold.isHolding { dragTouchedScrubber = true }
        let dx = value.translation.width
        let dy = value.translation.height
        if dragKind == nil {
            dragKind = classifyDrag(dx: dx, dy: dy, startX: value.startLocation.x, width: width)
        }
        if dragTouchedScrubber || zoomed, dragKind != .ignored {
            dragKind = .ignored
            resetDragVisuals()
        }
        switch dragKind {
        case .closeFeed?:
            swipe = max(0, dx)
        case .openPanel?:
            panelShift = min(max(0, -dx), panelWidth)
        case .closePanel?:
            panelShift = min(max(0, dx), panelWidth)
        case .ignored?, nil:
            break
        }
    }

    private func classifyDrag(dx: CGFloat, dy: CGFloat, startX: CGFloat, width: CGFloat) -> DragKind {
        if dragTouchedScrubber || zoomed { return .ignored }
        if abs(dx) <= abs(dy) * 1.3 { return .ignored }             // mostly up or down: the feed pages
        if infoOpen { return dx > 0 ? .closePanel : .ignored }
        if dx < 0 { return startX >= width - 32 ? .openPanel : .ignored }
        return .closeFeed
    }

    private func dragEnded(_ value: DragGesture.Value) {
        let kind = dragKind
        let scrubbed = dragTouchedScrubber || PlayerScrubbing.isActive || video.hold.isHolding
        dragKind = nil
        dragTouchedScrubber = false
        guard let kind, !scrubbed, !zoomed else {
            resetDragVisuals()
            return
        }
        let dx = value.translation.width
        let predicted = value.predictedEndTranslation.width
        switch kind {
        case .closeFeed:
            if swipe > 0, swipe > 120 || predicted > 320 {
                dismiss()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { swipe = 0 }
            }
        case .openPanel:
            let open = -dx > 80 || -predicted > 200
            withAnimation(.easeOut(duration: 0.25)) {
                infoOpen = open
                panelShift = 0
            }
        case .closePanel:
            let close = dx > 80 || predicted > 200
            withAnimation(.easeOut(duration: 0.25)) {
                if close { infoOpen = false }
                panelShift = 0
            }
        case .ignored:
            resetDragVisuals()
        }
    }

    private func resetDragVisuals() {
        guard swipe != 0 || panelShift != 0 else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            swipe = 0
            panelShift = 0
        }
    }

    // The info panel

    private func openInfo() {
        withAnimation(.easeOut(duration: 0.25)) {
            infoOpen = true
            panelShift = 0
        }
    }

    private func closeInfo() {
        guard infoOpen || panelShift != 0 else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            infoOpen = false
            panelShift = 0
        }
    }

    /// A web result already saved on the side of the library this feed saves to.
    private func isSaved(_ item: ViewerItem) -> Bool {
        guard case .web(let web) = item else { return false }
        return store.hasPin(sourceURL: web.pageURL.absoluteString, scope: webScope)
    }

    private func handleInfo(_ action: QuickLookInfoAction, for item: ViewerItem) {
        switch (action, item) {
        case (.close, _):
            closeInfo()
        case (.editTitle, .pin(let pin)):
            sheet = .editTitle(store.livePin(pin.id) ?? pin)
        case (.editNote, .pin(let pin)):
            sheet = .editNote(store.livePin(pin.id) ?? pin)
        case (.editTags, .pin(let pin)):
            actions.perform(.editTags, on: [pin.id], side: side(of: pin), place: .quickLook)
        case (.addToBoard, .pin(let pin)):
            actions.perform(.addToBoard, on: [pin.id], side: side(of: pin), place: .quickLook)
        case (.moveToBoard, .pin(let pin)):
            actions.perform(.moveToBoard, on: [pin.id], side: side(of: pin), place: .quickLook)
        case (.openLink, .pin(let pin)):
            actions.perform(.openLink, on: [pin.id], side: side(of: pin), place: .quickLook)
        case (.editLink, .pin(let pin)):
            actions.perform(.editLink, on: [pin.id], side: side(of: pin), place: .quickLook)
        case (.saveWeb, .web(let web)):
            saveWeb(web, to: webTarget.boardIDs)
        case (.saveWebToBoard, .web(let web)):
            sheet = .saveWeb(web)
        default:
            break
        }
    }

    /// The side of the library a pin's actions work on: the feed's (a library feed stays on
    /// its first pin's side).
    private func side(of pin: Pin) -> PinScope {
        feedScope ?? store.scope(of: store.livePin(pin.id) ?? pin)
    }

    /// Quick Look shows the hidden side: hidden pins, or the web results of a hidden board's
    /// or hidden pin's feed. It is then covered whenever the app is not in front.
    private var showsHiddenSide: Bool {
        switch request.source {
        case .library(let seed):
            return (feedScope ?? store.scope(of: store.livePin(seed.id) ?? seed)) == .hidden
        case .web:
            return webScope == .hidden
        }
    }

    // The menu: ⋯, and touching and holding a picture (a video has only ⋯)

    @ViewBuilder
    private func menu(for item: ViewerItem) -> some View {
        switch item {
        case .pin(let pin):
            Button {
                showInfo(of: pin)
            } label: {
                Label("Show info", systemImage: "info.circle")
            }
            if pin.isVideo {
                videoMenuItems(pin)
            }
            if (store.livePin(pin.id) ?? pin).originalName != nil {
                originalButton(pin)
            }
            PinActionMenuItems(pins: [pin.id], side: side(of: pin), place: .quickLook, actions: actions)
        case .web(let web):
            // Saved = already on the side of the library this feed saves to.
            let saved = store.hasPin(sourceURL: web.pageURL.absoluteString, scope: webScope)
            Button {
                openInfo()
            } label: {
                Label("Show info", systemImage: "info.circle")
            }
            Button {
                saveWeb(web, to: webTarget.boardIDs)
            } label: {
                Label(saved ? "Saved" : "Save to library", systemImage: saved ? "checkmark" : "plus")
            }
            .disabled(saved)
            Button {
                sheet = .saveWeb(web)
            } label: {
                Label("Save to board…", systemImage: "folder.badge.plus")
            }
            Button {
                sheet = .shareWeb(web)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            // The same submenu, in the same words, as a result's menu in Explore (WebImages.swift).
            ReverseSearchMenu { (engine: ReverseImageEngine) in
                searchOnTheWeb(web, engine: engine)
            }
            Link(destination: web.pageURL) {
                Label("Open source page", systemImage: "safari")
            }
        }
    }

    /// "Search this picture on the web ▸" for a web result: the search opens on the picture's own
    /// address, in PinBoard's browser (a sheet, `webSearchPage`) or in the default browser, as Settings says.
    private func searchOnTheWeb(_ web: WebImage, engine: ReverseImageEngine) {
        webSearchPage = ReverseSearchLauncher.open(engine, imageURL: web.fullURL, settings: settings, flow: importFlow)
    }

    /// What only a video's menu has: Speed ▸ and, while it is paused, "Use this frame as thumbnail".
    @ViewBuilder
    private func videoMenuItems(_ pin: Pin) -> some View {
        VideoSpeedMenu(handle: video)
        UseFrameAsThumbnailButton(pinID: pin.id, handle: video)
    }

    /// ⋯ › Show info. A video's info is its page: Quick Look closes and the page opens in the tab
    /// that is showing (`AppRouter.open`). Everything else opens the side panel, which a swipe in
    /// from the right edge opens for every item too.
    private func showInfo(of pin: Pin) {
        let live = store.livePin(pin.id) ?? pin
        let plan = QuickLookInfoPlan.make(for: .pin(live), feed: items, pinPageUnder: request.pinPageUnder,
                                          insideSettings: isInsideSettings)
        switch plan {
        case .panel:
            openInfo()
        case .alreadyThere:
            dismiss()
        case .pinPage(let route):
            dismiss()
            openPage(route)
        }
    }

    /// Opens a pin's page once Quick Look's cover has slid away. Opening it in the same instant as
    /// the closing can lose the push (UIKit ignores one that comes while the cover still moves), so
    /// it waits a moment. The router is kept in a constant first: this view is gone by then.
    private func openPage(_ route: Route) {
        let opening = router
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(QuickLookInfoPlan.pageOpenDelayMilliseconds))
            opening.open(route)
        }
    }

    /// "Show original" (a pin whose full-size original was kept): fetched first when it is only in
    /// iCloud — the item says so meanwhile — then shown full size. (The same symbol as on the pin's
    /// page; `externaldrive` is for where it is kept, in the info panel.)
    private func originalButton(_ pin: Pin) -> some View {
        let busy = originals.fetching.contains(pin.id)
        return Button {
            showOriginal(pin)
        } label: {
            Label(busy ? StorageText.fetching : "Show original", systemImage: StorageText.showOriginalSymbol)
        }
        .disabled(busy)
    }

    /// Fetches the original, then shows it; when it doesn't come, a short message says so. Swiping
    /// to another pin or closing Quick Look stops the fetch (`stopFetchingOriginal`): nothing opens then.
    private func showOriginal(_ pin: Pin) {
        let current = store.livePin(pin.id) ?? pin
        originalTask?.cancel()
        originalTask = Task { @MainActor in
            let url = await store.fetchOriginalURL(for: current)
            guard !Task.isCancelled else { return }
            if let url {
                sheet = .original(current, url)
            } else {
                importFlow.flash(StorageText.fetchFailed, symbol: "exclamationmark.triangle")
            }
        }
    }

    private func stopFetchingOriginal() {
        originalTask?.cancel()
        originalTask = nil
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .original(let pin, let url):
            // Closed: a tidy-up comes just after the original stops counting as opened lately
            // (see `MediaOriginalRow.viewerClosed`; this sheet slot is shared, so it hangs here).
            OriginalViewerSheet(pin: pin, url: url)
                .onDisappear { store.scheduleOriginalsUpkeep(after: OriginalsFolder.afterFetchUpkeep) }
        case .saveWeb(let web):
            BoardPickerSheet(title: "Save to…", scope: webScope) { boardID in
                if let boardID { settings.lastBoardID = boardID }
                saveWeb(web, to: boardID.map { [$0] } ?? [])
            }
        case .shareWeb(let web):
            ActivityShareSheet(items: [web.pageURL], isPresented: Binding(
                get: { self.sheet?.id == sheet.id },
                set: { shown in if !shown { self.sheet = nil } }))
                .presentationDetents([.medium, .large])
        case .editTitle(let pin):
            TextEditSheet(title: "Title", placeholder: "Title", initial: pin.title) { text in
                store.setTitle(text, for: pin.id)
            }
        case .editNote(let pin):
            // `pin` is the pin as it was when the sheet opened (the case holds that copy), so `pin.note`
            // is the note the sheet started from. The store needs it to keep a transcript that was
            // written into the note while the sheet was open (see `LibraryStore.setNote(_:for:openedWith:)`).
            TextEditSheet(title: "Note", placeholder: "Anything you want to remember about this pin.",
                          initial: pin.note, multiline: true) { text in
                store.setNote(text, for: pin.id, openedWith: pin.note)
            }
        }
    }

    /// Invisible buttons that give Quick Look keyboard shortcuts.
    private func keyboardShortcuts(count: Int) -> some View {
        Group {
            Button("Previous") { step(-1, count: count) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Next") { step(1, count: count) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Close") {
                // Escape closes the info panel first, then Quick Look.
                if infoOpen { closeInfo() } else { dismiss() }
            }
            .keyboardShortcut(.cancelAction)
            videoKeys
        }
        // A disabled button gives up its shortcut: with a sheet over Quick Look every key belongs to
        // the sheet (Space types in Edit title; it must not pause the video behind it).
        .disabled(!keysAreLive)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// The keys act only while nothing is on top of Quick Look (`QuickLookKeys`).
    private var keysAreLive: Bool {
        // `actions.isPresenting`: the tags, boards and link sheets of the pin actions count too.
        QuickLookKeys.areLive(sheetUp: sheet != nil, searchUp: webSearchPage != nil,
                              actionsUp: actions.isPresenting || importFlow.review != nil || importFlow.showMessage)
    }

    /// Space plays or pauses the video in front; ← and → skip it back and forward (by Settings ›
    /// `videoSkipSeconds`). They do nothing while the page in front is not a video. (A key can't be
    /// "held" for the 2× speed: that stays a finger's job.)
    @ViewBuilder
    private var videoKeys: some View {
        Button("Play or pause") { video.togglePlay() }
            .keyboardShortcut(.space, modifiers: [])
        Button("Skip back") { video.skip(forward: false, seconds: settings.videoSkipSeconds) }
            .keyboardShortcut(.leftArrow, modifiers: [])
        Button("Skip forward") { video.skip(forward: true, seconds: settings.videoSkipSeconds) }
            .keyboardShortcut(.rightArrow, modifiers: [])
    }

    private func step(_ delta: Int, count: Int) {
        let next = index.wrappedValue + delta
        guard next >= 0, next < count else { return }
        index.wrappedValue = next
    }

    // The feed

    /// A library feed that came with a list (`request.pages`): the list's live pins on the seed's
    /// side, in its order, with the seed where it stands. Runs once, when Quick Look appears.
    private func putTogetherPages() {
        guard !feedReady else { return }
        feedReady = true
        guard let pages = request.pages, case .library(let seed) = request.source else { return }
        let scope = feedScope ?? store.scope(of: store.livePin(seed.id) ?? seed)
        items = QuickLookPages.items(seed: seed, pages: pages, scope: scope,
                                     livePin: { (id: UUID) -> Pin? in store.livePin(id) },
                                     scopeOf: { (pin: Pin) -> PinScope in store.scope(of: pin) })
    }

    /// Fresh pin data; pins deleted meanwhile (or moved to the other side of the
    /// library) drop out, and the page in front stays at the same position.
    private func refreshItems() {
        let position = index.wrappedValue
        let scope = feedScope
        let fresh = items.compactMap { item -> ViewerItem? in
            guard case .pin(let pin) = item else { return item }
            guard let live = store.livePin(pin.id) else { return nil }
            if let scope, store.scope(of: live) != scope { return nil }
            return .pin(live)
        }
        if fresh != items { items = fresh }
        if !fresh.contains(where: { $0.id == currentKey }) {
            let i = min(position, max(fresh.count - 1, 0))
            if fresh.indices.contains(i) { currentKey = fresh[i].id } else { dismiss() }
        }
    }

    /// Asks for more once the page in front is near the end of the feed.
    private func loadMoreIfNeeded() {
        // A feed that came with its list (the grid's order) is that list and nothing more.
        guard request.pages == nil else { return }
        guard !isLoadingMore, !reachedEnd, !items.isEmpty else { return }
        guard index.wrappedValue >= items.count - QuickLookView.loadAhead else { return }
        isLoadingMore = true
        Task { @MainActor in
            let (more, finished) = await fetchMore()
            isLoadingMore = false
            let known = Set(items.map { $0.id })
            var seen: Set<String> = []
            let new = more.filter { !known.contains($0.id) && seen.insert($0.id).inserted }
            if !new.isEmpty { items += new }
            if new.isEmpty || finished {
                reachedEnd = true
            } else {
                loadMoreIfNeeded()   // still near the end (only a few came back): keep going
            }
        }
    }

    /// The next items of the feed, and whether there can be no more after them.
    private func fetchMore() async -> (items: [ViewerItem], finished: Bool) {
        switch request.source {
        case .library(let seed):
            let pin = store.livePin(seed.id) ?? seed
            let limit = askedFor + QuickLookView.libraryStep
            let related = await store.relatedPins(to: pin, limit: limit, kind: pin.kind)
            askedFor = limit
            return (related.map { ViewerItem.pin($0) }, related.count < limit)
        case .web(_, _, let loadMore, _, _):
            guard let loadMore else { return ([], true) }
            let images = await loadMore()
            return (images.map { ViewerItem.web($0) }, false)
        }
    }

    // Web results

    /// Where the web feed saves results: its boards, or straight into Hidden (a hidden feed).
    private var webTarget: (boardIDs: [UUID], hidden: Bool) {
        if case .web(_, _, _, let boardIDs, let hidden) = request.source { return (boardIDs, hidden) }
        return ([], false)
    }

    /// The side of the library saved web results land on.
    private var webScope: PinScope {
        let target = webTarget
        return store.importScope(boardIDs: target.boardIDs, hidden: target.hidden)
    }

    /// Saves a web result like the feed Quick Look was opened from does: with no board
    /// chosen, a hidden feed saves straight into Hidden (never into the normal library).
    private func saveWeb(_ web: WebImage, to boards: [UUID]) {
        importFlow.importWeb([web], boardIDs: boards, hidden: boards.isEmpty && webScope == .hidden)
    }
}
