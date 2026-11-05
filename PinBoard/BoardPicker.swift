//
//  BoardPicker.swift  —  PinBoard
//
//  The sheet for choosing a board: adding, moving or saving pins, and moving a board
//  into another. It lists one side of the library (normal or hidden), with "Last used"
//  and "Suggested" shortcuts, a search field that filters the boards by name, and a
//  way to create a board or sub-board on the spot. (Moved here from BoardPage.swift.)
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Board picker

/// A sheet listing the boards of one side of the library (normal or hidden) to
/// pick one, in the same order as the Boards page (favorites first). Boards with
/// sub-boards get a chevron: sub-boards start collapsed and open when you tap it.
/// The "+" on a row creates a sub-board inside that board and picks it straight
/// away. At the top, next to the "none" row, two shortcuts: the board chosen last
/// time, and — when `suggestFor` names the pins being added or moved — the board
/// they most likely belong on (highlighted; it is only a suggestion, nothing is
/// done until you tap it). The choice is remembered for next time.
///
/// A search field stays at the top: typing filters every board of this side by name
/// (capitals and accents don't matter), sub-boards with their parents' names under them.
/// The sheet has a solid background in every size: on iOS 26 a half-height sheet is
/// see-through glass that turns solid once you drag or scroll it, and the owner found
/// the see-through look hard to read.
struct BoardPickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinAccent) private var accent

    var title: String
    var noneLabel: String? = "No board (Unsorted)"     // nil: no "none" row (e.g. "Add to board…")
    var excluded: Set<UUID> = []
    var scope: PinScope = .visible                      // only the boards of this side of the library
    var suggestFor: Set<UUID> = []                      // the pins being added/moved; non-empty → "Suggested" row
    var onSelect: (UUID?) -> Void

    @State private var newBoardName = ""
    /// The "New board" name copies the search words until the person types in it themselves
    /// (and again once they empty it), so making a board from a search needs no retyping.
    @State private var nameFollowsSearch = true
    @State private var expanded: Set<UUID> = []
    @State private var addingUnder: UUID? = nil
    @State private var newSubBoardName = ""
    @State private var opened = false
    @State private var suggestion: BoardSuggestion? = nil
    @State private var searchText = ""

    /// The search words, trimmed; empty when not searching.
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Rows whose parents are all expanded.
    private func visibleRows(_ rows: [BoardRow]) -> [BoardRow] {
        let listed = Set(rows.map { $0.board.id })
        return rows.filter { row in
            var parent = row.board.parentID
            var depth = 0
            while let p = parent, listed.contains(p), depth < 30 {   // a hidden root's normal parent is not listed
                if !expanded.contains(p) { return false }
                parent = store.board(p)?.parentID
                depth += 1
            }
            return true
        }
    }

    var body: some View {
        let rows = store.boardRows(scope: scope, sort: settings.boardSort)
        let listed = Set(rows.map { $0.board.id })
        let lastChosen = settings.lastBoardID.flatMap { listed.contains($0) ? $0 : nil }
        NavigationStack {
            List {
                topSection(listed: listed, lastChosen: lastChosen)
                if query.isEmpty {
                    boardsSection(rows: rows, lastChosen: lastChosen)
                } else {
                    searchSection(rows: rows, listed: listed)
                }
                newBoardSection
            }
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .onChange(of: searchText) { followSearch() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { openOnLastChosen() }
        }
        .presentationDetents([.medium, .large])
        // Solid at every height: the same look iOS gives the sheet once it is scrolled or
        // pulled up, so it no longer changes (and stays easy to read) as you move it.
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .task {
            // Worked out in the background; the row appears when it is ready.
            guard !suggestFor.isEmpty else { return }
            suggestion = await store.suggestedBoard(for: suggestFor, scope: scope)
        }
    }

    /// "None", then the shortcuts: "Last used" and the highlighted "Suggested" (one row when they are the same board).
    @ViewBuilder
    private func topSection(listed: Set<UUID>, lastChosen: UUID?) -> some View {
        let last = lastChosen.flatMap { excluded.contains($0) ? nil : store.board($0) }
        let suggested = suggestion.flatMap { found in
            listed.contains(found.board.id) && !excluded.contains(found.board.id) ? found : nil
        }
        // While searching, only the "none" row stays above the results (the shortcuts would push them down).
        let searching = !query.isEmpty
        if noneLabel != nil || (!searching && (last != nil || suggested != nil)) {
            Section {
                if let noneLabel {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label(noneLabel, systemImage: "tray")
                    }
                }
                if !searching, let suggested {
                    shortcutRow(board: suggested.board, suggested: suggested,
                                lastUsed: suggested.board.id == last?.id)
                        .listRowBackground(accent.opacity(0.14))
                }
                if !searching, let last, last.id != suggested?.board.id {
                    shortcutRow(board: last, suggested: nil, lastUsed: true)
                }
            }
        }
    }

    private func shortcutRow(board: Board, suggested: BoardSuggestion?, lastUsed: Bool) -> some View {
        Button {
            choose(board.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: suggested != nil ? "sparkles" : "clock.arrow.circlepath")
                    .foregroundStyle(accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.boardPath(board.id) ?? board.name)
                        .lineLimit(1)
                    Text(shortcutCaption(suggested: suggested, lastUsed: lastUsed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text("\(store.pinCount(in: board.id))")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(suggested != nil ? "Suggested" : "Last used"): \(board.name)")
    }

    /// "Suggested · its tags match", "Last used", or both.
    private func shortcutCaption(suggested: BoardSuggestion?, lastUsed: Bool) -> String {
        var parts: [String] = []
        if let suggested {
            parts.append(suggested.reason.isEmpty ? "Suggested" : "Suggested · \(suggested.reason)")
        }
        if lastUsed { parts.append("Last used") }
        return parts.joined(separator: " · ")
    }

    private func boardsSection(rows: [BoardRow], lastChosen: UUID?) -> some View {
        let shown = visibleRows(rows)
        return Section(scope == .hidden ? "Hidden boards" : "Boards") {
            if shown.isEmpty {
                Text(scope == .hidden ? "No hidden boards yet — create one below." : "No boards yet — create one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { row in
                boardRow(row, isLastChosen: row.board.id == lastChosen)
                    .listRowBackground(row.board.id == lastChosen ? accent.opacity(0.14) : nil)
                if addingUnder == row.board.id {
                    subBoardField(parent: row.board)
                }
            }
        }
    }

    private var newBoardSection: some View {
        Section(scope == .hidden ? "New hidden board" : "New board") {
            HStack {
                NativeTextField(placeholder: "Board name", text: typedBoardName) {
                    createBoard()
                }
                Button("Create") { createBoard() }
                    .buttonStyle(.borderless)
                    .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if nameFollowsSearch, newBoardName.isEmpty, let existing = existingBoard(named: query) {
                Text("“\(existing.name)” already exists — tap it above to choose it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: New board name from the search

    /// The "New board" field as the person types in it: anything they type is theirs and the
    /// search no longer changes it; emptying it hands it back to the search (from the next
    /// change of the search words on, so the field can still be cleared).
    private var typedBoardName: Binding<String> {
        Binding(
            get: { newBoardName },
            set: { (typed: String) in
                newBoardName = typed
                nameFollowsSearch = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }

    /// Copies the search words into the "New board" name, unless the person typed their own
    /// name, or a board of this side already has exactly that name (no duplicate is offered).
    private func followSearch() {
        guard nameFollowsSearch else { return }
        let words = query
        newBoardName = existingBoard(named: words) == nil ? words : ""
    }

    /// A board of this picker's side whose name is the search words, capitals and accents aside.
    private func existingBoard(named words: String) -> Board? {
        if words.isEmpty { return nil }
        let rows = store.boardRows(scope: scope)
        return rows.first { (row: BoardRow) -> Bool in BoardPickerSheet.name(row.board.name, isSameAs: words) }?.board
    }

    /// Whether two board names are the same, ignoring capitals and accents ("cafe" = "Café").
    nonisolated static func name(_ name: String, isSameAs other: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.compare(other, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // MARK: Search

    /// The search field pinned above the list, with PinBoard's own keyboard under it when that is on.
    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NativeTextField(placeholder: "Search boards",
                                text: $searchText,
                                returnKey: .search,
                                autocapitalization: .none,
                                autocorrection: false,
                                showsClearButton: false,
                                accessibilityLabel: "Search boards") {
                    NativeTextField.endEditing()
                }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// Every board of this side whose name holds the search words, sub-boards included
    /// whether or not their parent is open, in the list's usual order.
    private func searchSection(rows: [BoardRow], listed: Set<UUID>) -> some View {
        let words = query
        let matches = rows.filter { (row: BoardRow) -> Bool in BoardPickerSheet.name(row.board.name, matches: words) }
        return Section(scope == .hidden ? "Matching hidden boards" : "Matching boards") {
            if matches.isEmpty {
                Text("No boards match")
                    .foregroundStyle(.secondary)
            }
            ForEach(matches) { row in
                searchRow(row, parents: parentNames(of: row.board, listed: listed))
            }
        }
    }

    /// One search result: the board's name, and for a sub-board the boards it lives in.
    private func searchRow(_ row: BoardRow, parents: [String]) -> some View {
        Button {
            choose(row.board.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: row.board.isSecret ? "lock.fill" : (row.depth == 0 ? "folder.fill" : "folder"))
                    .foregroundStyle(row.depth == 0 ? accent : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.board.name)
                        .lineLimit(1)
                    if !parents.isEmpty {
                        Text("in " + parents.joined(separator: " › "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text("\(store.pinCount(in: row.board.id))")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(excluded.contains(row.board.id))
        .accessibilityLabel(searchRowLabel(row.board.name, parents: parents))
    }

    /// "Paris, in Travel › Europe" for VoiceOver.
    private func searchRowLabel(_ name: String, parents: [String]) -> String {
        if parents.isEmpty { return name }
        return name + ", in " + parents.joined(separator: " › ")
    }

    /// The names of the boards a board lives in, outermost first. Only boards this picker
    /// lists count, so a hidden board's path never names the normal board it sits in.
    private func parentNames(of board: Board, listed: Set<UUID>) -> [String] {
        var names: [String] = []
        var parent = board.parentID
        while let id = parent, listed.contains(id), names.count < 30, let found = store.board(id) {
            names.insert(found.name, at: 0)
            parent = found.parentID
        }
        return names
    }

    /// Whether a board's name holds the search words, ignoring capitals and accents
    /// ("cafe" finds "Café", "TRAVEL" finds "Travel").
    nonisolated static func name(_ name: String, matches words: String) -> Bool {
        if words.isEmpty { return true }
        return name.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Opens the way to the board chosen last time (its parents expanded), once.
    private func openOnLastChosen() {
        guard !opened else { return }
        opened = true
        guard let id = settings.lastBoardID, store.boardRows(scope: scope).contains(where: { $0.board.id == id }) else { return }
        for ancestor in store.path(to: id).dropLast() { expanded.insert(ancestor.id) }
    }

    private func boardRow(_ row: BoardRow, isLastChosen: Bool) -> some View {
        // Only sub-boards of this picker's side (a normal picker never counts hidden ones).
        let childCount = (scope == .hidden ? store.children(of: row.board.id) : store.visibleChildren(of: row.board.id)).count
        return HStack(spacing: 8) {
            if childCount > 0 {
                Button {
                    withAnimation {
                        if expanded.contains(row.board.id) {
                            expanded.remove(row.board.id)
                        } else {
                            expanded.insert(row.board.id)
                        }
                    }
                } label: {
                    Image(systemName: expanded.contains(row.board.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded.contains(row.board.id) ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: 20)
            }
            Button {
                choose(row.board.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: row.board.isSecret ? "lock.fill" : (row.depth == 0 ? "folder.fill" : "folder"))
                        .foregroundStyle(row.depth == 0 ? accent : Color.secondary)
                    Text(row.board.name)
                    if isLastChosen {
                        Text("last used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if childCount > 0 {
                        Text("\(childCount) sub")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(store.pinCount(in: row.board.id))")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .disabled(excluded.contains(row.board.id))
            Button {
                withAnimation {
                    addingUnder = addingUnder == row.board.id ? nil : row.board.id
                    newSubBoardName = ""
                }
            } label: {
                Image(systemName: addingUnder == row.board.id ? "minus.circle" : "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(excluded.contains(row.board.id))
            .accessibilityLabel("New sub-board inside \(row.board.name)")
        }
        .padding(.leading, CGFloat(row.depth) * 18)
    }

    private func subBoardField(parent: Board) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NativeTextField(placeholder: "New sub-board in “\(parent.name)”", text: $newSubBoardName, autoFocus: true) {
                    createSubBoard(in: parent)
                }
                Button("Create") { createSubBoard(in: parent) }
                    .buttonStyle(.borderless)
                    .disabled(newSubBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.leading, 28)
    }

    /// Picks a board, and remembers it so the next picker opens there.
    private func choose(_ boardID: UUID) {
        settings.lastBoardID = boardID
        onSelect(boardID)
        dismiss()
    }

    /// A new board on this picker's side of the library (hidden in a hidden picker).
    private func createBoard() {
        if let board = store.addBoard(name: newBoardName, secret: scope == .hidden) {
            // Back to the start (the sheet closes too, which starts it fresh next time).
            newBoardName = ""
            nameFollowsSearch = true
            searchText = ""
            choose(board.id)
        }
    }

    /// Inside a hidden board a sub-board is hidden with it.
    private func createSubBoard(in parent: Board) {
        if let board = store.addBoard(name: newSubBoardName, parentID: parent.id) {
            choose(board.id)
        }
    }
}
