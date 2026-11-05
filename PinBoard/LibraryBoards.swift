//
//  LibraryBoards.swift  —  PinBoard
//
//  The part of `LibraryStore` about boards: making, renaming, moving, merging and deleting them,
//  their order, favorites and details, smart boards, the "Start here" proposals, the back-up
//  reminder, and which board a pin belongs on (board suggestions, "Sort into boards"). It is an
//  extension in its own file so that LibraryStore.swift stays short enough to paste.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

extension LibraryStore {

    // MARK: Boards

    @discardableResult
    func addBoard(name: String, parentID: UUID? = nil, secret: Bool = false) -> Board? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextIndex = (children(of: parentID).map { $0.sortIndex }.max() ?? -1) + 1
        var board = Board(name: trimmed, parentID: parentID, sortIndex: nextIndex)
        board.isSecret = secret
        boards.append(board)
        if let parentID { stampBoards(edited: [parentID]) }
        scheduleSave()
        return board
    }

    /// Adds a board record as it is (used when re-importing an export; ids are kept). It may have
    /// been erased here before: its tombstone goes. It keeps its own change date — so a newer edit
    /// made on another device still wins the next iCloud merge — moved just past that erase if it
    /// was erased here, so the merge keeps it instead of erasing it again (see `reinsertedDate`).
    func insertBoard(_ board: Board) {
        guard self.board(board.id) == nil else { return }
        var inserted = board
        if inserted.lastEditedAt == nil { inserted.lastEditedAt = board.updatedAt }   // "recently edited" keeps its real date
        inserted.updatedAt = LibraryStore.reinsertedDate(board.updatedAt, erasedAt: erased[board.id])
        erased[inserted.id] = nil
        boards.append(inserted)
        scheduleSave()
    }

    /// Adds a smart board record as it is (re-import); its change date is kept as for `insertBoard`.
    func insertSmartBoard(_ board: SmartBoard) {
        guard smartBoard(board.id) == nil else { return }
        var inserted = board
        inserted.updatedAt = LibraryStore.reinsertedDate(board.updatedAt, erasedAt: erased[board.id])
        erased[inserted.id] = nil
        smartBoards.append(inserted)
        smartBoards.sort { $0.sortIndex < $1.sortIndex }
        contentVersion += 1
        scheduleSave()
    }

    func modifyBoard(_ id: UUID, _ change: (inout Board) -> Void) {   // (not private: used by LibraryStore.swift)
        guard let index = boardIndex[id] else { return }
        var board = boards[index]
        // A board saved before "last edited" was kept takes its old date as that, so a change
        // that is not an edit (reordering, favorites) doesn't make it look edited just now.
        if board.lastEditedAt == nil { board.lastEditedAt = board.updatedAt }
        change(&board)
        board.updatedAt = Date()
        boards[index] = board
    }

    func renameBoard(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modifyBoard(id) { $0.name = trimmed; $0.lastEditedAt = Date() }
        scheduleSave()
    }

    func moveBoard(_ id: UUID, toParent parentID: UUID?) {
        if let parentID {
            // A board can't be moved into itself or into one of its own sub-boards.
            if parentID == id || descendants(of: id).contains(parentID) { return }
        }
        let nextIndex = (children(of: parentID).map { $0.sortIndex }.max() ?? -1) + 1
        let wasSecret = secretCache.contains(id)
        let oldParentID = board(id)?.parentID
        let oldParentSameSide = oldParentID.map { secretCache.contains($0) == wasSecret } ?? false
        modifyBoard(id) { $0.parentID = parentID; $0.sortIndex = nextIndex; $0.lastEditedAt = Date() }
        // Parents are stamped only on the moved board's side (a normal board never shows a change inside Hidden).
        var stamped: Set<UUID> = []
        if let oldParentID, oldParentSameSide { stamped.insert(oldParentID) }
        if let parentID, secretCache.contains(parentID) == secretCache.contains(id) { stamped.insert(parentID) }
        stampBoards(edited: stamped)
        if secretCache.contains(id) != wasSecret {
            // Moved into (or out of) a hidden board: it changed sides with everything inside it.
            if !wasSecret { detachVisibleSmartBoardsFromHiddenBoards() }
            separateDuplicatesAcrossHiddenLine(refresh: true)
        }
        tidyNestedMemberships()   // (a pin on this board and on the board it now sits in: only the inner one stays)
        scheduleSave()
    }

    func setCover(_ pinID: UUID?, for boardID: UUID) {
        guard board(boardID)?.coverPinID != pinID else { return }
        modifyBoard(boardID) { $0.coverPinID = pinID; $0.lastEditedAt = Date() }
        scheduleSave()
    }

    /// Hides a board (and everything inside it) in the Hidden folder, or brings it back.
    func setSecret(_ secret: Bool, for boardID: UUID) {
        modifyBoard(boardID) { $0.isSecret = secret; $0.lastEditedAt = Date() }
        // Sub-boards were hidden through the parent; when unhidden they keep their own flags.
        if secret { detachVisibleSmartBoardsFromHiddenBoards() }
        separateDuplicatesAcrossHiddenLine(refresh: true)
        tidyNestedMemberships()   // (an un-hidden sub-board: a pin on it and on its parent is now on both)
        scheduleSave()
    }

    /// A normal smart board can't look inside a hidden board: once its board (or a
    /// parent of it) is hidden, the smart board goes back to the whole normal library.
    private func detachVisibleSmartBoardsFromHiddenBoards() {
        let secret = secretCache
        var changed = false
        let now = Date()
        for index in smartBoards.indices where !smartBoards[index].isHidden {
            guard let boardID = smartBoards[index].filters.boardID, secret.contains(boardID) else { continue }
            smartBoards[index].filters.boardID = nil
            smartBoards[index].updatedAt = now
            changed = true
        }
        if changed {
            contentVersion += 1
            scheduleSave()
        }
    }

    /// Applies a new order to the boards that share a parent.
    func reorderBoards(parentID: UUID?, orderedIDs: [UUID]) {
        for (position, id) in orderedIDs.enumerated() {
            if let existing = board(id), existing.parentID == parentID, existing.sortIndex != position {
                modifyBoard(id) { $0.sortIndex = position }
            }
        }
        scheduleSave()
    }

    /// Applies a new order to the Hidden section's own boards (they may sit under different parents).
    func reorderHiddenRootBoards(_ orderedIDs: [UUID]) {
        let roots = Set(secretRootBoards.map { $0.id })
        for (position, id) in orderedIDs.enumerated() where roots.contains(id) {
            if let existing = board(id), existing.sortIndex != position {
                modifyBoard(id) { $0.sortIndex = position }
            }
        }
        scheduleSave()
    }

    /// Deletes a board and all of its sub-boards. Pins inside are either moved
    /// to "Recently deleted" (only the ones on no other board) or simply taken off.
    func deleteBoards(_ ids: Set<UUID>, deletePinsToo: Bool) {
        // A hidden board inside a normal board that is deleted is kept: it moves to the top of
        // Hidden with everything inside it (deleting on the normal side never removes what that
        // side can't show).
        for id in ids where !secretCache.contains(id) {
            let hiddenInside = descendants(of: id).filter { child in
                guard secretCache.contains(child), let parent = board(child)?.parentID else { return false }
                return !secretCache.contains(parent)
            }
            for child in hiddenInside { moveBoard(child, toParent: nil) }
        }
        var doomed: Set<UUID> = []
        for id in ids {
            doomed.insert(id)
            doomed.formUnion(descendants(of: id))
        }
        let onDoomed = Set(pins.filter { pin in pin.boardIDs.contains { doomed.contains($0) } }.map { $0.id })
        let remembering = Set(pins.filter { pin in pin.boardsBeforeHiding.contains { doomed.contains($0) } }.map { $0.id })
        let secret = secretCache
        // The pins these boards showed (a hidden pin only filed on one, out of sight, was never shown there).
        let shownOnDoomed = onDoomed.filter { id in
            pin(id).map { shownBoardIDs(for: $0).contains { doomed.contains($0) } } ?? false
        }
        modify(onDoomed.union(remembering)) { pin in
            let wasHidden = LibraryStore.isHidden(pin, secretBoards: secret)
            pin.boardIDs.removeAll { doomed.contains($0) }
            pin.boardsBeforeHiding.removeAll { doomed.contains($0) }
            if pin.boardIDs.isEmpty { pin.placementReason = nil }
            // A hidden pin never falls back into the normal library — not even onto a normal
            // board it was also filed on, out of sight (it goes to Hidden's Unsorted instead).
            if wasHidden, !LibraryStore.isHidden(pin, secretBoards: secret) {
                LibraryStore.keepHidden(&pin, secretBoards: secret)
            }
        }
        if deletePinsToo {
            // Only pins these boards showed that are now on no board of their side go to the trash.
            let orphaned = shownOnDoomed.filter { id in pin(id).map { shownBoardIDs(for: $0).isEmpty } ?? false }
            deletePins(orphaned)
        }
        let now = Date()
        for id in doomed { erased[id] = now }
        // A parent is stamped only on the deleted board's side (a normal board never shows a change inside Hidden).
        let parents = Set(ids.compactMap { id -> UUID? in
            guard let parent = board(id)?.parentID, secret.contains(parent) == secret.contains(id) else { return nil }
            return parent
        }).subtracting(doomed)
        boards.removeAll { doomed.contains($0.id) }
        stampBoards(edited: parents)
        smartBoardsCleared(boardIDs: doomed)
        scheduleSave()
    }

    /// Moves everything from `sources` into `target` and deletes the sources
    /// (their sub-boards become sub-boards of the target). A board the target sits in, or one
    /// that sits in the target, is never merged (it is skipped): deleting a board the target sits
    /// in would leave the target inside a deleted board — out of every list, and no longer hidden
    /// with it — and a hidden sub-board's pins would land on a normal target.
    /// Returns the boards that were merged: a board that contains the target, or is inside it,
    /// is skipped (merging it would orphan the target), so the caller can say so.
    @discardableResult
    func mergeBoards(_ sources: Set<UUID>, into target: UUID) -> Set<UUID> {
        guard board(target) != nil else { return [] }
        let around = Set(path(to: target).map { $0.id }).union(descendants(of: target))   // includes the target
        let real = sources.subtracting(around)
        guard !real.isEmpty else { return [] }
        let affected = Set(pins.filter { pin in
            pin.boardIDs.contains { real.contains($0) } || pin.boardsBeforeHiding.contains { real.contains($0) }
        }.map { $0.id })
        modify(affected) { pin in
            if pin.boardIDs.contains(where: { real.contains($0) }) {
                pin.boardIDs.removeAll { real.contains($0) }
                if !pin.boardIDs.contains(target) { pin.boardIDs.append(target) }
            }
            if pin.boardsBeforeHiding.contains(where: { real.contains($0) }) {
                pin.boardsBeforeHiding.removeAll { real.contains($0) }
                if !pin.boardsBeforeHiding.contains(target) { pin.boardsBeforeHiding.append(target) }
            }
        }
        for source in real {
            for child in children(of: source) { moveBoard(child.id, toParent: target) }
        }
        let now = Date()
        for id in real { erased[id] = now }
        boards.removeAll { real.contains($0.id) }
        // The whole library, not only `affected`: a pin on the target and on a board that moved inside it
        // (a sub-board of a merged board) was not on a merged board itself.
        tidyNestedMemberships()
        stampBoards(edited: [target], added: affected.isEmpty ? [] : [target])
        smartBoardsCleared(boardIDs: real)
        scheduleSave()
        return real
    }

    // MARK: Board order, favorites and details

    /// Stamps "last edited" (and, for `added`, "last added to") on boards, in one change of `boards`.
    /// A local statistic: `updatedAt` stays, so a sync never lets it win over a real edit made on
    /// another device. During an import the stamps are collected and written once at the end.
    func stampBoards(edited: Set<UUID>, added: Set<UUID> = []) {   // (not private: used by LibraryPins.swift, LibraryImports.swift and LibraryUpkeep.swift)
        let edited = edited.union(added)
        guard !edited.isEmpty else { return }
        if boardStampDepth > 0 {
            pendingEditedBoards.formUnion(edited)
            pendingAddedBoards.formUnion(added)
            return
        }
        let now = Date()
        var updated = boards
        var touched = false
        for id in edited {
            guard let index = boardIndex[id] else { continue }
            updated[index].lastEditedAt = now
            if added.contains(id) { updated[index].lastAddedAt = now }
            touched = true
        }
        if touched { boards = updated }
    }

    /// Board stamps wait until the matching `endBoardStampBatch()` (imports call these).
    func beginBoardStampBatch() {
        boardStampDepth += 1
    }

    func endBoardStampBatch() {
        boardStampDepth = max(0, boardStampDepth - 1)
        guard boardStampDepth == 0 else { return }
        let edited = pendingEditedBoards
        let added = pendingAddedBoards
        pendingEditedBoards = []
        pendingAddedBoards = []
        stampBoards(edited: edited, added: added)
    }

    /// Favorites first (in `sort` order), then the rest (in `sort` order). `.custom` = the manual
    /// order, then name; `.name` = A–Z; `.recentlyEdited` / `.recentlyAdded` = newest first (a board
    /// never added to comes last); ties by name.
    func sortedBoards(_ list: [Board], by sort: BoardSort) -> [Board] {
        var edited: [UUID: Date] = [:]
        var added: [UUID: Date] = [:]
        switch sort {
        case .recentlyEdited: for board in list { edited[board.id] = lastEditedDate(for: board.id) }
        case .recentlyAdded: for board in list { if let date = lastAddedDate(for: board.id) { added[board.id] = date } }
        case .custom, .name: break
        }
        func byName(_ a: Board, _ b: Board) -> Bool {
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
        func ordered(_ a: Board, _ b: Board) -> Bool {
            switch sort {
            case .custom:
                if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            case .name:
                break
            case .recentlyEdited:
                let da = edited[a.id] ?? .distantPast, db = edited[b.id] ?? .distantPast
                if da != db { return da > db }
            case .recentlyAdded:
                switch (added[a.id], added[b.id]) {
                case let (da?, db?) where da != db: return da > db
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            }
            return byName(a, b)
        }
        // (Written as closures: one Swift 6.0 compiler rejects passing the local function itself here.)
        let favorites = list.filter { $0.isFavorite }.sorted(by: { (a: Board, b: Board) -> Bool in ordered(a, b) })
        let others = list.filter { !$0.isFavorite }.sorted(by: { (a: Board, b: Board) -> Bool in ordered(a, b) })
        return favorites + others
    }

    /// The Boards page (or Hidden › Boards): every favorite board of the side, at any depth,
    /// then the side's other top-level boards — each group in `sort` order.
    func boardsPageBoards(scope: PinScope, sort: BoardSort) -> [Board] {
        let wantHidden = scope == .hidden
        let favorites = boards.filter { $0.isFavorite && secretCache.contains($0.id) == wantHidden }
        let roots = rootBoards(scope: scope).filter { !$0.isFavorite }
        return sortedBoards(favorites, by: sort) + sortedBoards(roots, by: sort)
    }

    /// A board page's sub-boards: the children on the board's own side (all of them inside a
    /// hidden board, only normal ones otherwise), favorites first.
    func sortedChildren(of parentID: UUID, sort: BoardSort) -> [Board] {
        let kids = secretCache.contains(parentID) ? children(of: parentID) : visibleChildren(of: parentID)
        return sortedBoards(kids, by: sort)
    }

    /// The board's descendants on its own side (a normal board never counts hidden sub-boards).
    private func sameSideDescendants(of boardID: UUID) -> [UUID] {
        let hidden = secretCache.contains(boardID)
        return descendants(of: boardID).filter { secretCache.contains($0) == hidden }
    }

    /// When a pin was last put on this board or one of its sub-boards (same side only): the newest
    /// of their "last added to" stamps and of the newest pin's date. A normal board ignores hidden
    /// sub-boards and hidden pins. nil = nothing was ever added.
    func lastAddedDate(for boardID: UUID) -> Date? {
        if let cached = lastAddedCache[boardID] { return cached }
        guard let board = board(boardID) else { return nil }
        var newest = board.lastAddedAt
        func consider(_ date: Date?) {
            guard let date else { return }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        for id in sameSideDescendants(of: boardID) { consider(self.board(id)?.lastAddedAt) }
        for id in pinIDs(in: boardID, includeNested: true) { consider(pin(id)?.createdAt) }
        lastAddedCache[boardID] = .some(newest)
        return newest
    }

    /// When this board or one of its sub-boards (same side only) last changed.
    func lastEditedDate(for boardID: UUID) -> Date {
        if let cached = lastEditedCache[boardID] { return cached }
        guard let board = board(boardID) else { return .distantPast }
        var newest = board.lastEditedAt ?? board.updatedAt
        for id in sameSideDescendants(of: boardID) {
            if let child = self.board(id) { newest = max(newest, child.lastEditedAt ?? child.updatedAt) }
        }
        lastEditedCache[boardID] = newest
        return newest
    }

    /// How many sub-boards sit directly inside this board, on its own side.
    func subBoardCount(of boardID: UUID) -> Int {
        secretCache.contains(boardID) ? children(of: boardID).count : visibleChildren(of: boardID).count
    }

    /// Adds a board to the favorites (top of the Boards page) or takes it off.
    func setFavorite(_ favorite: Bool, for boardID: UUID) {
        guard let board = board(boardID), board.isFavorite != favorite else { return }
        modifyBoard(boardID) { $0.isFavorite = favorite }
        scheduleSave()
    }

    /// The board's description ("" = none).
    func setBoardDetails(_ text: String, for boardID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let board = board(boardID), board.details != trimmed else { return }
        modifyBoard(boardID) { $0.details = trimmed; $0.lastEditedAt = Date() }
        scheduleSave()
    }

    /// Counts a visit to the board's page (a statistic of this device: not an edit).
    func noteBoardOpened(_ boardID: UUID) {
        guard let index = boardIndex[boardID] else { return }
        boards[index].openCount += 1
        scheduleSave()
    }

    /// Keeps the colors made from the board's pins, so they aren't worked out again (not an edit).
    func setPalette(_ hex: [String]?, for boardID: UUID) {
        guard let index = boardIndex[boardID] else { return }
        var board = boards[index]
        board.paletteHex = hex
        board.paletteMadeAt = hex == nil ? nil : Date()
        boards[index] = board
        scheduleSave()
    }

    /// Bytes of the files (picture, thumbnail, fingerprint, photo data, video) of the board's pins
    /// (the pins `pins(in:includeNested:)` lists), added up off the main thread.
    func storageSize(ofBoard boardID: UUID, includeNested: Bool) async -> Int64 {
        var files: [URL] = []
        for pin in pins(in: boardID, includeNested: includeNested) {
            if pin.hasImageFile {
                files.append(imagesURL.appendingPathComponent(pin.imageFileName))
                files.append(thumbsURL.appendingPathComponent(pin.thumbFileName))
            }
            files.append(printsURL.appendingPathComponent(pin.printFileName))
            files.append(exifURL.appendingPathComponent(pin.exifFileName))
            if pin.isVideo { files.append(videosURL.appendingPathComponent(pin.videoFileName)) }
        }
        guard !files.isEmpty else { return 0 }
        let list = files
        return await Task.detached(priority: .utility) { () -> Int64 in
            var total: Int64 = 0
            for url in list {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize { total += Int64(size) }
            }
            return total
        }.value
    }

    /// "Suggested" for a board picker: the board of `scope` that fits these pins best (board name,
    /// tag overlap and visual similarity, as `suggestBoards`), averaged over up to 12 of the pins.
    /// Boards every one of the pins is already on are left out; nil when nothing fits well enough.
    func suggestedBoard(for pinIDs: Set<UUID>, scope: PinScope) async -> BoardSuggestion? {
        let chosen = pinIDs.compactMap { livePin($0) }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString }
        guard let first = chosen.first else { return nil }
        var onAll = Set(first.boardIDs)
        for pin in chosen.dropFirst() { onAll.formIntersection(pin.boardIDs) }
        let wantHidden = scope == .hidden
        let targets = boards.filter { secretCache.contains($0.id) == wantHidden && !onAll.contains($0.id) }
        guard !targets.isEmpty else { return nil }
        let sample = LibraryStore.evenSample(chosen, limit: 12)
        let candidates = pins(scope: scope)
        var totals: [UUID: Double] = [:]
        var strongest: [UUID: BoardSuggestion] = [:]
        for pin in sample {
            let visual = await visualSimilarities(from: pin, printOverride: nil, among: candidates)
            let scored = await scoreBoards(targets, for: pin, visual: visual, among: candidates, minimumScore: 0, limit: targets.count)
            for suggestion in scored {
                totals[suggestion.board.id, default: 0] += suggestion.score
                if suggestion.score > (strongest[suggestion.board.id]?.score ?? -1) { strongest[suggestion.board.id] = suggestion }
            }
        }
        var best: (id: UUID, average: Double, name: String)? = nil
        for (id, total) in totals {
            let average = total / Double(sample.count)
            let name = board(id)?.name ?? ""
            if let current = best {
                if average < current.average { continue }
                if average == current.average, name.localizedStandardCompare(current.name) != .orderedAscending { continue }
            }
            best = (id, average, name)
        }
        guard let best, best.average >= 0.25, var suggestion = strongest[best.id], let board = board(best.id) else { return nil }
        suggestion.board = board
        suggestion.score = best.average
        return suggestion
    }

    /// Up to `limit` items spread evenly over the list (all of them when there are fewer).
    nonisolated static func evenSample<T>(_ items: [T], limit: Int) -> [T] {
        guard limit > 0, items.count > limit else { return items }
        return (0..<limit).map { items[$0 * items.count / limit] }
    }

    // MARK: Smart boards

    /// The smart boards of one scope (normal ones, or the Hidden section's), in the user's order.
    func smartBoards(scope: PinScope) -> [SmartBoard] {
        let wantHidden = scope == .hidden
        return smartBoards.filter { $0.isHidden == wantHidden }
    }

    @discardableResult
    func addSmartBoard(name: String, query: String, filters: SearchFilters, scope: PinScope = .visible) -> SmartBoard {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var board = SmartBoard(name: trimmed.isEmpty ? "Smart board" : trimmed, query: query, filters: filters,
                               isHidden: scope == .hidden)
        board.sortIndex = (smartBoards.map { $0.sortIndex }.max() ?? -1) + 1
        smartBoards.append(board)
        contentVersion += 1
        scheduleSave()
        return board
    }

    func smartBoard(_ id: UUID) -> SmartBoard? {
        smartBoards.first { $0.id == id }
    }

    func updateSmartBoard(_ board: SmartBoard) {
        guard let index = smartBoards.firstIndex(where: { $0.id == board.id }) else { return }
        var updated = board
        updated.updatedAt = Date()
        smartBoards[index] = updated
        contentVersion += 1
        scheduleSave()
    }

    func deleteSmartBoard(_ id: UUID) {
        smartBoards.removeAll { $0.id == id }
        erased[id] = Date()
        contentVersion += 1
        scheduleSave()
    }

    func excludePin(_ pinID: UUID, fromSmartBoard id: UUID) {
        guard var board = smartBoard(id) else { return }
        if !board.excludedPinIDs.contains(pinID) { board.excludedPinIDs.append(pinID) }
        updateSmartBoard(board)
    }

    /// "Reset": shows every matching pin again.
    func resetSmartBoard(_ id: UUID) {
        guard var board = smartBoard(id) else { return }
        board.excludedPinIDs = []
        updateSmartBoard(board)
    }

    func reorderSmartBoards(_ orderedIDs: [UUID]) {
        let now = Date()
        for (position, id) in orderedIDs.enumerated() {
            if let index = smartBoards.firstIndex(where: { $0.id == id }), smartBoards[index].sortIndex != position {
                smartBoards[index].sortIndex = position
                smartBoards[index].updatedAt = now
            }
        }
        smartBoards.sort { $0.sortIndex < $1.sortIndex }
        contentVersion += 1
        scheduleSave()
    }

    /// The pins a smart board shows right now (a hidden smart board looks at hidden pins only).
    func smartBoardPins(_ id: UUID) async -> [Pin] {
        guard let board = smartBoard(id) else { return [] }
        let excluded = Set(board.excludedPinIDs)
        let scope: PinScope = board.isHidden ? .hidden : .visible
        var filters = board.filters
        if board.query.isEmpty, !filters.isActive {
            // An empty rule shows everything, newest first.
            filters.sort = filters.sort == .relevance ? .newest : filters.sort
            let shown = pins(scope: scope).filter { !excluded.contains($0.id) }
            return LibraryStore.sorted(shown, by: filters.sort)
        }
        let hits = await search(board.query, filters: filters, scope: scope)
        return hits.map { $0.pin }.filter { !excluded.contains($0.id) }
    }

    /// A deleted board can no longer scope a smart board.
    private func smartBoardsCleared(boardIDs: Set<UUID>) {
        for index in smartBoards.indices where smartBoards[index].filters.boardID != nil && boardIDs.contains(smartBoards[index].filters.boardID!) {
            smartBoards[index].filters.boardID = nil
            smartBoards[index].updatedAt = Date()
        }
    }

    nonisolated static func sorted(_ pins: [Pin], by sort: SearchFilters.Sort) -> [Pin] {
        switch sort {
        case .relevance: return pins
        case .newest: return pins.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return pins.sorted { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: Start here — boards proposed from the library's own tags

    func proposeBoards(limit: Int = 4) -> [BoardProposal] {
        let existing = Set(boards.map { $0.name.lowercased() })
        var members: [String: [UUID]] = [:]
        for pin in visiblePins {
            var seen: Set<String> = []
            for tag in pin.tags { if seen.insert(tag.lowercased()).inserted { members[tag.lowercased(), default: []].append(pin.id) } }
            for tag in pin.aiTags where tag.confidence >= 0.45 && !TitleGenerator.genericLabels.contains(tag.label) {
                if seen.insert(tag.label).inserted { members[tag.label, default: []].append(pin.id) }
            }
        }
        return members
            .filter { $0.value.count >= 3 && !existing.contains($0.key) }
            .sorted { $0.value.count > $1.value.count || ($0.value.count == $1.value.count && $0.key < $1.key) }
            .prefix(limit)
            .map { BoardProposal(name: $0.key.titleCased, tag: $0.key, pinIDs: $0.value) }
    }

    func createProposedBoards(_ proposals: [BoardProposal]) {
        for proposal in proposals {
            guard let board = addBoard(name: proposal.name) else { continue }
            addPins(Set(proposal.pinIDs), to: board.id, reason: "Start here: tagged “\(proposal.tag)”")
        }
    }

    // MARK: Back-up reminder

    private var nudgeKey: String { "pinsAddedSinceExport.\(profileID.uuidString)" }
    private var exportKey: String { "lastExportAt.\(profileID.uuidString)" }

    func loadNudgeCounters() {   // (not private: used by LibraryStore.swift)
        pinsAddedSinceExport = UserDefaults.standard.integer(forKey: nudgeKey)
        lastExportAt = UserDefaults.standard.object(forKey: exportKey) as? Date
    }

    /// Counts new pins for the back-up reminder: only those of the normal library. A hidden pin is
    /// never counted there (the reminder shows on the normal side, and its number would give away
    /// that something was added to Hidden).
    func countNewPins(_ ids: [UUID]) {
        var count = 0
        for id in ids {
            if let pin = livePin(id), !isHidden(pin) { count += 1 }
        }
        guard count > 0 else { return }
        pinsAddedSinceExport += count
        UserDefaults.standard.set(pinsAddedSinceExport, forKey: nudgeKey)
    }

    /// True when enough was added since the last export (or the last "Later").
    var shouldNudgeBackup: Bool {
        pinsAddedSinceExport >= LibraryStore.backupNudgeThreshold
    }

    func recordExport() {
        pinsAddedSinceExport = 0
        lastExportAt = Date()
        UserDefaults.standard.set(0, forKey: nudgeKey)
        UserDefaults.standard.set(lastExportAt, forKey: exportKey)
    }

    /// "Later": counts from zero again.
    func snoozeBackupNudge() {
        pinsAddedSinceExport = 0
        UserDefaults.standard.set(0, forKey: nudgeKey)
    }

    // MARK: Board suggestions

    func suggestBoards(for pin: Pin, limit: Int = 3, printOverride: VNFeaturePrintObservation? = nil) async -> [BoardSuggestion] {
        let candidates = pins(scope: scope(of: pin))
        let visual = await visualSimilarities(from: pin, printOverride: printOverride, among: candidates)
        return await suggestBoards(for: pin, limit: limit, visual: visual, among: candidates)
    }

    /// Which boards would this pin fit in? Combines three on-device signals:
    ///   • the board's name vs. the pin's tags (works even for empty boards),
    ///   • how much the pin's tags overlap with the tags of pins already on the board,
    ///   • how visually similar the pin is to pins already on the board.
    /// Boards the pin is already on are left out; a normal pin is offered normal boards
    /// only, and a hidden pin hidden boards only.
    func suggestBoards(for pin: Pin, limit: Int, visual: [UUID: Double], among candidates: [Pin]) async -> [BoardSuggestion] {   // (not private: used by LibraryUpkeep.swift)
        guard !boards.isEmpty else { return [] }
        let hidden = isHidden(pin)
        let targets = boards.filter { !pin.isOn($0.id) && secretCache.contains($0.id) == hidden }
        return await scoreBoards(targets, for: pin, visual: visual, among: candidates, minimumScore: 0.2, limit: limit)
    }

    /// Scores how well `pin` fits each of `targets` (see `suggestBoards`), best first; boards
    /// scoring below `minimumScore` are left out.
    private func scoreBoards(_ targets: [Board], for pin: Pin, visual: [UUID: Double], among candidates: [Pin],
                             minimumScore: Double, limit: Int) async -> [BoardSuggestion] {
        guard !targets.isEmpty, limit > 0 else { return [] }
        // Everything the background pass needs, as plain values.
        var boardInfo: [(board: Board, nameWords: [(String, Double)], memberIDs: Set<UUID>)] = []
        let byID: [UUID: Pin] = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let membership = membership
        for board in targets {
            var nameWords: [(String, Double)] = []
            for word in SemanticMatcher.tokenize(board.name) { nameWords.append((word, 1.0)) }
            for ancestor in path(to: board.id).dropLast() {
                for word in SemanticMatcher.tokenize(ancestor.name) { nameWords.append((word, 0.6)) }
            }
            boardInfo.append((board, nameWords, (membership[board.id] ?? []).subtracting([pin.id])))
        }
        let snapshot = boardInfo
        // Words match by meaning through a language model's word map: for a hidden pin only with
        // "Include hidden pins in AI" on (otherwise as written and by their dictionary form).
        let byMeaning = aiMaySee(pin)
        return await Task.detached(priority: .userInitiated) { () -> [BoardSuggestion] in
            let matcher = SemanticMatcher.shared
            // The pin's tags, weighted (your own tags count most).
            var pinTags: [(label: String, weight: Double)] = []
            for tag in pin.tags { pinTags.append((label: tag.lowercased(), weight: 1.0)) }
            for tag in pin.fileKeywords { pinTags.append((label: tag, weight: 0.8)) }
            for tag in pin.aiTags { pinTags.append((label: tag.label, weight: 0.5 + 0.5 * tag.confidence)) }
            for tag in pin.ocrTags { pinTags.append((label: tag, weight: 0.6)) }
            for word in SemanticMatcher.tokenize(pin.title) where !pin.titleIsAuto {
                pinTags.append((label: word, weight: 0.9))
            }
            let focusTags = Array(pinTags.sorted { $0.weight > $1.weight }.prefix(8))
            var lemmas: [String: String] = [:]

            var suggestions: [BoardSuggestion] = []
            for info in snapshot {
                // 1. Name match (board name + parent names).
                var nameScore = 0.0
                var nameEvidence: [String] = []
                for (nameWord, nameWeight) in info.nameWords {
                    let lemma: String
                    if let known = lemmas[nameWord] { lemma = known } else { lemma = SemanticMatcher.lemmatize(nameWord); lemmas[nameWord] = lemma }
                    for (label, tagWeight) in pinTags {
                        var s = matcher.similarity(lemma, label, allowSemantic: byMeaning)
                        for part in SemanticMatcher.tokenize(label) where part != label {
                            s = max(s, matcher.similarity(lemma, part, allowSemantic: byMeaning) * 0.95)
                        }
                        let scored = s * nameWeight * (0.6 + 0.4 * tagWeight)
                        if scored > nameScore { nameScore = scored }
                        if s >= 0.6, !nameEvidence.contains(label) { nameEvidence.append(label) }
                    }
                }

                // 2. Tag overlap and 3. visual similarity with pins already on the board.
                let members = info.memberIDs.compactMap { byID[$0] }
                var tagScore = 0.0
                var visualScore = 0.0
                var sharedEvidence: [String] = []
                var lookalikes = 0
                if !members.isEmpty {
                    var profile: [String: Double] = [:]
                    for member in members {
                        var seen: Set<String> = []
                        for tag in member.aiTags where tag.confidence > 0.3 {
                            if seen.insert(tag.label).inserted { profile[tag.label, default: 0] += 1 }
                        }
                        for tag in member.tags + member.ocrTags + member.fileKeywords {
                            let t = tag.lowercased()
                            if seen.insert(t).inserted { profile[t, default: 0] += 1 }
                        }
                    }
                    let count = Double(members.count)
                    var numerator = 0.0
                    var denominator = 0.0
                    for (label, weight) in focusTags {
                        let frequency = (profile[label] ?? 0) / count
                        numerator += weight * min(1, frequency * 1.5)
                        denominator += weight
                        if frequency >= 0.34 { sharedEvidence.append(label) }
                    }
                    tagScore = denominator > 0 ? numerator / denominator : 0

                    let memberSimilarities = members.compactMap { visual[$0.id] }.sorted(by: >).prefix(3)
                    if !memberSimilarities.isEmpty {
                        visualScore = memberSimilarities.reduce(0, +) / Double(memberSimilarities.count)
                        lookalikes = memberSimilarities.filter { $0 >= 0.5 }.count
                    }
                }

                let weightedName = 0.55 * nameScore
                let weightedTags = 0.25 * tagScore
                let weightedVisual = 0.35 * visualScore
                let score = min(1, weightedName + weightedTags + weightedVisual)
                guard score >= minimumScore else { continue }

                let reason: String
                var evidence: [String]
                if weightedName >= weightedTags && weightedName >= weightedVisual {
                    reason = "board name matches its tags"
                    evidence = nameEvidence
                } else if weightedVisual >= weightedTags {
                    reason = "looks like pins already here"
                    evidence = lookalikes > 0 ? ["\(lookalikes) look-alike pin\(lookalikes == 1 ? "" : "s")"] : []
                } else {
                    reason = "shares tags with pins already here"
                    evidence = sharedEvidence
                }
                if evidence.isEmpty { evidence = Array((nameEvidence + sharedEvidence).prefix(3)) }
                suggestions.append(BoardSuggestion(board: info.board, score: score, reason: reason, evidence: Array(evidence.prefix(4))))
            }
            return Array(suggestions.sorted { $0.score > $1.score }.prefix(limit))
        }.value
    }

    /// Puts each pin on its best-matching board (if the AI is confident enough)
    /// — in addition to any board it is already on. Returns how many moved.
    func autoSort(_ ids: Set<UUID>, minimumScore: Double = 0.4) async -> Int {
        guard !isAutoSorting else { return 0 }   // one sort at a time
        isAutoSorting = true
        defer { isAutoSorting = false }
        let profile = profileID
        var moved = 0
        let ordered = Array(ids)
        // The progress shows on the Pins tab (the normal side's): never with a count of hidden pins.
        let showsProgress = !ordered.contains { id in pin(id).map { isHidden($0) } ?? false }
        for (index, id) in ordered.enumerated() {
            if showsProgress { setImportStatus("Sorting \(index + 1) of \(ordered.count)…", scope: .visible) }
            guard let pin = pin(id) else { continue }
            let best = await suggestBoards(for: pin, limit: 1).first
            guard isCurrentProfile(profile) else { break }   // another library now: its boards aren't these
            guard let best, best.score >= minimumScore else { continue }
            let why = best.evidence.isEmpty ? best.reason : best.evidence.joined(separator: ", ")
            addPins([id], to: best.board.id, reason: "Auto-sort: \(why)")
            moved += 1
        }
        if showsProgress { setImportStatus(nil, scope: .visible) }
        return moved
    }
}
