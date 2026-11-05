//
//  VideoCompression.swift  —  PinBoard
//
//  Making videos smaller (Settings › iCloud & storage › "Video quality"): `StoragePolicy` holds the plain
//  rules (when a video is converted, and to what) and `VideoCompressor` converts a video, copies
//  one, or puts a file in place. It is its own file because it is about the video file itself;
//  MediaStorage.swift has the store's side (what the library does with these).
//

import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - The rules

/// Facts about a video file, read once (`VideoTools.facts(for:)`).
struct VideoFacts: Sendable, Equatable {
    /// The longest side of a frame, in pixels (a portrait 1080 × 1920 video → 1920).
    var longEdge: Int
    /// How many bits per second the picture takes (the video track's estimated data rate).
    var dataRate: Double
    /// The picture's format: "hvc1" / "hev1" (HEVC), "avc1" (H.264)…; nil when unknown.
    var codec: String?
    /// The file's size in bytes.
    var bytes: Int
    /// The length in seconds.
    var duration: Double
}

/// What happens to the copy of a video kept on this device.
enum StorageDecision: Equatable, Sendable {
    case keep                     // small enough already: it is kept as it is
    case convert(preset: String)  // converted with this export preset (AVAssetExportSession)
}

/// The plain rules behind Settings › iCloud & storage › "Video quality" (the harness tests them).
enum StoragePolicy {
    /// Bits per second above which a video at that quality is worth converting, even when its
    /// frames are no larger than the quality's (a phone's 1080p H.264 film, say, takes far more
    /// room than the same film in HEVC).
    nonisolated static func dataRateLimit(for quality: VideoQuality) -> Double {
        switch quality {
        case .original: return .infinity
        case .uhd: return 30_000_000
        case .fullHD: return 12_000_000
        case .hd: return 6_000_000
        }
    }

    /// The export preset for a quality, spelled as in AVFoundation. There is no HEVC preset for
    /// 720p, so 720p is H.264. "Original" never converts (its preset only copies).
    nonisolated static func preset(for quality: VideoQuality) -> String {
        switch quality {
        case .original: return AVAssetExportPresetPassthrough
        case .uhd: return AVAssetExportPresetHEVC3840x2160
        case .fullHD: return AVAssetExportPresetHEVC1920x1080
        case .hd: return AVAssetExportPreset1280x720
        }
    }

    /// Convert when a quality is chosen and the video is larger than it — frames longer than
    /// the quality's longest side, or more data per second than its limit. Keep it as it is
    /// otherwise, and always when its length or size isn't known (it can't be converted then).
    nonisolated static func decision(for facts: VideoFacts, quality: VideoQuality) -> StorageDecision {
        guard let maxLongEdge = quality.maxLongEdge else { return .keep }
        guard facts.duration.isFinite, facts.duration > 0, facts.longEdge > 0 else { return .keep }
        let framesTooLarge = facts.longEdge > maxLongEdge
        let tooMuchData = facts.dataRate.isFinite && facts.dataRate > dataRateLimit(for: quality)
        guard framesTooLarge || tooMuchData else { return .keep }
        return .convert(preset: preset(for: quality))
    }

    /// A converted copy is kept only when it is at least 15 % smaller than the video it came
    /// from; otherwise the video is kept as it is (converting again would gain nothing, so the
    /// quality is still recorded).
    nonisolated static func worthKeeping(convertedBytes: Int, sourceBytes: Int) -> Bool {
        guard convertedBytes > 0, sourceBytes > 0 else { return false }
        return Double(convertedBytes) <= Double(sourceBytes) * 0.85
    }

    /// "48 MB", "1.2 GB" — sizes as the Files app writes them.
    nonisolated static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }

    /// The kind of file a converted copy is written as, so it keeps its file's name: ".mov"
    /// stays a QuickTime movie, ".mp4" and ".m4v" stay MPEG-4. nil for any other file (a new
    /// video's copy then becomes an ".mp4").
    ///
    /// Why the name stays: iCloud sync copies a video only when its pin first reaches another
    /// device. A copy renamed here (".mov" → ".mp4") would never reach the others, and the
    /// renamed pin would look for a file they don't have.
    nonisolated static func fileType(forExtension fileExtension: String) -> AVFileType? {
        switch fileExtension.lowercased() {
        case "mov", "qt": return .mov
        case "mp4": return .mp4
        case "m4v": return .m4v
        default: return nil
        }
    }

    /// Whether a new video is converted while it is imported rather than afterwards: only a kind of
    /// file that can't keep its name (not .mov/.mp4/.m4v — a .3gp, say) when a quality is chosen.
    /// Such a video becomes an .mp4, and a pin's file can't be renamed later (see `fileType`: iCloud
    /// copies a video only when its pin first reaches another device), so it is done before the pin
    /// exists, as it always was. Every other video is copied as it is, and converted afterwards.
    nonisolated static func convertsAtImport(extension fileExtension: String, quality: VideoQuality) -> Bool {
        quality != .original && fileType(forExtension: fileExtension) == nil
    }

    /// A file extension as the library keeps it: lower case, without a dot; "mov" when there is none.
    nonisolated static func libraryExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "mov" : ext
    }
}

// MARK: - Converting videos

/// What `VideoCompressor.place` did with a video.
enum VideoOutcome: Sendable, Equatable {
    /// Copied as it was, nothing decided ("Original" is the chosen quality, or converting failed
    /// — a later "Convert existing videos…" tries again).
    case copied(extension: String)
    /// Looked at for `tier` and kept as it was: small enough already, or converting it didn't
    /// make it smaller. `tier` is recorded, so it isn't tried again at that quality.
    case kept(extension: String, tier: VideoQuality)
    /// Converted to `tier`; the copy on this device takes `bytes`.
    case converted(extension: String, tier: VideoQuality, bytes: Int)
    /// Nothing could be put in place (not even a plain copy).
    case failed

    /// The extension of the file put in place (nil when nothing was).
    var fileExtension: String? {
        switch self {
        case .copied(let ext), .kept(let ext, _), .converted(let ext, _, _): return ext
        case .failed: return nil
        }
    }

    /// The quality to record on the pin (`Pin.videoTier`; nil: none).
    var tier: VideoQuality? {
        switch self {
        case .kept(_, let tier), .converted(_, let tier, _): return tier
        case .copied, .failed: return nil
        }
    }
}

/// Set once by an iOS 17 export's completion handler (which runs on AVFoundation's own thread);
/// read by the task waiting for it. @unchecked: `lock` guards `finished`.
private final class ExportFinished: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func set() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

/// How one conversion went.
enum ConversionResult: Sendable, Equatable {
    case smaller(bytes: Int)   // the converted file is ready and worth keeping
    case notSmaller            // converted, but not smaller: thrown away
    case failed                // couldn't be converted (or it was stopped)
}

/// Puts videos in place in the library: copied as they are, or converted when they are larger
/// than the chosen quality. A file is always written under a passing name first and then takes
/// its place in one step, so a library file is never half-written.
enum VideoCompressor {
    /// Puts the video for a pin in place at `folder/<id>.<ext>`: copied as it is, or converted to
    /// `quality` when `StoragePolicy` says so. `progress` gets 0…1 while converting. On any
    /// conversion failure the video is copied as it is. The extension stays the video's own when
    /// it is .mov, .mp4 or .m4v (see `StoragePolicy.fileType(forExtension:)`); a converted video
    /// of any other kind becomes an .mp4.
    /// (Since round 14 an import no longer converts: it copies the video as it is, and the
    /// conversion comes later, in the background, through `convert` and `settle` — see
    /// `LibraryStore.startConvertingNewVideos`. This all-in-one version is kept for its tests.)
    nonisolated static func place(source: URL, pinID: UUID, in folder: URL, quality: VideoQuality,
                                  progress: @escaping @Sendable (Double) -> Void) async -> VideoOutcome {
        let sourceExtension = StoragePolicy.libraryExtension(of: source)
        let copyTarget = folder.appendingPathComponent("\(pinID.uuidString).\(sourceExtension)")
        guard quality != .original else {
            return await copy(source, to: copyTarget) ? .copied(extension: sourceExtension) : .failed
        }
        let facts = await VideoTools.facts(for: source)
        guard let facts, case .convert(let preset) = StoragePolicy.decision(for: facts, quality: quality) else {
            // Small enough already (or it can't be read: then it can't be converted either).
            return await copy(source, to: copyTarget) ? .kept(extension: sourceExtension, tier: quality) : .failed
        }
        let keepsType = StoragePolicy.fileType(forExtension: sourceExtension)
        let outputExtension = keepsType == nil ? "mp4" : sourceExtension
        let temporary = temporaryFile(extension: outputExtension)
        let result = await convert(source, to: temporary, fileType: keepsType ?? .mp4, preset: preset,
                                   sourceBytes: facts.bytes, progress: progress)
        if case .smaller(let bytes) = result {
            let destination = folder.appendingPathComponent("\(pinID.uuidString).\(outputExtension)")
            if await settle(temporary, at: destination) {
                return .converted(extension: outputExtension, tier: quality, bytes: bytes)
            }
        }
        try? FileManager.default.removeItem(at: temporary)
        guard await copy(source, to: copyTarget) else { return .failed }
        return result == .notSmaller ? .kept(extension: sourceExtension, tier: quality) : .copied(extension: sourceExtension)
    }

    /// Converts `source` into `output` (a new file) with `preset`, then checks it is worth keeping
    /// (`StoragePolicy.worthKeeping`). Whatever isn't kept is removed again.
    nonisolated static func convert(_ source: URL, to output: URL, fileType: AVFileType, preset: String,
                                    sourceBytes: Int, progress: @escaping @Sendable (Double) -> Void) async -> ConversionResult {
        let exported = await export(source, to: output, fileType: fileType, preset: preset, progress: progress)
        guard exported, let bytes = fileBytes(at: output), bytes > 0 else {
            try? FileManager.default.removeItem(at: output)
            return .failed
        }
        guard StoragePolicy.worthKeeping(convertedBytes: bytes, sourceBytes: sourceBytes) else {
            try? FileManager.default.removeItem(at: output)
            return .notSmaller
        }
        return .smaller(bytes: bytes)
    }

    /// Runs the export itself. true only when `output` was written in full. Stopping the task
    /// that runs it stops the export too (the half-made file is removed).
    /// `artwork` (JPEG bytes): written into the output file as its artwork, next to the metadata
    /// the source file has already (a video's thumbnail; see VideoPosters.swift).
    nonisolated static func export(_ source: URL, to output: URL, fileType: AVFileType, preset: String,
                                   artwork: Data? = nil,
                                   progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        let asset = AVURLAsset(url: source)
        let compatible = await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType)
        guard compatible, !Task.isCancelled, let session = AVAssetExportSession(asset: asset, presetName: preset) else { return false }
        session.shouldOptimizeForNetworkUse = true
        if let artwork {
            let existing: [AVMetadataItem] = (try? await asset.load(.metadata)) ?? []
            session.metadata = PosterArtwork.metadata(keeping: existing, adding: artwork)
        }
        try? FileManager.default.removeItem(at: output)
        let finished: Bool
        if #available(iOS 18, *) {
            finished = await exportOnIOS18(session, to: output, fileType: fileType, progress: progress)
        } else {
            finished = await exportOnIOS17(session, to: output, fileType: fileType, progress: progress)
        }
        if !finished { try? FileManager.default.removeItem(at: output) }
        return finished && FileManager.default.fileExists(atPath: output.path)
    }

    /// iOS 18 and later: the export reports its own progress, and stops when the task is stopped.
    /// (The session itself may not be handed to another task; its stream of states may.)
    @available(iOS 18, *)
    nonisolated private static func exportOnIOS18(_ session: AVAssetExportSession, to output: URL, fileType: AVFileType,
                                                  progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        let states = session.states(updateInterval: 0.5)
        let watcher = Task {
            for await state in states {
                if case .exporting(let exporting) = state { progress(exporting.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: output, as: fileType)
        } catch {
            return false
        }
        progress(1)
        return true
    }

    /// iOS 17: the older export. It runs by itself; this task reads its progress every half
    /// second until it has finished, and stops it when this task is stopped. (The session never
    /// leaves this task: it may not be handed to another one.)
    nonisolated private static func exportOnIOS17(_ session: AVAssetExportSession, to output: URL, fileType: AVFileType,
                                                  progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        session.outputURL = output
        session.outputFileType = fileType
        let done = ExportFinished()
        session.exportAsynchronously { done.set() }
        var cancelled = false
        while !done.isSet {
            if Task.isCancelled, !cancelled {
                cancelled = true
                session.cancelExport()
            }
            if cancelled {
                // Stopped: this only waits for AVFoundation to finish stopping, and reports nothing
                // more. (A stopped task's Task.sleep returns at once, so without this the loop would
                // spin and flood the screen with progress reports.)
                await VideoCompressor.pause(seconds: 0.05)
            } else {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard !cancelled, session.status == .completed else { return false }
        progress(1)
        return true
    }

    /// Waits `seconds`, also in a stopped task (whose Task.sleep would return at once).
    nonisolated static func pause(seconds: Double) async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { resume.resume() }
        }
    }

    /// Copies a video as it is: under a passing name next to `destination` first, then into its
    /// place in one step. The copy is dated now (the orphan sweep tells a re-imported pin's new
    /// file from a leftover by its date, see `LibraryStore.sweepOrphans`). Off the main thread.
    nonisolated static func copy(_ source: URL, to destination: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            VideoCompressor.copyNow(source, to: destination)
        }.value
    }

    /// `copy`, right here (for code already off the main thread).
    nonisolated static func copyNow(_ source: URL, to destination: URL) -> Bool {
        let staged = LibraryStore.incoming(destination)
        try? FileManager.default.removeItem(at: staged)
        guard (try? FileManager.default.copyItem(at: source, to: staged)) != nil else {
            try? FileManager.default.removeItem(at: staged)
            return false
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: staged.path)
        guard LibraryStore.moveIntoPlace(staged, destination) else {
            try? FileManager.default.removeItem(at: staged)
            return false
        }
        return true
    }

    /// Puts a finished file from the temporary folder in the place of `destination`: a rename
    /// when both are on the same disk (one step), else a copy under a passing name next to it
    /// and then a rename. The temporary file is gone afterwards either way.
    nonisolated static func settle(_ temporary: URL, at destination: URL) async -> Bool {
        if LibraryStore.moveIntoPlace(temporary, destination) { return true }
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            defer { try? FileManager.default.removeItem(at: temporary) }
            return VideoCompressor.copyNow(temporary, to: destination)
        }.value
    }

    /// A new file name in the system's temporary folder for a conversion to write into. (The
    /// export needs the right extension on its file.)
    nonisolated static func temporaryFile(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(temporaryPrefix)\(UUID().uuidString).\(fileExtension)")
    }

    /// Conversions write into files named like this in the temporary folder.
    nonisolated static let temporaryPrefix = "PinBoard-video-"

    /// Removes what conversions (and copies into the originals folder) stopped halfway left in the
    /// temporary folder (the app was closed in the middle): files over an hour old, so work
    /// running now is never touched.
    nonisolated static func removeLeftovers() {
        let folder = FileManager.default.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-3600)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let prefixes = [temporaryPrefix, OriginalsFolder.stagingPrefix]
        for file in files where prefixes.contains(where: { (prefix: String) -> Bool in file.lastPathComponent.hasPrefix(prefix) }) {
            let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let written, written < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// A file's size in bytes, read fresh from the disk (nil when it isn't there).
    nonisolated static func fileBytes(at url: URL) -> Int? {
        let fresh = URL(fileURLWithPath: url.path)   // a new URL: sizes read before aren't reused
        return (try? fresh.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}
