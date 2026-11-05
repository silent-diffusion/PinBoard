//
//  SourceLinks.swift  —  PinBoard
//
//  Two small things that grew out of the pin menus (PinActions.swift) and stand on their own:
//
//  • The address sheet for "Edit link…" on a picture, video or text pin and "Add link…" on a pin
//    that has no link at all: `SourceLinkEditor`, and `SourceLinkOutcome`, the short message
//    after Save. (A link pin's own address is changed in the link editor, LinkPins.swift.)
//
//  • Handing a picture over to a web search: `WebSearchHandoff`, the plain rules and words for
//    how a picture that lives only in the library reaches a reverse image search page — on the
//    clipboard, in a folder in Files, or in Photos, as Settings › Links says — and the temporary
//    file Files' folder picker needs. A hidden pin's picture always goes to the clipboard.
//
//  PinActions.swift carries both out (`PinActionsPresenter`); everything here is plain rules and
//  one small sheet, so the harness can test the rules without a screen.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - The address sheet: Edit link… and Add link… on a picture, video or text

/// What the address sheet's Save did, for the short message (a plain rule; the harness tests it).
/// It follows the store's own answer (`setSourceLink` says whether anything changed) and the pin as
/// it was when the sheet opened (did it have a link?), so the words never disagree with what happened.
enum SourceLinkOutcome: Equatable, Sendable {
    case added           // the pin had no link; now it has one
    case changed         // the pin had a link; now it has another
    case removed         // the link is gone
    case unchanged       // the same address again (or nothing there to remove)
    case notAnAddress    // what was typed isn't a web address: the store refused it

    /// `hadLink`: the pin had a link before. `typed`: what was saved ("" = take the link away).
    /// `changed`: the store's answer.
    nonisolated static func of(hadLink: Bool, typed: String, changed: Bool) -> SourceLinkOutcome {
        let address = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return changed ? .removed : .unchanged }
        guard PinActionRules.webAddress(in: address) != nil else { return .notAnAddress }
        if !changed { return .unchanged }
        return hadLink ? .changed : .added
    }

    /// The short message.
    var text: String {
        switch self {
        case .added: return "Link added."
        case .changed: return "Link changed."
        case .removed: return "Link removed."
        case .unchanged: return "Link unchanged."
        case .notAnAddress: return "That isn't a web address."
        }
    }

    /// Its symbol: a check for something done, an "i" for nothing done, a triangle for a refusal.
    var symbol: String {
        switch self {
        case .added, .changed, .removed: return "checkmark.circle"
        case .unchanged: return "info.circle"
        case .notAnAddress: return "exclamationmark.triangle"
        }
    }
}

/// "Edit link…" on a picture, video or text pin, and "Add link…" on a pin that has none: a small
/// sheet for the address of the page the pin came from — or of any page about it. (A link pin's own
/// address is changed in the link editor, LinkPins.swift.) Save hands the typed address back
/// ("" when the link is to go); the presenter then asks the store (`setSourceLink`), which takes
/// the tracking out of the address and says whether anything changed.
struct SourceLinkEditor: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    /// The pin had a link when the sheet opened: the sheet is "Edit link", an empty field can be
    /// saved (that takes the link away) and "Remove link" is offered. Kept as it was at the start
    /// (a `@State`), so the sheet doesn't turn into "Add link" while it slides away after a save.
    @State private var hadLink: Bool
    /// What the field held when the sheet opened (to tell whether anything was changed).
    @State private var initial: String
    @State private var text: String
    private let onSave: (_ address: String) -> Void

    /// The line under the field.
    nonisolated static let hint = "The page this pin came from, or any page about it."

    init(pin: Pin, onSave: @escaping (_ address: String) -> Void) {
        let address = (pin.sourceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self._hadLink = State(initialValue: PinActionRules.hasLink(pin))
        self._initial = State(initialValue: address)
        self._text = State(initialValue: address)
        self.onSave = onSave
    }

    /// Whether Save may be pressed: a web address (http or https, with a host) — or nothing at all
    /// when there is a link to take away.
    nonisolated static func isSavable(text: String, hadLink: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return hadLink }
        return PinActionRules.webAddress(in: trimmed) != nil
    }

    private var isSavable: Bool {
        SourceLinkEditor.isSavable(text: text, hadLink: hadLink)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                addressField
                Text(SourceLinkEditor.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hadLink { removeButton }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(hadLink ? "Edit link" : "Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)   // Escape, on an iPad keyboard
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isSavable)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Once something is typed or changed, a swipe down can't throw it away: Cancel or Save decides.
        .interactiveDismissDisabled(text != initial)
    }

    /// The address field: the same UIKit field the link editor uses (no auto-capital, no autocorrect).
    private var addressField: some View {
        NativeTextField(placeholder: "https://…", text: $text, returnKey: .done, autocapitalization: .none,
                        autocorrection: false, autoFocus: true,
                        accessibilityLabel: "Web address") {
            save()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Takes the link away at once (the pin stays; only its address goes).
    private var removeButton: some View {
        Button("Remove link", role: .destructive) {
            onSave("")
            dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Save, Return on the keyboard and the built-in keyboard's Done all end here. Nothing
    /// happens while the text isn't savable (the Save button is dimmed meanwhile).
    private func save() {
        guard isSavable else { return }
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Handing a picture over to a web search

/// How the picture of a pin reaches a reverse image search page. A picture that lives only in the
/// library has no web address, so the search site can't be sent a link to it: the person uploads it
/// on the site's page, from wherever PinBoard put it. Settings › Explore & web search › "Hand the picture over by"
/// says where: the clipboard, a folder in Files, or Photos. The plain rules and the words are here
/// (the harness tests them); `PinActionsPresenter.searchWeb` carries them out.
enum WebSearchHandoff {
    /// What a search does with its picture.
    enum Step: Equatable, Sendable {
        case clipboard                          // on the clipboard for two minutes, on this device only
        case photos                             // saved to Photos: it is the newest picture in Recents
        case files                              // saved in a folder the person chooses in Files
    }

    /// The step for the setting.
    ///
    /// `hidden`: the picture belongs to a hidden pin. Whatever Settings says, it goes to the
    /// clipboard and nowhere else: the clipboard is kept on this device and clears itself after two
    /// minutes, whereas a copy in Photos (which may sync to iCloud) or in a folder in Files stays for
    /// good, out in the open, outside the hidden side. Settings' footer says so.
    nonisolated static func plan(setting: WebSearchPictureHandoff, hidden: Bool) -> Step {
        if hidden { return .clipboard }
        switch setting {
        case .clipboard: return .clipboard
        case .files: return .files
        case .photos: return .photos
        }
    }

    // The short messages. (The clipboard's own is `WebSearchOpening.copiedNote`.)

    /// The picture is in Photos and the search page is opening.
    nonisolated static let savedToPhotosNote = "Saved to Photos (the newest in Recents) — upload it on the page."
    /// Access to Photos was refused (or the save failed): no page opens, it would have nothing to upload.
    nonisolated static let photosRefusedNote = "Photos didn't take the picture."
    /// A place in Files was chosen and the search page is opening.
    nonisolated static let savedToFilesNote = "Saved — upload it on the page."
    /// The picture couldn't be written for Files' folder picker (no room on the device).
    nonisolated static let filesFailedNote = "The picture couldn't be saved to Files."

    // The picture's temporary file, for Files' folder picker

    /// The name of the folder (inside the device's temporary folder) that holds them.
    nonisolated static let folderName = "PinBoard Search"
    /// A leftover picture (the app was closed while the picker was up) is cleared away after this long.
    nonisolated static let leftoverAge: TimeInterval = 3600

    /// The folder for the temporary pictures: each one in a folder of its own inside it.
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The file's name in Files: the pin's title and ".jpg" (the library keeps pictures as JPEG),
    /// else "PinBoard picture.jpg". A hidden pin's title is never used: the file would carry it
    /// out of the hidden side, into Files, where anybody looking could read it.
    nonisolated static func fileName(title: String, hidden: Bool) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if hidden || trimmed.isEmpty { return "PinBoard picture.jpg" }
        return trimmed.safeFileName + ".jpg"
    }

    /// Writes the picture's bytes as a file called `name` in a folder of its own inside `root`.
    /// Returns the file, or nil when it couldn't be written (the half-made folder is removed).
    nonisolated static func writeTemporaryFile(_ data: Data, named name: String,
                                               in root: URL = WebSearchHandoff.folder) -> URL? {
        let manager = FileManager.default
        let place = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = place.appendingPathComponent(name)
        do {
            try manager.createDirectory(at: place, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            try? manager.removeItem(at: place)
            return nil
        }
    }

    /// Removes a temporary picture, and the folder it was in when that is empty now. Nothing else.
    nonisolated static func discard(_ file: URL) {
        let manager = FileManager.default
        try? manager.removeItem(at: file)
        let place = file.deletingLastPathComponent()
        if let left = try? manager.contentsOfDirectory(atPath: place.path), left.isEmpty {
            try? manager.removeItem(at: place)
        }
    }

    /// Clears away what an earlier run left in `root` (older than `age` seconds), so a hidden picture
    /// never stays in the temporary folder for good.
    nonisolated static func removeOldFiles(in root: URL = WebSearchHandoff.folder,
                                           olderThan age: TimeInterval = WebSearchHandoff.leftoverAge,
                                           now: Date = Date()) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            let item = root.appendingPathComponent(name)
            guard let attributes = try? manager.attributesOfItem(atPath: item.path),
                  let modified = attributes[.modificationDate] as? Date else { continue }
            if now.timeIntervalSince(modified) > age { try? manager.removeItem(at: item) }
        }
    }
}
