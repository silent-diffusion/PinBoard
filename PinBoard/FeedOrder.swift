//
//  FeedOrder.swift  —  PinBoard
//
//  The order a list of pins is shown in, and when that order changes.
//
//  Three kinds of feed have an order you choose in their ⋯ menu: the Pins tab's
//  All, Hidden › All, and board pages (all boards share one setting). The menu is
//  Apple's sort menu: a checkmarked choice of Shuffled, Newest first or Oldest
//  first, and "Shuffle again" while shuffled. A shuffle has a seed that stays put
//  until it should change; a date order stays until you choose another order.
//
//  A shuffled feed gets a fresh order:
//    • when you ask for one: ⋯ › Shuffle again, choosing Shuffled after a date
//      order, or pulling the grid down (pulling never touches a date order);
//    • on every visit to a board's page or to the Hidden section: each visit is a
//      feed of its own, so it keeps its order while you open pins from it, and
//      another page of the same board never changes it;
//    • when you come back to the Pins tab (from another tab, or the app from the
//      background) — but only if its grid is what you come back to and you were at
//      its top. Scrolled down, or with a pin open on top of it, it stays as it was;
//    • when a board page starts (or stops) including its sub-boards' pins.
//
//  The Pins tab's grid tells this module whether it is on screen and at its top
//  (FeedTopMarker; a grid that is leaving the screen can misreport where it is, so
//  only reports made while it is on screen count; each grid reports under its own
//  id, so a grid made anew never counts as gone when the old one leaves after it);
//  the Pins tab tells it whether something else shows in the grid's place (a pin
//  open on top, or Unsorted); AppRouter tells it when you come back to the tab,
//  before anything is redrawn.
//

import SwiftUI
import Foundation

/// A list of pins whose order the person controls.
enum Feed: Hashable, Sendable {
    case pins                         // the Pins tab's All
    case hiddenAll(visit: UUID)       // Hidden › All, during one opening of the Hidden section
    case board(UUID, visit: UUID)     // one visit to a board's page (every board shares one order setting)

    /// The Pins tab stays alive while other tabs show, so you can come back to it: FeedOrder
    /// follows whether its grid is on screen and at its top. Every other feed is one visit
    /// to a screen, which starts in an order of its own anyway.
    var canComeBack: Bool { self == .pins }
}

@MainActor
final class FeedOrder: ObservableObject {
    static let shared = FeedOrder()

    /// Scrolled less than this far below the top still counts as "at the top".
    static let topTolerance: CGFloat = 60

    /// Which order setting a feed uses (all boards share one).
    private enum Setting: String, CaseIterable {
        case pins = "pinSort", hiddenAll = "hiddenPinSort", boards = "boardPinSort"
    }

    /// The chosen orders, remembered between launches (the keys are the ones the app always used).
    @Published private var modes: [Setting: PinSortMode] = [:]
    /// Goes up whenever a feed's shuffle changes, so the grids showing it redraw.
    @Published private(set) var version = 0
    /// Seeds made by a reshuffle. Feeds without one use `launchSeed` mixed with the feed
    /// (and its visit), so every launch and every visit starts with a new order.
    private var seeds: [Feed: UInt64] = [:]
    private var launchSeed: UInt64
    /// Feeds you can come back to (`canComeBack`): the grids of each that are on screen right now
    /// (by each grid's own id — when a screen is made anew, after a profile switch, the new grid
    /// can say it came before the old one says it left), the feeds scrolled away from their top,
    /// and those with something else showing in their place.
    private var gridsOnScreen: [Feed: Set<UUID>] = [:]
    private var scrolledDown: Set<Feed> = []
    private var covered: Set<Feed> = []
    /// The profile in use's own preferences (each profile has its own orders: ProfileSettings.swift).
    private var defaults = ProfileSettings.defaults(for: AppSettings.shared.profileID)

    private init() {
        launchSeed = FeedOrder.clockSeed()
        readModes()
    }

    private func readModes() {
        for setting in Setting.allCases {
            modes[setting] = PinSortMode(rawValue: defaults.string(forKey: setting.rawValue) ?? "") ?? .shuffled
        }
    }

    /// Another profile: its own order settings, and every feed starts over in a new order.
    func useProfile(_ profile: UUID) {
        defaults = ProfileSettings.defaults(for: profile)
        readModes()
        startOver()
    }

    // MARK: Reading

    /// The pins in the feed's order.
    func arrange(_ pins: [Pin], in feed: Feed) -> [Pin] {
        FeedOrder.arranged(pins, mode: mode(of: feed), seed: seed(of: feed))
    }

    /// The feed's order setting.
    func mode(of feed: Feed) -> PinSortMode {
        modes[FeedOrder.setting(for: feed)] ?? .shuffled
    }

    // MARK: Your choices (the ⋯ menu, pulling the grid down)

    /// ⋯ › the order menu: Shuffled, Newest first or Oldest first (remembered). Choosing
    /// Shuffled after a date order gives a fresh shuffle; choosing the order the feed already
    /// has changes nothing.
    func setOrder(_ mode: PinSortMode, for feed: Feed) {
        let current = self.mode(of: feed)
        guard mode != current else { return }
        setMode(mode, for: feed)
        if mode == .shuffled { newSeed(for: feed) }
    }

    /// A fresh shuffle: ⋯ › Shuffle again, and pulling the grid down. Only a shuffled feed
    /// changes; a feed sorted by date keeps its order (and its setting).
    func shuffleAgain(_ feed: Feed) {
        reshuffleIfShuffled(feed)
    }

    // MARK: Moments that may bring a fresh shuffle

    /// You chose the feed's tab again (AppRouter says so before anything is redrawn): a fresh
    /// order only if its grid is what you come back to — no pin open on top of it — and you
    /// were at its top.
    func cameBackToTab(_ feed: Feed) {
        guard !covered.contains(feed), !scrolledDown.contains(feed) else { return }
        reshuffleIfShuffled(feed)
    }

    /// The app is back from the background with nothing shown over the tabs: a fresh order
    /// only if the feed's grid is on screen, with no page open on top of it, and at its top.
    func cameBackFromBackground(_ feed: Feed) {
        guard isOnScreen(feed), !covered.contains(feed), !scrolledDown.contains(feed) else { return }
        reshuffleIfShuffled(feed)
    }

    /// The feed's pins changed wholesale (a board page began or stopped including its
    /// sub-boards' pins): a fresh order, so they come out mixed.
    func contentsChanged(_ feed: Feed) {
        reshuffleIfShuffled(feed)
    }

    /// Another profile's library: every feed gets a new order. What the grids last reported
    /// is kept: ContentView makes every tab anew for the new library, and the new grids and
    /// the Pins tab report for themselves as they appear.
    func startOver() {
        seeds = [:]
        launchSeed = FeedOrder.freshSeed(after: launchSeed, now: FeedOrder.clockSeed())
        version += 1
    }

    // MARK: What the grid reports (FeedTopMarker does this for every grid)

    /// Something else shows where the feed's grid was — a page open on top of it (a pin, a
    /// board), or another list in its place (the Pins tab's Unsorted) — (true), or no longer
    /// (false). The Pins tab reports this.
    func setCovered(_ feed: Feed, _ isCovered: Bool) {
        guard feed.canComeBack else { return }
        if isCovered { covered.insert(feed) } else { covered.remove(feed) }
    }

    /// A grid of the feed came on screen (true) or left it (false). `grid`: which grid says so
    /// (each FeedTopMarker has an id of its own). The feed counts as on screen while any of its
    /// grids is.
    func setOnScreen(_ feed: Feed, _ shown: Bool, grid: UUID) {
        guard feed.canComeBack else { return }
        var grids = gridsOnScreen[feed] ?? []
        if shown { grids.insert(grid) } else { grids.remove(grid) }
        gridsOnScreen[feed] = grids
    }

    /// Whether the feed's grid is scrolled away from its top. Ignored while the grid is off
    /// screen: a grid that is leaving the screen can misreport where it is.
    func setScrolledDown(_ feed: Feed, _ down: Bool) {
        guard feed.canComeBack, isOnScreen(feed) else { return }   // off screen: keep what it last said
        if down { scrolledDown.insert(feed) } else { scrolledDown.remove(feed) }
    }

    // MARK: Inside

    /// Some grid of the feed is on screen.
    private func isOnScreen(_ feed: Feed) -> Bool {
        !(gridsOnScreen[feed] ?? []).isEmpty
    }

    private func setMode(_ mode: PinSortMode, for feed: Feed) {
        let setting = FeedOrder.setting(for: feed)
        guard modes[setting] != mode else { return }
        modes[setting] = mode
        defaults.set(mode.rawValue, forKey: setting.rawValue)
    }

    private func reshuffleIfShuffled(_ feed: Feed) {
        if mode(of: feed) == .shuffled { newSeed(for: feed) }
    }

    private func newSeed(for feed: Feed) {
        seeds[feed] = FeedOrder.freshSeed(after: seed(of: feed), now: FeedOrder.clockSeed())
        version += 1
    }

    private func seed(of feed: Feed) -> UInt64 {
        seeds[feed] ?? FeedOrder.mix(launchSeed, feed)
    }

    // MARK: Plain rules (no state; the harness tests these)

    private static func setting(for feed: Feed) -> Setting {
        switch feed {
        case .pins: return .pins
        case .hiddenAll: return .hiddenAll
        case .board: return .boards
        }
    }

    /// The pins in `mode`'s order. Shuffled: each pin gets a random key from the seed and
    /// its own id, so adding or removing a pin never moves the others. Ties (same date,
    /// same key) are broken by id, so the order never flickers.
    nonisolated static func arranged(_ pins: [Pin], mode: PinSortMode, seed: UInt64) -> [Pin] {
        switch mode {
        case .newestFirst:
            return pins.sorted { (a: Pin, b: Pin) -> Bool in
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
                return a.id.uuidString < b.id.uuidString
            }
        case .oldestFirst:
            return pins.sorted { (a: Pin, b: Pin) -> Bool in
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id.uuidString < b.id.uuidString
            }
        case .shuffled:
            var keyed: [(key: UInt64, pin: Pin)] = []
            keyed.reserveCapacity(pins.count)
            for pin in pins {
                keyed.append((key: shuffleKey(pin.id, seed: seed), pin: pin))
            }
            keyed.sort { (a: (key: UInt64, pin: Pin), b: (key: UInt64, pin: Pin)) -> Bool in
                if a.key != b.key { return a.key < b.key }
                return a.pin.id.uuidString < b.pin.id.uuidString
            }
            return keyed.map { (entry: (key: UInt64, pin: Pin)) -> Pin in entry.pin }
        }
    }

    /// A pin's place in a shuffle: the same seed and pin always give the same key.
    nonisolated static func shuffleKey(_ id: UUID, seed: UInt64) -> UInt64 {
        var raw: UInt64 = 0
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes.prefix(8) { raw = (raw << 8) | UInt64(byte) }
        }
        var generator = SeededGenerator(seed: seed &+ raw)
        return generator.next()
    }

    /// A new seed that always differs from the previous one.
    nonisolated static func freshSeed(after previous: UInt64, now: UInt64) -> UInt64 {
        now == previous ? now &+ 1 : now
    }

    /// Each feed's own starting seed for this launch: the Pins tab, every visit to Hidden
    /// and every visit to a board start in orders of their own.
    nonisolated static func mix(_ seed: UInt64, _ feed: Feed) -> UInt64 {
        switch feed {
        case .pins:
            return seed
        case .hiddenAll(let visit):
            return seed ^ shuffleKey(visit, seed: 7919)
        case .board(let id, let visit):
            let board: UInt64 = shuffleKey(id, seed: 104_729)
            return seed ^ board ^ shuffleKey(visit, seed: 1)
        }
    }

    private static func clockSeed() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Pieces the screens use

/// The ⋯ menu items for a feed's order, as Apple's sort menus do it (see BoardSortMenu): the
/// three orders with a checkmark on the chosen one, then "Shuffle again" while shuffled.
struct FeedOrderMenuItems: View {
    let feed: Feed
    /// Runs before any change (Hidden: switch to its All segment first).
    var onChoose: () -> Void = {}
    @ObservedObject private var order = FeedOrder.shared

    var body: some View {
        Picker("Order of pins", selection: chosenOrder) {
            Label("Shuffled", systemImage: "shuffle").tag(PinSortMode.shuffled)
            Label("Newest first", systemImage: "arrow.down").tag(PinSortMode.newestFirst)
            Label("Oldest first", systemImage: "arrow.up").tag(PinSortMode.oldestFirst)
        }
        if order.mode(of: feed) == .shuffled {
            Button {
                onChoose()
                order.shuffleAgain(feed)
            } label: {
                Label("Shuffle again", systemImage: "arrow.clockwise")
            }
        }
    }

    /// The picker's choice: it shows the feed's order, and choosing one sets it.
    private var chosenOrder: Binding<PinSortMode> {
        Binding(get: { order.mode(of: feed) },
                set: { mode in
                    onChoose()
                    order.setOrder(mode, for: feed)
                })
    }
}

/// Placed at the very top of a grid's scrolling content. For a feed it tells FeedOrder
/// whether the grid is on screen and at its top (FeedOrder keeps this only for a feed you
/// can come back to, see `Feed.canComeBack`). Without a feed it is just an empty line
/// (so every grid lays out the same).
struct FeedTopMarker: View {
    let feed: Feed?
    /// The top of the scroll view, in global coordinates.
    let scrollTop: CGFloat
    /// This grid's own id, for its reports (see `FeedOrder.setOnScreen`).
    @State private var grid = UUID()

    /// The feed, when FeedOrder follows it (board pages and Hidden need nothing reported).
    private var followed: Feed? {
        guard let feed, feed.canComeBack else { return nil }
        return feed
    }

    var body: some View {
        let feed = followed
        Color.clear
            .frame(height: 0)
            .background {
                if let feed {
                    GeometryReader { marker in
                        let down = scrollTop - marker.frame(in: .global).minY > FeedOrder.topTolerance
                        Color.clear.task(id: down) {
                            guard !Task.isCancelled else { return }   // the grid is going away
                            FeedOrder.shared.setScrolledDown(feed, down)
                        }
                    }
                }
            }
            .onAppear {
                if let feed { FeedOrder.shared.setOnScreen(feed, true, grid: grid) }
            }
            .onDisappear {
                if let feed { FeedOrder.shared.setOnScreen(feed, false, grid: grid) }
            }
            .onChange(of: followed) { old, new in
                // The grid shows another list now (the Pins tab's Unsorted has no feed).
                if let old { FeedOrder.shared.setOnScreen(old, false, grid: grid) }
                if let new { FeedOrder.shared.setOnScreen(new, true, grid: grid) }
            }
    }
}

extension View {
    /// Pulling the grid down shuffles a shuffled feed again; a feed sorted by date keeps its
    /// order (grids without a feed: no shuffle). It also starts an iCloud sync when this profile
    /// syncs (`CloudSync.syncFromPull`), just after the spinner has gone; the spinner doesn't wait
    /// for it. Always applied, so a grid switching between feeds never rebuilds its scroll view.
    func feedRefreshable(_ feed: Feed?) -> some View {
        refreshable {
            if let feed {
                await MainActor.run { FeedOrder.shared.shuffleAgain(feed) }
                try? await Task.sleep(nanoseconds: 350_000_000)   // lets the spinner be seen
            }
            // The sync starts only once the spinner has gone. Its "Syncing…" pill sits above the
            // grid, in the scrolling page: a pill coming or going while the spinner is still
            // sliding away could leave the spinner's space as an empty gap at the top (iPhone).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                let services = AppServices.shared
                services.cloudSync.syncFromPull(store: services.store, settings: AppSettings.shared)
            }
        }
    }
}
