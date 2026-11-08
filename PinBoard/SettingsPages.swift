//
//  SettingsPages.swift  —  PinBoard
//
//  The everyday pages of Settings (the list, and how a page opens, are in SettingsView.swift):
//  Appearance, Pins & boards, Videos, Links and AI. The other pages are in SettingsPages2.swift.
//  Each page is a small screen of its own, so none of them is slow to build. Row names and
//  footers come from SettingsCatalog.swift, and every row is marked with `.settingsRow(_:)`, so
//  the search finds it and can scroll to it.
//

import SwiftUI
import UIKit
import Foundation

/// Rows that need the internet are dimmed in Offline mode (never hidden, so you can still find
/// them), with this line saying why.
struct SettingsOfflineNote: View {
    var body: some View {
        Label("Off while Offline mode is on (\(SettingsCatalog.path(.offlineMode))).", systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// A section header from the catalog (nothing when the section has none).
struct SettingsHeader: View {
    let section: SettingSection

    var body: some View {
        if !section.header.isEmpty { Text(section.header) }
    }
}

// MARK: - Appearance

/// Theme, accent colour, the app icon, how many pictures per row, and how text pins look (with a live preview).
struct SettingsAppearancePage: View {
    @EnvironmentObject private var settings: AppSettings

    private let columnChoices = [0, 2, 3, 4, 5, 6, 7, 8]

    var body: some View {
        SettingsForm(.appearance) {
            appearanceSection
            appIconSection
            gridSection
            textPinSection
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(SettingsCatalog.title(.theme), selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .settingsRow(.theme)

            VStack(alignment: .leading, spacing: 8) {
                Text(SettingsCatalog.title(.accentColor))
                accentSwatches
            }
            .settingsRow(.accentColor)
            // More colours: the system colour picker (wheel, sliders, eyedropper…).
            HStack {
                ColorPicker(SettingsCatalog.title(.customAccent), selection: customAccentBinding, supportsOpacity: false)
                if settings.accent == .custom {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(settings.accentColor)
                }
            }
            .settingsRow(.customAccent)
        } header: {
            SettingsHeader(section: .appearance)
        }
    }

    /// The Home Screen icon (AppIconPicker.swift): the device's choice, not the profile's.
    private var appIconSection: some View {
        Section {
            AppIconRow()
                .settingsRow(.appIcon)
        } footer: {
            Text(SettingSection.appIcon.footer)
        }
    }

    private var gridSection: some View {
        Section {
            Picker(SettingsCatalog.title(.columns), selection: $settings.columns) {
                ForEach(columnChoices, id: \.self) { count in
                    Text(count == 0 ? "Automatic" : "\(count)").tag(count)
                }
            }
            .settingsRow(.columns)
        } header: {
            SettingsHeader(section: .grid)
        } footer: {
            Text(SettingSection.grid.footer)
        }
    }

    private var accentSwatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(AccentTheme.allCases.filter { $0 != .custom }) { theme in
                    swatch(theme)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One accent colour: a circle, with a tick on the one in use.
    private func swatch(_ theme: AccentTheme) -> some View {
        Button {
            settings.accent = theme
        } label: {
            ZStack {
                Circle()
                    .fill(theme.color)
                    .frame(width: 34, height: 34)
                if theme == settings.accent {
                    // White in light mode, near-black in dark mode, where
                    // the accent colours are lighter.
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
            .frame(minWidth: 44, minHeight: 44)   // a finger-sized touch area around the circle
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.label)
    }

    /// The colour picker edits the custom colour and selects it. It always shows (and so
    /// saves) the colour as picked, never its dark-mode or high-contrast version.
    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: settings.customAccentHex) ?? AccentTheme.red.baseColor },
            set: { newColor in
                if let hex = newColor.hexString {
                    settings.customAccentHex = hex
                    settings.accent = .custom
                }
            }
        )
    }

    private var textPinSection: some View {
        Section {
            Picker(SettingsCatalog.title(.textFont), selection: $settings.textFont) {
                ForEach(TextFontChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .settingsRow(.textFont)
            Stepper("\(SettingsCatalog.title(.textBoardSize)): \(Int(settings.textBoardSize)) pt", value: $settings.textBoardSize, in: 11...28, step: 1)
                .settingsRow(.textBoardSize)
            Stepper("\(SettingsCatalog.title(.textPageSize)): \(Int(settings.textPageSize)) pt", value: $settings.textPageSize, in: 13...40, step: 1)
                .settingsRow(.textPageSize)
            Stepper("\(SettingsCatalog.title(.textLines)): \(settings.textLinesOnBoard)", value: $settings.textLinesOnBoard, in: 2...30)
                .settingsRow(.textLines)
            Toggle(SettingsCatalog.title(.textShowsTitle), isOn: $settings.textShowsTitle)
                .settingsRow(.textShowsTitle)
            Toggle(SettingsCatalog.title(.textUsesAccent), isOn: $settings.textUsesAccent)
                .settingsRow(.textUsesAccent)
            textColorRow
                .settingsRow(.textColor)
            // A live preview.
            TextCardView(pin: previewTextPin, style: settings.textStyle, color: settings.textPinColor)
                .frame(maxWidth: 320)
        } header: {
            SettingsHeader(section: .textPins)
        } footer: {
            Text(SettingSection.textPins.footer)
        }
    }

    private var textColorRow: some View {
        HStack {
            ColorPicker(SettingsCatalog.title(.textColor), selection: textColorBinding, supportsOpacity: false)
            if !settings.textColorHex.isEmpty {
                Button("Reset") { settings.textColorHex = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var previewTextPin: Pin {
        var pin = Pin()
        pin.kind = .text
        pin.title = "A note to self"
        pin.textBody = "Text pins look like this. The typeface, size, colour and how many lines a card shows are all yours to change here."
        return pin
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: settings.textColorHex) ?? .primary },
            set: { newColor in
                if let hex = newColor.hexString { settings.textColorHex = hex }
            }
        )
    }
}

// MARK: - Pins & boards

/// How boards and pins are sorted, what board pages show, the share sheet, widgets, swiping
/// between tabs and PinBoard's own keyboard.
struct SettingsPinsAndBoardsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        SettingsForm(.pinsAndBoards) {
            homePageSection
            orderSection
            boardsSection
            sharingSection
            widgetsSection
            gettingAroundSection
        }
    }

    /// "Home page": opens the list of everything kept off the Pins tab (SettingsHomePage.swift),
    /// with how many pins that is at the right.
    private var homePageSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.homePage) {
                HStack {
                    Label(SettingsCatalog.title(.homePage), systemImage: SettingsDestination.homePage.symbol)
                    Spacer()
                    Text(HomePageText.pinCount(store.keptOutPins.count))
                        .foregroundStyle(.secondary)
                }
            }
            .settingsRow(.homePage)
        } header: {
            SettingsHeader(section: .homePage)
        } footer: {
            Text(SettingSection.homePage.footer)
        }
    }

    /// "Sort boards" and two "Order of pins": the same settings as the ⋯ menus (changing one here
    /// changes it there; the pin orders go through FeedOrder).
    private var orderSection: some View {
        Section {
            Picker(SettingsCatalog.title(.sortBoards), selection: $settings.boardSort) {
                ForEach(BoardSort.allCases) { (sort: BoardSort) in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(.sortBoards)
            SettingsOrderPicker(id: .pinsTabOrder)
            SettingsOrderPicker(id: .boardPagesOrder)
        } header: {
            SettingsHeader(section: .order)
        } footer: {
            Text(SettingSection.order.footer)
        }
    }

    /// The default for board pages' "Include pins from sub-boards" (each page can still change it).
    private var boardsSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.subBoardPins), isOn: $settings.boardPagesIncludeSubBoards)
                .settingsRow(.subBoardPins)
        } header: {
            SettingsHeader(section: .boards)
        } footer: {
            Text(SettingSection.boards.footer)
        }
    }

    /// The share sheet's quick save (ShareShared.swift; the share sheet is Xcode/PinBoardShare).
    private var sharingSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.chooseBoardWhenSharing), isOn: $settings.chooseBoardWhenSharing)
                .settingsRow(.chooseBoardWhenSharing)
        } header: {
            SettingsHeader(section: .sharing)
        } footer: {
            Text(SettingSection.sharing.footer)
        }
    }

    /// Running on a Mac ("Designed for iPad"), where widgets live on the desktop.
    private var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    /// Widgets keep their own choices (iOS keeps them with each widget), so this only says where.
    private var widgetsSection: some View {
        Section {
            Label(isMac ? "Edit a widget on the desktop" : "Edit a widget on the Home Screen", systemImage: "rectangle.3.group")
                .foregroundStyle(.secondary)
                .settingsRow(.widgets)
        } header: {
            SettingsHeader(section: .widgets)
        } footer: {
            // On a Mac only the Mac's own widgets work; the iPhone's copies ("From iPhone") can't show photos here.
            Text(isMac ? SettingSection.widgets.footer + " " + SettingsWords.widgetsOnMac : SettingSection.widgets.footer)
        }
    }

    private var gettingAroundSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.swipeBetweenTabs), isOn: $settings.swipeBetweenTabs)
                .settingsRow(.swipeBetweenTabs)
        } header: {
            SettingsHeader(section: .gettingAround)
        } footer: {
            Text(SettingSection.gettingAround.footer)
        }
    }
}

// MARK: - Videos

/// Auto-play in grids and on a pin's page, how far the player's skip buttons jump, the video
/// quality (also on iCloud & storage), and writing down the words spoken in videos.
struct SettingsVideosPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore

    /// The jumps the skip buttons can have (the player shows the matching arrows).
    nonisolated static let skipChoices = [5, 10, 15, 20, 30]

    var body: some View {
        SettingsForm(.videos) {
            videoSection
            playerSection
            SettingsVideoQualitySection(id: .videoQualityInVideos)
            transcriptSection
        }
    }

    private var videoSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.autoPlayGrids), isOn: $settings.autoPlayVideos)
                .settingsRow(.autoPlayGrids)
            Toggle(SettingsCatalog.title(.autoPlayPage), isOn: $settings.autoPlayOnPage)
                .settingsRow(.autoPlayPage)
        } header: {
            SettingsHeader(section: .videos)
        } footer: {
            Text(SettingSection.videos.footer)
        }
    }

    private var playerSection: some View {
        Section {
            Picker(SettingsCatalog.title(.skipSeconds), selection: $settings.videoSkipSeconds) {
                ForEach(SettingsVideosPage.skipChoices, id: \.self) { (seconds: Int) in
                    Text("\(seconds) seconds").tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .settingsRow(.skipSeconds)
        } header: {
            SettingsHeader(section: .player)
        } footer: {
            Text(SettingSection.player.footer)
        }
    }

    /// "Transcribe speech in videos": the on-device recogniser writes down what is said in a video
    /// after it is added and puts the words in the pin's note (VideoTranscripts.swift). Under the
    /// switch, one line of how the work is going — or, when no run is at work, what the last run
    /// left on purpose (see `SettingsVideosText.line`) — and a button that listens to the videos
    /// already in the library. (Turning Offline mode off starts waiting videos: ContentView.)
    private var transcriptSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.transcribe), isOn: $settings.transcribeVideos)
                // Switched on: the videos waiting for a transcript are listened to from now, not only
                // after the next launch (VideoTranscripts.swift starts nothing while the switch is off).
                .onChange(of: settings.transcribeVideos) { _, on in
                    if on { store.startTranscribingIfNeeded(delay: 2) }
                }
                .settingsRow(.transcribe)
            if let line = SettingsVideosText.line(status: store.transcriptionStatus,
                                                  closing: store.transcriptionClosing) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(SettingsCatalog.title(.transcribeExisting)) {
                store.startTranscribingAllVideos()
            }
            .disabled(!SettingsVideosText.canTranscribeExisting(switchIsOn: settings.transcribeVideos,
                                                                status: store.transcriptionStatus))
            .settingsRow(.transcribeExisting)
        } header: {
            SettingsHeader(section: .transcripts)
        } footer: {
            Text(SettingsVideosText.transcriptFooter)
        }
    }
}

/// The words under the transcript rows of Settings › Videos, and when its button works (pure, so the
/// harness can check them).
enum SettingsVideosText {
    /// The footer under "Transcribe speech in videos": what happens, where the words go, that nothing
    /// is sent anywhere, and that the language files come down once.
    nonisolated static let transcriptFooter = SettingsWords.transcripts

    /// The one line shown under the switch. `status`: how a run that is at work is getting on
    /// ("Transcribing 2 of 5…") — it comes first. `closing`: what the last run left on purpose when it
    /// ended ("The speech files … have to be downloaded first. Turn off Offline mode…"). The two are
    /// kept apart in the store so that a line left behind is only ever something to read: it is never
    /// mistaken for "a run is going" (see `canTranscribeExisting`).
    nonisolated static func line(status: String?, closing: String?) -> String? {
        status ?? closing
    }

    /// "Transcribe existing videos" works unless a run is at work right now (the store shows its
    /// progress line, `transcriptionStatus`, while one is). Nothing else dims it: it is an explicit
    /// ask, so it works with the switch off too (the store listens to the videos then as well), and a
    /// line a run left behind ("…try again", "…turn off Offline mode") is the very reason to press it.
    /// (`switchIsOn` is only kept so that the call reads as it always did; it is not looked at.)
    nonisolated static func canTranscribeExisting(switchIsOn: Bool, status: String?) -> Bool {
        status == nil
    }
}

// MARK: - Links

/// Link previews, a picture for links that have none, reading links fully and cleaning links. (Where
/// web searches open is on Explore & web search now.) In Offline mode the rows that need the
/// internet are dimmed, not hidden.
struct SettingsLinksPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow

    var body: some View {
        SettingsForm(.links) {
            previewSection
            // Reading links fully (articles, Pinterest pins, YouTube videos): SmartLinksViews.swift.
            SmartLinkSettingsSection()
                .disabled(settings.offlineMode)
            linkCleaningSection   // (cleaning needs no internet: it works in Offline mode too)
        }
    }

    /// "Fetch link previews" and "Find a picture for links without one": a link whose page has no
    /// picture of its own gets the first picture Explore's image source finds for the link's title
    /// (the link readers in SmartLinks*.swift and LinkPins.swift look at this switch). A link kept
    /// in Hidden is never searched for, and the footer says so. The second is dimmed while "Fetch
    /// link previews" is off, because with no previews nothing is fetched at all.
    private var previewSection: some View {
        Section {
            if settings.offlineMode {
                SettingsOfflineNote()
            }
            Toggle(SettingsCatalog.title(.fetchPreviews), isOn: $settings.fetchLinkPreviews)
                .disabled(settings.offlineMode)
                .settingsRow(.fetchPreviews)
            Toggle(SettingsCatalog.title(.linkPictures), isOn: $settings.linkPicturesFromWebSearch)
                .disabled(!settings.webAllowed || !settings.fetchLinkPreviews)
                .settingsRow(.linkPictures)
        } header: {
            SettingsHeader(section: .links)
        } footer: {
            Text(SettingSection.links.footer + " " + SettingsLinksText.linkPictureFooter(previewsAreOn: settings.fetchLinkPreviews))
        }
    }

    private var linkCleaningSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.cleanLinks), isOn: $settings.cleanLinks)
                .settingsRow(.cleanLinks)
            // The normal side's links only (hidden pins have nothing here, as everywhere in Settings).
            Button(SettingsCatalog.title(.cleanExistingLinks)) {
                importFlow.flash(LinkCleaner.cleanedText(count: store.cleanAllLinks(scope: .visible)))
            }
            .settingsRow(.cleanExistingLinks)
        } header: {
            SettingsHeader(section: .cleanLinks)
        } footer: {
            Text(SettingSection.cleanLinks.footer)
        }
    }
}

/// The words under "Find a picture for links without one" (Links) and "Search on the web" (Explore &
/// web search), pure so the harness can check them: no "Safari" — the browser is whichever the
/// person made their default.
enum SettingsLinksText {
    /// The footer under "Open web searches in" and "Hand the picture over by": what PinBoard's own
    /// browser keeps, what the default browser does, the three ways a picture that has no web address
    /// of its own reaches the search page, the one thing Photos needs, and the one pin that never
    /// follows the choice (a hidden pin's picture only ever goes to the clipboard, which clears
    /// itself — a copy in Photos or Files would stay for good, outside the hidden side).
    nonisolated static let searchFooter = SettingsWords.webSearches

    /// The owner's own sentences under "Find a picture for links without one".
    nonisolated static let linkPictureWords = "When a page has no picture of its own, PinBoard uses the first picture Explore's source finds for the link's title. It may not be a picture from that site."

    /// Said under that switch too: a link kept in Hidden never has its title sent to the image source
    /// (the page's own pictures are still tried — they come from the link's own site, which reading the
    /// link asks anyway).
    nonisolated static let hiddenLinksNote = "Links in Hidden are never searched for."

    /// The footer under "Find a picture for links without one". While "Fetch link previews" is off the
    /// switch is dimmed, and the footer says why.
    nonisolated static func linkPictureFooter(previewsAreOn: Bool) -> String {
        let what = "\(linkPictureWords) \(hiddenLinksNote)"
        if previewsAreOn { return what }
        return "\(what) Turn on “Fetch link previews” to use this."
    }
}

// MARK: - AI

/// On-device AI, the optional cloud model, and sorting or naming every pin with the AI.
struct SettingsAIPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var session: SettingsSession
    @State private var revealKeys = false

    var body: some View {
        SettingsForm(.ai) {
            onDeviceSection
            cloudSection
            sortingSection
        }
        .sheet(item: $session.cloudConsentFor) { (provider: CloudProvider) in
            CloudConsentSheet(provider: provider)
        }
    }

    private var onDeviceSection: some View {
        Section {
            Toggle(SettingsCatalog.title(.autoTitle), isOn: $settings.autoTitle)
                .settingsRow(.autoTitle)
            Toggle(SettingsCatalog.title(.accurateOCR), isOn: $settings.accurateOCR)
                .settingsRow(.accurateOCR)
            HiddenAISwitch(id: .hiddenAIInAI)
                .settingsRow(.hiddenAIInAI)
            if AppleIntelligence.isAvailable {
                Toggle(SettingsCatalog.title(.appleIntelligence), isOn: $settings.useAppleIntelligence)
                    .settingsRow(.appleIntelligence)
            } else {
                HStack {
                    Text("Apple Intelligence")
                    Spacer()
                    Text("Not available on this device")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .settingsRow(.appleIntelligence)
            }
        } header: {
            SettingsHeader(section: .onDeviceAI)
        } footer: {
            Text(AppleIntelligence.isAvailable
                 ? "Apple Intelligence writes more natural titles, adds related words to searches and composes web searches from everything known about an image — trusting your board names and tags first. It only ever sees text, never the picture, and runs on this device. Apple offers no cloud version to apps. " + SettingsWords.hiddenAI
                 : "Tags (objects, scenes, colours, people count, cats and dogs), text reading, search and suggestions work on every device using the built-in Vision and Natural Language frameworks. " + SettingsWords.hiddenAI)
        }
    }

    /// Dimmed in Offline mode (the cloud model is never contacted then), not hidden.
    private var cloudSection: some View {
        Section {
            if settings.offlineMode {
                SettingsOfflineNote()
            }
            Toggle(SettingsCatalog.title(.cloudAI), isOn: cloudSwitch)
                .settingsRow(.cloudAI)
            if cloudOn {
                cloudDetails
            }
        } header: {
            SettingsHeader(section: .cloudAI)
        } footer: {
            Text(SettingsAIText.cloudFooter(enabled: cloudOn, provider: settings.cloudProvider, includesHidden: settings.aiIncludesHidden))
        }
        .disabled(settings.offlineMode)
    }

    /// The switch shows on only with consent for the chosen provider (`cloudSwitchShowsOn`).
    private var cloudOn: Bool {
        settings.cloudSwitchShowsOn
    }

    /// Turning it on asks for consent first, naming the provider (the switch stays off until then).
    private var cloudSwitch: Binding<Bool> {
        Binding(
            get: { cloudOn },
            set: { wanted in
                if wanted && !settings.hasCloudConsent(for: settings.cloudProvider) {
                    session.cloudConsentFor = settings.cloudProvider
                } else {
                    settings.cloudEnabled = wanted
                }
            })
    }

    /// Choosing the other provider while Cloud AI is on asks again, naming that company: the
    /// pictures would go somewhere else. The choice only changes once the sheet is agreed to.
    private var providerChoice: Binding<CloudProvider> {
        Binding(
            get: { settings.cloudProvider },
            set: { (chosen: CloudProvider) in
                if settings.hasCloudConsent(for: chosen) {
                    settings.cloudProvider = chosen
                } else {
                    session.cloudConsentFor = chosen
                }
            })
    }

    @ViewBuilder
    private var cloudDetails: some View {
        Picker(SettingsCatalog.title(.cloudProvider), selection: providerChoice) {
            ForEach(CloudProvider.allCases) { provider in
                Text(provider.label).tag(provider)
            }
        }
        .settingsRow(.cloudProvider)
        SettingsKeyField(title: SettingsCatalog.title(.cloudKey), text: $settings.cloudKey, placeholder: settings.cloudProvider.keyPlaceholder, reveal: revealKeys)
            .settingsRow(.cloudKey)
        HStack {
            Text(SettingsCatalog.title(.cloudModel))
            NativeTextField(placeholder: settings.cloudProvider.defaultModel,
                            text: $settings.cloudModel,
                            autocapitalization: .none,
                            autocorrection: false,
                            alignment: .right)
        }
        .settingsRow(.cloudModel)
        Toggle(SettingsWords.showKeys, isOn: $revealKeys)
        if let url = settings.cloudProvider.signupURL {
            Link("Get a key from \(settings.cloudProvider.label)", destination: url)
        }
        if let error = store.cloudLastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Button(SettingsCatalog.title(.rerunCloud)) {
            store.reanalyze(scope: .visible)   // the normal library's pins (hidden ones have their own run in Hidden)
        }
        .disabled(!settings.cloudActive || store.visiblePins.isEmpty)
        .settingsRow(.rerunCloud)
    }

    /// Boards, tags and names for every pin (hidden pins have their own in Hidden's ⋯ menu).
    private var sortingSection: some View {
        Section {
            AISortingMenu(target: .all(.visible), prompt: $session.aiPrompt)
                .disabled(store.visiblePins.isEmpty)
                .settingsRow(.aiSorting)
            if store.namingScope == .visible, let progress = store.namingProgress {
                HStack(spacing: 8) {
                    WorkProgressLine(text: "Renaming… \(progress.done.formatted()) of \(progress.total.formatted())")
                    Spacer()
                    Button("Stop") { store.stopNaming() }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            SettingsHeader(section: .aiSorting)
        } footer: {
            Text(SettingSection.aiSorting.footer)
        }
    }
}

/// The words that say what the cloud model is sent: the footer under the switch and the lines on
/// the consent sheet (pure, so the harness can check they say what `CloudAI` really sends).
enum SettingsAIText {
    /// The footer under "Use a cloud vision model". A link's text goes to the model with its
    /// picture (up to `CloudAI.maximumPageText` = 1,500 characters), so the footer must not say
    /// that nothing else leaves the device.
    /// `includesHidden`: "Include hidden pins in Cloud AI" is on.
    nonisolated static func cloudFooter(enabled: Bool, provider: CloudProvider, includesHidden: Bool = false) -> String {
        if enabled {
            let sent = "Each new image is sent once, downscaled and stripped of all metadata, together with the names of its boards and your tags for it. For a link, the text read from its page (up to 1,500 characters) is sent with its preview picture."
            let hidden = includesHidden
                ? "Hidden pins are included: their pictures, titles, tags and text go to " + provider.company + " too (never the names of hidden boards)."
                : "Hidden pins are never sent (“Include hidden pins in AI” is off)."
            let to = "Everything goes to " + provider.company + " (" + provider.host + "), under " + provider.company + "'s privacy policy."
            let rest = "You pay " + provider.company + " per image (usually a fraction of a cent). Your notes, your location and your other images are not sent."
            return sent + " " + to + " " + hidden + " " + rest
        }
        return "Apple doesn't let apps use its cloud models, so this is the one way to get a model that actually looks at the picture: far more specific tags, real titles and better searches. Needs your own API key and sends each image to that provider once, with its boards, your tags and, for a link, the text read from its page."
    }

    /// The lines on the consent sheet, one bullet each (the sheet names the company and links
    /// its privacy policy above and below them).
    nonisolated static let consentLines: [String] = [
        "Sent: a copy of the image, shrunk to at most 1024 pixels, with all metadata (location, camera, dates) removed.",
        "Sent: the names of the boards the image is on and the tags you gave it, so the title and the suggested web search fit your own words.",
        "Sent: for a link, the text read from its page (up to 1,500 characters), together with its preview picture, so the title and tags fit what the page says.",
        "Hidden pins are not sent, unless you turn on “Include hidden pins in AI” — and even then the names of hidden boards never are.",
        "Never sent: your notes, your location, other images.",
        "The provider bills your key per image — usually a fraction of a cent. PinBoard has no account of its own and receives nothing."
    ]
}

/// "Include hidden pins in AI" — one value, shown on Privacy & Hidden and on AI (`id` says which
/// row of the catalog it is). Turned on, the hidden pins that were left out get the AI's look now.
struct HiddenAISwitch: View {
    let id: SettingID
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Toggle(SettingsCatalog.title(id), isOn: Binding(
            get: { settings.aiIncludesHidden },
            set: { (on: Bool) in
                settings.aiIncludesHidden = on
                if on { store.startAnalysisIfNeeded() }
            }))
    }
}

/// A row with a title and a field for a key, secret while `reveal` is off.
struct SettingsKeyField: View {
    let title: String
    let text: Binding<String>
    var placeholder: String = "Paste here"
    let reveal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                NativeTextField(placeholder: placeholder,
                                text: text,
                                autocapitalization: .none,
                                autocorrection: false,
                                alignment: .right,
                                secure: !reveal)
            }
            #if !DEBUG
            // The Keychain refused a key: it is not stored anywhere (see SecureStore).
            if !SecureStore.keychainWorks && !text.wrappedValue.isEmpty {
                Label(SecureStore.notSavedMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            #endif
        }
    }
}

