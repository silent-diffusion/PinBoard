//
//  SettingsCatalog.swift  —  PinBoard
//
//  The one list of everything Settings shows: its pages, the sections on each page (header and
//  footer), and every row (its name, where it is, the preference it changes, and other words
//  people may use for it, speech-to-text spellings included). The pages take their row names and
//  footers from here, the search in Settings looks through it, and the "Settings › …" paths the
//  app writes elsewhere are made from it, so they stay right when something moves.
//
//  Adding a setting: add it to AppSettings, ProfileSettings.preferenceKeys and the adopt lists
//  (and SettingsSync.syncedKeys if it travels), as always, AND give it an entry here and a
//  `.settingsRow(.yourID)` on its page. Keep the two in step: every stored
//  setting needs an entry, and every entry needs a row.
//
//  Plain Foundation only (no SwiftUI), so the rules here can be tested anywhere.
//

import Foundation

// MARK: - The pages

/// A screen in Settings: the pages of the list, and the screens inside the Library page. Other
/// screens (and the sheet's `opening:`) name one of these to open Settings right there.
enum SettingsDestination: Hashable, Sendable {
    // The list's pages.
    case appearance, pinsAndBoards, videos, links, ai, explore, privacy, iCloudAndStorage, library, about
    // Screens inside the Library page.
    case profiles, recentlyDeleted, duplicates, tags, recover
    // Screens inside the Pins & boards page.
    case homePage

    /// The pages of the list, in the order they are shown.
    nonisolated static let pages: [SettingsDestination] = [
        .appearance, .pinsAndBoards, .videos, .links, .ai, .explore, .privacy, .iCloudAndStorage, .library, .about
    ]

    /// How the list groups its pages: everyday things first, sync, storage and your data last.
    nonisolated static let groups: [[SettingsDestination]] = [
        [.appearance, .pinsAndBoards, .videos, .links],
        [.ai, .explore],
        [.privacy, .iCloudAndStorage],
        [.library, .about]
    ]

    nonisolated var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .pinsAndBoards: return "Pins & boards"
        case .videos: return "Videos"
        case .links: return "Links"
        case .ai: return "AI"
        case .explore: return "Explore & web search"
        case .privacy: return "Privacy & Hidden"
        case .iCloudAndStorage: return "iCloud & storage"
        case .library: return "Library"
        case .about: return "About"
        case .profiles: return "Profiles"
        case .recentlyDeleted: return "Recently Deleted"
        case .duplicates: return "Possible duplicates"
        case .tags: return "Your tags"
        case .recover: return "Recover library"
        case .homePage: return "Home page"
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .appearance: return "paintbrush"
        case .pinsAndBoards: return "square.grid.2x2"
        case .videos: return "play.rectangle"
        case .links: return "link"
        case .ai: return "sparkles"
        case .explore: return "globe"
        case .privacy: return "lock.shield"
        case .iCloudAndStorage: return "icloud"
        case .library: return "books.vertical"
        case .about: return "info.circle"
        case .profiles: return "person.2"
        case .recentlyDeleted: return "trash"
        case .duplicates: return "square.on.square"
        case .tags: return "tag"
        case .recover: return "clock.arrow.circlepath"
        case .homePage: return "house"
        }
    }

    /// The screens to push, in order, to land here: a page of the list alone, or the Library page
    /// and then the screen inside it ("Possible duplicates" = Library, then Possible duplicates).
    nonisolated var trail: [SettingsDestination] {
        switch self {
        case .profiles, .recentlyDeleted, .duplicates, .tags, .recover:
            return [.library, self]
        case .homePage:
            return [.pinsAndBoards, self]
        default:
            return [self]
        }
    }
}

// MARK: - The sections of each page

/// A section of a page: its header (may be empty) and footer. Pages show these words; the search
/// looks through them too.
enum SettingSection: String, CaseIterable, Sendable {
    case appearance, appIcon, grid, textPins
    case homePage, order, boards, sharing, widgets, gettingAround
    case videos, player, videoQualityInVideos, transcripts
    case links, reading, cleanLinks
    case onDeviceAI, cloudAI, aiSorting
    case imageSource, suggestions, webSearches
    case offline, hidden, privacy
    case iCloud, deviceStorage, videoQuality, originals
    case profiles, lists, yourData, backups, clear
    case about

    nonisolated var page: SettingsDestination {
        switch self {
        case .appearance, .appIcon, .grid, .textPins: return .appearance
        case .homePage, .order, .boards, .sharing, .widgets, .gettingAround: return .pinsAndBoards
        case .videos, .player, .videoQualityInVideos, .transcripts: return .videos
        case .links, .reading, .cleanLinks: return .links
        case .onDeviceAI, .cloudAI, .aiSorting: return .ai
        case .imageSource, .suggestions, .webSearches: return .explore
        case .offline, .hidden, .privacy: return .privacy
        case .iCloud, .deviceStorage, .videoQuality, .originals: return .iCloudAndStorage
        case .profiles, .lists, .yourData, .backups, .clear: return .library
        case .about: return .about
        }
    }

    nonisolated var header: String {
        switch self {
        case .appearance: return "Appearance"
        case .grid: return "Grid"
        case .textPins: return "Text pins"
        case .homePage: return "Home page"
        case .order: return "Order"
        case .boards: return "Boards"
        case .sharing: return "Sharing"
        case .widgets: return "Widgets"
        case .gettingAround: return "Getting around"
        case .videos: return "Videos"
        case .player: return "Player"
        case .videoQualityInVideos, .videoQuality: return "Video quality"
        case .transcripts: return "Transcripts"
        case .links: return "Links"
        case .reading: return "Reading links"
        case .cleanLinks: return "Clean links"
        case .onDeviceAI: return "On-device AI"
        case .cloudAI: return "Cloud AI (optional)"
        case .aiSorting: return "AI sorting"
        case .imageSource: return "Image source"
        case .suggestions: return "Web suggestions"
        case .webSearches: return "Search on the web"
        case .offline: return "Network"
        case .hidden: return "Hidden pins and boards"
        case .privacy: return "Privacy"
        case .iCloud: return "iCloud"
        case .deviceStorage: return "Device storage"
        case .originals: return "Originals and size"
        case .yourData: return "Your data"
        case .backups: return "Backups"
        case .about: return "About"
        case .appIcon, .profiles, .lists, .clear: return ""
        }
    }

    /// The footer under the section. A few pages say more or other words depending on what is on
    /// (Offline mode, the cloud model, the keychain, iCloud): those pages build their own footer,
    /// and this is the usual one, which the search reads.
    nonisolated var footer: String {
        switch self {
        case .grid: return "Large numbers only take effect on wide screens; columns never get narrower than about 88 points."
        case .appIcon: return SettingsWords.appIcon
        case .textPins: return SettingsWords.textPins
        case .homePage: return SettingsWords.homePage
        case .order: return SettingsWords.order
        case .boards: return SettingsWords.boards
        case .sharing: return SettingsWords.sharing
        case .widgets: return SettingsWords.widgets
        case .gettingAround: return SettingsWords.gettingAround
        case .videos: return SettingsWords.videos
        case .player: return SettingsWords.player
        case .videoQualityInVideos, .videoQuality: return SettingsWords.videoQuality
        case .transcripts: return SettingsWords.transcripts
        default: return otherFooter
        }
    }

    /// (Split off so neither switch is long for the compiler on the iPad.)
    nonisolated private var otherFooter: String {
        switch self {
        case .links: return "When a link is saved, its page is fetched once for the title and a preview picture, which are kept in your library. Off: the card shows the address only."
        case .reading: return "When you add a link, PinBoard reads the page: an article's text, writer and date; a Pinterest pin's picture; a YouTube video's details from YouTube's own service and, with a YouTube Data API key, its top comments. Posts on Reddit, TikTok, Instagram and X are read as far as each site shows them to a visitor. A video on those sites or inside a web page is kept as a link with its picture: download it in its own app, then save it to PinBoard."
        case .cleanLinks: return "Takes the tracking out of links you add — the “?utm_…”, “fbclid” and such that only tell a site who shared it. The page you get is the same."
        case .onDeviceAI: return "Tags (objects, scenes, colours, people count, cats and dogs), text reading, search and suggestions work on every device using the built-in Vision and Natural Language frameworks. Apple Intelligence writes more natural titles and only ever sees text. Hidden pins get none of this unless “Include hidden pins in AI” is on."
        case .cloudAI: return "Apple doesn't let apps use its cloud models, so this is the one way to get a model that actually looks at the picture: far more specific tags, real titles and better searches. Needs your own API key."
        case .aiSorting: return "Sorts every pin into boards, gives them tags and names them. Hidden pins have their own in Hidden's ⋯ menu."
        case .imageSource: return "The source Explore, board pages and pin pages search, and “Find a picture for links without one” uses. Keys are stored in the iOS Keychain and sent only to the service they belong to, over HTTPS."
        case .suggestions: return "Board pages and pin pages fetch web results only when you ask, unless “Automatically load” is on; the Explore tab searches when you tap Search."
        case .webSearches: return SettingsWords.webSearches
        default: return lastFooter
        }
    }

    /// (Split off as above.)
    nonisolated private var lastFooter: String {
        switch self {
        case .offline: return "Turn this on to switch off everything that uses the internet: Explore, web feeds, link previews, Cloud AI, iCloud sync and the speech recogniser's language download."
        case .hidden: return SettingsWords.hidden
        case .iCloud: return "Your library is kept in this app's iCloud Drive folder and merged with your other devices."
        case .deviceStorage: return "Full-size pictures and videos you haven't added or opened in a while are kept in iCloud only. Thumbnails stay, so browsing and search work offline."
        case .originals: return "Originals: full-size pictures and videos are copied to the folder you choose — pick one in iCloud Drive to keep them off this device."
        case .profiles: return "Each profile is a completely separate library, with its own settings (iCloud sync included). Switching happens only here."
        case .lists: return "Rename, merge or delete the tags you gave to pins."
        case .yourData: return "The export is a folder per board (sub-boards nested), with every pin's title, tags and notes, plus a library.json for an exact re-import. “Import a folder…” takes an export or any folder of pictures, videos and text files."
        case .backups: return "PinBoard keeps a copy of the library file from a few minutes ago and one from the previous day, so a bad save is never the only version."
        default: return ""
        }
    }
}

/// The longer footers, kept apart so the switches above stay short. They are shown as they are.
enum SettingsWords {
    /// Under the App icon row. The choice is iOS's own, kept per device (AppIconPicker.swift).
    nonisolated static let appIcon = "The icon on this device's Home Screen. iOS shows its light, dark or tinted look to match the Home Screen. The choice belongs to this iPhone or iPad: it stays the same in every profile and isn't synced to your other devices."
    nonisolated static let textPins = "Text pins sit in the grid like any other pin. Add one from the + menu on the Pins tab or on a board. The sizes are for the standard text size: text pins grow and shrink with the text size chosen in the Settings app."
    /// The Home page is the Pins tab (the tab keeps its name); only Settings calls it the Home page.
    nonisolated static let homePage = "The Home page is the Pins tab. “Keep off Home page” (in a pin's or a board's menu) takes pins off its All and Unsorted without hiding them: they still show on their boards, in Search and in smart boards. Open this to see them all and put any back."
    nonisolated static let order = "The same choices as in the ⋯ menus: Sort boards on the Boards tab, in Hidden and on a board's page; Order of pins on the Pins tab and on a board's page (one order for every board). Changing one changes the other. Favorites always stay on top. A shuffled list is shuffled again when you pull it down."
    nonisolated static let boards = "A board's page also shows the pins of its sub-boards, as if they were on the board itself. A pin you move into a sub-board counts as being on the boards above it already, and is never listed twice. Each board page can still switch this on or off for itself."
    nonisolated static let sharing = "When you share pictures, videos, links or text to PinBoard from another app, you choose the board and profile in the share sheet. Off: it saves straight away, to no board in the profile open here, and closes by itself. A picture or video that looks like one you already have is still asked about, so nothing is saved twice; the same link or text already in PinBoard is never saved again."
    nonisolated static let widgets = "PinBoard's widgets (Photo, Photo Grid and Quote) each show one board, or all of them. Choose the board on the widget itself: touch and hold it on the Home Screen and choose Edit Widget. For two widgets on the same board, give each its own Pick so they never show the same photo. Widgets never show hidden pins."
    /// Added after the footer above, on a Mac only.
    nonisolated static let widgetsOnMac = "On a Mac, add them from the widget gallery under PinBoard (this Mac's app), not under “From iPhone”: the iPhone's copies can't show your photos on a Mac. On the desktop, Control-click a widget and choose Edit to pick its board."
    nonisolated static let gettingAround = "Swipe left or right on Pins, Boards, Explore or Search to move to the next tab. Inside a board or a pin, swiping works as usual."
    nonisolated static let videos = "In grids, videos on screen play silently (a few at a time; the rest show a still frame); tap a card's speaker for sound. On a pin's page and in Quick Look, PinBoard's own player has a play button in the middle with skip buttons on either side, and along the bottom the time bar, sound, and on a pin's page a button that opens Quick Look (tap the video to show or hide them). Double-tap the video to skip by the skip-button step: in its upper part, left goes back and right goes forward; in its bottom third, left goes forward and right goes back. Tap the time bar to jump there, or drag it to move from where the video is; drag further above it for finer steps. Videos start over when they reach the end. Once you turn sound on it stays on for every video you open, until you turn it off. A video carries on where it stopped, wherever you open it next, until the app is closed. Auto-play on a pin's page: the video starts by itself and pauses when you scroll away. Off: press play."
    nonisolated static let player = "How far the buttons on either side of play jump back or forward. In Quick Look, touch and hold a video for a second to play it at double speed for as long as you hold; slide down while holding to keep 2× on, and do the same again to turn it off. The ⋯ menu there has other speeds."
    /// Under "Video quality", the same on the Videos page and on iCloud & storage.
    nonisolated static let videoQuality = "A video is added exactly as it is, at once; afterwards, in the background, those larger than the chosen size are converted so they take less room, and smaller ones are kept as they are. “Convert existing videos…” (iCloud & storage) does the videos already in your library."
    nonisolated static let transcripts = "Words spoken in a video are written down on this device after the video is added, and put in the pin's note. Nothing is sent anywhere. The first time, the speech recogniser's language files are downloaded."
    nonisolated static let webSearches = "PinBoard's browser keeps nothing: no cookies, no history, no cache. Your default browser opens the search in that app instead. A picture that lives only in your library has no web address, so PinBoard hands it to you for the page: copied to the clipboard for two minutes (on this device only), saved to a folder you choose in Files, or saved to Photos (the newest picture in Recents). The first time, iOS asks whether PinBoard may add to Photos. A hidden pin's picture always goes to the clipboard, whatever you chose here. Then upload it on the search page."
    nonisolated static let hidden = "Hidden pins and boards live in Boards › ⋯ › Hidden. Touch and hold a board and choose “Hide board”, or choose “Hide pin” on a pin. Hidden pins stay out of every other screen. Once unlocked, Hidden stays open until PinBoard goes to the background, you switch profiles or you choose “Lock now” in its ⋯ menu. “Order of pins in Hidden” is the same choice as in Hidden's ⋯ menu. " + SettingsWords.hiddenAI
    nonisolated static let about = "PinBoard keeps everything on this device. Image tagging, text reading, writing down speech, search and board suggestions run locally; the only network use is the web image search you start yourself, link previews and reading the links you add (and a web image search for a link that has no picture, if you turn that on), the speech recogniser's language files the first time, the cloud model if you turn it on, and iCloud sync if you turn that on."
    /// The friendly note about videos from other apps (PinBoard doesn't download them, App Review
    /// guideline 5.2.3): in the Links footer, in the search, and once on a link pin from one of those
    /// sites (`PlatformVideoNote`).
    nonisolated static let videoNote = "Most apps let you download a video inside the app itself. If you'd like the video in PinBoard, download it there, then save it to PinBoard (from Photos or with the share sheet)."
    /// What "Include hidden pins in AI" means (under Privacy & Hidden and AI).
    nonisolated static let hiddenAI = "Include hidden pins in AI: off, no AI looks at hidden pins — no tags, no reading of text in pictures, no AI titles, no Apple Intelligence, no speech transcripts and no Cloud AI. Only PinBoard's fixed checks run on them: colours, finding duplicates (pictures are still compared on this device), and searching the words you typed. Tags and titles the AI made before stay; “Remove AI tags from hidden pins” takes them out. On, hidden pins get the AI like any other pin — with Cloud AI on, their pictures go to its company too."
    /// The switch that shows API keys as they are typed (three pages have one; none is remembered).
    nonisolated static let showKeys = "Show keys"
}

// MARK: - The rows

/// One row of Settings. Its id is also how the page marks the row (`.settingsRow(_:)`), so the
/// search can scroll to it.
enum SettingID: String, CaseIterable, Sendable {
    // Appearance
    case theme, accentColor, customAccent, appIcon, columns
    case textFont, textBoardSize, textPageSize, textLines, textShowsTitle, textUsesAccent, textColor
    // Pins & boards
    case homePage, sortBoards, pinsTabOrder, boardPagesOrder, subBoardPins, chooseBoardWhenSharing, widgets
    case swipeBetweenTabs
    // Videos
    case autoPlayGrids, autoPlayPage, sound, skipSeconds, speed, videoQualityInVideos, transcribe, transcribeExisting
    // Links
    case fetchPreviews, linkPictures, readLinksFully, youTubeKey, socialVideos, readExistingLinks, cleanLinks, cleanExistingLinks
    // AI
    case autoTitle, accurateOCR, appleIntelligence, hiddenAIInAI, cloudAI, cloudProvider, cloudKey, cloudModel, rerunCloud, aiSorting
    // Explore & web search
    case imageSource, openverseID, openverseSecret, pexelsKey, pixabayKey, unsplashKey
    case autoLoadWeb, boardWebIdeas, clearExploreSearches, webSearchBrowser, webSearchHandoff
    // Privacy & Hidden
    case offlineMode, lockHidden, hiddenAI, removeHiddenAI, hiddenOrder, privacyPromises
    // iCloud & storage
    case iCloudSync, syncNow, syncLog, optimizeStorage, videoQuality, keepOriginals, librarySize, convertVideos
    // Library
    case profiles, recentlyDeleted, duplicates, tags, export, importFolder, recover, clearLibrary
    // About
    case about
}

/// What a row is, so the search can say so (and the harness knows which ones change something).
enum SettingKind: String, Sendable {
    case toggle, choice, stepper, color, text, key, button, screen, info
}

/// Everything known about one row.
struct SettingEntry: Sendable {
    let id: SettingID
    let title: String
    let section: SettingSection
    let kind: SettingKind
    /// The preference it changes (AppSettings' name for it, or a Keychain name for a key; nil
    /// for buttons, screens and lines of information).
    let key: String?
    /// Other words for it, lower case: what people may type instead, speech-to-text spellings too.
    let synonyms: [String]
    /// Said in the search results when the row isn't always shown ("Shown when … is on").
    let shownWhen: String?
    /// The row to open and highlight instead (the one that makes this row appear).
    let opensAt: SettingID?

    nonisolated var page: SettingsDestination { section.page }
}

// MARK: - The catalog

enum SettingsCatalog {
    /// Every row, in the order of the pages.
    nonisolated static let entries: [SettingEntry] = appearanceRows() + pinsAndBoardsRows() + videoRows()
        + linkRows() + aiRows() + exploreRows() + privacyRows() + storageRows() + libraryRows()

    nonisolated private static let byID: [SettingID: SettingEntry] = {
        var all: [SettingID: SettingEntry] = [:]
        for entry in entries { all[entry.id] = entry }
        return all
    }()

    /// The row with this id. (Every id has one: the harness checks it.)
    nonisolated static func entry(_ id: SettingID) -> SettingEntry {
        byID[id] ?? SettingEntry(id: id, title: id.rawValue, section: .about, kind: .info, key: nil,
                                 synonyms: [], shownWhen: nil, opensAt: nil)
    }

    /// The row's name as the page shows it.
    nonisolated static func title(_ id: SettingID) -> String {
        entry(id).title
    }

    /// "Settings › Privacy & Hidden › Hidden pins and boards": where the row's section is. (A
    /// section without a header, or named like its page, is left out.)
    nonisolated static func path(_ id: SettingID) -> String {
        "Settings › " + place(entry(id).section)
    }

    /// "Settings › Library › Import a folder…": the page, then the row itself.
    nonisolated static func rowPath(_ id: SettingID) -> String {
        let entry = entry(id)
        return "Settings › " + entry.page.title + " › " + entry.title
    }

    /// "Privacy & Hidden › Hidden pins and boards" (the grey line under a search result).
    nonisolated static func place(_ section: SettingSection) -> String {
        let header = section.header
        if header.isEmpty || header == section.page.title { return section.page.title }
        return section.page.title + " › " + header
    }

    /// Short helper so the lists below stay readable.
    nonisolated private static func row(_ id: SettingID, _ title: String, _ section: SettingSection, _ kind: SettingKind,
                                        key: String? = nil, _ synonyms: [String] = [],
                                        shownWhen: String? = nil, opensAt: SettingID? = nil) -> SettingEntry {
        SettingEntry(id: id, title: title, section: section, kind: kind, key: key, synonyms: synonyms,
                     shownWhen: shownWhen, opensAt: opensAt)
    }

    // MARK: Rows, page by page

    nonisolated private static func appearanceRows() -> [SettingEntry] {
        let colour = ["colour", "color", "tint"]
        let text = ["text pins", "notes", "font size", "text size"]
        let list: [SettingEntry] = [
            row(.theme, "Theme", .appearance, .choice, key: "appearance", ["dark", "dark mode", "light", "night", "black", "white"]),
            row(.accentColor, "Accent color", .appearance, .choice, key: "accent", colour + ["red", "blue", "green", "pink"]),
            row(.customAccent, "Any other color", .appearance, .color, key: "customAccentHex", colour + ["custom", "hex"]),
            row(.appIcon, "App icon", .appIcon, .choice, ["icon", "logo", "app logo", "home screen", "home screen icon", "alternate icon", "dark icon", "tinted icon"]),
            row(.columns, "Images per row", .grid, .choice, key: "columns", ["columns", "grid", "rows", "size", "pictures per row", "how many"]),
            row(.textFont, "Typeface", .textPins, .choice, key: "textFont", text + ["font", "serif", "rounded", "monospaced"]),
            row(.textBoardSize, "Size on boards", .textPins, .stepper, key: "textBoardSize", text + ["bigger", "smaller"]),
            row(.textPageSize, "Size on the pin's page", .textPins, .stepper, key: "textPageSize", text + ["bigger", "smaller"]),
            row(.textLines, "Lines shown on boards", .textPins, .stepper, key: "textLinesOnBoard", text + ["lines", "length"]),
            row(.textShowsTitle, "Show the title on the card", .textPins, .toggle, key: "textShowsTitle", text),
            row(.textUsesAccent, "Use the accent color for text", .textPins, .toggle, key: "textUsesAccent", text + colour),
            row(.textColor, "Custom text color", .textPins, .color, key: "textColorHex", text + colour)
        ]
        return list
    }

    nonisolated private static func pinsAndBoardsRows() -> [SettingEntry] {
        let order = ["order", "sort", "shuffle", "shuffled", "random", "newest", "oldest"]
        let list: [SettingEntry] = [
            row(.homePage, "Home page", .homePage, .screen, ["home page", "homepage", "home", "kept off", "keep off", "kept out", "keep out", "hidden from pins", "off the pins tab", "pins tab", "show in all", "show on home page"]),
            row(.sortBoards, "Sort boards", .order, .choice, key: "boardSort", ["order", "sort", "alphabetical", "a-z", "name", "recently edited"]),
            row(.pinsTabOrder, "Order of pins on the Pins tab", .order, .choice, key: "pinSort", order),
            row(.boardPagesOrder, "Order of pins on board pages", .order, .choice, key: "boardPinSort", order),
            row(.subBoardPins, "Board pages include sub-board pins", .boards, .toggle, key: "boardPagesIncludeSubBoards", ["sub-boards", "subboards", "nested", "children"]),
            row(.chooseBoardWhenSharing, "Choose a board when sharing", .sharing, .toggle, key: "chooseBoardWhenSharing", ["share sheet", "share", "quick save", "other apps", "extension"]),
            row(.widgets, "Widgets", .widgets, .info, ["widget", "home screen", "pick", "photo grid", "quote"]),
            row(.swipeBetweenTabs, "Swipe between tabs", .gettingAround, .toggle, key: "swipeBetweenTabs", ["swipe", "gestures", "navigation", "tabs"])
        ]
        return list
    }

    nonisolated private static func videoRows() -> [SettingEntry] {
        let quality = ["resolution", "4k", "1080p", "720p", "size", "compress", "convert", "space"]
        let list: [SettingEntry] = [
            row(.autoPlayGrids, "Auto-play videos in grids", .videos, .toggle, key: "autoPlayVideos", ["autoplay", "auto play", "play", "silent", "preview", "movies"]),
            row(.autoPlayPage, "Auto-play on a pin's page", .videos, .toggle, key: "autoPlayOnPage", ["autoplay", "auto play", "play", "movies"]),
            row(.sound, "Sound", .videos, .info, ["sound", "mute", "unmute", "volume", "audio", "speaker", "loud"],
                shownWhen: "No setting: tap the speaker on a video. Sound stays on until you turn it off or close PinBoard.", opensAt: .autoPlayGrids),
            row(.skipSeconds, "Skip buttons jump", .player, .choice, key: "videoSkipSeconds", ["skip", "seconds", "forward", "back", "rewind", "jump", "double tap", "double-tap"]),
            row(.speed, "Playback speed", .player, .info, ["speed", "slow", "fast", "faster", "2x", "double"],
                shownWhen: "No setting: in Quick Look, ⋯ › Speed, or touch and hold a video for 2×.", opensAt: .skipSeconds),
            row(.videoQualityInVideos, "Video quality", .videoQualityInVideos, .choice, key: "videoQuality", quality),
            row(.transcribe, "Transcribe speech in videos", .transcripts, .toggle, key: "transcribeVideos", ["transcript", "transcribe", "captions", "subtitles", "speech", "words", "dictation"]),
            row(.transcribeExisting, "Transcribe existing videos", .transcripts, .button, ["transcript", "captions", "subtitles"])
        ]
        return list
    }

    nonisolated private static func linkRows() -> [SettingEntry] {
        let reading = ["article", "youtube", "pinterest", "tiktok", "reddit", "instagram", "read"]
        let list: [SettingEntry] = [
            row(.fetchPreviews, "Fetch link previews", .links, .toggle, key: "fetchLinkPreviews", ["preview", "thumbnail", "link picture", "url", "web page"]),
            row(.linkPictures, "Find a picture for links without one", .links, .toggle, key: "linkPicturesFromWebSearch", ["picture", "image", "missing", "no picture"]),
            row(.readLinksFully, "Read links fully", .reading, .toggle, key: "readLinksFully", reading),
            row(.youTubeKey, "YouTube API key", .reading, .key, key: "youtube", ["key", "api", "token", "comments", "google"]),
            row(.socialVideos, "Videos from TikTok, Instagram and others", .reading, .info,
                ["video", "download", "save video", "reel", "reels", "tiktok", "instagram", "reddit", "pinterest", "x", "twitter"],
                shownWhen: "Kept as a link with its picture. " + SettingsWords.videoNote, opensAt: .readLinksFully),
            row(.readExistingLinks, "Read existing links", .reading, .button, reading + ["old links", "again"]),
            row(.cleanLinks, "Clean links", .cleanLinks, .toggle, key: "cleanLinks", ["tracking", "utm", "fbclid", "privacy", "clean"]),
            row(.cleanExistingLinks, "Clean existing links", .cleanLinks, .button, ["tracking", "utm", "fbclid"])
        ]
        return list
    }

    nonisolated private static func aiRows() -> [SettingEntry] {
        let cloud = ["cloud", "chatgpt", "chat gpt", "openai", "open ai", "gpt", "claude", "anthropic", "vision"]
        let whenOn = "Shown when “Use a cloud vision model” is on"
        let list: [SettingEntry] = [
            row(.autoTitle, "Write titles for untitled pins", .onDeviceAI, .toggle, key: "autoTitle", ["titles", "names", "naming", "automatic"]),
            row(.accurateOCR, "Accurate text reading (slower)", .onDeviceAI, .toggle, key: "accurateOCR", ["ocr", "text recognition", "read text", "scan"]),
            row(.appleIntelligence, "Use Apple Intelligence", .onDeviceAI, .toggle, key: "useAppleIntelligence", ["apple intelligence", "siri", "language model", "llm"]),
            // The same switch as Privacy & Hidden's (one value, two places, like Video quality).
            row(.hiddenAIInAI, "Include hidden pins in AI", .onDeviceAI, .toggle, key: "aiIncludesHidden",
                ["hidden", "ai", "cloud", "private", "tags", "secret", "privacy"]),
            row(.cloudAI, "Use a cloud vision model", .cloudAI, .toggle, key: "cloudEnabled", cloud),
            row(.cloudProvider, "Provider", .cloudAI, .choice, key: "cloudProvider", cloud, shownWhen: whenOn, opensAt: .cloudAI),
            row(.cloudKey, "API key", .cloudAI, .key, key: "cloud", cloud + ["key", "api", "token"], shownWhen: whenOn, opensAt: .cloudAI),
            row(.cloudModel, "Model", .cloudAI, .text, key: "cloudModel", cloud + ["haiku", "gpt-4o"], shownWhen: whenOn, opensAt: .cloudAI),
            row(.rerunCloud, "Re-run the cloud model on all pins", .cloudAI, .button, cloud + ["again", "redo"], shownWhen: whenOn, opensAt: .cloudAI),
            row(.aiSorting, "AI sorting", .aiSorting, .button, ["sort", "auto-sort", "autosort", "rename", "tags", "boards", "organize", "organise"])
        ]
        return list
    }

    nonisolated private static func exploreRows() -> [SettingEntry] {
        let keys = ["key", "api", "token"]
        let list: [SettingEntry] = [
            row(.imageSource, "Image source", .imageSource, .choice, key: "webSource", ["explore", "source", "wikimedia", "commons", "openverse", "pexels", "pixabay", "unsplash", "web"]),
            row(.openverseID, "Client ID", .imageSource, .key, key: "openverseID", keys + ["openverse"], shownWhen: "Shown when Image source is Openverse", opensAt: .imageSource),
            row(.openverseSecret, "Client secret", .imageSource, .key, key: "openverseSecret", keys + ["openverse"], shownWhen: "Shown when Image source is Openverse", opensAt: .imageSource),
            row(.pexelsKey, "Pexels API key", .imageSource, .key, key: "pexels", keys, shownWhen: "Shown when Image source is Pexels", opensAt: .imageSource),
            row(.pixabayKey, "Pixabay API key", .imageSource, .key, key: "pixabay", keys, shownWhen: "Shown when Image source is Pixabay", opensAt: .imageSource),
            row(.unsplashKey, "Unsplash access key", .imageSource, .key, key: "unsplash", keys, shownWhen: "Shown when Image source is Unsplash", opensAt: .imageSource),
            row(.autoLoadWeb, "Automatically load web suggestions", .suggestions, .toggle, key: "autoLoadWeb", ["web", "suggestions", "explore", "automatic", "ideas"]),
            row(.boardWebIdeas, "Offer web ideas at the end of boards", .suggestions, .toggle, key: "showBoardWebFeed", ["web", "ideas", "web feed", "suggestions"]),
            row(.clearExploreSearches, "Clear recent Explore searches", .suggestions, .button, key: "recentSearches", ["history", "recent", "searches", "clear"],
                shownWhen: "Shown while there are recent searches", opensAt: .autoLoadWeb),
            row(.webSearchBrowser, "Open web searches in", .webSearches, .choice, key: "webSearchBrowser", ["browser", "safari", "chrome", "default browser", "reverse image search", "google lens"]),
            row(.webSearchHandoff, "Hand the picture over by", .webSearches, .choice, key: "webSearchPictureHandoff", ["clipboard", "photos", "files", "upload", "copy"])
        ]
        return list
    }

    nonisolated private static func privacyRows() -> [SettingEntry] {
        let list: [SettingEntry] = [
            row(.offlineMode, "Offline mode", .offline, .toggle, key: "offlineMode", ["offline", "airplane", "aeroplane", "internet", "network", "wifi", "wi-fi", "no internet"]),
            row(.lockHidden, "Ask for Face ID, Touch ID or passcode", .hidden, .toggle, key: "lockHiddenBoards", ["face id", "faceid", "touch id", "passcode", "password", "lock", "hidden", "secret", "private"]),
            row(.hiddenAI, "Include hidden pins in AI", .hidden, .toggle, key: "aiIncludesHidden",
                ["hidden", "ai", "cloud", "private", "tags", "secret", "privacy", "apple intelligence", "transcribe"]),
            row(.removeHiddenAI, "Remove AI tags from hidden pins", .hidden, .button,
                ["hidden", "ai", "tags", "remove", "clear", "delete", "private", "text", "titles"]),
            row(.hiddenOrder, "Order of pins in Hidden", .hidden, .choice, key: "hiddenPinSort", ["hidden", "order", "sort", "shuffle", "newest", "oldest"]),
            row(.privacyPromises, "What stays private", .privacy, .info, ["privacy", "private", "data", "tracking", "sent", "safe"])
        ]
        return list
    }

    nonisolated private static func storageRows() -> [SettingEntry] {
        let sync = ["sync", "sink", "sinc", "synch", "syncing", "icloud", "i cloud", "cloud", "devices", "ipad", "iphone"]
        let whenOn = "Shown while “Sync with iCloud Drive” is on"
        let space = ["space", "storage", "full", "free up", "size"]
        let list: [SettingEntry] = [
            row(.iCloudSync, "Sync with iCloud Drive", .iCloud, .toggle, key: "iCloudSync", sync + ["backup"]),
            row(.syncNow, "Sync now", .iCloud, .button, sync, shownWhen: whenOn, opensAt: .iCloudSync),
            row(.syncLog, "Sync log", .iCloud, .screen, sync + ["log", "diary", "debug"], shownWhen: whenOn, opensAt: .iCloudSync),
            row(.optimizeStorage, "Optimize device storage", .deviceStorage, .toggle, key: "optimizeStorage", space + ["offload", "icloud only", "download", "optimise"]),
            row(.videoQuality, "Video quality", .videoQuality, .choice, key: "videoQuality", ["resolution", "4k", "1080p", "720p", "compress"] + space),
            row(.keepOriginals, "Keep originals in a folder", .originals, .toggle, key: "keepOriginals", ["originals", "full size", "folder", "files", "raw"]),
            row(.librarySize, "Library size", .originals, .info, space + ["gb", "mb", "how big"]),
            row(.convertVideos, "Convert existing videos…", .originals, .button, ["convert", "compress", "shrink", "smaller"] + space)
        ]
        return list
    }

    nonisolated private static func libraryRows() -> [SettingEntry] {
        let list: [SettingEntry] = [
            row(.profiles, "Profiles", .profiles, .screen, ["profile", "user", "account", "family", "work", "switch", "library"]),
            row(.recentlyDeleted, "Recently Deleted", .lists, .screen, ["trash", "bin", "deleted", "restore", "undelete"]),
            row(.duplicates, "Possible duplicates", .lists, .screen, ["duplicates", "doubles", "same", "copies", "twice"]),
            row(.tags, "Your tags", .lists, .screen, ["tags", "labels", "rename tag", "merge"]),
            row(.export, "Export all pins and boards…", .yourData, .button, ["export", "backup", "back up", "zip", "save", "airdrop"]),
            row(.importFolder, "Import a folder…", .yourData, .button, ["import", "restore", "bring in", "folder"]),
            row(.recover, "Recover library", .backups, .screen, ["recover", "backup", "restore", "missing", "broken"]),
            row(.clearLibrary, "Clear this profile's library…", .clear, .button, ["delete all", "erase", "reset", "start over", "wipe"]),
            row(.about, "About", .about, .info, ["about", "version", "privacy", "network"])
        ]
        return list
    }
}

// MARK: - Searching

extension SettingsCatalog {
    /// The rows that match what was typed, best first. Every word typed must be found in the row's
    /// name, its other words, its page and section, or its section's footer (ignoring capitals and
    /// accents; a word may be the start of a longer one). Best first: the name starts with what was
    /// typed, then whole words of the name, then the start of words of the name, then its other
    /// words, then its page or section; ties keep the order of the pages. Rows found only by the
    /// footer come only when nothing else was found.
    /// Nothing found: one wrong letter is forgiven in words of five letters or more ("transcibe"),
    /// looking at the names and other words only.
    nonisolated static func search(_ typed: String) -> [SettingEntry] {
        let words = searchWords(typed)
        guard !words.isEmpty else { return [] }
        let exact = ranked(words, typed: typed, forgiving: false)
        return exact.isEmpty ? ranked(words, typed: typed, forgiving: true) : exact
    }

    nonisolated private static func ranked(_ words: [String], typed: String, forgiving: Bool) -> [SettingEntry] {
        var found: [(rank: Int, index: Int, entry: SettingEntry)] = []
        for (index, entry) in entries.enumerated() {
            let rank = forgiving ? looseRank(entry, words: words) : rank(entry, words: words, typed: typed)
            if let rank { found.append((rank, index, entry)) }
        }
        // Rows found only by their section's footer are shown only when nothing better was found
        // ("colour" shouldn't list the AI rows because their footer mentions colours).
        if found.contains(where: { (item: (rank: Int, index: Int, entry: SettingEntry)) -> Bool in item.rank < footerRank }) {
            found.removeAll { (item: (rank: Int, index: Int, entry: SettingEntry)) -> Bool in item.rank == footerRank }
        }
        found.sort { (a: (rank: Int, index: Int, entry: SettingEntry), b: (rank: Int, index: Int, entry: SettingEntry)) -> Bool in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.index < b.index
        }
        return found.map { (item: (rank: Int, index: Int, entry: SettingEntry)) -> SettingEntry in item.entry }
    }

    /// The rank of a row found only by its section's footer.
    nonisolated static let footerRank = 6

    /// 0 = the name starts with what was typed … 6 = only the footer matches; nil = no match.
    nonisolated static func rank(_ entry: SettingEntry, words: [String], typed: String) -> Int? {
        let start = folded(typed).trimmingCharacters(in: .whitespaces)
        if folded(entry.title).hasPrefix(start) { return 0 }
        let name = searchWords(entry.title)
        let others = searchWords(entry.synonyms.joined(separator: " "))
        let placeWords = searchWords(place(entry.section))
        let footer = searchWords(entry.section.footer)
        var worst = 0
        for word in words {
            if name.contains(word) { worst = max(worst, 2) }
            else if startsAWord(word, name) { worst = max(worst, 3) }
            else if startsAWord(word, others) { worst = max(worst, 4) }
            else if startsAWord(word, placeWords) { worst = max(worst, 5) }
            else if word.count >= 3, startsAWord(word, footer) { worst = max(worst, footerRank) }
            else { return nil }
        }
        return worst
    }

    /// The forgiving look: every word is in the name or the other words, but for one letter.
    nonisolated static func looseRank(_ entry: SettingEntry, words: [String]) -> Int? {
        let near = searchWords(entry.title + " " + entry.synonyms.joined(separator: " "))
        for word in words where !startsAWord(word, near) && !nearlyStartsAWord(word, near) {
            return nil
        }
        return 7
    }

    /// Whether a typed word is the start of one of the words (or one of them).
    nonisolated static func startsAWord(_ word: String, _ list: [String]) -> Bool {
        list.contains { (candidate: String) -> Bool in candidate.hasPrefix(word) }
    }

    /// For words of five letters or more: one of the words, or its start, is the same but for one
    /// letter.
    nonisolated static func nearlyStartsAWord(_ word: String, _ list: [String]) -> Bool {
        guard word.count >= 5 else { return false }
        for candidate in list {
            if oneLetterApart(word, candidate) { return true }
            if candidate.count > word.count, oneLetterApart(word, String(candidate.prefix(word.count))) { return true }
        }
        return false
    }

    /// Lower case, no accents, words split at anything that isn't a letter or a digit.
    nonisolated static func searchWords(_ text: String) -> [String] {
        folded(text).split { (c: Character) -> Bool in !(c.isLetter || c.isNumber) }.map { String($0) }
    }

    nonisolated static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Whether two words differ by at most one letter (one changed, added or left out).
    nonisolated static func oneLetterApart(_ a: String, _ b: String) -> Bool {
        let x = Array(a)
        let y = Array(b)
        if abs(x.count - y.count) > 1 { return false }
        var i = 0
        var j = 0
        var edits = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        edits += (x.count - i) + (y.count - j)
        return edits <= 1
    }
}
