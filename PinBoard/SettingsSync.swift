//
//  SettingsSync.swift  —  PinBoard
//
//  With "Sync with iCloud Drive" on (and Offline mode off), a profile's settings travel to the
//  same profile on your other devices too, through iCloud's small key-value store: change the
//  accent colour on the iPhone and the iPad follows. Each profile's settings travel apart, under
//  the name of its iCloud folder (the one its library syncs with: `CloudSync.cloudFolder`), so they
//  only ever reach that profile; a profile with sync off sends and takes nothing. Only settings
//  about how you like the app travel. Ones that belong to one device stay put: the number of
//  columns (a phone and an iPad want different ones), Offline mode, the originals folder, the
//  Hidden lock, recent searches, the last board, the sync switch itself, and every API key and
//  the cloud model (keys stay in this device's Keychain). Started and stopped from RootTabsView
//  (ContentView.swift) and ProfileManager.select.
//

import Foundation

/// Keeps the travelling settings of the profile in use the same on every device where that
/// profile has sync on. The newest change wins. A device that turns sync on takes the settings
/// already in iCloud first, then adds any that are not there yet, so joining never overwrites
/// the other devices.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    /// The preference keys that travel (AppSettings stores each setting under its own name).
    nonisolated static let syncedKeys: [String] = [
        "appearance", "accent", "customAccentHex",
        "webSource", "showBoardWebFeed", "autoLoadWeb",
        "autoTitle", "accurateOCR", "useAppleIntelligence",
        "boardSort", "swipeBetweenTabs", "boardPagesIncludeSubBoards",
        "textFont", "textBoardSize", "textPageSize", "textLinesOnBoard",
        "textShowsTitle", "textUsesAccent", "textColorHex",
        "autoPlayVideos", "autoPlayOnPage", "videoSkipSeconds", "transcribeVideos", "videoQuality",
        "webSearchBrowser", "webSearchPictureHandoff", "linkPicturesFromWebSearch",
        "fetchLinkPreviews", "cleanLinks", "readLinksFully", "chooseBoardWhenSharing"
    ]

    /// iCloud's store, looked up only while syncing (a device signed out of iCloud complains in
    /// the device log as soon as it is touched).
    private var cloud: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }
    private var observers: [NSObjectProtocol] = []
    /// What is running: the profile, its preferences file and its iCloud folder's name.
    private var running: (profile: UUID, defaults: UserDefaults, folder: UUID)? = nil

    /// Follows the switches of the profile in use: runs while its sync is on, Offline mode is off,
    /// iCloud is there (`CloudSync.isAvailable`) and its library has synced once (so its iCloud
    /// folder is known); stops otherwise, and starts again for another profile. Safe to call as
    /// often as they change.
    func follow(_ settings: AppSettings, iCloudAvailable: Bool) {
        let folder = CloudSync.cloudFolder(of: settings.profileID)
        let wanted = settings.iCloudSync && !settings.offlineMode && iCloudAvailable && folder != nil
        if let running, !wanted || running.profile != settings.profileID || running.folder != folder {
            stop()
        }
        if wanted, running == nil, let folder {
            start(settings, folder: folder)
        }
    }

    /// Stops sending and taking settings (before another profile's are shown).
    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        running = nil
    }

    private func start(_ settings: AppSettings, folder: UUID) {
        let defaults = settings.defaults
        running = (settings.profileID, defaults, folder)
        cloud.synchronize()
        pull(Self.syncedKeys, into: settings)   // what the other devices already chose comes first
        push()                                  // then this device adds whatever iCloud doesn't have yet
        let prefix = Self.prefix(folder)
        let fromOtherDevices = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] (note: Notification) in
            let changed = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? [])
                .filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
            MainActor.assumeIsolated { self?.pull(changed, into: settings) }
        }
        let fromThisDevice = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.push() }
        }
        observers = [fromOtherDevices, fromThisDevice]
    }

    /// The profile's settings are kept in iCloud under "<its iCloud folder>.<setting>".
    nonisolated private static func prefix(_ folder: UUID) -> String { "profile.\(folder.uuidString)." }

    /// Writes this profile's travelling settings to iCloud where they differ from what is there.
    /// (A setting that arrived from iCloud is the same on both sides, so it isn't sent back.)
    private func push() {
        guard let running else { return }
        let prefix = Self.prefix(running.folder)
        var sent = false
        for key in Self.syncedKeys {
            guard let local = running.defaults.object(forKey: key) else { continue }   // never set here: nothing to offer
            if !Self.same(local, cloud.object(forKey: prefix + key)) {
                cloud.set(local, forKey: prefix + key)
                sent = true
            }
        }
        if sent { cloud.synchronize() }
    }

    /// Takes the given settings from iCloud where they differ from this profile's, and shows them.
    private func pull(_ keys: [String], into settings: AppSettings) {
        guard let running, running.profile == settings.profileID else { return }
        let prefix = Self.prefix(running.folder)
        var took = false
        for key in keys where Self.syncedKeys.contains(key) {
            guard let remote = cloud.object(forKey: prefix + key) else { continue }
            if !Self.same(running.defaults.object(forKey: key), remote) {
                running.defaults.set(remote, forKey: key)
                took = true
            }
        }
        if took { settings.reloadSyncedSettings() }
    }

    /// Whether two stored values are the same (both missing counts as the same).
    nonisolated private static func same(_ a: Any?, _ b: Any?) -> Bool {
        (a as? NSObject) == (b as? NSObject)
    }
}

extension AppSettings {
    /// Shows settings that just arrived from another device: AppSettings reads its values once,
    /// at launch, so a fresh copy reads the preferences again and every travelling setting that
    /// differs is taken from it. (Setting a property stores it again too, which changes nothing.)
    func reloadSyncedSettings() {
        let fresh = AppSettings(profileID: profileID)
        adopt(\.appearance, from: fresh)
        adopt(\.accent, from: fresh)
        adopt(\.customAccentHex, from: fresh)
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
    }

    /// (Split off so no single function lists too many settings for the compiler on the iPad.)
    func adoptTextAndVideoSettings(from fresh: AppSettings) {
        adopt(\.textFont, from: fresh)
        adopt(\.textBoardSize, from: fresh)
        adopt(\.textPageSize, from: fresh)
        adopt(\.textLinesOnBoard, from: fresh)
        adopt(\.textShowsTitle, from: fresh)
        adopt(\.textUsesAccent, from: fresh)
        adopt(\.textColorHex, from: fresh)
        adopt(\.autoPlayVideos, from: fresh)
        adopt(\.autoPlayOnPage, from: fresh)
        adopt(\.videoSkipSeconds, from: fresh)
        adopt(\.transcribeVideos, from: fresh)
        adopt(\.videoQuality, from: fresh)
    }

    /// Takes one setting from `fresh` when it differs (an unchanged setting isn't touched, so
    /// nothing on screen redraws for it).
    func adopt<Value: Equatable>(_ setting: ReferenceWritableKeyPath<AppSettings, Value>, from fresh: AppSettings) {
        let value = fresh[keyPath: setting]
        if self[keyPath: setting] != value {
            self[keyPath: setting] = value
        }
    }
}
