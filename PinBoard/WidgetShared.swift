//
//  WidgetShared.swift  —  PinBoard
//
//  What the app and its widgets share: a small snapshot of the normal library (board names,
//  a sample of pictures as small JPEGs, and the text pins) in the App Group's "Widgets" folder.
//  The widgets never read the library itself, and nothing from the Hidden section is ever in
//  the snapshot. This file is part of the app and of the widget extension (Xcode).
//  Without the App Group (a build that lacks it) the snapshot is simply never written.
//

import Foundation

enum WidgetShared {
    /// The App Group both the app and the widget extension belong to.
    static let appGroup = "group.com.silentdiffusion.pinboard2"
    /// The widgets' kinds (WidgetKit's names for them).
    static let photoKind = "PinBoardPhoto"
    static let gridKind = "PinBoardGrid"
    static let quoteKind = "PinBoardQuote"

    /// The shared folder ("Widgets" in the App Group), nil where there is no App Group.
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Widgets", isDirectory: true)
    }

    static var snapshotFile: URL? { folder?.appendingPathComponent("snapshot.json") }
    static var picturesFolder: URL? { folder?.appendingPathComponent("pictures", isDirectory: true) }

    /// A picture's file: named by the pin and its picture revision, so a turned or cropped
    /// picture gets a new file and an unchanged one is never written twice.
    static func pictureName(_ id: UUID, revision: Int) -> String { "\(id.uuidString)-\(revision).jpg" }

    /// The link a widget opens: the pin's page in PinBoard ("pinboard://pin/<id>").
    static let urlScheme = "pinboard"
    static func link(toPin id: UUID) -> URL { URL(string: "\(urlScheme)://pin/\(id.uuidString)")! }

    /// The pin a widget's link points at (nil: not one of ours).
    static func pinID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "pin" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let file = snapshotFile, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// The library as the widgets see it.
struct WidgetSnapshot: Codable, Sendable {
    struct Board: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var name: String
    }

    struct Photo: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var file: String          // in `WidgetShared.picturesFolder`
        var title: String
        var boardIDs: [UUID]      // every board whose page shows it (sub-boards' pins count for their parents)
    }

    struct Quote: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        var text: String
        var title: String
        var boardIDs: [UUID]
    }

    var made: Date
    var boards: [Board]
    var photos: [Photo]
    var quotes: [Quote]

    /// The photos of one board (nil: every board, and Unsorted).
    func photos(in board: UUID?) -> [Photo] {
        guard let board else { return photos }
        return photos.filter { $0.boardIDs.contains(board) }
    }

    func quotes(in board: UUID?) -> [Quote] {
        guard let board else { return quotes }
        return quotes.filter { $0.boardIDs.contains(board) }
    }
}
