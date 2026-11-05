//
//  SearchView.swift  —  PinBoard
//
//  The Search tab: search by meaning over the library (also embedded in the Hidden section),
//  its search bar and filters, and the "Start here" card. Split out of ContentView.swift so each
//  file stays a comfortable size to paste.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - Search tab

/// Search by meaning. As the Search tab (`isTabRoot`) it has its own navigation
/// stack, title and ⋯ menu; the Hidden section embeds it (`isTabRoot: false`)
/// inside its own stack. `scope` .hidden searches hidden pins only — top tags,
/// board filter and "Save as smart board" are about hidden pins then too.
struct SearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @State private var path = NavigationPath()   // the pages open on top of the results
    let scope: PinScope
    let isTabRoot: Bool
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var isSearching = false
    @State private var isSelecting = false
    @State private var aiWords: [String] = []
    @State private var filters = SearchFilters()
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var searchToken = UUID()
    @State private var refreshPending = false      // the library changed while a search was running
    @State private var savingSmartBoard = false

    init(scope: PinScope = .visible, isTabRoot: Bool = true) {
        self.scope = scope
        self.isTabRoot = isTabRoot
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearch: Bool { !trimmedQuery.isEmpty || filters.isActive }

    /// The results as the pins are now: one deleted, or moved across the hidden line, meanwhile
    /// is gone at once (the search itself runs again a moment later).
    private var shownPins: [Pin] {
        hits.compactMap { hit -> Pin? in
            guard let pin = store.livePin(hit.pin.id), store.scope(of: pin) == scope else { return nil }
            return pin
        }
    }

    private var captions: [UUID: String] {
        var result: [UUID: String] = [:]
        for hit in hits {
            let words = hit.matches.prefix(3).joined(separator: " · ")
            result[hit.pin.id] = words.isEmpty ? (filters.sort == .relevance ? "\(Int(hit.score * 100))% match" : "") : words
        }
        return result
    }

    var body: some View {
        if isTabRoot {
            NavigationStack(path: $path) {
                results
                    .tabSwipeRoot(.search, enabled: !isSelecting)   // only as the tab's own root screen
                    .navigationTitle("Search")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button {
                                    withAnimation { isSelecting.toggle() }
                                } label: {
                                    Label(isSelecting ? "Done selecting" : "Select pins", systemImage: "checkmark.circle")
                                }
                                .disabled(shownPins.isEmpty && !isSelecting)
                                Button {
                                    savingSmartBoard = true
                                } label: {
                                    Label("Save as smart board…", systemImage: "sparkles")
                                }
                                .disabled(!hasSearch)
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
                guard let route, router.selectedTab == .search else { return }   // (see AppRouter.open)
                router.pendingRoute = nil
                path.append(route)
            }
        } else {
            results
        }
    }

    /// The search field, filters and results (with the sheet and the reactions to typing).
    private var results: some View {
        let shown = shownPins
        return PinCollectionView(
            pins: shown,
            isSelecting: $isSelecting,
            captions: captions,
            emptyIcon: !hasSearch ? "text.magnifyingglass" : "questionmark.circle",
            emptyTitle: !hasSearch ? (scope == .hidden ? "Search hidden pins" : "Search by meaning") : (isSearching ? "Searching…" : "No matches"),
            emptyMessage: !hasSearch
                ? (scope == .hidden
                   ? "Only your hidden pins are searched here. Describe what you're looking for in plain words, or use the filters."
                   : "Describe what you're looking for in plain words — “puppies at the beach”, “food”, “screenshots with text”. The on-device AI matches meaning, not just exact tags. Filters work on their own too.")
                : (isSearching ? "" : "Try different words or fewer filters, or add your own tags to pins so they're easier to find."),
            scope: scope
        ) { _ in
            VStack(alignment: .leading, spacing: 10) {
                SearchBar(placeholder: scope == .hidden ? "Search hidden pins" : "What are you looking for?",
                          text: $query,
                          onSubmit: { runSearch(after: 0) })
                SearchFilterBar(filters: $filters, showSort: true, scope: scope)

                if !hasSearch {
                    let suggestions = store.topTags(limit: 14, scope: scope)
                    if !suggestions.isEmpty {
                        Text(scope == .hidden ? "Try one of the top tags of your hidden pins" : "Try one of your library's top tags")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(suggestions, id: \.self) { tag in
                                Button(tag) { query = tag }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                } else {
                    HStack {
                        if !shown.isEmpty {
                            Text("\(shown.count) result\(shown.count == 1 ? "" : "s")\(filters.sort == .relevance ? " — best matches first" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            savingSmartBoard = true
                        } label: {
                            Label("Save as smart board", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if !aiWords.isEmpty {
                        Label("Apple Intelligence also looked for: \(aiWords.joined(separator: ", "))", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $savingSmartBoard) {
            SmartBoardEditorSheet(existing: nil, query: trimmedQuery, filters: filters, scope: scope)
                .hiddenPrivacyCover(scope == .hidden)   // Hidden › Search's words and matches: never in the App Switcher
        }
        // Typing and filters search after a short pause; library changes (new
        // tags, new pins) refresh the results a little later. Coming back to
        // this screen keeps what was there.
        .onChange(of: query) { runSearch(after: 0.3) }
        .onChange(of: filters) { runSearch(after: 0.3) }
        .onChange(of: store.contentVersion) { if hasSearch { runSearch(after: 1.5, refresh: true) } }
        .onChange(of: settings.useAppleIntelligence) { runSearch(after: 0) }
    }

    /// Typing restarts the search. A library change (`refresh`) never interrupts a
    /// search that is already running — the AI tagging changes the library several
    /// times a second — it just asks for one more run when the current one is done.
    private func runSearch(after delay: Double, refresh: Bool = false) {
        if refresh, searchTask != nil {
            refreshPending = true
            return
        }
        searchTask?.cancel()
        let text = trimmedQuery
        let activeFilters = filters
        let scope = scope
        guard hasSearch else {
            hits = []
            aiWords = []
            isSearching = false
            searchTask = nil
            return
        }
        if !refresh { isSearching = true }
        let token = UUID()
        searchToken = token
        searchTask = Task { @MainActor in
            defer {
                if searchToken == token {
                    searchTask = nil
                    if refreshPending {
                        refreshPending = false
                        runSearch(after: 1, refresh: true)
                    }
                }
            }
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            let results = await store.search(text, filters: activeFilters, scope: scope)
            if Task.isCancelled { return }
            hits = results
            aiWords = []
            isSearching = false

            // Optional second pass with related words from Apple Intelligence.
            // (Not inside Hidden unless "Include hidden pins in AI" is on.)
            if !text.isEmpty, settings.appleIntelligenceActive, scope == .visible || settings.aiIncludesHidden {
                let extra = await AppleIntelligence.relatedSearchWords(for: text)
                if Task.isCancelled || extra.isEmpty { return }
                let widened = await store.search(text, extraTerms: extra, filters: activeFilters, scope: scope)
                if Task.isCancelled { return }
                hits = widened
                aiWords = extra
            }
        }
    }
}

/// A rounded search field with one clear button, a Search button (which
/// searches straight away and puts the keyboard away).
struct SearchBar: View {
    @EnvironmentObject private var settings: AppSettings
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NativeTextField(placeholder: placeholder,
                                text: $text,
                                returnKey: .search,
                                autocapitalization: .none,
                                autocorrection: false,
                                showsClearButton: false,
                                onSubmit: onSubmit)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        fieldButtonLabel("xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                Button {
                    NativeTextField.endEditing()
                    onSubmit()
                } label: {
                    Text("Search")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        }
    }

    /// A small symbol button inside the field, easy to hit: its tap area is at least
    /// 44 × 44 pt. The negative padding hands the extra height back to the layout, so the
    /// tap area reaches above and below the symbol without making the field any taller.
    private func fieldButtonLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
    }
}

// MARK: - Start here

/// Shown on the Pins tab until the library has photos and boards. Once
/// photos are tagged it offers to create boards from their most common tags.
struct StartHereCard: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.pinAccent) private var accent
    @State private var proposals: [BoardProposal] = []
    @State private var chosen: Set<String> = []
    @State private var dismissed = false

    private var analyzing: Bool { store.livePins.contains { $0.needsAnalysis } }

    var body: some View {
        if !dismissed, store.boards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Start here", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                if store.livePins.isEmpty {
                    step(1, "Tap + to add a few photos (or drag them in).", done: false)
                    step(2, "The AI tags them on this device.", done: false)
                    step(3, "Come back here to create boards from what it found.", done: false)
                } else if analyzing {
                    step(1, "Photos added.", done: true)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Tagging your photos — board ideas appear when it's done.")
                            .font(.subheadline)
                    }
                } else if proposals.isEmpty {
                    step(1, "Photos added and tagged.", done: true)
                    Text("Add a few more photos, or create a board yourself in the Boards tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Based on your photos, these boards would sort \(proposals.reduce(0) { $0 + $1.pinIDs.count }) of them straight away:")
                        .font(.subheadline)
                    FlowLayout(spacing: 8) {
                        ForEach(proposals) { proposal in
                            proposalChip(proposal)
                        }
                    }
                    Button {
                        store.createProposedBoards(proposals.filter { chosen.contains($0.id) })
                    } label: {
                        Label("Create \(chosen.count) board\(chosen.count == 1 ? "" : "s")", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: "\(store.livePins.count)|\(analyzing)|\(store.boards.count)") {
                proposals = analyzing ? [] : store.proposeBoards()
                chosen = Set(proposals.map { $0.id })
            }
        }
    }

    /// One suggested board, switched on or off with a tap (VoiceOver says "selected" when on).
    private func proposalChip(_ proposal: BoardProposal) -> some View {
        let isChosen = chosen.contains(proposal.id)
        return Button {
            if chosen.contains(proposal.id) { chosen.remove(proposal.id) } else { chosen.insert(proposal.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                Text("\(proposal.name) · \(proposal.pinIDs.count)")
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(isChosen ? accent : Color.secondary)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func step(_ number: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - Search filters

struct SearchFilterBar: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pinAccent) private var accent
    @Binding var filters: SearchFilters
    var showSort: Bool = false
    var scope: PinScope = .visible        // the board menu lists the boards of this side of the library

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // What kind of pin: none chosen = every kind.
                ForEach(PinKind.allCases, id: \.self) { kind in
                    let isOn = filters.kinds.contains(kind)
                    Button {
                        if filters.kinds.contains(kind) { filters.kinds.remove(kind) } else { filters.kinds.insert(kind) }
                    } label: {
                        chip(kind.label, icon: kind.icon, active: isOn)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])   // VoiceOver says "selected" when on
                }
                Menu {
                    Button("Any board") { filters.boardID = nil; filters.unsortedOnly = false }
                    Button("Unsorted only") { filters.boardID = nil; filters.unsortedOnly = true }
                    Divider()
                    // Same order as the Boards page (favorites first, then the chosen sort).
                    ForEach(store.boardRows(scope: scope, sort: settings.boardSort)) { row in
                        Button(String(repeating: "  ", count: row.depth) + row.board.name) {
                            filters.boardID = row.board.id
                            filters.unsortedOnly = false
                        }
                    }
                } label: {
                    // A normal search never names a hidden board (e.g. one hidden meanwhile; the search ignores it).
                    let chosen = store.board(filters.boardID).flatMap { board in
                        scope == .hidden || !store.isSecretBoard(board.id) ? board : nil
                    }
                    chip(filters.unsortedOnly ? "Unsorted" : (chosen?.name ?? "Any board"),
                         icon: "folder", active: chosen != nil || filters.unsortedOnly)
                }
                Menu {
                    ForEach(SearchFilters.DateRange.allCases) { range in
                        Button(range.label) { filters.dateRange = range }
                    }
                } label: {
                    chip(filters.dateRange.label, icon: "calendar", active: filters.dateRange != .any)
                }
                videoChips
                toggleChip("Untagged", icon: "tag.slash", isOn: $filters.untaggedOnly)
                toggleChip("With text", icon: "text.viewfinder", isOn: $filters.withTextOnly)
                toggleChip("Duplicates", icon: "square.on.square", isOn: $filters.duplicatesOnly)
                if showSort {
                    Menu {
                        ForEach(SearchFilters.Sort.allCases) { sort in
                            Button(sort.label) { filters.sort = sort }
                        }
                    } label: {
                        chip(filters.sort.label, icon: "arrow.up.arrow.down", active: filters.sort != .relevance)
                    }
                }
                if filters.isActive || filters.sort != .relevance {
                    Button {
                        filters = SearchFilters()
                    } label: {
                        chip("Clear", icon: "xmark", active: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .tabSwipeExempt()   // scrolling the chips sideways never switches tabs
    }

    /// Video filters: how long, and with or without sound. Choosing one shows only videos.
    @ViewBuilder
    private var videoChips: some View {
        Menu {
            ForEach(SearchFilters.DurationRange.allCases) { range in
                Button(range.label) { filters.duration = range }
            }
        } label: {
            chip(filters.duration.label, icon: "timer", active: filters.duration != .any)
        }
        Menu {
            ForEach(SearchFilters.SoundFilter.allCases) { sound in
                Button(sound.label) { filters.sound = sound }
            }
        } label: {
            chip(filters.sound.label, icon: "speaker.wave.2", active: filters.sound != .any)
        }
    }

    private func toggleChip(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            chip(title, icon: icon, active: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])   // VoiceOver says "selected" when on
    }

    private func chip(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? accent.opacity(0.18) : Color(uiColor: .secondarySystemBackground), in: Capsule())
            .foregroundStyle(active ? accent : Color.primary)
    }
}
