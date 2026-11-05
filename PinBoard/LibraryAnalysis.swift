//
//  LibraryAnalysis.swift  —  PinBoard
//
//  The part of `LibraryStore` that works out what pins are: the background AI queue (tags, titles,
//  descriptions), the cloud model's answer, "Re-run AI → Names" with its Undo, and natural-language
//  search. It is an extension in its own file so that LibraryStore.swift stays short enough to paste.
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

extension LibraryStore {

    // MARK: AI analysis queue

    /// Analyzes every pin that hasn't been looked at yet, one after another,
    /// in the background. Safe to call as often as you like.
    func startAnalysisIfNeeded() {
        wakePinsTheAIMaySeeNow()
        guard analysisTask == nil, hasPinWaitingForQueue else { return }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await self.runAnalysis()
            if Task.isCancelled { return }   // a newer queue may already be running
            self.analysisTask = nil
            if self.hasPinWaitingForQueue {
                self.startAnalysisIfNeeded()
            }
        }
    }

    /// A live pin waits for the AI's look, and no naming request is looking at it already
    /// (`lookingBeforeNaming`: that look ends by itself, and starts the queue if it was dropped).
    private var hasPinWaitingForQueue: Bool {
        pins.contains { (pin: Pin) -> Bool in pin.needsAnalysis && !pin.isDeleted && !lookingBeforeNaming.contains(pin.id) }
    }

    /// How far the AI queue has got: over both sides, and on each side of the library.
    private struct AnalysisTally {
        var done = 0
        var total = 0
        var visibleDone = 0
        var visibleTotal = 0
        var hiddenDone = 0
        var hiddenTotal = 0

        mutating func finished(hidden: Bool) {
            done += 1
            if hidden { hiddenDone += 1 } else { visibleDone += 1 }
        }
    }

    /// What the AI still has to look at: the next pin, and how many wait on each side.
    private struct AnalysisQueue {
        var next: Pin? = nil
        var visibleWaiting = 0
        var hiddenWaiting = 0
    }

    /// The next pin is one of the normal library's while any waits, so the Pins tab's progress
    /// (normal pins only) is done before any hidden pin is looked at. A pin a naming request is
    /// looking at right now (`lookingBeforeNaming`) still counts as waiting, but is never the next
    /// one: it would be looked at twice.
    private func analysisQueue() -> AnalysisQueue {
        var queue = AnalysisQueue()
        var firstHidden: Pin? = nil
        let secret = secretCache
        for pin in pins where pin.needsAnalysis && !pin.isDeleted {
            let free = !lookingBeforeNaming.contains(pin.id)
            if LibraryStore.isHidden(pin, secretBoards: secret) {
                queue.hiddenWaiting += 1
                if firstHidden == nil && free { firstHidden = pin }
            } else {
                queue.visibleWaiting += 1
                if queue.next == nil && free { queue.next = pin }
            }
        }
        if queue.next == nil { queue.next = firstHidden }
        return queue
    }

    /// Shows how far the queue has got: over both sides (`analysisProgress`) and each side on its
    /// own — nil for a side with nothing waiting, so the normal side's count never includes a hidden pin.
    private func publishAnalysisProgress(_ tally: inout AnalysisTally, queue: AnalysisQueue) {
        let waiting = queue.visibleWaiting + queue.hiddenWaiting
        tally.total = max(tally.total, tally.done + waiting)
        tally.visibleTotal = max(tally.visibleTotal, tally.visibleDone + queue.visibleWaiting)
        tally.hiddenTotal = max(tally.hiddenTotal, tally.hiddenDone + queue.hiddenWaiting)
        analysisProgress = AnalysisProgress(done: tally.done, total: max(tally.total, tally.done + 1))
        if queue.visibleWaiting > 0 {
            visibleAnalysisProgress = AnalysisProgress(done: tally.visibleDone, total: max(tally.visibleTotal, tally.visibleDone + 1))
        } else {
            visibleAnalysisProgress = nil
        }
        if queue.hiddenWaiting > 0 {
            hiddenAnalysisProgress = AnalysisProgress(done: tally.hiddenDone, total: max(tally.hiddenTotal, tally.hiddenDone + 1))
        } else {
            hiddenAnalysisProgress = nil
        }
    }

    /// The tagging progress counted on one side only (nil = nothing of that side is waiting). The
    /// Pins tab's pill uses `.visible`: a hidden pin being tagged never shows or counts there.
    func analysisProgress(for scope: PinScope) -> AnalysisProgress? {
        switch scope {
        case .visible: return visibleAnalysisProgress
        case .hidden: return hiddenAnalysisProgress
        }
    }

    func clearAnalysisProgress() {   // (not private: used by LibraryStore.swift and LibraryUpkeep.swift)
        analysisProgress = nil
        visibleAnalysisProgress = nil
        hiddenAnalysisProgress = nil
    }

    private func runAnalysis() async {
        let settings = AppSettings.shared
        let profile = profileID   // the library being looked at (see `isCurrentProfile`)
        var tally = AnalysisTally()
        var cloudFailures = 0
        looksOutsideQueue = []    // (only looks taken while this queue runs count)
        while true {
            // Pins a naming request looked at meanwhile are done too (they no longer wait).
            for hiddenLook in looksOutsideQueue { tally.finished(hidden: hiddenLook) }
            looksOutsideQueue = []
            let queue = analysisQueue()
            guard let pin = queue.next else { break }
            if Task.isCancelled || !isCurrentProfile(profile) { return }
            let hidden = isHidden(pin)
            publishAnalysisProgress(&tally, queue: queue)
            if LibraryStore.analysisPath(for: pin) == .text {
                await analyzeTextPin(pin.id, settings: settings)
                tally.finished(hidden: hidden)
                scheduleSave(after: 3)
                continue
            }
            // While it looks, a naming request waits for this look instead of taking its own.
            // A picture kept in iCloud only comes back first (a video's poster is always here).
            // Without a connection the run stops; it starts again with the next change.
            if !pin.isVideo, isOffloaded(pin), !(await ensureLocal(pin)) { break }
            analysingNow.insert(pin.id)
            let looked = await analyzePicture(pin, settings: settings)
            analysingNow.remove(pin.id)
            guard let result = looked else {
                if Task.isCancelled || !isCurrentProfile(profile) { return }
                // Looked at meanwhile (a naming request got there first): done. Otherwise the pin is
                // gone, or its picture was turned or cut meanwhile (it waits for the next round).
                if let now = self.pin(pin.id), !now.needsAnalysis { tally.finished(hidden: hidden) }
                continue
            }

            // Hidden (now), with "Include hidden pins in AI" off: no naming, no cloud model.
            if let now = self.pin(pin.id), !aiMaySee(now) {
                tally.finished(hidden: hidden)
                scheduleSave(after: 3)
                continue
            }

            // Name pins whose title the AI may write (untitled, or still the AI's own title).
            // Every title of this pass can be undone back to the one from before it.
            var pass: TitlePass? = nil
            if let current = self.pin(pin.id), current.titleIsAIOwned {
                var started = TitlePass(current)
                if settings.autoTitle {
                    await nameAfterLook(current, result: result, pass: &started, settings: settings)
                    if Task.isCancelled || !isCurrentProfile(profile) { return }
                }
                pass = started
            }

            // Optional cloud model: sees the picture, returns much better tags.
            // (A hidden pin only with "Include hidden pins in AI": `cloudMaySee`.)
            if let now = self.pin(pin.id), cloudMaySee(now), cloudFailures < 5 {
                let imageURL = imagesURL.appendingPathComponent(pin.imageFileName)
                // A video named from what is said in it keeps that name: the cloud model only sees its
                // poster (nothing said in a video is sent anywhere), so its title would be the worse one.
                let spoken = self.pin(pin.id)?.hasSpokenWords ?? false
                let ok = await applyCloudAnalysis(to: pin.id, imageURL: imageURL, pass: spoken ? nil : pass)
                if !isCurrentProfile(profile) { return }
                cloudFailures = ok ? 0 : cloudFailures + 1
                if cloudFailures >= 5 { cloudLastError = (cloudLastError ?? "The cloud model keeps failing") + " — paused until the next run." }
            }

            tally.finished(hidden: hidden)
            scheduleSave(after: 3)
        }
        clearAnalysisProgress()
        saveNow()
    }

    /// The AI queue's naming of a pin it has just looked at (its title is the AI's to write): the
    /// on-device title at once, then Apple Intelligence's when it is on. A link with text
    /// (`.pictureAndText`) is named from that text first, the picture's tags second
    /// (`nameFromText`); every other pin from what was seen in its picture.
    private func nameAfterLook(_ current: Pin, result: AnalysisResult, pass: inout TitlePass, settings: AppSettings) async {
        if LibraryStore.analysisPath(for: current) == .pictureAndText {
            await nameFromText(current.id, secondLabels: result.tags.map { $0.label }, pass: &pass, settings: settings)
            return
        }
        let profile = profileID
        let context = titleContext(for: current)
        writeAITitle(quickTitle(for: current, tags: result.tags, text: result.text, context: context), for: current.id, pass: &pass)
        guard settings.appleIntelligenceActive else { return }
        let labels = result.tags.map { $0.label }
        let smart = await AppleIntelligence.generateTitle(tags: labels, text: result.text, context: context)
        // Unasked, a title of only the person's own words is left out (the quick one stays).
        guard !Task.isCancelled, isCurrentProfile(profile), let smart, !TitleGenerator.isEcho(smart, context: context) else { return }
        writeAITitle(smart, for: current.id, pass: &pass)
    }

    /// Names a pin from its own text first — a text pin's text, a link's article or description
    /// (owner's bug 16): the on-device title from the first lines of the text now, then Apple
    /// Intelligence's (the text is its main input, `secondLabels` — what was detected in a link's
    /// preview picture, or a text's key words — come second). The pin's tags are the text's key
    /// words already (`analyzeTextContent`, `linkTags`), so they lead the on-device title's fall-back too.
    private func nameFromText(_ id: UUID, secondLabels: [String], pass: inout TitlePass, settings: AppSettings) async {
        let profile = profileID
        guard let current = pin(id) else { return }
        let context = titleContext(for: current)
        writeAITitle(quickTitle(for: current, tags: current.aiTags, text: "", context: context), for: id, pass: &pass)
        guard settings.appleIntelligenceActive else { return }
        // (A video's own text is what is said in it: the model names it from that, the poster's words second.)
        let source: TitleGenerator.TitleTextSource = current.isLink || current.isVideo ? .page : .picture
        let smart = await AppleIntelligence.generateTitle(tags: Array(secondLabels.prefix(8)), text: LibraryStore.titleText(of: current),
                                                          context: context, textSource: source)
        guard !Task.isCancelled, isCurrentProfile(profile), let smart, !TitleGenerator.isEcho(smart, context: context) else { return }
        writeAITitle(smart, for: id, pass: &pass)
    }

    /// The on-device look at a pin with a picture — the AI queue's first step, also taken before
    /// naming a pin that is still waiting for it (`lookBeforeNaming`): tags, colours, text read in
    /// the picture, its fingerprint, and whether it is a look-alike of an older pin. Returns what
    /// was found; nil when the work was dropped (stopped, another profile now), the pin is gone,
    /// its picture changed meanwhile (turned or cut: the result is of the old one), or another look
    /// at it finished first (the queue and a naming request can reach the same pin).
    private func analyzePicture(_ pin: Pin, settings: AppSettings) async -> AnalysisResult? {
        let profile = profileID
        let imageURL = imagesURL.appendingPathComponent(pin.imageFileName)
        let printURL = printsURL.appendingPathComponent(pin.printFileName)
        let accurate = settings.accurateOCR
        let usesAI = aiMaySee(pin)   // a hidden pin, with "Include hidden pins in AI" off: the fixed checks only
        let result = await Task.detached(priority: .utility) {
            VisionAnalyzer.analyze(imageURL: imageURL, accurateText: accurate, usesAI: usesAI)
        }.value
        if Task.isCancelled || !isCurrentProfile(profile) { return nil }
        guard let now = self.pin(pin.id), now.needsAnalysis, now.pictureRevision == pin.pictureRevision else { return nil }
        // Hidden while it was looked at (or hidden already): what the AI found is dropped.
        if !usesAI || !aiMaySee(now) { return keepFixedChecks(result, for: pin, printURL: printURL) }
        if let printData = result.featurePrint {
            try? printData.write(to: printURL, options: .atomic)
            printCache[pin.id] = nil
            printsMissing.remove(pin.id)
        }
        modify(pin.id) { current in
            current.aiTags = result.tags
            current.colorTags = result.colorTags
            current.ocrText = result.text
            current.ocrTags = result.ocrTags
            current.dhash = result.dhash
            current.needsAnalysis = false
            current.aiSkipped = false
            current.hasFeaturePrint = result.featurePrint != nil
            // A link's own words matter too — with text, they come first (owner's bug 16). So do the
            // words said in a video (its transcript).
            if current.isLink || current.hasSpokenWords { current.aiTags = LibraryStore.linkTags(of: current, pictureTags: result.tags) }
        }
        // Only the newer of two look-alikes gets flagged.
        if let current = self.pin(pin.id), let twin = findDuplicate(of: current), twin.createdAt <= current.createdAt {
            modify(pin.id) { $0.duplicateOfID = twin.id }
        }
        return result
    }

    /// A look without AI (a hidden pin while "Include hidden pins in AI" is off): only the fixed
    /// checks are kept — colours, the perceptual hash, the fingerprint and the look-alike check.
    /// What the AI found before stays (the person's data is never deleted); the pin is marked
    /// `aiSkipped`, so it gets the AI's look once the AI may see it. Returns the result without AI parts.
    private func keepFixedChecks(_ result: AnalysisResult, for pin: Pin, printURL: URL) -> AnalysisResult {
        if let printData = result.featurePrint {
            try? printData.write(to: printURL, options: .atomic)
            printCache[pin.id] = nil
            printsMissing.remove(pin.id)
        }
        modify(pin.id) { current in
            current.colorTags = result.colorTags
            current.dhash = result.dhash
            current.hasFeaturePrint = result.featurePrint != nil
            current.needsAnalysis = false
            current.aiSkipped = true
        }
        if let current = self.pin(pin.id), let twin = findDuplicate(of: current), twin.createdAt <= current.createdAt {
            modify(pin.id) { $0.duplicateOfID = twin.id }
        }
        return AnalysisResult(tags: [], colorTags: result.colorTags, text: "", ocrTags: [],
                              featurePrint: result.featurePrint, dhash: result.dhash)
    }

    /// Text pins (and links without a picture): tags are the key words of the
    /// text; the title is its first line.
    private func analyzeTextPin(_ id: UUID, settings: AppSettings) async {
        guard let keywords = analyzeTextContent(id), let current = self.pin(id), !current.isLink, aiMaySee(current) else { return }
        guard settings.autoTitle, current.titleIsAIOwned else { return }
        var pass = TitlePass(current)
        await nameFromText(id, secondLabels: keywords, pass: &pass, settings: settings)
    }

    /// The key words of a text pin's text (a link's description) become its tags. Returns them
    /// (nil = the pin is gone).
    @discardableResult
    private func analyzeTextContent(_ id: UUID) -> [String]? {
        guard let pin = pin(id) else { return nil }
        guard aiMaySee(pin) else {
            // Hidden, with "Include hidden pins in AI" off: no key words (they come from a language
            // model), nothing else changes; the AI looks once it may (`aiSkipped`).
            modify(id) { current in
                current.needsAnalysis = false
                current.aiSkipped = true
            }
            return []
        }
        let body = pin.isLink ? LibraryStore.linkText(of: pin) : pin.textBody
        let keywords = VisionAnalyzer.keywords(fromText: body + "\n" + pin.title)
        modify(id) { current in
            current.aiTags = keywords.map { TagScore(label: $0, confidence: 0.6) }
            current.ocrTags = []
            current.ocrText = ""
            current.needsAnalysis = false
            current.aiSkipped = false
        }
        return keywords
    }

    /// Before the AI names a pin it hasn't looked at yet (new, or turned or cut since): the AI
    /// queue's look at it (`analyzePicture`, or the key words of a text), without the queue's own
    /// naming — the naming that asked for it comes next. While it looks, the queue leaves the pin
    /// alone (`lookingBeforeNaming`); a look it takes while the queue runs counts in the queue's
    /// progress (`looksOutsideQueue`). Returns false when the work was dropped (stopped, or another
    /// profile now).
    private func lookBeforeNaming(_ pin: Pin, settings: AppSettings) async -> Bool {
        let profile = profileID
        let hidden = isHidden(pin)
        if LibraryStore.analysisPath(for: pin) == .text {
            analyzeTextContent(pin.id)
            countLookOutsideQueue(hidden: hidden)
            return true
        }
        lookingBeforeNaming.insert(pin.id)
        let result = await analyzePicture(pin, settings: settings)
        lookingBeforeNaming.remove(pin.id)
        // Not looked at after all (stopped, or its picture changed meanwhile): the queue takes it.
        if result == nil { startAnalysisIfNeeded() }
        guard !Task.isCancelled, isCurrentProfile(profile) else { return false }
        if result != nil { countLookOutsideQueue(hidden: hidden) }
        return true
    }

    /// A look taken outside the AI queue while it runs: it counts as done in the queue's progress.
    private func countLookOutsideQueue(hidden: Bool) {
        if analysisTask != nil { looksOutsideQueue.append(hidden) }
    }

    /// The first step of naming a pin (a naming run, Suggest): when the AI hasn't looked at it yet,
    /// its look. When the AI queue is looking at it right now, that look is waited for (up to ten
    /// seconds) instead of taking a second one; a pin still waiting after that is looked at here.
    /// `going`: false when the naming must stop (stopped, or another profile now). `lookedHere`:
    /// the naming took the look itself (then a cloud request may merge its tags, as the queue would).
    func lookFirst(_ id: UUID, settings: AppSettings) async -> (going: Bool, lookedHere: Bool) {   // (not private: used by LibraryPins.swift)
        let profile = profileID
        if isBeingLookedAt(id) {
            await waitForLook(at: id, seconds: 10)
            if Task.isCancelled || !isCurrentProfile(profile) { return (false, false) }
        }
        guard let waiting = pin(id), waiting.needsAnalysis else { return (true, false) }
        let going = await lookBeforeNaming(waiting, settings: settings)
        return (going && !Task.isCancelled && isCurrentProfile(profile), true)
    }

    /// The AI queue (or another naming request, say Suggest during a run) is looking at the pin now.
    private func isBeingLookedAt(_ id: UUID) -> Bool {
        analysingNow.contains(id) || lookingBeforeNaming.contains(id)
    }

    /// Waits (checking every tenth of a second, at most `seconds`) while the AI is looking at a pin
    /// that still needs its look.
    private func waitForLook(at id: UUID, seconds: Double) async {
        var waited = 0.0
        while waited < seconds, !Task.isCancelled, isBeingLookedAt(id), pin(id)?.needsAnalysis == true {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
    }

    /// The person's own words about a pin, for titling. A normal pin's boards are normal boards
    /// (`boardNames(for:)`). A hidden pin's are hidden boards: their names only help to spot a title
    /// that repeats them (`TitleContext.echoOnlyBoardNames`) — never a word of a title, never told
    /// to Apple Intelligence or the cloud model — so no title (or cloud tag) carries a hidden board's
    /// name to the normal side after Unhide.
    func titleContext(for pin: Pin) -> TitleContext {
        let names = boardNames(for: pin)
        let hidden = isHidden(pin)
        return TitleContext(userTags: pin.tags,
                            boardNames: hidden ? [] : names,
                            note: pin.personalNote,   // (a video's transcript in its note is the item's own text, not the person's words)
                            fileKeywords: pin.fileKeywords,
                            fileCaption: pin.fileCaption,
                            echoOnlyBoardNames: hidden ? names : [])
    }

    /// One AI naming pass over a pin: the title from before the pass (what Undo goes back to),
    /// and the title the pin must still have for the pass to keep writing (the person may
    /// edit it meanwhile, and then theirs stays).
    private struct TitlePass {
        let before: TitleState
        let undoBefore: TitleUndo?
        var expected: String
        /// "Rename all with AI": the pass may replace a title the person wrote too.
        let mayReplaceYours: Bool

        init(_ pin: Pin, mayReplaceYours: Bool = false) {
            before = pin.titleState
            undoBefore = pin.titleUndo
            expected = pin.title
            self.mayReplaceYours = mayReplaceYours
        }

        func allows(_ pin: Pin) -> Bool {
            if pin.isDeleted { return false }
            if !mayReplaceYours && !pin.titleIsAIOwned { return false }
            return pin.title == expected
        }
    }

    /// Writes an AI title within a pass (empty or unchanged titles are not written).
    /// Returns whether the title changed.
    @discardableResult
    private func writeAITitle(_ title: String, for id: UUID, pass: inout TitlePass, runID: UUID? = nil) -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let current = pin(id), pass.allows(current), cleaned != current.title else { return false }
        let before = pass.before
        let undoBefore = pass.undoBefore
        modify(id) { pin in
            pin.setAITitle(cleaned, replacing: before, runID: runID)
            // Back at the title the pass started from: the Undo it had applies again.
            if pin.title == before.title { pin.titleUndo = undoBefore }
        }
        pass.expected = cleaned
        return true
    }

    /// Asks the cloud model (if configured) about one pin and merges its answer.
    /// Returns false when the call failed.
    @discardableResult
    func applyCloudAnalysis(to pinID: UUID, imageURL: URL) async -> Bool {
        // (A video named from what is said in it keeps that name: the cloud model only sees its poster.)
        let pass = pin(pinID).flatMap { ($0.titleIsAIOwned && !$0.hasSpokenWords) ? TitlePass($0) : nil }
        return await applyCloudAnalysis(to: pinID, imageURL: imageURL, pass: pass)
    }

    /// `pass`: the naming pass a cloud title belongs to (nil = the pin's title is left alone).
    /// A title that only repeats the person's own words is not used.
    private func applyCloudAnalysis(to pinID: UUID, imageURL: URL, pass: TitlePass?) async -> Bool {
        let settings = AppSettings.shared
        let profile = profileID
        guard let current = pin(pinID), cloudMaySee(current) else { return false }
        let context = titleContext(for: current)
        let names = context.boardNames   // (a hidden pin's hidden boards are not told: see `titleContext`)
        let userTags = current.tags
        let pageText = LibraryStore.textForCloud(of: current)   // a link's own text: what it is named from first
        let provider = settings.cloudProvider
        let model = settings.cloudModel
        let key = settings.cloudKey
        let outcome: Result<CloudAnalysis, Error> = await Task.detached(priority: .utility) { () async -> Result<CloudAnalysis, Error> in
            do {
                guard let data = try? Data(contentsOf: imageURL) else { throw CloudAIError.imageTooLarge }
                return .success(try await CloudAI.analyze(imageData: data, boardNames: names, userTags: userTags, pageText: pageText,
                                                          provider: provider, model: model, apiKey: key))
            } catch {
                return .failure(error)
            }
        }.value
        // Another profile now (or the pin is gone): the answer is dropped.
        guard isCurrentProfile(profile), pin(pinID) != nil else { return false }
        switch outcome {
        case .success(let analysis):
            applyCloudTags(analysis, to: pinID)
            if var pass, let title = analysis.title, !TitleGenerator.isEcho(title, context: context) {
                writeAITitle(title, for: pinID, pass: &pass)
            }
            cloudLastError = nil
            scheduleSave(after: 3)
            return true
        case .failure(let error):
            cloudLastError = error.localizedDescription
            return false
        }
    }

    /// Merges the cloud model's tags, description and search words into a pin (its title is
    /// dealt with by the caller).
    private func applyCloudTags(_ analysis: CloudAnalysis, to pinID: UUID) {
        modify(pinID) { pin in
            pin.aiTags = LibraryStore.mergeTags(cloud: analysis.tags, onDevice: pin.aiTags)
            pin.aiDescription = LibraryStore.descriptionAfterCloud(current: pin.aiDescription, cloud: analysis.description, isLink: pin.isLink)
            pin.aiSearchHint = analysis.searchQuery
        }
    }

    /// Cloud tags first, then the on-device ones it didn't mention (a little discounted).
    nonisolated static func mergeTags(cloud: [TagScore], onDevice: [TagScore]) -> [TagScore] {
        var merged = cloud
        for tag in onDevice where !merged.contains(where: { $0.label == tag.label }) {
            merged.append(TagScore(label: tag.label, confidence: tag.confidence * 0.8))
        }
        return Array(merged.prefix(24))
    }

    // MARK: Re-run AI → Names

    /// Live pins of the side the AI may rename: not links without a picture (there is nothing to
    /// go on), and their title is empty or still the AI's own (`titleIsAIOwned`) — or any title
    /// with `includeYourNames` ("Rename all with AI"). Pins the AI hasn't looked at yet count too:
    /// the naming looks at them first. `among` limits it to those pins (a board's, a selection,
    /// one pin); nil = the whole side.
    func namingCandidates(scope: PinScope, among ids: Set<UUID>? = nil, includeYourNames: Bool = false) -> [Pin] {
        var result: [Pin] = []
        for pin in pins(scope: scope) {
            if let ids, !ids.contains(pin.id) { continue }
            if !includeYourNames && !pin.titleIsAIOwned { continue }
            if pin.isLink && !pin.hasPreview { continue }
            if !aiMaySee(pin) { continue }   // hidden, with "Include hidden pins in AI" off
            result.append(pin)
        }
        return result
    }

    /// "AI sorting → naming": names the candidates again, one at a time in the background.
    /// Without `includeYourNames` a title the person typed is never touched; with it every
    /// title may change. The whole run can be undone (`undoLastNamingRun`) — unless
    /// `recordsRun` is false (one pin: its own Undo is on its page, and the side's last
    /// run stays undoable). Does nothing while a run is going. Returns the run's id, for
    /// `namingOutcome(of:)` (nil = nothing was started).
    @discardableResult
    func rerunNaming(scope: PinScope, among ids: Set<UUID>? = nil, includeYourNames: Bool = false, recordsRun: Bool = true) -> UUID? {
        guard namingTask == nil else { return nil }
        let chosen = namingCandidates(scope: scope, among: ids, includeYourNames: includeYourNames).map { $0.id }
        guard !chosen.isEmpty else { return nil }
        let run = NamingRun(id: UUID(), date: Date(), hidden: scope == .hidden, renamed: 0)
        activeNamingRun = run
        namingRunRecorded = recordsRun
        namingScope = scope
        namingProgress = AnalysisProgress(done: 0, total: chosen.count)
        namingTask = Task { [weak self] in
            await self?.runNaming(chosen, scope: scope, includeYourNames: includeYourNames)
        }
        return run.id
    }

    /// Stops the run; what was renamed so far stays (and can be undone as one run).
    func stopNaming() {
        guard namingTask != nil else { return }
        namingTask?.cancel()
        finishNaming(completed: false)
    }

    /// Waits until the naming run `id` (from `rerunNaming`) has ended, and tells what it did:
    /// how many pins it renamed (`NamingRun.changed`) and how many kept their names
    /// (`NamingRun.kept`). nil = it was stopped (or another profile was chosen) before the end.
    /// Each run's outcome is told once.
    func namingOutcome(of id: UUID) async -> NamingRun? {
        if activeNamingRun?.id == id, let task = namingTask {
            await task.value
        }
        return namingOutcomes.removeValue(forKey: id)
    }

    /// The last run on one side that renamed something (for "Undo last AI naming").
    func lastNamingRun(scope: PinScope) -> NamingRun? {
        let hidden = scope == .hidden
        return lastNamingRuns.first { $0.hidden == hidden }
    }

    /// Puts back every name of that side's last run that still has the title the run wrote
    /// (pins in Recently Deleted too). Returns how many names were put back.
    @discardableResult
    func undoLastNamingRun(scope: PinScope) -> Int {
        guard let run = lastNamingRun(scope: scope) else { return 0 }
        let ids = Set(pins.filter { $0.titleUndo?.runID == run.id }.map { $0.id })
        var restored = 0
        modify(ids) { pin in
            if pin.undoAITitle() { restored += 1 }
        }
        lastNamingRuns.removeAll { $0.id == run.id }
        UserDefaults.standard.removeObject(forKey: namingRunKey(hidden: run.hidden))
        scheduleSave()
        return restored
    }

    enum CloudTitle {   // (not private: used by LibraryPins.swift)
        case title(String)
        case unusable            // answered, but with no title
        case failed(String)      // the call failed (the message)
    }

    /// One pin after another: a pin the AI hasn't looked at yet is looked at first (`lookFirst`:
    /// never a second time while the AI queue is at it); then it gets the best title that differs
    /// from the one it has (`explicitTitle`: the cloud model's first, when it is on) — or, when
    /// nothing different is found, it keeps its name and is counted (`NamingRun.kept`). A title the
    /// AI queue wrote meanwhile is renamed in turn (`renewedPass`); one the person typed stays.
    private func runNaming(_ ids: [UUID], scope: PinScope, includeYourNames: Bool) async {
        let settings = AppSettings.shared
        let profile = profileID   // the library being renamed (a switch also stops the run)
        var useCloud = settings.cloudActive
        var cloudFailures = 0
        for (index, id) in ids.enumerated() {
            // Lets the progress show and Stop get through, even when nothing below has to wait
            // (the on-device namer alone never does).
            await Task.yield()
            if Task.isCancelled { return }
            namingProgress = AnalysisProgress(done: index, total: ids.count)
            // Skip pins that were deleted or moved to the other side meanwhile — and, unless
            // names the person wrote may change too, pins they renamed meanwhile.
            guard let found = livePin(id), self.scope(of: found) == scope, aiMaySee(found) else { continue }
            if !includeYourNames && !found.titleIsAIOwned { continue }
            var pass = TitlePass(found, mayReplaceYours: includeYourNames)
            var lookedHere = false
            if found.needsAnalysis {
                let look = await lookFirst(id, settings: settings)
                if !look.going || Task.isCancelled || !isCurrentProfile(profile) { return }
                lookedHere = look.lookedHere
            }
            // The pin as it is after the look: the queue may have named it meanwhile.
            guard let current = livePin(id), self.scope(of: current) == scope, aiMaySee(current),
                  let renewed = renewedPass(pass, for: current) else { continue }
            pass = renewed
            var fromCloud: String? = nil
            if useCloud, cloudMaySee(current), current.hasImageFile {
                let answer = await cloudTitle(for: current, mergingTags: lookedHere)
                if Task.isCancelled || !isCurrentProfile(profile) { return }
                switch answer {
                case .title(let title):
                    cloudFailures = 0
                    fromCloud = title
                case .unusable:
                    cloudFailures = 0          // the on-device namer takes over
                case .failed(let message):
                    cloudFailures += 1         // this pin is named on the device instead
                    if cloudFailures >= 5 {
                        useCloud = false
                        cloudLastError = message + " — the rest of this renaming is done on this device."
                    }
                }
            }
            guard let named = livePin(id), let namedPass = renewedPass(pass, for: named) else { continue }
            pass = namedPass
            let newTitle = await explicitTitle(for: named, first: fromCloud, settings: settings)
            if Task.isCancelled || !isCurrentProfile(profile) { return }
            // Typed over, deleted or moved meanwhile: not this run's to change (nor to count).
            // Renamed by the AI meanwhile (the queue's own naming): that title is renamed in turn.
            guard let latest = livePin(id), self.scope(of: latest) == scope,
                  let latestPass = renewedPass(pass, for: latest) else { continue }
            pass = latestPass
            // Nothing different was found (or the queue meanwhile wrote this very title): the pin
            // keeps its name.
            guard let newTitle, !TitleGenerator.sameTitle(newTitle, latest.title) else {
                activeNamingRun?.kept += 1
                continue
            }
            let runID = namingRunRecorded ? activeNamingRun?.id : nil
            if writeAITitle(newTitle, for: id, pass: &pass, runID: runID) {
                // A rename Undo can put back, or a first title for an untitled pin (no Undo).
                if pin(id)?.titleUndo != nil {
                    activeNamingRun?.renamed += 1
                } else {
                    activeNamingRun?.firstNames += 1
                }
                scheduleSave(after: 3)
            } else {
                activeNamingRun?.kept += 1
            }
        }
        if Task.isCancelled { return }
        finishNaming()
    }

    /// The title pass to go on naming `pin` with: `pass` itself while the pin still has the title
    /// the pass expects; a new pass from the pin's title now when the AI renamed it meanwhile (the
    /// queue's own naming of a pin it just looked at) — so that title is renamed (or counted as
    /// kept) instead of being skipped; nil when the pin was deleted or the person changed its
    /// title meanwhile (theirs stays, and the pin isn't counted).
    private func renewedPass(_ pass: TitlePass, for pin: Pin) -> TitlePass? {
        if pass.allows(pin) { return pass }
        guard !pin.isDeleted, pin.title != pass.expected, pin.titleIsAIOwned else { return nil }
        return TitlePass(pin, mayReplaceYours: pass.mayReplaceYours)
    }

    /// Ends the run: records it when it made a rename Undo can put back, keeps what it did for
    /// `namingOutcome(of:)` when it ran to the end (not when stopped), clears the progress.
    private func finishNaming(completed: Bool = true) {
        if let run = activeNamingRun {
            if namingRunRecorded, run.renamed > 0 { recordNamingRun(run) }
            if completed {
                if namingOutcomes.count > 20 { namingOutcomes = [:] }   // (nobody asked for those)
                namingOutcomes[run.id] = run
            }
        }
        activeNamingRun = nil
        namingRunRecorded = false
        namingProgress = nil
        namingScope = nil
        namingTask = nil
        scheduleSave()
    }

    /// The cloud model's title for a pin. Only its title is used — unless `mergingTags` (the pin
    /// was only just looked at on the device, before naming it): then its tags, description and
    /// search words are merged in too, as the AI queue would have done (one request for both).
    /// A title that only repeats the person's own words is returned too: the naming ranks it last.
    func cloudTitle(for pin: Pin, mergingTags: Bool = false) async -> CloudTitle {   // (not private: used by LibraryPins.swift)
        // A video named from what is said in it: the cloud model only sees its poster (nothing said in a
        // video is sent anywhere), so its title is never wanted — and it is not asked at all unless its
        // tags are (`mergingTags`).
        if pin.hasSpokenWords && !mergingTags { return .unusable }
        guard cloudMaySee(pin) else { return .unusable }   // a hidden pin, unless "Include hidden pins" is on
        let settings = AppSettings.shared
        let profile = profileID
        if !pin.isVideo { await ensureLocal(pin) }   // a picture kept in iCloud only comes back first
        let imageURL = imageFileURL(for: pin)
        let names = titleContext(for: pin).boardNames   // (never a hidden board's name: see `titleContext`)
        let userTags = pin.tags
        let pageText = LibraryStore.textForCloud(of: pin)
        let provider = settings.cloudProvider
        let model = settings.cloudModel
        let key = settings.cloudKey
        let outcome: Result<CloudAnalysis, Error> = await Task.detached(priority: .utility) { () async -> Result<CloudAnalysis, Error> in
            do {
                guard let data = try? Data(contentsOf: imageURL) else { throw CloudAIError.imageTooLarge }
                return .success(try await CloudAI.analyze(imageData: data, boardNames: names, userTags: userTags, pageText: pageText,
                                                          provider: provider, model: model, apiKey: key))
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let analysis):
            cloudLastError = nil
            if mergingTags, isCurrentProfile(profile), self.pin(pin.id) != nil {
                applyCloudTags(analysis, to: pin.id)
                scheduleSave(after: 3)
            }
            let title = (analysis.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty || pin.hasSpokenWords ? .unusable : .title(title)
        case .failure(let error):
            cloudLastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    /// A new title for a pin the person asked the AI to name ("Name with AI", "Rename with AI",
    /// the pin page's Suggest): the best title that differs from the one it has — nil when
    /// nothing different was found (the pin keeps its name). Tried in this order until one
    /// differs: `first` (the cloud model's title, when it was asked), Apple Intelligence asked for
    /// a title other than the current one (when it is on), then the on-device titles
    /// (`TitleGenerator.alternativeTitles`). A title that only repeats the person's own words is
    /// taken only when nothing else differs (`TitleGenerator.bestNewTitle`).
    func explicitTitle(for pin: Pin, first: String?, settings: AppSettings) async -> String? {   // (not private: used by LibraryPins.swift)
        let context = titleContext(for: pin)
        let text = LibraryStore.titleText(of: pin)
        // A text pin, or a link with text (owner's bug 16): named from its text first, the picture's tags second.
        // A video with a transcript the same — except that the on-device titles are not lines of what is
        // said (a talk starts with a greeting): they are made of its key words, the poster's text aside.
        let fromLinkText = LibraryStore.analysisPath(for: pin) == .pictureAndText
        let fromSpeech = pin.hasSpokenWords
        let fromText = pin.isText || (fromLinkText && !fromSpeech)
        // What the AI recognized: a word of these is never "only the person's own word" (see `bestNewTitle`).
        let recognized: [String] = pin.aiTags.map { (tag: TagScore) -> String in tag.label }
        var candidates: [String] = []
        if let first { candidates.append(first) }
        if let found = TitleGenerator.bestNewTitle(from: candidates, current: pin.title, context: context, labels: recognized),
           !TitleGenerator.isEcho(found, context: context) {
            return found
        }
        if settings.appleIntelligenceActive {
            let labels: [String] = fromLinkText ? LibraryStore.pictureLabels(of: pin)
                                                : pin.aiTags.prefix(pin.isText ? 8 : pin.aiTags.count).map { $0.label }
            let source: TitleGenerator.TitleTextSource = fromLinkText ? .page : .picture
            if let smart = await AppleIntelligence.generateTitle(tags: labels, text: text, context: context,
                                                                 avoiding: pin.title, textSource: source) {
                candidates.append(smart)
            }
            if let found = TitleGenerator.bestNewTitle(from: candidates, current: pin.title, context: context, labels: recognized),
               !TitleGenerator.isEcho(found, context: context) {
                return found
            }
        }
        candidates += TitleGenerator.alternativeTitles(tags: pin.aiTags, text: fromSpeech ? pin.ocrText : text, context: context,
                                                       current: pin.title, preferText: fromText)
        return TitleGenerator.bestNewTitle(from: candidates, current: pin.title, context: context, labels: recognized)
    }

    private func namingRunKey(hidden: Bool) -> String {
        "lastNamingRun.\(hidden ? "hidden" : "visible").\(profileID.uuidString)"
    }

    private func recordNamingRun(_ run: NamingRun) {
        lastNamingRuns.removeAll { $0.hidden == run.hidden }
        lastNamingRuns.append(run)
        if let data = try? JSONEncoder().encode(run) {
            UserDefaults.standard.set(data, forKey: namingRunKey(hidden: run.hidden))
        }
    }

    func loadNamingRuns() {   // (not private: used by LibraryStore.swift)
        lastNamingRuns = [false, true].compactMap { hidden in
            guard let data = UserDefaults.standard.data(forKey: namingRunKey(hidden: hidden)) else { return nil }
            return try? JSONDecoder().decode(NamingRun.self, from: data)
        }
    }

    func forgetNamingRuns() {   // (not private: used by LibraryUpkeep.swift)
        for hidden in [false, true] { UserDefaults.standard.removeObject(forKey: namingRunKey(hidden: hidden)) }
        lastNamingRuns = []
    }

    // MARK: Natural-language search

    /// `extraTerms` are optional related words (e.g. from Apple Intelligence)
    /// that count a little less than the words the user typed. `scope` picks the
    /// pins searched: the normal library, or hidden pins only. A Hidden-section search
    /// limited to a hidden board looks at every pin on that board. A normal search never
    /// looks inside a hidden board (such a board limit is ignored) and never matches a
    /// hidden board's name.
    func search(_ query: String, extraTerms: [String] = [], filters: SearchFilters = SearchFilters(), scope: PinScope = .visible) async -> [SearchHit] {
        var resolved = filters
        let secret = secretCache
        if let boardID = filters.boardID {
            if scope == .visible, secret.contains(boardID) {
                resolved.boardID = nil
            } else {
                let tree = [boardID] + descendants(of: boardID)
                resolved.boardScopeIDs = Set(scope == .visible ? tree.filter { !secret.contains($0) } : tree)
            }
        }
        let boardIsSecret = scope == .hidden && (filters.boardID.map { secret.contains($0) } ?? false)
        // On a hidden board every pin counts (as on the board's own page); the board
        // filter then keeps only that board's pins.
        let searched = boardIsSecret ? livePins : pins(scope: scope)
        // A hidden pin's normal boards (filed out of sight) never count for Hidden's filters
        // ("Unsorted only" then agrees with Hidden › Unsorted).
        let snapshot = scope == .visible ? searched : searched.map { pin -> Pin in
            var copy = pin
            copy.boardIDs.removeAll { !secret.contains($0) }
            return copy
        }
        // Board names count as words only for boards of the side being searched.
        let wantSecret = scope == .hidden
        var boardNames: [UUID: String] = [:]
        for board in boards where secret.contains(board.id) == wantSecret { boardNames[board.id] = board.name }
        let names = boardNames
        let effective = resolved
        // Matching by meaning uses a language model's word map: inside Hidden only with "Include
        // hidden pins in AI" on (otherwise words match as written, and by their dictionary form).
        let byMeaning = scope == .visible || AppSettings.shared.aiIncludesHidden
        return await Task.detached(priority: .userInitiated) {
            LibraryStore.performSearch(query: query,
                                       extraTerms: extraTerms,
                                       pins: snapshot,
                                       boardNames: names,
                                       filters: effective,
                                       matcher: SemanticMatcher.shared,
                                       byMeaning: byMeaning)
        }.value
    }

    nonisolated static func passesFilters(_ pin: Pin, _ filters: SearchFilters, now: Date) -> Bool {
        if !filters.boardScopeIDs.isEmpty, !pin.boardIDs.contains(where: { filters.boardScopeIDs.contains($0) }) { return false }
        if filters.unsortedOnly, !pin.boardIDs.isEmpty { return false }
        if filters.untaggedOnly, !pin.tags.isEmpty { return false }
        if filters.withTextOnly, pin.ocrText.isEmpty, pin.textBody.isEmpty { return false }
        if filters.duplicatesOnly, pin.duplicateOfID == nil { return false }
        if !filters.kinds.isEmpty, !filters.kinds.contains(pin.kind) { return false }
        // Length and sound filters keep videos only; a length or sound not known yet
        // leaves the video out until the background check has filled it in.
        if filters.duration != .any || filters.sound != .any {
            guard pin.isVideo else { return false }
            if filters.duration != .any {
                guard let seconds = pin.duration, seconds > 0, filters.duration.contains(seconds) else { return false }
            }
            switch filters.sound {
            case .any: break
            case .withSound: if pin.hasAudio != true { return false }
            case .withoutSound: if pin.hasAudio != false { return false }
            }
        }
        let days: Double?
        switch filters.dateRange {
        case .any: days = nil
        case .week: days = 7
        case .month: days = 31
        case .year: days = 366
        }
        if let days {
            let reference = pin.capturedAt ?? pin.createdAt
            if reference < now.addingTimeInterval(-days * 86_400) { return false }
        }
        return true
    }

    /// The words search matches for one pin, weighted (built once per pin per search).
    nonisolated private static func searchWords(for pin: Pin, boardNames: [UUID: String]) -> [(word: String, weight: Double, semantic: Bool)] {
        var words: [(word: String, weight: Double, semantic: Bool)] = []
        for tag in pin.tags {
            let t = tag.lowercased()
            words.append((word: t, weight: 1.0, semantic: true))
            for part in SemanticMatcher.tokenize(t) where part != t {
                words.append((word: part, weight: 0.95, semantic: true))
            }
        }
        for tag in pin.fileKeywords { words.append((word: tag, weight: 0.9, semantic: true)) }
        for tag in pin.aiTags {
            let weight = 0.5 + 0.5 * tag.confidence
            words.append((word: tag.label, weight: weight, semantic: true))
            for part in SemanticMatcher.tokenize(tag.label) where part != tag.label {
                words.append((word: part, weight: weight * 0.9, semantic: true))
            }
        }
        for tag in pin.colorTags { words.append((word: tag, weight: 0.7, semantic: false)) }
        for tag in pin.ocrTags { words.append((word: tag, weight: 0.85, semantic: true)) }
        for word in SemanticMatcher.tokenize(pin.title) { words.append((word: word, weight: 0.95, semantic: true)) }
        // (A video's transcript sits in its note: like a link's article below, only the start of a long one
        // is matched word by word — the person's own note comes first in it, so that is always in.)
        let note = pin.hasSpokenWords ? String(pin.note.prefix(TranscriptText.searchLimit)) : pin.note
        for word in SemanticMatcher.tokenize(note) { words.append((word: word, weight: 0.85, semantic: true)) }
        // (A link's article text is capped: matching every word of a long article against every
        // search term would make search slow; the exact-phrase check below still sees all of it.)
        for word in SemanticMatcher.tokenize(pin.isLink ? LibraryStore.linkText(of: pin) : pin.textBody) { words.append((word: word, weight: 0.85, semantic: true)) }
        for word in SemanticMatcher.tokenize(pin.aiDescription) { words.append((word: word, weight: 0.8, semantic: true)) }
        if let host = pin.linkHost { words.append((word: host, weight: 0.9, semantic: false)) }
        for boardID in pin.boardIDs {
            if let name = boardNames[boardID] {
                for word in SemanticMatcher.tokenize(name) { words.append((word: word, weight: 0.8, semantic: true)) }
            }
        }
        for word in SemanticMatcher.tokenize(pin.ocrText) { words.append((word: word, weight: 0.7, semantic: false)) }
        return words
    }

    nonisolated static func performSearch(query: String,
                                          extraTerms: [String],
                                          pins: [Pin],
                                          boardNames: [UUID: String],
                                          filters: SearchFilters,
                                          matcher: SemanticMatcher,
                                          byMeaning: Bool = true) -> [SearchHit] {
        let now = Date()
        let candidates = pins.filter { passesFilters($0, filters, now: now) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            // Filters alone: newest first (or as asked).
            guard filters.isActive else { return [] }
            let order = filters.sort == .relevance ? .newest : filters.sort
            return LibraryStore.sorted(candidates, by: order).map { SearchHit(pin: $0, score: 1, matches: []) }
        }
        var terms = SemanticMatcher.queryTerms(trimmed)
        if terms.isEmpty { terms = SemanticMatcher.tokenize(trimmed) }
        guard !terms.isEmpty else { return [] }
        let extras = extraTerms
            .map { SemanticMatcher.lemmatize($0.lowercased()) }
            .filter { !terms.contains($0) && !$0.isEmpty }

        var hits: [SearchHit] = []
        for pin in candidates {
            let words = searchWords(for: pin, boardNames: boardNames)
            var total = 0.0
            var matched: [String] = []
            for term in terms {
                var best = 0.0
                var bestWord = ""
                for entry in words {
                    let s = matcher.similarity(term, entry.word, allowSemantic: entry.semantic && byMeaning) * entry.weight
                    if s > best {
                        best = s
                        bestWord = entry.word
                    }
                }
                if best >= 0.3 {
                    total += best
                    if !matched.contains(bestWord) { matched.append(bestWord) }
                }
            }
            var score = total / Double(terms.count)

            // Related words from Apple Intelligence can lift a pin a little.
            if !extras.isEmpty {
                var extraBest = 0.0
                var extraWord = ""
                for extra in extras {
                    for entry in words where entry.semantic {
                        let s = matcher.similarity(extra, entry.word) * entry.weight
                        if s > extraBest {
                            extraBest = s
                            extraWord = entry.word
                        }
                    }
                }
                if extraBest >= 0.6 {
                    score = max(score, extraBest * 0.55)
                    if !matched.contains(extraWord) { matched.append(extraWord) }
                }
            }

            // Exact phrase anywhere in the pin's text is a strong match.
            let haystack = [pin.title, pin.note, pin.textBody, pin.ocrText, pin.aiDescription, pin.linkURL ?? "", pin.tags.joined(separator: " ")]
                .joined(separator: " ").lowercased()
            if trimmed.count >= 3, haystack.contains(trimmed) {
                score = max(score, 0.95)
                if !matched.contains(trimmed) { matched.insert(trimmed, at: 0) }
            }
            if score >= 0.3 {
                hits.append(SearchHit(pin: pin, score: score, matches: matched))
            }
        }
        switch filters.sort {
        case .relevance: return hits.sorted { $0.score > $1.score }
        case .newest: return hits.sorted { $0.pin.createdAt > $1.pin.createdAt }
        case .oldest: return hits.sorted { $0.pin.createdAt < $1.pin.createdAt }
        }
    }
}
