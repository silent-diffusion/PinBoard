//
//  SettingsHomePage.swift  —  PinBoard
//
//  Settings › Pins & boards › Home page: everything kept off the Home page (the Pins tab's All and
//  Unsorted; the tab itself keeps its name "Pins"). "Keep off Home page" in a pin's or a board's
//  menu does it; this page lists the boards that keep their pins off (with their pins under them),
//  and the pins kept off by their own setting, and puts any of them back. Kept-off pins still show
//  on their boards, in Search and in smart boards. Hidden pins and boards are never listed here.
//
//  The stored names still say "out of All" (`Pin.keptOutOfAll`, `Board.keepsPinsOutOfAll`), so
//  libraries and iCloud sync from before the rename keep working; only the words changed.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - What the page lists

extension LibraryStore {
    /// Normal boards whose own switch keeps their pins off the Home page, in the order of their
    /// paths ("Travel", "Travel › Japan", "Work"). Hidden boards are never listed.
    var boardsKeepingPinsOffHome: [Board] {
        let kept = boards.filter { (board: Board) -> Bool in board.keepsPinsOutOfAll && !isSecretBoard(board.id) }
        return kept.sorted { (a: Board, b: Board) -> Bool in
            homePathName(a.id).localizedStandardCompare(homePathName(b.id)) == .orderedAscending
        }
    }

    /// Normal pins kept off the Home page by their own setting, newest first.
    var pinsKeptOffByThemselves: [Pin] {
        visiblePins.filter { (pin: Pin) -> Bool in pin.keptOutOfAll }
            .sorted { (a: Pin, b: Pin) -> Bool in a.createdAt > b.createdAt }
    }

    /// "Travel › Japan": a board's name with the boards it sits in.
    func homePathName(_ id: UUID) -> String {
        path(to: id).map { (board: Board) -> String in board.name }.joined(separator: " › ")
    }

    /// The board (itself, or one it sits in) that keeps this board's pins off, when it isn't the
    /// board itself ("Kept off with “Travel”").
    func keepingParent(of id: UUID) -> Board? {
        path(to: id).dropLast().last { (board: Board) -> Bool in board.keepsPinsOutOfAll }
    }

    /// The first board that keeps this pin off the Home page (for "via Travel"), if any.
    func boardKeepingPinOff(_ pin: Pin) -> Board? {
        for id in pin.boardIDs where boardKeepsPinsOutOfAll(id) && !isSecretBoard(id) {
            if let board = board(id) { return board }
        }
        return nil
    }
}

/// The few words of the page (pure, so the harness can check them).
enum HomePageText {
    nonisolated static let intro = "The Home page is the Pins tab. These pins don't show in its All or Unsorted, but they still show on their boards, in Search and in smart boards."
    nonisolated static let emptyTitle = "Nothing is kept off the Home page"
    nonisolated static let emptyMessage = "Choose “Keep off Home page” in a pin's or a board's menu to take pins off the Pins tab without hiding them."
    nonisolated static let showAgain = "Show on Home page"

    /// "3 pins", "1 pin".
    nonisolated static func pinCount(_ count: Int) -> String {
        count == 1 ? "1 pin" : "\(count) pins"
    }
}

// MARK: - The page

/// The list: boards that keep their pins off (each with its pins), then pins kept off by their own
/// setting. A pin opens its page as usual; "Show on Home page" puts a board or a pin back.
struct SettingsHomePageView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow

    var body: some View {
        let boards = store.boardsKeepingPinsOffHome
        let own = store.pinsKeptOffByThemselves
        Form {
            if boards.isEmpty && own.isEmpty {
                emptySection
            } else {
                Section {
                    Text(HomePageText.intro)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(boards, id: \.id) { (board: Board) in
                    boardSection(board)
                }
                if !own.isEmpty {
                    ownSection(own)
                }
            }
        }
        .navigationTitle("Home page")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(HomePageText.emptyTitle, systemImage: "house")
                    .font(.headline)
                Text(HomePageText.emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Boards

    /// One board that keeps its pins off: its name and count, a way to show them again, then its
    /// pins (sub-boards' pins included, as the board's own page shows them).
    private func boardSection(_ board: Board) -> some View {
        let pins = store.pins(in: board.id, includeNested: true)
            .sorted { (a: Pin, b: Pin) -> Bool in a.createdAt > b.createdAt }
        let parent = store.keepingParent(of: board.id)
        return Section {
            HStack(spacing: 12) {
                Button {
                    showBoard(board)
                } label: {
                    Text(HomePageText.showAgain)
                }
                .buttonStyle(.borderless)
                .disabled(parent != nil)
                Spacer()
                NavigationLink(value: Route.board(board.id)) {
                    Text("Open board")
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            if let parent {
                Text("Also kept off with “\(parent.name)”: show that board first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(pins, id: \.id) { (pin: Pin) in
                HomePagePinRow(pin: pin, context: pins.map { $0.id }, note: nil, onShow: nil)
            }
        } header: {
            Label("\(store.homePathName(board.id)) · \(HomePageText.pinCount(pins.count))", systemImage: "folder")
                .textCase(nil)
        }
    }

    private func showBoard(_ board: Board) {
        store.setBoardKeepsPinsOutOfAll(board.id, false)
        importFlow.flash(BoardKeepOutText.message(keeping: false, count: 1, stillKept: false))
    }

    // MARK: Pins kept off by themselves

    private func ownSection(_ pins: [Pin]) -> some View {
        Section {
            ForEach(pins, id: \.id) { (pin: Pin) in
                HomePagePinRow(pin: pin, context: pins.map { $0.id }, note: viaNote(pin)) {
                    showPin(pin)
                }
            }
        } header: {
            Text("Pins kept off by their own setting · \(pins.count)")
                .textCase(nil)
        }
    }

    /// "Also kept off via “Travel”" when a board would keep the pin off anyway.
    private func viaNote(_ pin: Pin) -> String? {
        store.boardKeepingPinOff(pin).map { (board: Board) -> String in "Also kept off via “\(board.name)”" }
    }

    private func showPin(_ pin: Pin) {
        store.setKeptOutOfAll([pin.id], false)
        let still = store.livePin(pin.id).map { (fresh: Pin) -> Bool in store.isKeptOutOfAll(fresh) } ?? false
        importFlow.flash(PinActionText.shownInAll(1, stillKept: still ? 1 : 0))
    }
}

// MARK: - A pin's row

/// A small picture (or the kind's symbol), the pin's name and a grey line; tapping opens the pin's
/// page. `onShow` adds a "Show" button that puts the pin back on the Home page.
struct HomePagePinRow: View {
    let pin: Pin
    /// The list it was opened from (swiping on the pin's page moves along it).
    let context: [UUID]
    let note: String?
    let onShow: (() -> Void)?
    @EnvironmentObject private var store: LibraryStore
    @State private var picture: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.pin(pin.id, PinContext(ids: context, around: pin.id))) {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HomePagePinRow.name(of: pin))
                            .lineLimit(2)
                        if let note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let onShow {
                Button("Show", action: onShow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(HomePageText.showAgain)
            }
        }
        .task(id: pin.id) {
            picture = await store.thumbnail(for: pin)
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: HomePagePinRow.symbol(for: pin.kind))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The pin's title, or the start of its text, or what kind of pin it is.
    nonisolated static func name(of pin: Pin) -> String {
        let title = pin.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let text = pin.textBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return String(text.prefix(80)) }
        switch pin.kind {
        case .image: return "Photo"
        case .video: return "Video"
        case .link: return "Link"
        case .text: return "Text"
        }
    }

    nonisolated static func symbol(for kind: PinKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .link: return "link"
        case .text: return "text.alignleft"
        }
    }
}
