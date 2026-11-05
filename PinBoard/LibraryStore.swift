//
//  LibraryStore.swift  —  PinBoard
//
//  All data (pins, boards, smart boards) for the current profile. This file is the core of the
//  store: its stored state, `init` and switching profile, saving and loading (with backups), the
//  indexes and the lookups every screen uses, and the hooks the sync engine uses.
//  The rest of the store is split by topic into extensions of `LibraryStore`, one file each:
//    LibraryPins.swift      – editing pins, tags, which boards a pin is on, hiding single pins
//    LibraryBoards.swift    – boards, smart boards, "Start here", the back-up reminder, board suggestions
//    LibraryImports.swift   – importing (read and check, then commit), text/link/video pins, highlights
//    LibraryUpkeep.swift    – recently deleted, orphan sweep, duplicates, video upkeep, pictures, look-alikes
//    LibraryAnalysis.swift  – the background AI queue, re-running the AI's names, natural-language search
//    LibraryTypes.swift     – the small types around the store (`PendingImport`, `LibraryWriter`, …)
//  Saves are written in order by `LibraryWriter`; work that waits (imports, syncs,
//  the AI) drops its result when the profile was switched meanwhile (`isCurrentProfile`),
//  and a prepared import remembers its profile (`PendingImport.profileID`). A restore
//  first keeps the list it replaces ("Before the last restore").
//

import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

@MainActor
final class LibraryStore: ObservableObject {

    /// Every pin, including the ones in "Recently deleted".
    @Published var pins: [Pin] = [] {   // (not private: used by LibraryPins.swift, LibraryImports.swift and LibraryUpkeep.swift)
        didSet { pinsChanged() }
    }
    @Published var boards: [Board] = [] {   // (not private: used by LibraryBoards.swift and LibraryUpkeep.swift)
        didSet { boardsChanged() }
    }
    @Published var smartBoards: [SmartBoard] = []   // (not private: used by LibraryBoards.swift and LibraryUpkeep.swift)
    /// The AI's tagging progress over both sides of the library (see `analysisProgress(for:)`).
    @Published var analysisProgress: AnalysisProgress? = nil
    /// The same, counted on one side only (nil = nothing of that side is waiting). The Pins tab
    /// shows the normal side's, so a hidden pin being tagged never shows or counts there.
    @Published var visibleAnalysisProgress: AnalysisProgress? = nil   // (not private: used by LibraryAnalysis.swift)
    @Published var hiddenAnalysisProgress: AnalysisProgress? = nil   // (not private: used by LibraryAnalysis.swift)
    /// Imports, folder imports and iCloud syncs going on now (see `isBusyWithLibraryWork`).
    @Published private(set) var libraryWorkCount = 0
    /// What an import (or a web download, a link preview, "Sort into boards") is doing now, e.g.
    /// "Importing 3 of 10…". Set only through `setImportStatus`, together with its side.
    @Published private(set) var importStatus: String? = nil
    /// The side of the library the work that `importStatus` describes is on (the Pins tab's pill
    /// shows only the normal side's).
    @Published private(set) var importStatusScope: PinScope = .visible
    @Published var cloudLastError: String? = nil
    /// "AI sorting → naming": how far the run has got (nil while no run is going).
    @Published var namingProgress: AnalysisProgress? = nil   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    /// The side of the library being renamed (nil while no run is going).
    @Published var namingScope: PinScope? = nil   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    /// "Sort into boards" is going (one at a time).
    @Published var isAutoSorting = false   // (not private: used by LibraryBoards.swift)
    /// The last naming run of each side that renamed something (at most one per side), for Undo.
    @Published var lastNamingRuns: [NamingRun] = []   // (not private: used by LibraryAnalysis.swift)
    /// Pins whose picture or video file is missing on disk (found by the sweep at launch).
    @Published var missingFileIDs: Set<UUID> = []   // (not private: used by LibraryUpkeep.swift)
    /// "Convert existing videos…" (Settings › iCloud & storage, MediaStorage.swift): the normal side's
    /// videos done and to do while it runs (nil otherwise). It converts the normal side only:
    /// Settings is the normal side (hidden videos have their own command in Hidden's ⋯ menu).
    @Published private(set) var conversionProgress: AnalysisProgress? = nil
    /// How far the normal video being converted now has got (0…100).
    @Published private(set) var conversionPercent = 0
    /// Why the last conversion stopped early (Settings shows it until the next one; nil: it didn't).
    @Published private(set) var conversionNote: String? = nil
    /// The conversion running now, kept so "Stop" can end it (see `startConvertingVideos`).
    var conversionTask: Task<Void, Never>? = nil
    /// Hidden's ⋯ › "Convert videos to 1080p…": the hidden videos done and to do while it runs (nil
    /// otherwise). Only the Hidden section shows it — its row "Converting 2 of 5 (45%)" with Stop,
    /// and the ⋯ item reading "Stop converting"; Settings and the normal side never do.
    @Published private(set) var hiddenConversionProgress: AnalysisProgress? = nil
    /// How far the hidden video being converted now has got (0…100).
    @Published private(set) var hiddenConversionPercent = 0
    /// Hidden's own run is going on now.
    var isConvertingHiddenVideos: Bool { hiddenConversionProgress != nil }
    /// That run, kept so "Stop converting" can end it; its summary is the Hidden section's message.
    var hiddenConversionTask: Task<ConversionSummary, Never>? = nil
    /// Videos being converted right now (by either side's run: a video that changed sides while
    /// being converted is never converted twice at once).
    var videosBeingConverted: Set<UUID> = []
    /// The conversion run going on each side now (only one per side: new videos from a later
    /// import join it — see `startConvertingNewVideos`).
    var conversionRuns: [PinScope: ConversionRun] = [:]
    /// New videos that couldn't join the run going on, per side: they start when it has ended.
    var laterConversions: [PinScope: LaterConversion] = [:]
    /// Videos whose new poster still has to be written into their file as artwork, one at a
    /// time in the background (VideoPosters.swift).
    var artworkQueue: [UUID] = []
    var artworkTask: Task<Void, Never>? = nil
    /// Videos whose artwork is being written into their file right now (a conversion waits for it).
    var artworkWriting: Set<UUID> = []
    /// Videos that were asked to have a poster written while a conversion had their file: it is
    /// written when the conversion has ended (see `convertVideo`, `writeArtwork`).
    var artworkWaiting: Set<UUID> = []
    /// Goes up on every change to pins, boards or smart boards (views use it to refresh derived lists).
    @Published var contentVersion = 0   // (not private: used by LibraryBoards.swift)
    /// Pins added since the last export (for the back-up reminder).
    @Published var pinsAddedSinceExport = 0   // (not private: used by LibraryBoards.swift)
    @Published var lastExportAt: Date? = nil   // (not private: used by LibraryBoards.swift)
    @Published var lastSyncAt: Date? = nil
    @Published var syncStatus: String? = nil

    static let trashRetentionDays = 30
    static let duplicateHashDistance = 6
    static let backupNudgeThreshold = 50

    private(set) var location: LibraryLocation
    /// The profile whose library this is. Published, so a window can notice a switch made in
    /// another window (ImportFlow drops a question about the old library's batch).
    @Published private(set) var profileID: UUID
    var baseURL: URL { location.root }
    var imagesURL: URL { location.images }
    var thumbsURL: URL { location.thumbs }
    var printsURL: URL { location.prints }
    var exifURL: URL { location.exif }
    var videosURL: URL { location.videos }

    /// Pins erased for good (id → when), kept so a synced copy erases them too.
    var erased: [UUID: Date] = [:]   // (not private: used by LibraryBoards.swift, LibraryImports.swift and LibraryUpkeep.swift)

    let thumbCache = NSCache<NSString, UIImage>()   // (not private: used by LibraryPins.swift, LibraryImports.swift and LibraryUpkeep.swift)
    let fullCache = NSCache<NSString, UIImage>()           // a few full-size pictures, for smooth swiping   // (not private: used by LibraryPins.swift, LibraryImports.swift and LibraryUpkeep.swift)
    var printCache: [UUID: VNFeaturePrintObservation] = [:]   // (not private: used by LibraryPins.swift, LibraryImports.swift, LibraryUpkeep.swift and LibraryAnalysis.swift)
    var printsMissing: Set<UUID> = []                      // prints that could not be read (no retry per call)   // (not private: used by LibraryImports.swift, LibraryUpkeep.swift and LibraryAnalysis.swift)
    var saveTask: Task<Void, Never>? = nil         // (not private: these four are used by LibrarySaving.swift)
    var unsavedSince: Date? = nil                  // the oldest change no save has started for yet
    var analysisTask: Task<Void, Never>? = nil   // (not private: used by LibraryImports.swift, LibraryUpkeep.swift and LibraryAnalysis.swift)
    var saveGeneration = 0
    var savedGeneration = 0
    let writer = LibraryWriter()                   // every save is written through it, in order
    var onSaved: (() -> Void)? = nil                       // the sync engine listens here

    // Indexes, rebuilt lazily after a change.
    private var indexDirty = true
    var indexByID: [UUID: Int] = [:]   // (not private: used by LibraryPins.swift)
    private var liveCache: [Pin]? = nil
    private var membershipCache: [UUID: Set<UUID>]? = nil  // board id → live pin ids (direct membership)
    var boardIndex: [UUID: Int] = [:]   // (not private: used by LibraryBoards.swift)
    private var childrenCache: [UUID?: [Board]] = [:]
    private var descendantsCache: [UUID: [UUID]] = [:]
    var secretCache: Set<UUID> = []                        // boards that are secret themselves or inside a secret board   // (not private: used by LibraryPins.swift, LibraryBoards.swift, LibraryImports.swift, LibraryUpkeep.swift and LibraryAnalysis.swift)
    private var keptOutCache: Set<UUID> = []               // boards that keep their pins out of All, and every board inside them
    private var scopeCache: ScopeSplit? = nil              // live pins split into visible / hidden
    var audioChecks: Set<UUID> = []                        // video pins whose sound track is being looked at   // (not private: used by LibraryUpkeep.swift)
    var duplicateRefreshTask: Task<Void, Never>? = nil           // a pending re-check after pins changed sides   // (not private: used by LibraryPins.swift)
    var namingTask: Task<Void, Never>? = nil               // "AI sorting → naming"   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    var activeNamingRun: NamingRun? = nil                  // the run going on now (what it has done so far)   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    var namingRunRecorded = false                          // …and it is kept for "Undo last AI naming" when it ends   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    var namingOutcomes: [UUID: NamingRun] = [:]            // runs that ended, until `namingOutcome(of:)` tells them   // (not private: used by LibraryAnalysis.swift)
    /// Pins whose picture the AI queue is looking at right now: a naming request waits for that
    /// look instead of taking a second one (see `lookFirst`).
    var analysingNow: Set<UUID> = []   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    /// Pins whose picture a naming request is looking at right now (`lookBeforeNaming`): the queue
    /// leaves them alone meanwhile.
    var lookingBeforeNaming: Set<UUID> = []   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    /// Looks a naming request took while the AI queue was running (true = a hidden pin's): the
    /// queue counts them as done in its progress (see `runAnalysis`).
    var looksOutsideQueue: [Bool] = []   // (not private: used by LibraryUpkeep.swift and LibraryAnalysis.swift)
    var pageKeyCache: [UUID: PageKeyEntry] = [:]           // link pin → its page key (see `cachedPageKey`)   // (not private: used by LibraryUpkeep.swift)
    var maintenanceTask: Task<Void, Never>? = nil          // video upkeep (length, sound, black posters)   // (not private: used by LibraryUpkeep.swift)
    var lastAddedCache: [UUID: Date?] = [:]                // board id → lastAddedDate (tiles ask every render)   // (not private: used by LibraryBoards.swift)
    var lastEditedCache: [UUID: Date] = [:]                // board id → lastEditedDate   // (not private: used by LibraryBoards.swift)
    var boardStampDepth = 0                                // > 0 while an import collects board stamps   // (not private: used by LibraryBoards.swift)
    var pendingEditedBoards: Set<UUID> = []   // (not private: used by LibraryBoards.swift)
    var pendingAddedBoards: Set<UUID> = []   // (not private: used by LibraryBoards.swift)
    /// Folders a folder import is reading, by plan id (see Export.swift): access to each
    /// stops exactly once, on commit or cancel.
    var folderImportAccess: [UUID: URL] = [:]
    /// Ids an import is putting files under right now, before its pin exists (a video can take
    /// minutes to convert first): no other import takes one of them meanwhile (see `reserveID`).
    var reservedIDs: Set<UUID> = []   // (not private: used by LibraryImports.swift)

    // (state used by VideoTranscripts.swift — the transcription run. It is kept here because an extension
    //  cannot hold stored properties; its hooks are in LibraryImports.swift.)
    /// What Settings › Videos shows of the speech recogniser's work while a run is at work
    /// ("Transcribing 2 of 5…"; nil: nothing is being written down right now). It only ever means
    /// "a run is at work" — a line a run leaves when it ends is in `transcriptionClosing`.
    @Published var transcriptionStatus: String? = nil
    /// What the last run left on purpose when it ended (a language the device cannot read, the
    /// language files still to download, some videos that could not be listened to…): shown under the
    /// switch until the next run replaces or clears it (or the next switch of profile). Separate from
    /// `transcriptionStatus`, so Settings' "Transcribe existing videos" is dimmed only while a run is
    /// going, never by a line that asks the person to try again.
    @Published var transcriptionClosing: String? = nil
    /// The background run that listens to videos (nil: none is going and none waits for its turn).
    var transcriptionTask: Task<Void, Never>? = nil
    /// The run is past its start-up wait and at work (an automatic start that still waits for its
    /// delay is not: the Settings button may then take its place).
    var transcriptionIsListening = false
    /// The words this run put on the Pins tab's pill, so it takes down only its own words.
    var transcriptionPill: String? = nil
    /// "Transcribing 2 of 5…" as the status shows it while a normal video is being listened to (the
    /// status goes back to it when the language files have come down).
    var transcriptionLine: String? = nil
    /// The run was started by the Settings button: it also tries again the videos listened to before
    /// that gave no words, and it shows its count on the pill. A button pressed while an automatic
    /// run is going turns this on for the rest of that run.
    var transcriptionByHand = false
    /// Speech recognition is not allowed to the app, or needs a newer system than this one (the older
    /// recogniser, no permission or no usage description): no automatic start tries again until the
    /// next launch or the Settings button.
    var transcriptionPaused = false
    /// How often a waiting run looks whether the AI and the conversions have gone quiet (seconds;
    /// the tests make it short).
    var transcriptionPollSeconds = 2.0
    /// How long "No videos are waiting…" stays in the status (seconds; the tests make it short).
    var transcriptionNoticeSeconds = 4.0
    /// The rest the run takes between two videos, so a long list never keeps the processor at full
    /// power without a break (seconds; the tests make it short).
    var transcriptionBreathSeconds = 0.25
    /// What listens to a video: Apple's recogniser. The real one cannot run without a device, so
    /// the tests put a fake in its place (`SpeechRecogniser`, VideoTranscripts.swift).
    var speechRecogniser: SpeechRecogniser = SpeechTranscription.standard

    /// Live pins sorted into the normal library and the Hidden section (rebuilt after a change).
    struct ScopeSplit {   // (not private: used by LibraryPins.swift and LibraryUpkeep.swift)
        var visible: [Pin]
        var hidden: [Pin]
        var hiddenIDs: Set<UUID>
    }

    /// A link pin's page key and the address it was worked out from.
    struct PageKeyEntry {   // (not private: used by LibraryUpkeep.swift)
        var link: String
        var key: String
    }

    init(location: LibraryLocation, profileID: UUID) {
        self.location = location
        self.profileID = profileID
        thumbCache.countLimit = 300
        fullCache.countLimit = 8
        location.createFolders()
        load()
        finishLoading()
    }

    /// Switches to another profile's library (used by Settings → Profiles). Work still under way
    /// for the old library (an import, a sync, the AI) notices the switch and drops its result
    /// (see `isCurrentProfile`); Settings offers no switch while `isBusyWithLibraryWork`.
    func switchTo(location newLocation: LibraryLocation, profileID newID: UUID) {
        stopNaming()   // a run of the old library is recorded under that library
        // Every conversion run is told to stop first, so a video made right after a switch there and
        // back never joins a run that is only winding down (it would be dropped with it).
        for run in conversionRuns.values { run.stop() }
        conversionTask?.cancel()   // "Convert existing videos…" belongs to the old library
        hiddenConversionTask?.cancel()   // (and so does Hidden's, and what an import left to convert)
        laterConversions = [:]
        cancelArtworkWriting()   // (posters' artwork being written into the old library's video files)
        maintenanceTask?.cancel()
        maintenanceTask = nil
        cancelTranscription()   // (listening to the old library's videos, and the line its last run left)
        analysisTask?.cancel()
        analysisTask = nil
        clearAnalysisProgress()
        duplicateRefreshTask?.cancel()
        duplicateRefreshTask = nil
        saveNowSynchronously()
        location = newLocation
        profileID = newID
        newLocation.createFolders()
        thumbCache.removeAllObjects()
        fullCache.removeAllObjects()
        printCache = [:]
        printsMissing = []
        missingFileIDs = []
        analysingNow = []
        lookingBeforeNaming = []
        looksOutsideQueue = []
        pageKeyCache = [:]
        // Board stamps an import of the old library collected are about its boards, not these.
        pendingEditedBoards = []
        pendingAddedBoards = []
        load()
        finishLoading()
    }

    /// Whether `id` is still the profile in use. Work that waits (an import, a sync, the AI)
    /// remembers the profile it started in and asks this after each wait, before it writes: after
    /// a switch its result belongs to the other library, so it is dropped — otherwise it would land
    /// in this one, filed on that library's boards (and a pin hidden there would show here).
    func isCurrentProfile(_ id: UUID) -> Bool {
        profileID == id
    }

    /// True while an import (reading or saving), a folder import or an iCloud sync is going on.
    /// Settings keeps the profile from being switched meanwhile: that work belongs to this library.
    var isBusyWithLibraryWork: Bool {
        libraryWorkCount > 0
    }

    /// Imports and syncs call these around their work (always in pairs).
    func beginLibraryWork() {
        libraryWorkCount += 1
    }

    func endLibraryWork() {
        libraryWorkCount = max(0, libraryWorkCount - 1)
    }

    /// Sets `importStatus` together with the side of the library the work is on — always both at
    /// once, so a hidden import's "Importing 3 of 10…" never shows as the normal side's (the Pins
    /// tab's pill reads the side). `nil` clears it.
    func setImportStatus(_ text: String?, scope: PinScope) {
        importStatusScope = scope
        importStatus = text
    }

    /// Sets what Settings shows of "Convert existing videos…" (MediaStorage.swift): the normal
    /// side's count (nil: none is running), the current video's percent, and why it stopped early.
    func setConversionProgress(_ progress: AnalysisProgress?, percent: Int, note: String?) {
        conversionProgress = progress
        conversionPercent = percent
        conversionNote = note
    }

    /// Sets what the Hidden section shows of its own "Convert videos…" run (MediaStorage.swift): the
    /// hidden side's count (nil: none is running) and the current video's percent. Only the Hidden
    /// section reads these.
    func setHiddenConversionProgress(_ progress: AnalysisProgress?, percent: Int) {
        hiddenConversionProgress = progress
        hiddenConversionPercent = percent
    }

    /// Temporary files of a conversion or a share are cleared once per launch.
    private static var clearedTemporaryFiles = false

    private func finishLoading() {
        loadNudgeCounters()
        loadNamingRuns()
        purgeOldDeleted()
        pruneTombstones()
        startAnalysisIfNeeded()
        Task { await sweepOrphans() }
        startVideoMaintenanceIfNeeded()
        startTranscribingIfNeeded()   // (a few seconds after launch; what is said in videos is written down in the background)
        if !LibraryStore.clearedTemporaryFiles {
            LibraryStore.clearedTemporaryFiles = true
            Task.detached(priority: .utility) {
                VideoCompressor.removeLeftovers()
                OriginalsFolder.removeTemporaryCopies()
                // A picture a "Search on the web" hand-over to Files left behind when the app was closed under
                // the picker (a hidden pin's too): swept now, not only at the next hand-over. A minute, not an
                // hour, so what the last launch left is gone while a hand-over of this launch never loses its file.
                WebSearchHandoff.removeOldFiles(olderThan: 60)
            }
        }
        // Originals iCloud has in full leave this device; erased pins' originals go (MediaStorage.swift).
        scheduleOriginalsUpkeep(after: 30)
    }

    // MARK: Persistence

    private func load() {
        pins = []
        boards = []
        smartBoards = []
        erased = [:]
        guard let data = try? Data(contentsOf: location.library) else { return }
        if let document = LibraryStore.decodeDocument(data) {
            apply(document)
        } else {
            // Never overwrite a file we couldn't read: keep it next to the new one.
            let backup = location.root.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: location.library, to: backup)
            // A backup may still be fine.
            for candidate in [location.previousBackup, location.dailyBackup] {
                if let backupData = try? Data(contentsOf: candidate), let document = LibraryStore.decodeDocument(backupData) {
                    apply(document)
                    scheduleSave()
                    break
                }
            }
        }
    }

    private func apply(_ document: LibraryDocument) {
        pins = document.pins
        boards = document.boards
        smartBoards = document.smartBoards.sorted { $0.sortIndex < $1.sortIndex }
        erased = document.erased
        // A pin on a board and on one inside it keeps only the inner one (see `addPins`): this
        // cleans up a library made before that rule, and what a sync brings.
        tidyNestedMemberships()
    }

    /// Dates are ISO text; very old files stored numbers. Each date field reads either form by
    /// itself (see `StoredDate` in Models.swift) — a whole-file retry could never catch them, since
    /// a field that fails is simply left out instead of failing the file. A number is read as
    /// counted from 2001 unless that lands over a year in the future (then from 1970): so a
    /// 1970-based number naming a date before about 1997 is misread — left so on purpose, see
    /// `StoredDate.date(fromNumber:)`.
    nonisolated static func decodeDocument(_ data: Data) -> LibraryDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryDocument.self, from: data)
    }

    nonisolated static func encodeDocument(_ document: LibraryDocument, pretty: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try? encoder.encode(document)
    }

    var document: LibraryDocument {
        LibraryDocument(pins: pins, boards: boards, smartBoards: smartBoards, erased: erased)
    }

    /// The library as JSON for an export: live pins only, and without the
    /// hidden boards, hidden pins and hidden smart boards when asked.
    func exportJSON(includeHidden: Bool) -> Data? {
        var exported = document
        exported.erased = [:]
        exported.pins = exportPins(includeHidden: includeHidden)
        if !includeHidden {
            let secret = secretCache
            let kept = Set(exported.pins.map { $0.id })
            exported.boards = exported.boards.filter { !secret.contains($0.id) }
            for index in exported.boards.indices {
                if let cover = exported.boards[index].coverPinID, !kept.contains(cover) { exported.boards[index].coverPinID = nil }
            }
            exported.smartBoards = exported.smartBoards.filter { board in
                if board.isHidden { return false }
                guard let scope = board.filters.boardID else { return true }
                return !secret.contains(scope)
            }
            for index in exported.smartBoards.indices {
                exported.smartBoards[index].excludedPinIDs.removeAll { !kept.contains($0) }
            }
        }
        return LibraryStore.encodeDocument(exported, pretty: true)
    }

    /// The live pins an export writes out. Without hidden content: no hidden pins,
    /// no hidden board ids, nothing remembered from hiding, and no links to left-out pins.
    func exportPins(includeHidden: Bool) -> [Pin] {
        guard !includeHidden else { return livePins }
        let secret = secretCache
        let shown = visiblePins
        let kept = Set(shown.map { $0.id })
        return shown.map { pin in
            var copy = pin
            copy.boardIDs.removeAll { secret.contains($0) }
            copy.isHidden = false
            copy.boardsBeforeHiding = []
            if let twin = copy.duplicateOfID, !kept.contains(twin) { copy.duplicateOfID = nil }
            if let article = copy.quotedFromID, !kept.contains(article) { copy.quotedFromID = nil }   // (a quote of a hidden article: not even its id)
            copy.notDuplicateOf.removeAll { !kept.contains($0) }
            return copy
        }
    }

    /// Board ids that are hidden (secret or inside a secret board).
    var hiddenBoardIDs: Set<UUID> { secretCache }

    /// Backups that can be restored, newest first (reads and decodes whole
    /// library files — call it off the main thread). "Before the last restore" is the list as it
    /// was when a copy was last restored (see `restore`). Copies saved in the same second (the
    /// file keeps whole seconds) stay in the order below: that one first, as it is made last.
    nonisolated static func backups(at location: LibraryLocation) -> [LibraryBackup] {
        var result: [LibraryBackup] = []
        let candidates: [(URL, String)] = [(location.beforeRestoreBackup, "Before the last restore"),
                                           (location.previousBackup, "Earlier today"),
                                           (location.dailyBackup, "Daily copy")]
        for (url, label) in candidates {
            guard let data = try? Data(contentsOf: url), let document = LibraryStore.decodeDocument(data) else { continue }
            result.append(LibraryBackup(url: url, label: label, savedAt: document.savedAt, pinCount: normalPinCount(of: document)))
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: location.root, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("library-unreadable-") {
                if let data = try? Data(contentsOf: url), let document = LibraryStore.decodeDocument(data) {
                    result.append(LibraryBackup(url: url, label: "Set aside (unreadable at the time)", savedAt: document.savedAt, pinCount: normalPinCount(of: document)))
                }
            }
        }
        // Newest first; on a tie, the order above (a plain sort may swap equal ones).
        let numbered = Array(result.enumerated())
        let ordered = numbered.sorted { (a: (offset: Int, element: LibraryBackup), b: (offset: Int, element: LibraryBackup)) -> Bool in
            if a.element.savedAt != b.element.savedAt { return a.element.savedAt > b.element.savedAt }
            return a.offset < b.offset
        }
        return ordered.map { (entry: (offset: Int, element: LibraryBackup)) -> LibraryBackup in entry.element }
    }

    /// A backup's pins as Settings counts them: live normal pins only (hidden ones are never counted there).
    nonisolated private static func normalPinCount(of document: LibraryDocument) -> Int {
        let secret = LibraryStore.secretBoardIDs(in: document.boards)
        var count = 0
        for pin in document.pins where !pin.isDeleted && !LibraryStore.isHidden(pin, secretBoards: secret) { count += 1 }
        return count
    }

    /// Replaces the library with a backup (files on disk are untouched: the pictures of pins added
    /// since the copy stay, see `sweepOrphans`).
    ///
    /// The list as it is now is kept first, as "Before the last restore" (library.before-restore.json):
    /// "Earlier today" is replaced only once it is ten minutes old, so right after it was made it
    /// may be the very copy being restored — without this, the current list would be kept nowhere.
    /// It is written through the writer, under its lock (never in the middle of a save). If it
    /// can't be written, nothing is restored (false). Restoring "Before the last restore" itself
    /// swaps the two: the list it replaces becomes the new "Before the last restore".
    func restore(_ backup: LibraryBackup) -> Bool {
        guard let data = try? Data(contentsOf: backup.url), let document = LibraryStore.decodeDocument(data) else { return false }
        guard let current = LibraryStore.encodeDocument(self.document),
              writer.keepCopyBeforeRestore(current, at: location) else { return false }
        analysisTask?.cancel()
        analysisTask = nil
        clearAnalysisProgress()
        apply(document)
        saveNow()   // a bulk change: written at once, not after a delay (see LibrarySaving.swift)
        startAnalysisIfNeeded()
        Task { await sweepOrphans() }
        startVideoMaintenanceIfNeeded()
        startTranscribingIfNeeded()
        return true
    }

    /// Merged data from another device (the sync engine hands it over). `profile`: the library
    /// the sync started in — a result that arrives after a switch to another profile is dropped.
    /// `pictures`: newer pictures the sync staged next to the pins' files; each is put in place
    /// here only while the pin's picture is still the one the sync saw (`placeSyncedPictures`).
    /// Whatever isn't put in place is thrown away.
    func applySynced(_ document: LibraryDocument, profile: UUID? = nil, pictures: [CloudSync.StagedPicture] = []) {
        if let profile, !isCurrentProfile(profile) {
            CloudSync.discard(pictures)   // (staged in the other library's folders)
            return
        }
        analysisTask?.cancel()
        analysisTask = nil
        clearAnalysisProgress()
        let revisions = pictureRevisions()
        var synced = document
        let placed = placeSyncedPictures(pictures, in: &synced)
        apply(synced)
        forgetCachedPictures(changedSince: revisions, placed: placed)
        missingFileIDs.subtract(placed)
        lastSyncAt = Date()
        saveNow()   // a sync's merge is a bulk change: written at once (see LibrarySaving.swift)
        startAnalysisIfNeeded()
        startVideoMaintenanceIfNeeded()
        startTranscribingIfNeeded()   // (a video that came with the sync and has no transcript yet)
    }

    /// Puts the pictures a sync brought (see `CloudSync.StagedPicture`) in place, and has
    /// `document` describe them (`Pin.takePictureDetails`) — each only while the pin's picture
    /// here is still the one the sync saw (the same `pictureRevision`: the sync runs in the
    /// background for up to a minute or so). A picture turned, cropped or refreshed here meanwhile
    /// stays: the one brought is thrown away, and this device's revision goes above it, so its own
    /// picture wins the next sync. Returns the pins whose picture files changed.
    private func placeSyncedPictures(_ pictures: [CloudSync.StagedPicture], in document: inout LibraryDocument) -> Set<UUID> {
        guard !pictures.isEmpty else { return [] }
        var indexByPin: [UUID: Int] = [:]
        for (index, pin) in document.pins.enumerated() where indexByPin[pin.id] == nil { indexByPin[pin.id] = index }
        var placed: Set<UUID> = []
        for staged in pictures {
            let id = staged.picture.id
            guard let index = indexByPin[id] else {
                CloudSync.discard([staged])   // the pin is gone here
                continue
            }
            let current = self.pin(id)?.pictureRevision
            guard current == staged.seenRevision else {
                CloudSync.discard([staged])
                // Changed here meanwhile (a higher revision: turned, cropped, refreshed): that picture
                // stays, and its revision goes above the one brought. (A lower one — a backup restored
                // meanwhile — just waits for the next sync, which brings the picture again.)
                let brought = staged.picture.pictureRevision
                if let current, current > staged.seenRevision, document.pins[index].pictureRevision <= brought {
                    document.pins[index].pictureRevision = brought + 1
                }
                continue
            }
            guard let fingerprint = placeFiles(of: staged) else { continue }
            var updated = document.pins[index]
            updated.takePictureDetails(from: staged.picture)
            if updated.hasFeaturePrint && !fingerprint {
                // Its fingerprint didn't come: made again here (the AI looks at the picture), so
                // the pin doesn't drop out of "More like this".
                updated.hasFeaturePrint = false
                updated.needsAnalysis = true
            }
            document.pins[index] = updated
            placed.insert(id)
        }
        return placed
    }

    /// Puts one staged picture's files in the place of the pin's own, each in one step
    /// (`moveIntoPlace`: there is never a moment without a picture). The old picture's thumbnail
    /// and fingerprint never stay with the new picture: a new one that didn't come leaves none. A
    /// staged "no picture" (a link preview dropped on the other device) removes the pin's preview
    /// files. nil: the picture couldn't be put in place (the old files and details stay; the next
    /// sync tries again). Otherwise whether the new fingerprint is in place.
    private func placeFiles(of staged: CloudSync.StagedPicture) -> Bool? {
        let imageURL = location.images.appendingPathComponent(staged.picture.imageFileName)
        let thumbURL = location.thumbs.appendingPathComponent(staged.picture.thumbFileName)
        let printURL = location.prints.appendingPathComponent(staged.picture.printFileName)
        guard let image = staged.image else {
            CloudSync.removePictureFiles(of: staged.picture, in: location)
            return false
        }
        guard LibraryStore.moveIntoPlace(image, imageURL) else {
            CloudSync.discard([staged])
            return nil
        }
        let thumbnail = staged.thumbnail.map { (file: URL) -> Bool in LibraryStore.moveIntoPlace(file, thumbURL) } ?? false
        if !thumbnail { try? FileManager.default.removeItem(at: thumbURL) }
        let fingerprint = staged.fingerprint.map { (file: URL) -> Bool in LibraryStore.moveIntoPlace(file, printURL) } ?? false
        if !fingerprint { try? FileManager.default.removeItem(at: printURL) }
        CloudSync.discard([staged])   // (whatever couldn't be moved)
        return fingerprint
    }

    /// Each pin's picture revision now (to tell afterwards which pictures changed).
    private func pictureRevisions() -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for pin in pins { result[pin.id] = pin.pictureRevision }
        return result
    }

    /// Forgets the pictures and fingerprints kept in memory for pins whose picture changed since
    /// `revisions`, and for the pins whose files a sync just put in place (`placed`) — say one
    /// turned or cropped on another device (see `CloudSync`): the views, which load a picture again
    /// when its revision changes, and "More like this" then read the new files instead of the old copies.
    func forgetCachedPictures(changedSince revisions: [UUID: Int], placed: Set<UUID> = []) {
        for pin in pins {
            let changed = revisions[pin.id].map { (old: Int) -> Bool in old != pin.pictureRevision } ?? false
            guard changed || placed.contains(pin.id) else { continue }
            thumbCache.removeObject(forKey: pin.id.uuidString as NSString)
            fullCache.removeObject(forKey: pin.id.uuidString as NSString)
            printCache[pin.id] = nil
            printsMissing.remove(pin.id)
        }
    }

    // MARK: Indexes

    private func pinsChanged() {
        indexDirty = true
        liveCache = nil
        membershipCache = nil
        scopeCache = nil
        lastAddedCache = [:]
        lastEditedCache = [:]
        contentVersion += 1
    }

    private func boardsChanged() {
        boardIndex = [:]
        for (index, board) in boards.enumerated() { boardIndex[board.id] = index }
        childrenCache = [:]
        descendantsCache = [:]
        secretCache = LibraryStore.secretBoardIDs(in: boards)
        keptOutCache = LibraryStore.boardIDs(in: boards, where: { (board: Board) -> Bool in board.keepsPinsOutOfAll })
        membershipCache = nil
        scopeCache = nil
        lastAddedCache = [:]
        lastEditedCache = [:]
        contentVersion += 1
    }

    func rebuildIndexIfNeeded() {   // (not private: used by LibraryPins.swift)
        guard indexDirty else { return }
        indexByID = [:]
        indexByID.reserveCapacity(pins.count)
        for (index, pin) in pins.enumerated() { indexByID[pin.id] = index }
        indexDirty = false
    }

    func index(of id: UUID) -> Int? {   // (not private: used by LibraryPins.swift and LibraryUpkeep.swift)
        rebuildIndexIfNeeded()
        return indexByID[id]
    }

    var membership: [UUID: Set<UUID>] {   // (not private: used by LibraryBoards.swift)
        if let membershipCache { return membershipCache }
        var result: [UUID: Set<UUID>] = [:]
        for pin in pins where !pin.isDeleted {
            for boardID in pin.boardIDs { result[boardID, default: []].insert(pin.id) }
        }
        membershipCache = result
        return result
    }

    // MARK: Lookups

    /// Pins that are not in "Recently deleted".
    var livePins: [Pin] {
        if let liveCache { return liveCache }
        let live = pins.filter { !$0.isDeleted }
        liveCache = live
        return live
    }

    var scopeSplit: ScopeSplit {   // (not private: used by LibraryPins.swift and LibraryUpkeep.swift)
        if let scopeCache { return scopeCache }
        let secret = secretCache
        var visible: [Pin] = []
        var hidden: [Pin] = []
        var hiddenIDs: Set<UUID> = []
        for pin in livePins {
            if LibraryStore.isHidden(pin, secretBoards: secret) {
                hidden.append(pin)
                hiddenIDs.insert(pin.id)
            } else {
                visible.append(pin)
            }
        }
        let split = ScopeSplit(visible: visible, hidden: hidden, hiddenIDs: hiddenIDs)
        scopeCache = split
        return split
    }

    /// Live pins of the normal library (not hidden).
    var visiblePins: [Pin] { scopeSplit.visible }

    /// Live pins of the Hidden section.
    var hiddenPins: [Pin] { scopeSplit.hidden }

    /// Live pins of one scope.
    func pins(scope: PinScope) -> [Pin] {
        switch scope {
        case .visible: return scopeSplit.visible
        case .hidden: return scopeSplit.hidden
        }
    }

    /// Recently deleted pins of the normal library, newest first.
    var deletedPins: [Pin] { deletedPins(scope: .visible) }

    /// Recently deleted pins of one scope, newest first (a pin deleted while hidden stays in the hidden list).
    func deletedPins(scope: PinScope) -> [Pin] {
        let secret = secretCache
        let wantHidden = scope == .hidden
        var deleted: [Pin] = []
        for pin in pins where pin.isDeleted && LibraryStore.isHidden(pin, secretBoards: secret) == wantHidden {
            deleted.append(pin)
        }
        // (Small steps with explicit types, so the compiler checks them quickly.)
        deleted.sort { (a: Pin, b: Pin) -> Bool in
            let first: Date = a.deletedAt ?? Date.distantPast
            let second: Date = b.deletedAt ?? Date.distantPast
            return first > second
        }
        return deleted
    }

    /// A pin is hidden when it was hidden on its own ("Hide pin"), or when it is on any
    /// hidden board (also when it is on a normal board too: hidden wins, and it stays filed
    /// there, out of sight, until it is no longer on a hidden board).
    /// Whether any AI may look at `pin` now: it isn't hidden, or "Include hidden pins in AI" is on.
    /// Asked at the moment the AI would look, with the pin as it is then, so a pin hidden after it
    /// was queued (or while it is looked at) is left out, and one un-hidden gets the AI normally.
    func aiMaySee(_ pin: Pin) -> Bool {
        if AppSettings.shared.aiIncludesHidden { return true }
        let now = self.pin(pin.id) ?? pin
        return !(isHidden(now) || now.isHidden)
    }

    /// Whether the cloud model may be sent anything of `pin` now: Cloud AI is on (with consent and a
    /// key), and the AI may see the pin (`aiMaySee`).
    func cloudMaySee(_ pin: Pin) -> Bool {
        AppSettings.shared.cloudActive && aiMaySee(pin)
    }

    // MARK: "Remove AI tags from hidden pins" (Settings › Privacy & Hidden)

    /// Whether `pin` holds anything the AI made: its tags, the text it read in the picture, its
    /// description or search hint, or a title only the AI wrote (never edited by the person, not
    /// from a file or page). A plain rule, so the harness tests it.
    nonisolated static func hasAIResults(_ pin: Pin) -> Bool {
        if !pin.aiTags.isEmpty || !pin.ocrTags.isEmpty || !pin.aiDescription.isEmpty { return true }
        if !pin.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let hint = pin.aiSearchHint, !hint.isEmpty { return true }
        return hasAITitle(pin)
    }

    /// A title the AI wrote and nobody changed since (an empty title is nobody's).
    nonisolated static func hasAITitle(_ pin: Pin) -> Bool {
        let named = !pin.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return named && pin.titleIsAuto && pin.lastAITitle == pin.title && !pin.titleEditedByUser
    }

    /// Takes out of `pin` what the AI made (see `hasAIResults`). The person's own tags, notes and a
    /// title they typed or that came from a file or page stay. An AI title goes back to the title
    /// from before the AI's last rename when there is one, else the pin is untitled. The pin is
    /// marked `aiSkipped`, so the AI looks again only once it may (un-hidden, or the switch on).
    nonisolated static func removeAIResults(_ pin: inout Pin) {
        pin.aiTags = []
        pin.ocrTags = []
        pin.ocrText = ""
        pin.aiDescription = ""
        pin.aiSearchHint = nil
        if hasAITitle(pin) {
            pin.undoAITitle()   // back to the title from before, when the AI renamed one
        }
        if hasAITitle(pin) {    // still the AI's (it named an untitled pin, or the one before was its too)
            pin.title = ""
            pin.titleIsAuto = false
            pin.lastAITitle = nil
            pin.titleUndo = nil
        }
        pin.aiSkipped = true
    }

    /// The live hidden pins that hold something the AI made (the button's count).
    var hiddenPinsWithAIResults: [Pin] {
        hiddenPins.filter { (pin: Pin) -> Bool in !pin.isDeleted && LibraryStore.hasAIResults(pin) }
    }

    /// Takes the AI's work out of every hidden pin of this profile (`removeAIResults`). Quick (no
    /// file is touched), so it shows no progress. Returns how many pins changed.
    @discardableResult
    func removeAIResultsFromHiddenPins() -> Int {
        let ids = Set(hiddenPinsWithAIResults.map { (pin: Pin) -> UUID in pin.id })
        guard !ids.isEmpty else { return 0 }
        modify(ids) { (pin: inout Pin) in LibraryStore.removeAIResults(&pin) }
        saveNow()   // a bulk change: written at once (see LibrarySaving.swift)
        return ids.count
    }

    /// Pins that were looked at without AI while hidden (`Pin.aiSkipped`) and that the AI may see
    /// now — un-hidden, or "Include hidden pins in AI" turned on — wait for the AI's look again.
    /// Called before the AI queue starts and after every save, so no hiding path is missed.
    func wakePinsTheAIMaySeeNow() {
        let ids = pins.filter { (pin: Pin) -> Bool in pin.aiSkipped && !pin.needsAnalysis && !pin.isDeleted && aiMaySee(pin) }
            .map { (pin: Pin) -> UUID in pin.id }
        guard !ids.isEmpty else { return }
        for id in ids {
            modifyKeepingDate(id) { (pin: inout Pin) in
                pin.needsAnalysis = true
                pin.aiSkipped = false
            }
        }
        startTranscribingIfNeeded()   // a video among them may be listened to now
    }

    func isHidden(_ pin: Pin) -> Bool {
        LibraryStore.isHidden(pin, secretBoards: secretCache)
    }

    /// The same rule on plain values (usable inside `modify` blocks and off the main thread).
    nonisolated static func isHidden(_ pin: Pin, secretBoards: Set<UUID>) -> Bool {
        pin.isHidden || pin.boardIDs.contains { secretBoards.contains($0) }
    }

    /// Keeps a pin hidden the way "Hide pin" does: it remembers its normal boards (for Unhide),
    /// leaves them (its hidden boards stay) and is hidden on its own. Used whenever something
    /// done to a hidden pin — taking it off its last hidden board, deleting that board, moving it
    /// to Recently Deleted — would otherwise drop it back into the normal library.
    nonisolated static func keepHidden(_ pin: inout Pin, secretBoards: Set<UUID>) {
        for boardID in pin.boardIDs where !secretBoards.contains(boardID) && !pin.boardsBeforeHiding.contains(boardID) {
            pin.boardsBeforeHiding.append(boardID)
        }
        pin.boardIDs.removeAll { !secretBoards.contains($0) }
        if pin.boardIDs.isEmpty { pin.placementReason = nil }
        pin.isHidden = true
    }

    /// The hidden boards among `boards`: the secret ones and every board inside them.
    nonisolated static func secretBoardIDs(in boards: [Board]) -> Set<UUID> {
        boardIDs(in: boards, where: { (board: Board) -> Bool in board.isSecret })
    }

    /// The boards that `marked` says yes to, and every board inside them (a mark on a board
    /// covers its sub-boards: hiding, keeping out of All).
    nonisolated static func boardIDs(in boards: [Board], where marked: (Board) -> Bool) -> Set<UUID> {
        var children: [UUID: [UUID]] = [:]
        for board in boards {
            if let parent = board.parentID { children[parent, default: []].append(board.id) }
        }
        var result: Set<UUID> = []
        var waiting: [UUID] = boards.filter(marked).map { $0.id }
        while let id = waiting.popLast() {
            guard result.insert(id).inserted else { continue }
            waiting.append(contentsOf: children[id] ?? [])
        }
        return result
    }

    // MARK: Kept out of All (softer than hiding)

    /// A pin stays out of the Pins tab's All feed when it says so itself, or when it is on a board
    /// (or inside one) that keeps its pins out. It still shows everywhere else.
    func isKeptOutOfAll(_ pin: Pin) -> Bool {
        pin.keptOutOfAll || pin.boardIDs.contains { (id: UUID) -> Bool in keptOutCache.contains(id) }
    }

    /// Whether a board keeps its pins out of All — itself, or because a board it is in does.
    func boardKeepsPinsOutOfAll(_ id: UUID) -> Bool { keptOutCache.contains(id) }

    /// The normal side's All feed: live normal pins that aren't kept out.
    var allFeedPins: [Pin] { visiblePins.filter { (pin: Pin) -> Bool in !isKeptOutOfAll(pin) } }

    /// The normal pins kept out of All (the Pins tab's "Kept out" filter).
    var keptOutPins: [Pin] { visiblePins.filter { (pin: Pin) -> Bool in isKeptOutOfAll(pin) } }

    /// "Keep out of All" / "Show in All" for pins. Showing again a pin that a board keeps out
    /// changes only the pin's own flag (the board's rule still applies: the caller says so).
    /// Only the pins whose flag really changes are touched (and stamped): a pin that already is as
    /// asked must not get a newer date, or it would win the next iCloud merge over a real edit.
    func setKeptOutOfAll(_ ids: Set<UUID>, _ kept: Bool) {
        let changing: Set<UUID> = Set(ids.filter { (id: UUID) -> Bool in
            guard let current = pin(id) else { return false }
            return current.keptOutOfAll != kept
        })
        guard !changing.isEmpty else { return }
        modify(changing) { (pin: inout Pin) in pin.keptOutOfAll = kept }
        scheduleSave()
    }

    /// "Keep out of All" / "Show in All" for a board (its sub-boards follow).
    func setBoardKeepsPinsOutOfAll(_ id: UUID, _ keeps: Bool) {
        guard let index = boardIndex[id], boards[index].keepsPinsOutOfAll != keeps else { return }
        // Through `modifyBoard`, so a board saved before "last edited" existed keeps its old date as
        // that (this is a setting, not an edit of what is on the board) and the caches are refreshed.
        modifyBoard(id) { (board: inout Board) in board.keepsPinsOutOfAll = keeps }
        scheduleSave()
    }

    /// The scope a pin belongs to.
    func scope(of pin: Pin) -> PinScope { isHidden(pin) ? .hidden : .visible }

    /// Secret itself, or inside a secret board.
    func isSecretBoard(_ id: UUID) -> Bool { secretCache.contains(id) }

    /// Anything an export may want to leave out: hidden boards, hidden pins or hidden smart boards.
    var hasHiddenContent: Bool {
        !secretCache.isEmpty || !scopeSplit.hidden.isEmpty || smartBoards.contains { $0.isHidden }
    }

    func pin(_ id: UUID) -> Pin? {
        guard let index = index(of: id) else { return nil }
        return pins[index]
    }

    /// A pin that is not in the trash.
    func livePin(_ id: UUID) -> Pin? {
        guard let pin = pin(id), !pin.isDeleted else { return nil }
        return pin
    }

    /// Is this web page already saved as a pin on this side of the library?
    /// (A hidden pin never counts for the normal library, and the other way round.)
    func hasPin(sourceURL: String, scope: PinScope = .visible) -> Bool {
        pinID(forSourceURL: sourceURL, scope: scope) != nil
    }

    /// The pin saved from this web page, among the pins of one scope.
    func pinID(forSourceURL sourceURL: String, scope: PinScope = .visible) -> UUID? {
        pins(scope: scope).first { $0.sourceURL == sourceURL }?.id
    }

    /// The link pin for this web page, among the pins of one scope. Two addresses that differ
    /// only in their tracking (see `LinkCleaner`) are the same page.
    func pinID(forLink url: String, scope: PinScope = .visible) -> UUID? {
        let page = LibraryStore.pageKey(url)
        return pins(scope: scope).first { $0.isLink && cachedPageKey(of: $0) == page }?.id
    }

    /// A link pin's `pageKey`, worked out once per address: cleaning every link pin's address
    /// again on every look-up (each link of an import asks) would be slow in a big library. An
    /// entry is used only while the pin still has the address it was worked out from, so a changed
    /// address (edited, cleaned, synced, restored) is simply worked out again.
    private func cachedPageKey(of pin: Pin) -> String {
        let link = pin.linkURL ?? ""
        if let known = pageKeyCache[pin.id], known.link == link { return known.key }
        if pageKeyCache.count > pins.count + 500 { pageKeyCache = [:] }   // (erased pins' entries)
        let key = LibraryStore.pageKey(link)
        pageKeyCache[pin.id] = PageKeyEntry(link: link, key: key)
        return key
    }

    /// What two addresses of the same page have in common: the address without its tracking,
    /// normalized (see `normalizedLink`).
    nonisolated static func pageKey(_ link: String) -> String {
        normalizedLink(LinkCleaner.cleaned(link))
    }

    /// The address a link pin keeps: without its tracking when "Clean links" is on (Settings ›
    /// Links), otherwise as it was given.
    func keptLink(_ url: URL) -> URL {
        guard AppSettings.shared.cleanLinks else { return url }
        return LibraryStore.cleanedLink(url)
    }

    /// `url` without its tracking (see `LinkCleaner`), in the form a link pin keeps it.
    nonisolated static func cleanedLink(_ url: URL) -> URL {
        URL(string: LinkCleaner.cleaned(url.absoluteString)) ?? url
    }

    /// The side of the library new pins land on: straight into Hidden (`hidden`, no board),
    /// or onto boards of which any is hidden → .hidden (see `isHidden`); otherwise .visible.
    func importScope(boardIDs: [UUID], hidden: Bool) -> PinScope {
        if boardIDs.isEmpty { return hidden ? .hidden : .visible }
        return boardIDs.contains { secretCache.contains($0) } ? .hidden : .visible
    }

    nonisolated static func normalizedLink(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix("/") { value.removeLast() }
        return value.replacingOccurrences(of: "http://", with: "https://")
    }

    func board(_ id: UUID?) -> Board? {
        guard let id, let index = boardIndex[id] else { return nil }
        return boards[index]
    }

    /// Sub-boards in the user's order (then by name).
    func children(of parentID: UUID?) -> [Board] {
        if let cached = childrenCache[parentID] { return cached }
        let result = boards.filter { $0.parentID == parentID }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        childrenCache[parentID] = result
        return result
    }

    /// Sub-boards that are shown outside the Hidden folder.
    func visibleChildren(of parentID: UUID?) -> [Board] {
        children(of: parentID).filter { !$0.isSecret }
    }

    /// Top-level boards that live in the Hidden folder (in the user's order, then by name).
    var secretRootBoards: [Board] {
        boards.filter { $0.isSecret && !($0.parentID.map { secretCache.contains($0) } ?? false) }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// The outermost boards of a scope: normal top-level boards, or the Hidden section's boards.
    func rootBoards(scope: PinScope) -> [Board] {
        switch scope {
        case .visible: return visibleChildren(of: nil)
        case .hidden: return secretRootBoards
        }
    }

    /// Every board nested anywhere inside `id` (not including `id` itself).
    func descendants(of id: UUID) -> [UUID] {
        if let cached = descendantsCache[id] { return cached }
        var result: [UUID] = []
        var seen: Set<UUID> = [id]
        var queue = children(of: id).map { $0.id }
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(next).inserted else { continue }   // a cycle in a damaged file can't hang us
            result.append(next)
            queue.append(contentsOf: children(of: next).map { $0.id })
        }
        descendantsCache[id] = result
        return result
    }

    /// Parents of a board, outermost first, ending with the board itself.
    func path(to id: UUID) -> [Board] {
        var chain: [Board] = []
        var current = board(id)
        var guardCounter = 0
        while let b = current, guardCounter < 50 {
            chain.insert(b, at: 0)
            current = board(b.parentID)
            guardCounter += 1
        }
        return chain
    }

    func boardPath(_ id: UUID?) -> String? {
        guard let id else { return nil }
        let chain = path(to: id)
        return chain.isEmpty ? nil : chain.map { $0.name }.joined(separator: " › ")
    }

    /// The boards that show a pin: a normal pin's boards, or only the hidden boards of a hidden
    /// pin. (A hidden pin can stay filed on a normal board out of sight — say one of its boards
    /// was hidden — and that board never shows it, lists it or is offered for it.)
    func shownBoardIDs(for pin: Pin) -> [UUID] {
        let hidden = isHidden(pin)
        return pin.boardIDs.filter { secretCache.contains($0) == hidden }
    }

    /// The names of the boards shown for a pin (see `shownBoardIDs(for:)`).
    func boardNames(for pin: Pin) -> [String] {
        shownBoardIDs(for: pin).compactMap { board($0)?.name }
    }

    /// All boards flattened into an indented list (for pickers). Secret boards
    /// are included only when asked.
    func boardRows(includingSecret: Bool) -> [BoardRow] {
        var rows: [BoardRow] = []
        func visit(_ parentID: UUID?, depth: Int) {
            for child in children(of: parentID) where depth < 20 {
                if !includingSecret && child.isSecret { continue }
                rows.append(BoardRow(board: child, depth: depth))
                visit(child.id, depth: depth + 1)
            }
        }
        visit(nil, depth: 0)
        return rows
    }

    /// The boards of one scope flattened into an indented list (for pickers):
    /// normal boards only, or only the Hidden section's boards (hidden roots at depth 0).
    func boardRows(scope: PinScope) -> [BoardRow] {
        switch scope {
        case .visible:
            return boardRows(includingSecret: false)
        case .hidden:
            var rows: [BoardRow] = []
            func visit(_ parentID: UUID, depth: Int) {
                for child in children(of: parentID) where depth < 20 {
                    rows.append(BoardRow(board: child, depth: depth))
                    visit(child.id, depth: depth + 1)
                }
            }
            for root in secretRootBoards {
                rows.append(BoardRow(board: root, depth: 0))
                visit(root.id, depth: 1)
            }
            return rows
        }
    }

    /// Like `boardRows(scope:)` (same depths, hidden roots at depth 0), but the boards that
    /// share a parent are ordered like the Boards page (`sortedBoards`: favorites first).
    func boardRows(scope: PinScope, sort: BoardSort) -> [BoardRow] {
        var rows: [BoardRow] = []
        let hidden = scope == .hidden
        func visit(_ parentID: UUID, depth: Int) {
            guard depth < 20 else { return }
            let kids = hidden ? children(of: parentID) : visibleChildren(of: parentID)
            for child in sortedBoards(kids, by: sort) {
                rows.append(BoardRow(board: child, depth: depth))
                visit(child.id, depth: depth + 1)
            }
        }
        for root in sortedBoards(rootBoards(scope: scope), by: sort) {
            rows.append(BoardRow(board: root, depth: 0))
            visit(root.id, depth: 1)
        }
        return rows
    }

    /// Live pins on a board (and, if asked, its sub-boards). A normal board never
    /// lists hidden pins (e.g. those on a hidden sub-board); a hidden board lists all of its pins.
    func pinIDs(in boardID: UUID, includeNested: Bool) -> Set<UUID> {
        var ids = membership[boardID] ?? []
        if includeNested {
            for child in descendants(of: boardID) { ids.formUnion(membership[child] ?? []) }
        }
        if !ids.isEmpty, !secretCache.contains(boardID) {
            let hidden = scopeSplit.hiddenIDs
            if !hidden.isEmpty { ids.subtract(hidden) }
        }
        return ids
    }

    func pins(in boardID: UUID, includeNested: Bool) -> [Pin] {
        let ids = pinIDs(in: boardID, includeNested: includeNested)
        guard !ids.isEmpty else { return [] }
        return livePins.filter { ids.contains($0.id) }
    }

    /// The live video pins among `ids` (what the "Thumbnail" commands work on: a selection of pins
    /// of several kinds offers them only when it is all videos — compare the count with `ids`).
    func videoPinIDs(in ids: Set<UUID>) -> Set<UUID> {
        ids.filter { (id: UUID) -> Bool in livePin(id)?.isVideo == true }
    }

    /// Normal pins on no board.
    var unsortedPins: [Pin] { unsortedPins(scope: .visible) }

    /// Pins on no board of their own side: normal pins on no board, or (scope .hidden) hidden
    /// pins on no hidden board (one filed only on normal boards, out of sight, is unsorted in Hidden).
    func unsortedPins(scope: PinScope) -> [Pin] {
        guard scope == .hidden else { return pins(scope: .visible).filter { $0.isUnsorted } }
        let secret = secretCache
        return pins(scope: .hidden).filter { pin in !pin.boardIDs.contains { secret.contains($0) } }
    }

    func pinCount(in boardID: UUID) -> Int {
        pinIDs(in: boardID, includeNested: true).count
    }

    /// Boards this pin can be the cover of: its boards plus all of their parents,
    /// without repeats, outermost first along each path. A hidden pin is offered
    /// hidden boards only; a normal pin normal boards only (its hidden boards, and
    /// the paths to them, are left out).
    func coverCandidates(for pin: Pin) -> [Board] {
        let hidden = isHidden(pin)
        var seen: Set<UUID> = []
        var result: [Board] = []
        for boardID in shownBoardIDs(for: pin) {
            for board in path(to: boardID) where !seen.contains(board.id) {
                seen.insert(board.id)
                if hidden != secretCache.contains(board.id) { continue }
                result.append(board)
            }
        }
        return result
    }

    /// Most-used tags across a set of pins (for search suggestions and web queries).
    func topTags(in subset: [Pin], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for pin in subset {
            var seen: Set<String> = []
            for tag in pin.tags {
                let t = tag.lowercased()
                if seen.insert(t).inserted { counts[t, default: 0] += 3 }
            }
            for tag in pin.aiTags where tag.confidence > 0.5 {
                if seen.insert(tag.label).inserted { counts[tag.label, default: 0] += 1 }
            }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(limit)
            .map { $0.key }
    }

    func topTags(limit: Int, scope: PinScope = .visible) -> [String] {
        topTags(in: pins(scope: scope), limit: limit)
    }

    // The rest of the store is in extensions, one file per topic: see the list at the top of this file.
}
