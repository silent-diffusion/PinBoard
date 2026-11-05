//
//  SmartBoards.swift  —  PinBoard
//
//  Smart boards: a saved search that fills itself. They live in the "Smart"
//  segment of the Boards tab (normal pins) or of the Hidden section (hidden
//  pins), can be edited, and any pin can be removed from one ("Bring back"
//  shows everything again). Their commands (Edit rule…, Bring back removed
//  pins, Delete…) are defined once, in SmartBoardCommand, for the tile's menu
//  and the page's ⋯ menu alike.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Describing a rule

extension SmartBoard {
    /// "“sunset” · Photos · Past year · in Travel"
    @MainActor
    func ruleSummary(store: LibraryStore) -> String {
        var parts: [String] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append("“\(trimmed)”") }
        if !filters.kinds.isEmpty {
            parts.append(filters.kinds.sorted { $0.rawValue < $1.rawValue }.map { $0.label }.joined(separator: "/"))
        }
        // A normal smart board never names a hidden board (its search ignores one, too).
        if let boardID = filters.boardID, isHidden || !store.isSecretBoard(boardID), let name = store.board(boardID)?.name {
            parts.append("in \(name)")
        }
        if filters.unsortedOnly { parts.append("Unsorted") }
        if filters.untaggedOnly { parts.append("Untagged") }
        if filters.withTextOnly { parts.append("With text") }
        if filters.duplicatesOnly { parts.append("Duplicates") }
        if filters.dateRange != .any { parts.append(filters.dateRange.label) }
        // Video filters: length and sound.
        if filters.duration != .any { parts.append(filters.duration.label) }
        if filters.sound != .any { parts.append(filters.sound.label) }
        if filters.sort != .relevance { parts.append(filters.sort.label) }
        return parts.isEmpty ? "Every pin" : parts.joined(separator: " · ")
    }
}

// MARK: - Smart board commands

/// One thing you can do with a smart board, defined once — words, symbol, when it can be used —
/// for its tile's touch-and-hold menu and its page's ⋯ menu.
enum SmartBoardCommand: Hashable, CaseIterable, Sendable {
    case editRule, bringBack, delete

    /// The commands in menu order (Delete… last, after a divider).
    static let menu: [SmartBoardCommand] = [.editRule, .bringBack, .delete]

    /// The same words on both menus. The ellipsis means a sheet or a question comes first.
    var title: String {
        switch self {
        case .editRule: return "Edit rule…"
        case .bringBack: return "Bring back removed pins"
        case .delete: return "Delete…"
        }
    }

    var symbol: String {
        switch self {
        case .editRule: return "pencil"
        case .bringBack: return "arrow.counterclockwise"
        case .delete: return "trash"
        }
    }

    /// A sheet or a question comes before anything changes (the title ends with "…").
    var asksFirst: Bool { self != .bringBack }

    var isDestructive: Bool { self == .delete }

    /// Bring back needs a pin that was removed from the smart board; the others always work.
    nonisolated static func available(_ command: SmartBoardCommand, removedPins: Int) -> Bool {
        command != .bringBack || removedPins > 0
    }

    /// The delete question, the same from the tile and the page. A hidden smart board is never
    /// named ("Delete this smart board?"): the question sits above the App Switcher cover.
    nonisolated static func deleteQuestion(name: String, hidden: Bool = false) -> String {
        hidden ? "Delete this smart board?" : "Delete “\(name)”?"
    }
    static let deleteButton = "Delete smart board"
    static let deleteMessage = "Only the rule is deleted; the pins it showed are not touched."
}

/// A smart board's commands as menu items. What can't be used right now follows the boards' rule
/// (`BoardCommandRules.shows`): left out of the tile's context menu, dimmed in the page's ⋯ menu.
struct SmartBoardCommandItems: View {
    let board: SmartBoard
    let commands: [SmartBoardCommand]
    let surface: BoardCommandSurface
    let onCommand: (SmartBoardCommand) -> Void

    var body: some View {
        ForEach(shownCommands, id: \.self) { command in
            if command.isDestructive {
                Divider()
            }
            item(command)
        }
    }

    private var shownCommands: [SmartBoardCommand] {
        commands.filter { (command: SmartBoardCommand) -> Bool in
            BoardCommandRules.shows(available: isAvailable(command), on: surface)
        }
    }

    private func isAvailable(_ command: SmartBoardCommand) -> Bool {
        SmartBoardCommand.available(command, removedPins: board.excludedPinIDs.count)
    }

    private func item(_ command: SmartBoardCommand) -> some View {
        Button(role: command.isDestructive ? .destructive : nil) {
            onCommand(command)
        } label: {
            Label(command.title, systemImage: command.symbol)
        }
        .disabled(!isAvailable(command))
    }
}

// MARK: - The Smart segment of the Boards tab

struct SmartBoardsSection: View {
    @EnvironmentObject private var store: LibraryStore
    let width: CGFloat
    var scope: PinScope = .visible        // .hidden: the Hidden section's smart boards, over hidden pins

    @State private var editing: SmartBoard? = nil
    @State private var creating = false
    @State private var deleting: SmartBoard? = nil
    @State private var showDeleteConfirm = false
    @State private var showReorder = false

    var body: some View {
        let boards = store.smartBoards(scope: scope)
        VStack(alignment: .leading, spacing: 12) {
            Text(scope == .hidden
                 ? "A smart board here is a saved search over your hidden pins that fills itself. Make one here, or from Search with “Save as smart board”."
                 : "A smart board is a saved search that fills itself as your library grows. Make one here, or from the Search tab with “Save as smart board”.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            let count = max(2, min(4, Int(width / 230)))
            // Tiles line up at the top: a name on two lines makes its row taller, never its neighbors lower.
            let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(boards) { board in
                    NavigationLink(value: Route.smartBoard(board.id)) {
                        SmartBoardCardView(board: board)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        SmartBoardCommandItems(board: board, commands: SmartBoardCommand.menu, surface: .contextMenu) { command in
                            run(command, on: board)
                        }
                    }
                }
                NewBoardTile(title: scope == .hidden ? "New hidden smart board" : "New smart board") { creating = true }
            }
            if boards.count > 1 {
                Button {
                    showReorder = true
                } label: {
                    Label("Reorder smart boards", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                }
            }
        }
        // Hidden's smart boards (their names, rules and matches) never show in the App Switcher.
        .sheet(isPresented: $creating) {
            SmartBoardEditorSheet(existing: nil, scope: scope)
                .hiddenPrivacyCover(scope == .hidden)
        }
        .sheet(item: $editing) { board in
            SmartBoardEditorSheet(existing: board)
                .hiddenPrivacyCover(scope == .hidden)
        }
        .sheet(isPresented: $showReorder) {
            SmartBoardReorderSheet(scope: scope)
                .hiddenPrivacyCover(scope == .hidden)
        }
        // `deleting` stays set while the question closes, so its title doesn't flicker.
        .confirmationDialog(SmartBoardCommand.deleteQuestion(name: deleting?.name ?? "", hidden: scope == .hidden),
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(SmartBoardCommand.deleteButton, role: .destructive) {
                if let deleting { store.deleteSmartBoard(deleting.id) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(SmartBoardCommand.deleteMessage)
        }
    }

    /// A command from a tile's touch-and-hold menu.
    private func run(_ command: SmartBoardCommand, on board: SmartBoard) {
        switch command {
        case .editRule:
            editing = board
        case .bringBack:
            store.resetSmartBoard(board.id)
        case .delete:
            deleting = board
            showDeleteConfirm = true
        }
    }
}

/// A smart board tile: a collage of what it currently matches.
struct SmartBoardCardView: View {
    @EnvironmentObject private var store: LibraryStore
    let board: SmartBoard
    @State private var matches: [Pin] = []
    @State private var loaded = false
    @State private var refreshing = false
    @State private var refreshPending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CollageView(pins: Array(matches.filter { $0.hasImageFile }.prefix(4)))
                .aspectRatio(1.35, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
            Text(board.name)
                .font(.headline)
                .lineLimit(2)   // the grid lines tiles up at the top, so a long name may take two lines
            Text(loaded ? "\(matches.count) pin\(matches.count == 1 ? "" : "s") · \(board.ruleSummary(store: store))" : board.ruleSummary(store: store))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .task(id: "\(board.id)|\(board.updatedAt.timeIntervalSince1970)|\(store.contentVersion)") {
            // Library changes come in bursts (the AI tagging); wait for a pause, and
            // never throw away a search that is already running — run once more after it.
            if loaded { try? await Task.sleep(nanoseconds: 800_000_000) }
            if Task.isCancelled { return }
            if refreshing {
                refreshPending = true
                return
            }
            await loadMatches()
        }
    }

    private func loadMatches() async {
        refreshing = true
        repeat {
            refreshPending = false
            let result = await store.smartBoardPins(board.id)
            matches = result
            loaded = true
        } while refreshPending
        refreshing = false
    }
}

/// Drag to reorder the smart boards of one side of the library.
struct SmartBoardReorderSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var scope: PinScope = .visible
    @State private var ordered: [SmartBoard] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(ordered) { board in
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(.secondary)
                        Text(board.name)
                    }
                }
                .onMove { from, to in
                    ordered.move(fromOffsets: from, toOffset: to)
                    store.reorderSmartBoards(ordered.map { $0.id })
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
            .onAppear { ordered = store.smartBoards(scope: scope) }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - One smart board

struct SmartBoardView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var access = HiddenAccess.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isInsideSettings) private var isInsideSettings
    let boardID: UUID

    @State private var results: [Pin] = []
    @State private var isSelecting = false
    @State private var editing = false
    @State private var showDelete = false
    @State private var isLoading = true
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var refreshPending = false

    private var board: SmartBoard? { store.smartBoard(boardID) }

    var body: some View {
        if let board {
            Group {
                if board.isHidden {
                    content(board).hiddenGate()
                } else {
                    content(board)
                }
            }
            // A hidden smart board's name is not shown until Hidden has been unlocked.
            .navigationTitle(board.isHidden && settings.lockHiddenBoards && !access.isUnlocked ? "Hidden" : board.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            EmptyStateView(icon: "sparkles", title: "This smart board was deleted", message: "")
        }
    }

    private func content(_ board: SmartBoard) -> some View {
        // Removed, deleted and newly hidden (or unhidden) pins disappear straight away; the
        // search catches up in the background.
        let excluded = Set(board.excludedPinIDs)
        let side: PinScope = board.isHidden ? .hidden : .visible
        let shown = results.compactMap { found -> Pin? in
            guard !excluded.contains(found.id), let pin = store.livePin(found.id) else { return nil }
            return store.scope(of: pin) == side ? pin : nil
        }
        return PinCollectionView(
            pins: shown,
            isSelecting: $isSelecting,
            emptyIcon: "sparkles",
            emptyTitle: isLoading ? "Looking…" : "Nothing matches yet",
            emptyMessage: isLoading ? "" : "Pins that match the rule appear here automatically. Edit the rule from the ⋯ menu.",
            smartBoardID: boardID,
            scope: board.isHidden ? .hidden : .visible
        ) { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Label(board.ruleSummary(store: store), systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { editing = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !board.excludedPinIDs.isEmpty {
                    HStack {
                        Text("\(board.excludedPinIDs.count) pin\(board.excludedPinIDs.count == 1 ? "" : "s") removed from this smart board.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Bring back") { store.resetSmartBoard(boardID) }
                            .font(.caption)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                moreMenu(board)
            }
        }
        .sheet(isPresented: $editing) {
            SmartBoardEditorSheet(existing: board)
                .hiddenPrivacyCover(board.isHidden)   // never in the App Switcher
        }
        .confirmationDialog(SmartBoardCommand.deleteQuestion(name: board.name, hidden: board.isHidden),
                            isPresented: $showDelete, titleVisibility: .visible) {
            Button(SmartBoardCommand.deleteButton, role: .destructive) {
                store.deleteSmartBoard(boardID)
                dismiss()
            }
        } message: {
            Text(SmartBoardCommand.deleteMessage)
        }
        .onAppear { if results.isEmpty { refresh(after: 0) } }
        .onChange(of: board.updatedAt) { refresh(after: 0) }                 // the rule changed, or Bring back
        .onChange(of: store.contentVersion) { refresh(after: 0.8) }         // the library changed
    }

    /// ⋯: Select pins, the smart board's commands (the same as its tile's menu, but what can't be
    /// used right now is dimmed here), Settings…, then Delete….
    private func moreMenu(_ board: SmartBoard) -> some View {
        let commands = SmartBoardCommand.menu
        let mainCommands = commands.filter { (command: SmartBoardCommand) -> Bool in !command.isDestructive }
        let deleteCommands = commands.filter { (command: SmartBoardCommand) -> Bool in command.isDestructive }
        return Menu {
            Button {
                withAnimation { isSelecting.toggle() }
            } label: {
                Label(isSelecting ? "Done selecting" : "Select pins", systemImage: "checkmark.circle")
            }
            .disabled(results.isEmpty && !isSelecting)
            SmartBoardCommandItems(board: board, commands: mainCommands, surface: .moreMenu) { command in
                run(command)
            }
            if !isInsideSettings {   // (a smart board page reached from Settings is inside it already)
                Divider()
                Button { router.showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
            }
            SmartBoardCommandItems(board: board, commands: deleteCommands, surface: .moreMenu) { command in
                run(command)
            }
        } label: {
            MoreMenuLabel()
        }
        .accessibilityLabel("More")
    }

    /// A command from the ⋯ menu.
    private func run(_ command: SmartBoardCommand) {
        switch command {
        case .editRule:
            editing = true
        case .bringBack:
            store.resetSmartBoard(boardID)
        case .delete:
            showDelete = true
        }
    }

    /// Library changes come in bursts (the AI tagging), so a refresh waits for a
    /// pause — and never interrupts a search already running; it runs once more after it.
    private func refresh(after delay: Double) {
        if refreshTask != nil {
            refreshPending = true
            return
        }
        refreshTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            repeat {
                refreshPending = false
                let found = await store.smartBoardPins(boardID)
                results = found
                isLoading = false
            } while refreshPending
            refreshTask = nil
        }
    }
}

// MARK: - Editing a rule

/// Name, search words and filters of a smart board (new or existing).
struct SmartBoardEditorSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let existing: SmartBoard?
    let scope: PinScope                 // a new smart board is made on this side of the library
    @State private var name: String
    @State private var query: String
    @State private var filters: SearchFilters
    @State private var preview: [Pin] = []
    @State private var typingInto = 0   // built-in keyboard: 0 = name, 1 = search words
    // What the sheet opened with. Once any of it changes, a swipe down can't close the sheet
    // (and lose it); Cancel and Save still can.
    private let initialName: String
    private let initialQuery: String
    private let initialFilters: SearchFilters

    init(existing: SmartBoard?, query: String = "", filters: SearchFilters = SearchFilters(), scope: PinScope = .visible) {
        self.existing = existing
        self.scope = existing.map { $0.isHidden ? .hidden : .visible } ?? scope
        let startName = existing?.name ?? ""
        let startQuery = existing?.query ?? query
        let startFilters = existing?.filters ?? filters
        initialName = startName
        initialQuery = startQuery
        initialFilters = startFilters
        _name = State(initialValue: startName)
        _query = State(initialValue: startQuery)
        _filters = State(initialValue: startFilters)
    }

    /// Something was typed or chosen that Save hasn't kept yet.
    private var hasUnsavedInput: Bool {
        name != initialName || query != initialQuery || filters != initialFilters
    }

    private var previewKey: String {
        "\(query)|\(filters.hashValue)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name", placeholder: "e.g. Beach days", text: $name, index: 0)
                    field("Search words (optional)", placeholder: "e.g. sunset beach", text: $query, index: 1)
                    Text("Filters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SearchFilterBar(filters: $filters, showSort: true, scope: scope)
                    Divider()
                    Text(preview.isEmpty
                         ? (query.trimmingCharacters(in: .whitespaces).isEmpty && !filters.isActive ? "Add search words or a filter." : "Nothing matches right now — the board fills up as pins arrive.")
                         : "Matches now: \(preview.count) pin\(preview.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !preview.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(preview.prefix(12)) { pin in
                                    PinCardView(pin: pin)
                                        .frame(width: 110)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(existing == nil ? (scope == .hidden ? "New hidden smart board" : "New smart board") : "Edit smart board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (query.trimmingCharacters(in: .whitespaces).isEmpty && !filters.isActive))
                }
            }
            .task(id: previewKey) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty || filters.isActive else {
                    preview = []
                    return
                }
                let hits = await store.search(text, filters: filters, scope: scope)
                if Task.isCancelled { return }
                preview = hits.map { $0.pin }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasUnsavedInput)
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            NativeTextField(placeholder: placeholder, text: text, autocapitalization: index == 0 ? .sentences : .none)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Simultaneous, so the field itself still gets the tap (and the keyboard).
                .simultaneousGesture(TapGesture().onEnded { typingInto = index })
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if var board = existing {
            board.name = trimmedName
            board.query = trimmedQuery
            board.filters = filters
            store.updateSmartBoard(board)
        } else {
            store.addSmartBoard(name: trimmedName, query: trimmedQuery, filters: filters, scope: scope)
        }
        dismiss()
    }
}
