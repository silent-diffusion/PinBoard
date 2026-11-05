//
//  BoardPage.swift  —  PinBoard
//
//  A single board's page (its info line and description, sub-boards, the "+" menu,
//  drops, sharing the board, the "keep exploring" web feed), and the batch tag editor.
//  The board picker is in BoardPicker.swift; the Boards tab and the board tiles are in
//  BoardViews.swift.
//

import SwiftUI
import PhotosUI
import LocalAuthentication
import UIKit
import Foundation

// MARK: - One board

/// The page's own sheets (one at a time). The board's commands — rename, description, new
/// sub-board, cover, move, share, delete — go through BoardCommandPresenter, like a tile's menu.
enum BoardPageSheet: String, Identifiable {
    case reorderSubBoards, palette
    var id: String { rawValue }
}

struct BoardDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var access = HiddenAccess.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinAccent) private var accent
    @Environment(\.isInsideSettings) private var isInsideSettings
    let boardID: UUID

    @StateObject private var addFlags = AddPinFlags()
    /// This visit's own choice for "Include pins from sub-boards" (nil: it was not touched, so
    /// the default from Settings › Pins & boards applies). The choice lasts for the visit only.
    @State private var nestedChoice: Bool? = nil
    @State private var isSelectingBoards = false    // selecting sub-boards (a sub-board tile's "Select")
    @State private var boardSelection: Set<UUID> = []
    @State private var sheet: BoardPageSheet? = nil
    @State private var boardCommand: BoardCommandRequest? = nil   // a board command (BoardCommandPresenter)
    @State private var isSelecting = false
    @State private var countedOpen = false          // this visit was counted ("Opened N×")
    @State private var visit = UUID()               // this visit's own order of pins (see Feed)
    @State private var bigTitle = false             // the title's surprise is showing
    @State private var titleColors: [String] = []   // the board's colors for it
    @State private var aiPrompt: AIPrompt? = nil    // the "AI sorting" menu's questions
    /// This page hid its own board and is going back: meanwhile the page stays as it is instead
    /// of turning into Hidden's lock screen (which would ask for Face ID on the way out).
    @State private var leaving = false

    /// This visit's list of pins: its order lasts while you open pins from it and come back,
    /// and the next visit to the board starts in a new one.
    private var feed: Feed { .board(boardID, visit: visit) }

    /// Whether the page lists its sub-boards' pins too: the default is set in Settings (on, as a
    /// pin moved into a sub-board is still on its parent boards), the toggle changes it for this visit.
    private var includeNested: Bool { nestedChoice ?? settings.boardPagesIncludeSubBoards }

    /// The toggle's two-way link to this visit's choice.
    private var includeNestedBinding: Binding<Bool> {
        Binding(get: { includeNested }, set: { (now: Bool) -> Void in nestedChoice = now })
    }

    var body: some View {
        if let board = store.board(boardID) {
            let secret = store.isSecretBoard(boardID) && !leaving
            // A hidden board's name is not shown until it has been unlocked.
            let locked = secret && settings.lockHiddenBoards && !access.isUnlocked
            Group {
                if secret {
                    content(board).hiddenGate()
                } else {
                    content(board)
                }
            }
            .navigationTitle(locked ? "Hidden" : board.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleView(board, locked: locked)
                }
            }
        } else {
            EmptyStateView(icon: "folder", title: "This board was deleted", message: "")
        }
    }

    /// The small title in the bar. Tapping it shows (or hides) the board's name in big colored letters.
    @ViewBuilder
    private func titleView(_ board: Board, locked: Bool) -> some View {
        if locked {
            Text("Hidden")
                .font(.headline)
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { bigTitle.toggle() }
            } label: {
                Text(board.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(board.name)
        }
    }

    private func content(_ board: Board) -> some View {
        // Inside a hidden board everything is hidden, so nothing is filtered there.
        let hidden = store.isSecretBoard(boardID)
        let subBoards = store.sortedChildren(of: boardID, sort: settings.boardSort)
        return PinCollectionView(
            pins: store.pins(in: boardID, includeNested: includeNested),
            isSelecting: $isSelecting,
            emptyIcon: "pin",
            emptyTitle: "No pins on this board",
            emptyMessage: "Add with +, drag pins or pictures here, open a pin and choose this board, or scroll down for ideas from the web.",
            boardID: boardID,
            scope: hidden ? .hidden : .visible,
            feed: feed   // shuffled or by date added, as chosen in ⋯ (one setting for every board)
        ) { metrics in
            header(board, hidden: hidden, subBoards: subBoards, metrics: metrics)
        } footer: { metrics in
            if settings.showBoardWebFeed, settings.webAllowed {
                // Lazy, so the web is only contacted once you scroll down to it.
                LazyVStack {
                    BoardWebFooter(boardID: boardID, metrics: metrics)
                }
            }
        }
        // Pins added to a hidden board are hidden by the board itself.
        .modifier(PinDropZone(boardIDs: [boardID], style: .page))
        .modifier(AddPinPresenters(flags: addFlags, boardIDs: [boardID]))
        // Selecting sub-boards (from a sub-board tile's menu or ⋯): the same bar as the Boards tab's.
        .modifier(BoardBatchActions(isSelecting: $isSelectingBoards, selection: $boardSelection,
                                    scope: hidden ? .hidden : .visible,
                                    allBoardIDs: subBoards.map { (board: Board) -> UUID in board.id }))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                AddPinMenu(flags: addFlags)
                moreMenu(board, hidden: hidden, subBoardCount: subBoards.count)
            }
        }
        .sheet(item: $sheet) { which in
            // Reorder and Colors of a hidden board never show in the App Switcher.
            sheetView(which, board: board, hidden: hidden)
                .hiddenPrivacyCover(hidden)
        }
        .modifier(AISortingDialogs(prompt: $aiPrompt))
        // Rename, description, cover, move, share, hide, delete…: the same presenter as the tiles' menus.
        .modifier(BoardCommandPresenter(request: $boardCommand, onDone: { command in
            goBackIfGone(after: command)
        }))
        .onAppear {
            // Counted once per visit, and (inside the gate) only once a hidden board is unlocked.
            guard !countedOpen else { return }
            countedOpen = true
            store.noteBoardOpened(boardID)
        }
        .onChange(of: includeNested) {
            // With (or without) the sub-boards' pins: mixed afresh, not grouped by sub-board.
            FeedOrder.shared.contentsChanged(feed)
        }
        .onChange(of: isSelecting) { _, selecting in
            // One selection bar at a time: choosing pins ends choosing sub-boards, and the other way round.
            if selecting, isSelectingBoards { endBoardSelection() }
        }
        .onChange(of: isSelectingBoards) { _, selecting in
            if selecting, isSelecting { isSelecting = false }
        }
        .task(id: bigTitle) {
            await loadTitleColors()
        }
    }

    private func header(_ board: Board, hidden: Bool, subBoards: [Board], metrics: GridMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if bigTitle {
                PaletteTitleBlock(name: board.name, colors: titleColorList)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { bigTitle = false }
                    }
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                if let path = store.boardPath(board.parentID) {
                    Text("In: \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hidden {
                    Label("Hidden", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            BoardInfoSection(board: board) { ask(.description) }
            subBoardsSection(subBoards, metrics: metrics)
        }
    }

    @ViewBuilder
    private func subBoardsSection(_ subBoards: [Board], metrics: GridMetrics) -> some View {
        if subBoards.isEmpty {
            Button {
                ask(.newSubBoard)
            } label: {
                Label("Add a sub-board", systemImage: "folder.badge.plus")
                    .font(.subheadline)
            }
        } else {
            // Sub-boards look and work exactly like boards on the Boards tab,
            // with a dashed tile at the end for a new one.
            Text("Sub-boards")
                .font(.headline)
            BoardGrid(boards: subBoards, width: metrics.width, isSelecting: isSelectingBoards, selection: $boardSelection,
                      onSelect: { (id: UUID) -> Void in startBoardSelection(id) }) {
                if !isSelectingBoards {
                    NewBoardTile(title: "New sub-board") { ask(.newSubBoard) }
                }
            }
            Toggle("Include pins from sub-boards", isOn: includeNestedBinding)
                .font(.subheadline)
            Divider()
            Text(includeNested ? "Pins (including sub-boards)" : "Pins")
                .font(.headline)
        }
    }

    /// "Select" in a sub-board tile's menu: selecting sub-boards starts, with this one chosen.
    private func startBoardSelection(_ id: UUID) {
        withAnimation {
            boardSelection = [id]
            isSelectingBoards = true
        }
    }

    private func endBoardSelection() {
        withAnimation {
            boardSelection = []
            isSelectingBoards = false
        }
    }

    /// Asks for one of the board's commands (BoardCommandPresenter carries it out).
    private func ask(_ command: BoardCommand) {
        boardCommand = BoardCommandRequest(command, board: boardID, store: store)
    }

    /// After Delete… the board is gone; after Hide board it has moved into Hidden. Either way the
    /// page goes back to where it was opened from, and the presenter's confirmation says where the
    /// board went. (Unhide keeps the page: the board is simply a normal board again.)
    private func goBackIfGone(after command: BoardCommand) {
        let hidItsBoard = command == .hide && store.board(boardID)?.isSecret == true
        guard command == .delete || hidItsBoard else { return }
        leaving = hidItsBoard   // no lock screen, no Face ID on the way out
        dismiss()
    }

    /// ⋯: Select pins | the board's commands, from the table (the same as its tile's menu) | its
    /// sub-boards and pins | AI sorting and colors | Settings… | Delete…. Commands that can't be
    /// used right now are dimmed here (a tile's menu leaves them out).
    private func moreMenu(_ board: Board, hidden: Bool, subBoardCount: Int) -> some View {
        let commands = BoardCommandRules.commands(on: .moreMenu)
        let mainCommands = commands.filter { (command: BoardCommand) -> Bool in !command.isDestructive }
        let deleteCommands = commands.filter { (command: BoardCommand) -> Bool in command.isDestructive }
        let facts = [store.boardFacts(board)]
        return Menu {
            Group {
                selectPinsItem
                selectSubBoardsItem(count: subBoardCount)
                Divider()
                BoardCommandItems(commands: mainCommands, boards: facts, surface: .moreMenu) { command in
                    ask(command)
                }
            }
            Group {
                Divider()
                Button { sheet = .reorderSubBoards } label: { Label("Reorder sub-boards", systemImage: "arrow.up.arrow.down") }
                    .disabled(subBoardCount < 2)
                BoardSortMenu()
                Menu {
                    FeedOrderMenuItems(feed: feed)
                } label: {
                    Label("Order of pins", systemImage: "shuffle")
                }
            }
            Group {
                Divider()
                aiSortingMenu(hidden: hidden)
                Button { sheet = .palette } label: { Label("Generate colors", systemImage: "paintpalette") }
            }
            if !isInsideSettings {   // (a board page reached from Settings is inside it already)
                Divider()
                Button {
                    router.showSettings = true
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
            }
            BoardCommandItems(commands: deleteCommands, boards: facts, surface: .moreMenu) { command in
                ask(command)
            }
        } label: {
            MoreMenuLabel()
        }
        .accessibilityLabel("More")
    }

    private var selectPinsItem: some View {
        Button {
            withAnimation { isSelecting.toggle() }
        } label: {
            Label(isSelecting ? "Done selecting" : "Select pins", systemImage: "checkmark.circle")
        }
    }

    /// ⋯ › Select sub-boards (only when the board has some).
    @ViewBuilder
    private func selectSubBoardsItem(count: Int) -> some View {
        if count > 0 || isSelectingBoards {
            Button {
                if isSelectingBoards { endBoardSelection() } else { withAnimation { isSelectingBoards = true } }
            } label: {
                Label(isSelectingBoards ? "Done selecting" : "Select sub-boards", systemImage: "checkmark.circle")
            }
        }
    }

    /// AI sorting for the pins this page shows (with or without its sub-boards' pins).
    private func aiSortingMenu(hidden: Bool) -> some View {
        let shownIDs = Set(store.pins(in: boardID, includeNested: includeNested).map { (pin: Pin) -> UUID in pin.id })
        return AISortingMenu(target: .pins(shownIDs, scope: hidden ? .hidden : .visible), prompt: $aiPrompt)
            .disabled(shownIDs.isEmpty)
    }

    @ViewBuilder
    private func sheetView(_ which: BoardPageSheet, board: Board, hidden: Bool) -> some View {
        switch which {
        case .reorderSubBoards:
            BoardReorderSheet(parentID: boardID)
        case .palette:
            PaletteSheet(title: board.name,
                         pinIDs: Array(store.pinIDs(in: boardID, includeNested: true)),
                         boardID: boardID,
                         scope: hidden ? .hidden : .visible)
        }
    }

    /// The colors behind the big title: the board's saved palette while it is up to date,
    /// otherwise worked out in the background (and saved). The accent color meanwhile.
    private var titleColorList: [Color] {
        let colors = titleColors.compactMap { Color(hexString: $0) }
        return colors.isEmpty ? [accent, accent.opacity(0.45)] : colors
    }

    private func loadTitleColors() async {
        guard bigTitle else { return }
        if let fresh = store.freshPalette(for: boardID) {
            titleColors = fresh
            return
        }
        let ids = Array(store.pinIDs(in: boardID, includeNested: true))
        titleColors = await PaletteMaker.colors(for: ids, boardID: boardID, store: store)
    }
}

/// Under a board's title: one compact line of facts (pins, sub-boards, dates,
/// visits, size), then the board's description — or a button to add one.
struct BoardInfoSection: View {
    @EnvironmentObject private var store: LibraryStore
    let board: Board
    let onEditDescription: () -> Void
    @State private var bytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(infoLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            descriptionRow
        }
        .task(id: "\(board.id)|\(store.pinCount(in: board.id))") {
            bytes = await store.storageSize(ofBoard: board.id, includeNested: true)
        }
    }

    /// "134 pins · 15 sub-boards · Created 3 Mar 2025 · Edited 2d ago · Last added 5h ago · Opened 12× · 48 MB"
    private var infoLine: String {
        let pins = store.pinCount(in: board.id)
        var parts = ["\(pins) pin\(pins == 1 ? "" : "s")"]
        let subBoards = store.subBoardCount(of: board.id)
        if subBoards > 0 { parts.append("\(subBoards) sub-board\(subBoards == 1 ? "" : "s")") }
        parts.append("Created \(board.createdAt.formatted(date: .abbreviated, time: .omitted))")
        parts.append(ago("Edited", store.lastEditedDate(for: board.id)))
        if let added = store.lastAddedDate(for: board.id) { parts.append(ago("Last added", added)) }
        if board.openCount > 0 { parts.append("Opened \(board.openCount)×") }
        if bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    private func ago(_ what: String, _ date: Date) -> String {
        let age = compactAge(since: date)
        return age == "now" ? "\(what) just now" : "\(what) \(age) ago"
    }

    @ViewBuilder
    private var descriptionRow: some View {
        if board.details.isEmpty {
            Button(action: onEditDescription) {
                Label("Add a description", systemImage: "text.alignleft")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text(board.details)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onEditDescription) {
                    // A 44-pt target (the pencil itself is much smaller), level with the first line.
                    Image(systemName: "pencil")
                        .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit description")
            }
        }
    }
}

/// What the background export of "Share board…" hands back (plain values only).
enum ShareBoardOutcome: Sendable {
    case ready(URL)        // the zip
    case failed(String)    // why it failed, in words
}

/// "Share board…": the board — and, if wanted, its sub-boards — with all their
/// pins as one zip, handed straight to the share sheet. Unzipped in Files, it
/// comes back exactly with Settings › Library › Import a folder….
struct ShareBoardSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID

    @State private var includeSubBoards = true
    @State private var exporting = false
    @StateObject private var progress = ExportProgress()
    @State private var zipURL: URL? = nil
    @State private var sharePresented = false
    @State private var errorText: String? = nil

    /// Sub-boards on the board's own side (a normal board never takes hidden ones along).
    private var subBoardCount: Int {
        let hidden = store.isSecretBoard(boardID)
        return store.descendants(of: boardID).filter { store.isSecretBoard($0) == hidden }.count
    }

    var body: some View {
        Group {
            if let zipURL {
                ActivityShareSheet(items: [zipURL], isPresented: $sharePresented)
            } else {
                NavigationStack {
                    optionsForm
                        .navigationTitle("Share board")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                        }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: sharePresented) { _, showing in
            // The share sheet is done: close this sheet too.
            if !showing, zipURL != nil { dismiss() }
        }
    }

    private var optionsForm: some View {
        let subBoards = subBoardCount
        let pinCount = store.pinIDs(in: boardID, includeNested: includeSubBoards && subBoards > 0).count
        return Form {
            Section {
                HStack {
                    Label(store.board(boardID)?.name ?? "Board", systemImage: "folder.fill")
                    Spacer()
                    Text("\(pinCount) pin\(pinCount == 1 ? "" : "s")").foregroundStyle(.secondary)
                }
                if subBoards > 0 {
                    Toggle("Include sub-boards (\(subBoards))", isOn: $includeSubBoards)
                        .disabled(exporting)
                }
            } footer: {
                Text(footerText)
            }
            Section {
                if exporting {
                    ExportProgressBar(progress: progress)
                        .padding(.vertical, 4)
                } else {
                    Button {
                        startExport(includeSubBoards: includeSubBoards && subBoards > 0)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footerText: String {
        var text = "One zip with the pictures, videos, notes and tags. Unzip it in Files, then in PinBoard choose \(SettingsCatalog.rowPath(.importFolder)) to bring the board back exactly."
        if store.isSecretBoard(boardID) {
            text += " The copy is not hidden: whoever opens it sees everything in it."
        }
        return text
    }

    private func startExport(includeSubBoards: Bool) {
        guard !exporting else { return }
        guard let job = store.boardExportJob(boardID: boardID, includeSubBoards: includeSubBoards) else {
            errorText = "This board no longer exists."
            return
        }
        exporting = true
        errorText = nil
        let progressBox = progress
        progressBox.start(total: job.pins.count)
        // Reported per pin from the export's thread; about 200 updates at most reach the screen.
        let step = max(1, job.pins.count / 200)
        let report: @Sendable (Int, Int) -> Void = { done, total in
            guard done == total || done % step == 0 else { return }
            Task { @MainActor in progressBox.report(done: done, total: total) }
        }
        let zipping: @Sendable (Int64) -> Void = { bytes in
            Task { @MainActor in progressBox.beginZip(bytes: bytes) }
        }
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) { () -> ShareBoardOutcome in
                do {
                    return .ready(try LibraryExporter.exportBoard(job, progress: report, zipping: zipping))
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            exporting = false
            switch outcome {
            case .ready(let url):
                zipURL = url
                sharePresented = true
            case .failed(let reason):
                errorText = "The board couldn't be exported: \(reason)"
            }
        }
    }
}

/// "Keep exploring" — web results related to a board, shown under its pins.
/// Nothing is fetched until you tap the button (unless "Automatically load
/// web suggestions" is on in Settings). Saving a result puts it on this board.
struct BoardWebFooter: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    let boardID: UUID
    let metrics: GridMetrics

    @State private var wanted = false          // the user asked for web ideas
    @State private var query = ""
    @State private var thinking = false
    @State private var usedAI = false
    @State private var variant = 0
    @State private var editingQuery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.top, 8)
            HStack {
                Label("Keep exploring", systemImage: "globe")
                    .font(.headline)
                Spacer()
                if wanted, !query.isEmpty {
                    Button {
                        variant += 1
                        Task { await chooseQuery(avoiding: query) }
                    } label: {
                        Label("Different ideas", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    .disabled(thinking)
                }
            }
            if !wanted {
                Text("Find images related to this board on \(settings.webSource.label). Anything you save lands on this board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    wanted = true
                    Task { await chooseQuery(avoiding: nil) }
                } label: {
                    Label("Show ideas from the web", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
            } else if thinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(boardUsesAI ? "Apple Intelligence is composing a search…" : "Choosing a search…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: usedAI ? "sparkles" : "tag")
                        .foregroundStyle(.secondary)
                    Text("Searching for “\(query)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Change") { editingQuery = true }
                        .font(.caption)
                }
                WebFeedView(query: query, boardIDs: [boardID], metrics: metrics)
            }
        }
        .onAppear {
            // A hidden board always waits for the button: its name and pins would
            // otherwise go to the web without a tap.
            if settings.autoLoadWeb, !wanted, !store.isSecretBoard(boardID) {
                wanted = true
                Task { await chooseQuery(avoiding: nil) }
            }
        }
        .sheet(isPresented: $editingQuery) {
            TextEditSheet(title: "Search the web for", placeholder: "Search words", initial: query) { text in
                if !text.isEmpty { query = text; usedAI = false }
            }
            .hiddenPrivacyCover(store.isSecretBoard(boardID))   // a hidden board's search words stay out of the App Switcher
        }
    }

    /// Apple Intelligence composes the search for this board: not for a hidden board unless
    /// "Include hidden pins in AI" is on (it would read its pins' titles and tags).
    private var boardUsesAI: Bool {
        settings.appleIntelligenceActive && (settings.aiIncludesHidden || !store.isSecretBoard(boardID))
    }

    /// Picks the search words: Apple Intelligence when available, tags otherwise.
    private func chooseQuery(avoiding: String?) async {
        guard let board = store.board(boardID) else { return }
        thinking = true
        let members = store.pins(in: boardID, includeNested: true)
        let tags = store.topTags(in: members, limit: 10)
        let parents = store.path(to: boardID).dropLast().map { $0.name }
        let titles = members.prefix(12).map { $0.title }
        let chosen = await WebQueryBuilder.query(forBoardNamed: board.name,
                                                 parents: Array(parents),
                                                 tags: tags,
                                                 titles: Array(titles),
                                                 variant: variant,
                                                 avoid: avoiding,
                                                 useAI: boardUsesAI)
        usedAI = boardUsesAI && chosen != WebQueryBuilder.fallbackQuery(forBoardNamed: board.name, tags: tags, variant: variant)
        query = chosen
        thinking = false
    }
}

// MARK: - Batch tag editor

struct TagEditorSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let pinIDs: Set<UUID>

    @State private var newTag = ""

    private var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for id in pinIDs {
            guard let pin = store.pin(id) else { continue }
            for tag in pin.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { (tag: $0.key, count: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Add a tag to \(pinIDs.count) pin\(pinIDs.count == 1 ? "" : "s")") {
                    HStack {
                        NativeTextField(placeholder: "New tag", text: $newTag, autocapitalization: .none, autoFocus: true) {
                            addTag()
                        }
                        Button("Add", action: addTag)
                            .buttonStyle(.borderless)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    // Matching tags as you type: yours first, then the AI's — only from pins on
                    // the same side, so hidden pins get hidden tags and normal pins never do.
                    let suggested = store.tagSuggestions(matching: newTag,
                                                         excluding: tagCounts.filter { $0.count == pinIDs.count }.map { $0.tag },
                                                         scope: pinsScope)
                    if !suggested.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(suggested) { suggestion in
                                Button {
                                    store.addTags([suggestion.tag], to: pinIDs)
                                    newTag = ""
                                } label: {
                                    Label(suggestion.tag, systemImage: suggestion.isUser ? "person" : "sparkles")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                                .tint(suggestion.isUser ? settings.accentColor : Color.secondary)
                            }
                        }
                    }
                }
                Section("Tags on the selected pins") {
                    if tagCounts.isEmpty {
                        Text("No tags yet.").foregroundStyle(.secondary)
                    }
                    ForEach(tagCounts, id: \.tag) { entry in
                        HStack {
                            Image(systemName: "tag")
                            Text(entry.tag)
                            Spacer()
                            Text("\(entry.count)/\(pinIDs.count)")
                                .foregroundStyle(.secondary)
                            Button {
                                store.removeTag(entry.tag, from: pinIDs)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(entry.tag)")
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The side of the library these pins are on (that of the first one found).
    private var pinsScope: PinScope {
        for id in pinIDs { if let pin = store.pin(id) { return store.scope(of: pin) } }
        return .visible
    }

    private func addTag() {
        store.addTags([newTag], to: pinIDs)
        newTag = ""
    }
}
