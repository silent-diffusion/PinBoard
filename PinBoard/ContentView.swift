//
//  ContentView.swift  —  PinBoard
//
//  The root of the app (the one shared library, each window's tabs) and the Pins tab. The
//  Search tab is SearchView.swift; the small UI pieces every screen shares are SharedControls.swift.
//
//  FILES IN THIS PROJECT (all 58 must be present; MyApp.swift comes with the template and is never
//  changed). Files are kept to about 1,200 lines so each one pastes safely.
//
//  The library (the store, split by topic — all one class, `LibraryStore`):
//    LibraryStore.swift      – the core: state, loading and saving, lookups, the hidden and kept-out rules
//    LibraryTypes.swift      – the small types that go with it (imports, locations, backups, membership rules)
//    LibraryPins.swift       – changing pins: edits, tags, board membership, hiding
//    LibraryBoards.swift     – boards, their order and favorites, smart boards, board suggestions
//    LibraryImports.swift    – bringing things in: reading what was picked, committing imports, link pins
//    LibraryUpkeep.swift     – Recently deleted, orphan sweep, duplicates, video upkeep, pictures and prints
//    LibraryAnalysis.swift   – the AI queue, "AI sorting → naming", natural-language search
//    MediaStorage.swift      – the store's side of storage: conversions after imports, originals, size
//    VideoCompression.swift  – the rules and the converter that make videos smaller
//    OriginalsFolder.swift   – the Files folder for full-size originals, the library size, storage words
//    VideoPosters.swift      – choosing a video's thumbnail; VideoTranscripts.swift – what is said in a video
//    Models.swift            – data types shared by the whole app; Profiles.swift – profiles + iCloud sync
//    Export.swift            – export / import, Save to Photos, drag-out; FeedOrder.swift – feed order
//
//  Screens:
//    ContentView.swift       – this file: root, tabs, the Pins tab
//    SearchView.swift        – the Search tab; SharedControls.swift – text fields, chips
//    PinGrid.swift           – the masonry grid, the pin collection, the pin card
//    PinDetailView.swift     – a pin's page (state and layout); PinPageContent.swift – what it shows;
//                              PinPageLayout.swift – its one-/two-column rule; DuplicatePairs.swift
//    QuickLook.swift         – Quick Look (full-screen feed); QuickLookPage.swift – its pages and info panel
//    BoardViews.swift        – the Boards tab and board tiles; BoardPage.swift – one board's page, pickers
//    BoardCommands.swift     – the board command table, its menus, AI sorting; HiddenSection.swift – Hidden
//    SmartBoards.swift       – smart boards (saved searches)
//    PinActions.swift        – what the pin menus offer and how they are drawn
//    PinActionsPresenter.swift – carrying those actions out; SourceLinks.swift – the address sheet, hand-offs
//    CropEditor.swift        – cropping a picture; Palette.swift – "Generate colors"
//    ImportFlow.swift        – adding pins: the import questions, the "+" menu, confirmations
//    DragAndDrop.swift       – drop zones and what a dragged pin card carries
//    MediaPager.swift        – the pager shared by the pin page and Quick Look
//    TextAndVideo.swift      – text pins, video previews in the grid, camera, share sheet
//    VideoPlayer.swift       – PinBoard's own video player; VideoControls.swift – its buttons, speeds, taps
//    AppSettings.swift       – preferences and key storage; SettingsView.swift – the Settings list;
//                              SettingsPages.swift – its pages; SettingsTools.swift – Storage rows, Profiles,
//                              tag manager, Recovery, Recently Deleted, Duplicates
//    WebImages.swift         – Explore tab, web image sources; WebBrowser.swift – reverse image search, browser
//    ShareShared.swift       – what the share sheet and the app share; ShareInbox.swift – taking in what was
//                              shared from other apps (the share sheet itself exists only in the TestFlight build)
//
//  Links and AI:
//    LinkPins.swift          – link pins and their previews; LinkPictures.swift – a picture for every link
//    SmartLinks.swift        – reading links fully; SmartLinksParsers.swift, SmartLinksReaders.swift,
//                              SmartLinksReaders2.swift – the readers; SmartLinksViews.swift – their screens
//    ArticleHighlights.swift – highlights in the article reader
//    OnDeviceAI.swift        – Vision, colours, NaturalLanguage, Apple Intelligence; CloudAI.swift – optional cloud model
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - Theme

enum PinTheme {
    static let cardRadius: CGFloat = 16
    static let gridSpacing: CGFloat = 12
}

/// The accent color chosen in Settings, available to every view.
private struct PinAccentKey: EnvironmentKey {
    static let defaultValue: Color = AccentTheme.red.color
}

extension EnvironmentValues {
    var pinAccent: Color {
        get { self[PinAccentKey.self] }
        set { self[PinAccentKey.self] = newValue }
    }
}

/// The app's tabs.
enum AppTab: Hashable, CaseIterable {
    case pins, boards, explore, search

    /// The tabs in tab-bar order. The tab bar and the swipe between tabs are both built from
    /// this one list, so the order lives in one place. Every tab is always there: a tab bar
    /// only navigates, so a tab is never hidden or disabled (in Offline mode, Explore stays
    /// and says why it shows nothing).
    static let inBarOrder: [AppTab] = [.pins, .boards, .explore, .search]

    /// The tab's name in the tab bar.
    var title: String {
        switch self {
        case .pins: return "Pins"
        case .boards: return "Boards"
        case .explore: return "Explore"
        case .search: return "Search"
        }
    }

    /// The tab's symbol in the tab bar.
    var symbol: String {
        switch self {
        case .pins: return "square.grid.2x2"
        case .boards: return "folder"
        case .explore: return "globe"
        case .search: return "magnifyingglass"
        }
    }

    /// Where a sideways swipe on this tab's root screen leads: the next tab in the bar
    /// (`forward`, a swipe from right to left) or the previous one. Nil at either end:
    /// the swipe never wraps around.
    func neighbor(forward: Bool) -> AppTab? {
        let order = AppTab.inBarOrder
        guard let index = order.firstIndex(of: self) else { return nil }
        let next = forward ? index + 1 : index - 1
        return order.indices.contains(next) ? order[next] : nil
    }
}

/// Things any screen may ask its window's root to do: open Settings (a sheet), start an
/// export there, or switch to another tab (the swipe between tabs does that). Every
/// window has its own (see `ContentView`).
@MainActor
final class AppRouter: ObservableObject {
    @Published var showSettings = false
    @Published var pendingExport = false
    /// A page some screen asked to open (Quick Look's "Show info" opens the pin's page): the
    /// selected tab's root pushes it and clears this. Set through `open(_:)`.
    @Published var pendingRoute: Route? = nil

    /// Opens a page in the selected tab (after whatever is presenting has closed).
    func open(_ route: Route) {
        pendingRoute = route
    }
    @Published var selectedTab: AppTab = .pins {
        didSet {
            // Back on the Pins tab: told before anything is redrawn, so a fresh order (if you
            // were at the top of the grid) is there from the first frame.
            if selectedTab == .pins, oldValue != .pins { FeedOrder.shared.cameBackToTab(.pins) }
        }
    }
}

/// The library and what works directly on its files, created once for the whole app.
///
/// Why only once: on an iPad, PinBoard can be open in two windows side by side, and each
/// window builds its own ContentView. If every window made its own LibraryStore, two stores
/// would read and write the same files, and whichever saved last would quietly wipe out what
/// was changed in the other window. So all windows share these. A window only has its own
/// tabs, sheets and confirmations (the `AppRouter` and `ImportFlow` in `ContentView`).
@MainActor
final class AppServices {
    static let shared = AppServices()

    let profiles: ProfileManager
    let store: LibraryStore
    let cloudSync = CloudSync()

    private init() {
        let manager = ProfileManager()
        profiles = manager
        store = LibraryStore(location: manager.currentLocation, profileID: manager.currentID)
    }
}

// MARK: - Root view

/// The root of one window. The library comes from `AppServices.shared` (the same in every
/// window); the router (which tab shows, Settings) and the import flow (its questions and
/// confirmations) belong to this window alone.
struct ContentView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var importFlow = ImportFlow(store: AppServices.shared.store)
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        let shared = AppServices.shared
        RootTabsView()
            .environmentObject(shared.store)
            .environmentObject(settings)
            .environmentObject(shared.profiles)
            .environmentObject(shared.cloudSync)
            .environmentObject(importFlow)
            .environmentObject(router)
    }
}

/// One window's tabs, its Settings sheet, and the reactions to the app coming and going
/// (and to iCloud being switched on, and to another profile being chosen).
struct RootTabsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var cloudSync: CloudSync
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false
    /// The Boards tab's path, kept here so going to the background can close the
    /// Hidden section whichever tab is showing.
    @StateObject private var boardsNav = BoardsNavigation()
    /// The profile whose library the Boards tab's path belongs to (see `libraryChanged`).
    @State private var boardsPathProfile: UUID? = nil

    var body: some View {
        TabView(selection: $router.selectedTab) {
            // Built from one list, so the tab bar and the swipe between tabs share one order.
            ForEach(AppTab.inBarOrder, id: \.self) { tab in
                tabRoot(tab)
                    // Another profile is another library: the tab starts over at its root screen
                    // (the pages it had open belonged to the old library). Only what is inside the
                    // TabView is made anew, so the Settings sheet (on the TabView) stays up.
                    .id(profiles.currentID)
                    // Short confirmations float just above whatever ends this tab at the bottom:
                    // the tab bar, the home indicator or the keyboard (see `confirmationToast()`).
                    .confirmationToast()
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        // With the Hidden section open and on screen, the tabs are covered while the app is not in
        // front. Only while the Boards tab shows: on another tab nothing hidden is on screen, so
        // pulling down Control Center there doesn't make the screen blink.
        .hiddenPrivacyCover(boardsNav.hiddenOpenedAt != nil && router.selectedTab == .boards)
        .environment(\.pinAccent, settings.accentColor)
        .tint(settings.accentColor)
        .preferredColorScheme(settings.appearance.colorScheme)
        .importFlowRoot()   // Quick Look and Settings show import questions themselves
        .sheet(isPresented: $router.showSettings) {
            settingsSheet
        }
        .onChange(of: scenePhase) { _, phase in
            sceneChanged(to: phase)
        }
        .onOpenURL { openFromWidget($0) }
        .onAppear {
            if boardsPathProfile == nil { boardsPathProfile = profiles.currentID }
        }
        .onChange(of: profiles.currentID) {
            libraryChanged()
        }
        .onChange(of: profiles.profiles) {
            ShareBoardListWriter.write(store: store, profiles: profiles)   // the share sheet's profile names
        }
        .onChange(of: settings.chooseBoardWhenSharing) {
            ShareBoardListWriter.write(store: store, profiles: profiles)   // the share sheet follows it
        }
        .onChange(of: settings.boardSort) {
            ShareBoardListWriter.write(store: store, profiles: profiles)   // the share sheet lists boards in the same order
        }
        .onChange(of: settings.iCloudSync) { _, on in
            if on { cloudSync.syncSoon(store: store, settings: settings, delay: 1) }
            SettingsSync.shared.follow(settings, iCloudAvailable: cloudSync.isAvailable)   // settings travel with the library (SettingsSync.swift)
        }
        // Offline mode off again (Settings, or Explore's button): videos whose transcript waited for the
        // speech recogniser's language files can be listened to now (VideoTranscripts.swift).
        .onChange(of: settings.offlineMode) { _, offline in
            if !offline { store.startTranscribingIfNeeded(delay: 2) }
            SettingsSync.shared.follow(settings, iCloudAvailable: cloudSync.isAvailable)   // Offline mode stops settings from travelling too
        }
        .task {
            // Every save also nudges iCloud (when it is on and available).
            let sync = cloudSync
            store.onSaved = { [weak store, weak sync] in
                guard let store, let sync else { return }
                sync.librarySaved(store: store, settings: AppSettings.shared)   // (not for a save of what a sync brought)
                WidgetSnapshotWriter.shared.refreshSoon(store: store)   // the widgets' pictures and quotes
                ShareBoardListWriter.writeSoon(store: store, profiles: AppServices.shared.profiles)   // the share sheet's boards
            }
            WidgetSnapshotWriter.shared.refreshSoon(store: store, delay: 5)
            ShareBoardListWriter.write(store: store, profiles: profiles)
            ShareInbox.shared.listen()   // the share sheet says when it saved something (ShareInbox.swift)
            ShareInbox.shared.takeIn(flow: importFlow)   // what was shared while PinBoard was closed
            await cloudSync.checkAvailability()
            SettingsSync.shared.follow(settings, iCloudAvailable: cloudSync.isAvailable)
            cloudSync.syncSoon(store: store, settings: settings, delay: 3)
        }
    }

    /// The screen at the root of a tab (each has its own NavigationStack inside).
    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .pins: HomeView()
        case .boards:
            if boardsPathIsCurrent {
                BoardsView().environmentObject(boardsNav)
            } else {
                // Just after another profile was chosen, for one moment (behind Settings): the path
                // still holds the old library's pages until `libraryChanged` empties it, and a Boards
                // tab made then would open those pages (a locked Hidden section would even ask for
                // Face ID). So the tab waits, empty, and is made on the emptied path.
                Color(uiColor: .systemBackground)
            }
        case .explore: ExploreView()
        case .search: SearchView()
        }
    }

    /// The Boards tab's path belongs to the library on show. (At launch, before the first
    /// `onAppear` notes the profile, it does.)
    private var boardsPathIsCurrent: Bool {
        guard let owner = boardsPathProfile else { return true }
        return owner == profiles.currentID
    }

    /// Settings, as a sheet over the tabs, with everything it reads handed on to it. The screen
    /// underneath never hears that it went out of sight (a sheet is not a new page), so, like a
    /// pin page or Quick Look, Settings silences the grid card that had sound when it comes up.
    /// (A pin page's own video waits by itself while Settings is open: see PinDetailView.)
    private var settingsSheet: some View {
        SettingsView()
            .modifier(SoundScreenPresence())
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(profiles)
            .environmentObject(cloudSync)
            .environmentObject(importFlow)
            .environmentObject(router)
            .environment(\.pinAccent, settings.accentColor)
            .tint(settings.accentColor)
            .preferredColorScheme(settings.appearance.colorScheme)
    }

    /// The app came to the front, stepped out of it ("inactive": the App Switcher, Control
    /// Center, a system question) or went to the background. (While it is not in front, an open
    /// Hidden section is covered: see `hiddenPrivacyCover`.)
    private func sceneChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            ShareBoardListWriter.write(store: store, profiles: profiles)   // (a profile renamed meanwhile)
            ShareInbox.shared.takeIn(flow: importFlow)   // what was shared from other apps meanwhile
            // Only a real return from the background reshuffles (not Control Center or a
            // notification, which only pass through "inactive").
            if wasInBackground {
                wasInBackground = false
                // A fresh order only if the Pins tab's grid is on screen and at its top, with
                // nothing (Quick Look, Settings, a sheet) shown over it.
                if !RootTabsView.somethingIsPresented() { FeedOrder.shared.cameBackFromBackground(.pins) }
                if cloudSync.isSyncing { SyncLog.add("App back in front (the sync goes on)") }
                cloudSync.syncSoon(store: store, settings: settings, delay: 2)
            }
        case .inactive:
            store.saveIfPending()   // the App Switcher may close the app before "background" comes
        case .background:
            wasInBackground = true
            if cloudSync.isSyncing { SyncLog.add("App left the screen during a sync") }
            importFlow.dropHiddenQuestions()   // Hidden locks: its import questions don't wait for your return
            importFlow.clearToast()            // nor does a confirmation
            store.saveNowSynchronously()
            // Hidden things never stay on screen while the app is away: the Boards tab goes
            // back to where the Hidden section was opened from (also when another tab shows).
            boardsNav.closeHidden()
            HiddenAccess.shared.lock()   // hidden boards ask again after the app was away
        default:
            break
        }
    }

    /// Another profile was chosen (Settings › Library › Profiles): another library. Every tab has been made
    /// anew at its root by then (its `.id` is the profile), so no page of the old library stays
    /// open ("This pin was deleted"). Only the Boards tab's path lives here, outside the tabs: it
    /// is emptied now, and then the Boards tab is made on it (see `tabRoot`).
    private func libraryChanged() {
        boardsNav.path = NavigationPath()
        boardsPathProfile = profiles.currentID
        WidgetSnapshotWriter.shared.refreshSoon(store: store, delay: 3)   // the widgets show the library in use
        ShareBoardListWriter.write(store: store, profiles: profiles)       // so does the share sheet
        ShareInbox.shared.takeIn(flow: importFlow)                         // shares made for this profile
        cloudSync.syncSoon(store: store, settings: settings, delay: 3)    // only if this profile syncs (its own setting)
    }

    /// A widget was tapped ("pinboard://pin/<id>"): that pin's page opens on the Pins tab. A pin
    /// that is gone (or hidden: the widgets never show one) opens nothing.
    private func openFromWidget(_ url: URL) {
        guard let id = WidgetShared.pinID(from: url), let pin = store.livePin(id), !store.isHidden(pin) else { return }
        router.showSettings = false
        router.selectedTab = .pins
        router.open(.pin(id, .none))
    }
}

// MARK: - Hidden pins and the App Switcher

extension View {
    /// While `showsHidden` (this screen shows hidden pins or boards), the screen is covered
    /// by `HiddenPrivacyCover` as soon as the app is not in front, until it is in front again.
    /// Why: the App Switcher shows a picture of the screen taken as the app leaves, and Hidden
    /// only locks and closes once the app has reached the background — too late for that
    /// picture. Used by the tabs (the Hidden section open), Quick Look and the sheets that
    /// show hidden pins.
    func hiddenPrivacyCover(_ showsHidden: Bool) -> some View {
        modifier(HiddenPrivacyGuard(showsHidden: showsHidden))
    }

    /// A sheet that deserves the room: on iPad it opens as a page-sized sheet instead of the
    /// small form sheet (iOS 18 and later; older systems keep the form sheet). For the sheets that
    /// show a whole picture, video or article.
    func largeSheetSizing() -> some View {
        modifier(LargeSheetSizing())
    }
}

/// See `largeSheetSizing()`. The `if #available` stays: `presentationSizing` is iOS 18 only.
private struct LargeSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

@MainActor
private struct HiddenPrivacyGuard: ViewModifier {
    let showsHidden: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var covered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if covered { HiddenPrivacyCover() }
            }
            .onChange(of: scenePhase) { _, phase in
                // Covered the moment the app steps out of the front ("inactive": the App Switcher,
                // Control Center, a system question), and kept on its way to the background — also
                // once Hidden has closed there — until the app is in front again.
                if phase == .active {
                    covered = false
                } else if showsHidden, !HiddenPrivacyGuard.isFaceIDPrompt(phase) {
                    covered = true
                }
            }
    }

    /// Hidden's own Face ID / passcode prompt makes the app "inactive" too. Only the lock screen
    /// is behind it (nothing is unlocked yet), so the screen stays as it is while the prompt is
    /// up instead of turning into the cover. Going to the background still covers.
    private static func isFaceIDPrompt(_ phase: ScenePhase) -> Bool {
        phase == .inactive && HiddenAccess.shared.isAsking
    }
}

/// What covers hidden things while the app is not in front: the plain background with the lock
/// (Hidden's own symbol). Opaque: nothing of the screen shows through, and nothing is blurred.
struct HiddenPrivacyCover: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hidden pins are covered")
    }
}

// MARK: - Swiping between tabs

extension View {
    /// Horizontal swipes on this tab's root screen switch tabs (Settings › "Swipe between
    /// tabs"). Apply INSIDE the tab's NavigationStack, to the root screen's content only, so
    /// screens pushed on top (a board, a pin) keep their normal swipe back.
    func tabSwipeRoot(_ tab: AppTab, enabled: Bool = true) -> some View {
        modifier(TabSwipeRoot(tab: tab, enabled: enabled))
    }

    /// A sideways-scrolling area on a tab root (a row of chips, a segmented control):
    /// drags that touch it never switch tabs.
    func tabSwipeExempt() -> some View {
        modifier(TabSwipeExempt())
    }
}

/// Remembers when an exempt area was last dragged, so the tab swipe that ends a
/// moment later knows the drag belonged to that area.
@MainActor
final class TabSwipeGate {
    static let shared = TabSwipeGate()
    private(set) var lastExemptDrag = Date.distantPast

    func exemptDragged() {
        lastExemptDrag = Date()
    }
}

/// The tab swipe itself: a quick, clearly sideways drag moves to the next tab
/// (right to left) or the previous one (left to right), in tab-bar order, without
/// wrapping around. It runs alongside everything else on the screen, so vertical
/// scrolling, taps and long presses work as before.
@MainActor
private struct TabSwipeRoot: ViewModifier {
    let tab: AppTab
    let enabled: Bool
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    @State private var dragStart: Date? = nil

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onChanged { _ in
                    if dragStart == nil { dragStart = Date() }
                }
                .onEnded { value in
                    let start = dragStart ?? Date()
                    dragStart = nil
                    finishSwipe(value, startedAt: start)
                }
        )
    }

    private func finishSwipe(_ value: DragGesture.Value, startedAt start: Date) {
        guard settings.swipeBetweenTabs, enabled, router.selectedTab == tab else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        // Clearly sideways and long enough…
        guard abs(dx) >= 80, abs(dx) > 2.2 * abs(dy) else { return }
        // …and quick (a slow drag is probably something else), or flicked hard.
        let quick = Date().timeIntervalSince(start) < 0.6 || abs(value.predictedEndTranslation.width) >= 220
        guard quick else { return }
        // A drag that touched a chip row or another exempt area belongs to that area.
        guard TabSwipeGate.shared.lastExemptDrag < start.addingTimeInterval(-0.5) else { return }
        // Right to left moves on to the next tab, left to right back to the one before
        // (in tab-bar order, see `AppTab.inBarOrder`).
        guard let next = tab.neighbor(forward: dx < 0) else { return }
        router.selectedTab = next
    }
}

/// Records every drag on an exempt area (see `tabSwipeExempt()`).
@MainActor
private struct TabSwipeExempt: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in TabSwipeGate.shared.exemptDragged() }
        )
    }
}

/// Turns a `Route` into the screen it points at.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .pin(let id, let context):
            PinDetailView(pinID: id, context: context)
        case .board(let id):
            BoardDetailView(boardID: id)
        case .smartBoard(let id):
            SmartBoardView(boardID: id)
        case .webImage(let image, let context, let boardIDs, let hidden):
            PinDetailView(webImage: image, context: context, boardIDs: boardIDs, hidden: hidden)
        case .hidden:
            HiddenSectionView()
        case .hiddenScreen(let screen):
            switch screen {
            case .duplicates: DuplicatesView(scope: .hidden).hiddenGate()
            case .recentlyDeleted: RecentlyDeletedView(scope: .hidden).hiddenGate()
            case .tags: TagManagerView(scope: .hidden).hiddenGate()
            }
        }
    }
}

// MARK: - Pins tab

extension RootTabsView {
    /// Whether anything — a sheet (Settings is one), a full-screen screen (Quick Look, the
    /// camera), an alert — is shown over the tabs right now.
    @MainActor
    static func somethingIsPresented() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.rootViewController?.presentedViewController != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - Toolbar symbols

/// The symbol of a toolbar's ⋯ menu. On iOS 26 every toolbar button already sits on its
/// own glass circle, so the plain ellipsis is the system look; before that the circled one is.
struct MoreMenuLabel: View {
    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: "ellipsis")
        } else {
            Image(systemName: "ellipsis.circle")
        }
    }
}

/// The symbol of a toolbar's "+" (add) button or menu, sized like the other toolbar items
/// on iOS 26 and filled-and-larger before that, as the app always drew it.
struct AddMenuLabel: View {
    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: "plus")
        } else {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
    }
}

enum HomeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unsorted = "Unsorted"
    case keptOut = "Kept out"   // pins kept out of All (from a pin's or a board's menu); shown only while there are some
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var router: AppRouter
    @StateObject private var addFlags = AddPinFlags()
    @State private var filter: HomeFilter = .all
    @State private var isSelecting = false
    @State private var aiPrompt: AIPrompt? = nil   // the "AI sorting" menu's questions
    /// The pages open on top of the grid (FeedOrder never reshuffles All under an open pin,
    /// nor while Unsorted shows in its place).
    @State private var path = NavigationPath()

    /// "All" is a feed: its order (shuffled, or by date added) is chosen in ⋯ and kept
    /// by FeedOrder. "Unsorted" stays newest-first so triage is predictable.
    private var visiblePins: [Pin] {
        switch filter {
        case .all: return store.allFeedPins
        case .unsorted: return store.unsortedPins
        case .keptOut: return store.keptOutPins
        }
    }

    /// The filters offered: "Kept out" only while something is kept out of All.
    private var filters: [HomeFilter] {
        store.keptOutPins.isEmpty ? [.all, .unsorted] : HomeFilter.allCases
    }

    /// The segment's words: "All (120)", "Unsorted (3)", "Kept out (5)".
    private func segmentTitle(_ choice: HomeFilter) -> String {
        switch choice {
        case .all: return "All (\(store.allFeedPins.count))"
        case .unsorted: return "Unsorted (\(store.unsortedPins.count))"
        case .keptOut: return "Kept out (\(store.keptOutPins.count))"
        }
    }

    /// What the empty grid says. With no pins at all, Unsorted says "No pins yet" too: "Every pin
    /// is on a board" would not be true of an empty library.
    private var emptyText: (title: String, message: String) {
        if filter == .keptOut {
            return ("Nothing kept out of All", "“Keep out of All” (in a pin's or a board's menu) takes pins off this tab's All feed without hiding them; they show here and stay on their boards.")
        }
        if filter == .all || store.visiblePins.isEmpty {
            return ("No pins yet", "Tap + to add photos, take one, or drag pictures, text and links in from another app. The on-device AI tags them automatically.")
        }
        return ("Nothing unsorted", "Every pin is on a board. Nice work!")
    }

    /// Something other than All's grid shows here: a page open on top of it, or Unsorted.
    private var gridCovered: Bool { path.count > 0 || filter != .all }

    var body: some View {
        let shown = visiblePins   // (the grid puts All in its feed order)
        let empty = emptyText
        NavigationStack(path: $path) {
            PinCollectionView(
                pins: shown,
                isSelecting: $isSelecting,
                emptyIcon: "photo.on.rectangle.angled",
                emptyTitle: empty.title,
                emptyMessage: empty.message,
                feed: filter == .all ? .pins : nil
            ) { _ in
                VStack(spacing: 10) {
                    StatusBanner()
                    if store.shouldNudgeBackup {
                        BackupNudgeBanner()
                    }
                    StartHereCard()
                    FittingSegmentedPicker(title: "Filter", selection: $filter,
                                           options: filters.map { (f: HomeFilter) in SegmentOption(value: f, label: segmentTitle(f)) })
                    .tabSwipeExempt()   // sliding along the segments never switches tabs
                    .onChange(of: store.keptOutPins.isEmpty) { _, none in
                        if none, filter == .keptOut { filter = .all }   // the last kept-out pin went back: the segment goes
                    }
                }
            }
            .tabSwipeRoot(.pins, enabled: !isSelecting)   // swipe sideways for the next tab (not while selecting)
            .modifier(PinDropZone(boardIDs: [], style: .page))   // drops land in Unsorted
            .modifier(AddPinPresenters(flags: addFlags, boardIDs: []))
            .modifier(AISortingDialogs(prompt: $aiPrompt))
            .navigationTitle("PinBoard")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    AddPinMenu(flags: addFlags)
                    Menu {
                        Button {
                            withAnimation { isSelecting.toggle() }
                        } label: {
                            Label(isSelecting ? "Done selecting" : "Select pins", systemImage: "checkmark.circle")
                        }
                        .disabled(shown.isEmpty && !isSelecting)
                        Divider()
                        // The order of All (choosing one shows All).
                        FeedOrderMenuItems(feed: .pins) { filter = .all }
                        Divider()
                        // Boards, tags and names for every pin (hidden pins have their own in Hidden's ⋯ menu).
                        AISortingMenu(target: .all(.visible), prompt: $aiPrompt)
                            .disabled(store.visiblePins.isEmpty)
                        Divider()
                        Button {
                            router.showSettings = true
                        } label: {
                            Label("Settings…", systemImage: "gearshape")
                        }
                    } label: {
                        MoreMenuLabel()
                    }
                    .accessibilityLabel("More")
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onChange(of: router.pendingRoute) { _, route in
            // A page another screen asked for (see AppRouter.open): this tab pushes it when selected.
            guard let route, router.selectedTab == .pins else { return }
            router.pendingRoute = nil
            path.append(route)
        }
        .onChange(of: gridCovered) { _, covered in
            // All's grid isn't what you see: a pin (or board) is open on top, or Unsorted shows.
            FeedOrder.shared.setCovered(.pins, covered)
        }
        .onAppear {
            // Said again whenever the tab appears. After a profile switch this tab is made anew
            // (on All, nothing open), and the old one's last report must not stay behind.
            FeedOrder.shared.setCovered(.pins, gridCovered)
        }
    }
}

/// "You've added 50 pins since your last export" — a gentle reminder to back up.
/// The buttons sit beside the words when there is room for both; with large text (or in a
/// narrow window) they move underneath, so the words never get squeezed into a thin column.
struct BackupNudgeBanner: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var router: AppRouter
    /// How wide the words want to be when the buttons sit beside them (grows with the text size).
    @ScaledMetric(relativeTo: .subheadline) private var wordsWidth: CGFloat = 170

    var body: some View {
        // ViewThatFits shows the first layout that fits the width, else the last one.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                symbol
                words
                    .frame(idealWidth: wordsWidth, maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) { buttons }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    symbol
                    words
                }
                HStack(spacing: 16) { buttons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // the banner stays full width
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var symbol: some View {
        Image(systemName: "externaldrive.badge.timemachine")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Time for a back-up?")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let count = store.pinsAddedSinceExport
        if store.lastExportAt == nil {
            return "\(count) pins added and never exported. An export is the only copy outside this device."
        }
        return "\(count) pins added since your last export."
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Export now") {
            router.pendingExport = true
            router.showSettings = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        Button("Later") { store.snoozeBackupNudge() }
            .font(.caption)
    }
}

/// Small progress pill shown while importing, syncing or while the AI is tagging or renaming.
/// (Short confirmations float over every screen instead — see ImportFlow's `flash`.)
struct StatusBanner: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.pinAccent) private var accent

    var body: some View {
        // Only the normal library's work is mentioned here (a hidden import or hidden tagging never is).
        // A line with a count ("Importing 3 of 40…") draws a bar; one without, a spinner.
        if let status = store.importStatus, store.importStatusScope == .visible {
            pill(text: status, progress: WorkProgress.fraction(of: status))
        } else if let sync = store.syncStatus {
            pill(text: sync, progress: WorkProgress.fraction(of: sync))
        } else if let progress = store.analysisProgress(for: .visible) {
            pill(text: "AI is tagging pins… \(progress.done + 1) of \(progress.total)",
                 progress: Double(progress.done) / Double(max(progress.total, 1)))
        } else if let naming = store.namingProgress, store.namingScope == .visible {
            // "AI sorting → naming" on the normal library (a run on hidden pins is never mentioned here).
            pill(text: "AI is renaming pins… \(min(naming.done + 1, max(naming.total, 1))) of \(naming.total)",
                 progress: Double(naming.done) / Double(max(naming.total, 1)))
        }
    }

    /// A line of text with a progress bar (a count is known) or a small spinner.
    private func pill(text: String, progress: Double?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.footnote.weight(.medium))
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(text)
    }
}
