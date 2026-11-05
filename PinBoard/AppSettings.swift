//
//  AppSettings.swift  —  PinBoard
//
//  User preferences (saved automatically), secure storage for API keys, and
//  the accent colours (each with dark-mode and Increase Contrast variants).
//  The Settings screens that do a job (storage, profiles, tags, Recently
//  Deleted, duplicates, recovery) are in SettingsTools.swift.
//

import SwiftUI
import Security
import UniformTypeIdentifiers
import Foundation

// MARK: - Option types

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentTheme: String, CaseIterable, Identifiable {
    case red, coral, orange, gold, green, teal, blue, indigo, purple, pink, graphite
    case custom      // a colour chosen with the system colour picker
    var id: String { rawValue }

    var label: String { rawValue.titleCased }

    /// The theme's colour exactly as it was chosen: light mode, normal contrast.
    var baseRGB: RGB {
        switch self {
        case .custom: return RGB(red: 0.90, green: 0.00, blue: 0.14)   // replaced by the picked colour
        case .red: return RGB(red: 0.90, green: 0.00, blue: 0.14)
        case .coral: return RGB(red: 1.00, green: 0.40, blue: 0.36)
        case .orange: return RGB(red: 1.00, green: 0.55, blue: 0.10)
        case .gold: return RGB(red: 0.85, green: 0.65, blue: 0.10)
        case .green: return RGB(red: 0.20, green: 0.66, blue: 0.36)
        case .teal: return RGB(red: 0.10, green: 0.62, blue: 0.66)
        case .blue: return RGB(red: 0.12, green: 0.48, blue: 0.95)
        case .indigo: return RGB(red: 0.35, green: 0.34, blue: 0.84)
        case .purple: return RGB(red: 0.62, green: 0.30, blue: 0.85)
        case .pink: return RGB(red: 0.95, green: 0.30, blue: 0.62)
        case .graphite: return RGB(red: 0.35, green: 0.35, blue: 0.38)
        }
    }

    /// The theme's colour on screen. It adapts by itself to dark mode and to Increase
    /// Contrast (see `adaptive`), like the system's own colours.
    var color: Color {
        AccentTheme.adaptiveColors[self] ?? AccentTheme.adaptive(baseRGB.uiColor())
    }

    /// The colour exactly as chosen, never a variant. The colour picker starts from this one,
    /// so what gets saved is always the colour the person picked.
    var baseColor: Color {
        Color(red: baseRGB.red, green: baseRGB.green, blue: baseRGB.blue)
    }

    /// Every theme's adaptive colour, made once. Handing out the very same value every time
    /// matters: two separately made adaptive colours never count as equal, so a fresh one on
    /// each redraw would look like an accent change to SwiftUI and redraw every card.
    private static let adaptiveColors: [AccentTheme: Color] = {
        var colors: [AccentTheme: Color] = [:]
        for theme in AccentTheme.allCases {
            colors[theme] = adaptive(theme.baseRGB.uiColor())
        }
        return colors
    }()
}

// MARK: - Accent colours for every appearance

/// Apple asks for a light, a dark and an increased-contrast version of every custom colour.
/// The versions are worked out from the chosen colour, in hue / saturation / brightness:
/// - light mode: the colour as chosen;
/// - dark mode: a little brighter and a little less saturated (and always at least 3 : 1
///   against a dark background, so even a very dark picked colour stays visible);
/// - Increase Contrast: darker in light mode, lighter in dark mode, step by step, until text
///   in the colour stands out at least 4.5 : 1 against the system backgrounds (the light grey
///   #F2F2F7 of grouped screens, and #2C2C2E, the grey of rows in a sheet in dark mode) —
///   and therefore against plain white and black too.
/// The maths below is plain numbers, so it can be tested without a device.
extension AccentTheme {
    /// A colour as red, green and blue, each 0…1 (sRGB).
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        /// From "#RRGGBB" (or "RRGGBB"); nil when the text is not such a colour.
        init?(hex: String) {
            var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("#") { text.removeFirst() }
            guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Kept inside 0…1 (wide-gamut colours can report values outside it).
        var clamped: RGB {
            RGB(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
        }

        func uiColor(opacity: Double = 1) -> UIColor {
            UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity))
        }
    }

    /// A colour as hue, saturation and brightness, each 0…1 (as in the colour picker).
    struct HSB: Equatable, Sendable {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    /// The backgrounds text in the accent colour is checked against (see above).
    static let lightBackground = RGB(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255)
    static let darkBackground = RGB(red: 44.0 / 255, green: 44.0 / 255, blue: 46.0 / 255)
    /// The contrast text needs (4.5 : 1), and the least a dark-mode colour gets (3 : 1).
    static let textContrast = 4.5
    static let darkModeContrast = 3.0
    /// How much brightness (or saturation) one step changes.
    static let step = 0.03

    // MARK: The adaptive colour

    /// A colour that adapts: `base` as it is in light mode, and the variants below in dark
    /// mode and with Increase Contrast. Used for every theme and for the picked colour.
    static func adaptive(_ base: UIColor) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard base.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return Color(uiColor: base) }
        let light = RGB(red: Double(red), green: Double(green), blue: Double(blue)).clamped
        let dark = darkVariant(of: light)
        let lightHigh = lightHighContrastVariant(of: light)
        let darkHigh = darkHighContrastVariant(of: light)
        let opacity = Double(alpha)
        // Only plain numbers are captured, so the provider can run on any thread.
        let provider: @Sendable (UITraitCollection) -> UIColor = { traits in
            let highContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return (highContrast ? darkHigh : dark).uiColor(opacity: opacity)
            }
            return (highContrast ? lightHigh : light).uiColor(opacity: opacity)
        }
        return Color(uiColor: UIColor(dynamicProvider: provider))
    }

    /// The adaptive colour of a picked "#RRGGBB", or nil when the text is not a colour.
    static func adaptive(hex: String) -> Color? {
        guard let rgb = RGB(hex: hex) else { return nil }
        return adaptive(rgb.uiColor())
    }

    // MARK: The variants

    /// Dark mode: a little brighter and a little less saturated, then (only for very dark
    /// colours) brighter still until it reaches 3 : 1 against the dark background.
    static func darkVariant(of base: RGB) -> RGB {
        var color = hsb(of: base.clamped)
        color.brightness += (1 - color.brightness) * 0.35
        color.saturation *= 0.9
        while contrast(rgb(of: color), darkBackground) < darkModeContrast, canLighten(color) {
            color = lighter(color)
        }
        return rgb(of: color)
    }

    /// Increase Contrast in light mode: darker than the colour as chosen (at least one
    /// step), until text in it reaches 4.5 : 1 against the light background.
    static func lightHighContrastVariant(of base: RGB) -> RGB {
        var color = hsb(of: base.clamped)
        repeat {
            color.brightness = max(0, color.brightness - step)
        } while contrast(rgb(of: color), lightBackground) < textContrast && color.brightness > 0
        return rgb(of: color)
    }

    /// Increase Contrast in dark mode: lighter than the dark-mode colour (at least one
    /// step), until text in it reaches 4.5 : 1 against the dark background.
    static func darkHighContrastVariant(of base: RGB) -> RGB {
        var color = hsb(of: darkVariant(of: base))
        repeat {
            color = lighter(color)
        } while contrast(rgb(of: color), darkBackground) < textContrast && canLighten(color)
        return rgb(of: color)
    }

    /// One step lighter: brighter while it can be, then less saturated (towards white).
    static func lighter(_ color: HSB) -> HSB {
        var result = color
        if result.brightness < 1 {
            result.brightness = min(1, result.brightness + step)
        } else {
            result.saturation = max(0, result.saturation - step)
        }
        return result
    }

    /// False once the colour is white (nothing is lighter).
    static func canLighten(_ color: HSB) -> Bool {
        color.brightness < 1 || color.saturation > 0
    }

    // MARK: Colour maths

    static func hsb(of color: RGB) -> HSB {
        let largest = max(color.red, color.green, color.blue)
        let smallest = min(color.red, color.green, color.blue)
        let spread = largest - smallest
        let saturation = largest > 0 ? spread / largest : 0
        var hue = 0.0
        if spread > 0 {
            if largest == color.red {
                hue = (color.green - color.blue) / spread           // between magenta and yellow
            } else if largest == color.green {
                hue = 2 + (color.blue - color.red) / spread         // between yellow and cyan
            } else {
                hue = 4 + (color.red - color.green) / spread        // between cyan and magenta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSB(hue: hue, saturation: saturation, brightness: largest)
    }

    static func rgb(of color: HSB) -> RGB {
        let brightness = min(max(color.brightness, 0), 1)
        let saturation = min(max(color.saturation, 0), 1)
        let sector = (color.hue - color.hue.rounded(.down)) * 6     // which sixth of the colour wheel, 0 ..< 6
        let index = min(5, Int(sector))
        let fraction = sector - Double(index)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return RGB(red: brightness, green: rising, blue: low)
        case 1: return RGB(red: falling, green: brightness, blue: low)
        case 2: return RGB(red: low, green: brightness, blue: rising)
        case 3: return RGB(red: low, green: falling, blue: brightness)
        case 4: return RGB(red: rising, green: low, blue: brightness)
        default: return RGB(red: brightness, green: low, blue: falling)
        }
    }

    /// How bright a colour looks: 0 for black … 1 for white (WCAG "relative luminance").
    static func luminance(of color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = min(max(channel, 0), 1)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The WCAG contrast ratio of two colours: 1 (the same) … 21 (black on white).
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let a = luminance(of: first)
        let b = luminance(of: second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Colours as text (for saving a picked colour)

extension Color {
    /// "#RRGGBB" for a colour, or nil when it can't be resolved. An adaptive colour gives the
    /// version for the current appearance, so a picked colour is saved from the picker's own
    /// (plain) colour, never from an accent colour.
    var hexString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        // Wide-gamut pickers can report components outside 0…1.
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// A colour from "#RRGGBB" (or "RRGGBB"), exactly as written (it does not adapt).
    init?(hexString: String) {
        guard let rgb = AccentTheme.RGB(hex: hexString) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Secure storage for API keys

/// Keeps secrets in the iOS Keychain (encrypted, tied to this app). If the
/// Keychain refuses (it can, inside some sandboxed runners), it falls back to
/// the app's preferences and says so in Settings.
enum SecureStore {
    private static let service = "com.pinboard.keys"
    private static let fallbackPrefix = "securestore.fallback."

    /// True once the Keychain has accepted a write in this session.
    @MainActor static private(set) var keychainWorks = true

    static func read(_ account: String) -> String {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject? = nil
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) {
            return text
        }
        return UserDefaults.standard.string(forKey: fallbackPrefix + account) ?? ""
    }

    @MainActor
    static func write(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = SecItemDelete(baseQuery(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
        guard !trimmed.isEmpty else { return }

        var item = baseQuery(account)
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            keychainWorks = true
        } else {
            keychainWorks = false
            UserDefaults.standard.set(trimmed, forKey: fallbackPrefix + account)
        }
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - Settings model

@MainActor
final class AppSettings: ObservableObject {
    /// The settings of the profile in use. Every profile keeps its own (`ProfileSettings`):
    /// switching profiles switches them all (`switchProfile`).
    static let shared = AppSettings(profileID: ProfileManager.launchProfiles().current)

    /// The profile these settings belong to, and its own preferences file.
    private(set) var profileID: UUID
    private(set) var defaults: UserDefaults

    /// From now on, settings are kept in `other`'s profile (see `switchProfile`).
    func useStorage(of other: AppSettings) {
        profileID = other.profileID
        defaults = other.defaults
    }

    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var accent: AccentTheme { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    /// 0 = automatic (based on screen width), otherwise 2…8 columns.
    @Published var columns: Int { didSet { defaults.set(columns, forKey: "columns") } }

    @Published var webSource: WebImageSource { didSet { defaults.set(webSource.rawValue, forKey: "webSource") } }
    @Published var pexelsKey: String { didSet { if pexelsKey != oldValue { SecureStore.write(pexelsKey, for: ProfileSettings.account("pexels", profile: profileID)); keysVersion += 1 } } }
    @Published var pixabayKey: String { didSet { if pixabayKey != oldValue { SecureStore.write(pixabayKey, for: ProfileSettings.account("pixabay", profile: profileID)); keysVersion += 1 } } }
    @Published var unsplashKey: String { didSet { if unsplashKey != oldValue { SecureStore.write(unsplashKey, for: ProfileSettings.account("unsplash", profile: profileID)); keysVersion += 1 } } }
    @Published var openverseClientID: String { didSet { if openverseClientID != oldValue { SecureStore.write(openverseClientID, for: ProfileSettings.account("openverseID", profile: profileID)); keysVersion += 1 } } }
    @Published var openverseClientSecret: String { didSet { if openverseClientSecret != oldValue { SecureStore.write(openverseClientSecret, for: ProfileSettings.account("openverseSecret", profile: profileID)); keysVersion += 1 } } }
    /// Changes whenever a key changes, so web feeds know to retry (without
    /// ever putting the key itself into a view identifier).
    @Published var keysVersion: Int = 0

    @Published var showBoardWebFeed: Bool { didSet { defaults.set(showBoardWebFeed, forKey: "showBoardWebFeed") } }
    @Published var autoLoadWeb: Bool { didSet { defaults.set(autoLoadWeb, forKey: "autoLoadWeb") } }

    @Published var autoTitle: Bool { didSet { defaults.set(autoTitle, forKey: "autoTitle") } }
    @Published var accurateOCR: Bool { didSet { defaults.set(accurateOCR, forKey: "accurateOCR") } }
    @Published var useAppleIntelligence: Bool { didSet { defaults.set(useAppleIntelligence, forKey: "useAppleIntelligence") } }
    // (The order of the Pins tab, Hidden › All and board pages is kept by FeedOrder.)
    /// How boards are ordered on both sides of the library (Boards page, inside boards, pickers).
    @Published var boardSort: BoardSort { didSet { defaults.set(boardSort.rawValue, forKey: "boardSort") } }
    /// Swiping left or right on the four tab screens moves to the next tab.
    @Published var swipeBetweenTabs: Bool { didSet { defaults.set(swipeBetweenTabs, forKey: "swipeBetweenTabs") } }
    /// The colour picked with the system colour picker ("#RRGGBB"), exactly as picked.
    @Published var customAccentHex: String {
        didSet {
            defaults.set(customAccentHex, forKey: "customAccentHex")
            customAccentColor = AccentTheme.adaptive(hex: customAccentHex)
        }
    }
    /// The picked colour made adaptive (dark mode, Increase Contrast). Made once per pick, so
    /// every redraw is handed the very same colour value.
    private(set) var customAccentColor: Color? = nil

    // Text pins
    @Published var textFont: TextFontChoice { didSet { defaults.set(textFont.rawValue, forKey: "textFont") } }
    @Published var textBoardSize: Double { didSet { defaults.set(textBoardSize, forKey: "textBoardSize") } }
    @Published var textPageSize: Double { didSet { defaults.set(textPageSize, forKey: "textPageSize") } }
    @Published var textLinesOnBoard: Int { didSet { defaults.set(textLinesOnBoard, forKey: "textLinesOnBoard") } }
    @Published var textShowsTitle: Bool { didSet { defaults.set(textShowsTitle, forKey: "textShowsTitle") } }
    @Published var textUsesAccent: Bool { didSet { defaults.set(textUsesAccent, forKey: "textUsesAccent") } }
    @Published var textColorHex: String { didSet { defaults.set(textColorHex, forKey: "textColorHex") } }

    // Video pins
    @Published var autoPlayVideos: Bool { didSet { defaults.set(autoPlayVideos, forKey: "autoPlayVideos") } }
    @Published var autoPlayOnPage: Bool { didSet { defaults.set(autoPlayOnPage, forKey: "autoPlayOnPage") } }
    /// How far the player's skip buttons jump (5, 10, 15, 20 or 30 seconds).
    @Published var videoSkipSeconds: Int { didSet { defaults.set(videoSkipSeconds, forKey: "videoSkipSeconds") } }
    /// Videos with speech are written down by the on-device speech recogniser after they are added
    /// (the words go into the pin's note; nothing leaves the device). See VideoTranscripts.swift.
    @Published var transcribeVideos: Bool { didSet { defaults.set(transcribeVideos, forKey: "transcribeVideos") } }
    /// Board pages start with "Include pins from sub-boards" on (a sub-board's pins count as the board's).
    @Published var boardPagesIncludeSubBoards: Bool { didSet { defaults.set(boardPagesIncludeSubBoards, forKey: "boardPagesIncludeSubBoards") } }
    /// Where "Search this picture on the web" opens: PinBoard's own private browser, or the
    /// browser the person made their default.
    @Published var webSearchBrowser: WebSearchBrowser { didSet { defaults.set(webSearchBrowser.rawValue, forKey: "webSearchBrowser") } }
    /// How a picture that lives only in the library reaches a reverse image search's page: on
    /// the clipboard (for two minutes), saved to Files, or saved to Photos (see WebSearchPictureHandoff).
    @Published var webSearchPictureHandoff: WebSearchPictureHandoff { didSet { defaults.set(webSearchPictureHandoff.rawValue, forKey: "webSearchPictureHandoff") } }
    /// A link whose page has no picture of its own gets the first picture a web image search for
    /// its title finds (Explore's source) as its preview. Off: such a link stays without a picture.
    @Published var linkPicturesFromWebSearch: Bool { didSet { defaults.set(linkPicturesFromWebSearch, forKey: "linkPicturesFromWebSearch") } }

    /// The share sheet ("PinBoard" in other apps' share sheets) lets you choose a board. Off: it
    /// saves straight to No board in the profile open here, asking only about a look-alike picture.
    @Published var chooseBoardWhenSharing: Bool { didSet { defaults.set(chooseBoardWhenSharing, forKey: "chooseBoardWhenSharing") } }

    // Links
    @Published var fetchLinkPreviews: Bool { didSet { defaults.set(fetchLinkPreviews, forKey: "fetchLinkPreviews") } }
    /// Links you add are stripped of their tracking ("?utm_…", "fbclid" and such) — see LinkCleaner.
    @Published var cleanLinks: Bool { didSet { defaults.set(cleanLinks, forKey: "cleanLinks") } }
    /// A link you add is read fully (SmartLinks.swift): an article's text, writer and date; a
    /// Pinterest pin's picture or video and its links; a YouTube video's details (and its top
    /// comments with `youTubeAPIKey`); a link straight to a picture or video file becomes that pin.
    @Published var readLinksFully: Bool { didSet { defaults.set(readLinksFully, forKey: "readLinksFully") } }
    /// A YouTube Data API key (optional, free from Google): with it a video's description, date,
    /// length and top comments come from YouTube's own service. Kept in the Keychain.
    @Published var youTubeAPIKey: String { didSet { if youTubeAPIKey != oldValue { SecureStore.write(youTubeAPIKey, for: ProfileSettings.account("youtube", profile: profileID)) } } }   // (not `keysVersion`: that reloads the web feeds, which this key has nothing to do with)

    // Storage (MediaStorage.swift)
    /// How big the copy of a video kept on this device may be; larger videos are converted when added.
    @Published var videoQuality: VideoQuality { didSet { defaults.set(videoQuality.rawValue, forKey: "videoQuality") } }
    /// Full-size originals of pictures and videos are copied to `originalsBookmark`'s folder.
    @Published var keepOriginals: Bool { didSet { defaults.set(keepOriginals, forKey: "keepOriginals") } }
    /// The originals folder the person chose in Files (a security-scoped bookmark; nil = none yet).
    @Published var originalsBookmark: Data? {
        didSet {
            if let originalsBookmark { defaults.set(originalsBookmark, forKey: "originalsBookmark") } else { defaults.removeObject(forKey: "originalsBookmark") }
        }
    }
    /// The chosen folder's name, for showing in Settings ("iCloud Drive › PinBoard Originals").
    @Published var originalsFolderName: String { didSet { defaults.set(originalsFolderName, forKey: "originalsFolderName") } }
    /// That name while a folder is set (nil: none is) — the delete questions say the originals
    /// there go too (`StorageText.clearLibraryMessage`…). It says nothing about hidden pins.
    var originalsFolderIfSet: String? {
        guard originalsBookmark != nil else { return nil }
        return originalsFolderName
    }

    /// Turns off and hides everything that leaves the device.
    @Published var offlineMode: Bool { didSet { defaults.set(offlineMode, forKey: "offlineMode") } }

    /// Full pictures and videos not used for 30 days live in iCloud only (Offloading.swift; needs iCloud sync).
    @Published var optimizeStorage: Bool { didSet { defaults.set(optimizeStorage, forKey: "optimizeStorage") } }

    /// Sync the library through iCloud Drive.
    @Published var iCloudSync: Bool { didSet { defaults.set(iCloudSync, forKey: "iCloudSync") } }

    /// Whether the Hidden section asks for Face ID / passcode.
    @Published var lockHiddenBoards: Bool { didSet { defaults.set(lockHiddenBoards, forKey: "lockHiddenBoards") } }

    /// Recent Explore searches, newest first.
    @Published var recentSearches: [String] { didSet { defaults.set(recentSearches, forKey: "recentSearches") } }

    /// The board most recently chosen in a board picker or with Add / Move (pickers open there).
    @Published var lastBoardID: UUID? {
        didSet {
            guard lastBoardID != oldValue else { return }
            if let lastBoardID {
                defaults.set(lastBoardID.uuidString, forKey: "lastBoardID")
            } else {
                defaults.removeObject(forKey: "lastBoardID")
            }
        }
    }

    // Optional cloud vision model (own key; off by default).
    @Published var cloudEnabled: Bool { didSet { defaults.set(cloudEnabled, forKey: "cloudEnabled") } }
    @Published var cloudProvider: CloudProvider { didSet { defaults.set(cloudProvider.rawValue, forKey: "cloudProvider") } }
    @Published var cloudModel: String { didSet { defaults.set(cloudModel, forKey: "cloudModel") } }
    @Published var cloudKey: String { didSet { if cloudKey != oldValue { SecureStore.write(cloudKey, for: ProfileSettings.account("cloud", profile: profileID)); keysVersion += 1 } } }
    /// The provider the person agreed to send pictures to on the consent sheet ("" = none yet).
    /// Consent is for one company: choosing the other provider asks again. (Builds before 16 kept a
    /// yes/no under "cloudConsentGiven" that named no company; it is not carried over, so everyone
    /// sees the sheet that names the company once.)
    @Published var cloudConsentProvider: String { didSet { defaults.set(cloudConsentProvider, forKey: "cloudConsentProvider") } }
    /// "Include hidden pins in AI". Off by default: then no AI of any kind looks at a hidden pin —
    /// not the on-device tagging, text reading or naming, not Apple Intelligence, not speech
    /// transcription, not the cloud model. Only the fixed, rule-based code does (colours, the
    /// picture's fingerprint and look-alikes, text search over what the person typed, link
    /// reading, video upkeep). Per profile, kept on this device (not synced, like Cloud AI).
    @Published var aiIncludesHidden: Bool { didSet { defaults.set(aiIncludesHidden, forKey: "aiIncludesHidden") } }

    init(profileID: UUID) {
        let d = ProfileSettings.defaults(for: profileID)
        self.profileID = profileID
        defaults = d
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        accent = AccentTheme(rawValue: d.string(forKey: "accent") ?? "") ?? .red
        columns = d.integer(forKey: "columns")
        webSource = WebImageSource(rawValue: d.string(forKey: "webSource") ?? "") ?? .commons
        showBoardWebFeed = d.object(forKey: "showBoardWebFeed") as? Bool ?? true
        autoLoadWeb = d.object(forKey: "autoLoadWeb") as? Bool ?? false
        autoTitle = d.object(forKey: "autoTitle") as? Bool ?? true
        accurateOCR = d.object(forKey: "accurateOCR") as? Bool ?? true
        useAppleIntelligence = d.object(forKey: "useAppleIntelligence") as? Bool ?? true
        boardSort = BoardSort(rawValue: d.string(forKey: "boardSort") ?? "") ?? .custom
        swipeBetweenTabs = d.object(forKey: "swipeBetweenTabs") as? Bool ?? true
        let pickedHex = d.string(forKey: "customAccentHex") ?? "#E6002B"
        customAccentHex = pickedHex
        customAccentColor = AccentTheme.adaptive(hex: pickedHex)   // (didSet does not run in init)
        textFont = TextFontChoice(rawValue: d.string(forKey: "textFont") ?? "") ?? .system
        textBoardSize = d.object(forKey: "textBoardSize") as? Double ?? 15
        textPageSize = d.object(forKey: "textPageSize") as? Double ?? 20
        textLinesOnBoard = d.object(forKey: "textLinesOnBoard") as? Int ?? 6
        textShowsTitle = d.object(forKey: "textShowsTitle") as? Bool ?? true
        textUsesAccent = d.object(forKey: "textUsesAccent") as? Bool ?? false
        textColorHex = d.string(forKey: "textColorHex") ?? ""
        autoPlayVideos = d.object(forKey: "autoPlayVideos") as? Bool ?? false
        autoPlayOnPage = d.object(forKey: "autoPlayOnPage") as? Bool ?? false
        let skip = d.object(forKey: "videoSkipSeconds") as? Int ?? 10
        videoSkipSeconds = [5, 10, 15, 20, 30].contains(skip) ? skip : 10
        boardPagesIncludeSubBoards = d.object(forKey: "boardPagesIncludeSubBoards") as? Bool ?? true
        webSearchBrowser = WebSearchBrowser(rawValue: d.string(forKey: "webSearchBrowser") ?? "") ?? .inApp
        webSearchPictureHandoff = WebSearchPictureHandoff(rawValue: d.string(forKey: "webSearchPictureHandoff") ?? "") ?? .clipboard
        transcribeVideos = d.object(forKey: "transcribeVideos") as? Bool ?? true
        linkPicturesFromWebSearch = d.object(forKey: "linkPicturesFromWebSearch") as? Bool ?? false
        fetchLinkPreviews = d.object(forKey: "fetchLinkPreviews") as? Bool ?? true
        chooseBoardWhenSharing = d.object(forKey: "chooseBoardWhenSharing") as? Bool ?? true
        cleanLinks = d.object(forKey: "cleanLinks") as? Bool ?? true
        readLinksFully = d.object(forKey: "readLinksFully") as? Bool ?? true
        youTubeAPIKey = SecureStore.read(ProfileSettings.account("youtube", profile: profileID))
        videoQuality = VideoQuality(rawValue: d.string(forKey: "videoQuality") ?? "") ?? .fullHD
        keepOriginals = d.object(forKey: "keepOriginals") as? Bool ?? false
        originalsBookmark = d.data(forKey: "originalsBookmark")
        originalsFolderName = d.string(forKey: "originalsFolderName") ?? ""
        offlineMode = d.object(forKey: "offlineMode") as? Bool ?? false
        iCloudSync = d.object(forKey: "iCloudSync") as? Bool ?? false
        optimizeStorage = d.object(forKey: "optimizeStorage") as? Bool ?? false
        lockHiddenBoards = d.object(forKey: "lockHiddenBoards") as? Bool ?? true
        recentSearches = d.stringArray(forKey: "recentSearches") ?? []
        lastBoardID = d.string(forKey: "lastBoardID").flatMap { UUID(uuidString: $0) }
        cloudEnabled = d.object(forKey: "cloudEnabled") as? Bool ?? false
        cloudProvider = CloudProvider(rawValue: d.string(forKey: "cloudProvider") ?? "") ?? .anthropic
        cloudModel = d.string(forKey: "cloudModel") ?? ""
        cloudConsentProvider = d.string(forKey: "cloudConsentProvider") ?? ""
        aiIncludesHidden = d.object(forKey: "aiIncludesHidden") as? Bool ?? false
        cloudKey = SecureStore.read(ProfileSettings.account("cloud", profile: profileID))

        // Keys live in the Keychain. Anything an earlier version left in the
        // preferences file is moved over once and removed from there.
        pexelsKey = SecureStore.read(ProfileSettings.account("pexels", profile: profileID))
        pixabayKey = SecureStore.read(ProfileSettings.account("pixabay", profile: profileID))
        unsplashKey = SecureStore.read(ProfileSettings.account("unsplash", profile: profileID))
        openverseClientID = SecureStore.read(ProfileSettings.account("openverseID", profile: profileID))
        openverseClientSecret = SecureStore.read(ProfileSettings.account("openverseSecret", profile: profileID))
        migrateLegacyKey("pexelsKey", to: "pexels") { self.pexelsKey = $0 }
        migrateLegacyKey("pixabayKey", to: "pixabay") { self.pixabayKey = $0 }
        migrateLegacyKey("unsplashKey", to: "unsplash") { self.unsplashKey = $0 }
        migrateLegacyKey("openverseClientID", to: "openverseID") { self.openverseClientID = $0 }
        migrateLegacyKey("openverseClientSecret", to: "openverseSecret") { self.openverseClientSecret = $0 }
    }

    /// (Keys an early version kept in the shared preferences file go to the profile in use.)
    private func migrateLegacyKey(_ oldKey: String, to account: String, assign: (String) -> Void) {
        guard let old = UserDefaults.standard.string(forKey: oldKey), !old.isEmpty else { return }
        if SecureStore.read(ProfileSettings.account(account, profile: profileID)).isEmpty { assign(old) }
        UserDefaults.standard.removeObject(forKey: oldKey)
    }

    /// The accent colour on screen: the theme's or the picked colour, adapting by itself to
    /// dark mode and Increase Contrast.
    var accentColor: Color {
        if accent == .custom, let customAccentColor { return customAccentColor }
        return accent.color
    }

    /// Everything the text-pin views need, in one value.
    var textStyle: TextCardStyle {
        TextCardStyle(font: textFont,
                      boardSize: textBoardSize,
                      pageSize: textPageSize,
                      linesOnBoard: textLinesOnBoard,
                      showsTitleOnBoard: textShowsTitle)
    }

    /// The colour text pins are drawn in (nil = the normal text colour).
    var textPinColor: Color? {
        if !textColorHex.isEmpty, let picked = Color(hexString: textColorHex) { return picked }
        return textUsesAccent ? accentColor : nil
    }

    /// Whether Apple Intelligence should actually be used right now.
    var appleIntelligenceActive: Bool {
        useAppleIntelligence && AppleIntelligence.isAvailable
    }

    /// Anything that talks to the internet is allowed only when not offline.
    var webAllowed: Bool { !offlineMode }

    func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        recentSearches = Array(list.prefix(10))
    }

    /// How many columns the grid should use for a given width.
    func columnCount(forWidth width: CGFloat) -> Int {
        if columns <= 0 {
            if width > 1400 { return 5 }
            if width > 1000 { return 4 }
            if width > 640 { return 3 }
            return 2
        }
        // Never let a column get narrower than ~88 points (unreadable on phones).
        let maxThatFits = max(2, Int(width / 88))
        return max(2, min(columns, maxThatFits))
    }

    func apiKey(for source: WebImageSource) -> String {
        switch source {
        case .commons: return ""
        case .openverse: return openverseClientID
        case .pexels: return pexelsKey
        case .pixabay: return pixabayKey
        case .unsplash: return unsplashKey
        }
    }

    /// True when the chosen source can be used (a key is present if needed).
    func isSourceReady(_ source: WebImageSource) -> Bool {
        !source.needsKey || !apiKey(for: source).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether the person agreed to send pictures to `provider` (the consent sheet that names it).
    func hasCloudConsent(for provider: CloudProvider) -> Bool {
        cloudConsentProvider == provider.rawValue
    }

    /// What "Use a cloud vision model" shows: on only with consent for the chosen provider (after an
    /// update from a build whose consent named no company, it shows off until the sheet is agreed to).
    var cloudSwitchShowsOn: Bool {
        cloudEnabled && hasCloudConsent(for: cloudProvider)
    }

    /// Cloud tagging really runs only with consent for the chosen provider, the switch on, a key —
    /// and not offline.
    var cloudActive: Bool {
        !offlineMode && cloudEnabled && hasCloudConsent(for: cloudProvider) && !cloudKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}


// MARK: - Settings sheet

// (The Settings screen itself is SettingsView.swift; its pages are SettingsPages.swift.)

/// True for everything shown inside the Settings sheet, including the screens pushed there
/// (a pin's page opened from Possible duplicates, say). A ⋯ menu can leave out its
/// "Settings…" item when this is true: Settings is already open, so the item would do nothing.
/// (The pin, board and smart board pages' ⋯ menus read it.)
private struct InsideSettingsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInsideSettings: Bool {
        get { self[InsideSettingsKey.self] }
        set { self[InsideSettingsKey.self] = newValue }
    }
}

/// How far an export has got: pins written so far out of all of them. Updated
/// from the export's thread through the main actor.
@MainActor
final class ExportProgress: ObservableObject {
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// Which export the numbers belong to. Starting an export, or stopping one, moves it on, so
    /// what a stopped export still reports from its thread (or hands back) is ignored.
    private(set) var run = 0

    /// Starts counting a new export; returns its number.
    @discardableResult
    func start(total: Int) -> Int {
        run += 1
        done = 0
        self.total = total
        zipStartedAt = nil
        return run
    }

    /// When the zip was begun, and how long it is expected to take (the system makes it and says
    /// nothing until it is done, so its part of the bar moves by the clock: about 40 MB a second).
    @Published private(set) var zipStartedAt: Date? = nil
    private(set) var zipSeconds: Double = 1

    /// Every pin is written; the zip of `bytes` is being made now.
    func beginZip(bytes: Int64, run: Int? = nil) {
        if let run, run != self.run { return }
        zipSeconds = max(1, Double(bytes) / 40_000_000)
        zipStartedAt = Date()
    }

    /// The export being counted was stopped.
    func stop() {
        run += 1
    }

    /// Whether `run` is the export being counted now (not stopped, not followed by another).
    func isCurrent(_ run: Int) -> Bool {
        run == self.run
    }

    /// Updates can arrive out of order; the count never goes back. `run`: the export they come
    /// from (nil: whichever is counted now — "Share board…" makes only one per sheet).
    func report(done: Int, total: Int, run: Int? = nil) {
        if let run, run != self.run { return }
        self.total = total
        if done > self.done { self.done = done }
    }

    /// Writing the pins fills the bar to 90%; the zip the rest (by the clock, never quite full
    /// before it is done). Views showing it redraw a few times a second (`ExportProgressBar`).
    var fraction: Double {
        let written = total > 0 ? min(1, Double(done) / Double(total)) : 0
        guard let zipStartedAt else { return written * 0.9 }
        let zipped = min(0.95, Date().timeIntervalSince(zipStartedAt) / zipSeconds)
        return 0.9 + 0.1 * zipped
    }

    /// "Preparing export… 120 of 1,040", then "Making the zip…" once every pin is written.
    var statusText: String {
        if zipStartedAt != nil || (total > 0 && done >= total) { return "Making the zip…" }
        return "Preparing export… \(done.formatted()) of \(total.formatted())"
    }
}

/// An export's line and bar, redrawn a few times a second (the zip's part moves by the clock).
struct ExportProgressBar: View {
    @ObservedObject var progress: ExportProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { (_: TimelineViewDefaultContext) in
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.statusText).foregroundStyle(.secondary)
                ProgressView(value: progress.fraction)
            }
        }
    }
}
