//
//  SettingsPages2.swift  —  PinBoard
//
//  The pages of Settings for the web, privacy, sync and your data: Explore & web search, Privacy
//  & Hidden, iCloud & storage, Library and About. (The everyday pages are in SettingsPages.swift.)
//  Row names and footers come from SettingsCatalog.swift; every row is marked `.settingsRow(_:)`.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Explore & web search

/// The web image source (and its keys), web suggestions, and how "Search on the web" opens a
/// picture's search. Dimmed, not hidden, in Offline mode.
struct SettingsExplorePage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var revealKeys = false

    var body: some View {
        SettingsForm(.explore) {
            sourceSection
            suggestionsSection
            searchBrowserSection
        }
    }

    private var sourceSection: some View {
        Section {
            if settings.offlineMode {
                SettingsOfflineNote()
            }
            Picker(SettingsCatalog.title(.imageSource), selection: $settings.webSource) {
                ForEach(WebImageSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .settingsRow(.imageSource)
            sourceKeyRows
            if settings.webSource != .commons {
                Toggle(SettingsWords.showKeys, isOn: $revealKeys)
            }
            if let url = settings.webSource.signupURL {
                Link(settings.webSource.needsKey ? "Get a free key from \(settings.webSource.label)" : "About \(settings.webSource.label)",
                     destination: url)
            }
        } header: {
            SettingsHeader(section: .imageSource)
        } footer: {
            Text(sourceFooterText)
        }
        .disabled(settings.offlineMode)
    }

    /// The key (or client ID and secret) the chosen image source needs, and a line on what it gives.
    @ViewBuilder
    private var sourceKeyRows: some View {
        switch settings.webSource {
        case .commons:
            Text("Wikimedia Commons needs no key and has no practical limit. Results are openly licensed but mixed in quality.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .openverse:
            SettingsKeyField(title: SettingsCatalog.title(.openverseID), text: $settings.openverseClientID, reveal: revealKeys)
                .settingsRow(.openverseID)
            SettingsKeyField(title: SettingsCatalog.title(.openverseSecret), text: $settings.openverseClientSecret, reveal: revealKeys)
                .settingsRow(.openverseSecret)
            Text("Without credentials Openverse allows only about 5 searches per hour. Registering is free: it emails you a client ID and secret.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .pexels:
            SettingsKeyField(title: SettingsCatalog.title(.pexelsKey), text: $settings.pexelsKey, reveal: revealKeys)
                .settingsRow(.pexelsKey)
        case .pixabay:
            SettingsKeyField(title: SettingsCatalog.title(.pixabayKey), text: $settings.pixabayKey, reveal: revealKeys)
                .settingsRow(.pixabayKey)
        case .unsplash:
            SettingsKeyField(title: SettingsCatalog.title(.unsplashKey), text: $settings.unsplashKey, reveal: revealKeys)
                .settingsRow(.unsplashKey)
        }
    }

    /// What the source is for, and where keys are kept (or, when the keychain refused them, where
    /// they are kept instead).
    private var sourceFooterText: String {
        var lines = ["The source Explore, board pages and pin pages search, and “\(SettingsCatalog.title(.linkPictures))” (Links) uses."]
        if SecureStore.keychainWorks {
            lines.append("Keys are stored in the iOS Keychain and sent only to the service they belong to, over HTTPS.")
        } else {
            lines.append("The Keychain refused to store keys in this environment, so they are kept in the app's preferences instead. They are still sent only to the service they belong to, over HTTPS.")
        }
        return lines.joined(separator: " ")
    }

    private var suggestionsSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.autoLoadWeb), isOn: $settings.autoLoadWeb)
                .settingsRow(.autoLoadWeb)
            Toggle(SettingsCatalog.title(.boardWebIdeas), isOn: $settings.showBoardWebFeed)
                .settingsRow(.boardWebIdeas)
            if !settings.recentSearches.isEmpty {
                Button(SettingsCatalog.title(.clearExploreSearches)) { settings.recentSearches = [] }
                    .settingsRow(.clearExploreSearches)
            }
        } header: {
            SettingsHeader(section: .suggestions)
        } footer: {
            Text(SettingSection.suggestions.footer)
        }
        .disabled(settings.offlineMode)
    }

    /// "Search this picture on the web" opens in PinBoard's own browser or in the default browser,
    /// and a picture that lives only in the library reaches the search page by the clipboard, a
    /// folder in Files, or Photos (PinActions.swift does the handing over).
    private var searchBrowserSection: some View {
        Section {
            Picker(SettingsCatalog.title(.webSearchBrowser), selection: $settings.webSearchBrowser) {
                ForEach(WebSearchBrowser.allCases) { (browser: WebSearchBrowser) in
                    Text(browser.label).tag(browser)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(.webSearchBrowser)
            Picker(SettingsCatalog.title(.webSearchHandoff), selection: $settings.webSearchPictureHandoff) {
                ForEach(WebSearchPictureHandoff.allCases) { (handoff: WebSearchPictureHandoff) in
                    Text(handoff.label).tag(handoff)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(.webSearchHandoff)
        } header: {
            SettingsHeader(section: .webSearches)
        } footer: {
            Text(SettingsLinksText.searchFooter)
        }
        .disabled(settings.offlineMode)
    }
}

// MARK: - Privacy & Hidden

/// Offline mode, the Hidden lock and Hidden's order of pins, and what stays private.
struct SettingsPrivacyPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsForm(.privacy) {
            offlineSection
            hiddenSection
            privacySection
        }
    }

    private var offlineSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.offlineMode), isOn: $settings.offlineMode)
                .settingsRow(.offlineMode)
        } header: {
            SettingsHeader(section: .offline)
        } footer: {
            Text(settings.offlineMode
                 ? "Nothing leaves the device: Explore, web feeds, link previews, Cloud AI, iCloud sync and the speech recogniser's language download are off. On-device AI keeps working."
                 : SettingSection.offline.footer)
        }
    }

    /// The lock, and Hidden's own "Order of pins" (the same choice as in Hidden's ⋯ menu; it says
    /// nothing about what is hidden).
    private var hiddenSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.lockHidden), isOn: $settings.lockHiddenBoards)
                .settingsRow(.lockHidden)
            HiddenAISwitch(id: .hiddenAI)
                .settingsRow(.hiddenAI)
            RemoveHiddenAIRow()
                .settingsRow(.removeHiddenAI)
            SettingsOrderPicker(id: .hiddenOrder)
        } header: {
            SettingsHeader(section: .hidden)
        } footer: {
            Text(SettingSection.hidden.footer)
        }
    }

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsPrivacyText.lines, id: \.self) { (line: String) in
                    privacyLine(line)
                }
            }
            .padding(.vertical, 4)
            .settingsRow(.privacyPromises)
        } header: {
            SettingsHeader(section: .privacy)
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Remove AI tags from hidden pins": asks first, with the count, then takes out what the AI made
/// from every hidden pin of this profile (`LibraryStore.removeAIResultsFromHiddenPins`): its tags,
/// the text read in the picture, its description and a title only the AI wrote. The person's own
/// tags, titles and notes stay. Dimmed when there is nothing to remove. The message names no board.
struct RemoveHiddenAIRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @State private var asking = false

    private var count: Int { store.hiddenPinsWithAIResults.count }

    var body: some View {
        Button(SettingsCatalog.title(.removeHiddenAI), role: .destructive) { asking = true }
            .disabled(count == 0)
            .alert(RemoveHiddenAIRow.question(count), isPresented: $asking) {
                Button("Remove", role: .destructive) { remove() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your own tags, titles and notes stay.")
            }
    }

    /// "Remove AI tags from 42 hidden pins?" (a plain rule, so the harness checks it).
    nonisolated static func question(_ count: Int) -> String {
        "Remove AI tags from \(count) hidden pin\(count == 1 ? "" : "s")?"
    }

    /// "Removed AI tags from 42 hidden pins."
    nonisolated static func done(_ count: Int) -> String {
        "Removed AI tags from \(count) hidden pin\(count == 1 ? "" : "s")."
    }

    private func remove() {
        let removed = store.removeAIResultsFromHiddenPins()
        if removed > 0 { importFlow.flash(RemoveHiddenAIRow.done(removed)) }
    }
}

/// The lines of Privacy & Hidden's "Privacy" section, one each (a list, not a long block of views, so
/// it is easy to add a line, and the harness can check the words: nothing says "Safari" — the
/// browser is whichever the person made their default — and each new way a picture, a title or
/// a recording could leave PinBoard's own place has a line that says so).
enum SettingsPrivacyText {
    nonisolated static let lines: [String] = [
        "Tagging, text reading, search and suggestions run on this device.",
        "Speech in videos is written down on this device; nothing is sent anywhere.",
        "Web searches use a throwaway connection: no cookies, no cache, no tracking identifiers, HTTPS only.",
        "Only the search words leave the device — never your notes, tags or images (unless Cloud AI is on).",
        "With “Find a picture for links without one” on, a link's title is one of those search words: it goes to the image source you chose. Links in Hidden are never searched for.",
        "Keys stay in the Keychain and go only to their own service.",
        "Location data in photos is kept for export only and never sent anywhere.",
        "Offline mode switches every network feature off.",
        "A picture searched on the web opens in PinBoard's own browser, which keeps no cookies, history or cache, unless you chose your default browser.",
        "A picture that lives only in your library reaches the search page by the clipboard (gone after two minutes, on this device only) or, if you chose that, as a copy saved to Files or Photos, which stays there until you delete it. A hidden pin's picture only ever goes by the clipboard."
    ]
}

// MARK: - iCloud & storage

/// iCloud sync, keeping full files in iCloud only, the video quality (also on Videos), originals
/// in a folder, the library's size and converting the videos already there.
struct SettingsStoragePage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var cloudSync: CloudSync
    @EnvironmentObject private var session: SettingsSession

    var body: some View {
        SettingsForm(.iCloudAndStorage) {
            iCloudSection
            deviceStorageSection
            SettingsVideoQualitySection(id: .videoQuality)
            originalsSection
        }
    }

    /// Dimmed, not hidden, in Offline mode (sync stops then).
    private var iCloudSection: some View {
        Section {
            if settings.offlineMode {
                SettingsOfflineNote()
            }
            Toggle(SettingsCatalog.title(.iCloudSync), isOn: $settings.iCloudSync)
                .disabled(settings.offlineMode)
                .settingsRow(.iCloudSync)
            if settings.iCloudSync, cloudSync.isAvailable {
                iCloudRows
                    .disabled(settings.offlineMode)
            }
        } header: {
            SettingsHeader(section: .iCloud)
        } footer: {
            Text(cloudSync.explanation + (settings.iCloudSync && !cloudSync.isAvailable ? " The switch stays on and starts working once iCloud is there." : ""))
        }
    }

    @ViewBuilder
    private var iCloudRows: some View {
        HStack {
            Text("Last sync")
            Spacer()
            Text(store.lastSyncAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                .foregroundStyle(.secondary)
        }
        if cloudSync.isSyncing {
            // "Syncing with iCloud… 2,100 of 2,500" with its bar, while a sync runs, and Stop.
            HStack(spacing: 8) {
                WorkProgressLine(text: store.syncStatus ?? "Syncing with iCloud…")
                Spacer()
                Button("Stop") { cloudSync.stopSoon() }
                    .buttonStyle(.borderless)
                    .disabled(cloudSync.stopRequested)
            }
        } else {
            Button(SettingsCatalog.title(.syncNow)) {
                Task { await cloudSync.syncNow(store: store, settings: settings, full: true) }
            }
            .settingsRow(.syncNow)
        }
        if let error = cloudSync.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let files = cloudSync.filesStatus {
            WorkProgressLine(text: files)   // full pictures and videos coming after a sync (CloudChanges.swift)
        }
        NavigationLink(SettingsCatalog.title(.syncLog)) { SyncLogPage() }
            .settingsRow(.syncLog)   // what the last syncs did (CloudProfiles.swift)
    }

    /// "Optimize device storage" (Offloading.swift), right under the switch it needs.
    private var deviceStorageSection: some View {
        Section {
            OptimizeStorageRows()
        } header: {
            SettingsHeader(section: .deviceStorage)
        }
    }

    /// Originals in a folder, the library's size, "Convert existing videos…" (StorageSettingsRows,
    /// SettingsTools.swift), then how many pins there are.
    private var originalsSection: some View {
        Section {
            StorageSettingsRows(sizeText: $session.storageText)
            HStack {
                Text("Pins")
                Spacer()
                Text("\(store.visiblePins.count)").foregroundStyle(.secondary)   // hidden pins are never counted here
            }
        } header: {
            SettingsHeader(section: .originals)
        } footer: {
            Text(SettingsStorageText.footer)
        }
    }
}

/// The Storage footer: the words the storage code owns (`StorageText.footer`), then how converting
/// behaves when the person leaves the app (a pure string, so the harness can check it).
enum SettingsStorageText {
    /// A conversion is stopped when the app leaves the screen; the video is tried once more at
    /// the end of the run, and "Convert existing videos…" picks up anything still waiting.
    nonisolated static let conversionNote = "Converting runs while PinBoard is open; a video interrupted by leaving the app is tried again at the end of the run, and “Convert existing videos…” catches anything left."

    nonisolated static var footer: String {
        StorageText.footer + " " + conversionNote
    }
}

// MARK: - Library

/// Profiles, Recently Deleted, duplicates, tags, exporting and importing, recovering, and clearing.
/// (Profiles stays here: switching happens only on this page.)
struct SettingsLibraryPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var session: SettingsSession

    var body: some View {
        SettingsForm(.library) {
            profilesSection
            organiseSection
            dataSection
            recoverSection
            clearSection
        }
        .confirmationDialog("Delete every pin and board in “\(profiles.current.name)”?", isPresented: $session.showClearConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                store.clearLibrary()
                Task { session.storageText = await store.librarySizeDescription() }
            }
        } message: {
            // Says so when the full-size originals in the folder go too (iCloud & storage).
            Text(StorageText.clearLibraryMessage(folderName: settings.originalsFolderIfSet))
        }
        .confirmationDialog("Include hidden boards in the export?", isPresented: $session.askHidden, titleVisibility: .visible) {
            Button("Include hidden boards") { session.runExport(includeHidden: true, store: store, importFlow: importFlow) }
            Button("Leave them out") { session.runExport(includeHidden: false, store: store, importFlow: importFlow) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hidden pins (hidden on their own, or on a hidden board) are left out too.")
        }
        .fileImporter(isPresented: $session.showImportPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { (result: Result<[URL], Error>) in
            folderPicked(result)
        }
        .alert(session.importMessage ?? "", isPresented: $session.showImportMessage) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: Profiles and the lists

    private var profilesSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.profiles) {
                HStack {
                    Label("Profiles", systemImage: "person.2")
                    Spacer()
                    Text(profiles.current.name).foregroundStyle(.secondary)
                }
            }
            .settingsRow(.profiles)
        } footer: {
            Text(SettingSection.profiles.footer)
        }
    }

    /// Recently Deleted, Possible duplicates and your tags.
    private var organiseSection: some View {
        Section {
            countRow(.recentlyDeleted, count: store.deletedPins.count)
                .settingsRow(.recentlyDeleted)
            countRow(.duplicates, count: store.duplicatePins.count)
                .settingsRow(.duplicates)
            countRow(.tags, count: store.userTagCounts().count)
                .settingsRow(.tags)
        } footer: {
            Text(SettingSection.lists.footer)
        }
    }

    private func countRow(_ destination: SettingsDestination, count: Int) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(destination.title, systemImage: destination.symbol)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Export and import

    private var dataSection: some View {
        Section {
            exportRows
            importRows
        } header: {
            SettingsHeader(section: .yourData)
        } footer: {
            Text(dataFooterText)
        }
    }

    @ViewBuilder
    private var exportRows: some View {
        if session.exporting {
            ExportProgressRows(progress: session.exportProgress) { session.stopExport() }
        } else {
            Button {
                session.beginExport(store: store, importFlow: importFlow)
            } label: {
                Label(SettingsCatalog.title(.export), systemImage: "square.and.arrow.up")
            }
            .disabled(store.livePins.isEmpty && store.boards.isEmpty)
            .settingsRow(.export)
        }
        if let message = session.exportMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        if session.exportZip != nil {
            Button {
                session.shareZip()
            } label: {
                Label("Share the zip (AirDrop, Files…)", systemImage: "doc.zipper")
            }
            Button {
                session.showFolderPicker = true
            } label: {
                Label("Save the folder to Files…", systemImage: "folder.badge.plus")
            }
            .disabled(session.exportFolder == nil)
        }
    }

    @ViewBuilder
    private var importRows: some View {
        if importFlow.isWorking {
            // Only a normal import's progress is described here (a hidden one is never mentioned).
            let status = store.importStatusScope == .visible ? (store.importStatus ?? "") : ""
            WorkProgressLine(text: "Importing… \(status)")
        } else {
            Button {
                session.showImportPicker = true
            } label: {
                Label(SettingsCatalog.title(.importFolder), systemImage: "square.and.arrow.down")
            }
            .settingsRow(.importFolder)
        }
    }

    private var dataFooterText: String {
        var text = "The export is a folder per board (sub-boards nested), with every pin's title, tags and notes written into the JPEG's metadata, plus a library.json for an exact re-import. Zips can't be opened by the app itself — unzip them in Files first, then import the folder. “Import a folder…” takes an export or any folder of pictures, videos and text files (its sub-folders become boards); anything that looks like a pin you already have is asked about, like any import."
        if let last = store.lastExportAt {
            text += " Last export: \(last.formatted(date: .abbreviated, time: .shortened))."
        }
        if store.pinsAddedSinceExport > 0 {
            text += " \(store.pinsAddedSinceExport) pin\(store.pinsAddedSinceExport == 1 ? "" : "s") added since."
        }
        return text
    }

    private func folderPicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            // The same questions as every import (look-alikes), then a report.
            importFlow.importFolder(folder)
        case .failure(let error):
            session.importMessage = error.localizedDescription
            session.showImportMessage = true
        }
    }

    // MARK: Recover and clear

    private var recoverSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.recover) {
                HStack {
                    Label(SettingsCatalog.title(.recover), systemImage: "clock.arrow.circlepath")
                    Spacer()
                    let missing = store.missingFilesInLibrary   // hidden pins are never counted here
                    if missing > 0 {
                        Text("\(missing) missing").foregroundStyle(.secondary)
                    }
                }
            }
            .settingsRow(.recover)
        } header: {
            SettingsHeader(section: .backups)
        } footer: {
            Text(SettingSection.backups.footer)
        }
    }

    private var clearSection: some View {
        Section {
            Button(SettingsCatalog.title(.clearLibrary), role: .destructive) {
                session.showClearConfirm = true
            }
            .disabled(store.pins.isEmpty && store.boards.isEmpty)
            .settingsRow(.clearLibrary)
        }
    }
}

/// While an export runs: how far it has got, and "Stop export" right under it (Done and the
/// swipe down wait for the export, so this is the way out).
struct ExportProgressRows: View {
    @ObservedObject var progress: ExportProgress
    let onStop: () -> Void

    var body: some View {
        ExportProgressBar(progress: progress)
            .padding(.vertical, 4)
        Button {
            onStop()
        } label: {
            Label("Stop export", systemImage: "stop.circle")
        }
    }
}

// MARK: - About

/// What PinBoard keeps and what it sends.
struct SettingsAboutPage: View {
    var body: some View {
        SettingsForm(.about) {
            Section {
                Text(SettingsWords.about)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .settingsRow(.about)
            } header: {
                SettingsHeader(section: .about)
            }
        }
    }
}
