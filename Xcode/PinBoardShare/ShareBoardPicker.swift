//
//  ShareBoardPicker.swift  —  PinBoard share extension
//
//  The share sheet's board list, made to look and behave like the app's own board picker
//  (BoardPicker.swift — it can't be shared: that one reads the library itself): a search field
//  pinned on top; "No board (Unsorted)" and the "Suggested" boards at the top, highlighted; then
//  "Boards" in the app's order, sub-boards collapsed under a chevron, each with its folder, its
//  count of sub-boards and pins, and a "+" to make a sub-board inside it; while searching,
//  "Matching boards" with each one's parents ("in Travel › Europe"); and "New board" at the end,
//  whose name follows the search words until you type your own. "Last used" (the board the last
//  share of this profile went to) is a shortcut only: a share always starts on "No board". Boards made here are made by
//  PinBoard when it takes the share in (ShareInbox.swift), never hidden ones.
//  Also the profile list, like Settings › Library › Profiles.
//

import SwiftUI
import UIKit

struct BoardChoiceList: View {
    @ObservedObject var model: ShareModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var newBoardName = ""
    /// The "New board" name copies the search words until the person types in it themselves (and
    /// again once they empty it), as in the app.
    @State private var nameFollowsSearch = true
    @State private var expanded: Set<UUID> = []
    @State private var addingUnder: UUID? = nil
    @State private var newSubBoardName = ""
    @State private var opened = false

    private let accent = ShareView.accent
    private var rows: [ShareBoardList.Board] { model.boardList?.boards ?? [] }
    /// The search words, trimmed; empty when not searching.
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            topSection
            if query.isEmpty {
                boardsSection
            } else {
                searchSection
            }
            newBoardSection
        }
        .safeAreaInset(edge: .top, spacing: 0) { searchBar }
        .onChange(of: searchText) { followSearch() }
        .navigationTitle("Board")
        .navigationBarTitleDisplayMode(.inline)
        .solidShareBackground()
        .onAppear { openOnChosen() }
    }

    // MARK: Top: "No board" and the suggestions

    /// "No board (Unsorted)", then the suggested boards (left out while searching, as in the app).
    private var topSection: some View {
        Section {
            Button {
                choose(nil)
            } label: {
                Label("No board (Unsorted)", systemImage: "tray")
            }
            .listRowBackground(model.boardID == nil ? accent.opacity(0.14) : nil)
            if query.isEmpty {
                ForEach(model.suggestions) { (suggestion: ShareSuggestion) in
                    suggestedRow(suggestion)
                        .listRowBackground(accent.opacity(0.14))
                }
                if let last = model.lastUsedBoard, !model.suggestions.contains(where: { $0.board.id == last.id }) {
                    lastUsedRow(last)
                        .listRowBackground(last.id == model.boardID ? accent.opacity(0.14) : nil)
                }
            }
        }
    }

    private func suggestedRow(_ suggestion: ShareSuggestion) -> some View {
        let board = suggestion.board
        return Button {
            choose(board.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.boardList?.path(of: board.id) ?? board.name)
                        .lineLimit(1)
                    Text(board.id == model.lastUsedID ? "Suggested · \(suggestion.reason) · Last used" : "Suggested · \(suggestion.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                count(of: board)
            }
        }
        .accessibilityLabel("Suggested: \(board.name)")
    }

    /// The board the last share went to, as the app's "Last used" row shows it.
    private func lastUsedRow(_ board: ShareBoardList.Board) -> some View {
        Button {
            choose(board.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.boardList?.path(of: board.id) ?? board.name)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("Last used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                count(of: board)
            }
        }
        .accessibilityLabel("Last used: \(board.name)")
    }

    // MARK: Boards

    private var boardsSection: some View {
        let shown = visibleRows
        return Section("Boards") {
            if shown.isEmpty {
                Text("No boards yet — create one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { (board: ShareBoardList.Board) in
                boardRow(board)
                    .listRowBackground(board.id == model.boardID ? accent.opacity(0.14) : nil)
                if addingUnder == board.id {
                    subBoardField(parent: board)
                }
            }
        }
    }

    /// Rows whose parents are all expanded.
    private var visibleRows: [ShareBoardList.Board] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { (first, _) in first })
        return rows.filter { (board: ShareBoardList.Board) -> Bool in
            var parent = board.parentID
            var depth = 0
            while let id = parent, depth < 30 {
                if !expanded.contains(id) { return false }
                parent = byID[id]?.parentID
                depth += 1
            }
            return true
        }
    }

    private func childCount(of board: ShareBoardList.Board) -> Int {
        rows.filter { $0.parentID == board.id }.count
    }

    private func boardRow(_ board: ShareBoardList.Board) -> some View {
        let children = childCount(of: board)
        return HStack(spacing: 8) {
            if children > 0 {
                Button {
                    withAnimation { toggle(board.id) }
                } label: {
                    Image(systemName: expanded.contains(board.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded.contains(board.id) ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: 20)
            }
            Button {
                choose(board.id)
            } label: {
                HStack(spacing: 8) {
                    folder(depth: board.depth)
                    Text(board.name).foregroundStyle(Color.primary)
                    if board.id == model.lastUsedID {
                        Text("last used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if children > 0 {
                        Text("\(children) sub")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    count(of: board)
                }
            }
            .buttonStyle(.borderless)
            Button {
                withAnimation {
                    addingUnder = addingUnder == board.id ? nil : board.id
                    newSubBoardName = ""
                }
            } label: {
                Image(systemName: addingUnder == board.id ? "minus.circle" : "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("New sub-board inside \(board.name)")
        }
        .padding(.leading, CGFloat(board.depth) * 18)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private func folder(depth: Int) -> some View {
        Image(systemName: depth == 0 ? "folder.fill" : "folder")
            .foregroundStyle(depth == 0 ? accent : Color.secondary)
    }

    /// The board's pin count, as the app shows it; a board made in the share sheet says "new".
    @ViewBuilder
    private func count(of board: ShareBoardList.Board) -> some View {
        if let pins = board.pinCount {
            Text("\(pins)").foregroundStyle(.secondary)
        } else {
            Text("new").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func subBoardField(parent: ShareBoardList.Board) -> some View {
        HStack {
            TextField("New sub-board in “\(parent.name)”", text: $newSubBoardName)
                .onSubmit { createSubBoard(in: parent) }
            Button("Create") { createSubBoard(in: parent) }
                .buttonStyle(.borderless)
                .disabled(newSubBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 28)
    }

    // MARK: Search

    /// The search field pinned above the list, as in the app.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search boards", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search boards")
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// Every board whose name holds the search words (capitals and accents don't matter), sub-boards
    /// included whether or not their parent is open, in the list's usual order.
    private var searchSection: some View {
        let words = query
        let matches = rows.filter { (board: ShareBoardList.Board) -> Bool in
            board.name.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return Section("Matching boards") {
            if matches.isEmpty {
                Text("No boards match")
                    .foregroundStyle(.secondary)
            }
            ForEach(matches) { (board: ShareBoardList.Board) in
                searchRow(board)
            }
        }
    }

    private func searchRow(_ board: ShareBoardList.Board) -> some View {
        let parents = parentNames(of: board)
        return Button {
            choose(board.id)
        } label: {
            HStack(spacing: 8) {
                folder(depth: board.depth)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.name)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if !parents.isEmpty {
                        Text("in " + parents.joined(separator: " › "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                count(of: board)
            }
        }
        .accessibilityLabel(parents.isEmpty ? board.name : board.name + ", in " + parents.joined(separator: " › "))
    }

    /// The names of the boards a board lives in, outermost first.
    private func parentNames(of board: ShareBoardList.Board) -> [String] {
        var names: [String] = []
        var parent = board.parentID
        while let id = parent, names.count < 30, let found = rows.first(where: { $0.id == id }) {
            names.insert(found.name, at: 0)
            parent = found.parentID
        }
        return names
    }

    // MARK: New board

    private var newBoardSection: some View {
        Section("New board") {
            HStack {
                TextField("Board name", text: typedBoardName)
                    .onSubmit { createBoard() }
                Button("Create") { createBoard() }
                    .buttonStyle(.borderless)
                    .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if nameFollowsSearch, newBoardName.isEmpty, let existing = model.existingBoard(named: query) {
                Text("“\(existing.name)” already exists — tap it above to choose it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The "New board" field as the person types in it: anything they type is theirs and the search
    /// no longer changes it; emptying it hands it back to the search.
    private var typedBoardName: Binding<String> {
        Binding(
            get: { newBoardName },
            set: { (typed: String) in
                newBoardName = typed
                nameFollowsSearch = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }

    /// Copies the search words into the "New board" name, unless the person typed their own, or a
    /// board already has exactly that name (no duplicate is offered).
    private func followSearch() {
        guard nameFollowsSearch else { return }
        let words = query
        newBoardName = model.existingBoard(named: words) == nil ? words : ""
    }

    private func createBoard() {
        guard let id = model.makeBoard(named: newBoardName, inside: nil) else { return }
        newBoardName = ""
        nameFollowsSearch = true
        searchText = ""
        choose(id)
    }

    private func createSubBoard(in parent: ShareBoardList.Board) {
        guard let id = model.makeBoard(named: newSubBoardName, inside: parent.id) else { return }
        choose(id)
    }

    // MARK: Choosing

    private func choose(_ id: UUID?) {
        model.boardID = id
        dismiss()
    }

    /// Opens the way to the chosen board (its parents expanded), once.
    private func openOnChosen() {
        guard !opened else { return }
        opened = true
        var parent = model.boardID.flatMap { id in rows.first { $0.id == id }?.parentID }
        while let id = parent, expanded.count < 30 {
            expanded.insert(id)
            parent = rows.first { $0.id == id }?.parentID
        }
    }
}

/// The profiles, as Settings › Library › Profiles shows them: a filled circle on the chosen one, "Current"
/// on the one open in PinBoard. Choosing another swaps the boards and resets the board.
struct ProfileChoiceList: View {
    @ObservedObject var model: ShareModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(model.profiles?.profiles ?? []) { (profile: ShareProfiles.Profile) in
                    row(profile)
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Each profile is a library of its own, with its own boards. What you save goes to the profile chosen here; for a profile that isn't open in PinBoard, it waits until you open that profile.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .solidShareBackground()
    }

    private func row(_ profile: ShareProfiles.Profile) -> some View {
        let chosen = profile.id == model.profileID
        return Button {
            model.chooseProfile(profile.id)
            dismiss()
        } label: {
            HStack {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? ShareView.accent : Color.secondary)
                Text(profile.name).foregroundStyle(Color.primary)
                Spacer()
                if profile.id == model.profiles?.current {
                    Text("Current").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
