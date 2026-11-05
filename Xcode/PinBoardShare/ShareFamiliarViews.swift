//
//  ShareFamiliarViews.swift  —  PinBoard share extension
//
//  The share sheet's "Looks familiar" part, under the preview, in the app's own words (8.4):
//    • the same link or text already in PinBoard: one grey line, "Already in PinBoard: it'll be
//      added to Travel." (the pin you have goes on the board, nothing is saved twice);
//    • a look-alike picture or video: "New" and "Already in your library" side by side, then the
//      app's answers — "Save as a new pin" (the default), "Add the existing pin to this board",
//      "Skip this one" — and, with several, "Save all N as new" / "Add all N existing" / "Skip all N".
//  The answer is saved with the item; PinBoard carries it out when it takes the item in.
//

import SwiftUI
import UIKit

struct FamiliarSections: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        let exact = model.exactItems
        let similar = model.similarItems
        if !exact.isEmpty {
            Section {
                Label(exactText(count: exact.count, first: exact.first), systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(Array(similar.enumerated()), id: \.element.id) { (offset: Int, shown: ShareModel.Shown) in
            Section {
                FamiliarComparison(model: model, shown: shown)
                choiceRows(for: shown)
            } header: {
                Text(header(for: shown, number: offset + 1, of: similar.count))
            }
        }
        if similar.count > 1 {
            Section {
                allButtons(count: similar.count)
            }
        }
    }

    /// "This picture looks like one you already have" — and, with several, "2 of 3".
    private func header(for shown: ShareModel.Shown, number: Int, of count: Int) -> String {
        let what = shown.item.kind == .video ? "This video looks like one you already have"
                                             : "This picture looks like one you already have"
        return count > 1 ? "\(what) (\(number) of \(count))" : what
    }

    /// The same link or text: the pin you have goes on the board.
    private func exactText(count: Int, first: ShareModel.Shown?) -> String {
        let board = model.boardID == nil ? nil : model.boardTitle
        if count == 1 {
            guard let board else { return "Already in PinBoard: it won't be saved twice." }
            if let first, let match = model.familiar[first.id], model.isOnChosenBoard(match) { return "Already in PinBoard, on \(board)." }
            return "Already in PinBoard: it'll be added to \(board)."
        }
        guard let board else { return "\(count) are already in PinBoard: they won't be saved twice." }
        return "\(count) are already in PinBoard: they'll be added to \(board)."
    }

    @ViewBuilder
    private func choiceRows(for shown: ShareModel.Shown) -> some View {
        choiceRow("Save as a new pin", .saveNew, for: shown)
        if let match = model.familiar[shown.id] {
            if model.boardID == nil {
                if !model.quickSave {
                    Text("Choose a board to add the existing pin to it instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.isOnChosenBoard(match) {
                Text("The existing pin is already on this board.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                choiceRow("Add the existing pin to this board", .addExisting, for: shown)
            }
        }
        choiceRow("Skip this one", .skip, for: shown)
    }

    private func choiceRow(_ title: String, _ choice: ShareChoice, for shown: ShareModel.Shown) -> some View {
        Button {
            model.choices[shown.id] = choice
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if (model.choices[shown.id] ?? .saveNew) == choice {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One answer for every look-alike ("Add all N existing" only with a board).
    private func allButtons(count: Int) -> some View {
        HStack(spacing: 8) {
            Button("Save all \(count) as new") { model.chooseForAll(.saveNew) }
            if model.boardID != nil {
                Button("Add all \(count) existing") { model.chooseForAll(.addExisting) }
            }
            Button("Skip all \(count)") { model.chooseForAll(.skip) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.footnote)
        .frame(maxWidth: .infinity)
    }
}

/// "New" and "Already in your library" side by side, with the boards the pin you have is on.
struct FamiliarComparison: View {
    @ObservedObject var model: ShareModel
    let shown: ShareModel.Shown

    var body: some View {
        let match = model.familiar[shown.id]
        HStack(alignment: .top, spacing: 12) {
            column("New", image: shown.thumbnail, caption: nil)
            column("Already in your library", image: match.flatMap { model.existingThumbs[$0.existing.id] },
                   caption: match.flatMap { boardsCaption($0.existing) })
        }
        .padding(.vertical, 4)
    }

    private func column(_ title: String, image: UIImage?, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            picture(image)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func picture(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    /// "On: Travel, Japan" (nothing when the pin is on no board).
    private func boardsCaption(_ pin: ShareFamiliarIndex.Known) -> String? {
        pin.boardNames.isEmpty ? nil : "On: " + pin.boardNames.joined(separator: ", ")
    }
}
