//
//  ShareView.swift  —  PinBoard share extension
//
//  The share sheet's screen: a preview of what is shared, the board to save it to, an optional
//  note, Cancel and Save. Hidden boards are never in the list (the app never writes them).
//

import SwiftUI
import UIKit

struct ShareView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Save to PinBoard")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !model.isSaved {   // (once saved, the sheet only says so and closes)
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { model.cancel() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { model.save() }
                                .fontWeight(.semibold)
                                .disabled(!model.canSave)
                        }
                    }
                }
        }
        .tint(ShareView.accent)
    }

    /// PinBoard's red (its default accent; the share sheet can't read the colour chosen in Settings).
    static let accent = Color(red: 0.90, green: 0.00, blue: 0.14)

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading(let text):
            VStack(spacing: 12) {
                ProgressView()
                Text(text).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .nothing:
            ShareMessage(symbol: "questionmark.square.dashed", title: "Nothing to save",
                         text: "PinBoard keeps pictures, GIFs, videos, links and text. None of these could be read.")
        case .failed:
            ShareMessage(symbol: "exclamationmark.triangle", title: "Couldn't save",
                         text: "PinBoard's shared folder couldn't be written. Open PinBoard once, then try again.")
        case .ready:
            form
        case .saved(let title, let text):
            ShareMessage(symbol: "checkmark.circle", title: title, text: text)
        }
    }

    private var form: some View {
        Form {
            Section {
                SharePreview(shown: model.shown)
            } footer: {
                Text(model.summary)
            }
            FamiliarSections(model: model)   // "Looks familiar" (ShareFamiliarViews.swift)
            if model.quickSave {
                // Quick save, held up only by a look-alike: no board or profile to choose.
                Section {
                } footer: {
                    Text("Saves to no board in “\(model.profileName)”. To choose a board when sharing, turn on “Choose a board when sharing” in PinBoard's \(ShareShared.chooseBoardSettingPath).")
                }
            } else {
                whereSection
                Section {
                    TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                        .lineLimit(1...5)
                }
            }
        }
        .solidShareBackground()
    }

    /// The profile (with several) and the board.
    private var whereSection: some View {
        Section {
            if model.showsProfiles {
                NavigationLink {
                    ProfileChoiceList(model: model)
                } label: {
                    LabeledContent("Profile", value: model.profileName)
                }
            }
            NavigationLink {
                BoardChoiceList(model: model)
            } label: {
                LabeledContent("Board", value: model.boardTitle)
            }
        } footer: {
            Text(boardFooter)
        }
    }

    /// When it arrives (a profile that isn't open: when that one is opened).
    private var boardFooter: String {
        guard model.profileID != nil else {
            return "Open PinBoard once to see your boards here. What you save now is added without a board."
        }
        var text = model.isOpenProfile
            ? "It's added to PinBoard the next time you open it."
            : "It's added to “\(model.profileName)” the next time you open that profile in PinBoard."
        if !model.hasWrittenList {
            text += " Open “\(model.profileName)” in PinBoard once to see its boards here."
        }
        return text
    }
}

/// The shared things: pictures and videos as small squares in a row, links and text below.
struct SharePreview: View {
    let shown: [ShareModel.Shown]

    private var visual: [ShareModel.Shown] { shown.filter { $0.item.file != nil } }
    private var words: [ShareModel.Shown] { shown.filter { $0.item.file == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !visual.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visual) { (each: ShareModel.Shown) in
                            ShareThumbnail(shown: each)
                        }
                    }
                }
            }
            ForEach(words.prefix(5)) { (each: ShareModel.Shown) in
                ShareWordsRow(item: each.item)
            }
            if words.count > 5 {
                Text("and \(words.count - 5) more").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A picture, GIF or video as a small square (a badge says which).
struct ShareThumbnail: View {
    let shown: ShareModel.Shown

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            picture
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            badge
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var picture: some View {
        if let image = shown.thumbnail {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
                .overlay(ProgressView())
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch shown.item.kind {
        case .video:
            Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white)
                .padding(5).background(.black.opacity(0.55), in: Circle()).padding(5)
        case .gif:
            Text("GIF").font(.caption2.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule()).padding(5)
        default:
            EmptyView()
        }
    }

    private var label: String {
        switch shown.item.kind {
        case .video: return "Video"
        case .gif: return "GIF"
        default: return "Picture"
        }
    }
}

/// A shared link (its site and address) or text (its first lines).
struct ShareWordsRow: View {
    let item: ShareInboxEntry.Item

    var body: some View {
        if item.kind == .link, let text = item.url {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(string: text)?.host ?? text).font(.subheadline.weight(.semibold))
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } icon: {
                Image(systemName: "link")
            }
        } else {
            Label {
                Text(item.text ?? "").font(.subheadline).lineLimit(4)
            } icon: {
                Image(systemName: "text.quote")
            }
        }
    }
}

extension View {
    /// The share sheet's steady background: the solid grouped grey (darker than the see-through
    /// glass iOS would show), behind the list and the title bar alike, so nothing shines through
    /// and nothing changes as the list scrolls. The owner asked for this in every board picker.
    func solidShareBackground() -> some View {
        let solid = Color(uiColor: .systemGroupedBackground)
        return self
            .scrollContentBackground(.hidden)
            .background(solid.ignoresSafeArea())
            .toolbarBackground(solid, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// A full-screen note: nothing could be read, or the inbox couldn't be written.
struct ShareMessage: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
