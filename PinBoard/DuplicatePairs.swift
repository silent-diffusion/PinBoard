//
//  DuplicatePairs.swift  —  PinBoard
//
//  The duplicate pair card (two look-alikes side by side, with a way to delete
//  either or keep both) and the sheet that merges their titles and notes. A pin's
//  page and Settings › Library › Possible duplicates show it.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Duplicate pairs

/// The two look-alikes side by side, labelled Newer and Older, with a way to
/// delete either (its boards and tags move to the survivor) or keep both.
struct DuplicatePairView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.pinAccent) private var accent
    let newer: Pin
    let older: Pin
    var showsCards: Bool = true

    private struct Merge: Identifiable {
        var id: String { keep.id.uuidString + remove.id.uuidString }
        var keep: Pin
        var remove: Pin
    }

    @State private var pendingMerge: Merge? = nil        // waiting for the delete confirmation
    @State private var confirmed: Merge? = nil           // confirmed; resolved once the dialog is gone
    @State private var showConfirm = false
    @State private var fieldChoice: Merge? = nil         // the sheet asking which title / note to keep

    /// The delete that is being asked about right now (the question, or the which-title
    /// sheet after it). While there is one, the cards show what will happen.
    private var previewedMerge: Merge? { pendingMerge ?? confirmed ?? fieldChoice }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCards {
                HStack(alignment: .top, spacing: 12) {
                    column("Newer", pin: newer)
                    column("Older", pin: older)
                }
            }
            HStack(spacing: 8) {
                Button("Delete newer", role: .destructive) { ask(keep: older, remove: newer) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Delete older", role: .destructive) { ask(keep: newer, remove: older) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Keep both") { store.keepBoth(newer.id, older.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text("Deleting one moves it to Recently Deleted; its boards and tags go to the other. “Keep both” hides the pair from future checks.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(pendingMerge.map { "Delete the \($0.remove.id == newer.id ? "newer" : "older") copy?" } ?? "",
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete and merge", role: .destructive) {
                confirmed = pendingMerge
                pendingMerge = nil
            }
            Button("Cancel", role: .cancel) { pendingMerge = nil }
        } message: {
            Text("Its boards and tags move to the copy you keep.")
        }
        .animation(.easeInOut(duration: 0.2), value: previewedMerge?.id)
        .onChange(of: showConfirm) { _, shown in
            guard !shown else { return }
            // Closed by tapping outside it counts as Cancel: the cards go back to normal.
            pendingMerge = nil
            // The follow-up sheet waits until the dialog has actually gone.
            if let merge = confirmed {
                confirmed = nil
                resolve(merge)
            }
        }
        .sheet(item: $fieldChoice) { merge in
            MergeFieldsSheet(keep: merge.keep, remove: merge.remove) { title, note in
                store.mergeDuplicates(keep: merge.keep.id, remove: merge.remove.id, title: title, note: note)
            }
            .hiddenPrivacyCover(store.scope(of: merge.keep) == .hidden)   // hidden pins' titles and notes: never in the App Switcher
        }
    }

    private func column(_ label: String, pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label + " · " + pin.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            let deleting = previewedMerge?.remove.id == pin.id
            let keeping = previewedMerge?.keep.id == pin.id
            NavigationLink(value: Route.pin(pin.id, .none)) { PinCardView(pin: pin) }
                .buttonStyle(.plain)
                // While a delete is being confirmed: the copy that goes is grey with a
                // trash can on it; the copy that stays is a little bigger, with a frame.
                .grayscale(deleting ? 1 : 0)
                .opacity(deleting ? 0.45 : 1)
                .overlay {
                    if deleting {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if keeping {
                        RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous)
                            .strokeBorder(accent, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(keeping ? 1.04 : 1)
                .accessibilityValue(deleting ? "Will be deleted" : (keeping ? "Will be kept" : ""))
            if !store.boardNames(for: pin).isEmpty {
                Text(store.boardNames(for: pin).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ask(keep: Pin, remove: Pin) {
        pendingMerge = Merge(keep: keep, remove: remove)
        showConfirm = true
    }

    /// Merges straight away unless both have a different title or note — then asks which to keep.
    private func resolve(_ merge: Merge) {
        let titleConflict = !merge.keep.title.isEmpty && !merge.remove.title.isEmpty && merge.keep.title != merge.remove.title
        let noteConflict = !merge.keep.note.isEmpty && !merge.remove.note.isEmpty && merge.keep.note != merge.remove.note
        if titleConflict || noteConflict {
            fieldChoice = merge
        } else {
            store.mergeDuplicates(keep: merge.keep.id, remove: merge.remove.id)
        }
    }
}

/// "Both have a title / note — which one do you want to keep?"
struct MergeFieldsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let keep: Pin
    let remove: Pin
    let onConfirm: (String?, String?) -> Void

    @State private var keepTitle = true
    @State private var keepNote = true

    private var titleConflict: Bool { !keep.title.isEmpty && !remove.title.isEmpty && keep.title != remove.title }
    private var noteConflict: Bool { !keep.note.isEmpty && !remove.note.isEmpty && keep.note != remove.note }

    var body: some View {
        NavigationStack {
            Form {
                if titleConflict {
                    Section("Which title?") {
                        choice(keep.title, selected: keepTitle) { keepTitle = true }
                        choice(remove.title, selected: !keepTitle) { keepTitle = false }
                    }
                }
                if noteConflict {
                    Section("Which note?") {
                        choice(keep.note, selected: keepNote) { keepNote = true }
                        choice(remove.note, selected: !keepNote) { keepNote = false }
                    }
                }
                Section {
                    Text("Boards and tags from both copies are combined either way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Keep which?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        onConfirm(titleConflict ? (keepTitle ? keep.title : remove.title) : nil,
                                  noteConflict ? (keepNote ? keep.note : remove.note) : nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(text).foregroundStyle(Color.primary)
                Spacer()
            }
        }
    }
}
