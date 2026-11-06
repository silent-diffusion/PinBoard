//
//  BoardViews.swift  —  PinBoard
//
//  The Boards tab (boards and smart boards, selecting several boards, sorting,
//  favorites) and the board tiles it is made of: the grid of tiles with their
//  collages, and the pickers for a board's cover and for a video's thumbnail.
//  The colors of a board and the big-title surprise live in Palette.swift.
//
//  The other board screens have their own files: BoardCommands.swift (the one
//  table of board commands and the "AI sorting" menu), HiddenSection.swift (the
//  Hidden section) and BoardPage.swift (a single board's page, the board
//  picker and the batch tag editor).
//

import SwiftUI
import PhotosUI
import LocalAuthentication
import UIKit
import Foundation

// MARK: - Boards tab

enum BoardsSegment: String, CaseIterable, Identifiable {
    case boards, smart
    var id: String { rawValue }
}

/// The Boards tab's navigation stack. It belongs to the root (RootTabsView), so
/// the Hidden section can be closed when the app goes to the background even
/// while another tab is showing; screens inside the tab push with `push(_:)`.
@MainActor
final class BoardsNavigation: ObservableObject {
    @Published var path = NavigationPath() {
        didSet {
            // Backed out of the Hidden section (or further): it is no longer open.
            if let opened = hiddenOpenedAt, path.count <= opened { hiddenOpenedAt = nil }
        }
    }
    /// How deep the stack was when the Hidden section was opened (nil: it is not open).
    /// Everything pushed after it — Duplicates, Recently Deleted, Tags, hidden pins and
    /// boards — sits deeper, so it counts as inside Hidden too.
    private(set) var hiddenOpenedAt: Int? = nil

    /// Pushes a screen onto the Boards stack (the one path every screen there uses).
    func push(_ route: Route) {
        path.append(route)
    }

    func openHidden() {
        hiddenOpenedAt = path.count
        path.append(Route.hidden)
    }

    /// Hidden things never stay on screen while the app is away: back to where the
    /// Hidden section was opened from.
    func closeHidden() {
        guard let opened = hiddenOpenedAt else { return }
        let extra = path.count - opened
        if extra > 0 { path.removeLast(extra) }
        hiddenOpenedAt = nil
    }
}

struct BoardsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var nav: BoardsNavigation   // the path; RootTabsView closes Hidden on going to the background
    @State private var segment: BoardsSegment = .boards
    @State private var showNewBoard = false
    @State private var showReorder = false
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []

    /// Favorite boards (at any depth) first, then the top-level boards, in the chosen order.
    private var pageBoards: [Board] { store.boardsPageBoards(scope: .visible, sort: settings.boardSort) }

    var body: some View {
        NavigationStack(path: $nav.path) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 14) {
                        segmentPicker
                        switch segment {
                        case .boards:
                            boardsSection(width: geometry.size.width - 28)
                        case .smart:
                            SmartBoardsSection(width: geometry.size.width - 28)
                                .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .hidesBarsOnScroll(enabled: !isSelecting)   // scrolling down tucks the bars away (ScrollingBars.swift)
            }
            // Swiping sideways here moves to the next tab (only on this root screen).
            .tabSwipeRoot(.boards, enabled: !isSelecting)
            .navigationTitle("Boards")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    addButton
                    moreMenu
                }
            }
            .modifier(BoardBatchActions(isSelecting: $isSelecting, selection: $selection, scope: .visible,
                                        allBoardIDs: pageBoards.map { (board: Board) -> UUID in board.id }))
            .sheet(isPresented: $showNewBoard) {
                TextEditSheet(title: "New board", placeholder: "Board name", initial: "", requiresText: true) { name in
                    store.addBoard(name: name)
                }
            }
            .sheet(isPresented: $showReorder) {
                BoardReorderSheet(parentID: nil)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onChange(of: segment) {
            if isSelecting { finishSelecting() }
        }
        .onChange(of: router.pendingRoute) { _, route in
            // A page another screen asked for (see AppRouter.open): this tab pushes it when selected.
            guard let route, router.selectedTab == .boards else { return }
            router.pendingRoute = nil
            nav.push(route)
        }
    }

    /// "Select" in a board tile's menu: selecting boards starts, with this board chosen.
    private func startSelecting(_ id: UUID) {
        withAnimation {
            selection = [id]
            isSelecting = true
        }
    }

    private var segmentPicker: some View {
        let smartCount = store.smartBoards(scope: .visible).count
        return FittingSegmentedPicker(title: "Section", selection: $segment, options: [
            SegmentOption(value: BoardsSegment.boards, label: "Boards"),
            SegmentOption(value: BoardsSegment.smart, label: "Smart\(smartCount == 0 ? "" : " (\(smartCount))")")
        ])
        .tabSwipeExempt()   // sliding along the switch never changes tabs
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    /// "+" makes a new board (Boards segment). While selecting, the one "Done" is in the selection bar.
    @ViewBuilder
    private var addButton: some View {
        if segment == .boards {
            Button {
                showNewBoard = true
            } label: {
                AddMenuLabel()
            }
            .accessibilityLabel("New board")
        }
    }

    private var moreMenu: some View {
        Menu {
            if segment == .boards {
                Button {
                    withAnimation { isSelecting.toggle() }
                    if !isSelecting { selection = [] }
                } label: {
                    Label(isSelecting ? "Done selecting" : "Select boards", systemImage: "checkmark.circle")
                }
                .disabled(pageBoards.isEmpty && !isSelecting)
                BoardSortMenu()
                Button {
                    showReorder = true
                } label: {
                    Label("Reorder boards", systemImage: "arrow.up.arrow.down")
                }
                .disabled(store.rootBoards(scope: .visible).count < 2)
                Divider()
            }
            // Always offered: it also opens an empty Hidden section, so a first hidden board can be made.
            Button {
                openHidden()
            } label: {
                Label("Hidden…", systemImage: "lock")
            }
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

    private func openHidden() {
        if isSelecting { finishSelecting() }
        nav.openHidden()
    }

    @ViewBuilder
    private func boardsSection(width: CGFloat) -> some View {
        let boards = pageBoards
        if boards.isEmpty {
            EmptyStateView(icon: "folder.badge.plus",
                           title: "No boards yet",
                           message: "Boards keep pins organized. You can nest boards inside boards to make categories, e.g. Travel › Beaches. Drag a pin onto a board to put it there.")
                .padding(.top, 40)
        } else {
            BoardGrid(boards: boards, width: width, isSelecting: isSelecting, selection: $selection, showsParents: true,
                      onSelect: { (id: UUID) -> Void in startSelecting(id) })
                .padding(.horizontal, 14)
        }
        if !store.unsortedPins.isEmpty {
            // The menu item's own title, so it can be found as written.
            Text("\(store.unsortedPins.count) unsorted pin\(store.unsortedPins.count == 1 ? "" : "s") — to put them on suggested boards, choose Pins › ⋯ › AI sorting › Sort Unsorted pins into boards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func finishSelecting() {
        withAnimation {
            selection = []
            isSelecting = false
        }
    }
}

/// "Sort boards" in the ⋯ menus (Boards tab, Hidden, a board's page): one choice
/// for every board list of the app. Favorites always stay on top.
struct BoardSortMenu: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Menu {
            Picker("Sort boards", selection: $settings.boardSort) {
                ForEach(BoardSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort boards", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

/// "5m", "3h", "3d", "2w", "1mo", "1y" — how long ago, as short as possible ("now" under a minute).
func compactAge(since date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    let minutes = Int(seconds / 60)
    let hours = minutes / 60
    let days = hours / 24
    if minutes < 1 { return "now" }
    if hours < 1 { return "\(minutes)m" }
    if days < 1 { return "\(hours)h" }
    if days < 7 { return "\(days)d" }
    if days < 30 { return "\(days / 7)w" }
    if days < 365 { return "\(max(1, days / 30))mo" }
    return "\(days / 365)y"
}

/// Selecting several boards (the Boards tab and the Hidden section): the bar at the bottom,
/// and — through the same presenter as a tile's menu — what its buttons do. Moves stay on
/// the `scope`'s side of the library. Any command carried out ends selecting.
@MainActor
struct BoardBatchActions: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @Binding var isSelecting: Bool
    @Binding var selection: Set<UUID>
    let scope: PinScope
    /// Every board the screen lists — what "Select all" selects.
    var allBoardIDs: [UUID] = []

    @State private var request: BoardCommandRequest? = nil   // the bar's command (BoardCommandPresenter)

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    BoardBatchBar(count: selection.count,
                                  boards: selectedFacts,
                                  allSelected: allSelected,
                                  side: scope,
                                  onSelectAll: { toggleAll() },
                                  onCommand: { command in ask(command) },
                                  onDone: { finish() })
                }
            }
            .modifier(BoardCommandPresenter(request: $request, onDone: { _ in finish() }))
    }

    /// Every board the screen lists is selected.
    private var allSelected: Bool {
        !allBoardIDs.isEmpty && Set(allBoardIDs).isSubset(of: selection)
    }

    /// "Select all" / "Deselect all" (selecting goes on after "Deselect all").
    private func toggleAll() {
        selection = allSelected ? [] : Set(allBoardIDs)
    }

    /// The selected boards, as the command rules see them (each also says whether it sits inside
    /// another selected board).
    private var selectedFacts: [BoardFacts] {
        let boards = selection.compactMap { (id: UUID) -> Board? in store.board(id) }
        return store.boardFacts(boards)
    }

    /// Move into…, Hide/Unhide, Merge… or Delete… for the selected boards.
    private func ask(_ command: BoardCommand) {
        request = BoardCommandRequest(command: command, boardIDs: Array(selection), side: scope)
    }

    private func finish() {
        withAnimation {
            selection = []
            isSelecting = false
        }
    }
}

extension LibraryStore {
    /// Moves a board under another one (nil = the top) without it changing sides:
    /// a board moved to the top of Hidden stays hidden.
    func moveBoard(_ id: UUID, toParent parentID: UUID?, staying scope: PinScope) {
        moveBoard(id, toParent: parentID)
        if scope == .hidden, parentID == nil, board(id)?.isSecret == false {
            setSecret(true, for: id)
        }
    }
}

/// The explanation under "Delete “Travel”?" (and "Delete 3 boards?"), wherever boards are deleted from.
func boardDeleteMessage(hidden: Bool, count: Int = 1) -> String {
    let one = count == 1
    let subBoards = one ? "Sub-boards inside it are deleted as well." : "Sub-boards inside them are deleted as well."
    guard hidden else { return "\(subBoards) Pins that are also on other boards stay there." }
    let pins = one ? "Its pins stay hidden" : "Their pins stay hidden"
    return "\(subBoards) \(pins): kept ones go to Unsorted in Hidden, deleted ones to Recently Deleted in Hidden's ⋯ menu."
}

/// The bar at the bottom while selecting boards: the commands the table gives the bar
/// (dimmed when they can't be used on what is selected), and the selection's one "Done".
struct BoardBatchBar: View {
    var count: Int
    var boards: [BoardFacts]          // the selected boards
    var allSelected: Bool = false     // every board of the screen is selected
    var side: PinScope = .visible     // Hidden's bar has no "Keep off Home page" (hidden pins are never in All)
    var onSelectAll: () -> Void = {}
    var onCommand: (BoardCommand) -> Void
    var onDone: () -> Void

    private var commands: [BoardCommand] { BoardCommandRules.commands(on: .selectionBar, side: side) }

    var body: some View {
        VStack(spacing: 8) {
            SelectionBarHeader(countText: "\(count) selected", allSelected: allSelected,
                               onSelectAll: onSelectAll, onDone: onDone)
            // Icon above caption while every caption fits whole; with larger text, icons alone.
            ViewThatFits(in: .horizontal) {
                buttonRow(withCaptions: true)
                buttonRow(withCaptions: false)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    /// How to select — or, while Merge is dimmed because a selected board sits inside another
    /// selected one, why it is.
    private var hint: String {
        BoardCommandRules.nested(boards) ? BoardMergeText.nestedHint : "Tap boards to select them."
    }

    private func buttonRow(withCaptions: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(commands, id: \.self) { command in
                barButton(command, withCaption: withCaptions)
            }
        }
    }

    /// A short caption under the symbol ("Move", "Hide"…); VoiceOver says the full title
    /// ("Move into…", "Hide boards"…), with the caption or with the symbol alone.
    private func barButton(_ command: BoardCommand, withCaption: Bool) -> some View {
        let title = command.title(for: boards)
        return Button(role: command.isDestructive ? .destructive : nil) {
            onCommand(command)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: command.symbol(for: boards))
                if withCaption {
                    caption(command.barCaption(for: boards))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(!BoardCommandRules.available(command, for: boards))
        .accessibilityLabel(title)
    }

    /// Every caption keeps the room of the widest caption the bar shows right now (invisible
    /// copies underneath). So all buttons ask for the same width, and captions show only when
    /// each of them fits whole in its equal share of the bar. The captions are one short word,
    /// so they fit on an iPhone at the standard text size.
    private func caption(_ text: String) -> some View {
        ZStack {
            ForEach(shownCaptions, id: \.self) { other in
                Text(other)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption2)
        .lineLimit(1)
    }

    /// The captions of the bar's buttons as they read now ("Move", "Hide", "Merge", "Delete").
    private var shownCaptions: [String] {
        commands.map { (command: BoardCommand) -> String in command.barCaption(for: boards) }
    }
}

/// Merging several boards into one: pick the name of the result.
struct MergeBoardsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let boards: [Board]
    let onMerge: (UUID, String) -> Void
    @State private var name: String
    private let initialName: String   // once the name was changed, a swipe down can't close the sheet

    init(boards: [Board], onMerge: @escaping (UUID, String) -> Void) {
        self.boards = boards
        self.onMerge = onMerge
        let start = boards.first?.name ?? ""
        initialName = start
        _name = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Merging: " + boards.map { $0.name }.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NativeTextField(placeholder: "Name of the merged board", text: $name, autoFocus: true) { merge() }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("All their pins and sub-boards end up in one board; the others are removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Merge boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { merge() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || boards.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(name != initialName)   // typed text is only lost with Cancel
    }

    private func merge() {
        guard let first = boards.first, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onMerge(first.id, name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// Drag the handles to change the order of boards that share a parent — or,
/// with `scope: .hidden` and no parent, of the Hidden section's own boards.
struct BoardReorderSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let parentID: UUID?
    var scope: PinScope = .visible
    @State private var ordered: [Board] = []

    private var hiddenRoots: Bool { scope == .hidden && parentID == nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { board in
                        HStack {
                            Image(systemName: board.isSecret ? "lock.fill" : "folder.fill").foregroundStyle(.secondary)
                            Text(board.name)
                            if board.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Favorite")
                            }
                            Spacer()
                            Text("\(store.pinCount(in: board.id))").foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        ordered.move(fromOffsets: from, toOffset: to)
                        if hiddenRoots {
                            store.reorderHiddenRootBoards(ordered.map { $0.id })
                        } else {
                            store.reorderBoards(parentID: parentID, orderedIDs: ordered.map { $0.id })
                        }
                        // Your own order only shows when the lists follow it.
                        settings.boardSort = .custom
                    }
                } footer: {
                    Text(settings.boardSort == .custom
                         ? "Favorites always stay on top."
                         : "Moving a board switches every board list to “Custom order”. Favorites always stay on top.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if hiddenRoots {
                    ordered = store.rootBoards(scope: .hidden)
                } else {
                    // Hidden boards stay out of it unless the parent itself is hidden (then they all are).
                    let insideHidden = parentID.map { store.isSecretBoard($0) } ?? false
                    ordered = insideHidden ? store.children(of: parentID) : store.visibleChildren(of: parentID)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// Board commands (one table for every surface): BoardCommands.swift.

// MARK: - Board tiles

/// Board tiles that fill the width: as many columns as fit (2 to 4). Two
/// columns even for a single board, so it never spans the whole screen.
/// Used by the Boards tab and for sub-boards inside a board. Tiles take drops
/// (pins, pictures, text, links) and have a touch-and-hold menu.
struct BoardGrid<Trailing: View>: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    let boards: [Board]
    let width: CGFloat
    var isSelecting: Bool = false
    var selection: Binding<Set<UUID>>? = nil
    /// The Boards page (and Hidden › Boards): a favorite sub-board says which board it is in.
    var showsParents: Bool = false
    /// "Select" in a tile's menu: the screen starts selecting boards with this one chosen (nil:
    /// this grid can't select, and its menu has no "Select").
    var onSelect: ((UUID) -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @State private var request: BoardCommandRequest? = nil   // a tile menu's command (BoardCommandPresenter)

    init(boards: [Board], width: CGFloat, isSelecting: Bool = false, selection: Binding<Set<UUID>>? = nil,
         showsParents: Bool = false, onSelect: ((UUID) -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.boards = boards
        self.width = width
        self.isSelecting = isSelecting
        self.selection = selection
        self.showsParents = showsParents
        self.onSelect = onSelect
        self.trailing = trailing
    }

    var body: some View {
        let count = max(2, min(4, Int(width / 230)))
        // Tiles line up at the top: a name on two lines makes its row taller, never its neighbors lower.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(boards) { board in
                tile(for: board)
            }
            trailing()
        }
        // Rename, cover, move, share, delete…: the same presenter as a board page's ⋯ menu.
        .modifier(BoardCommandPresenter(request: $request))
    }

    @ViewBuilder
    private func tile(for board: Board) -> some View {
        let selected = selection?.wrappedValue.contains(board.id) ?? false
        if isSelecting {
            Button {
                guard let selection else { return }
                if selected { selection.wrappedValue.remove(board.id) } else { selection.wrappedValue.insert(board.id) }
            } label: {
                BoardCardView(board: board, isSelecting: true, isSelected: selected, showsParent: showsParents)
            }
            .buttonStyle(.plain)
            // The card's own label replaces its parts, so VoiceOver hears the selection as a trait.
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: Route.board(board.id)) {
                BoardCardView(board: board, showsParent: showsParents)
            }
            .buttonStyle(.plain)
            .contextMenu {
                BoardTileMenu(board: board, canSelect: onSelect != nil) { command in
                    runTileCommand(command, on: board)
                }
            }
            .modifier(PinDropZone(boardIDs: [board.id], style: .tile))
        }
    }
}

extension BoardGrid {
    /// A command from a tile's touch-and-hold menu: "Select" starts selecting (the screen does it);
    /// every other one goes to the presenter.
    fileprivate func runTileCommand(_ command: BoardCommand, on board: Board) {
        if command == .select {
            onSelect?(board.id)
        } else {
            request = BoardCommandRequest(command, board: board.id, store: store)
        }
    }
}

extension BoardGrid where Trailing == EmptyView {
    init(boards: [Board], width: CGFloat, isSelecting: Bool = false, selection: Binding<Set<UUID>>? = nil,
         showsParents: Bool = false, onSelect: ((UUID) -> Void)? = nil) {
        self.init(boards: boards, width: width, isSelecting: isSelecting, selection: selection,
                  showsParents: showsParents, onSelect: onSelect) { EmptyView() }
    }
}

/// A dashed tile that creates a new (sub-)board.
struct NewBoardTile: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .aspectRatio(1.35, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)   // like a board's name
                Text(" ")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A board tile with a small collage of its most recent pins, and one compact
/// line under the name: "134 pins • 15 sub-boards • 1mo" (the age is how long
/// ago something was last added). A normal board never counts hidden things.
/// For VoiceOver the tile is one element with its own label; while selecting, the
/// grid adds "selected" to it as a trait.
struct BoardCardView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.pinAccent) private var accent
    let board: Board
    var isSelecting: Bool = false
    var isSelected: Bool = false
    /// Add "in <parent>" for a favorite sub-board (it sits among top-level boards on the Boards page).
    var showsParent: Bool = false

    var body: some View {
        // One pass over the board's pins per render (tiles re-render on every library change).
        let boardPins = store.pins(in: board.id, includeNested: true)
        let cover = board.coverPinID.flatMap { id in boardPins.first { $0.id == id } } ?? boardPins.first
        let collage = ([cover].compactMap { $0 } + boardPins.filter { $0.id != cover?.id && $0.hasImageFile }).prefix(4)
        let details = subtitleParts(pins: boardPins.count)
        VStack(alignment: .leading, spacing: 8) {
            CollageView(pins: Array(collage))
                .aspectRatio(1.35, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous)
                        .strokeBorder(accent, lineWidth: isSelected ? 3 : 0)
                }
                .overlay(alignment: .topTrailing) { trailingBadge }
                .overlay(alignment: .topLeading) { favoriteBadge }
            Text(board.name)
                .font(.headline)
                .lineLimit(2)   // the grid lines tiles up at the top, so a long name may take two lines
            Text(details.joined(separator: " • "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(isSelecting && !isSelected ? 0.75 : 1)
        // Only this label is spoken (the parts are ignored), so each fact is said once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(details))
    }

    /// "Travel, favorite, 134 pins, 15 sub-boards, 1mo, hidden".
    private func spokenLabel(_ details: [String]) -> String {
        var parts = [board.name]
        if board.isFavorite { parts.append("favorite") }
        parts.append(contentsOf: details)
        if store.isSecretBoard(board.id) { parts.append("hidden") }
        return parts.joined(separator: ", ")
    }

    /// The selection mark and the lock only repeat what the label and the "selected" trait say.
    @ViewBuilder
    private var trailingBadge: some View {
        if isSelecting {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isSelected ? accent : Color.black.opacity(0.35))
                .padding(10)
                .accessibilityHidden(true)
        } else if store.isSecretBoard(board.id) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.semibold))
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var favoriteBadge: some View {
        if board.isFavorite {
            Image(systemName: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.yellow)
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    /// "134 pins", "15 sub-boards", "1mo", plus "in Travel" for a favorite sub-board on the Boards page
    /// (the line under the name, and — once — the spoken label).
    private func subtitleParts(pins: Int) -> [String] {
        var parts = ["\(pins) pin\(pins == 1 ? "" : "s")"]
        let subBoards = store.subBoardCount(of: board.id)
        if subBoards > 0 { parts.append("\(subBoards) sub-board\(subBoards == 1 ? "" : "s")") }
        if let added = store.lastAddedDate(for: board.id) { parts.append(compactAge(since: added)) }
        if showsParent, board.isFavorite, let parentID = board.parentID, let parent = store.board(parentID) {
            parts.append("in \(parent.name)")
        }
        return parts
    }
}

struct CollageView: View {
    let pins: [Pin]

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack(alignment: .topLeading) {
                Color(uiColor: .secondarySystemFill)
                if pins.isEmpty {
                    Image(systemName: "folder")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                        .frame(width: w, height: h)
                } else if pins.count == 1 {
                    CollageTile(pin: pins[0]).frame(width: w, height: h)
                } else {
                    CollageTile(pin: pins[0]).frame(width: w * 0.62 - 1, height: h)
                    VStack(spacing: 2) {
                        ForEach(Array(pins.dropFirst().prefix(3))) { pin in
                            CollageTile(pin: pin)
                        }
                    }
                    .frame(width: w * 0.38 - 1, height: h)
                    .offset(x: w * 0.62 + 1)
                }
            }
        }
    }
}

struct CollageTile: View {
    @EnvironmentObject private var store: LibraryStore
    let pin: Pin
    @State private var image: UIImage? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .tertiarySystemFill)
                if pin.isText {
                    Text(pin.textBody.isEmpty ? pin.title : pin.textBody)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if pin.isLink {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                }
                if pin.isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(pin.id)|\(pin.hasPreview)|\(pin.updatedAt.timeIntervalSince1970)") {
            if pin.hasImageFile { image = await store.thumbnail(for: pin) } else { image = nil }
        }
    }
}

/// A scrolling grid of pictures to choose one from: a board's cover, or a video's thumbnail. `top`
/// is whatever sits above the grid (the cover picker's "Automatic" button). `selectedID` gets the
/// accent border. Tapping a picture calls `onPick`.
struct PicturePinPicker<Top: View>: View {
    @EnvironmentObject private var settings: AppSettings
    let pins: [Pin]
    var selectedID: UUID? = nil
    var emptyTitle: String
    @ViewBuilder var top: () -> Top
    let onPick: (Pin) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(columns: max(2, settings.columnCount(forWidth: geometry.size.width)),
                                      width: geometry.size.width - PinTheme.gridSpacing * 2)
            ScrollView {
                VStack(spacing: 12) {
                    top()
                    if pins.isEmpty {
                        EmptyStateView(icon: "photo", title: emptyTitle, message: "")
                    } else {
                        pictureGrid(metrics)
                    }
                }
                .padding(.horizontal, PinTheme.gridSpacing)
                .padding(.bottom, 24)
            }
        }
    }

    private func pictureGrid(_ metrics: GridMetrics) -> some View {
        MasonryGrid(items: pins, metrics: metrics,
                    aspectRatio: { $0.aspectRatio },
                    footerHeight: { PinCardView.footerHeight(for: $0, caption: nil) }) { pin in
            Button {
                onPick(pin)
            } label: {
                PinCardView(pin: pin, isSelected: selectedID == pin.id)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Pick a board's cover from its pins.
struct CoverPickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID

    var body: some View {
        NavigationStack {
            PicturePinPicker(pins: store.pins(in: boardID, includeNested: true).filter { $0.hasImageFile },
                             selectedID: store.board(boardID)?.coverPinID,
                             emptyTitle: "No pictures on this board yet") {
                Button {
                    store.setCover(nil, for: boardID)
                    dismiss()
                } label: {
                    Label("Automatic (the newest pin)", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } onPick: { (pin: Pin) -> Void in
                store.setCover(pin.id, for: boardID)
                dismiss()
            }
            .navigationTitle("Board cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// "Thumbnail ▸ Use a picture pin…": the library's picture pins (only those of `side`, newest
/// first) to choose a video's thumbnail from. It hands back the chosen pin's id and closes.
struct PosterPinPickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let side: PinScope
    let onPick: (UUID) -> Void

    var body: some View {
        NavigationStack {
            PicturePinPicker(pins: pictures, emptyTitle: "No picture pins yet") {
                EmptyView()
            } onPick: { (pin: Pin) -> Void in
                onPick(pin.id)
                dismiss()
            }
            .navigationTitle("Choose a picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    /// Picture pins of this side of the library (videos and links are not offered: their pictures
    /// are frames and previews), newest first.
    private var pictures: [Pin] {
        store.pins(scope: side)
            .filter { (pin: Pin) -> Bool in pin.kind == .image && pin.hasImageFile }
            .sorted { (a: Pin, b: Pin) -> Bool in a.createdAt > b.createdAt }
    }
}

// Hidden (hidden pins and boards behind Face ID / Touch ID / passcode): HiddenSection.swift.
// AI sorting (boards, tags and names): BoardCommands.swift.
// One board, the Board picker and the Batch tag editor: BoardPage.swift.
