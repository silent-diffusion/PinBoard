//
//  ProfileSettings.swift  —  PinBoard
//
//  Every profile keeps its own settings, as fully apart as its library: its own preferences
//  file (a UserDefaults suite named after the profile), its own API keys in the Keychain, and
//  its own feed orders. So one profile can sync with iCloud while another stays on this device
//  only, one can be in Offline mode, each has its own accent colour, originals folder, Hidden
//  lock, recent searches… Switching profiles switches every setting (`AppSettings.switchProfile`);
//  deleting one deletes its settings and keys too.
//
//  Before profiles had settings of their own, one set was shared by all of them. The first
//  launch of this version gives every existing profile a copy of that set (`moveSharedSettings`),
//  so nothing changes until you change it; a profile made later starts with the defaults.
//

import Foundation

@MainActor
enum ProfileSettings {
    /// The Keychain names of the API keys (each profile's are `account(_:profile:)`).
    static let keyAccounts = ["pexels", "pixabay", "unsplash", "openverseID", "openverseSecret", "youtube", "cloud"]

    /// Every preference a profile keeps (AppSettings stores each under its own name; the last
    /// three are FeedOrder's).
    static let preferenceKeys = [
        "appearance", "accent", "customAccentHex", "columns",
        "webSource", "showBoardWebFeed", "autoLoadWeb",
        "autoTitle", "accurateOCR", "useAppleIntelligence",
        "boardSort", "swipeBetweenTabs", "boardPagesIncludeSubBoards",
        "textFont", "textBoardSize", "textPageSize", "textLinesOnBoard",
        "textShowsTitle", "textUsesAccent", "textColorHex",
        "autoPlayVideos", "autoPlayOnPage", "videoSkipSeconds", "transcribeVideos",
        "webSearchBrowser", "webSearchPictureHandoff", "linkPicturesFromWebSearch",
        "fetchLinkPreviews", "cleanLinks", "readLinksFully", "chooseBoardWhenSharing",
        "videoQuality", "keepOriginals", "originalsBookmark", "originalsFolderName",
        "offlineMode", "optimizeStorage", "iCloudSync", "lockHiddenBoards",
        "recentSearches", "lastBoardID",
        "cloudEnabled", "cloudProvider", "cloudModel", "cloudConsentProvider", "aiIncludesHidden",
        "pinSort", "hiddenPinSort", "boardPinSort"
    ]

    /// Set once the shared settings were given to every profile.
    private static let movedKey = "settingsArePerProfile"

    /// One UserDefaults per profile, kept so everyone watching it (SettingsSync) sees the same one.
    private static var suites: [UUID: UserDefaults] = [:]

    static func suiteName(for profile: UUID) -> String {
        "com.silentdiffusion.pinboard2.profile.\(profile.uuidString)"
    }

    /// The profile's own preferences file.
    static func defaults(for profile: UUID) -> UserDefaults {
        if let known = suites[profile] { return known }
        let suite = UserDefaults(suiteName: suiteName(for: profile)) ?? .standard
        suites[profile] = suite
        return suite
    }

    /// The profile's Keychain name for an API key.
    nonisolated static func account(_ key: String, profile: UUID) -> String {
        "\(key).\(profile.uuidString)"
    }

    /// Once: the settings every profile shared (and the keys in the Keychain) are copied to each
    /// of `profiles`, then the shared keys are removed. Called by ProfileManager at launch.
    static func moveSharedSettings(to profiles: [UUID]) {
        let shared = UserDefaults.standard
        guard !shared.bool(forKey: movedKey) else { return }
        for profile in profiles {
            let own = defaults(for: profile)
            for key in preferenceKeys {
                if let value = shared.object(forKey: key), own.object(forKey: key) == nil { own.set(value, forKey: key) }
            }
        }
        for key in keyAccounts {
            let value = SecureStore.read(key)
            guard !value.isEmpty else { continue }
            for profile in profiles where SecureStore.read(account(key, profile: profile)).isEmpty {
                SecureStore.write(value, for: account(key, profile: profile))
            }
            SecureStore.write("", for: key)   // (an empty write deletes it)
        }
        for key in preferenceKeys { shared.removeObject(forKey: key) }
        shared.set(true, forKey: movedKey)
    }

    /// A deleted profile's settings and API keys go with it.
    static func forget(_ profile: UUID) {
        for key in keyAccounts { SecureStore.write("", for: account(key, profile: profile)) }
        // (The library's own counters, kept by profile in the shared file: LibraryBoards, LibraryAnalysis.)
        for key in ["pinsAddedSinceExport", "lastExportAt", "lastNamingRun.visible", "lastNamingRun.hidden"] {
            UserDefaults.standard.removeObject(forKey: "\(key).\(profile.uuidString)")
        }
        defaults(for: profile).removePersistentDomain(forName: suiteName(for: profile))
        suites[profile] = nil
    }
}

extension AppSettings {
    /// Shows another profile's settings: every setting is taken from that profile's own file
    /// (and Keychain), and from then on every change is kept there. SettingsSync is stopped
    /// first and started again afterwards by the caller (ProfileManager.select).
    func switchProfile(to profile: UUID) {
        guard profile != profileID else { return }
        let fresh = AppSettings(profileID: profile)
        useStorage(of: fresh)   // first: every setting adopted below is stored in the new profile's file
        adopt(\.appearance, from: fresh)
        adopt(\.accent, from: fresh)
        adopt(\.customAccentHex, from: fresh)
        adopt(\.columns, from: fresh)
        adopt(\.webSource, from: fresh)
        adopt(\.showBoardWebFeed, from: fresh)
        adopt(\.autoLoadWeb, from: fresh)
        adopt(\.autoTitle, from: fresh)
        adopt(\.accurateOCR, from: fresh)
        adopt(\.useAppleIntelligence, from: fresh)
        adopt(\.boardSort, from: fresh)
        adopt(\.swipeBetweenTabs, from: fresh)
        adopt(\.boardPagesIncludeSubBoards, from: fresh)
        adoptTextAndVideoSettings(from: fresh)
        adopt(\.webSearchBrowser, from: fresh)
        adopt(\.webSearchPictureHandoff, from: fresh)
        adopt(\.linkPicturesFromWebSearch, from: fresh)
        adopt(\.fetchLinkPreviews, from: fresh)
        adopt(\.cleanLinks, from: fresh)
        adopt(\.readLinksFully, from: fresh)
        adopt(\.chooseBoardWhenSharing, from: fresh)
        adoptDeviceSettings(from: fresh)
        adoptKeys(from: fresh)
    }

    /// (Split off so no single function lists too many settings for the compiler on the iPad.)
    private func adoptDeviceSettings(from fresh: AppSettings) {
        adopt(\.keepOriginals, from: fresh)
        adopt(\.originalsBookmark, from: fresh)
        adopt(\.originalsFolderName, from: fresh)
        adopt(\.offlineMode, from: fresh)
        adopt(\.optimizeStorage, from: fresh)
        adopt(\.iCloudSync, from: fresh)
        adopt(\.lockHiddenBoards, from: fresh)
        adopt(\.recentSearches, from: fresh)
        adopt(\.lastBoardID, from: fresh)
        adopt(\.cloudEnabled, from: fresh)
        adopt(\.cloudProvider, from: fresh)
        adopt(\.cloudModel, from: fresh)
        adopt(\.cloudConsentProvider, from: fresh)
        adopt(\.aiIncludesHidden, from: fresh)
    }

    private func adoptKeys(from fresh: AppSettings) {
        adopt(\.pexelsKey, from: fresh)
        adopt(\.pixabayKey, from: fresh)
        adopt(\.unsplashKey, from: fresh)
        adopt(\.openverseClientID, from: fresh)
        adopt(\.openverseClientSecret, from: fresh)
        adopt(\.youTubeAPIKey, from: fresh)
        adopt(\.cloudKey, from: fresh)
    }
}
