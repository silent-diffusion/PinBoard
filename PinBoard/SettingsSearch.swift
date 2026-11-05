//
//  SettingsSearch.swift  —  PinBoard
//
//  Finding a setting: the search field at the top of the Settings list, its results (the
//  setting's name, where it is, and its value now), and what a result does: it opens the page,
//  scrolls to the row and lights it up for a moment. Also the two pieces every page uses for
//  that: `SettingsForm` (a page's Form, which scrolls to the row asked for) and `.settingsRow(_:)`
//  (marks a row so it can be found and lit). The words searched are in SettingsCatalog.swift.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - A page, and its rows

/// A Settings page: its Form under the page's own name, scrolled to the row a search result (or
/// another screen) asked for. Every page of the list is one of these.
struct SettingsForm<Content: View>: View {
    let page: SettingsDestination
    let content: Content
    @EnvironmentObject private var session: SettingsSession

    init(_ page: SettingsDestination, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            Form {
                content
            }
            .onAppear { goToTarget(proxy) }
            .onChange(of: session.target) { goToTarget(proxy) }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The row asked for is on this page: scroll it to the middle once the page has slid in, light
    /// it up, and let the light fade after a moment.
    private func goToTarget(_ proxy: ScrollViewProxy) {
        guard let target = session.target, SettingsCatalog.entry(target).page == page else { return }
        session.target = nil
        let shared = session
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)   // the page's slide in
            withAnimation { proxy.scrollTo(target.rawValue, anchor: .center) }
            shared.highlighted = target
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if shared.highlighted == target {
                withAnimation(.easeOut(duration: 0.8)) { shared.highlighted = nil }
            }
        }
    }
}

extension View {
    /// Marks a row of a Settings page with its catalog id: the search scrolls to it and lights it.
    func settingsRow(_ id: SettingID) -> some View {
        modifier(SettingsRowMark(id: id))
    }
}

/// (What `.settingsRow(_:)` does.) Only used inside Settings, which hands down its SettingsSession.
private struct SettingsRowMark: ViewModifier {
    let id: SettingID
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SettingsSession

    func body(content: Content) -> some View {
        content
            .id(id.rawValue)
            .listRowBackground(session.highlighted == id ? SettingsHighlight(color: settings.accentColor) : nil)
    }
}

/// A lit row: the accent colour at 18 % over the row's usual background (as the Search tab's chips).
private struct SettingsHighlight: View {
    let color: Color

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            color.opacity(0.18)
        }
    }
}

// MARK: - The search field and results

/// The field pinned at the top of the Settings list, with PinBoard's own keyboard under it when
/// that is on (built like the board picker's search).
struct SettingsSearchBar: View {
    @Binding var text: String
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NativeTextField(placeholder: "Search settings",
                                text: $text,
                                returnKey: .search,
                                autocapitalization: .none,
                                autocorrection: false,
                                showsClearButton: false,
                                accessibilityLabel: "Search settings") {
                    NativeTextField.endEditing()
                }
                if !text.isEmpty {
                    clearButton
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

    private var clearButton: some View {
        Button {
            text = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
    }
}

/// What the search found, in place of the list of pages while something is typed.
struct SettingsSearchResults: View {
    let query: String
    /// A result was tapped: open its page at its row.
    let onOpen: (SettingEntry) -> Void
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var order = FeedOrder.shared

    var body: some View {
        let found = SettingsCatalog.search(query)
        if found.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No settings match “\(query.trimmingCharacters(in: .whitespaces))”.")
                    Text("Try another word, like “sync” or “colour”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else {
            Section {
                ForEach(found, id: \.id) { (entry: SettingEntry) in
                    resultRow(entry)
                }
            }
        }
    }

    private func resultRow(_ entry: SettingEntry) -> some View {
        Button {
            onOpen(entry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .foregroundStyle(.primary)
                    Text(SettingsCatalog.place(entry.section))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let note = entry.shownWhen {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let value = SettingsValueText.value(entry.id, settings: settings, order: order) {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The value a result shows

/// The value now, beside a search result: "On" / "Off" for a switch, the choice for a menu (nil
/// for anything else). Read when the result is drawn, so it is always the profile in use's.
@MainActor
enum SettingsValueText {
    static func value(_ id: SettingID, settings: AppSettings, order: FeedOrder) -> String? {
        if id == .cloudAI { return settings.cloudSwitchShowsOn ? "On" : "Off" }   // (on only with consent for the provider)
        if let setting = switchSetting(id) {
            return settings[keyPath: setting] ? "On" : "Off"
        }
        if let feed = orderFeed(id) {
            return orderLabel(order.mode(of: feed))
        }
        return choice(id, settings: settings)
    }

    /// The menus' values.
    private static func choice(_ id: SettingID, settings: AppSettings) -> String? {
        switch id {
        case .theme: return settings.appearance.label
        case .accentColor: return settings.accent.label
        case .columns: return settings.columns == 0 ? "Automatic" : "\(settings.columns)"
        case .textFont: return settings.textFont.label
        case .textBoardSize: return "\(Int(settings.textBoardSize)) pt"
        case .textPageSize: return "\(Int(settings.textPageSize)) pt"
        case .textLines: return "\(settings.textLinesOnBoard)"
        case .sortBoards: return settings.boardSort.label
        case .skipSeconds: return "\(settings.videoSkipSeconds) seconds"
        case .videoQuality, .videoQualityInVideos: return settings.videoQuality.label
        case .imageSource: return settings.webSource.label
        case .cloudProvider: return settings.cloudProvider.label
        default: return nil
        }
    }

    /// The three "Order of pins" choices (FeedOrder keeps them: going through it, the grids follow).
    static func orderFeed(_ id: SettingID) -> Feed? {
        switch id {
        case .pinsTabOrder: return .pins
        case .boardPagesOrder: return .board(UUID(), visit: UUID())   // (one order for every board)
        case .hiddenOrder: return .hiddenAll(visit: UUID())
        default: return nil
        }
    }

    static func orderLabel(_ mode: PinSortMode) -> String {
        switch mode {
        case .shuffled: return "Shuffled"
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }

    /// The switches' settings.
    static func switchSetting(_ id: SettingID) -> ReferenceWritableKeyPath<AppSettings, Bool>? {
        switch id {
        case .textShowsTitle: return \.textShowsTitle
        case .textUsesAccent: return \.textUsesAccent
        case .subBoardPins: return \.boardPagesIncludeSubBoards
        case .chooseBoardWhenSharing: return \.chooseBoardWhenSharing
        case .swipeBetweenTabs: return \.swipeBetweenTabs
        case .autoPlayGrids: return \.autoPlayVideos
        case .autoPlayPage: return \.autoPlayOnPage
        case .transcribe: return \.transcribeVideos
        default: return moreSwitches(id)
        }
    }

    /// (Split off so no switch is long for the compiler on the iPad.)
    private static func moreSwitches(_ id: SettingID) -> ReferenceWritableKeyPath<AppSettings, Bool>? {
        switch id {
        case .fetchPreviews: return \.fetchLinkPreviews
        case .linkPictures: return \.linkPicturesFromWebSearch
        case .readLinksFully: return \.readLinksFully
        case .cleanLinks: return \.cleanLinks
        case .autoTitle: return \.autoTitle
        case .accurateOCR: return \.accurateOCR
        case .appleIntelligence: return \.useAppleIntelligence
        case .cloudAI: return \.cloudEnabled
        case .hiddenAI, .hiddenAIInAI: return \.aiIncludesHidden
        case .autoLoadWeb: return \.autoLoadWeb
        case .boardWebIdeas: return \.showBoardWebFeed
        case .offlineMode: return \.offlineMode
        case .lockHidden: return \.lockHiddenBoards
        case .iCloudSync: return \.iCloudSync
        case .optimizeStorage: return \.optimizeStorage
        case .keepOriginals: return \.keepOriginals
        default: return nil
        }
    }
}

// MARK: - Order of pins, as a Settings row

/// "Order of pins on the Pins tab" (and on board pages, and in Hidden): the same choice as the ⋯
/// menus, read and set through FeedOrder, so a grid on screen follows at once.
struct SettingsOrderPicker: View {
    let id: SettingID
    @ObservedObject private var order = FeedOrder.shared

    var body: some View {
        if let feed = SettingsValueText.orderFeed(id) {
            Picker(SettingsCatalog.title(id), selection: binding(feed)) {
                ForEach(PinSortMode.allCases, id: \.self) { (mode: PinSortMode) in
                    Text(SettingsValueText.orderLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(id)
        }
    }

    private func binding(_ feed: Feed) -> Binding<PinSortMode> {
        Binding(get: { order.mode(of: feed) },
                set: { (mode: PinSortMode) in order.setOrder(mode, for: feed) })
    }
}

/// "Video quality": the same row on the Videos page and on iCloud & storage, so its name, choices
/// and footer can't differ (both come from here and the catalog).
struct SettingsVideoQualitySection: View {
    /// Which of the two rows this is (the search opens each at its own place).
    let id: SettingID
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let entry = SettingsCatalog.entry(id)
        Section {
            Picker(entry.title, selection: $settings.videoQuality) {
                ForEach(VideoQuality.allCases) { (quality: VideoQuality) in
                    Text(quality.label).tag(quality)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(id)
        } header: {
            Text(entry.section.header)
        } footer: {
            Text(entry.section.footer)
        }
    }
}
