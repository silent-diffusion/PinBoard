//
//  VideoPlayer.swift  —  PinBoard
//
//  PinBoard's own video player, for a video shown large: on a pin's page and in
//  Quick Look. The picture sits in an AVPlayerLayer and our own controls run along
//  the bottom (play/pause, the time, a scrub bar, sound, and — on a pin's page — a
//  button that opens the video in Quick Look), so nothing covers Quick Look's ✕ and
//  ⋯ buttons at the top. A big play / pause button with skip back and skip forward
//  sits in the middle. Videos start over by themselves when they reach the end.
//  In Quick Look a video can also play faster or slower (VideoControls.swift: hold a finger on it,
//  or ⋯ › Speed); the player plays at whatever speed its `VideoPlayerHandle` says. Two quick taps
//  skip back or forward by the Settings step (YouTube-style). A video carries on from where it was
//  left wherever you come back to it from, and its controls stay hidden until you tap it.
//
//  Also here: where each video was stopped last (`PlaybackPositions`). Every
//  player shares it, the small looping previews in the grids too, and it is kept
//  only until the app quits. And `VideoFileChanges`: when "Convert existing
//  videos…" (Settings › iCloud & storage) replaces a video's file with a smaller copy under
//  the same name, every player showing it opens the new file.
//

import SwiftUI
import AVFoundation
import UIKit
import Foundation

// MARK: - The player

/// PinBoard's own player for a video shown large (pin page, Quick Look).
///
/// One player per view, made once per `url`. `playing` is the wish to play by
/// itself: becoming true plays (when `mayPlay`), false pauses. `mayPlay` false
/// (scrolled away, covered) pauses whatever plays — started by itself or by
/// hand — and resumes it when it turns true again. At the end a video starts over.
/// The picture is fitted, never cropped, on black. The controls sit along the
/// bottom, inside `controlsInsets`; the top 64 points stay free (Quick Look's ✕ and
/// ⋯ live there). The controls start hidden (a video scrolled to plays undisturbed); one tap on the picture shows or hides the controls (answered 0.3 s later, once
/// it is clear no second tap follows); two quick taps skip instead — back on the left half, forward
/// on the right half, by Settings' step — and each further quick tap skips again, with the sum
/// ("+30") over the half (`TapSkipState`). While playing the controls fade out 3 seconds after the
/// last touch. Sound follows `SoundState.shared.soundOn`; turning the volume up unmutes the video in
/// front (`VolumeButtonWatcher`, through the `handle`).
/// `onExpand` adds the expand button (the pin page opens Quick Look with it). In the middle are
/// the big play / pause button and skip back / forward (by Settings › `videoSkipSeconds`); they
/// show and hide with the bar. `handle` is the screen's line to this player (see
/// `VideoPlayerHandle`): it names the video in front (`isFront`; Quick Look mounts the
/// neighbours' players too), knows when it is paused, and in Quick Look sets the speed.
struct VideoPlayerView: View {
    let url: URL
    var playing: Bool
    var mayPlay: Bool
    var controlsInsets: EdgeInsets
    var onExpand: (() -> Void)?
    var handle: VideoPlayerHandle?
    var isFront: Bool

    @StateObject private var controller = VideoPlaybackController()
    /// Carries out a tap on the picture: show or hide the controls, or skip (see `TapSkipState`).
    @StateObject private var taps = TapSkipDriver()
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pinAccent) private var accent

    init(url: URL,
         playing: Bool,
         mayPlay: Bool = true,
         controlsInsets: EdgeInsets = EdgeInsets(),
         onExpand: (() -> Void)? = nil,
         handle: VideoPlayerHandle? = nil,
         isFront: Bool = true) {
        self.url = url
        self.playing = playing
        self.mayPlay = mayPlay
        self.controlsInsets = controlsInsets
        self.onExpand = onExpand
        self.handle = handle
        self.isFront = isFront
    }

    var body: some View {
        GeometryReader { box in
            let width = box.size.width - controlsInsets.leading - controlsInsets.trailing
            let compact = width < VideoControlBar.compactWidth
            // The middle of the part of the picture that is in view: a tap left of it is on the
            // left half, a tap right of it on the right half.
            let middle = controlsInsets.leading + width / 2
            ZStack {
                Color.black
                VideoPlayerSurface(player: controller.isReady ? controller.player : nil)
                if controller.failed {
                    VideoFailureNote()
                }
                handleLayer
            }
            .contentShape(Rectangle())
            .gesture(tapGesture(middle: middle))
            .overlay(alignment: .center) {
                centreControls(box: box.size, width: width, compact: compact)
            }
            .overlay(alignment: .bottom) {
                controlBar(box: box.size, compact: compact)
            }
            .overlay {
                TapSkipOverlay(driver: taps, insets: controlsInsets)
            }
        }
        .onAppear {
            controller.appeared(url: url, playing: playing, mayPlay: mayPlay, handle: handle)
            controller.frontChanged(to: isFront)
        }
        .onChange(of: url) { _, newURL in
            controller.urlChanged(newURL, playing: playing)
            taps.cancel()
        }
        .onChange(of: playing) { _, wish in
            controller.playingChanged(wish)
        }
        .onChange(of: isFront) { _, now in
            controller.frontChanged(to: now)
            if !now { taps.cancel() }
        }
        .onChange(of: mayPlay) { _, allowed in
            controller.mayPlayChanged(allowed)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.sceneWentToBackground() }
        }
        .onDisappear {
            controller.disappeared()
            taps.cancel()
        }
    }

    /// A tap on the picture. One tap shows or hides the controls — a moment later, once it is clear
    /// that no second tap follows. Two quick taps skip instead (back on the left half, forward on the
    /// right half, by Settings' step), and every further quick tap skips again, with the sum shown
    /// over the half (see `TapSkipState`). This sits on the very view the old single tap did, so the
    /// control bar and the buttons in the middle, which lie above it, still take their own taps first.
    private func tapGesture(middle: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { (tap: SpatialTapGesture.Value) in
                let side = TapSkipState.Side(x: Double(tap.location.x), middle: Double(middle))
                let step = VideoSkip.cleaned(settings.videoSkipSeconds)
                taps.tapped(side, on: controller, seconds: step)
            }
    }

    /// The screen's line to this player: the layer over the picture (see `VideoHandleLayer`).
    @ViewBuilder
    private var handleLayer: some View {
        if let handle {
            VideoHandleLayer(handle: handle,
                             controller: controller,
                             isFront: isFront,
                             topInset: controlsInsets.top)
        }
    }

    /// The play / pause button in the middle with skip back and forward either side. It takes
    /// the room that is left between the free top and the bar, and none at all when there is
    /// too little (the bar has a play button of its own).
    @ViewBuilder
    private func centreControls(box: CGSize, width: CGFloat, compact: Bool) -> some View {
        let size = VideoCentreSize.fit(width: width,
                                       height: box.height,
                                       topUsed: controlsInsets.top + VideoControlBar.topClearance,
                                       bottomUsed: VideoControlBar.usedHeight(compact: compact, bottomInset: controlsInsets.bottom))
        if !controller.failed, size != .hidden {
            VideoCentreControls(controller: controller,
                                skipSeconds: VideoSkip.cleaned(settings.videoSkipSeconds),
                                size: size)
                .padding(.leading, controlsInsets.leading)
                .padding(.trailing, controlsInsets.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The bar along the bottom (never on a video that can't be played).
    @ViewBuilder
    private func controlBar(box: CGSize, compact: Bool) -> some View {
        if !controller.failed {
            VideoControlBar(controller: controller,
                            clock: controller.clock,
                            tint: accent,
                            insets: controlsInsets,
                            compact: compact,
                            room: box.height - controlsInsets.top - VideoControlBar.topClearance,
                            onExpand: onExpand)
        }
    }
}

// MARK: - Where each video was left

/// Where each video was stopped last, shared by every player: the grid previews,
/// the pin page and Quick Look. Kept in memory only, so a fresh launch starts every
/// video from the beginning. Keyed by the video file's path.
///
/// Big players write when they stop (pause, scrub, leave, the app goes away). A grid
/// preview writes when it stops, if it played at least 0.3 s. While a preview plays
/// it is listed here, so a big player that opens the same video can start from the
/// preview's live time, and a preview jumps to wherever a big player stopped. Big
/// players are listed too: when one starts a video another one is playing (Quick
/// Look closing over the pin page, say), the other stops and the new one carries on
/// from exactly there — no jump back, no sound twice.
@MainActor
final class PlaybackPositions {
    static let shared = PlaybackPositions()

    private struct Saved {
        var seconds: Double
        var stamp: Int
        /// Stopped on purpose (the pause button, the app going away): a player waiting
        /// to carry on with this video stays paused instead.
        var onPurpose = false
    }

    private struct LivePreview {
        weak var view: LoopingPlayerView?
    }

    private struct LivePlayer {
        weak var controller: VideoPlaybackController?
        let key: String
    }

    private var saved: [String: Saved] = [:]
    private var previews: [String: [LivePreview]] = [:]
    /// Big players that have played something (weak; one entry each).
    private var players: [LivePlayer] = []
    /// Goes up by one with every position written: a larger stamp is newer.
    private(set) var clock = 0

    private func key(_ url: URL) -> String { url.path }

    private func livePreviews(of url: URL) -> [LoopingPlayerView] {
        (previews[key(url)] ?? []).compactMap { $0.view }
    }

    @discardableResult
    private func write(_ seconds: Double, for url: URL, onPurpose: Bool = false) -> Int {
        clock += 1
        saved[key(url)] = Saved(seconds: max(0, seconds), stamp: clock, onPurpose: onPurpose)
        return clock
    }

    // Big players

    /// Where a big player opening this video should start: a grid preview playing it
    /// right now when that one is at least as fresh as the saved place, else the saved place.
    func startPosition(for url: URL) -> Double? {
        var best: (seconds: Double, stamp: Int)? = saved[key(url)].map { ($0.seconds, $0.stamp) }
        for preview in livePreviews(of: url) where !preview.takenOver {
            guard let time = preview.liveTime else { continue }
            if let current = best, preview.syncStamp < current.stamp { continue }
            best = (time, preview.syncStamp)
        }
        return best?.seconds
    }

    /// The saved place, if another player wrote it after `stamp` (and whether that
    /// player was stopped on purpose).
    func newerPosition(for url: URL, than stamp: Int) -> (seconds: Double, onPurpose: Bool)? {
        guard let entry = saved[key(url)], entry.stamp > stamp else { return nil }
        return (entry.seconds, entry.onPurpose)
    }

    /// A big player stopped this video at `seconds` (0 = back to the start). Previews
    /// playing the same video jump there and keep looping. Returns the stamp.
    @discardableResult
    func recordFromPlayer(_ seconds: Double, for url: URL, onPurpose: Bool = false) -> Int {
        let stamp = write(seconds, for: url, onPurpose: onPurpose)
        for preview in livePreviews(of: url) {
            preview.follow(seconds, stamp: stamp)
        }
        return stamp
    }

    /// A big player started playing (or scrubbing) this video: from now on it knows
    /// better than the previews, whose own times went stale.
    func playerTookOver(_ url: URL) {
        for preview in livePreviews(of: url) {
            preview.takenOver = true
        }
    }

    /// A big player is about to play this video. One big video plays at a time: every
    /// other big player that is playing stops (and saves its place). If one of them was
    /// playing this same video, its time comes back, so the new one carries on from there.
    func handOver(to controller: VideoPlaybackController, url: URL) -> Double? {
        let k = key(url)
        saved[k]?.onPurpose = false          // it plays again: no longer "stopped on purpose"
        var handed: Double? = nil
        var kept: [LivePlayer] = []
        for entry in players {
            guard let other = entry.controller, other !== controller else { continue }
            if let time = other.stopForHandOver(), entry.key == k { handed = time }
            kept.append(entry)
        }
        kept.append(LivePlayer(controller: controller, key: k))
        players = kept
        return handed
    }

    /// A big player went away, or moved on to another video.
    func playerLeft(_ controller: VideoPlaybackController) {
        players = players.filter { $0.controller != nil && $0.controller !== controller }
    }

    /// A grid card got the sound: big players go quiet (one video with sound at a time).
    func silenceBigPlayers() {
        for entry in players {
            entry.controller?.quietForCard()
        }
    }

    // Grid previews

    /// The saved place, for a preview that starts playing.
    func savedPosition(for url: URL) -> Double? {
        saved[key(url)]?.seconds
    }

    func previewStarted(_ view: LoopingPlayerView, url: URL) {
        let k = key(url)
        var list = (previews[k] ?? []).filter { $0.view != nil && $0.view !== view }
        list.append(LivePreview(view: view))
        previews[k] = list
    }

    /// A preview stopped; `seconds` is where, when it counts (nil = write nothing).
    func previewStopped(_ view: LoopingPlayerView, url: URL, at seconds: Double?) {
        let k = key(url)
        let list = (previews[k] ?? []).filter { $0.view != nil && $0.view !== view }
        previews[k] = list.isEmpty ? nil : list
        if let seconds {
            write(seconds, for: url)
        }
    }
}

// MARK: - The controller

/// The times shown by the controls. They change often, so only the controls watch them.
@MainActor
final class VideoPlaybackClock: ObservableObject {
    @Published fileprivate(set) var elapsed: Double = 0
    @Published fileprivate(set) var duration: Double = 0
    @Published fileprivate(set) var isScrubbing = false

    fileprivate func reset() {
        elapsed = 0
        duration = 0
        isScrubbing = false
    }
}

/// Owns one big player's AVPlayer and everything about it: playing and pausing
/// (the page's wishes, the buttons, being off screen), sound, the scrub bar, where
/// to start, starting over at the end, and the controls fading out.
/// Lives on the main actor; AVFoundation's callbacks hop back to it with plain values.
@MainActor
final class VideoPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer? = nil
    /// Playing, or about to (the button shows Pause).
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = true
    /// Loaded and moved to where it starts: the picture and the scrub bar are live.
    @Published private(set) var isReady = false
    @Published private(set) var failed = false
    /// Hidden until the person taps, pauses by hand or skips; see `showsControlsWhileWaiting`.
    @Published private(set) var controlsShown = false
    let clock = VideoPlaybackClock()

    private var url: URL? = nil
    /// Goes up with every new video, so callbacks about an old one are ignored.
    private var generation = 0
    private var statusObservation: NSKeyValueObservation? = nil
    private var stateObservation: NSKeyValueObservation? = nil
    private var timeObserver: Any? = nil
    private var endObserver: NotificationObserver? = nil
    private var isPositioning = false

    private var mayPlay = true
    private var resumeWhenAllowed = false
    /// Played or scrubbed since it was loaded (one that never did writes no position).
    private var hasPlayedOrScrubbed = false
    /// The registry's clock when this player last wrote or read a position.
    private var lastSync = 0

    private var wasPlayingBeforeScrub = false
    private var chaseTarget: Double? = nil
    private var chaseInFlight = false

    /// The screen's line to this player (Quick Look's, the pin page's), if it has one. It decides
    /// the speed. Not owned here.
    weak var handle: VideoPlayerHandle? = nil
    /// The page this player is on is the one in front, as far as this player has been told.
    private var isInFront = false
    /// Where the next skip starts from while an earlier skip is still seeking. Skip buttons can be
    /// tapped faster than a seek finishes, and the time shown may still be the old one then.
    private var skipBase = SkipBase()

    private var hideTask: Task<Void, Never>? = nil
    private var backgroundObserver: NotificationObserver? = nil
    /// How often the file had been replaced when it was opened (see `VideoFileChanges`).
    private var fileRevision = 0
    private var fileObserver: NotificationObserver? = nil

    nonisolated static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: The view's events

    /// A new video starts as the page wishes (`playing`). The same video coming back
    /// keeps its own state: it carries on if it was playing, stays paused if paused. (If its
    /// file was replaced while it was away, the new file is opened, from the same place.)
    func appeared(url newURL: URL, playing: Bool, mayPlay allowed: Bool, handle newHandle: VideoPlayerHandle? = nil) {
        handle = newHandle
        listenForBackground()
        listenForFileChanges()
        let fresh = newURL != url
        if !fresh, VideoFileChanges.revision(of: newURL) != fileRevision {
            reopenReplacedFile()
        }
        load(newURL)
        applyMayPlay(allowed)
        if fresh { applyPlaying(playing) }
    }

    func urlChanged(_ newURL: URL, playing: Bool) {
        load(newURL)
        applyPlaying(playing)
    }

    /// The page this player is on came to the front or left it. A paused video that won't play by
    /// itself shows its play button when it comes to the front (`showsControlsWhileWaiting`).
    func frontChanged(to front: Bool) {
        guard front != isInFront else { return }
        isInFront = front
        if front, showsControlsWhileWaiting { showControls() }
    }

    /// A video in front that is loaded but will not play by itself (a pin page with autoplay off):
    /// its controls show, so its play button can be seen. One that is about to play, or that waits
    /// only for its page to be on screen again, keeps them hidden.
    private var showsControlsWhileWaiting: Bool {
        isInFront && isReady && !failed && !isPlaying && !resumeWhenAllowed
    }

    func playingChanged(_ wish: Bool) {
        applyPlaying(wish)
    }

    func mayPlayChanged(_ allowed: Bool) {
        applyMayPlay(allowed)
    }

    /// Off screen (another screen covers it, or it went away): pause and remember the
    /// place. A video that was playing carries on when the view comes back.
    func disappeared() {
        let carryOn = isPlaying || resumeWhenAllowed
        pausePlayback()              // remembers where it was
        resumeWhenAllowed = carryOn
        stopListeningForBackground()
        fileObserver = nil           // a file replaced meanwhile is opened again on the way back
        PlaybackPositions.shared.playerLeft(self)
    }

    /// Hears when a video file is replaced under the same name (see `VideoFileChanges`).
    private func listenForFileChanges() {
        guard fileObserver == nil else { return }
        fileObserver = NotificationObserver(name: VideoFileChanges.notification, object: nil) { @Sendable [weak self] in
            let target = self
            Task { @MainActor in
                target?.fileMayHaveChanged()
            }
        }
    }

    private func fileMayHaveChanged() {
        guard let url, VideoFileChanges.revision(of: url) != fileRevision else { return }
        reopenReplacedFile()
    }

    /// The file was replaced under the same name (a smaller copy of it): a new player opens it
    /// and carries on from the same place — playing if it was playing.
    private func reopenReplacedFile() {
        guard let current = url else { return }
        let carryOn = isPlaying || resumeWhenAllowed
        recordPosition()
        url = nil                    // so `load` makes a new player for the same address
        load(current)
        if carryOn { applyPlaying(true) }
    }

    /// The app went to the background: pause, remember the place, and don't carry on
    /// by itself later (a hidden pin's video never starts again on its own).
    func sceneWentToBackground() {
        resumeWhenAllowed = false
        if isPlaying { pausePlayback(onPurpose: true) }
    }

    /// Hears the app going to the background directly too: the views' scene phase
    /// may not reach pages that UIKit hosts (the pagers' pages), and a hidden pin's
    /// video must never keep playing. Listens only while the player is shown.
    private func listenForBackground() {
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationObserver(name: UIScene.didEnterBackgroundNotification, object: nil) { @Sendable [weak self] in
            let target = self
            Task { @MainActor in
                target?.sceneWentToBackground()
            }
        }
    }

    private func stopListeningForBackground() {
        backgroundObserver = nil     // removes it
    }

    // MARK: Loading

    /// Makes the player for `newURL` — once: the same address again changes nothing.
    private func load(_ newURL: URL) {
        guard newURL != url else { return }
        recordPosition()             // the video being replaced keeps its place
        PlaybackPositions.shared.playerLeft(self)
        SoundState.shared.setSounding(false, player: ObjectIdentifier(self))
        stopTimeUpdates()
        stopWatching()
        player?.pause()
        hideTask?.cancel()
        hideTask = nil

        url = newURL
        fileRevision = VideoFileChanges.revision(of: newURL)
        generation += 1
        isReady = false
        isPositioning = false
        failed = false
        isPlaying = false
        resumeWhenAllowed = false
        hasPlayedOrScrubbed = false
        lastSync = 0
        chaseTarget = nil
        chaseInFlight = false
        skipBase.forget()
        clock.reset()

        let fresh = AVPlayer(url: newURL)
        fresh.actionAtItemEnd = .none        // at the end it starts over (see `itemReachedEnd`)
        fresh.isMuted = !SoundState.shared.soundOn
        isMuted = fresh.isMuted
        prepareSpeed(of: fresh)
        player = fresh
        watch(fresh)
        controlsShown = false        // hidden until asked for (see `showsControlsWhileWaiting`)
    }

    private func watch(_ player: AVPlayer) {
        let current = generation
        // KVO and notifications may call from any thread: only plain values go over to the main actor.
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] _, _ in
            let target = self
            Task { @MainActor in
                target?.itemStatusChanged(generation: current)
            }
        }
        stateObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            let target = self
            Task { @MainActor in
                target?.playbackStateChanged(generation: current)
            }
        }
        endObserver = NotificationObserver(name: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem) { @Sendable [weak self] in
            let target = self
            Task { @MainActor in
                target?.itemReachedEnd(generation: current)
            }
        }
    }

    private func stopWatching() {
        statusObservation?.invalidate()
        stateObservation?.invalidate()
        statusObservation = nil
        stateObservation = nil
        endObserver = nil            // removes it
    }

    private func itemStatusChanged(generation reported: Int) {
        guard reported == generation, let player, let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            guard !isReady, !isPositioning else { return }
            isPositioning = true
            let length = CMTimeGetSeconds(item.duration)
            clock.duration = length.isFinite && length > 0 ? length : 0
            moveToStart(player)
        case .failed:
            failed = true
            isPlaying = false
            resumeWhenAllowed = false
            hideTask?.cancel()
            controlsShown = true
        default:
            break
        }
    }

    /// Starts where this video was left last, in any player (not when that is the very
    /// start or end). Only then does the picture show, so it never jumps.
    private func moveToStart(_ player: AVPlayer) {
        let positions = PlaybackPositions.shared
        let start = url.flatMap { positions.startPosition(for: $0) } ?? 0
        lastSync = positions.clock
        guard start > 0.5, start < clock.duration - 0.5 else {
            becameReady(generation: generation)
            return
        }
        clock.elapsed = start
        let current = generation
        player.seek(to: VideoPlaybackController.time(start), toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] _ in
            let target = self
            Task { @MainActor in
                target?.becameReady(generation: current)
            }
        }
    }

    private func becameReady(generation reported: Int) {
        guard reported == generation, !isReady, player != nil else { return }
        isReady = true
        isPositioning = false
        guard isPlaying else {
            if showsControlsWhileWaiting { showControls() }
            return
        }
        if mayPlay {
            beginPlaying()           // it was asked to play while it was still loading
        } else {
            isPlaying = false
            resumeWhenAllowed = true
        }
    }

    // MARK: Playing and pausing

    private func applyPlaying(_ wish: Bool) {
        if wish {
            guard mayPlay else {
                resumeWhenAllowed = true   // starts as soon as it may
                return
            }
            guard !isPlaying else { return }
            adoptNewerPosition()
            startPlayback()
        } else {
            resumeWhenAllowed = false
            if isPlaying { pausePlayback() }
        }
    }

    private func applyMayPlay(_ allowed: Bool) {
        mayPlay = allowed
        if allowed {
            adoptNewerPosition()
            showCarriedSound()
            if resumeWhenAllowed {
                resumeWhenAllowed = false
                startPlayback()
            }
        } else if isPlaying {
            pausePlayback()
            resumeWhenAllowed = true
        }
    }

    /// The play / pause button.
    func togglePlay() {
        showControls()
        if isPlaying {
            resumeWhenAllowed = false
            pausePlayback(onPurpose: true)
        } else if mayPlay {
            adoptNewerPosition()
            startPlayback()
        }
    }

    private func startPlayback() {
        guard player != nil, !failed else { return }
        resumeWhenAllowed = false
        isPlaying = true
        if isReady { beginPlaying() }   // otherwise it starts as soon as it is ready
    }

    private func beginPlaying() {
        guard let player, let url else { return }
        let positions = PlaybackPositions.shared
        if let handed = positions.handOver(to: self, url: url) {
            // Another big player was playing this video (it has just stopped): carry on from there.
            let target = handed < clock.duration - 0.5 ? handed : 0
            clock.elapsed = target
            player.seek(to: VideoPlaybackController.time(target), toleranceBefore: .zero, toleranceAfter: .zero)
            lastSync = positions.clock
        } else if clock.duration > 0 {
            let now = CMTimeGetSeconds(player.currentTime())
            if now.isFinite, now >= clock.duration - 0.1 {
                clock.elapsed = 0            // standing at the very end: start over
                player.seek(to: .zero)
            }
        }
        applyCarriedSound()
        player.play()
        startTimeUpdates()
        if !hasPlayedOrScrubbed {
            hasPlayedOrScrubbed = true
            positions.playerTookOver(url)
        }
        scheduleControlsHide()
    }

    /// Pauses and remembers the place (if it was playing). `onPurpose`: the person
    /// paused it (or left the app), so a player waiting to carry on with this video
    /// elsewhere stays paused too.
    private func pausePlayback(onPurpose: Bool = false) {
        let wasPlaying = isPlaying
        isPlaying = false
        player?.pause()
        stopTimeUpdates()
        SoundState.shared.setSounding(false, player: ObjectIdentifier(self))
        if wasPlaying {
            if let player, !clock.isScrubbing {
                let now = CMTimeGetSeconds(player.currentTime())
                if now.isFinite { clock.elapsed = max(0, now) }
            }
            recordPosition(onPurpose: onPurpose)
        }
        // Paused by hand: the controls show, so it can be started again. A pause because the page
        // scrolled away (or another player took over) leaves them hidden for the way back.
        if onPurpose { showControls() }
    }

    /// Another player takes this video over (see `PlaybackPositions.handOver`): stop here
    /// and remember the place. Returns the time it stopped at (nil when it wasn't playing).
    fileprivate func stopForHandOver() -> Double? {
        guard isPlaying, isReady, !clock.isScrubbing, let player else { return nil }
        let now = CMTimeGetSeconds(player.currentTime())
        resumeWhenAllowed = false
        pausePlayback()
        return now.isFinite ? max(0, now) : nil
    }

    /// The video reached its end: it starts over (videos loop), if it is still meant to play.
    private func itemReachedEnd(generation reported: Int) {
        guard reported == generation, let player, isPlaying, mayPlay, !clock.isScrubbing else { return }
        clock.elapsed = 0
        skipBase.forget()   // a skip still seeking is overtaken by the start over: the next one counts from 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// The player stopped by itself: at the end (it starts over), or something else took
    /// over (a phone call, another app's sound).
    private func playbackStateChanged(generation reported: Int) {
        guard reported == generation, isReady, isPlaying, !clock.isScrubbing, let player else { return }
        guard player.rate == 0, player.timeControlStatus == .paused else { return }
        let now = CMTimeGetSeconds(player.currentTime())
        if clock.duration > 0, now.isFinite, now >= clock.duration - 0.25 {
            itemReachedEnd(generation: reported)
            return
        }
        pausePlayback()
    }

    // MARK: Sound

    /// Sound follows the one switch the person sets (`SoundState.soundOn`): before
    /// every play the mute switch follows it, and the audio session too.
    private func applyCarriedSound() {
        guard let player else { return }
        let muted = !SoundState.shared.soundOn
        if player.isMuted != muted { player.isMuted = muted }
        isMuted = muted
        if !muted { SoundState.shared.gridSoundPinID = nil }   // one video with sound at a time
        SoundState.shared.setSounding(!muted, player: ObjectIdentifier(self))
    }

    /// A grid card got the sound: go quiet (the sound switch stays on for the next video).
    fileprivate func quietForCard() {
        guard let player, !player.isMuted else { return }
        player.isMuted = true
        isMuted = true
        SoundState.shared.setSounding(false, player: ObjectIdentifier(self))
    }

    /// A paused player shows the sound its next play will have.
    private func showCarriedSound() {
        guard let player, !isPlaying else { return }
        let muted = !SoundState.shared.soundOn
        if player.isMuted != muted { player.isMuted = muted }
        isMuted = muted
    }

    /// The speaker button: sound on or off for every video from now on (until turned
    /// off again). Sound on also starts a paused video (you want to hear it).
    func toggleMute() {
        guard let player else { return }
        showControls()
        setMuted(!player.isMuted, startingIfPaused: true)
    }

    /// The volume was turned up while this video is muted (see `VolumeButtonWatcher`): sound on, by
    /// the very same path as the speaker button, so the switch every video follows
    /// (`SoundState.soundOn`) and the speaker on the bar agree. Louder is not "play": a paused
    /// video stays paused. The bar shows for a moment, so the speaker can be seen changing.
    func unmuteForVolume() {
        guard let player, player.isMuted else { return }
        showControls()
        setMuted(false, startingIfPaused: false)
    }

    /// The one place sound goes on or off for a player: the player itself, what the bar shows, the
    /// switch every other video follows, and the audio session. (The speaker button and a turn
    /// of the volume both come through here, so they can never disagree.)
    /// `startingIfPaused`: turning sound on also starts a video that is paused.
    private func setMuted(_ muted: Bool, startingIfPaused: Bool) {
        guard let player else { return }
        player.isMuted = muted
        isMuted = muted
        SoundState.shared.soundOn = !muted
        if !muted { SoundState.shared.gridSoundPinID = nil }   // one video with sound at a time
        SoundState.shared.setSounding(!muted && isPlaying, player: ObjectIdentifier(self))
        if !muted, startingIfPaused, !isPlaying, mayPlay {
            adoptNewerPosition()
            startPlayback()
        }
    }

    // MARK: Speed

    /// The speed the screen wants (1 when it has no say: the pin page, the original viewer).
    private var wantedRate: Float { handle?.rate ?? 1 }

    /// A new player starts at the speed the screen wants, so a speed carries on from one video
    /// to the next in Quick Look. `defaultRate` is what `play()` starts at: pausing and playing
    /// again keeps the speed. At any speed other than 1× — slower (0.25×) or faster (5×) — the sound
    /// is kept at its own pitch with `.spectral`, the only good-quality choice that covers both
    /// (`.timeDomain` only works between 0.5× and 2×, so it would drop the sound at 0.25× and 3×).
    private func prepareSpeed(of player: AVPlayer) {
        let rate = wantedRate
        player.defaultRate = rate
        if rate != 1 { player.currentItem?.audioTimePitchAlgorithm = .spectral }
    }

    /// The speed the screen wants changed (⋯ › Speed, a hold, a lock). It plays at the new speed from
    /// now on; the rate itself is only set while playing, because setting it on a paused player
    /// would start it.
    func speedChanged() {
        guard let player else { return }
        prepareSpeed(of: player)
        let rate = wantedRate
        guard isPlaying, isReady, !clock.isScrubbing, player.rate != 0, player.rate != rate else { return }
        player.rate = rate
    }

    // MARK: Positions

    /// Remembers where this video is now, for every player (previews follow).
    private func recordPosition(onPurpose: Bool = false) {
        guard hasPlayedOrScrubbed, let url, let player else { return }
        var seconds = clock.isScrubbing ? clock.elapsed : CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite else { return }
        if clock.duration > 0, seconds >= clock.duration - 0.5 { seconds = 0 }   // at the end: next time from the start
        lastSync = PlaybackPositions.shared.recordFromPlayer(max(0, seconds), for: url, onPurpose: onPurpose)
    }

    /// Another player stopped this video elsewhere since this one last looked:
    /// continue from there. Only while paused (a playing player is the news itself).
    /// If it was paused there on purpose, this one no longer carries on by itself either.
    private func adoptNewerPosition() {
        guard isReady, !isPlaying, !clock.isScrubbing, let url, let player else { return }
        let positions = PlaybackPositions.shared
        guard let found = positions.newerPosition(for: url, than: lastSync) else { return }
        lastSync = positions.clock
        if found.onPurpose { resumeWhenAllowed = false }
        let newer = found.seconds
        let target = newer > 0.5 && newer < clock.duration - 0.5 ? newer : 0
        clock.elapsed = target
        player.seek(to: VideoPlaybackController.time(target), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Time

    private func startTimeUpdates() {
        guard timeObserver == nil, let player else { return }
        let current = generation
        timeObserver = player.addPeriodicTimeObserver(forInterval: VideoPlaybackController.time(0.1), queue: .main) { @Sendable [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            let target = self
            Task { @MainActor in
                target?.timePassed(seconds, generation: current)
            }
        }
    }

    private func stopTimeUpdates() {
        if let token = timeObserver, let player {
            player.removeTimeObserver(token)
        }
        timeObserver = nil
    }

    private func timePassed(_ seconds: Double, generation reported: Int) {
        guard reported == generation, isReady, !clock.isScrubbing, seconds.isFinite else { return }
        let shown = clock.duration > 0 ? min(max(0, seconds), clock.duration) : max(0, seconds)
        if abs(shown - clock.elapsed) >= 0.05 { clock.elapsed = shown }
    }

    // MARK: Scrubbing

    func beginScrub(at fraction: Double) {
        guard isReady, player != nil, clock.duration > 0, !clock.isScrubbing else { return }
        clock.isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        if isPlaying { player?.pause() }   // the button keeps showing Pause: it plays on after
        hideTask?.cancel()
        hideTask = nil
        controlsShown = true
        scrub(to: fraction)
    }

    /// While the finger moves: quick seeks near the spot, one at a time.
    func scrub(to fraction: Double) {
        guard clock.isScrubbing else { return }
        let seconds = clock.duration * min(max(fraction, 0), 1)
        clock.elapsed = seconds
        chaseTarget = seconds
        if !chaseInFlight { sendChaseSeek() }
    }

    /// The finger lifted: an exact seek, the place is remembered, and it plays on if it was playing.
    func endScrub(at fraction: Double) {
        guard clock.isScrubbing else { return }
        clock.isScrubbing = false
        chaseTarget = nil
        seekByHand(to: clock.duration * min(max(fraction, 0), 1), resume: wasPlayingBeforeScrub)
    }

    /// VoiceOver's swipe up or down on the scrub bar: a few seconds on or back.
    func step(by seconds: Double) {
        guard isReady, !clock.isScrubbing, clock.duration > 0 else { return }
        seekByHand(to: clock.elapsed + seconds, resume: isPlaying)
    }

    /// The skip buttons, the arrow keys and a double tap: `seconds` on (or back, when negative), never
    /// before the start and never to the very end (see `VideoSkip.target`). It keeps playing or paused
    /// as it was. The buttons and keys show the controls; a double tap passes `showingControls: false`,
    /// because the number over the picture is its answer — the bar would only be in the way (and a
    /// bar that is already showing stays, and gets its three seconds again). Says whether it skipped:
    /// a video that is still loading, or can't be played, can't.
    @discardableResult
    func skip(by seconds: Double, showingControls: Bool = true) -> Bool {
        guard isReady, !failed, !clock.isScrubbing, clock.duration > 0 else { return false }
        if showingControls { showControls() }
        let start = skipBase.base ?? clock.elapsed
        let target = VideoSkip.target(from: start, by: seconds, duration: clock.duration)
        skipBase.base = target
        seekByHand(to: target, resume: isPlaying)
        return true
    }

    /// The video is paused and ready: its frame can be made the thumbnail.
    var canGrabFrame: Bool { isReady && !isPlaying && !failed && player != nil }

    /// Where a paused video stands, for "Use this frame as thumbnail" (nil when it isn't ready).
    var currentSeconds: Double? {
        guard isReady, clock.elapsed.isFinite else { return nil }
        return max(0, clock.elapsed)
    }

    private func seekByHand(to seconds: Double, resume: Bool) {
        guard let player, let url else { return }
        let target = min(max(0, seconds), clock.duration)
        clock.elapsed = target
        let current = generation
        let number = skipBase.began()
        player.seek(to: VideoPlaybackController.time(target), toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] _ in
            let controller = self
            Task { @MainActor in
                controller?.handSeekEnded(number, generation: current)
            }
        }
        if !hasPlayedOrScrubbed {
            hasPlayedOrScrubbed = true
            PlaybackPositions.shared.playerTookOver(url)
        }
        lastSync = PlaybackPositions.shared.recordFromPlayer(target, for: url)
        if resume {
            if mayPlay {
                applyCarriedSound()
                player.play()
                startTimeUpdates()
            } else {
                isPlaying = false
                stopTimeUpdates()
                resumeWhenAllowed = true
            }
        }
        scheduleControlsHide()
    }

    /// A seek started by hand (skip, scrub's end, VoiceOver) came to its end, finished or cut short.
    /// `SkipBase` ignores one that a newer seek by hand overtook (the newer one is what counts), and
    /// lets go of the base when the latest one ends — even cut short by the video starting over.
    private func handSeekEnded(_ number: Int, generation reported: Int) {
        guard reported == generation else { return }
        skipBase.ended(number)
    }

    private func sendChaseSeek() {
        guard let player, let target = chaseTarget, clock.isScrubbing,
              player.currentItem?.status == .readyToPlay else {
            chaseInFlight = false
            return
        }
        chaseTarget = nil
        chaseInFlight = true
        let current = generation
        let slack = VideoPlaybackController.time(0.1)
        player.seek(to: VideoPlaybackController.time(target), toleranceBefore: slack, toleranceAfter: slack) { @Sendable [weak self] _ in
            let controller = self
            Task { @MainActor in
                controller?.chaseSeekFinished(generation: current)
            }
        }
    }

    private func chaseSeekFinished(generation reported: Int) {
        guard reported == generation else { return }
        chaseInFlight = false
        if clock.isScrubbing, chaseTarget != nil { sendChaseSeek() }
    }

    // MARK: Controls

    /// A tap on the picture shows or hides the controls (with VoiceOver on they stay).
    func toggleControls() {
        if controlsShown, !UIAccessibility.isVoiceOverRunning {
            hideTask?.cancel()
            hideTask = nil
            controlsShown = false
        } else {
            showControls()
        }
    }

    private func showControls() {
        controlsShown = true
        scheduleControlsHide()
    }

    /// While playing, the controls fade out 3 seconds after the last touch; while paused they stay.
    private func scheduleControlsHide() {
        hideTask?.cancel()
        hideTask = nil
        guard isPlaying, !clock.isScrubbing, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, self.isPlaying, !self.clock.isScrubbing else { return }
            self.controlsShown = false
        }
    }
}

/// The player is what a tap on the picture acts on (`toggleControls`, `skip(by:showingControls:)`).
extension VideoPlaybackController: TapSkipTarget {}

// MARK: - A video file replaced under the same name

/// Tells every player that a video file was replaced under the same name — Settings › iCloud & storage ›
/// "Convert existing videos…" puts the smaller copy in the old one's place — so each player
/// showing it (the big ones and the grids' previews) opens it again, instead of playing on from
/// the old copy. It counts, per file, how often it was replaced while the app runs; a player
/// compares that with the count when it opened the file.
@MainActor
enum VideoFileChanges {
    static let notification = Notification.Name("PinBoardVideoFileReplaced")
    private static var replacements: [String: Int] = [:]

    /// `url`'s file was just replaced.
    static func replaced(_ url: URL) {
        replacements[url.path, default: 0] += 1
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// How often `url`'s file was replaced so far.
    static func revision(of url: URL) -> Int {
        replacements[url.path] ?? 0
    }
}

/// A NotificationCenter observation that ends by itself when this object goes away
/// (with the player that owns it), so none is left behind.
final class NotificationObserver {
    private let token: NSObjectProtocol

    init(name: Notification.Name, object: AnyObject?, handler: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { _ in
            handler()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

// MARK: - The picture

/// The video picture: a view whose layer is an AVPlayerLayer, fitted on black.
/// It takes no touches (taps go to the SwiftUI view around it).
struct VideoPlayerSurface: UIViewRepresentable {
    var player: AVPlayer?

    func makeUIView(context: Context) -> VideoPlayerLayerView {
        let view = VideoPlayerLayerView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: VideoPlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

@MainActor
final class VideoPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Shown instead of the picture when a video can't be read.
struct VideoFailureNote: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text("This video can't be played.")
                .font(.callout)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding()
    }
}

// MARK: - The controls

/// The controls along the bottom of a player, on a shade that fades up from black:
/// play/pause, the time played, the scrub bar, the time left, sound, and (when
/// `onExpand` is set) the expand button. On a narrow player the scrub bar gets a
/// row of its own above the buttons. (The scrub bar itself, `VideoScrubBar`, and the
/// time text are in VideoControls.swift.)
struct VideoControlBar: View {
    /// Narrower than this (after the insets): two rows.
    static let compactWidth: CGFloat = 520
    /// The player keeps this much free at its top, below `controlsInsets.top`
    /// (Quick Look's ✕ and ⋯).
    static let topClearance: CGFloat = 64

    /// How much height the buttons and scrub bar take (without the shade above them).
    static func usedHeight(compact: Bool, bottomInset: CGFloat) -> CGFloat {
        rowsHeight(compact: compact) + bottomInset + 8
    }

    /// The buttons' rows: one of 44 points, or (narrow) the scrub bar's 36 above the buttons' 44.
    private static func rowsHeight(compact: Bool) -> CGFloat {
        compact ? 36 + 44 : 44
    }

    @ObservedObject var controller: VideoPlaybackController
    @ObservedObject var clock: VideoPlaybackClock
    var tint: Color
    var insets: EdgeInsets
    var compact: Bool
    /// The most height the controls and their shade may take.
    var room: CGFloat
    /// The expand button's action (nil = no button).
    var onExpand: (() -> Void)?

    var body: some View {
        let rows = VideoControlBar.rowsHeight(compact: compact)
        // The shade fades in above the buttons, but never reaches into the free top.
        let fade = min(28, max(0, room - rows - insets.bottom - 8))
        VStack(spacing: 0) {
            if compact {
                HStack(spacing: 8) {
                    elapsedLabel
                    VideoScrubBar(controller: controller, clock: clock, tint: tint, height: 36)
                    remainingLabel
                }
                .padding(.horizontal, 8)
                HStack(spacing: 0) {
                    playButton
                    Spacer(minLength: 0)
                    muteButton
                    expandButton
                }
            } else {
                HStack(spacing: 6) {
                    playButton
                    elapsedLabel
                    VideoScrubBar(controller: controller, clock: clock, tint: tint, height: 44)
                    remainingLabel
                    muteButton
                    expandButton
                }
            }
        }
        .padding(.leading, insets.leading + 8)
        .padding(.trailing, insets.trailing + 8)
        .padding(.bottom, insets.bottom + 8)
        .padding(.top, fade)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .opacity(controller.controlsShown ? 1 : 0)
        .allowsHitTesting(controller.controlsShown)
        .animation(.easeInOut(duration: 0.25), value: controller.controlsShown)
    }

    private var playButton: some View {
        Button {
            controller.togglePlay()
        } label: {
            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
    }

    private var muteButton: some View {
        Button {
            controller.toggleMute()
        } label: {
            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(controller.isMuted ? "Turn sound on" : "Turn sound off")
    }

    /// Opens the video large (the pin page: in Quick Look, where you can swipe on
    /// through the feed and ⋯ has the pin's actions). Sound and place carry over.
    @ViewBuilder
    private var expandButton: some View {
        if let onExpand {
            Button {
                onExpand()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Open in Quick Look")
        }
    }

    private var elapsedLabel: some View {
        Text(VideoTimeText.text(clock.elapsed))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)   // the scrub bar reads the time out
    }

    private var remainingLabel: some View {
        Text(VideoTimeText.remaining(elapsed: clock.elapsed, duration: clock.duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
