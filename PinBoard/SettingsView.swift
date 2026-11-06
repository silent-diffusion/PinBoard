//
//  SettingsView.swift  —  PinBoard
//
//  The Settings sheet: a short list of pages (like the iOS Settings app), each page a screen of
//  its own (SettingsPages.swift). This file holds the list, how other screens open a page
//  (`SettingsDestination`), and what the pages share while Settings is open (`SettingsSession`):
//  the export and import, the library's size line and the "AI sorting" questions.
//
//  Done sits on the list only; every page has Back. Everything is saved as it changes.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Where things are in Settings
//
// The pages, their sections and every row are listed in SettingsCatalog.swift (SettingsDestination
// is there too); this file turns a page into its screen.

/// Turns a destination into its screen.
struct SettingsDestinationView: View {
    let destination: SettingsDestination

    var body: some View {
        switch destination {
        case .appearance: SettingsAppearancePage()
        case .pinsAndBoards: SettingsPinsAndBoardsPage()
        case .videos: SettingsVideosPage()
        case .links: SettingsLinksPage()
        case .ai: SettingsAIPage()
        case .explore: SettingsExplorePage()
        case .privacy: SettingsPrivacyPage()
        case .iCloudAndStorage: SettingsStoragePage()
        case .library: SettingsLibraryPage()
        case .about: SettingsAboutPage()
        default: SettingsLibraryItemView(destination: destination)
        }
    }
}

/// The screens inside a page: Library's (the ones that were rows of Settings before it had pages),
/// and Pins & boards' Home page.
struct SettingsLibraryItemView: View {
    let destination: SettingsDestination

    var body: some View {
        switch destination {
        case .profiles: ProfilesView()
        case .recentlyDeleted: RecentlyDeletedView(scope: .visible)
        case .duplicates: DuplicatesView(scope: .visible)
        case .tags: TagManagerView(scope: .visible)
        case .recover: RecoverLibraryView()
        case .homePage: SettingsHomePageView()
        default: EmptyView()
        }
    }
}

// MARK: - What the pages share

/// What Settings' screens share while the sheet is open: the library's size line (Storage shows
/// it; a folder import or "Clear" measure it again), the "AI sorting" questions, the questions and
/// sheets of the export and the import, and an export that is running. Kept here, not in one page,
/// because an export goes on when you go back to the list, and Done waits for it.
@MainActor
final class SettingsSession: ObservableObject {
    @Published var storageText = "Measuring…"
    @Published var aiPrompt: AIPrompt? = nil
    @Published var showClearConfirm = false
    /// The Cloud AI consent sheet is up, for this provider (the one being turned on or chosen).
    @Published var cloudConsentFor: CloudProvider? = nil
    /// A row to open: a search result (or another screen) asked for it; its page scrolls to it.
    @Published var target: SettingID? = nil
    /// The row lit up for a moment after it was opened that way.
    @Published var highlighted: SettingID? = nil

    // Export / import
    @Published var exporting = false
    let exportProgress = ExportProgress()
    @Published var askHidden = false
    @Published var exportFolder: URL? = nil
    @Published var exportZip: URL? = nil
    @Published var exportMessage: String? = nil
    @Published var showFolderPicker = false
    @Published var showShareSheet = false
    @Published var showImportPicker = false
    @Published var importMessage: String? = nil
    @Published var showImportMessage = false
    /// The export being made now, kept so "Stop export" can cancel it.
    var exportJob: Task<Result<(ExportOutcome, URL), Error>, Never>? = nil
    /// The profile whose library the export was made of (it counts as that library's back-up only).
    var exportProfile: UUID? = nil
}

// MARK: - The sheet

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var importFlow: ImportFlow
    @Environment(\.dismiss) private var dismiss

    /// The page or screen to open at once (nil: the list). Another screen can ask for one here.
    let opening: SettingsDestination?
    /// …or a row, whose page opens scrolled to it, lit up for a moment.
    let openingRow: SettingID?

    @StateObject private var session = SettingsSession()
    /// What is pushed on the sheet's stack: pages (`SettingsDestination`) and, inside them, pin
    /// pages (`Route`, from Possible duplicates).
    @State private var path = NavigationPath()
    @State private var openedFirstScreen = false
    /// What is typed in the search field at the top of the list.
    @State private var searchText = ""

    init(opening: SettingsDestination? = nil, row: SettingID? = nil) {
        self.opening = opening
        self.openingRow = row
    }

    var body: some View {
        NavigationStack(path: $path) {
            pageList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Settings is a sheet: Done closes it (everything is saved as it changes) — but not
                    // during an export, whose result (share or save the zip) lives in Settings.
                    // "Stop export", under the export's progress (Library), is the way out meanwhile.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .disabled(session.exporting)
                    }
                }
                .onAppear { openWhatWasAskedFor() }
                .navigationDestination(for: SettingsDestination.self) { (destination: SettingsDestination) in
                    SettingsDestinationView(destination: destination)
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        // The export's share sheet and folder picker (they open over any screen pushed here), and
        // what another profile chosen meanwhile does to the export.
        .modifier(SettingsExportSheets(session: session))
        // Import questions, results and confirmations show over Settings, and the naming-run dialogs.
        // Apply outside any NavigationStack: on a screen inside the stack, pushing another screen
        // makes the first one "disappear", and Settings would stop counting as up.
        .modifier(SettingsImportAndNaming(session: session))
        .environmentObject(session)
        // Set on the whole stack (and what the modifiers above present), so the screens pushed
        // inside Settings see it too.
        .environment(\.isInsideSettings, true)
        // Neither a swipe down nor Done closes Settings halfway through an export.
        .interactiveDismissDisabled(session.exporting)
    }

    // MARK: The list

    /// The search field, pinned at the top, and under it the pages — or, while something is
    /// typed, the rows that match it.
    private var pageList: some View {
        Form {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(SettingsDestination.groups, id: \.self) { (group: [SettingsDestination]) in
                    Section {
                        ForEach(group, id: \.self) { (destination: SettingsDestination) in
                            pageRow(destination)
                        }
                    }
                }
            } else {
                SettingsSearchResults(query: searchText) { (entry: SettingEntry) in
                    open(entry.opensAt ?? entry.id)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsSearchBar(text: $searchText)
        }
    }

    /// One row of the list: the page's symbol and name, and a few words on the right where they help.
    private func pageRow(_ destination: SettingsDestination) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(destination.title, systemImage: destination.symbol)
                Spacer()
                if let detail = SettingsView.rowDetail(destination, profileName: profiles.current.name, offline: settings.offlineMode) {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The few words on the right of a row (a plain rule; the harness tests it): the profile in
    /// use beside Library, "Offline" beside Privacy & Hidden while offline mode is on.
    nonisolated static func rowDetail(_ destination: SettingsDestination, profileName: String, offline: Bool) -> String? {
        switch destination {
        case .library: return profileName.isEmpty ? nil : profileName
        case .privacy: return offline ? "Offline" : nil
        default: return nil
        }
    }

    // MARK: Opening a page on purpose

    /// Another screen asked for something when it opened Settings: the export ("Export now" in the
    /// back-up reminder: the Library page, and the export starts once the page is up), or a page
    /// or screen named in `opening`. Done once; going back to the list doesn't push it again.
    private func openWhatWasAskedFor() {
        if router.pendingExport {
            router.pendingExport = false
            openedFirstScreen = true
            push(.library)
            let target = session
            let library = store
            let flow = importFlow
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)   // let the page finish appearing
                target.beginExport(store: library, importFlow: flow)
            }
            return
        }
        guard !openedFirstScreen else { return }
        openedFirstScreen = true
        if let openingRow {
            open(openingRow)
        } else if let opening {
            push(opening)
        }
    }

    /// Opens the row's page (from the list) and has the page scroll to the row and light it up.
    private func open(_ row: SettingID) {
        NativeTextField.endEditing()
        session.target = row
        path = NavigationPath()
        push(SettingsCatalog.entry(row).page)
    }

    private func push(_ destination: SettingsDestination) {
        for step in destination.trail {
            path.append(step)
        }
    }
}

// MARK: - The hooks on the sheet itself

/// Settings' round-8 hooks, kept out of SettingsView's modifier chain so it type-checks quickly:
/// the import questions ("Looks familiar"), results and short confirmations appear over Settings,
/// the "AI sorting" dialogs, and the storage line refreshed when a folder import finishes.
/// Attached to Settings' NavigationStack itself (the sheet's content), never to a screen inside
/// it: the import cover counts the screens it is on as they appear and disappear, and a screen
/// inside a stack "disappears" whenever another one is pushed on top of it.
private struct SettingsImportAndNaming: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @ObservedObject var session: SettingsSession

    func body(content: Content) -> some View {
        content
            .importFlowCover()   // import questions, results and confirmations show over Settings
            .modifier(AISortingDialogs(prompt: $session.aiPrompt))
            .onChange(of: importFlow.isWorking) { _, working in
                // A folder import finished: the library's size changed.
                if !working { Task { session.storageText = await store.librarySizeDescription() } }
            }
    }
}

/// A finished export's share sheet and its "Save the folder to Files" picker. Like the hooks
/// above, attached to Settings' NavigationStack (not to a page), so they open even when a
/// screen was pushed while the zip was being made. The export only counts as done — "Last
/// export", and the reminder to back up starting over — once the zip was shared or the folder
/// saved, not as soon as the zip is ready; and only for the library it was made of.
/// Another profile chosen while Settings is open is passed on: the export belongs to the old library.
@MainActor
private struct SettingsExportSheets: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var profiles: ProfileManager
    @ObservedObject var session: SettingsSession

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $session.showShareSheet) {
                // A full-size share sheet (a ShareLink in a settings row opens as a
                // cramped popover on iPad).
                if let zip = session.exportZip { shareSheet(zip) }
            }
            .sheet(isPresented: $session.showFolderPicker) {
                if let folder = session.exportFolder { folderPicker(folder) }
            }
            .onChange(of: profiles.currentID) {
                session.forgetExport()
            }
    }

    /// Counts the export once the zip went somewhere (AirDrop, Files, Mail…), not on Cancel.
    private func shareSheet(_ zip: URL) -> some View {
        let library = store
        let exported = session.exportProfile
        return ActivityShareSheet(items: [zip], isPresented: $session.showShareSheet, onComplete: { @MainActor @Sendable shared in
            if shared { SettingsSession.record(exported, in: library) }
        })
        .presentationDetents([.medium, .large])
    }

    /// The picker says whether the folder was saved: only a save counts, cancelling it is not a
    /// back-up.
    private func folderPicker(_ folder: URL) -> some View {
        let exported = session.exportProfile
        return FolderExportPicker(url: folder) { saved in
            session.showFolderPicker = false
            if saved { SettingsSession.record(exported, in: store) }
        }
    }
}

// MARK: - The export

extension SettingsSession {
    /// Counts the export as a back-up of the library in use — only if that is still the library
    /// it was made of (another window may have switched profiles meanwhile).
    static func record(_ profile: UUID?, in store: LibraryStore) {
        guard let profile, store.isCurrentProfile(profile) else { return }
        store.recordExport()
    }

    /// Asks about hidden boards first, when there are any.
    func beginExport(store: LibraryStore, importFlow: ImportFlow) {
        guard !exporting else { return }
        if store.hasHiddenContent {
            askHidden = true
        } else {
            runExport(includeHidden: true, store: store, importFlow: importFlow)
        }
    }

    func runExport(includeHidden: Bool, store: LibraryStore, importFlow: ImportFlow) {
        exporting = true
        exportMessage = nil
        exportZip = nil
        exportFolder = nil
        exportProfile = store.profileID   // the library this export is a back-up of
        let pins = store.exportPins(includeHidden: includeHidden)
        let boards = store.boards
        let images = store.imagesURL
        let prints = store.printsURL
        let exif = store.exifURL
        let videos = store.videosURL
        let json = store.exportJSON(includeHidden: includeHidden)
        let hidden = includeHidden ? Set<UUID>() : store.hiddenBoardIDs
        let progressBox = exportProgress
        let run = progressBox.start(total: pins.count)   // this export's number (see `stopExport`)
        // Reported per pin from the export's thread; about 200 updates at most reach the screen.
        let step = max(1, pins.count / 200)
        let report: @Sendable (Int, Int) -> Void = { done, total in
            guard done == total || done % step == 0 else { return }
            Task { @MainActor in progressBox.report(done: done, total: total, run: run) }
        }
        Task { @MainActor in
            guard progressBox.isCurrent(run) else { return }   // stopped before it began
            // Made off the main thread, and kept so "Stop export" can cancel it.
            let job = Task.detached(priority: .userInitiated) { () -> Result<(ExportOutcome, URL), Error> in
                do {
                    let outcome = try LibraryExporter.buildFolder(pins: pins, boards: boards, imagesURL: images, printsURL: prints,
                                                                   exifURL: exif, videosURL: videos, libraryJSON: json, hiddenBoardIDs: hidden,
                                                                   progress: report)
                    let bytes = LibraryStore.folderSize(at: outcome.folderURL)   // the bar's last part (ExportProgress)
                    Task { @MainActor in progressBox.beginZip(bytes: bytes, run: run) }
                    let zip = try LibraryExporter.zip(folder: outcome.folderURL)
                    return .success((outcome, zip))
                } catch {
                    return .failure(error)
                }
            }
            exportJob = job
            let result: Result<(ExportOutcome, URL), Error> = await job.value
            // Stopped meanwhile ("Stop export", or another profile chosen): whatever it ended
            // with — a zip, or the error a cancelled export stops with — is not shown.
            guard progressBox.isCurrent(run) else { return }
            exportJob = nil
            exporting = false
            switch result {
            case .success(let (outcome, zip)):
                exportFolder = outcome.folderURL
                exportZip = zip
                exportMessage = outcome.readyMessage   // also says when pins were left out for missing files
                offerZip(importFlow: importFlow)
            case .failure(let error):
                // A stopped export is not a failure (its own row already went quiet).
                if error is CancellationError { return }
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// The zip is ready. The share sheet opens by itself, wherever Settings is scrolled to (or
    /// when the export was started from the back-up reminder and its row was never on screen) —
    /// unless something else is shown over Settings right now: a share sheet can't open over
    /// that, so a short confirmation points to "Share the zip" instead. Either way the export is
    /// counted once the zip is shared or the folder saved (SettingsExportSheets); closing the
    /// share sheet leaves the Share and Save rows under "Your data" (Library).
    private func offerZip(importFlow: ImportFlow) {
        if somethingShowsOverSettings(importFlow: importFlow) {
            importFlow.flash("Your export is ready — tap Share the zip.")
        } else {
            showShareSheet = true
        }
    }

    /// Something is shown over Settings right now: one of its own sheets (the folder pickers,
    /// the Cloud AI consent, the share sheet), a question or a result it asks (also an import's,
    /// shown over Settings) — or anything a screen pushed inside Settings put up.
    func somethingShowsOverSettings(importFlow: ImportFlow) -> Bool {
        let sheets = showFolderPicker || cloudConsentFor != nil || showImportPicker || showShareSheet
        let questions = askHidden || showClearConfirm || showImportMessage || aiPrompt != nil
        let imports = importFlow.review != nil || importFlow.showMessage
        return sheets || questions || imports || SettingsSession.settingsIsCovered()
    }

    /// Whether the Settings sheet has something of its own over it — also what a screen pushed
    /// inside Settings put up (Rename profile, a pin page's editor…), which the flags above don't
    /// know about. The window's root shows Settings, and whatever Settings shows sits on top of
    /// that. (With two windows on an iPad, the other window's Settings counts too: then the zip
    /// waits for "Share the zip", which is harmless.)
    private static func settingsIsCovered() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.rootViewController?.presentedViewController?.presentedViewController != nil {
                return true
            }
        }
        return false
    }

    /// "Share the zip". The flag goes off first and on again a moment later: if the share sheet
    /// could not open when it was asked for before (something else was shown over Settings), the
    /// flag is still on, and turning it on again would change nothing. (The short pause lets
    /// SwiftUI see it off; set off and on in the same update, nothing would happen.)
    func shareZip() {
        showShareSheet = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            showShareSheet = true
        }
    }

    /// "Stop export": the export is cancelled (it stops early where it checks for that; one past
    /// that point finishes unseen) and everything about it is cleared, so Done works again.
    func stopExport() {
        exportProgress.stop()   // what it still reports, or hands back, is ignored from now on
        exportJob?.cancel()
        exportJob = nil
        exporting = false
        exportMessage = nil
        exportZip = nil
        exportFolder = nil
    }

    /// Another profile was chosen while Settings is open. An export belongs to the library it was
    /// made of: one still running stops, and a finished one's message and Share / Save rows go.
    func forgetExport() {
        if exporting { stopExport() }
        showShareSheet = false     // (only up here if another window switched the profile)
        showFolderPicker = false
        exportMessage = nil
        exportZip = nil
        exportFolder = nil
        exportProfile = nil
    }
}
