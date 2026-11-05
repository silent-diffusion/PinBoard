//
//  LibrarySaving.swift  —  PinBoard
//
//  The part of `LibraryStore` that writes the library to disk: right away, finished before
//  returning, or shortly after the last change. It is an extension in its own file so that
//  LibraryStore.swift stays short enough to paste.
//
//  Why a delayed save may not be postponed for ever: after "Import a folder…" the AI looks at
//  every new pin, and each pin it tags asked for a save 3 seconds later — which put off the
//  import's own save again and again. Closing the app then (from the App Switcher, which may
//  never reach "background") lost the whole import. Now a delayed save happens at the latest
//  a few seconds after the oldest unsaved change, and every bulk change (an import, a restore,
//  a sync's merge) saves the moment it is done.
//

import SwiftUI

extension LibraryStore {

    /// The longest a change waits for its save while more changes keep coming (typing, the AI
    /// tagging pin after pin). A longer `delay` asked for by `scheduleSave` still counts.
    private static let longestWait: Double = 2

    /// Writes the library in the background (encoding a big library takes a
    /// moment, and this runs after every tagged pin). The writer keeps the saves in order and
    /// keeps the safety copies (see `LibraryWriter`). The task returned ends once the file is
    /// written (see `saveNowAndWait`).
    @discardableResult
    func saveNow() -> Task<Void, Never> {
        saveTask?.cancel()
        saveTask = nil
        unsavedSince = nil
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = document
        let target = location
        let writer = writer
        return Task.detached(priority: .utility) { [weak self] in
            guard let data = LibraryStore.encodeDocument(snapshot) else { return }
            // A newer save already written (say the one made going to the background) wins: this one is dropped.
            guard writer.write(data, generation: generation, to: target) else { return }
            let store = self
            await MainActor.run {
                guard let store, generation > store.savedGeneration else { return }
                store.savedGeneration = generation
                store.onSaved?()
            }
        }
    }

    /// Saves now and returns once the file is written — for the end of a bulk change (an import,
    /// a restore), before "done" is shown. The encoding and writing happen off the main actor,
    /// so the screen keeps moving meanwhile, also for a big library.
    func saveNowAndWait() async {
        await saveNow().value
    }

    /// Same, but finished before returning — for the moment the app goes to the background.
    /// It goes through the same writer: it waits for a background write already under way, and
    /// no older background save can land on the file after it.
    func saveNowSynchronously() {
        saveTask?.cancel()
        saveTask = nil
        unsavedSince = nil
        saveGeneration += 1
        savedGeneration = saveGeneration
        guard let data = LibraryStore.encodeDocument(document) else { return }
        writer.write(data, generation: saveGeneration, to: location)
        onSaved?()
    }

    /// The app steps out of the front ("inactive": the App Switcher, Control Center): a save
    /// still waiting is started now, in the background. Closing the app from the App Switcher
    /// may end it without it ever reaching "background" (where `saveNowSynchronously` runs).
    func saveIfPending() {
        guard saveTask != nil else { return }
        saveNow()
    }

    /// Saves shortly after the last change (so typing doesn't write on every key) — but never
    /// later than `longestWait` (or `delay`, if longer) after the oldest change still unsaved.
    func scheduleSave(after delay: Double = 0.4) {   // (not private: the extensions in MediaStorage.swift and SmartLinks.swift save too)
        let now = Date()
        let oldest = unsavedSince ?? now
        unsavedSince = oldest
        let latest = oldest.addingTimeInterval(max(delay, LibraryStore.longestWait))
        let wait = max(0, min(delay, latest.timeIntervalSince(now)))
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
            // A pin un-hidden by any path (or the switch turned on) gets the AI's look now.
            self.startAnalysisIfNeeded()
        }
    }
}
