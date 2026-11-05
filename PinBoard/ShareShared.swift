//
//  ShareShared.swift  —  PinBoard
//
//  What the app and its share extension ("PinBoard" in the share sheet of Photos, Safari, Files…)
//  share, through the same App Group as the widgets:
//    • the board list: the open profile's boards (never a hidden one), written by the app, so the
//      share sheet can offer them;
//    • the inbox: one folder per share, holding copies of the shared files and a small JSON saying
//      what they are and where they go. The app takes the inbox in (ShareInbox.swift).
//  Why an inbox: the share sheet runs inside another app with very little memory, and the library
//  belongs to the app, so the extension only copies files and the app does the real import.
//  This file is part of the app and of the share extension (Xcode/PinBoardShare).
//  Without the App Group (a build that lacks it) nothing is written and the inbox is always empty.
//

import Foundation
import CryptoKit

enum ShareShared {
    /// The App Group the app, the widgets and the share extension belong to.
    nonisolated static let appGroup = "group.com.silentdiffusion.pinboard2"
    /// Where the quick-save switch is, for the share sheet's note (it can't see the app's
    /// SettingsCatalog; a harness test checks this is the catalog's path).
    nonisolated static let chooseBoardSettingPath = "Settings › Pins & boards › Sharing"
    /// Told by the share sheet after a save, so a PinBoard that is open (on iPad, side by side
    /// with Safari) takes the new item in at once.
    nonisolated static let inboxChangedNotice = "com.silentdiffusion.pinboard2.shareInboxChanged"
    /// A folder still being filled by the share sheet starts with this (the app leaves it alone).
    nonisolated static let unfinishedPrefix = ".incoming-"
    /// The share description inside each inbox folder.
    nonisolated static let entryFileName = "share.json"

    nonisolated static var groupFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// The inbox: one folder per share ("Share Inbox" in the App Group).
    nonisolated static var inboxFolder: URL? {
        groupFolder?.appendingPathComponent("Share Inbox", isDirectory: true)
    }

    /// The share sheet's own folder in the App Group ("Share"): a list of the profiles, and a
    /// folder per profile with what the sheet shows for that library (each kept apart).
    nonisolated static var shareFolder: URL? {
        groupFolder?.appendingPathComponent("Share", isDirectory: true)
    }

    /// The profiles, and which one is open in PinBoard (`ShareProfiles`).
    nonisolated static var profilesFile: URL? { shareFolder?.appendingPathComponent("profiles.json") }

    /// One profile's folder ("Share/<profile id>").
    nonisolated static func folder(for profile: UUID) -> URL? {
        shareFolder?.appendingPathComponent(profile.uuidString, isDirectory: true)
    }

    /// A profile's board list (written by the app while that profile is open).
    nonisolated static func boardListFile(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("boards.json")
    }

    /// What the share sheet's "Looks familiar" check compares with (`ShareFamiliarIndex`).
    nonisolated static func familiarFile(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("familiar.json")
    }

    /// Tiny pictures of a profile's normal pins, for the "Already in your library" side of that check.
    nonisolated static func thumbsFolder(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("thumbs", isDirectory: true)
    }

    /// Boards made in the share sheet that PinBoard hasn't made yet (`ShareNewBoard`), so the next
    /// share already lists them. Written by the share sheet; cleared by the app once it made them.
    nonisolated static func newBoardsFile(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("new-boards.json")
    }

    /// The profile's settings the share sheet follows (`ShareProfileSettings`), written by the app.
    nonisolated static func settingsFile(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("settings.json")
    }

    /// The board the last share of this profile went to (for the "Last used" row only: a share
    /// always starts on "No board"). Written by the share sheet; the app puts in the real board
    /// when it makes one the share sheet made.
    nonisolated static func lastBoardFile(for profile: UUID) -> URL? {
        folder(for: profile)?.appendingPathComponent("last-board.txt")
    }

    nonisolated static func readProfileSettings(profile: UUID) -> ShareProfileSettings? {
        read(ShareProfileSettings.self, from: settingsFile(for: profile))
    }

    nonisolated static func readLastBoard(profile: UUID) -> UUID? {
        guard let file = lastBoardFile(for: profile), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated static func writeLastBoard(_ board: UUID, profile: UUID) {
        guard let file = lastBoardFile(for: profile) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? board.uuidString.write(to: file, atomically: true, encoding: .utf8)
    }

    nonisolated static func readProfiles() -> ShareProfiles? {
        read(ShareProfiles.self, from: profilesFile)
    }

    nonisolated static func readBoardList(profile: UUID) -> ShareBoardList? {
        read(ShareBoardList.self, from: boardListFile(for: profile))
    }

    nonisolated static func readFamiliarIndex(profile: UUID) -> ShareFamiliarIndex? {
        read(ShareFamiliarIndex.self, from: familiarFile(for: profile))
    }

    nonisolated static func readNewBoards(profile: UUID) -> [ShareNewBoard] {
        read([ShareNewBoard].self, from: newBoardsFile(for: profile)) ?? []
    }

    private nonisolated static func read<T: Decodable>(_ type: T.Type, from file: URL?) -> T? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The profiles (PinBoard's separate libraries), as the share sheet's "Profile" row offers them.
struct ShareProfiles: Codable, Sendable, Equatable {
    struct Profile: Codable, Sendable, Equatable, Identifiable {
        var id: UUID
        var name: String
    }

    var profiles: [Profile]
    /// The profile open in PinBoard (the share sheet starts on it).
    var current: UUID
}

/// A profile's settings that the share sheet follows (Settings › Pins & boards › Sharing).
struct ShareProfileSettings: Codable, Sendable, Equatable {
    /// "Choose a board when sharing". Off: quick save — straight to no board in the open profile.
    var chooseBoard: Bool = true
}

/// A board made in the share sheet ("New board"): PinBoard makes it when it takes the share in —
/// or uses a normal board it already has with the same name in the same place (capitals and
/// accents don't count), so two shares never make it twice. Never a hidden board.
struct ShareNewBoard: Codable, Sendable, Equatable, Identifiable {
    /// A stand-in id, used by the share until PinBoard has made the board.
    var id: UUID
    var name: String
    /// A board it goes inside (a real board, or another new one); nil: top level.
    var parentID: UUID?
}

/// The boards of one profile, as the share sheet lists them: in the app's order,
/// each sub-board right after its parent. Hidden boards (and anything inside them) are never here,
/// nor is anything about a hidden pin.
struct ShareBoardList: Codable, Sendable, Equatable {
    struct Board: Codable, Sendable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var parentID: UUID?
        /// 0 for a top-level board, 1 for a sub-board, and so on.
        var depth: Int
        /// Its normal pins, as the app's board picker counts them (nil: a board made in the share
        /// sheet, not made by PinBoard yet).
        var pinCount: Int? = nil
        // What the share sheet's "Suggested" compares a shared item with (the same signals as the
        // app's own board suggestions, worked out by the app: the share sheet can't open the library).
        /// The words of the board's name (1) and its parents' names (0.6), in their base form.
        var nameWords: [String: Double] = [:]
        /// The most common tags of the board's pins → the share of its pins that carry each.
        var tags: [String: Double] = [:]
        /// The sites its link pins and web pictures come from ("swift.org") → their share of its pins.
        var sites: [String: Double] = [:]
    }

    var profileID: UUID
    var profileName: String
    /// How many profiles there are (the share sheet names the profile only when there are several).
    var profileCount: Int
    var boards: [Board]

    /// A web address's site, as `Board.sites` keeps it ("www.swift.org" → "swift.org").
    nonisolated static func site(of address: String) -> String? {
        guard let host = URL(string: address)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "Travel › Japan": the board with its parents, for the row that shows the choice.
    func path(of id: UUID) -> String? {
        guard var board = boards.first(where: { $0.id == id }) else { return nil }
        var names = [board.name]
        while let parent = board.parentID, let next = boards.first(where: { $0.id == parent }) {
            names.insert(next.name, at: 0)
            board = next
        }
        return names.joined(separator: " › ")
    }
}

/// One share: what was shared together, with the board and note chosen for all of it.
struct ShareInboxEntry: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case picture, gif, video, link, text
    }

    /// One shared thing. Pictures, GIFs and videos have a `file` (in the entry's folder); a link
    /// has its `url`; text has its `text`.
    struct Item: Codable, Sendable, Identifiable {
        var id: UUID = UUID()
        var kind: Kind
        var file: String? = nil
        var url: String? = nil
        var text: String? = nil
        /// The shared file's own name, without its extension (a video's title).
        var name: String? = nil
        /// The pin it looks like (the share sheet's "Looks familiar"), and what the person chose.
        /// nil: nothing looked familiar there (the app's own check still runs on take-in).
        var existingPinID: UUID? = nil
        var choice: ShareChoice? = nil
    }

    var id: UUID = UUID()
    /// The profile (library) chosen in the share sheet (nil: PinBoard had not written its profile
    /// list yet; the item goes to whichever profile is open). Taken in only while it is open.
    var profileID: UUID?
    /// nil: no board (the item lands in Unsorted). May be a board made in the share sheet: then
    /// `newBoards` says how to make it.
    var boardID: UUID?
    /// Boards made in the share sheet that this share needs (the chosen one and any new parents),
    /// outermost first.
    /// (Optional, so a share saved by an older share sheet, without it, still reads.)
    var newBoards: [ShareNewBoard]? = nil
    var note: String = ""
    var date: Date = Date()
    var items: [Item]
}

/// What to do with a shared thing that looks like a pin already in the library — the answers of
/// the app's own "Looks familiar" question (8.4).
enum ShareChoice: String, Codable, Sendable {
    case saveNew        // "Save as a new pin"
    case addExisting    // "Add the existing pin to this board" (an exact copy: always this)
    case skip           // "Skip this one"
}

/// The normal library as the "Looks familiar" check sees it: each normal pin's picture signature
/// (pictures, and videos by their poster), each link pin's page and each text pin's words — the
/// words only as a fingerprint, never the text itself. Never anything of a hidden pin.
struct ShareFamiliarIndex: Codable, Sendable {
    /// A pin the check may point at, with what the sheet shows of it.
    struct Known: Codable, Sendable, Identifiable {
        var id: UUID
        var kind: String           // "picture", "video", "link", "text"
        var title: String
        var boardIDs: [UUID]
        var boardNames: [String]
        var thumb: String? = nil   // in `ShareShared.thumbsFolder`
    }

    /// A picture's 64-step light-and-dark signature (as hex: JSON numbers can't hold 64 bits) and shape.
    struct Picture: Codable, Sendable {
        var id: UUID
        var hash: String
        var aspect: Double
    }

    var profileID: UUID
    var pins: [Known]
    var pictures: [Picture]
    /// A link pin's page (`ShareFamiliarIndex.pageKey`) → the pin.
    var links: [String: UUID]
    /// A text pin's words (`ShareFamiliarIndex.textKey`) → the pin.
    var texts: [String: UUID]

    /// The app's rule for the same text: capitals and blank space at the ends don't count. Kept as
    /// a fingerprint, so the words themselves never sit in the shared folder.
    nonisolated static func textKey(_ body: String) -> String {
        let plain = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(plain.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The app's rule for the same page (`LibraryStore.normalizedLink`): capitals, "http" versus
    /// "https" and a trailing "/" don't count. (The app takes tracking out first; the share sheet
    /// takes out only the common kinds, see `ShareFamiliarIndex.withoutCommonTracking`.)
    nonisolated static func normalized(_ link: String) -> String {
        var value = link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix("/") { value.removeLast() }
        return value.replacingOccurrences(of: "http://", with: "https://")
    }

    /// A shared address without the most common tracking (utm_…, fbclid, gclid, Instagram's igsh,
    /// YouTube's and Spotify's si, a text highlight): the app's full cleaning (LinkCleaner) is too
    /// big for the share sheet; the app still checks properly when it takes the link in.
    nonisolated static func withoutCommonTracking(_ link: String) -> String {
        guard var parts = URLComponents(string: link) else { return link }
        if let items = parts.queryItems {
            let dropped: Set<String> = ["fbclid", "gclid", "igsh", "igshid", "si", "mc_cid", "mc_eid", "ref_src", "srsltid"]
            let kept = items.filter { (item: URLQueryItem) -> Bool in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !dropped.contains(name)
            }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        if let fragment = parts.fragment, let highlight = fragment.range(of: ":~:") {
            let rest = String(fragment[..<highlight.lowerBound])
            parts.fragment = rest.isEmpty ? nil : rest
        }
        return parts.string ?? link
    }

    nonisolated static func hex(_ hash: UInt64) -> String { String(hash, radix: 16) }
    nonisolated static func hash(fromHex text: String) -> UInt64? { UInt64(text, radix: 16) }
}
