//
//  SettingsTools.swift  —  PinBoard
//
//  The Settings screens that do a job: the Storage rows, the cloud-consent
//  sheet, Profiles, the tag manager, Recover library, Recently Deleted and
//  Possible duplicates. (Preferences, key storage and the accent colours are
//  AppSettings.swift; the Settings screen itself is SettingsView.swift.)
//

import SwiftUI
import Security
import UniformTypeIdentifiers
import Foundation

// MARK: - Storage

/// Settings › iCloud & storage's own rows (MediaStorage.swift does the work): the quality of the videos
/// kept on this device, keeping full-size originals in a folder chosen in Files, how much room the
/// library takes, and converting the videos already there. Settings is the normal side: it counts
/// and converts normal videos only (hidden ones have their own command in Hidden's ⋯ menu).
/// (Each modifier sits on one row: on a group of rows in a Form it would be copied onto every row.)
struct StorageSettingsRows: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var originals = OriginalsFolder.shared
    /// The library's size as a line of text. Settings keeps it, so a folder import or "Clear"
    /// measures it again too.
    @Binding var sizeText: String

    @State private var choosingFolder = false        // the folder picker is up
    @State private var askChangeFolder = false       // "Use another folder?" is being asked
    @State private var folderProblem: String? = nil  // the folder picked couldn't be used
    @State private var askConvert = false            // "Convert 12 videos to 1080p?" is being asked
    @State private var measured = false              // the size was measured on this visit to Settings

    var body: some View {
        originalsToggle
            .settingsRow(.keepOriginals)
        if settings.originalsBookmark != nil {
            folderRow
        }
        if let folderProblem {
            Text(folderProblem)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        sizeRow
            .settingsRow(.librarySize)
        if store.originalsBytes(scope: .visible) > 0 {
            originalsSizeRow
        }
        convertRow
            .settingsRow(.convertVideos)
    }

    /// Turning it on before a folder was chosen opens the folder picker first (the switch shows
    /// on meanwhile); cancelling the picker leaves it off.
    private var originalsToggle: some View {
        Toggle(SettingsCatalog.title(.keepOriginals), isOn: keepOriginals)
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { (result: Result<[URL], Error>) in
                folderChosen(result)
            }
    }

    private var keepOriginals: Binding<Bool> {
        Binding(get: { settings.keepOriginals || choosingFolder },
                set: { (on: Bool) in
                    if on, settings.originalsBookmark == nil {
                        folderProblem = nil
                        choosingFolder = true
                    } else {
                        settings.keepOriginals = on
                    }
                })
    }

    /// "Folder: iCloud Drive › PinBoard Originals", whether it can be reached now ("Checking…"
    /// until it was looked at), and "Change…" — which asks first, from itself (on iPad the question
    /// points at it), when originals are already kept.
    private var folderRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder: \(settings.originalsFolderName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(StorageText.folderStatus(originals.isReachable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change…") { changeFolder() }
                .buttonStyle(.borderless)
                .confirmationDialog("Use another folder?", isPresented: $askChangeFolder, titleVisibility: .visible) {
                    Button("Choose a folder…") { chooseFolderSoon() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(StorageText.changeFolderMessage(current: settings.originalsFolderName))
                }
        }
    }

    /// The library's size on this device: measured once per visit to Settings (the row appears
    /// again each time it scrolls into view), and again after a conversion.
    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Library size")
            Text(sizeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            guard !measured else { return }
            measured = true
            await measure()
        }
        .onChange(of: store.conversionProgress == nil) { (_: Bool, idle: Bool) in
            if idle { Task { await measure() } }
        }
    }

    /// How much the normal library's originals take in the folder (from what the pins recorded).
    private var originalsSizeRow: some View {
        HStack {
            Text("Originals in the folder")
            Spacer()
            Text(StoragePolicy.sizeText(Int(store.originalsBytes(scope: .visible))))
                .foregroundStyle(.secondary)
        }
    }

    /// "Convert existing videos…" — or, while it runs, "Converting 3 of 12 (45%)" with Stop.
    @ViewBuilder
    private var convertRow: some View {
        if let progress = store.conversionProgress {
            HStack(spacing: 8) {
                WorkProgressLine(text: StorageText.convertingRow(done: progress.done, total: progress.total, percent: store.conversionPercent))
                Spacer()
                Button("Stop") { store.cancelConversion() }
                    .buttonStyle(.borderless)
            }
        } else {
            convertButton(count: store.videosToConvert(to: settings.videoQuality, scope: .visible))
            if let note = store.conversionNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Asks first: "Convert 12 videos to 1080p?" (the normal library's videos). Without originals
    /// kept the larger versions are gone for good, so the answer is red then and the message says
    /// so. Nothing to convert (or "Original" chosen): dimmed.
    private func convertButton(count: Int) -> some View {
        let quality = settings.videoQuality
        let keeps = settings.keepOriginals
        return Button(SettingsCatalog.title(.convertVideos)) { askConvert = true }
            .disabled(store.isBusyWithLibraryWork || quality == .original || count == 0)
            .confirmationDialog(StorageText.convertQuestion(count: count, quality: quality), isPresented: $askConvert,
                                titleVisibility: .visible) {
                Button("Convert", role: keeps ? nil : .destructive) { store.startConvertingVideos(to: quality) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(StorageText.convertMessage(quality: quality, keepsOriginals: keeps))
            }
    }

    /// With originals already kept, asks first (they stay in the old folder).
    private func changeFolder() {
        folderProblem = nil
        if store.originalsBytes(scope: .visible) > 0 {
            askChangeFolder = true
        } else {
            choosingFolder = true
        }
    }

    /// Opens the folder picker once the question has gone: asked for while a dialog is still
    /// closing, a picker may not open at all (the same wait as ImportFlow's `presentSoon`).
    private func chooseFolderSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            choosingFolder = true
        }
    }

    private func folderChosen(_ result: Result<[URL], Error>) {
        let problem = "That folder can't be used. Choose another one (in iCloud Drive, say)."
        guard case .success(let urls) = result, let folder = urls.first else {
            folderProblem = problem
            return
        }
        if originals.choose(folder, settings: settings) {
            folderProblem = nil
            Task { await originals.refresh(settings: settings) }
        } else {
            folderProblem = problem
        }
    }

    private func measure() async {
        sizeText = await store.librarySizeDescription()
        await originals.refresh(settings: settings)
    }
}

/// Explains exactly what the cloud model receives, and which company receives it, before it can
/// be turned on — and again before pictures go to the other provider (App Review guideline
/// 5.1.2(i): say where personal data goes, including to a third-party AI, and ask first).
struct CloudConsentSheet: View {
    /// The provider being agreed to: the one chosen when the switch was turned on, or the one just
    /// picked under Provider.
    let provider: CloudProvider
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Send pictures to \(provider.company)?", systemImage: "cloud")
                        .font(.title3.weight(.semibold))
                    Text(CloudConsentSheet.intro(for: provider))
                    VStack(alignment: .leading, spacing: 8) {
                        // The lines are in SettingsPages.swift (`SettingsAIText`), next to the footer
                        // that says the same, so the two always agree.
                        ForEach(SettingsAIText.consentLines, id: \.self) { (line: String) in
                            consentLine(line)
                        }
                    }
                    privacyPolicy
                    Text("You can turn this off at any time; images already tagged keep their tags. Choosing the other provider later asks you again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    agreeButton
                    Button("Not now") { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Cloud AI")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    /// The first words of the sheet: who receives the pictures, by name.
    nonisolated static func intro(for provider: CloudProvider) -> String {
        "With this on, every new image (and any you re-run) is sent to " + provider.company + " (" + provider.maker
            + "), at " + provider.host + ", using your own API key. That is the trade for much better tags and titles."
    }

    /// Whose rules apply once the pictures arrive, with a link to them.
    private var privacyPolicy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What \(provider.company) does with what it receives is governed by its privacy policy, not by PinBoard.")
                .font(.subheadline)
            Link("Read \(provider.company)'s privacy policy", destination: provider.privacyPolicyURL)
                .font(.subheadline)
        }
    }

    /// Agreeing is for this provider only: it is remembered by name (per profile, like every
    /// setting) and becomes the chosen provider.
    private var agreeButton: some View {
        Button {
            settings.cloudConsentProvider = provider.rawValue
            settings.cloudProvider = provider
            settings.cloudEnabled = true
            dismiss()
        } label: {
            Text("I understand — turn it on")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func consentLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 6)).padding(.top, 7)
            Text(text)
        }
        .font(.subheadline)
    }
}

// MARK: - Profiles

/// Create, rename, switch between and delete profiles (separate libraries).
struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProfileManager
    /// Items shared from other apps into a profile that isn't open wait for it (ShareInbox.swift).
    @ObservedObject private var shareInbox = ShareInbox.shared
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @EnvironmentObject private var cloudSync: CloudSync
    @EnvironmentObject private var settings: AppSettings   // the originals folder (the delete question names it)
    @State private var showNew = false
    @State private var renaming: Profile? = nil
    @State private var deleting: Profile? = nil
    @State private var showDeleteConfirm = false
    @State private var switchedTo: String? = nil

    /// An import is writing into the library in use. Switching profiles now would swap that
    /// library out from under it (and mix two libraries), so switching — and New profile…, which
    /// switches to the new one — waits until it has finished. A running iCloud sync never makes
    /// it wait: the switch stops it (`ProfileSwitchPlan`); it picks up at its next sync.
    private var isBusy: Bool {
        ProfileSwitchPlan.plan(importing: importFlow.isWorking || store.isImporting,
                               syncing: cloudSync.isSyncing) == .waitForImport
    }

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { profile in
                    profileRow(profile)
                        .contextMenu { profileActions(profile, inContextMenu: true) }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text(footerText)
            }
            Section {
                Button {
                    showNew = true
                } label: {
                    Label("New profile…", systemImage: "plus")
                }
                .disabled(isBusy)
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) {
            TextEditSheet(title: "New profile", placeholder: "Name (e.g. Work, Kids)", initial: "", requiresText: true) { name in
                if let profile = profiles.create(name: name) {
                    switchTo(profile)
                }
            }
        }
        .sheet(item: $renaming) { profile in
            TextEditSheet(title: "Rename profile", placeholder: "Name", initial: profile.name, requiresText: true) { name in
                profiles.rename(profile.id, to: name)
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")” and everything in it?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                if let deleting { _ = profiles.delete(deleting.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            // Its full-size originals in the folder go too (Settings › iCloud & storage): said whenever a folder is set.
            Text(StorageText.deleteProfileMessage(folderName: settings.originalsFolderIfSet))
        }
    }

    /// "Now using “Work”. Tap a profile to switch to it. …", with a line on why switching waits
    /// while an import or a sync is running.
    private var footerText: String {
        var parts: [String] = []
        if let switchedTo { parts.append("Now using “\(switchedTo)”.") }
        if isBusy { parts.append("Switching waits until the import that is running has finished.") }
        else if cloudSync.isSyncing { parts.append("Switching stops the iCloud sync that is running; it carries on next time.") }
        parts.append("Tap a profile to switch to it. Each one is kept completely apart: its own pins, boards, smart boards and Recently Deleted, and its own settings — iCloud sync, Offline mode, look, API keys and the rest. A new profile starts with the default settings. Rename or delete a profile with its ⋯ button (or touch and hold it). The profile in use can't be deleted.")
        return parts.joined(separator: " ")
    }

    /// One profile: tap it to switch to it; its ⋯ button renames or deletes it (like a tag's row).
    private func profileRow(_ profile: Profile) -> some View {
        HStack {
            Button {
                switchTo(profile)
            } label: {
                profileLabel(profile)
            }
            .buttonStyle(.plain)   // only the row's own taps; the ⋯ button handles its own
            .disabled(isBusy && profile.id != profiles.currentID)
            Menu {
                profileActions(profile, inContextMenu: false)
            } label: {
                RowMoreLabel()
            }
            .accessibilityLabel("Actions for \(profile.name)")
        }
    }

    private func profileLabel(_ profile: Profile) -> some View {
        let isCurrent = profile.id == profiles.currentID
        let canSwitch = isCurrent || !isBusy   // the other profiles look dimmed while switching waits
        return HStack {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .foregroundStyle(canSwitch ? Color.primary : Color.secondary)
                if let count = shareInbox.waiting[profile.id], count > 0, !isCurrent {
                    Text(count == 1 ? "1 shared item waiting" : "\(count) shared items waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isCurrent {
                Text("Current").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())   // the whole row switches, not just the words
    }

    /// Rename… and Delete…, for the ⋯ menu and the touch-and-hold menu alike. Only another
    /// profile can be deleted (never the one in use, never the last): the ⋯ menu then shows
    /// Delete… dimmed, the touch-and-hold menu leaves it out.
    @ViewBuilder
    private func profileActions(_ profile: Profile, inContextMenu: Bool) -> some View {
        let canDelete = profile.id != profiles.currentID && profiles.profiles.count > 1
        Button { renaming = profile } label: { Label("Rename…", systemImage: "pencil") }
        if canDelete || !inContextMenu {
            Button(role: .destructive) {
                deleting = profile
                showDeleteConfirm = true
            } label: {
                Label("Delete…", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
    }

    private func switchTo(_ profile: Profile) {
        guard profile.id != profiles.currentID, !isBusy else { return }
        profiles.select(profile.id, store: store)
        switchedTo = profile.name
    }
}

/// The ⋯ button at the end of a list row: the toolbar's ⋯ symbol, with a finger-sized
/// (44-point) target — the bare symbol alone is only a few points tall.
private struct RowMoreLabel: View {
    var body: some View {
        MoreMenuLabel()
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Tag manager

/// The rule behind the tags list's "Select all" button (pure, so the tests can check it).
enum TagSelection {
    /// True when there are tags listed and every one of them is chosen.
    nonisolated static func allChosen(listed: [String], selection: Set<String>) -> Bool {
        if listed.isEmpty { return false }
        return listed.allSatisfy { selection.contains($0) }
    }

    /// The selection after the button is pressed: every listed tag chosen, or — when they all were
    /// already — every listed tag let go. Tags that are chosen but not listed (a filter hides
    /// them) are left as they are.
    nonisolated static func toggledAll(listed: [String], selection: Set<String>) -> Set<String> {
        if allChosen(listed: listed, selection: selection) {
            return selection.subtracting(listed)
        }
        return selection.union(listed)
    }
}

/// Rename, merge or delete the tags you gave to pins — of the normal library,
/// or (scope .hidden, from the Hidden section) of hidden pins only.
struct TagManagerView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    var scope: PinScope = .visible
    /// A tag name that can drive a sheet.
    private struct TagName: Identifiable {
        var name: String
        var id: String { name }
    }

    @State private var renaming: TagName? = nil
    @State private var mergingInto: String? = nil       // the tag being merged (nil = the selection)
    @State private var deleting: String? = nil
    @State private var showDeleteConfirm = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var showMerge = false
    @State private var filter = ""

    var body: some View {
        let all = store.userTagCounts(scope: scope)   // once per render
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let tags = needle.isEmpty ? all : all.filter { $0.tag.contains(needle) }
        List {
            filterSection(tagCount: all.count)
            Section {
                if tags.isEmpty {
                    Text(all.isEmpty
                         ? (scope == .hidden ? "No tags on hidden pins yet. Add tags on a pin's page." : "No tags of your own yet. Add tags on a pin's page.")
                         : "No tag matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tags, id: \.tag) { entry in
                    HStack {
                        if isSelecting {
                            Image(systemName: selection.contains(entry.tag) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(entry.tag) ? Color.accentColor : Color.secondary)
                        } else {
                            Image(systemName: "tag").foregroundStyle(.secondary)
                        }
                        Text(entry.tag)
                        Spacer()
                        Text("\(entry.count)").foregroundStyle(.secondary)
                        if !isSelecting {
                            Menu {
                                Button { renaming = TagName(name: entry.tag) } label: { Label("Rename…", systemImage: "pencil") }
                                Button { mergingInto = entry.tag; showMerge = true } label: { Label("Merge into another tag…", systemImage: "arrow.triangle.merge") }
                                Button(role: .destructive) {
                                    deleting = entry.tag
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete…", systemImage: "trash")
                                }
                            } label: {
                                RowMoreLabel()
                            }
                            .accessibilityLabel("Actions for \(entry.tag)")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isSelecting else { return }
                        if selection.contains(entry.tag) { selection.remove(entry.tag) } else { selection.insert(entry.tag) }
                    }
                }
            } header: {
                Text("\(all.count) tag\(all.count == 1 ? "" : "s")")
            } footer: {
                Text(scope == .hidden
                     ? "Only the tags of hidden pins are listed. The number is how many hidden pins carry the tag. Renaming or merging changes it on every hidden pin."
                     : "The number is how many pins carry the tag. Renaming or merging changes it on every pin.")
            }
        }
        .navigationTitle(scope == .hidden ? "Tags of hidden pins" : "Your tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    selectAllButton(listed: tags.map { $0.tag })
                }
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation { isSelecting.toggle() }
                    if !isSelecting { selection = [] }
                }
                .disabled(all.count < 2 && !isSelecting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        // The tags of hidden pins (from Hidden's ⋯ › Tags) never show in the App Switcher.
        .sheet(item: $renaming) { tag in
            TextEditSheet(title: "Rename “\(tag.name)”", placeholder: "New name", initial: tag.name, requiresText: true) { name in
                store.renameTag(tag.name, to: name, scope: scope)
            }
            .hiddenPrivacyCover(scope == .hidden)
        }
        .sheet(isPresented: $showMerge) {
            let sources = mergingInto.map { [$0] } ?? Array(selection).sorted()
            TextEditSheet(title: sources.count == 1 ? "Merge “\(sources[0])” into…" : "Merge \(sources.count) tags into…",
                          placeholder: "Name of the tag to keep", initial: mergingInto ?? sources.first ?? "",
                          requiresText: true) { name in
                store.mergeTags(sources, into: name, scope: scope)
                selection = []
                isSelecting = false
            }
            .hiddenPrivacyCover(scope == .hidden)
        }
        // (The question sits above any cover: a hidden pin's tag is not named in it.)
        .confirmationDialog(deleteQuestion, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete tag", role: .destructive) {
                if let deleting { store.deleteTag(deleting, scope: scope) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    /// "Delete “beach” from every pin?" — or, for the tags of hidden pins, "Delete this tag from
    /// every hidden pin?".
    private var deleteQuestion: String {
        if scope == .hidden { return "Delete this tag from every hidden pin?" }
        return "Delete “\(deleting ?? "")” from every pin?"
    }

    /// "Find a tag", once there are more than 8. With PinBoard's own keyboard its Done key puts
    /// the keyboard away (the list is filtered as you type, so there is nothing to submit).
    @ViewBuilder
    private func filterSection(tagCount: Int) -> some View {
        if tagCount > 8 {
            Section {
                NativeTextField(placeholder: "Find a tag", text: $filter, autocapitalization: .none, autocorrection: false, showsClearButton: true)
            }
        }
    }

    /// "Select all" while selecting (it becomes "Deselect all" once every tag listed is chosen).
    /// It works on the tags listed now, so with a filter typed it chooses just the matches.
    private func selectAllButton(listed: [String]) -> some View {
        let everyOneChosen: Bool = TagSelection.allChosen(listed: listed, selection: selection)
        return Button(everyOneChosen ? "Deselect all" : "Select all") {
            selection = TagSelection.toggledAll(listed: listed, selection: selection)
        }
        .disabled(listed.isEmpty)
    }

    /// The bar under the list while selecting: how many tags are chosen, and Merge.
    private var selectionBar: some View {
        HStack {
            Text("\(selection.count) selected").font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                mergingInto = nil
                showMerge = true
            } label: {
                mergeLabel
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selection.count < 2)
            .accessibilityLabel("Merge into one…")
        }
        .padding(12)
        .background(.regularMaterial)
    }

    /// The symbol with its caption under it; when the caption doesn't fit (large text on a
    /// narrow screen), the symbol alone — the words are never shrunk. VoiceOver reads the
    /// button's name either way.
    private var mergeLabel: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.merge")
                Text("Merge into one…")
                    .font(.caption2)
                    .lineLimit(1)
            }
            Image(systemName: "arrow.triangle.merge")
        }
    }
}

// MARK: - Recovery

extension LibraryStore {
    /// How many pins of the normal library have lost their picture or video file. Hidden pins
    /// are never counted on this side (Settings and Recover library are the normal side).
    var missingFilesInLibrary: Int { missingFileCount(scope: .visible) }   // (Library's row in Settings shows it too)
}

/// Restore an earlier copy of the library file, or move pins whose files are gone to Recently
/// Deleted. Only the normal library's pins are counted and moved here.
struct RecoverLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var backups: [LibraryBackup] = []
    @State private var restoring: LibraryBackup? = nil
    @State private var showRestoreConfirm = false
    @State private var showRemoveMissing = false
    @State private var message: String? = nil
    @State private var showMessage = false
    @State private var checking = false

    var body: some View {
        List {
            backupsSection
            missingFilesSection
        }
        .navigationTitle("Recover library")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBackups() }
        .confirmationDialog(restoreQuestion, isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            restoreButtons
        } message: {
            Text("The current list of pins and boards is replaced. A copy of it is kept as “Before the last restore”, so this can be undone.")
        }
        .confirmationDialog(moveQuestion, isPresented: $showRemoveMissing, titleVisibility: .visible) {
            Button("Move to Recently Deleted", role: .destructive) { store.removeMissingFilePins() }
        } message: {
            Text(moveMessage)
        }
        .alert(message ?? "", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        }
    }

    private var backupsSection: some View {
        Section {
            if backups.isEmpty {
                Text("No earlier copies yet. One is kept after the first few minutes of use.")
                    .foregroundStyle(.secondary)
            }
            ForEach(backups) { backup in
                backupRow(backup)
            }
        } header: {
            Text("Earlier copies of the library")
        } footer: {
            Text("Restoring replaces the list of pins and boards with the copy. Pictures and videos on disk are kept.")
        }
    }

    private func backupRow(_ backup: LibraryBackup) -> some View {
        Button {
            restoring = backup
            showRestoreConfirm = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.label).foregroundStyle(Color.primary)
                    Text("\(backup.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(backup.pinCount) pin\(backup.pinCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Restore").font(.subheadline)
            }
        }
    }

    private var missingFilesSection: some View {
        let missing = store.missingFilesInLibrary
        return Section {
            HStack {
                Text("Pins in your library with missing files")
                Spacer()
                Text("\(missing)").foregroundStyle(.secondary)
            }
            Button {
                checkForMissingFiles()
            } label: {
                HStack {
                    Text("Check for missing files")
                    if checking { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(checking)
            Button("Move pins with missing files to Recently Deleted…", role: .destructive) {
                showRemoveMissing = true
            }
            .disabled(missing == 0)
        } header: {
            Text("Missing files")
        } footer: {
            Text("A pin whose picture or video file has disappeared shows an empty card. Pins moved to Recently Deleted stay there for \(LibraryStore.trashRetentionDays) days.")
        }
    }

    /// "Restore “Earlier today” from 3 Mar 2025 at 09:12?"
    private var restoreQuestion: String {
        let when = restoring?.savedAt.formatted(date: .abbreviated, time: .shortened) ?? ""
        return "Restore “\(restoring?.label ?? "")” from \(when)?"
    }

    @ViewBuilder
    private var restoreButtons: some View {
        Button("Restore this copy", role: .destructive) {
            if let restoring {
                message = store.restore(restoring)
                    ? "Restored. The AI will look at anything that still needs it."
                    : "Nothing was changed: that copy couldn't be read, or the current list couldn't be kept first."
                showMessage = true
            }
            restoring = nil
            Task { await loadBackups() }
        }
        Button("Cancel", role: .cancel) { restoring = nil }
    }

    /// "Move 3 pins to Recently Deleted?"
    private var moveQuestion: String {
        let count = store.missingFilesInLibrary
        return "Move \(count) pin\(count == 1 ? "" : "s") to Recently Deleted?"
    }

    /// "They stay in Recently Deleted for 30 days." (as when pins are deleted from a menu)
    private var moveMessage: String {
        let days = LibraryStore.trashRetentionDays
        return store.missingFilesInLibrary == 1
            ? "It stays in Recently Deleted for \(days) days."
            : "They stay in Recently Deleted for \(days) days."
    }

    /// Looks for missing files again, then says how many pins of the library lack theirs.
    private func checkForMissingFiles() {
        checking = true
        Task { @MainActor in
            await store.sweepOrphans()
            checking = false
            let count = store.missingFilesInLibrary
            if count == 0 {
                message = "Every pin in your library has its file."
            } else {
                message = count == 1 ? "1 pin in your library is missing its file." : "\(count) pins in your library are missing a file."
            }
            showMessage = true
        }
    }

    /// Reading the copies means decoding whole library files: done off the main thread.
    private func loadBackups() async {
        let location = store.location
        let found = await Task.detached(priority: .userInitiated) { () -> [LibraryBackup] in
            LibraryStore.backups(at: location)
        }.value
        backups = found
    }
}

// MARK: - Recently Deleted and duplicates

/// Pins waiting in the bin (30 days), with restore and permanent delete — the
/// normal library's, or (scope .hidden, from the Hidden section) hidden pins only.
struct RecentlyDeletedView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    var scope: PinScope = .visible
    @ScaledMetric(relativeTo: .body) private var buttonRowHeight: CGFloat = 32
    @State private var showEmptyConfirm = false
    @State private var erasing: Pin? = nil
    @State private var showEraseConfirm = false

    var body: some View {
        let deleted = store.deletedPins(scope: scope)   // once per render
        GeometryReader { geometry in
            let metrics = GridMetrics(columns: settings.columnCount(forWidth: geometry.size.width),
                                      width: geometry.size.width - PinTheme.gridSpacing * 2)
            let rowHeight = buttonRowHeight
            ScrollView {
                VStack(spacing: 12) {
                    if deleted.isEmpty {
                        EmptyStateView(icon: "trash", title: "Nothing here",
                                       message: "Deleted \(scope == .hidden ? "hidden " : "")pins stay for \(LibraryStore.trashRetentionDays) days so you can change your mind.")
                            .padding(.top, 60)
                    } else {
                        Text(scope == .hidden
                             ? "Deleted hidden pins. Restored pins stay hidden. They are erased for good after \(LibraryStore.trashRetentionDays) days."
                             : "Pins are erased for good after \(LibraryStore.trashRetentionDays) days.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        let textStyle = settings.textStyle
                        MasonryGrid(items: deleted, metrics: metrics,
                                    aspectRatio: { $0.aspectRatio },
                                    footerHeight: { PinCardView.footerHeight(for: $0, caption: nil) + 6 + rowHeight },
                                    cardHeight: { pin, width in
                                        PinCardView.fixedHeight(for: pin, width: width, textStyle: textStyle)
                                    }) { pin in
                            VStack(alignment: .leading, spacing: 6) {
                                PinCardView(pin: pin)
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Button("Restore") { store.restorePins([pin.id]) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        Button("Erase", role: .destructive) { erasing = pin; showEraseConfirm = true }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                    HStack {
                                        Button { store.restorePins([pin.id]) } label: { Image(systemName: "arrow.uturn.backward") }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .accessibilityLabel("Restore")
                                        Button(role: .destructive) { erasing = pin; showEraseConfirm = true } label: { Image(systemName: "trash") }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .accessibilityLabel("Erase")
                                    }
                                }
                                .frame(height: rowHeight)
                            }
                        }
                    }
                }
                .padding(.horizontal, PinTheme.gridSpacing)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Restore all") { store.restorePins(Set(deleted.map { $0.id })) }
                    Button("Erase all now…", role: .destructive) { showEmptyConfirm = true }
                } label: {
                    MoreMenuLabel()
                }
                .disabled(deleted.isEmpty)
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog(scope == .hidden ? "Erase every deleted hidden pin?" : "Erase everything in Recently Deleted?",
                            isPresented: $showEmptyConfirm, titleVisibility: .visible) {
            Button("Erase all", role: .destructive) { store.emptyTrash(scope: scope) }
        } message: {
            // Their full-size originals in the folder go too (Settings › iCloud & storage): said whenever a folder is set.
            Text(StorageText.eraseMessage(folderName: settings.originalsFolderIfSet))
        }
        .confirmationDialog("Erase this pin for good?", isPresented: $showEraseConfirm, titleVisibility: .visible) {
            Button("Erase", role: .destructive) {
                if let erasing { store.erasePins([erasing.id]) }
                erasing = nil
            }
            Button("Cancel", role: .cancel) { erasing = nil }
        }
    }
}

/// Pins that look identical to another pin, side by side (newer and older) —
/// in the normal library, or (scope .hidden, from the Hidden section) among hidden pins.
struct DuplicatesView: View {
    @EnvironmentObject private var store: LibraryStore
    var scope: PinScope = .visible
    @State private var checking = false

    var body: some View {
        let pairs = store.duplicatePins(scope: scope).compactMap { newer -> (Pin, Pin)? in
            guard let originalID = newer.duplicateOfID, let original = store.livePin(originalID) else { return nil }
            return (newer, original)
        }
        GeometryReader { geometry in
            // With lots of room (more than 900 points across) the pairs sit in a centered
            // panel about 700 points wide instead of stretching edge to edge. It goes by the
            // width this screen actually gets, so in a narrower sheet the plain list is used.
            if geometry.size.width > 900 {
                ScrollView {
                    pairList(pairs)
                        .padding(20)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
                        .frame(maxWidth: 700)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                ScrollView {
                    pairList(pairs)
                        .padding()
                }
            }
        }
        .navigationTitle("Possible duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        recheck(reset: false)
                    } label: {
                        Label("Re-check (skips pairs you kept)", systemImage: "arrow.clockwise")
                    }
                    Button {
                        recheck(reset: true)
                    } label: {
                        Label("Reset and re-check everything", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    // A symbol like the other toolbar buttons; its name is the title.
                    if checking { ProgressView() } else { Label("Re-check", systemImage: "arrow.clockwise") }
                }
                .disabled(checking)
                .accessibilityLabel("Re-check")
            }
        }
    }

    private func pairList(_ pairs: [(Pin, Pin)]) -> some View {
        VStack(spacing: 16) {
            if pairs.isEmpty {
                EmptyStateView(icon: "square.on.square", title: "No duplicates found",
                               message: scope == .hidden
                                   ? "Each new hidden image is compared with your other hidden pins as it is tagged."
                                   : "Each new image is compared with the library as it is tagged.")
                    .padding(.top, 60)
            } else {
                Text("Delete either copy — its boards and tags move to the one you keep — or keep both.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(pairs, id: \.0.id) { pair in
                    DuplicatePairView(newer: pair.0, older: pair.1, showsCards: true)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
                }
            }
        }
    }

    private func recheck(reset: Bool) {
        checking = true
        Task { @MainActor in
            if reset { await store.resetDuplicateDecisions() } else { await store.refreshDuplicates() }
            checking = false
        }
    }
}
