//
//  TextAndVideo.swift  —  PinBoard
//
//  Text pins (a card of text that sits in the grid like a picture) and video
//  pins (a poster frame in the grid, a looping preview on the card), the
//  helpers that read videos (a poster frame; the facts Settings › iCloud & storage decides
//  by — see MediaStorage.swift), the sound switch, the
//  camera and the share sheet. The big player (pin page, Quick Look, full
//  screen) lives in VideoPlayer.swift.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import Foundation

// MARK: - Reading videos

/// A still from a video, plus what else is worth knowing about it.
struct VideoPoster: Sendable {
    var jpegData: Data
    var duration: Double
    var hasAudio: Bool? = nil     // filled in by the importer (VideoTools.hasAudio)
}

enum VideoTools {
    /// 0…255: pixels darker than this count as black.
    static let darkLuma: Double = 24
    /// A frame with more than this share of black pixels is a "black" frame.
    static let mostlyBlackShare: Double = 0.7

    /// A poster frame for the video (rotated upright) that is not (nearly) black.
    /// A few small frames are looked at first — near the start, then around the
    /// middle — and the first one that is not mostly black wins (else the least
    /// dark one). The poster is then made full size from exactly that frame.
    /// So a video that fades in from black gets a poster from its middle.
    nonisolated static func poster(for url: URL) async -> VideoPoster? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        let length = seconds.isFinite ? max(0, seconds) : 0
        let times = posterProbeTimes(duration: length)

        // 1. Small, quick looks (a frame near each time will do).
        let probe = AVAssetImageGenerator(asset: asset)
        probe.appliesPreferredTrackTransform = true
        probe.maximumSize = CGSize(width: 320, height: 320)
        let slack = CMTime(seconds: 0.5, preferredTimescale: 600)
        probe.requestedTimeToleranceBefore = slack
        probe.requestedTimeToleranceAfter = slack
        var chosen: CMTime? = nil
        var leastDark: (time: CMTime, dark: Double)? = nil
        for time in times {
            guard let frame = try? await probe.image(at: CMTime(seconds: time, preferredTimescale: 600)) else { continue }
            let dark = darkFraction(of: frame.image)
            if dark <= mostlyBlackShare {
                chosen = frame.actualTime   // not mostly black: this one
                break
            }
            if let best = leastDark, best.dark <= dark { continue }
            leastDark = (frame.actualTime, dark)
        }
        let at = chosen ?? leastDark?.time ?? CMTime(seconds: times.first ?? 0, preferredTimescale: 600)

        // 2. The poster itself, full size, from that very frame.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var result = try? await generator.image(at: at)
        if result == nil {
            // Some files can't give that exact frame: the nearest one will do.
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            result = try? await generator.image(at: at)
        }
        guard let image = result?.image,
              let jpeg = ImageProcessor.jpegData(image, quality: 0.9) else { return nil }
        return VideoPoster(jpegData: jpeg, duration: length)
    }

    /// Where `poster(for:)` looks, in order: 0.5 s in (or halfway, for a very short
    /// video), then the middle, and further out from it. Times closer than a
    /// quarter second to one already listed are left out.
    nonisolated private static func posterProbeTimes(duration: Double) -> [Double] {
        var times = [duration > 0 ? min(0.5, duration / 2) : 0]
        guard duration > 0 else { return times }
        for share in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8] {
            let time = duration * share
            if !times.contains(where: { abs($0 - time) < 0.25 }) {
                times.append(time)
            }
        }
        return times
    }

    /// Share (0…1) of black pixels in a ≤32×32 downsample of `image`
    /// (luma = 0.299 R + 0.587 G + 0.114 B, below `darkLuma`).
    nonisolated static func darkFraction(of image: CGImage) -> Double {
        guard image.width > 0, image.height > 0 else { return 0 }
        let scale = min(1, 32 / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium   // averages the pixels each dot stands for
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { return 0 }   // can't tell: not dark
        var dark = 0
        for start in stride(from: 0, to: pixels.count, by: 4) {
            let luma = 0.299 * Double(pixels[start]) + 0.587 * Double(pixels[start + 1]) + 0.114 * Double(pixels[start + 2])
            if luma < darkLuma { dark += 1 }
        }
        return Double(dark) / Double(width * height)
    }

    /// `darkFraction(of:)` > `mostlyBlackShare`.
    nonisolated static func isMostlyBlack(_ image: CGImage) -> Bool {
        darkFraction(of: image) > mostlyBlackShare
    }

    /// The video's length in seconds, nil when the file can't be read. Loads the
    /// asset — call it off the main thread.
    nonisolated static func duration(for url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// Whether the video has a sound track (false when the file can't be read).
    /// Loads the asset's track list — call it off the main thread.
    nonisolated static func hasAudio(for url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else { return false }
        return !tracks.isEmpty
    }

    /// What Settings › iCloud & storage decides by (see `StoragePolicy`): the longest side of the frames,
    /// the picture's data rate and format, the file's size and the video's length — read once
    /// from the file. The longest side is the larger of the frame's width and height, so a
    /// portrait video (stored sideways and turned when shown) counts the same as a landscape one.
    /// nil when the file can't be read as a video. Loads the asset — call it off the main thread.
    nonisolated static func facts(for url: URL) async -> VideoFacts? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration),
              let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let size = try? await track.load(.naturalSize),
              let rate = try? await track.load(.estimatedDataRate) else { return nil }
        let formats: [CMFormatDescription] = (try? await track.load(.formatDescriptions)) ?? []
        let seconds = CMTimeGetSeconds(time)
        let longEdge = Int(max(abs(size.width), abs(size.height)).rounded())
        let codec = formats.first.flatMap { (format: CMFormatDescription) -> String? in
            fourCharacterText(CMFormatDescriptionGetMediaSubType(format))
        }
        let bytes = VideoCompressor.fileBytes(at: url) ?? 0
        return VideoFacts(longEdge: longEdge, dataRate: Double(rate), codec: codec, bytes: bytes,
                          duration: seconds.isFinite ? max(0, seconds) : 0)
    }

    /// A four-letter code as text ("hvc1", "avc1"); nil when it isn't four printable letters.
    nonisolated static func fourCharacterText(_ code: UInt32) -> String? {
        let bytes: [UInt8] = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                              UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        guard bytes.allSatisfy({ (byte: UInt8) -> Bool in byte >= 32 && byte < 127 }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// "1:05". nil when the length isn't known yet (0) or makes no sense: a broken file can report
    /// an absurd length, and turning one past what a whole number holds into one would crash the
    /// app wherever its card is on screen (the same limit as a YouTube link's length).
    static func durationText(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 1e9 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A video picked from Photos, delivered as a file we own.
struct MovieFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { (movie: MovieFile) in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

// MARK: - Sound

/// Which videos may play with sound. One switch, set by any speaker button: once
/// the person turns sound on, every video they open large (pin pages, Quick Look)
/// plays with sound — from page to page, tab to tab — until they turn it off again.
/// In the grids only one card at a time plays with sound (the one whose speaker was
/// tapped). It also keeps the audio session right: silent videos mix with other
/// apps' audio, sound takes over like any video app.
@MainActor
final class SoundState: ObservableObject {
    static let shared = SoundState()

    /// Sound is on: videos shown large play with sound. Only the speaker buttons change it.
    @Published var soundOn = false
    /// The one grid card allowed to play with sound (nil = every card is silent).
    @Published var gridSoundPinID: UUID? = nil {
        didSet { if gridSoundPinID != oldValue { updateAudioSession() } }
    }

    private enum SessionMode { case ambient, playback }
    private var sessionMode: SessionMode? = nil
    /// Big players playing with sound right now.
    private var soundingPlayers: Set<ObjectIdentifier> = []

    /// A big player started (true) or stopped (false) playing with sound. The audio
    /// session is in "playback" mode only while something really plays with sound, so
    /// silent videos never stop other apps' music.
    func setSounding(_ sounding: Bool, player: ObjectIdentifier) {
        let changed = sounding ? soundingPlayers.insert(player).inserted : soundingPlayers.remove(player) != nil
        if changed { updateAudioSession() }
    }

    /// Puts the audio session in the right mode for what may sound right now.
    /// `playingSound`: the caller itself is about to play with sound.
    func updateAudioSession(playingSound: Bool = false) {
        let wanted: SessionMode = (playingSound || !soundingPlayers.isEmpty || gridSoundPinID != nil) ? .playback : .ambient
        guard wanted != sessionMode else { return }
        sessionMode = wanted
        let session = AVAudioSession.sharedInstance()
        switch wanted {
        case .ambient:
            // Silent videos must never interrupt whatever else is playing.
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        case .playback:
            // Real sound, like any video app (also with the silent switch on).
            try? session.setCategory(.playback, mode: .moviePlayback)
        }
    }
}

// MARK: - Playing videos

/// A looping player for a card in the grid (no controls). Silent, unless
/// `muted` is false (the one card the person gave sound to).
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var muted: Bool = true

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.load(url, muted: muted)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        if view.url != url || view.fileWasReplaced {
            view.load(url, muted: muted)
        } else if view.isSilent != muted {
            view.setMuted(muted)
        }
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: ()) {
        view.stop()
    }
}

/// Where a preview is (see `PlaybackPositions`): it continues where the video was
/// left in any player, remembers where it stopped if it played at least 0.3 s,
/// and jumps to wherever a big player stops the same video.
@MainActor
final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var url: URL?
    private(set) var isSilent = true

    /// When it really started playing (nil = not yet).
    private var playingSince: Date? = nil
    /// Where to start once the first loop is ready (nil = no waiting).
    private var pendingStart: Double? = nil
    /// Goes up with every new video, so callbacks about an old one are ignored.
    private var generation = 0
    private var itemObservation: NSKeyValueObservation? = nil
    private var statusObservation: NSKeyValueObservation? = nil
    private weak var watchedItem: AVPlayerItem? = nil
    /// The positions' clock when this preview last took a place from them.
    private(set) var syncStamp = 0
    /// A big player took this video over: this preview's own time is stale, so
    /// stopping writes nothing (the big player writes when it stops).
    var takenOver = false
    /// How often the file had been replaced when it was opened (see `VideoFileChanges`).
    private var fileRevision = 0
    private var fileObserver: NotificationObserver? = nil
    /// The video's picture is showing. Until its first frame is ready the view is invisible and
    /// clear, so the card's poster (drawn underneath by the grid) stays in view — never a grey or
    /// empty rectangle while the video starts.
    private var revealed = false
    private var readyObservation: NSKeyValueObservation? = nil

    /// The file was replaced under the same name since it was opened (a smaller copy of it).
    var fileWasReplaced: Bool {
        guard let url else { return false }
        return VideoFileChanges.revision(of: url) != fileRevision
    }

    /// The time within the current loop, while it plays.
    var liveTime: Double? {
        guard playingSince != nil, let player else { return nil }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? max(0, seconds) : nil
    }

    func load(_ url: URL, muted: Bool) {
        stop()
        hideUntilReady()
        self.url = url
        fileRevision = VideoFileChanges.revision(of: url)
        listenForFileChanges()
        isSilent = muted
        generation += 1
        SoundState.shared.updateAudioSession(playingSound: !muted)
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        queue.preventsDisplaySleepDuringVideoPlayback = !muted
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.videoGravity = .resizeAspectFill
        let positions = PlaybackPositions.shared
        syncStamp = positions.clock
        takenOver = false
        if let start = positions.savedPosition(for: url), start > 0.5 {
            // Continue where this video was left (in any player): seek once the first
            // loop is ready, and only then show and play it, so it never jumps.
            pendingStart = start
            watchFirstLoop(of: queue)
        } else {
            startPlaying()
        }
        positions.previewStarted(self, url: url)
    }

    /// Clear background (nothing grey behind the picture) and no picture showing yet: it fades in
    /// once the player layer says its first frame is ready. Watches the layer until `stop()`.
    private func hideUntilReady() {
        backgroundColor = .clear
        playerLayer.backgroundColor = UIColor.clear.cgColor
        revealed = false
        alpha = 0
        readyObservation?.invalidate()
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { @Sendable [weak self] _, _ in
            let view = self
            Task { @MainActor in
                view?.readinessChanged()
            }
        }
    }

    /// The layer's first frame may be ready: show the picture.
    private func readinessChanged() {
        guard !revealed, playerLayer.isReadyForDisplay else { return }
        reveal()
    }

    /// Fades the picture in over 0.15 s, once per opening of a file (a loop starting over never
    /// hides it again).
    private func reveal() {
        guard !revealed else { return }
        revealed = true
        UIView.animate(withDuration: 0.15) {
            self.alpha = 1
        }
    }

    /// Turns the sound on or off without restarting the video.
    func setMuted(_ muted: Bool) {
        isSilent = muted
        SoundState.shared.updateAudioSession(playingSound: !muted)
        guard let player else { return }
        player.isMuted = muted
        player.preventsDisplaySleepDuringVideoPlayback = !muted
        if playingSince != nil { player.play() }   // one still moving to its start plays once it is there
    }

    /// A video file was replaced under the same name: if it is this one, it is opened again
    /// (from where it was, like any preview).
    private func listenForFileChanges() {
        guard fileObserver == nil else { return }
        fileObserver = NotificationObserver(name: VideoFileChanges.notification, object: nil) { @Sendable [weak self] in
            let view = self
            Task { @MainActor in
                guard let view, let url = view.url, view.fileWasReplaced else { return }
                view.load(url, muted: view.isSilent)
            }
        }
    }

    func stop() {
        readyObservation?.invalidate()
        readyObservation = nil
        revealed = false
        alpha = 0
        if let url {
            PlaybackPositions.shared.previewStopped(self, url: url, at: placeToKeep())
        }
        fileObserver = nil
        itemObservation?.invalidate()
        statusObservation?.invalidate()
        itemObservation = nil
        statusObservation = nil
        watchedItem = nil
        pendingStart = nil
        playingSince = nil
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
    }

    /// A big player stopped this video at `seconds`: jump there and keep looping.
    func follow(_ seconds: Double, stamp: Int) {
        syncStamp = stamp
        takenOver = false
        guard let player else { return }
        if pendingStart != nil {
            pendingStart = seconds        // not started yet: it starts there instead
            return
        }
        let slack = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: slack, toleranceAfter: slack)
    }

    /// Where it stands now, if that counts: it played at least 0.3 s and no big
    /// player took the video over since. The time within the current loop, so a
    /// preview stopped just after it wrapped around keeps about 0.
    private func placeToKeep() -> Double? {
        guard !takenOver, let since = playingSince, Date().timeIntervalSince(since) >= 0.3 else { return nil }
        return liveTime
    }

    private func startPlaying() {
        guard let player else { return }
        playerLayer.player = player
        player.play()
        playingSince = Date()
        revealAnyway(generation: generation)
    }

    /// A safety net: if the layer never says it is ready (it should, always), the picture still
    /// shows after a moment — a video that plays unseen would be worse than a late fade.
    private func revealAnyway(generation started: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.generation == started, self.player != nil else { return }
            self.reveal()
        }
    }

    /// The looper queues its first copy of the video a moment after it is made;
    /// the start seek has to wait until that copy is ready to play.
    private func watchFirstLoop(of queue: AVQueuePlayer) {
        let current = generation
        itemObservation = queue.observe(\.currentItem, options: [.initial, .new]) { @Sendable [weak self] _, _ in
            let view = self
            Task { @MainActor in
                view?.firstLoopChanged(generation: current)
            }
        }
    }

    private func firstLoopChanged(generation reported: Int) {
        guard reported == generation, let start = pendingStart, let queue = player,
              let item = queue.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            pendingStart = nil
            itemObservation?.invalidate()
            statusObservation?.invalidate()
            itemObservation = nil
            statusObservation = nil
            watchedItem = nil
            let length = CMTimeGetSeconds(item.duration)
            guard start > 0.5, length.isFinite, start < length - 0.5 else {
                startPlaying()
                return
            }
            let slack = CMTime(seconds: 0.25, preferredTimescale: 600)
            queue.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                       toleranceBefore: slack, toleranceAfter: slack) { @Sendable [weak self] _ in
                let view = self
                Task { @MainActor in
                    view?.firstLoopPositioned(generation: reported)
                }
            }
        case .failed:
            pendingStart = nil
            startPlaying()
        default:
            // Not ready yet: watch this copy (once) until it is.
            guard watchedItem !== item else { return }
            watchedItem = item
            statusObservation = item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] _, _ in
                let view = self
                Task { @MainActor in
                    view?.firstLoopChanged(generation: reported)
                }
            }
        }
    }

    private func firstLoopPositioned(generation reported: Int) {
        guard reported == generation, player != nil, playingSince == nil else { return }
        startPlaying()
    }
}

// MARK: - Camera

/// Takes one photo with the system camera (photos only: no video, so no microphone).
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onFinish: () -> Void

    /// Whether this device has a camera (the Simulator and some iPads don't).
    @MainActor static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraCaptureView

        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish()
        }
    }
}

// MARK: - Text pins

/// The card a text pin shows in the grid. Its height is computed by
/// `TextCardStyle.cardHeight`, so the grid knows it before drawing. Its type follows the
/// text size chosen in iOS (see `TextCardStyle.scaled`).
struct TextCardView: View {
    let pin: Pin
    let style: TextCardStyle
    let color: Color?
    /// Read so the card is redrawn at the new size when the text size changes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if style.showsTitleOnBoard, !pin.title.isEmpty {
                Text(pin.title)
                    .font(style.swiftFont(size: style.boardSize * TextCardStyle.titleScale, weight: .semibold))
                    .lineLimit(2)
            }
            Text(pin.textBody.isEmpty ? " " : pin.textBody)
                .font(style.swiftFont(size: style.boardSize))
                .lineLimit(style.linesOnBoard)
        }
        .foregroundStyle(color ?? Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.cardPadding)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
    }
}

/// The text of a text pin on its page (the whole text, page-size type, following the
/// text size chosen in iOS).
struct TextPanelView: View {
    let pin: Pin
    let style: TextCardStyle
    let color: Color?
    var onEdit: (() -> Void)? = nil
    /// Read so the text is redrawn at the new size when the text size changes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pin.textBody.isEmpty ? "No text yet — tap “Edit text” to write some." : pin.textBody)
                .font(style.swiftFont(size: style.pageSize))
                .foregroundStyle(pin.textBody.isEmpty ? Color.secondary : (color ?? Color.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let onEdit {
                HStack {
                    Spacer()
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit text", systemImage: "pencil")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
    }
}

/// Writing a new text pin (or rewriting one): a title and the text itself.
struct TextPinEditorSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let heading: String
    let onSave: (String, String) -> Void
    @State private var title: String
    @State private var body_: String
    @State private var editingBody = true
    /// What the fields held when the sheet opened.
    private let initialTitle: String
    private let initialBody: String

    init(heading: String, title: String = "", body: String = "", onSave: @escaping (String, String) -> Void) {
        self.heading = heading
        self.onSave = onSave
        _title = State(initialValue: title)
        _body_ = State(initialValue: body)
        initialTitle = title
        initialBody = body
    }

    /// Something was typed or changed: then a swipe down must not throw it away.
    private var hasChanges: Bool {
        title != initialTitle || body_ != initialBody
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                NativeTextField(placeholder: "Title (optional — the AI can write one)", text: $title)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                NativeTextView(text: $body_, autoFocus: true)
                    .frame(minHeight: 160, maxHeight: 320)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("The text becomes a pin: it sits in the grid, can go on boards, and is searched like everything else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               body_.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        // With changes, only Cancel or Save closes the sheet (a swipe down can't lose them).
        .interactiveDismissDisabled(hasChanges)
    }
}

// MARK: - Sharing files (a share sheet that works on iPad and iPhone)

/// The system share sheet, presented inside a regular sheet so it is never
/// squeezed into a tiny popover.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool
    /// Runs when the share sheet closes: true when the items were really shared or saved
    /// (AirDrop, Save to Files, Mail…), false when it was cancelled. (Settings counts an export
    /// as done only then.)
    var onComplete: (@MainActor @Sendable (Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let presented = $isPresented
        let finished = onComplete
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in
                finished?(completed)
                presented.wrappedValue = false   // close our sheet when the share sheet is done
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
