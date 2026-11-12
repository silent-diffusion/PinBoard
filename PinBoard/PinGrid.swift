//
//  PinGrid.swift  —  PinBoard
//
//  The Pinterest-style grid: its layout (masonry columns), the reusable pin
//  collection with selection mode and the selection bar, and the pin card (with
//  the grid's one-card-with-sound switch). Importing lives in ImportFlow.swift,
//  dragging and dropping in DragAndDrop.swift, the pager in MediaPager.swift,
//  Quick Look in QuickLook.swift, and what the card menus and the selection bar
//  do in PinActions.swift.
//

import SwiftUI
#if canImport(Accessibility)   // AccessibilityNotification (the selection bar's announcements) lives there
import Accessibility
#endif
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Foundation


// MARK: - Masonry grid

/// What a grid needs to know about the space it is given.
struct GridMetrics: Equatable {
    var columns: Int
    var width: CGFloat       // the width the grid may use (padding already removed)
    /// How far down the window the grid can be seen, counted from the window's top (cards show
    /// through the bars at the top and at the bottom). Cards further down are made only as you
    /// scroll near them. Grids that don't say get 1200 pt.
    var visibleHeight: CGFloat = 1200
}

extension GridMetrics {
    /// `visibleHeight` for a grid whose scroll view fills `geometry` (a GeometryReader that keeps
    /// to the safe area): from the window's top to the bottom of the scroll view, plus the bottom
    /// bars and home indicator it scrolls under. The window, not the screen: on an external
    /// display or in an iPad window they differ.
    @MainActor
    static func visibleHeight(in geometry: GeometryProxy) -> CGFloat {
        geometry.frame(in: .global).maxY + geometry.safeAreaInsets.bottom
    }
}

/// Line heights used by the cards, so the grid can compute every card's exact
/// height before anything is drawn.
enum CardMetrics {
    static var titleLineHeight: CGFloat { ceil(UIFont.preferredFont(forTextStyle: .footnote).lineHeight) }
    static var captionLineHeight: CGFloat { ceil(UIFont.preferredFont(forTextStyle: .caption2).lineHeight) }
    static let textSpacing: CGFloat = 6

    /// Extremely tall pictures are shown at 1:5 at most, so a card never becomes a sliver.
    static func clamped(_ aspectRatio: CGFloat) -> CGFloat { max(aspectRatio, 0.2) }

    /// Height of the text under a picture: an optional title line and an optional caption line.
    static func footerHeight(hasTitle: Bool, hasCaption: Bool) -> CGFloat {
        var height: CGFloat = 0
        if hasTitle { height += textSpacing + titleLineHeight }
        if hasCaption { height += textSpacing + captionLineHeight }
        return height
    }
}

/// Whether a card is inside the visible part of the screen (not just in the
/// grid's buffer). Video cards only play while this is true.
private struct CardOnScreenKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var cardOnScreen: Bool {
        get { self[CardOnScreenKey.self] }
        set { self[CardOnScreenKey.self] = newValue }
    }
}

/// How far a card is from where the playing video cards should be: from the middle of what is
/// visible (or, while the page is at its very top, from the top edge). The grid fills it in for
/// every card; a video card hands it to the budget, which lets the closest cards play first.
/// Cards outside a grid don't say: 0, as if they were in the middle.
private struct CardMiddleDistanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var cardMiddleDistance: CGFloat {
        get { self[CardMiddleDistanceKey.self] }
        set { self[CardMiddleDistanceKey.self] = newValue }
    }
}

/// Quick Look is open over this screen (set by the screen's `.pinActions`). Its cards' video
/// previews stop meanwhile: the full-screen cover hides them, and they would keep decoding behind
/// it (battery, heat, and the video in front fighting them for the decoder).
private struct QuickLookIsUpKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var quickLookIsUp: Bool {
        get { self[QuickLookIsUpKey.self] }
        set { self[QuickLookIsUpKey.self] = newValue }
    }
}

/// One video card that wants to play: how far it is from the middle, and whether it is the card
/// with sound (that one is always chosen).
struct LiveCandidate: Hashable, Sendable {
    var id: UUID
    var distance: CGFloat
    var hasPriority: Bool = false
}

/// Which video cards get a player (the plain rules; the harness tests them). Only a few cards
/// may play at once, and the owner wants the ones in the middle of the screen to be them — not
/// the ones at the very top edge (scrolling down) or the very bottom edge (scrolling up).
enum LivePreviewRanking {
    /// Whether a card wants a player at all: a video that is on screen, while Quick Look is not
    /// covering the screen, with auto-play on — or the card with sound, which plays even with
    /// auto-play off.
    nonisolated static func wantsToPlay(isVideo: Bool, onScreen: Bool, quickLookIsUp: Bool,
                                        autoPlay: Bool, hasSound: Bool) -> Bool {
        isVideo && onScreen && !quickLookIsUp && (autoPlay || hasSound)
    }

    /// A card playing keeps its player unless a waiting card is closer by more than this (about
    /// the height of a card), so scrolling a little never swaps players back and forth.
    nonisolated static let swapMargin: CGFloat = 120
    /// The ranking is redone at most this often (seconds).
    nonisolated static let rankInterval: Double = 0.4
    /// A short wait before a ranking, so every card of a screen has asked before anyone is chosen.
    nonisolated static let settleDelay: Double = 0.05

    /// How far a card is from where the players should be. While the page is at its very top
    /// (`visibleTop <= 0`: its first row isn't scrolled away) the top edge counts, so the page
    /// starts from the top, as the owner asked. Once scrolled, the middle of the visible area does.
    nonisolated static func distance(cardTop: CGFloat, cardBottom: CGFloat,
                                     visibleTop: CGFloat, visibleBottom: CGFloat) -> CGFloat {
        if visibleTop <= 0 { return max(0, cardTop) }
        let middle = (visibleTop + visibleBottom) / 2
        let center = (cardTop + cardBottom) / 2
        return abs(center - middle)
    }

    /// Who plays now: the card with sound first, then the closest cards up to `limit`. A card that
    /// is playing already stays unless a waiting one is closer by more than `swapMargin`.
    /// (Pass `.infinity` as the margin to only fill free places and never swap.)
    nonisolated static func chosen(from candidates: [LiveCandidate], playing: Set<UUID>, limit: Int,
                                   swapMargin margin: CGFloat = swapMargin) -> Set<UUID> {
        let byDistance: [LiveCandidate] = candidates.sorted(by: closer)
        var result: Set<UUID> = []
        for candidate in byDistance where candidate.hasPriority && result.count < limit {
            result.insert(candidate.id)
        }
        let places = limit - result.count
        guard places > 0 else { return result }
        let others = byDistance.filter { (candidate: LiveCandidate) -> Bool in !candidate.hasPriority }
        var keepers = others.filter { (candidate: LiveCandidate) -> Bool in playing.contains(candidate.id) }
        if keepers.count > places { keepers = Array(keepers.prefix(places)) }
        var waiting = others.filter { (candidate: LiveCandidate) -> Bool in !keepers.contains(candidate) }
        while keepers.count < places, !waiting.isEmpty {
            keepers.append(waiting.removeFirst())
        }
        swapCloserOnes(keepers: &keepers, waiting: &waiting, margin: margin)
        for candidate in keepers { result.insert(candidate.id) }
        return result
    }

    /// Nearest first; the same distance goes by id, so the answer never depends on the order the
    /// cards asked in.
    private nonisolated static func closer(_ a: LiveCandidate, _ b: LiveCandidate) -> Bool {
        if a.distance != b.distance { return a.distance < b.distance }
        return a.id.uuidString < b.id.uuidString
    }

    /// The farthest card that plays gives its place to the closest waiting card while that one is
    /// closer by more than `margin`. Each swap makes the set closer overall, so this ends.
    private nonisolated static func swapCloserOnes(keepers: inout [LiveCandidate], waiting: inout [LiveCandidate],
                                                   margin: CGFloat) {
        while let nearest = waiting.first, let far = farthestIndex(in: keepers) {
            guard keepers[far].distance - nearest.distance > margin else { return }
            let leaving = keepers[far]
            keepers[far] = nearest
            waiting.removeFirst()
            waiting.append(leaving)
            waiting.sort(by: closer)
        }
    }

    /// The place (in the list) of the card that is farthest away; nil for an empty list.
    private nonisolated static func farthestIndex(in list: [LiveCandidate]) -> Int? {
        var best: Int? = nil
        for index in list.indices {
            guard let current = best else {
                best = index
                continue
            }
            if closer(list[current], list[index]) { best = index }
        }
        return best
    }

    /// How long to wait before the next ranking: at least `settleDelay`, and never sooner than
    /// `rankInterval` after the last one. (Times are seconds on any one clock.)
    nonisolated static func waitBeforeRanking(now: Double, lastRank: Double) -> Double {
        max(settleDelay, lastRank + rankInterval - now)
    }
}

/// Pinterest-style staggered grid: each item goes into whichever column is
/// currently shortest. Every card gets an exact, precomputed frame, so the scroll
/// position never jumps while pictures load or come back into view — and only
/// the cards near the visible area exist at any time, which keeps memory low.
struct MasonryGrid<Item: Identifiable, Content: View>: View {
    var items: [Item]
    var metrics: GridMetrics
    var aspectRatio: (Item) -> CGFloat
    /// Extra height under the picture (title lines, buttons…). Default: nothing.
    var footerHeight: (Item) -> CGFloat = { _ in 0 }
    /// The whole card's height at a given column width, for items whose height
    /// does not come from a picture (text pins, links without a preview). nil = use the aspect ratio.
    var cardHeight: (Item, CGFloat) -> CGFloat? = { _, _ in nil }
    @ViewBuilder var content: (Item) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize   // read so text-size changes re-run the layout
    @State private var originBucket: CGFloat = 0   // the grid's top edge on screen, in 200-pt steps

    private struct Placed {
        var item: Item
        var frame: CGRect
    }

    private var columnWidth: CGFloat {
        let count = max(metrics.columns, 1)
        return max(1, (metrics.width - PinTheme.gridSpacing * CGFloat(count - 1)) / CGFloat(count))
    }

    /// Positions of all cards and the total height of the grid.
    private var layout: (placed: [Placed], height: CGFloat) {
        let count = max(metrics.columns, 1)
        let spacing = PinTheme.gridSpacing
        let width = columnWidth
        var bottoms = Array(repeating: CGFloat(0), count: count)
        var placed: [Placed] = []
        placed.reserveCapacity(items.count)
        for item in items {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let height: CGFloat
            if let whole = cardHeight(item, width) {
                height = whole.rounded() + footerHeight(item).rounded()
            } else {
                height = (width / CardMetrics.clamped(aspectRatio(item))).rounded() + footerHeight(item).rounded()
            }
            let frame = CGRect(x: CGFloat(column) * (width + spacing), y: bottoms[column], width: width, height: height)
            placed.append(Placed(item: item, frame: frame))
            bottoms[column] = frame.maxY + spacing
        }
        let total = max(0, (bottoms.max() ?? 0) - spacing)
        return (placed, total)
    }

    var body: some View {
        let result = layout
        let margin: CGFloat = 500
        // Visible part of the grid, in the grid's own coordinates: from the window's top down
        // to `metrics.visibleHeight` (what the grid's own window shows, not the whole screen).
        let visibleTop = -originBucket
        let visibleBottom = -originBucket + metrics.visibleHeight
        let top = visibleTop - margin
        let bottom = visibleBottom + margin
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(metrics.width, 1), height: max(result.height, 1))
            ForEach(result.placed.filter { $0.frame.maxY >= top && $0.frame.minY <= bottom }, id: \.item.id) { placed in
                content(placed.item)
                    .environment(\.cardOnScreen, placed.frame.maxY >= visibleTop - 100 && placed.frame.minY <= visibleBottom + 100)
                    .environment(\.cardMiddleDistance, middleDistance(of: placed.frame, visibleTop: visibleTop, visibleBottom: visibleBottom))
                    .frame(width: placed.frame.width, height: placed.frame.height, alignment: .top)
                    .clipped()
                    .offset(x: placed.frame.minX, y: placed.frame.minY)
            }
        }
        .frame(width: max(metrics.width, 1), height: max(result.height, 1), alignment: .topLeading)
        .background {
            // Follows the grid's top edge as it scrolls, in 200-pt steps.
            GeometryReader { proxy in
                let bucket = (proxy.frame(in: .global).minY / 200).rounded(.down) * 200
                Color.clear.task(id: bucket) { originBucket = bucket }
            }
        }
    }

    /// How far a card is from the middle of the visible area (from the top edge while the page is
    /// at its very top): the video cards that play first are the ones with the smallest number.
    private func middleDistance(of frame: CGRect, visibleTop: CGFloat, visibleBottom: CGFloat) -> CGFloat {
        LivePreviewRanking.distance(cardTop: frame.minY, cardBottom: frame.maxY,
                                    visibleTop: visibleTop, visibleBottom: visibleBottom)
    }
}

/// Only a few video cards may play at once (the system stops decoding when too
/// many players exist at the same time). Cards that want to play tell it how far they are from
/// the middle of the screen, and it lets the closest ones play (see `LivePreviewRanking`): a
/// screen full of videos plays the ones in the middle, not the ones at the very edge. The
/// ranking is redone at most every 0.4 s, and a playing card is only replaced by one that is
/// clearly closer, so scrolling never makes the players jump around.
@MainActor
final class LivePreviewBudget: ObservableObject {
    static let shared = LivePreviewBudget()
    static let limit = 6

    @Published private(set) var active: Set<UUID> = []
    /// Every card that wants to play, with its distance (not published: only `active` redraws cards).
    private var candidates: [UUID: LiveCandidate] = [:]
    private var lastRank = Date.distantPast
    private var pendingRank: Task<Void, Never>? = nil

    func isActive(_ id: UUID) -> Bool { active.contains(id) }

    /// A card wants to play. `distance`: from the middle of the visible area (see
    /// `cardMiddleDistance`). `priority`: the card with sound — it is chosen at once, in front of
    /// every other card.
    func request(_ id: UUID, distance: CGFloat, priority: Bool = false) {
        store(LiveCandidate(id: id, distance: distance, hasPriority: priority))
    }

    /// A card that wants to play is now at another distance (the screen scrolled). Cards that
    /// don't want to play (or gave their place back) are left out.
    func update(_ id: UUID, distance: CGFloat, priority: Bool = false) {
        guard candidates[id] != nil else { return }
        store(LiveCandidate(id: id, distance: distance, hasPriority: priority))
    }

    /// A card stopped wanting to play (left the screen, or auto-play went off): its place goes to
    /// the closest waiting card at the next ranking.
    func release(_ id: UUID) {
        guard candidates.removeValue(forKey: id) != nil else { return }
        if active.contains(id) {
            active.remove(id)
            scheduleRanking()
        }
    }

    private func store(_ candidate: LiveCandidate) {
        guard candidates[candidate.id] != candidate else { return }
        candidates[candidate.id] = candidate
        if candidate.hasPriority, !active.contains(candidate.id) {
            pendingRank?.cancel()
            pendingRank = nil
            rank()   // the card with sound doesn't wait
        } else {
            scheduleRanking()
        }
    }

    /// Ranks soon: a moment for the rest of the screen to ask first, and never sooner than 0.4 s
    /// after the last ranking. Asking again while one is waiting changes nothing.
    private func scheduleRanking() {
        guard pendingRank == nil else { return }
        let wait = LivePreviewRanking.waitBeforeRanking(now: Date().timeIntervalSinceReferenceDate,
                                                        lastRank: lastRank.timeIntervalSinceReferenceDate)
        pendingRank = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.pendingRank = nil
            self.rank()
        }
    }

    /// Chooses who plays now.
    private func rank() {
        lastRank = Date()
        let chosen = LivePreviewRanking.chosen(from: Array(candidates.values), playing: active,
                                               limit: LivePreviewBudget.limit)
        if chosen != active { active = chosen }
    }
}

// MARK: - Reusable pin grid with selection + batch actions

struct PinCollectionView<Header: View, Footer: View>: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    let pins: [Pin]
    @Binding var isSelecting: Bool
    var captions: [UUID: String]
    var emptyIcon: String
    var emptyTitle: String
    var emptyMessage: String
    var boardID: UUID?              // the board this grid shows, for "Remove from this board"
    var smartBoardID: UUID?         // the smart board this grid shows, for "Remove from this smart board"
    /// Which side of the library the grid shows: a hidden grid offers "Unhide pin"
    /// instead of "Hide pin", and its board pickers list hidden boards only.
    var scope: PinScope
    var header: (GridMetrics) -> Header     // both receive the current column count and width
    var footer: (GridMetrics) -> Footer
    /// The feed this grid shows, if its order is one you choose (the Pins tab's All,
    /// Hidden › All, a board page): the grid shows `pins` in the feed's order, pulling
    /// down shuffles it again, and it tells FeedOrder whether it is at its top.
    var feed: Feed? = nil

    @ObservedObject private var feedOrder = FeedOrder.shared
    @StateObject private var actions = PinActions()   // what the card menus and the selection bar ask for
    @State private var selection: Set<UUID> = []

    init(pins: [Pin],
         isSelecting: Binding<Bool>,
         captions: [UUID: String] = [:],
         emptyIcon: String = "photo",
         emptyTitle: String = "Nothing here",
         emptyMessage: String = "",
         boardID: UUID? = nil,
         smartBoardID: UUID? = nil,
         scope: PinScope = .visible,
         feed: Feed? = nil,
         @ViewBuilder header: @escaping (GridMetrics) -> Header,
         @ViewBuilder footer: @escaping (GridMetrics) -> Footer) {
        self.pins = pins
        self._isSelecting = isSelecting
        self.captions = captions
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.boardID = boardID
        self.smartBoardID = smartBoardID
        self.scope = scope
        self.feed = feed
        self.header = header
        self.footer = footer
    }

    private var selectedVisible: Set<UUID> {
        selection.intersection(pins.map { $0.id })
    }

    /// The pins as shown: in the feed's order when the grid shows a feed.
    private var shownPins: [Pin] {
        guard let feed else { return pins }
        return feedOrder.arrange(pins, in: feed)   // (a new order redraws the grid: it observes feedOrder)
    }

    var body: some View {
        let listed = shownPins   // arranged once per render
        let allIDs = listed.map { $0.id }   // once per render, not once per card
        GeometryReader { geometry in
            let metrics = GridMetrics(columns: settings.columnCount(forWidth: geometry.size.width),
                                      width: geometry.size.width - PinTheme.gridSpacing * 2,
                                      visibleHeight: GridMetrics.visibleHeight(in: geometry))
            let scrollTop = geometry.frame(in: .global).minY
            let textStyle = settings.textStyle
            ScrollView {
                VStack(spacing: PinTheme.gridSpacing) {
                    // At the very top: tells the feed's order whether the grid is at its top.
                    FeedTopMarker(feed: feed, scrollTop: scrollTop)
                    header(metrics)
                    if listed.isEmpty {
                        EmptyStateView(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                            .padding(.top, 40)
                    } else {
                        MasonryGrid(items: listed, metrics: metrics,
                                    aspectRatio: { $0.aspectRatio },
                                    footerHeight: { PinCardView.footerHeight(for: $0, caption: captions[$0.id]) },
                                    cardHeight: { pin, width in
                                        PinCardView.fixedHeight(for: pin, width: width, textStyle: textStyle)
                                    }) { pin in
                            card(for: pin, allIDs: allIDs)
                        }
                    }
                    footer(metrics)
                }
                .padding(.horizontal, PinTheme.gridSpacing)
                .padding(.bottom, 24)
            }
            .hidesBarsOnScroll(enabled: !isSelecting)   // scrolling down tucks the bars away (ScrollingBars.swift)
            .feedRefreshable(feed)
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                let chosen = selectedVisible
                BatchActionBar(actions: actions,
                               selected: chosen,
                               allSelected: !pins.isEmpty && chosen.count == pins.count,
                               scope: scope,
                               boardID: boardID,
                               smartBoardID: smartBoardID,
                               onSelectAll: {
                                   if selectedVisible.count == pins.count { selection = [] } else { selection = Set(pins.map { $0.id }) }
                               },
                               onDone: finishSelecting)
            }
        }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selection = [] }
        }
        .pinActions(actions, onSelectionDone: finishSelecting, onSelect: startSelecting)
        // Quick Look from a card pages through this grid's pins, in the order shown here (the
        // order of a feed, as it is now): the screen's actions ask for the list when Quick Look opens.
        .onAppear { actions.quickLookPages = { allIDs } }
        .onChange(of: allIDs) { _, ids in actions.quickLookPages = { ids } }
    }

    @ViewBuilder
    private func card(for pin: Pin, allIDs: [UUID]) -> some View {
        let isSelected = selection.contains(pin.id)
        let cardView = PinCardView(pin: pin,
                                   isSelecting: isSelecting,
                                   isSelected: isSelected,
                                   caption: captions[pin.id],
                                   onToggleSelect: { toggle(pin.id) })
        if isSelecting {
            // Tapping anywhere on a card selects or deselects it. VoiceOver: the card is a
            // button that says whether it is selected; double-tapping it does the same.
            cardView
                .contentShape(Rectangle())
                .onTapGesture { toggle(pin.id) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle(pin.id) }
                .contextMenu {
                    Button {
                        actions.perform(.quickLook, on: [pin.id], side: scope, place: .grid)
                    } label: {
                        Label("Quick look", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
        } else if pin.isVideo {
            // A video opens full screen at once, in Quick Look; its ⋯ › Show info goes on to the
            // pin's page. (The long-press menu is the same as on every other card.)
            Button {
                actions.perform(.quickLook, on: [pin.id], side: scope, place: .grid)
            } label: {
                cardView
            }
            .buttonStyle(.plain)
            .modifier(PinDraggable(pin: pin, store: store))
            .contextMenu { contextMenu(for: pin) }
        } else {
            NavigationLink(value: Route.pin(pin.id, PinContext(ids: allIDs, around: pin.id))) {
                cardView
            }
            .buttonStyle(.plain)
            .modifier(PinDraggable(pin: pin, store: store))
            .contextMenu { contextMenu(for: pin) }
        }
    }

    /// A card's long-press menu: everything the ⋯ menu offers, "Select" first (PinActions.swift).
    @ViewBuilder
    private func contextMenu(for pin: Pin) -> some View {
        PinActionMenuItems(pins: [pin.id], side: scope, place: .grid, actions: actions,
                           boardID: boardID, smartBoardID: smartBoardID)
    }

    /// "Select" in a card's menu: selecting starts with this pin chosen.
    private func startSelecting(_ id: UUID) {
        withAnimation {
            selection = [id]
            isSelecting = true
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func finishSelecting() {
        withAnimation {
            selection = []
            isSelecting = false
        }
    }
}

/// Drag a card: out of the app as a file or text, onto a board tile as itself
/// (what it carries: `PinDragOut` in DragAndDrop.swift).
private struct PinDraggable: ViewModifier {
    let pin: Pin
    let store: LibraryStore

    func body(content: Content) -> some View {
        let pin = pin
        let file: URL?
        switch pin.kind {
        case .image: file = store.imageFileURL(for: pin)
        case .video: file = store.videoFileURL(for: pin)
        case .text, .link: file = nil
        }
        return content.onDrag { PinDragOut.provider(for: pin, file: file) }
    }
}

extension PinCollectionView where Footer == EmptyView {
    init(pins: [Pin],
         isSelecting: Binding<Bool>,
         captions: [UUID: String] = [:],
         emptyIcon: String = "photo",
         emptyTitle: String = "Nothing here",
         emptyMessage: String = "",
         boardID: UUID? = nil,
         smartBoardID: UUID? = nil,
         scope: PinScope = .visible,
         feed: Feed? = nil,
         @ViewBuilder header: @escaping (GridMetrics) -> Header) {
        self.init(pins: pins,
                  isSelecting: isSelecting,
                  captions: captions,
                  emptyIcon: emptyIcon,
                  emptyTitle: emptyTitle,
                  emptyMessage: emptyMessage,
                  boardID: boardID,
                  smartBoardID: smartBoardID,
                  scope: scope,
                  feed: feed,
                  header: header,
                  footer: { _ in EmptyView() })
    }
}

/// The top line of a selection bar (pins and boards): how many are selected, "Select all" /
/// "Deselect all" and "Done". The two buttons are at least 44 pt high (Apple's smallest touch
/// target; a bare line of text is about 20 pt). When the three do not fit on one line (a large text
/// size, a narrow window) the count moves above the buttons, and at the very largest sizes each
/// button gets a line of its own, so nothing is cut off.
struct SelectionBarHeader: View {
    var countText: String
    var isBusy: Bool = false
    var allSelected: Bool
    var onSelectAll: () -> Void
    var onDone: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                countLabel
                Spacer(minLength: 8)
                selectAllButton
                doneButton.padding(.leading, 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                countLabel
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    selectAllButton
                    doneButton.padding(.leading, 12)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                countLabel
                selectAllButton
                doneButton
            }
        }
    }

    /// "3 selected" (and a small spinner while a job runs).
    private var countLabel: some View {
        HStack(spacing: 8) {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var selectAllButton: some View {
        Button(action: onSelectAll) {
            Text(allSelected ? "Deselect all" : "Select all")
                .font(.subheadline)
                .frame(minHeight: 44)          // inside the label: this is what makes the tap area tall
                .contentShape(Rectangle())
        }
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// Bottom bar shown while selecting pins. Its buttons and its "More" menu ask `actions`
/// (PinActions.swift) to act on the selected pins. A button's name and symbol come from
/// `PinAction.label`, so each command has one name everywhere. The buttons show their names
/// when every name fits whole; otherwise only their symbols (VoiceOver still says the names),
/// in two rows at the largest text sizes. Text is never shrunk below its size.
/// (A later option: the system's bottom toolbar instead of this bar.)
struct BatchActionBar: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var actions: PinActions
    var selected: Set<UUID>
    var allSelected: Bool
    var scope: PinScope
    var boardID: UUID?          // the grid's board and smart board, for "Remove from this…"
    var smartBoardID: UUID?
    var onSelectAll: () -> Void
    var onDone: () -> Void

    /// The actions that have a button of their own ("More" leaves them out).
    private var buttonActions: [PinAction] { [.editTags, .addToBoard, .moveToBoard, .sortIntoBoards, .delete] }

    /// The AI sorting menu's own name and symbol (as AISortingMenu in BoardViews.swift shows them).
    private static let aiTitle = "AI sorting"
    private static let aiIcon = "wand.and.stars"
    /// "More": every other pin action.
    private static let moreTitle = "More"
    private static let moreIcon = "ellipsis.circle"
    private static let hint = "Tap pins to select or deselect them. Touch and hold one for Quick look."

    /// The VoiceOver announcement waiting to be said (see `announce`).
    @State private var announcement: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 8) {
            SelectionBarHeader(countText: countText, isBusy: actions.isBusy, allSelected: allSelected,
                               onSelectAll: onSelectAll, onDone: onDone)
            buttonRows
                .disabled(selected.isEmpty || actions.isBusy)
            Text(BatchActionBar.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial)
        .onAppear { announce(withHint: true) }
        .onChange(of: selected.count) { announce(withHint: false) }
        .onDisappear { announcement?.cancel() }   // selecting is over: nothing more to say
    }

    /// "3 selected".
    private var countText: String { "\(selected.count) selected" }

    /// VoiceOver says how many pins are selected and how selecting works when the bar comes up,
    /// then the new count whenever it changes. It waits a moment, so VoiceOver has first said
    /// "Selected" for the card, and only the latest count is said. (Without VoiceOver: nothing.)
    private func announce(withHint: Bool) {
        let text = withHint ? "\(countText). \(BatchActionBar.hint)" : countText
        announcement?.cancel()
        announcement = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(text).post()
        }
    }

    private func perform(_ action: PinAction) {
        actions.perform(action, on: selected, side: scope, place: .selection, boardID: boardID)
    }

    // The buttons

    /// The six buttons: with their names if all of them fit, else just symbols in one row, else
    /// (the largest text sizes) in two rows of three.
    private var buttonRows: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                firstButtons(titled: true)
                lastButtons(titled: true)
            }
            HStack(spacing: 6) {
                firstButtons(titled: false)
                lastButtons(titled: false)
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) { firstButtons(titled: false) }
                HStack(spacing: 6) { lastButtons(titled: false) }
            }
        }
    }

    /// Edit tags, Add to board, Move to board (only when a selected pin is on a board: pins
    /// that are on none have nothing to be moved from).
    @ViewBuilder
    private func firstButtons(titled: Bool) -> some View {
        actionButton(.editTags, titled: titled)
        actionButton(.addToBoard, titled: titled)
        if canMove {
            actionButton(.moveToBoard, titled: titled)
        }
    }

    /// Whether "Move to board…" applies: at least one selected pin is on a board of its side.
    private var canMove: Bool {
        store.isAnyOnABoard(selected.compactMap { (id: UUID) -> Pin? in store.livePin(id) })
    }

    /// AI sorting, More, Delete.
    @ViewBuilder
    private func lastButtons(titled: Bool) -> some View {
        aiButton(titled: titled)
        moreButton(titled: titled)
        actionButton(.delete, titled: titled)
    }

    /// The button of one pin action, named and drawn as in the menus.
    private func actionButton(_ action: PinAction, titled: Bool) -> some View {
        let label = action.label(count: selected.count)
        return Button(role: action == .delete ? .destructive : nil) {
            perform(action)
        } label: {
            barLabel(label.text, icon: label.icon, titled: titled)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label.text)
        .modifier(NameWhenHeld(title: label.text, icon: label.icon, iconOnly: !titled))
    }

    /// "AI sorting": sort into boards, tags, names — for the selected pins.
    private func aiButton(titled: Bool) -> some View {
        Menu {
            AISortingMenuItems(target: .pins(selected, scope: scope), prompt: $actions.aiPrompt,
                               sortIntoBoards: { perform(.sortIntoBoards) }, onChosen: onDone)
        } label: {
            barLabel(BatchActionBar.aiTitle, icon: BatchActionBar.aiIcon, titled: titled)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(BatchActionBar.aiTitle)
        .modifier(NameWhenHeld(title: BatchActionBar.aiTitle, icon: BatchActionBar.aiIcon, iconOnly: !titled))
    }

    /// "More": every other pin action for the selected pins.
    private func moreButton(titled: Bool) -> some View {
        Menu {
            PinActionMenuItems(pins: selected, side: scope, place: .selection, actions: actions,
                               boardID: boardID, smartBoardID: smartBoardID, except: buttonActions)
        } label: {
            barLabel(BatchActionBar.moreTitle, icon: BatchActionBar.moreIcon, titled: titled)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(BatchActionBar.moreTitle)
        .modifier(NameWhenHeld(title: BatchActionBar.moreTitle, icon: BatchActionBar.moreIcon, iconOnly: !titled))
    }

    /// Inside a button: the symbol, with the name under it when `titled`.
    private func barLabel(_ title: String, icon: String, titled: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
            if titled { caption(title) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// A button's name, as wide as the longest name of the bar: the other names are there,
    /// invisible, only to take up that room. So all buttons ask for one width, and the row
    /// with names is chosen only when every name fits whole.
    private func caption(_ title: String) -> some View {
        ZStack {
            ForEach(allTitles, id: \.self) { other in
                Text(other).hidden()
            }
            Text(title)
        }
        .font(.caption2)
        .lineLimit(1)
    }

    /// Every button's name.
    private var allTitles: [String] {
        let named: [PinAction] = [.editTags, .addToBoard, .moveToBoard, .delete]
        var titles = named.map { (action: PinAction) -> String in action.label(count: selected.count).text }
        titles.append(BatchActionBar.aiTitle)
        titles.append(BatchActionBar.moreTitle)
        return titles
    }
}

/// A selection bar button that shows only its symbol: with one of the largest text sizes on
/// (Settings › Accessibility › Larger Text), touching and holding it shows its name and symbol
/// large in the middle of the screen — Apple's large content viewer, as for tab bar items.
/// A button that shows its name needs none of that.
private struct NameWhenHeld: ViewModifier {
    let title: String
    let icon: String
    let iconOnly: Bool

    func body(content: Content) -> some View {
        if iconOnly {
            content.accessibilityShowsLargeContentViewer {
                Label(title, systemImage: icon)
            }
        } else {
            content
        }
    }
}

// MARK: - Pin card

struct PinCardView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var budget = LivePreviewBudget.shared
    @ObservedObject private var sound = SoundState.shared
    @Environment(\.pinAccent) private var accent
    @Environment(\.cardOnScreen) private var onScreen
    @Environment(\.cardMiddleDistance) private var middleDistance
    @Environment(\.quickLookIsUp) private var quickLookIsUp
    let pin: Pin
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var caption: String? = nil
    var onToggleSelect: () -> Void = {}

    @State private var image: UIImage? = nil

    /// This card is the one in the grids that plays with sound.
    private var hasSound: Bool { pin.isVideo && sound.gridSoundPinID == pin.id }

    /// The speaker button: only for videos known to have a sound track.
    private var showsSpeaker: Bool { pin.isVideo && pin.hasAudio == true && !isSelecting }

    /// The exact height of the text under the picture (the grid relies on it).
    /// Text pins carry their title inside the card, so only a caption counts.
    static func footerHeight(for pin: Pin, caption: String?) -> CGFloat {
        let hasTitle = !pin.title.isEmpty && !pin.isText && !(pin.isLink && !pin.hasPreview)
        var height = CardMetrics.footerHeight(hasTitle: hasTitle, hasCaption: !(caption ?? "").isEmpty)
        if pin.isLink, pin.hasPreview, pin.linkHost != nil { height += CardMetrics.textSpacing + CardMetrics.captionLineHeight }
        return height
    }

    /// Cards whose height is not given by a picture: text pins and links without a preview.
    @MainActor
    static func fixedHeight(for pin: Pin, width: CGFloat, textStyle: TextCardStyle) -> CGFloat? {
        if pin.isText { return textStyle.cardHeight(title: pin.title, body: pin.textBody, width: width) }
        if pin.isLink, !pin.hasPreview { return LinkCardView.noPreviewHeight }
        return nil
    }

    /// A video card plays while it is on screen — with auto-play on, or when it
    /// is the card with sound (that one plays even with auto-play off) — and not while Quick Look
    /// is open over the screen.
    private var wantsLive: Bool {
        LivePreviewRanking.wantsToPlay(isVideo: pin.isVideo, onScreen: onScreen, quickLookIsUp: quickLookIsUp,
                                       autoPlay: settings.autoPlayVideos, hasSound: hasSound)
    }

    private var playsLive: Bool {
        wantsLive && budget.isActive(pin.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardMetrics.textSpacing) {
            ZStack(alignment: .topTrailing) {
                switch pin.kind {
                case .text:
                    TextCardView(pin: pin, style: settings.textStyle, color: settings.textPinColor)
                        .overlay { selectionBorder }
                case .link:
                    LinkCardView(pin: pin, image: image)
                        .overlay { selectionBorder }
                case .image, .video:
                    Color(uiColor: .secondarySystemFill)
                        .aspectRatio(CardMetrics.clamped(pin.aspectRatio), contentMode: .fit)
                        .overlay { posterLayer }
                        .overlay { liveLayer }
                        .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
                        .overlay { selectionBorder }
                        .overlay(alignment: .bottomLeading) {
                            badges
                                .padding(8)
                                .padding(.trailing, showsSpeaker ? 48 : 0)   // leaves room for the speaker
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if showsSpeaker { speakerButton.padding(5) }
                        }
                }

                if isSelecting {
                    Button(action: onToggleSelect) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? accent : Color.black.opacity(0.35))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)   // for the eye: VoiceOver hears "Selected" on the card itself
                }
            }
            if !pin.title.isEmpty, !pin.isText, !(pin.isLink && !pin.hasPreview) {
                Text(pin.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .frame(height: CardMetrics.titleLineHeight, alignment: .leading)
            }
            if pin.isLink, pin.hasPreview, let host = pin.linkHost {
                Text(host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: CardMetrics.captionLineHeight, alignment: .leading)
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: CardMetrics.captionLineHeight, alignment: .leading)
            }
        }
        .opacity(isSelecting && !isSelected ? 0.75 : 1)
        // VoiceOver: the card is one element that says what the pin is and whether it is
        // selected. The speaker is drawn for the eye; for VoiceOver it is an action of the card.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selectionTraits)
        .accessibilityActions {
            if showsSpeaker {
                Button(soundActionName) { toggleSound() }
            }
        }
        // Loads again for a new picture file (turned, flipped, cropped: `pictureRevision`) too.
        .task(id: "\(pin.id)|\(pin.hasPreview)|\(pin.pictureRevision)|\(pin.updatedAt.timeIntervalSince1970)") {
            if pin.hasImageFile { image = await store.thumbnail(for: pin) } else { image = nil }
        }
        .task(id: pin.id) {
            // Older videos were never checked for a sound track: find out once.
            if pin.isVideo, pin.hasAudio == nil { await store.ensureAudioInfo(for: pin.id) }
        }
        .onAppear { updateLivePreview() }
        .onDisappear {
            budget.release(pin.id)
            if hasSound { sound.gridSoundPinID = nil }   // gone from the screen: silent again
        }
        .onChange(of: onScreen) { _, visible in
            // A card that leaves the screen stops; the one with sound also goes quiet for good.
            if !visible, hasSound { sound.gridSoundPinID = nil }
            updateLivePreview()
        }
        .onChange(of: settings.autoPlayVideos) { updateLivePreview() }
        .onChange(of: hasSound) { updateLivePreview() }
        .onChange(of: quickLookIsUp) { updateLivePreview() }   // players stop under Quick Look, start again after
        .onChange(of: middleDistance) { _, distance in
            // The screen scrolled: the budget ranks this card again (only video cards that want to play).
            guard pin.isVideo, wantsLive else { return }
            budget.update(pin.id, distance: distance, priority: hasSound)
        }
    }

    /// The picture of a picture pin, or a video's poster. It stays in place underneath a playing
    /// video, so the card never shows a grey or empty rectangle while the video starts.
    @ViewBuilder
    private var posterLayer: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ProgressView()
        }
    }

    /// The playing video, above the poster. It is invisible until its first picture is ready
    /// (see `LoopingPlayerView`), then fades in over the poster.
    @ViewBuilder
    private var liveLayer: some View {
        if playsLive, !store.isOffloaded(pin) {   // (a video kept in iCloud only shows its poster here)
            LoopingVideoView(url: store.videoFileURL(for: pin), muted: !hasSound)
        }
    }

    /// The larger speaker button on video cards (see `toggleSound`). Its circle is 42 pt; it
    /// answers to touches in a 44-pt circle, Apple's minimum.
    private var speakerButton: some View {
        Button {
            toggleSound()
        } label: {
            Image(systemName: hasSound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.45), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)   // VoiceOver: the card's "Turn sound on/off" action instead
    }

    /// Makes this the one card with sound and turns sound on (so the video keeps it when
    /// opened), or turns sound off again.
    private func toggleSound() {
        if hasSound {
            sound.gridSoundPinID = nil
            sound.soundOn = false
        } else {
            sound.gridSoundPinID = pin.id
            sound.soundOn = true
            PlaybackPositions.shared.silenceBigPlayers()   // one video with sound at a time
        }
    }

    private var soundActionName: String { hasSound ? "Turn sound off" : "Turn sound on" }

    /// VoiceOver says "Selected" for a selected card (and nothing extra otherwise).
    private var selectionTraits: AccessibilityTraits { isSelected ? .isSelected : [] }

    /// What VoiceOver says for the card: the kind of pin (for a link that was read fully, what it
    /// was read as: "Article", "YouTube video"), a video's length, its title (a text pin: the
    /// start of its text too), a link's site and the caption.
    private var accessibilityText: String {
        var parts = [PinCardView.kindName(pin.kind)]
        if pin.isLink, let flavor = pin.linkFlavor, flavor != .page { parts.append(flavor.label) }
        if pin.isVideo, let length = VideoTools.durationText(pin.duration) { parts.append(length) }
        if !pin.title.isEmpty { parts.append(pin.title) }
        if pin.isText, !pin.textBody.isEmpty { parts.append(String(pin.textBody.prefix(160))) }
        if pin.isLink, let host = pin.linkHost { parts.append(host) }
        if let caption, !caption.isEmpty { parts.append(caption) }
        return parts.joined(separator: ", ")
    }

    /// One pin's kind in words: "Photo", "Video", "Text", "Link" (where the filters say "Photos").
    /// VoiceOver says it on the cards; an untitled pin's page is called by it too.
    static func kindName(_ kind: PinKind) -> String {
        switch kind {
        case .image: return "Photo"
        case .video: return "Video"
        case .text: return "Text"
        case .link: return "Link"
        }
    }

    private func updateLivePreview() {
        guard pin.isVideo else { return }
        if wantsLive {
            // The card with sound always gets a player; the others by how close to the middle they are.
            budget.request(pin.id, distance: middleDistance, priority: hasSound)
        } else {
            budget.release(pin.id)
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous)
            .strokeBorder(accent, lineWidth: isSelected ? 3 : 0)
    }

    /// Badges shrink to icons on narrow cards (many columns, large text).
    private var badges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { badgeItems(compact: false) }
            HStack(spacing: 4) { badgeItems(compact: true) }
        }
    }

    @ViewBuilder
    private func badgeItems(compact: Bool) -> some View {
        if pin.isVideo {
            badge(compact ? nil : (VideoTools.durationText(pin.duration) ?? "Video"), icon: "play.fill")
        }
        if pin.needsAnalysis {
            badge(compact ? nil : "Tagging…", icon: "sparkles")
        }
        // A normal card never hints at hidden pins or boards (a twin across the hidden
        // line, or hidden boards it is also on).
        if pin.duplicateOfID != nil, store.duplicateTwin(of: pin) != nil {
            badge(compact ? nil : "Duplicate?", icon: "square.on.square")
        }
        if pin.boardIDs.count > 1 {
            let shown = store.shownBoardIDs(for: pin).count
            if shown > 1 {
                badge(compact ? nil : "\(shown) boards", icon: "folder")
            }
        }
    }

    private func badge(_ text: String?, icon: String) -> some View {
        Group {
            if let text {
                Label(text, systemImage: icon)
            } else {
                Image(systemName: icon)
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, text == nil ? 6 : 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
