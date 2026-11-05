//
//  VideoPosters.swift  —  PinBoard
//
//  Choosing a video's thumbnail (its poster): another frame from the video, the frame it is
//  paused on, a picture from Photos, or a picture pin — and writing it into the video file's
//  own artwork so other apps show it too.
//
//  What is here, top to bottom:
//    • VideoPosters — the plain rules and the frame work (which frames to look at, what counts as
//      "another" frame, a frame as a JPEG). Nothing in it touches the store, so the harness can
//      test the rules.
//    • PosterArtwork — the metadata that puts a picture into a video file as its artwork.
//    • the store's side (the four functions the menus call, and the queue that writes the
//      artwork into the files one at a time in the background).
//
//  How a poster change goes: the library's own poster (its picture file and thumbnail) changes
//  first, at once — that is what every card and page shows. Then, in the background, the same
//  picture is written into the video file itself, as its artwork. That second step is best
//  effort: when it can't be done the poster in the library still changed and nothing is lost.
//  QuickTime Player, VLC and the Files app's previews read that artwork; Photos ignores it (it
//  always uses a video's first frame). The original video in the originals folder is never touched.
//

import SwiftUI
import UIKit
import AVFoundation
import Foundation

// MARK: - The rules

/// Which frames to look at for "another frame", and what makes one good enough (the harness
/// tests all of this). Frames are compared as tiny 16 × 16 grey pictures: cheap, and enough to
/// tell "the same shot" from "another shot".
enum VideoPosters {
    /// Side of the tiny grey picture frames are compared by.
    nonisolated static let gridSide = 16
    /// A frame counts as "another" frame when, on average, its pixels differ from the poster
    /// shown now by more than this share of the whole range (10 %).
    nonisolated static let differentEnough = 0.10
    /// When no frame differs that much, the most different one is still used — unless even that
    /// one is the same picture (a video that hardly moves): then nothing changes.
    nonisolated static let practicallyTheSame = 0.02
    /// A frame whose brightness hardly varies (one plain colour, a blank title card) is a poor
    /// thumbnail: its brightness spread (0…255) is under this.
    nonisolated static let flatSpread = 6.0

    /// The times (in seconds) to look at, in order: the first is a random spot in the middle
    /// 60 % of the video (`startShare` 0…1 picks where), the others walk on from it through that
    /// middle part and wrap round. Times closer than a quarter second to one already listed are
    /// left out. A video with no known length gives none.
    nonisolated static func probeTimes(duration: Double, startShare: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let start = startShare.isFinite ? min(max(startShare, 0), 1) : 0.5
        var times: [Double] = []
        for step in 0..<8 {
            let walked = (start * 0.6 + Double(step) * 0.13).truncatingRemainder(dividingBy: 0.6)
            let time = duration * (0.2 + walked)
            if !times.contains(where: { (earlier: Double) -> Bool in abs(earlier - time) < 0.25 }) { times.append(time) }
        }
        return times
    }

    /// A picture as a 16 × 16 grid of brightness values (0…255). nil when it can't be drawn.
    nonisolated static func lumaGrid(of image: CGImage) -> [UInt8]? {
        let side = gridSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium   // averages the pixels each cell stands for
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
            return true
        }
        guard drawn else { return nil }
        var grid: [UInt8] = []
        grid.reserveCapacity(side * side)
        for start in stride(from: 0, to: pixels.count, by: 4) {
            let luma = 0.299 * Double(pixels[start]) + 0.587 * Double(pixels[start + 1]) + 0.114 * Double(pixels[start + 2])
            grid.append(UInt8(min(max(luma.rounded(), 0), 255)))
        }
        return grid
    }

    /// The grid of a picture file (the poster shown now). nil when it can't be read.
    nonisolated static func lumaGrid(ofFileAt url: URL) -> [UInt8]? {
        guard let data = try? Data(contentsOf: url), let image = ImageProcessor.downsample(data, maxPixelSize: 64) else { return nil }
        return lumaGrid(of: image)
    }

    /// How different two grids are: the average difference of their cells as a share of the whole
    /// range (0: the same picture, 1: black against white). Grids of different sizes: 1.
    nonisolated static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total = 0
        for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
        return Double(total) / Double(a.count * 255)
    }

    /// A grid whose brightness hardly varies: one plain colour, a blank card.
    nonisolated static func isFlat(_ grid: [UInt8]) -> Bool {
        guard !grid.isEmpty else { return true }
        let mean = grid.reduce(0.0) { (sum: Double, value: UInt8) -> Double in sum + Double(value) } / Double(grid.count)
        let variance = grid.reduce(0.0) { (sum: Double, value: UInt8) -> Double in
            sum + (Double(value) - mean) * (Double(value) - mean)
        } / Double(grid.count)
        return variance.squareRoot() < flatSpread
    }

    /// How good a frame is as "another" poster: nil when it can't be one (black, or one plain
    /// colour); otherwise how different it is from the poster shown now (1 when that isn't known).
    nonisolated static func novelty(of grid: [UInt8], isBlack: Bool, current: [UInt8]?) -> Double? {
        if isBlack || isFlat(grid) { return nil }
        guard let current, current.count == grid.count else { return 1 }
        return difference(grid, current)
    }

    /// Goes through `times` in order and stops at the first frame `rate` calls different enough.
    /// When none is, the most different usable one wins, unless even that is practically the same
    /// picture as the poster (then nil: nothing to change). `rate` gives a frame's `novelty`.
    nonisolated static func selectTime(_ times: [Double], rate: (Double) async -> Double?) async -> Double? {
        var best: (time: Double, novelty: Double)? = nil
        for time in times {
            if Task.isCancelled { return nil }
            guard let novelty = await rate(time) else { continue }
            if novelty > differentEnough { return time }
            if novelty > (best?.novelty ?? -1) { best = (time, novelty) }
        }
        guard let best, best.novelty > practicallyTheSame else { return nil }
        return best.time
    }

    // MARK: A picture of another shape than the video

    /// Pictures whose shape is this close to the video's (a share of the video's width ÷ height)
    /// are left whole.
    nonisolated static let shapeTolerance = 0.03

    /// The part of a picture — in whole pixels, centred — that has the video's shape, so a card
    /// shows the video's shape whatever picture was chosen for it. nil: the picture has that shape
    /// already (within `shapeTolerance`) or one of the sizes makes no sense.
    nonisolated static func cropRect(pictureWidth: Int, pictureHeight: Int, videoWidth: Double, videoHeight: Double) -> CGRect? {
        guard pictureWidth > 0, pictureHeight > 0, videoWidth.isFinite, videoHeight.isFinite,
              videoWidth > 0, videoHeight > 0 else { return nil }
        let wanted = videoWidth / videoHeight
        let have = Double(pictureWidth) / Double(pictureHeight)
        if abs(have - wanted) / wanted < shapeTolerance { return nil }
        if have > wanted {
            // Too wide: the sides are cut.
            let width = min(pictureWidth, max(1, Int((Double(pictureHeight) * wanted).rounded())))
            return CGRect(x: (pictureWidth - width) / 2, y: 0, width: width, height: pictureHeight)
        }
        // Too tall: top and bottom are cut.
        let height = min(pictureHeight, max(1, Int((Double(pictureWidth) / wanted).rounded())))
        return CGRect(x: 0, y: (pictureHeight - height) / 2, width: pictureWidth, height: height)
    }

    /// `data` as a JPEG of the video's shape (centred; at most 2048 px, as the library keeps
    /// posters). The picture itself when the shape is not known or already right, or when it
    /// can't be cut. Off the main thread.
    nonisolated static func fitted(_ data: Data, toVideoShape shape: CGSize?) -> Data {
        guard let shape, let picture = ImageProcessor.downsample(data, maxPixelSize: 2048),
              let rect = cropRect(pictureWidth: picture.width, pictureHeight: picture.height,
                                  videoWidth: Double(shape.width), videoHeight: Double(shape.height)),
              let cut = picture.cropping(to: rect),
              let jpeg = ImageProcessor.jpegData(cut, quality: 0.92) else { return data }
        return jpeg
    }

    /// The video's size as shown (its track's natural size turned the way the file says, so a
    /// portrait film is tall). nil when the file can't be read. Loads the asset: off the main thread.
    nonisolated static func shownSize(of video: URL) async -> CGSize? {
        let asset = AVURLAsset(url: video)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let turned = natural.applying(transform)
        let shown = CGSize(width: abs(turned.width), height: abs(turned.height))
        return shown.width > 0 && shown.height > 0 ? shown : nil
    }

    // MARK: Frames from a video (AVFoundation; call off the main thread)

    /// Another frame of the video as JPEG bytes: not black, not a plain colour, and not the picture
    /// shown now (`currentPoster`), looked for from a random spot in the middle of the video.
    /// nil when the video can't be read or has no such frame.
    nonisolated static func anotherFrame(of video: URL, currentPoster: URL, startShare: Double) async -> Data? {
        let asset = AVURLAsset(url: video)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let length = CMTimeGetSeconds(duration)
        guard length.isFinite, length > 0 else { return nil }
        let current = lumaGrid(ofFileAt: currentPoster)
        let probe = AVAssetImageGenerator(asset: asset)
        probe.appliesPreferredTrackTransform = true
        probe.maximumSize = CGSize(width: 320, height: 320)
        let slack = CMTime(seconds: 0.5, preferredTimescale: 600)
        probe.requestedTimeToleranceBefore = slack
        probe.requestedTimeToleranceAfter = slack
        // The frame each looked-at time really gave, so the poster is made from exactly that one.
        var actualTimes: [Double: CMTime] = [:]
        let rate = { (seconds: Double) async -> Double? in
            let wanted = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let frame = try? await probe.image(at: wanted), let grid = lumaGrid(of: frame.image) else { return nil }
            actualTimes[seconds] = frame.actualTime
            return novelty(of: grid, isBlack: VideoTools.isMostlyBlack(frame.image), current: current)
        }
        let times = probeTimes(duration: length, startShare: startShare)
        guard let chosen = await selectTime(times, rate: rate) else { return nil }
        let at = actualTimes[chosen] ?? CMTime(seconds: chosen, preferredTimescale: 600)
        return await frameJPEG(of: asset, at: at, slack: nil)
    }

    /// The frame at `seconds` as JPEG bytes: exactly that one (the picture the person paused on,
    /// not one a fraction of a second away that may belong to another shot); when the file can't
    /// give it — a pause at the very end, say — the nearest. nil when the video can't be read.
    nonisolated static func frame(of video: URL, atSeconds seconds: Double) async -> Data? {
        guard seconds.isFinite else { return nil }
        let asset = AVURLAsset(url: video)
        var time = max(0, seconds)
        if let duration = try? await asset.load(.duration) {
            let length = CMTimeGetSeconds(duration)
            if length.isFinite, length > 0 { time = min(time, length) }
        }
        let wanted = CMTime(seconds: time, preferredTimescale: 600)
        return await frameJPEG(of: asset, at: wanted, slack: nil)
    }

    /// One frame, turned upright, at most 2048 px (the library keeps posters at that size), as
    /// JPEG (quality 0.92). `slack`: how far from `at` a frame may come (nil: exactly that one,
    /// and when the file can't give it, the nearest).
    nonisolated private static func frameJPEG(of asset: AVURLAsset, at time: CMTime, slack: CMTime?) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        generator.requestedTimeToleranceBefore = slack ?? .zero
        generator.requestedTimeToleranceAfter = slack ?? .zero
        var result = try? await generator.image(at: time)
        if result == nil, slack == nil {
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            result = try? await generator.image(at: time)
        }
        guard let image = result?.image else { return nil }
        return ImageProcessor.jpegData(image, quality: 0.92)
    }
}

// MARK: - The artwork in the file

/// Putting a picture into a video file as its artwork (what QuickTime Player, VLC and the Files
/// app's previews show as its thumbnail). Only the plain rules are here; `LibraryStore.writeArtwork`
/// does the export.
enum PosterArtwork {
    /// The metadata a re-written file gets: what it has already, without any artwork it carries
    /// (the old thumbnail goes), plus the new picture as its artwork.
    nonisolated static func metadata(keeping existing: [AVMetadataItem], adding jpeg: Data) -> [AVMetadataItem] {
        // The artwork items the file has, by whatever key space they were written in.
        let oldArtwork = AVMetadataItem.metadataItems(from: existing, filteredByIdentifier: .commonIdentifierArtwork)
        let oldIdentifiers = Set(oldArtwork.compactMap { (item: AVMetadataItem) -> AVMetadataIdentifier? in item.identifier })
        let kept = existing.filter { (item: AVMetadataItem) -> Bool in
            guard let identifier = item.identifier else { return true }
            return !oldIdentifiers.contains(identifier)
        }
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.dataType = kCMMetadataBaseDataType_JPEG as String
        artwork.value = NSData(data: jpeg)
        artwork.extendedLanguageTag = "und"
        return kept + [artwork]
    }

    /// A video file whose own kind can be written again: .mov, .mp4 or .m4v (other files are
    /// left as they are — their artwork can't be written in the same kind of file).
    nonisolated static func fileType(of video: URL) -> AVFileType? {
        StoragePolicy.fileType(forExtension: StoragePolicy.libraryExtension(of: video))
    }

    /// A re-written file must be about as big as the one it replaces (the picture adds a little;
    /// a passthrough export copies the rest): well under half means something went wrong.
    nonisolated static func looksComplete(newBytes: Int, oldBytes: Int) -> Bool {
        guard newBytes > 0, oldBytes > 0 else { return false }
        return Double(newBytes) >= Double(oldBytes) * 0.5
    }
}

// MARK: - The store's side

extension LibraryStore {
    /// Picks another frame (not the one shown now, never a black one) as each video's poster.
    /// Returns how many posters changed. One video at a time, off the main thread; a video whose
    /// file is missing, that has no other usable frame, or that belongs to another profile's
    /// library by the time its frame is ready is left as it is.
    @discardableResult
    func pickAnotherPoster(for ids: Set<UUID>) async -> Int {
        let profile = profileID
        var changed = 0
        for id in ids.sorted(by: { (a: UUID, b: UUID) -> Bool in a.uuidString < b.uuidString }) {
            if Task.isCancelled || !isCurrentProfile(profile) { break }
            guard let video = livePin(id), video.isVideo, !missingFileIDs.contains(id), await ensureLocal(video) else { continue }
            let file = videoFileURL(for: video)
            let poster = imageFileURL(for: video)
            let startShare = Double.random(in: 0...1)
            let jpeg = await Task.detached(priority: .userInitiated) { () -> Data? in
                await VideoPosters.anotherFrame(of: file, currentPoster: poster, startShare: startShare)
            }.value
            guard isCurrentProfile(profile), let jpeg else { continue }
            if await changePoster(of: id, with: jpeg, videoFile: video.videoFileName) { changed += 1 }
        }
        return changed
    }

    /// The frame `seconds` into the video becomes its poster (the frame it is paused on).
    /// false: the video can't be read, or it is gone.
    @discardableResult
    func setPoster(for id: UUID, frameAt seconds: Double) async -> Bool {
        let profile = profileID
        guard let video = livePin(id), video.isVideo, !missingFileIDs.contains(id), seconds.isFinite,
              await ensureLocal(video) else { return false }
        let file = videoFileURL(for: video)
        let jpeg = await Task.detached(priority: .userInitiated) { () -> Data? in
            await VideoPosters.frame(of: file, atSeconds: seconds)
        }.value
        guard isCurrentProfile(profile), let jpeg else { return false }
        return await changePoster(of: id, with: jpeg, videoFile: video.videoFileName)
    }

    /// A picture (from Photos, or a picture pin's file) becomes the video's poster. Any picture
    /// the system can read will do; false when `imageData` isn't one. A picture of another shape
    /// than the video is cut to the video's shape (the middle of it): the card keeps the video's
    /// shape, and the poster file stays exactly the size the pin's record says (iCloud checks that
    /// before it carries a changed picture to another device).
    @discardableResult
    func setPoster(for id: UUID, imageData: Data) async -> Bool {
        let profile = profileID
        guard let video = livePin(id), video.isVideo else { return false }
        await ensureLocal(video)   // (the video's shape is read from its file)
        let file = videoFileURL(for: video)
        let prepared = await Task.detached(priority: .userInitiated) { () async -> Data? in
            guard ImageProcessor.downsample(imageData, maxPixelSize: 64) != nil else { return nil }   // not a picture
            let shape = await VideoPosters.shownSize(of: file)
            return VideoPosters.fitted(imageData, toVideoShape: shape)
        }.value
        guard let prepared, isCurrentProfile(profile) else { return false }
        return await changePoster(of: id, with: prepared, videoFile: video.videoFileName)
    }

    /// A picture pin's picture becomes the video's poster. The picture must come from the same
    /// side of the library as the video: a hidden pin's picture never becomes a normal video's
    /// poster (nor the other way round). false: no such picture.
    @discardableResult
    func setPoster(for id: UUID, fromPictureOf other: UUID) async -> Bool {
        let profile = profileID
        guard id != other, let video = livePin(id), video.isVideo, let source = livePin(other),
              source.hasImageFile, scope(of: source) == scope(of: video) else { return false }
        let file = imageFileURL(for: source)
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in try? Data(contentsOf: file) }.value
        guard isCurrentProfile(profile), let data else { return false }
        return await setPoster(for: id, imageData: data)
    }

    /// Changes the library's poster of a video (its picture file, thumbnail and what the AI sees),
    /// then has the picture written into the video file in the background. Only while the pin is
    /// still the same video (`videoFile`: its file name when the picture was made) in this library.
    private func changePoster(of id: UUID, with data: Data, videoFile: String) async -> Bool {
        let profile = profileID
        guard let before = livePin(id), before.isVideo, before.videoFileName == videoFile else { return false }
        let changed = await replacePoster(of: id, with: data)
        guard changed, isCurrentProfile(profile) else { return false }
        scheduleArtwork(for: id)
        return true
    }

    // MARK: The artwork in the video's own file

    /// Has a video's current poster written into its file, in the background, after the ones
    /// already waiting. A video asked for twice waits only once (the file gets the newest poster).
    func scheduleArtwork(for id: UUID) {
        if !artworkQueue.contains(id) { artworkQueue.append(id) }
        startArtworkWorker()
    }

    /// Stops the artwork writing of the library that was in use (a switch to another profile).
    func cancelArtworkWriting() {
        artworkQueue = []
        artworkWaiting = []
        artworkTask?.cancel()
    }

    private func startArtworkWorker() {
        guard artworkTask == nil, !artworkQueue.isEmpty else { return }
        artworkTask = Task { @MainActor [weak self] in
            while let store = self, !store.artworkQueue.isEmpty, !Task.isCancelled {
                let profile = store.profileID
                let id = store.artworkQueue.removeFirst()
                await store.writeArtwork(for: id, profile: profile)
            }
            self?.artworkTask = nil
            self?.startArtworkWorker()   // (something came in while a stopped run was winding down)
        }
    }

    /// Writes a video's poster into its own file as its artwork: the file is exported again
    /// without converting anything (AVAssetExportPresetPassthrough — its video and sound are
    /// copied), with the poster added to what metadata it has, into a temporary file; that then
    /// takes the file's place in one step, and players showing it open it again. A video that is
    /// being converted is left alone while that goes on — the request is remembered and runs when
    /// the conversion has ended (`artworkWaiting`), so the new poster still reaches the file; and a
    /// conversion waits for an artwork write instead of skipping the video. The file is replaced by
    /// one job at a time. Best effort: when the export fails, isn't possible for this kind of file,
    /// or there is no room, nothing changes (the library's poster already did).
    private func writeArtwork(for id: UUID, profile: UUID) async {
        guard isCurrentProfile(profile), let video = livePin(id), video.isVideo, !missingFileIDs.contains(id),
              !isOffloaded(video) else { return }   // (a video kept in iCloud only keeps its old artwork)
        if videosBeingConverted.contains(id) {
            artworkWaiting.insert(id)   // a conversion has the file: this poster is written right after it
            return
        }
        let file = videoFileURL(for: video)
        guard let fileType = PosterArtwork.fileType(of: file), let oldBytes = VideoCompressor.fileBytes(at: file),
              LibraryStore.hasRoomForCopy(of: oldBytes) else { return }
        let fileName = video.videoFileName
        let posterFile = imageFileURL(for: video)
        videosBeingConverted.insert(id)   // no other job touches this video until its file is settled
        artworkWriting.insert(id)         // (a conversion that comes meanwhile waits for it)
        defer {
            videosBeingConverted.remove(id)
            artworkWriting.remove(id)
        }
        let jpeg = await Task.detached(priority: .utility) { () -> Data? in try? Data(contentsOf: posterFile) }.value
        guard let jpeg, isCurrentProfile(profile) else { return }
        let temporary = VideoCompressor.temporaryFile(extension: StoragePolicy.libraryExtension(of: file))
        let written = await VideoCompressor.export(file, to: temporary, fileType: fileType, preset: AVAssetExportPresetPassthrough,
                                                   artwork: jpeg, progress: { (_: Double) in })
        // Still this library, still this pin and file, and the new file looks complete?
        let newBytes = VideoCompressor.fileBytes(at: temporary) ?? 0
        guard written, PosterArtwork.looksComplete(newBytes: newBytes, oldBytes: oldBytes), isCurrentProfile(profile),
              let now = pin(id), now.videoFileName == fileName, FileManager.default.fileExists(atPath: file.path) else {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        guard await VideoCompressor.settle(temporary, at: file) else { return }
        VideoFileChanges.replaced(file)   // the file changed under the same name: players showing it open the new one
    }

    /// Whether the device has room for one more copy of a file this big (plus a margin), so a
    /// re-written video never fills the disk. true when that can't be told.
    nonisolated static func hasRoomForCopy(of bytes: Int) -> Bool {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: FileManager.default.temporaryDirectory.path)
        guard let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value else { return true }
        return free > Int64(bytes) + 200_000_000
    }
}
