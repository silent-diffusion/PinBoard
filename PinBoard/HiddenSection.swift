//
//  HiddenSection.swift  —  PinBoard
//
//  The Hidden section (hidden pins and boards behind Face ID / Touch ID / passcode):
//  whether it is unlocked (HiddenAccess), the lock screen and the gate that asks
//  (`.hiddenGate()`), and the section's own page with its segments, selecting, ⋯ menu
//  and "Convert videos…" question. One feature with its own rules, so its own file.
//

import SwiftUI
import PhotosUI
import LocalAuthentication
import UIKit
import Foundation

// MARK: - Hidden (hidden pins and boards behind Face ID / Touch ID / passcode)

/// Whether Hidden is unlocked. Once unlocked, it stays unlocked until the app goes to the
/// background or "Lock now" is chosen in Hidden's ⋯ menu (both call `lock()`). It never locks
/// by itself while in use: that would swap the screen for the lock screen and close any sheet
/// open there, typed text and all. Views observe it, so titles and gates update.
@MainActor
final class HiddenAccess: ObservableObject {
    static let shared = HiddenAccess()

    @Published private(set) var isUnlocked = false
    /// The system's Face ID / Touch ID / passcode prompt is up. It makes the app "inactive" while
    /// it shows, like the App Switcher does — but only the lock screen is behind it, so the App
    /// Switcher cover (`hiddenPrivacyCover`) leaves the screen as it is meanwhile.
    @Published private(set) var isAsking = false
    private var askCount = 0 { didSet { isAsking = askCount > 0 } }   // two gates may ask at once

    func lock() { isUnlocked = false }

    /// Asks the system (Face ID, Touch ID or the passcode). A device without a
    /// passcode cannot lock anything, so it is let through.
    func unlock(reason: String) async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        var error: NSError? = nil
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return true
        }
        askCount += 1
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        askCount -= 1
        if ok { isUnlocked = true }
        return ok
    }
}

/// Shown in place of hidden content until the person has unlocked it.
struct LockedView: View {
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Hidden pins and boards are locked")
                .font(.title3.weight(.semibold))
            Text("Unlock with Face ID, Touch ID or your passcode. You can turn this off in \(SettingsCatalog.path(.lockHidden)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Asks to unlock (when the setting is on) before showing its content.
@MainActor
struct HiddenGate: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var access = HiddenAccess.shared
    @State private var asking = false

    func body(content: Content) -> some View {
        Group {
            if access.isUnlocked || !settings.lockHiddenBoards {
                content
            } else {
                LockedView { ask() }
            }
        }
        .onAppear {
            if settings.lockHiddenBoards, !access.isUnlocked { ask() }
        }
    }

    private func ask() {
        guard !asking else { return }
        asking = true
        Task { @MainActor in
            _ = await access.unlock(reason: "Show your hidden pins and boards")
            asking = false
        }
    }
}

extension View {
    /// Requires an unlock (Face ID / passcode) when Hidden is locked in Settings.
    func hiddenGate() -> some View {
        modifier(HiddenGate())
    }
}

enum HiddenSegment: String, CaseIterable, Identifiable {
    case all, unsorted, boards, smart, search
    var id: String { rawValue }
}

/// The Hidden section (Boards › ⋯ › Hidden…), behind Face ID when that is on
/// in Settings: hidden pins (all of them, or those on no board), hidden boards,
/// hidden smart boards and a search over hidden pins. Whatever is added with +
/// or dropped here goes straight into Hidden.
struct HiddenSectionView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var boardsNav: BoardsNavigation   // Duplicates / Recently Deleted / Tags go on the Boards path
    @EnvironmentObject private var importFlow: ImportFlow        // the short message when converting videos ends
    @Environment(\.dismiss) private var dismiss

    @StateObject private var addFlags = AddPinFlags()
    @State private var segment: HiddenSegment = .all
    @State private var isSelectingPins = false
    @State private var isSelectingBoards = false
    @State private var boardSelection: Set<UUID> = []
    @State private var showNewBoard = false
    @State private var showReorder = false
    @State private var visit = UUID()                   // this opening of Hidden: All gets an order of its own
    @State private var aiPrompt: AIPrompt? = nil          // the "AI sorting" menu's questions
    @State private var askConvertVideos = false           // "Convert 3 videos to 1080p?" is being asked

    /// Favorite hidden boards (at any depth) first, then the top of Hidden, in the chosen order.
    private var hiddenBoards: [Board] { store.boardsPageBoards(scope: .hidden, sort: settings.boardSort) }

    var body: some View {
        VStack(spacing: 0) {
            // Never cut short with "…": smaller words first, a menu only at very large text sizes.
            FittingSegmentedPicker(title: "Section", selection: $segment, options: [
                SegmentOption(value: HiddenSegment.all, label: "All (\(store.hiddenPins.count))"),
                SegmentOption(value: HiddenSegment.unsorted, label: "Unsorted (\(store.unsortedPins(scope: .hidden).count))"),
                SegmentOption(value: HiddenSegment.boards, label: "Boards"),
                SegmentOption(value: HiddenSegment.smart, label: "Smart"),
                SegmentOption(value: HiddenSegment.search, label: "Search")
            ])
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            if store.isConvertingHiddenVideos {
                HiddenConversionRow()   // "Converting 2 of 5 (45%)" with Stop — only ever here
            }
            segmentContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(PinDropZone(boardIDs: [], style: .page, hidden: true))   // drops land in Hidden › Unsorted
        .modifier(AddPinPresenters(flags: addFlags, boardIDs: [], hidden: true))
        .modifier(BoardBatchActions(isSelecting: $isSelectingBoards, selection: $boardSelection, scope: .hidden,
                                    allBoardIDs: hiddenBoards.map { (board: Board) -> UUID in board.id }))
        .modifier(AISortingDialogs(prompt: $aiPrompt))
        .modifier(HiddenConvertQuestion(isAsking: $askConvertVideos, convert: { () -> Void in convertHiddenVideos() }))
        .toolbar {
            // While selecting boards, the one "Done" is in the selection bar.
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                AddPinMenu(flags: addFlags)
                moreMenu
            }
        }
        // Hidden's own sheets never show in the App Switcher (see `hiddenPrivacyCover`).
        .sheet(isPresented: $showNewBoard) {
            TextEditSheet(title: "New hidden board", placeholder: "Board name", initial: "", requiresText: true) { name in
                store.addBoard(name: name, secret: true)
            }
            .hiddenPrivacyCover(true)
        }
        .sheet(isPresented: $showReorder) {
            BoardReorderSheet(parentID: nil, scope: .hidden)
                .hiddenPrivacyCover(true)
        }
        .onChange(of: segment) { _, now in
            if now != .boards, isSelectingBoards { endBoardSelection() }
            if now != .all, now != .unsorted, isSelectingPins { isSelectingPins = false }
        }
        .hiddenGate()   // the toolbar and its sheets are inside the gate too
        .navigationTitle("Hidden")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// All: a feed (shuffled, or by date added, as chosen in ⋯ — the grid puts it in that
    /// order). Unsorted: always newest first.
    private func listedPins(unsortedOnly: Bool) -> [Pin] {
        if unsortedOnly {
            return store.unsortedPins(scope: .hidden).sorted { $0.createdAt > $1.createdAt }
        }
        return store.hiddenPins
    }

    /// What All or Unsorted says when it is empty. Unsorted says "every hidden pin is on a hidden
    /// board" only when there are hidden pins; with none at all it says what All says.
    private func emptyText(unsortedOnly: Bool) -> (title: String, message: String) {
        if unsortedOnly, !store.hiddenPins.isEmpty {
            return ("Nothing unsorted here", "Every hidden pin is on a hidden board.")
        }
        return ("No hidden pins yet",
                "Hidden pins stay out of Pins, Search, suggestions and “More like this”. Hide a pin from its ⋯ menu (or touch and hold it), add one here with +, or drag pictures here.")
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case .all, .unsorted:
            let unsortedOnly = segment == .unsorted
            let empty = emptyText(unsortedOnly: unsortedOnly)
            PinCollectionView(
                pins: listedPins(unsortedOnly: unsortedOnly),
                isSelecting: $isSelectingPins,
                emptyIcon: "eye.slash",
                emptyTitle: empty.title,
                emptyMessage: empty.message,
                scope: .hidden,
                feed: unsortedOnly ? nil : .hiddenAll(visit: visit)
            ) { _ in
                EmptyView()
            }
        case .boards:
            boardsContent
        case .smart:
            GeometryReader { geometry in
                ScrollView {
                    SmartBoardsSection(width: geometry.size.width - 28, scope: .hidden)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
        case .search:
            SearchView(scope: .hidden, isTabRoot: false)
        }
    }

    private var boardsContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if hiddenBoards.isEmpty {
                        Text("Everything on a hidden board is hidden too. Make one here, or touch and hold a board on the Boards tab and choose “Hide board”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    BoardGrid(boards: hiddenBoards, width: geometry.size.width - 28,
                              isSelecting: isSelectingBoards, selection: $boardSelection, showsParents: true,
                              onSelect: { (id: UUID) -> Void in startBoardSelection(id) }) {
                        if !isSelectingBoards {
                            NewBoardTile(title: "New hidden board") { showNewBoard = true }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            selectionItems
            Divider()
            if segment == .all || segment == .unsorted {
                pinOrderItems
                Divider()
            }
            Group {
                // Buttons, not links: a link inside a menu does not push reliably. They go on the
                // Boards path (like the pin pages opened from these screens), after Route.hidden.
                Button { boardsNav.push(.hiddenScreen(.duplicates)) } label: { Label("Duplicates", systemImage: "square.on.square") }
                Button { boardsNav.push(.hiddenScreen(.recentlyDeleted)) } label: { Label("Recently Deleted", systemImage: "trash") }
                Button { boardsNav.push(.hiddenScreen(.tags)) } label: { Label("Tags", systemImage: "tag") }
                // No AI looks at hidden pins unless Settings › Privacy & Hidden › "Include hidden pins in AI" is on.
                if settings.aiIncludesHidden {
                    AISortingMenu(target: .all(.hidden), prompt: $aiPrompt)
                        .disabled(store.hiddenPins.isEmpty)
                }
                convertVideosItem
            }
            Divider()
            Button {
                HiddenAccess.shared.lock()
                dismiss()
            } label: {
                Label("Lock now", systemImage: "lock")
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
        // (Its "Convert videos…" question hangs off the section itself: `HiddenConvertQuestion`.)
    }

    // Converting hidden videos (MediaStorage.swift). Settings converts the normal side's videos
    // only; the hidden ones are converted from here, and nothing about it ever shows in Settings
    // or on the normal side's pill.

    /// "Convert videos to 1080p…" (the chosen quality), or "Stop converting" while it runs. Offered
    /// only while originals aren't kept — hidden pins' originals are never copied to the folder,
    /// so their videos then stay as they are — and while some hidden video isn't at that quality yet.
    @ViewBuilder
    private var convertVideosItem: some View {
        if store.isConvertingHiddenVideos {
            Button {
                store.cancelConversion(scope: .hidden)
            } label: {
                Label(StorageText.stopConverting, systemImage: "stop.circle")
            }
        } else if canConvertHiddenVideos {
            Button {
                askConvertVideos = true
            } label: {
                Label(StorageText.convertMenuItem(quality: settings.videoQuality), systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(store.isBusyWithLibraryWork)   // not during an import, a sync or Settings' own conversion
        }
    }

    private var canConvertHiddenVideos: Bool {
        guard !settings.keepOriginals, settings.videoQuality != .original else { return false }
        return store.videosToConvert(to: settings.videoQuality, scope: .hidden) > 0
    }

    /// Starts converting the hidden videos. When it ends, a short message says how it went — only
    /// while Hidden is still on screen in this window (never over another tab or Settings).
    private func convertHiddenVideos() {
        store.startConvertingVideos(to: settings.videoQuality, scope: .hidden)
        guard let run = store.hiddenConversionTask else { return }
        let nav = boardsNav
        let appRouter = router
        let flow = importFlow
        Task { @MainActor in
            let summary = await run.value
            guard nav.hiddenOpenedAt != nil, appRouter.selectedTab == .boards, !appRouter.showSettings else { return }
            let text = StorageText.conversionDone(converted: summary.converted, stopped: summary.stopped)
            flow.flash(text, symbol: summary.stopped ? "stop.circle" : "checkmark.circle")
        }
    }

    @ViewBuilder
    private var selectionItems: some View {
        Button {
            if segment != .all, segment != .unsorted { segment = .all }
            withAnimation { isSelectingPins.toggle() }
        } label: {
            Label(isSelectingPins ? "Done selecting" : "Select pins", systemImage: "checkmark.circle")
        }
        .disabled(store.hiddenPins.isEmpty && !isSelectingPins)
        Button {
            if isSelectingBoards {
                endBoardSelection()
            } else {
                segment = .boards
                withAnimation { isSelectingBoards = true }
            }
        } label: {
            Label(isSelectingBoards ? "Done selecting" : "Select boards", systemImage: "checkmark.circle")
        }
        .disabled(hiddenBoards.isEmpty && !isSelectingBoards)
        Button {
            showNewBoard = true
        } label: {
            Label("New hidden board", systemImage: "folder.badge.plus")
        }
        BoardSortMenu()
        Button {
            showReorder = true
        } label: {
            Label("Reorder boards", systemImage: "arrow.up.arrow.down")
        }
        .disabled(store.rootBoards(scope: .hidden).count < 2)
    }

    /// The order of All — the same choices as the Pins tab (choosing one shows All).
    private var pinOrderItems: some View {
        FeedOrderMenuItems(feed: .hiddenAll(visit: visit)) {
            if segment != .all { segment = .all }
        }
    }

    private func endBoardSelection() {
        withAnimation {
            boardSelection = []
            isSelectingBoards = false
        }
    }

    /// "Select" in a hidden board tile's menu: selecting boards starts, with this board chosen.
    private func startBoardSelection(_ id: UUID) {
        withAnimation {
            boardSelection = [id]
            isSelectingBoards = true
        }
    }
}

/// While Hidden's "Convert videos to 1080p…" runs: "Converting 2 of 5 (45%)" with Stop, under the
/// Hidden section's tabs — the row Settings shows for the normal videos, here for the hidden ones.
/// Nothing about the hidden run ever shows in Settings or on the normal side.
private struct HiddenConversionRow: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        HStack(spacing: 8) {
            WorkProgressLine(text: rowText)
            Spacer()
            Button {
                store.cancelConversion(scope: .hidden)
            } label: {
                // Outside a list row a plain word is a small target: at least 44 points each way.
                Text("Stop")
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
    }

    /// "Converting 2 of 5 (45%)" ("Finishing up…" once the last one is done).
    private var rowText: String {
        let progress = store.hiddenConversionProgress ?? AnalysisProgress(done: 0, total: 0)
        return StorageText.convertingRow(done: progress.done, total: progress.total,
                                         percent: store.hiddenConversionPercent)
    }
}

/// Hidden's "Convert 3 videos to 1080p?" (asked from its ⋯ menu). It hangs off the section itself,
/// as the AI-sorting questions do: a question attached to a menu in the toolbar may not show on
/// every system. Without an original the larger version is gone for good, so the answer is red.
/// It closes the moment the app leaves the front, so it never shows over Hidden's privacy cover
/// in the App Switcher (see `hiddenPrivacyCover`).
@MainActor
private struct HiddenConvertQuestion: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isAsking: Bool
    /// Starts the run (the Hidden section's `convertHiddenVideos`).
    let convert: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(question, isPresented: $isAsking, titleVisibility: .visible) {
                Button("Convert", role: .destructive) { convert() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(StorageText.hiddenConvertMessage(quality: settings.videoQuality))
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { isAsking = false }
            }
    }

    /// "Convert 3 videos to 1080p?" — the hidden videos only.
    private var question: String {
        StorageText.convertQuestion(count: store.videosToConvert(to: settings.videoQuality, scope: .hidden),
                                    quality: settings.videoQuality)
    }
}
