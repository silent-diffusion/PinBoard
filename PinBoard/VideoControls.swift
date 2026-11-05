//
//  VideoControls.swift  —  PinBoard
//
//  What sits on top of PinBoard's own video player (VideoPlayer.swift) besides its bar along
//  the bottom:
//    • the big play / pause button in the middle with skip back and skip forward either side
//      (how far: Settings › Videos, `AppSettings.videoSkipSeconds`);
//    • in Quick Look, the speed: holding a finger on the video for a second plays it at 2× until
//      the finger lifts, dragging down while holding locks 2× (again to unlock), and ⋯ › Speed
//      picks 0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×, 3× or 5×;
//    • "Use this frame as thumbnail" for a paused video;
//    • two quick taps on the picture skip back or forward, YouTube-style, with the sum ("+30")
//      shown over the tapped half (`TapSkipState`, `TapSkipDriver`, `TapSkipOverlay`);
//    • turning the volume up unmutes the video in front (`VolumeButtonWatcher`);
//    • at the end of the file, the scrub bar's slider in the bar along the bottom (the bar
//      itself is in VideoPlayer.swift).
//  The rules (how far a skip goes, what a hold or a double tap does) are small pure types at the
//  top of the file, so they can be tested without a screen; the gestures themselves can only be
//  tried on a device. `VideoPlayerHandle` is how a screen around a player (Quick Look, the pin
//  page) talks to it.
//

import SwiftUI
import AVFoundation
import UIKit
import Foundation

// MARK: - Skipping (pure rules)

/// How the skip buttons behave. No player in here: just the arithmetic and the names.
enum VideoSkip {
    /// The steps Settings offers.
    static let choices: [Int] = [5, 10, 15, 20, 30]
    /// What a stored value that is not one of the choices turns into.
    static let standard = 10
    /// A skip forward never lands closer than this to the very end. At the very end a video
    /// starts over, and a button that only skips must not do that by accident.
    static let endMargin: Double = 0.1

    /// The steps that have a symbol of their own in SF Symbols (`gobackward.10`). There is no
    /// `gobackward.20`, so 20 gets the plain arrow with the number written over it.
    private static let numbered: Set<Int> = [5, 10, 15, 30]

    /// A stored step turned into one of the choices.
    static func cleaned(_ seconds: Int) -> Int {
        choices.contains(seconds) ? seconds : standard
    }

    /// Where a skip of `delta` seconds (negative = back) from `current` lands in a video that is
    /// `duration` long: never before the start, never past `duration − endMargin`. A length that
    /// is not known (0) only keeps the start.
    static func target(from current: Double, by delta: Double, duration: Double) -> Double {
        let start = current.isFinite ? current : 0
        let wanted = max(0, start + delta)
        guard duration.isFinite, duration > 0 else { return wanted }
        return min(wanted, max(0, duration - endMargin))
    }

    /// The picture on a skip button: a symbol name, and the number to write over it when the
    /// symbol has none of its own.
    struct Symbol: Equatable {
        let name: String
        let number: String?
    }

    static func symbol(forward: Bool, seconds: Int) -> Symbol {
        let base = forward ? "goforward" : "gobackward"
        if numbered.contains(seconds) {
            return Symbol(name: "\(base).\(seconds)", number: nil)
        }
        return Symbol(name: base, number: "\(seconds)")
    }

    /// What VoiceOver says: "Skip back 10 seconds".
    static func label(forward: Bool, seconds: Int) -> String {
        forward ? "Skip forward \(seconds) seconds" : "Skip back \(seconds) seconds"
    }
}

/// Where the next skip starts from. Skip buttons can be tapped faster than a seek finishes, and the
/// time shown may still be the old one then, so a skip remembers where it is going (`base`) until the
/// last seek made by hand has come to its end. Only the latest seek counts: an earlier one that a
/// newer one cut short says nothing. A seek that something else cut short (the video starting over)
/// still ends the wait — it used to leave a stale base behind for one more skip.
struct SkipBase: Equatable {
    /// Where the skip in flight is going; nil when no seek by hand is under way.
    var base: Double? = nil
    private var latest = 0

    /// A seek by hand starts. Returns its number, to report back to `ended(_:)`.
    mutating func began() -> Int {
        latest += 1
        return latest
    }

    /// The seek with this number came to its end, finished or cut short. Only the latest one clears.
    mutating func ended(_ number: Int) {
        if number == latest { base = nil }
    }

    /// The video starts over, or another video opens: nothing is in flight any more.
    mutating func forget() {
        base = nil
    }
}

// MARK: - Speed (pure rules)

/// The speeds a video can play at in Quick Look, and how they are written.
enum VideoSpeed {
    /// ⋯ › Speed offers these: three slower than normal (for watching a move or a recipe step
    /// closely), normal, and five faster.
    static let choices: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 5]
    /// Holding a finger on the video (or locking it) plays at this, whatever was chosen.
    static let holdRate: Float = 2

    /// "0.25", "1.5" or "2": a whole number without the ".0", and the others without a long tail
    /// of digits (a `Float` such as 0.1 would otherwise be written 0.1 or 0.10000000149).
    /// Two decimals are enough for every speed the menu offers.
    private static func number(_ rate: Float) -> String {
        guard rate.isFinite else { return "1" }   // never happens; a whole-number cast of NaN would crash
        if rate == rate.rounded() { return "\(Int(rate))" }
        var text = String(format: "%.2f", Double(rate))
        while text.hasSuffix("0") { text.removeLast() }   // 1.50 -> 1.5, 0.50 -> 0.5
        return text
    }

    /// "1×", "1.5×" — for menus and the little pill.
    static func label(_ rate: Float) -> String {
        number(rate) + "×"
    }

    /// What VoiceOver says for the pill: "Playing at 2 times speed".
    static func spoken(_ rate: Float) -> String {
        "Playing at \(number(rate)) times speed"
    }

    /// The speed to play at: the hold's while a finger holds (or the lock is on), else the chosen one.
    static func rate(chosen: Float, fast: Bool) -> Float {
        fast ? holdRate : chosen
    }
}

/// What holding a finger on a video in Quick Look does, as a small state machine. The touch view
/// reports what the finger does (held long enough, moved down by so much, lifted); this says
/// what changes, and nothing else. A hold that lasts `holdSeconds` plays at 2× until the finger
/// lifts. While holding, dragging down by `dragDistance` points turns the lock on (2× stays after
/// the finger lifts); a hold and drag down while it is on turns it off. One drag, one change.
struct HoldSpeedState: Equatable, Sendable {
    /// How long a finger must rest on the video before it counts as a hold.
    static let holdSeconds: Double = 1
    /// How far (points) the finger may wander before that second is up — more is a swipe, not a hold.
    static let stillRadius: Double = 10
    /// How far down (points) a holding finger must drag to lock or unlock.
    static let dragDistance: Double = 40

    /// What the caller should do about what just happened.
    enum Change: Equatable, Sendable {
        case none
        case speedUp      // the hold began: fast
        case slowDown     // the hold ended (no lock): back to the chosen speed
        case locked       // dragged down: 2× stays
        case unlocked     // dragged down while locked: back to the chosen speed, even with the finger still down
    }

    /// A finger has been resting long enough and is still down.
    private(set) var isHolding = false
    /// 2× stays on after the finger lifts.
    private(set) var isLocked = false
    /// This hold's drag already locked or unlocked (it does that once).
    private var dragUsed = false
    /// This hold unlocked: normal speed until the finger lifts, although it is still down.
    private var unlockedByDrag = false

    /// Playing at 2× now.
    var isFast: Bool { isLocked || (isHolding && !unlockedByDrag) }

    /// The finger stayed down for `holdSeconds` without wandering.
    @discardableResult
    mutating func began() -> Change {
        guard !isHolding else { return .none }
        isHolding = true
        dragUsed = false
        unlockedByDrag = false
        return isLocked ? .none : .speedUp
    }

    /// The finger is now `distance` points below where the hold began (negative = above).
    @discardableResult
    mutating func moved(down distance: Double) -> Change {
        guard isHolding, !dragUsed, distance >= HoldSpeedState.dragDistance else { return .none }
        dragUsed = true
        if isLocked {
            isLocked = false
            unlockedByDrag = true
            return .unlocked
        }
        isLocked = true
        return .locked
    }

    /// The finger lifted (or something took the touch away).
    @discardableResult
    mutating func ended() -> Change {
        guard isHolding else { return .none }
        let wasFast = isFast
        isHolding = false
        dragUsed = false
        unlockedByDrag = false
        return (wasFast && !isLocked) ? .slowDown : .none
    }

    /// A speed picked in ⋯ › Speed wins over the lock.
    @discardableResult
    mutating func clearLock() -> Change {
        guard isLocked else { return .none }
        isLocked = false
        return isHolding ? .none : .slowDown
    }

    /// Everything off (Quick Look closes).
    @discardableResult
    mutating func reset() -> Change {
        let wasFast = isFast
        self = HoldSpeedState()
        return wasFast ? .slowDown : .none
    }
}

// MARK: - Double tap to skip (pure rules)

/// What a tap on the video does, as a small state machine — the way the YouTube app does it.
///
/// A tap is a *single* tap unless a second one follows within `doubleTapSeconds`; only then do the
/// controls show or hide (so that answer comes a little later than the tap itself: it had to wait
/// and see). A second tap that comes soon enough *skips* instead — back when it lands on the left
/// half of the video, forward on the right half, by the step chosen in Settings — and starts a run:
/// every further tap within `runSeconds` of the one before skips again, in the direction of its own
/// half. The number on the screen adds up while the taps stay on the same half ("+10", "+20",
/// "+30") and starts again at one step when the other half is tapped.
///
/// There is no clock in here: the times are plain seconds that the caller passes in, so the exact
/// sequences can be tested without waiting. The two limits never overlap and leave no gap: a gap of
/// less than the limit pairs the taps, a gap of the limit or more does not.
struct TapSkipState: Equatable, Sendable {
    /// A second tap this soon after a first one is a double tap. Without one, the first was a single tap.
    static let doubleTapSeconds: Double = 0.3
    /// Once skipping has begun, a tap this soon after the one before skips again. The run — and the
    /// number on the screen — ends when this long has passed since the last tap.
    static let runSeconds: Double = 0.5

    /// Which half of the video a tap landed on.
    enum Side: Equatable, Sendable {
        case left, right

        /// The half a tap at `x` is on, for a video whose middle is at `middle` (both in the same
        /// units, measured from the same edge). A tap right in the middle counts as the right half.
        init(x: Double, middle: Double) {
            self = x < middle ? .left : .right
        }

        /// The left half skips back, the right half skips forward.
        var direction: Direction {
            self == .left ? .back : .forward
        }
    }

    /// Which way a skip goes.
    enum Direction: Equatable, Sendable {
        case back, forward
    }

    /// What the caller should do about a tap.
    enum Outcome: Equatable, Sendable {
        /// A first tap: wait `doubleTapSeconds`; if no second tap comes, show or hide the controls then.
        case waitForSecond
        /// Skip once by the step, in `direction`. `total` is how many steps the run has added up to
        /// on this side (1, 2, 3 …): the number to show is `total` times the step.
        case skip(direction: Direction, total: Int)
    }

    /// When the latest tap landed (nil: none yet).
    private var lastTap: Double? = nil
    /// The latest tap was a first tap that nobody has answered yet.
    private var singleTapPending = false
    /// The way the run goes now (nil: no run).
    private var runDirection: Direction? = nil
    /// How many steps the run has added up to on its current side.
    private var runSteps = 0

    /// A tap landed at `time` on `side`. See `Outcome`.
    @discardableResult
    mutating func tap(at time: Double, side: Side) -> Outcome {
        let direction = side.direction
        if let last = lastTap {
            let gap = time - last
            if runDirection != nil, gap >= 0, gap < TapSkipState.runSeconds {
                return continueRun(at: time, direction: direction)
            }
            if singleTapPending, gap >= 0, gap < TapSkipState.doubleTapSeconds {
                return beginRun(at: time, direction: direction)
            }
        }
        // Not part of a double tap or a run: this is a new first tap, and an earlier run is over.
        runDirection = nil
        runSteps = 0
        singleTapPending = true
        lastTap = time
        return .waitForSecond
    }

    /// The second tap of a double tap: the first skip of a run.
    private mutating func beginRun(at time: Double, direction: Direction) -> Outcome {
        singleTapPending = false
        runDirection = direction
        runSteps = 1
        lastTap = time
        return .skip(direction: direction, total: 1)
    }

    /// A further tap of a run. The same side adds one more step; the other side starts its own count.
    private mutating func continueRun(at time: Double, direction: Direction) -> Outcome {
        if runDirection == direction {
            runSteps += 1
        } else {
            runDirection = direction
            runSteps = 1
        }
        lastTap = time
        return .skip(direction: direction, total: runSteps)
    }

    /// Is the first tap that is waiting for a second one due now? True once (and only once) when
    /// `doubleTapSeconds` have passed since it with no second tap: show or hide the controls now.
    /// Call it again before the next tap too, in case the timer that normally asks was late.
    mutating func singleTapDue(at time: Double) -> Bool {
        guard singleTapPending, let last = lastTap, time - last >= TapSkipState.doubleTapSeconds else { return false }
        singleTapPending = false
        return true
    }

    /// Is the run over at `time`? True when there is none, or when `runSeconds` have passed since
    /// its last tap: the number on the screen fades.
    func runIsOver(at time: Double) -> Bool {
        guard runDirection != nil, let last = lastTap else { return true }
        return time - last >= TapSkipState.runSeconds
    }

    /// Forget everything (the player goes away, or another video opens).
    mutating func reset() {
        self = TapSkipState()
    }
}

/// The number that shows over the half of the video that was tapped: "+10", "+20", "−10".
enum TapSkipLabel {
    /// A real minus sign (U+2212), not a hyphen: it is as wide and as high as the plus beside it.
    static let minus = "\u{2212}"
    static let plus = "+"

    /// `steps` skips of `secondsPerStep` each, in `direction`: four taps of a 10-second step show
    /// three skips, "+30". Negative numbers count as none.
    static func text(direction: TapSkipState.Direction, steps: Int, secondsPerStep: Int) -> String {
        let sign = direction == .forward ? plus : minus
        let total = max(0, steps) * max(0, secondsPerStep)
        return "\(sign)\(total)"
    }
}

// MARK: - Volume up unmutes the video in front

/// Hears the volume being turned up (the buttons on the side of the iPad, or the slider in Control
/// Center) and says so. `VideoPlayerHandle` owns one: while the video in front is playing, a rise in
/// the volume gives that video its sound if it is muted — someone who turns the volume up wants to hear it.
///
/// It looks at `AVAudioSession.outputVolume` through key-value observing, which iOS reports only
/// while the app's audio session is active. Two limits follow, and the ASBUILT says them too: with
/// the volume already at the top the system reports no change (so there is nothing to see), and a
/// paused video's session may be inactive, so nothing is heard then. Only a rise counts; turning
/// the volume down does nothing.
///
/// Two safeguards were added after the review, for things only a device can show. Each is one
/// named constant below, so either can be switched off with one word if the iPad shows a problem:
///  • `wakesAmbientSession` — a video that is muted plays in a quiet "ambient" audio session that
///    nothing may have activated (a muted player may not), and then no volume change is reported
///    at all. When that is the session in use, the watcher activates it before listening.
///  • `routeChangeQuietSeconds` — connecting AirPods or AirPlay changes the output, and the new
///    output has its own volume, which can look like a rise. Rises are ignored for a moment after
///    the route changes, so a muted video is never unmuted by a connection nobody pressed a button for.
@MainActor
final class VolumeButtonWatcher {
    /// A rise smaller than this is noise, not a button (the buttons move it by a sixteenth).
    nonisolated static let minimumRise: Float = 0.001

    /// Safeguard 1. True: `start()` activates the audio session when it is the quiet kind (ambient,
    /// mixing with other apps), so the system reports volume changes. Never done for the "playback"
    /// session — a playing video has activated that one itself. Set to `false` to take it away (then
    /// the session is left exactly as the players leave it).
    nonisolated static let wakesAmbientSession = true

    /// Safeguard 2. A rise within this many seconds after the audio route changed is not taken as a
    /// button press. Set to `0` to take it away.
    nonisolated static let routeChangeQuietSeconds: Double = 1

    /// What to do when the volume went up.
    var onIncrease: (@MainActor () -> Void)? = nil

    private var observation: NSKeyValueObservation? = nil
    /// Hears the audio route change (AirPods connecting, AirPlay, a cable) for as long as the watcher
    /// lives — also while it is not listening for the volume, because a connection made just before a
    /// video starts playing can still make the first report look like a rise.
    private var routeObserver: NotificationObserver? = nil
    /// When the route last changed, on the system's uptime clock (nil: not since the watcher was made).
    private var routeChangedAt: Double? = nil

    init() {
        // The system may post this from any thread: only the time it arrived is carried to the main actor.
        routeObserver = NotificationObserver(name: AVAudioSession.routeChangeNotification, object: nil) { @Sendable [weak self] in
            let when = ProcessInfo.processInfo.systemUptime
            let target = self
            Task { @MainActor in
                target?.routeChanged(at: when)
            }
        }
    }

    /// It is listening now.
    var isWatching: Bool { observation != nil }

    /// Starts listening (again, with no effect, when it already is).
    func start() {
        guard observation == nil else { return }
        wakeAmbientSession()
        // The system may call this from any thread: only the two plain numbers, and the time the
        // report arrived, go over to the main actor.
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { @Sendable [weak self] _, change in
            let when = ProcessInfo.processInfo.systemUptime
            let before = change.oldValue
            let after = change.newValue
            let target = self
            Task { @MainActor in
                target?.volumeChanged(from: before, to: after, at: when)
            }
        }
    }

    /// Stops listening.
    func stop() {
        observation?.invalidate()
        observation = nil
    }

    /// Activates the audio session when it is the quiet kind (safeguard 1). A failure is ignored: the
    /// watcher then hears what it would have heard before.
    private func wakeAmbientSession() {
        guard VolumeButtonWatcher.wakesAmbientSession else { return }
        let session = AVAudioSession.sharedInstance()
        guard VolumeButtonWatcher.needsWakingSession(category: session.category, options: session.categoryOptions) else { return }
        try? session.setActive(true)
    }

    /// The audio route changed at `time` (safeguard 2 remembers it).
    func routeChanged(at time: Double = ProcessInfo.processInfo.systemUptime) {
        routeChangedAt = time
    }

    /// The volume went from `before` to `after`; the report arrived at `time` (the system's uptime
    /// clock; the tests give their own). A report that arrives after `stop()` (it hops over to the
    /// main actor first) is ignored, so a video that has just been paused is not unmuted — and so is
    /// a rise that comes just after the audio route changed (`isSettling`).
    func volumeChanged(from before: Float?, to after: Float?, at time: Double = ProcessInfo.processInfo.systemUptime) {
        guard isWatching, VolumeButtonWatcher.wentUp(from: before, to: after) else { return }
        guard !VolumeButtonWatcher.isSettling(at: time, routeChangedAt: routeChangedAt) else { return }
        onIncrease?()
    }

    /// The rule: only a clear rise counts. Without both numbers there is nothing to compare.
    nonisolated static func wentUp(from before: Float?, to after: Float?) -> Bool {
        guard let before, let after else { return false }
        return after > before + minimumRise
    }

    /// Safeguard 1's rule: only the quiet session — "ambient" that mixes with other apps' sound — is
    /// activated here. Activating "playback" (or the solo ambient session, which silences other apps)
    /// is not this watcher's business.
    nonisolated static func needsWakingSession(category: AVAudioSession.Category,
                                               options: AVAudioSession.CategoryOptions) -> Bool {
        category == .ambient && options.contains(.mixWithOthers)
    }

    /// Safeguard 2's rule: is a report at `time` too close after the route changed at `routeChangedAt`
    /// to be a button press? Only the moment after counts: a report that came before the change is
    /// left alone, and with `quietSeconds` at 0 nothing is ever ignored.
    nonisolated static func isSettling(at time: Double, routeChangedAt: Double?,
                                       quietSeconds: Double = VolumeButtonWatcher.routeChangeQuietSeconds) -> Bool {
        guard let routeChangedAt else { return false }
        let since = time - routeChangedAt
        return since >= 0 && since < quietSeconds
    }
}

// MARK: - The handle a screen keeps on its player

/// How the screen around a player (Quick Look, the pin page) talks to it, and it to the screen:
///  • which video is "in front" (Quick Look mounts the players of the neighbours too), whether it
///    is paused (so "Use this frame as thumbnail" can show) and where it stands;
///  • in Quick Look only (`speedControls`): the speed chosen in ⋯, and the hold with its lock.
///    Every player of that screen plays at `rate`, so a speed carries on from one video to the
///    next. The pin page has no speed controls: its player always plays at 1×.
/// One handle per screen, given to every `VideoPlayerView` of it (`handle:`).
@MainActor
final class VideoPlayerHandle: ObservableObject {
    /// This screen has ⋯ › Speed and the hold gesture.
    let hasSpeedControls: Bool

    /// The speed picked in ⋯ › Speed (1 = normal).
    @Published private(set) var chosenSpeed: Float = 1
    /// What the finger on the video is doing (see `HoldSpeedState`).
    @Published private(set) var hold = HoldSpeedState()
    /// The video in front is paused and ready: its frame can be used as the thumbnail.
    @Published private(set) var canUseFrame = false

    /// The player of the video in front (not owned).
    private(set) weak var front: VideoPlaybackController?
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    /// Listens for the volume going up while the video in front plays (see `VolumeButtonWatcher`).
    /// Not private only so that the tests can stand in for the system's volume reports.
    let volume = VolumeButtonWatcher()

    init(speedControls: Bool = false) {
        hasSpeedControls = speedControls
        volume.onIncrease = { [weak self] in
            self?.volumeWentUp()
        }
    }

    /// The volume was turned up: the video in front gets its sound if it is muted. Only the video in
    /// front — the neighbours Quick Look keeps ready are paused, and follow the switch when they play.
    private func volumeWentUp() {
        guard let front, front.isMuted else { return }
        front.unmuteForVolume()
    }

    /// The volume is being watched (the video in front is playing).
    var isWatchingVolume: Bool { volume.isWatching }

    /// The speed every player of this screen should play at now.
    var rate: Float {
        guard hasSpeedControls else { return 1 }
        return VideoSpeed.rate(chosen: chosenSpeed, fast: hold.isFast)
    }

    // Speed

    /// ⋯ › Speed. Turns the lock off: what was just picked is what you get.
    func chooseSpeed(_ speed: Float) {
        guard hasSpeedControls, VideoSpeed.choices.contains(speed) else { return }
        if chosenSpeed != speed { chosenSpeed = speed }
        update { (state: inout HoldSpeedState) -> HoldSpeedState.Change in state.clearLock() }
    }

    /// The finger has rested on the video for a second.
    func holdBegan() {
        impact.prepare()
        update { (state: inout HoldSpeedState) -> HoldSpeedState.Change in state.began() }
    }

    /// The holding finger is now `distance` points below where it began.
    func holdMoved(down distance: Double) {
        update { (state: inout HoldSpeedState) -> HoldSpeedState.Change in state.moved(down: distance) }
    }

    /// The finger lifted.
    func holdEnded() {
        update { (state: inout HoldSpeedState) -> HoldSpeedState.Change in state.ended() }
    }

    /// Back to 1×, no hold, no lock (Quick Look closes). The volume is not watched any more.
    func reset() {
        if chosenSpeed != 1 { chosenSpeed = 1 }
        update { (state: inout HoldSpeedState) -> HoldSpeedState.Change in state.reset() }
        volume.stop()
    }

    /// Runs one step of the hold's state machine and publishes only a real change. A lock or an
    /// unlock is felt: a tap on the hand.
    private func update(_ step: (inout HoldSpeedState) -> HoldSpeedState.Change) {
        var next = hold
        let change = step(&next)
        if next != hold { hold = next }
        if change == .locked || change == .unlocked { impact.impactOccurred() }
    }

    // The video in front

    /// A player says it is (or is no longer) the video in front. (The layer over the picture calls
    /// this; the tests do too.)
    func frontChanged(_ controller: VideoPlaybackController, isFront: Bool) {
        if isFront {
            front = controller
        } else if front === controller {
            front = nil
        }
        refresh()
    }

    /// Looks again at whether the video in front is paused and ready, and whether it plays (the
    /// volume is listened to only then: that is when the audio session is awake).
    func refresh() {
        let can = front?.canGrabFrame ?? false
        if can != canUseFrame { canUseFrame = can }
        if front?.isPlaying == true {
            volume.start()
        } else {
            volume.stop()
        }
    }

    /// Where the video in front stands, in seconds (nil when nothing is ready).
    func currentSeconds() -> Double? {
        front?.currentSeconds
    }

    /// Play or pause the video in front (the keyboard).
    func togglePlay() {
        front?.togglePlay()
    }

    /// Skip the video in front forward or back (the keyboard).
    func skip(forward: Bool, seconds: Int) {
        let step = Double(VideoSkip.cleaned(seconds))
        front?.skip(by: forward ? step : -step)
    }
}

// MARK: - The buttons in the middle

/// How big the buttons in the middle are, for the room a player has.
enum VideoCentreSize: Equatable {
    case large, compact, hidden

    /// The play button's diameter.
    var playSide: CGFloat {
        switch self {
        case .large: return 72
        case .compact: return 48
        case .hidden: return 0
        }
    }

    /// The skip buttons' touch area (44 points at least: the owner's rule).
    var skipSide: CGFloat {
        switch self {
        case .large: return 56
        case .compact: return 44
        case .hidden: return 0
        }
    }

    var spacing: CGFloat { self == .large ? 24 : 12 }
    var playGlyph: CGFloat { self == .large ? 32 : 22 }
    var skipGlyph: CGFloat { self == .large ? 34 : 28 }

    /// All three buttons side by side.
    var width: CGFloat { skipSide * 2 + playSide + spacing * 2 }

    /// Half the height the buttons take.
    var halfHeight: CGFloat { max(playSide, skipSide) / 2 }

    /// The biggest size that fits in a player `width` × `height` whose top `topUsed` points and
    /// bottom `bottomUsed` points belong to other things (✕ and ⋯, the bar). The buttons sit in
    /// the middle of the player, so what matters is the room above and below the middle. Too
    /// little room: no buttons at all (the bar has its own play button).
    static func fit(width: CGFloat, height: CGFloat, topUsed: CGFloat, bottomUsed: CGFloat) -> VideoCentreSize {
        let above = height / 2 - topUsed
        let below = height / 2 - bottomUsed
        let half = min(above, below)
        let candidates: [VideoCentreSize] = [.large, .compact]
        for size in candidates where size.halfHeight + 4 <= half && size.width <= width {
            return size
        }
        return .hidden
    }
}

/// The big play / pause button with skip back and skip forward either side. It shows and hides
/// with the bar (a tap on the video), so the two are always together.
struct VideoCentreControls: View {
    @ObservedObject var controller: VideoPlaybackController
    var skipSeconds: Int
    var size: VideoCentreSize

    var body: some View {
        HStack(spacing: size.spacing) {
            skipButton(forward: false)
            playButton
            skipButton(forward: true)
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
                .font(.system(size: size.playGlyph, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size.playSide, height: size.playSide)
                .background(Color.black.opacity(0.45), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)   // the bar's play button says it for VoiceOver; one is enough
    }

    /// Skip back or forward. The number of seconds is in the symbol (10, 15…) or written over the
    /// plain arrow (20); VoiceOver hears it either way.
    private func skipButton(forward: Bool) -> some View {
        let symbol = VideoSkip.symbol(forward: forward, seconds: skipSeconds)
        return Button {
            controller.skip(by: forward ? Double(skipSeconds) : -Double(skipSeconds))
        } label: {
            ZStack {
                Image(systemName: symbol.name)
                    .font(.system(size: size.skipGlyph, weight: .regular))
                if let number = symbol.number {
                    Text(number)
                        .font(.system(size: size.skipGlyph * 0.36, weight: .bold, design: .rounded))
                        .offset(y: size.skipGlyph * 0.04)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.6), radius: 3)
            .frame(width: size.skipSide, height: size.skipSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!controller.isReady)
        .opacity(controller.isReady ? 1 : 0.4)
        .accessibilityLabel(VideoSkip.label(forward: forward, seconds: skipSeconds))
    }
}

// MARK: - Double tap to skip (what a player does about it)

/// What a tap on the picture needs from a player: show or hide the controls, and skip. The player
/// (`VideoPlaybackController`) is one; so is a stand-in made by the tests.
@MainActor
protocol TapSkipTarget: AnyObject {
    func toggleControls()
    /// Skips by `seconds` (negative = back). Says whether it did: a video still loading can't.
    @discardableResult
    func skip(by seconds: Double, showingControls: Bool) -> Bool
}

/// Carries out `TapSkipState` for one player: it keeps the state, waits the short times (0.3 s for
/// a second tap, 0.5 s for the end of a run) and says what the number over the picture is and
/// whether it shows. Each new tap cancels the waiting that the one before started.
@MainActor
final class TapSkipDriver: ObservableObject {
    /// The number over the picture and the half it sits over.
    struct Shown: Equatable {
        let direction: TapSkipState.Direction
        let text: String
    }

    /// What was shown last (it stays while it fades out).
    @Published private(set) var shown: Shown? = nil
    /// The number is on the screen. False starts its fade.
    @Published private(set) var isLabelVisible = false

    /// The timers wait this much longer than the rules say. The clock read after waking must be past
    /// the limit (two clocks, never quite the same), or a tap that is due would be answered never.
    nonisolated static let slackSeconds: Double = 0.02

    private var state = TapSkipState()
    private var singleTask: Task<Void, Never>? = nil
    private var runTask: Task<Void, Never>? = nil

    /// The time in seconds, from a clock that only goes forward (a change of the date can't upset it).
    nonisolated static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    nonisolated private static func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// The picture was tapped on `side`. `seconds` is the step from Settings.
    func tapped(_ side: TapSkipState.Side, on target: any TapSkipTarget, seconds: Int) {
        let now = TapSkipDriver.now()
        // A single tap whose time ran out before its timer did still gets its answer first.
        if state.singleTapDue(at: now) { target.toggleControls() }
        stopTimers()
        switch state.tap(at: now, side: side) {
        case .waitForSecond:
            waitForSecondTap(on: target)
        case .skip(let direction, let total):
            skipped(direction, total: total, seconds: seconds, on: target)
            waitForRunEnd()
        }
    }

    /// The player went away (or another video opened, or the page left the front): nothing is
    /// waited for any more and the number goes. No late toggle comes out of a tap nobody can see.
    func cancel() {
        stopTimers()
        state.reset()
        if isLabelVisible { isLabelVisible = false }
    }

    private func stopTimers() {
        singleTask?.cancel()
        singleTask = nil
        runTask?.cancel()
        runTask = nil
    }

    /// A first tap: if no second one comes in time, it was a single tap — show or hide the controls.
    private func waitForSecondTap(on target: any TapSkipTarget) {
        let wait = TapSkipState.doubleTapSeconds + TapSkipDriver.slackSeconds
        singleTask = Task { @MainActor [weak self, weak target] in
            try? await Task.sleep(nanoseconds: TapSkipDriver.nanoseconds(wait))
            guard let self, !Task.isCancelled else { return }
            if self.state.singleTapDue(at: TapSkipDriver.now()) {
                target?.toggleControls()
            }
        }
    }

    /// One skip: the player jumps and the number is shown (only when the jump really happened).
    private func skipped(_ direction: TapSkipState.Direction, total: Int, seconds: Int, on target: any TapSkipTarget) {
        let step = Double(VideoSkip.cleaned(seconds))
        let delta = direction == .forward ? step : -step
        guard target.skip(by: delta, showingControls: false) else { return }
        let text = TapSkipLabel.text(direction: direction, steps: total, secondsPerStep: VideoSkip.cleaned(seconds))
        shown = Shown(direction: direction, text: text)
        isLabelVisible = true
    }

    /// The run ends half a second after its last tap: the number fades.
    private func waitForRunEnd() {
        let wait = TapSkipState.runSeconds + TapSkipDriver.slackSeconds
        runTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: TapSkipDriver.nanoseconds(wait))
            guard let self, !Task.isCancelled else { return }
            if self.state.runIsOver(at: TapSkipDriver.now()) {
                self.isLabelVisible = false
            }
        }
    }
}

/// The number over the half that was tapped: large, bold, rounded, white with a soft shadow. It
/// appears at once and fades out over a third of a second once the run is over. It takes no touches
/// (the taps go through to the player) and VoiceOver ignores it.
struct TapSkipOverlay: View {
    @ObservedObject var driver: TapSkipDriver
    /// The player's own insets: the halves are those of the part of the picture that is in view
    /// (beside Quick Look's info panel, say), the same halves the taps are told apart by.
    var insets: EdgeInsets

    var body: some View {
        HStack(spacing: 0) {
            half(.back)
            half(.forward)
        }
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One half of the picture, with the number in its middle when it is this half's.
    private func half(_ direction: TapSkipState.Direction) -> some View {
        ZStack {
            Color.clear
            if let shown = driver.shown, shown.direction == direction {
                label(shown.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
            .opacity(driver.isLabelVisible ? 1 : 0)
            .animation(fade, value: driver.isLabelVisible)
    }

    /// Fading out takes a third of a second; appearing takes no time at all (a tap should be answered now).
    private var fade: Animation? {
        driver.isLabelVisible ? nil : Animation.easeOut(duration: 0.3)
    }
}

// MARK: - The layer over the picture

/// What every player with a handle has on top of its picture: it tells the handle that this is the
/// video in front (and whether it is paused), keeps the player's speed right, and — in Quick Look —
/// holds the touch area for the hold gesture and the little speed pill.
struct VideoHandleLayer: View {
    @ObservedObject var handle: VideoPlayerHandle
    @ObservedObject var controller: VideoPlaybackController
    /// This is the video the screen is about (Quick Look mounts the neighbours' players too).
    var isFront: Bool
    /// The pill sits below this (the safe area's top), level with ✕ and ⋯.
    var topInset: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if handle.hasSpeedControls {
                touchArea
                speedPill
            }
        }
        .onAppear { handle.frontChanged(controller, isFront: isFront) }
        .onDisappear { handle.frontChanged(controller, isFront: false) }
        .onChange(of: isFront) { _, now in handle.frontChanged(controller, isFront: now) }
        .onChange(of: controller.isPlaying) { handle.refresh() }
        .onChange(of: controller.isReady) { handle.refresh() }
        .onChange(of: controller.failed) { handle.refresh() }
        .onChange(of: handle.rate) { controller.speedChanged() }
    }

    /// A finger can hold only on the video in front, and only while it plays: a paused video has
    /// nothing to speed up (and the touch then goes to the taps and swipes as it always did).
    private var touchArea: some View {
        VideoHoldTouchArea(enabled: isFront && controller.isReady && controller.isPlaying,
                           onBegan: { handle.holdBegan() },
                           onMoved: { (down: Double) in handle.holdMoved(down: down) },
                           onEnded: { handle.holdEnded() })
    }

    /// "2×" (or whatever speed is on) in a small pill at the top, while the speed is not normal.
    /// It takes no touches.
    @ViewBuilder
    private var speedPill: some View {
        let rate = handle.rate
        if rate != 1 {
            Text(VideoSpeed.label(rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, topInset + 14)
                .allowsHitTesting(false)
                .accessibilityLabel(VideoSpeed.spoken(rate))
        }
    }
}

/// The hold gesture's touch area. UIKit, not SwiftUI, for three reasons: its long-press recognizer
/// only starts on a finger that stays still (one that moves is a swipe and fails at once), it keeps
/// reporting the finger after the second is up, and every other recognizer can be made to wait for
/// it — so a finger that has held is never also a page swipe or a swipe to close.
struct VideoHoldTouchArea: UIViewRepresentable {
    var enabled: Bool
    var onBegan: () -> Void
    /// How many points the finger is below where the hold began.
    var onMoved: (Double) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> VideoHoldTouchView {
        let view = VideoHoldTouchView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ view: VideoHoldTouchView, context: Context) {
        configure(view)
    }

    static func dismantleUIView(_ view: VideoHoldTouchView, coordinator: ()) {
        view.finish()   // the player went away under a holding finger: the hold ends here
    }

    private func configure(_ view: VideoHoldTouchView) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.isHoldEnabled = enabled
    }
}

/// A clear view over the picture with one long-press recognizer (1 second, still finger).
/// Every other recognizer waits for it to fail: a finger that moves fails it at once (so swipes
/// start as they always did), one that lifts early fails it too (so a tap is a tap), and one that
/// stays still for a second keeps it, which means no page swipe and no tap can come out of that
/// touch. Off (no touches taken at all) unless the video in front is playing.
@MainActor
final class VideoHoldTouchView: UIView, UIGestureRecognizerDelegate {
    var isHoldEnabled = false {
        didSet {
            if isHoldEnabled != oldValue {
                press?.isEnabled = isHoldEnabled
                isUserInteractionEnabled = isHoldEnabled
            }
        }
    }
    var onBegan: () -> Void = {}
    var onMoved: (Double) -> Void = { _ in }
    var onEnded: () -> Void = {}
    private var press: UILongPressGestureRecognizer? = nil
    private var isHolding = false
    private var startY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: self, action: #selector(VideoHoldTouchView.pressChanged(_:)))
        press.minimumPressDuration = HoldSpeedState.holdSeconds
        press.allowableMovement = CGFloat(HoldSpeedState.stillRadius)
        press.cancelsTouchesInView = false
        press.delegate = self
        press.isEnabled = isHoldEnabled
        isUserInteractionEnabled = isHoldEnabled
        addGestureRecognizer(press)
        self.press = press
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pressChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard isHoldEnabled, !isHolding else { return }
            isHolding = true
            startY = gesture.location(in: self).y
            onBegan()
        case .changed:
            guard isHolding else { return }
            onMoved(Double(gesture.location(in: self).y - startY))
        case .ended, .cancelled, .failed:
            finish()
        default:
            break
        }
    }

    /// Ends a hold: the finger lifted, the touch was taken away, or the view went away under it.
    func finish() {
        guard isHolding else { return }
        isHolding = false
        onEnded()
    }

    /// Every other recognizer (the pager's scrolling, Quick Look's swipes, SwiftUI's taps) waits
    /// for this one to fail.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Menu items

/// ⋯ › Speed ▸ 0.25× · 0.5× · 0.75× · 1× · 1.25× · 1.5× · 2× · 3× · 5× (a checkmark on the chosen
/// one). Shows only where the screen has speed controls (Quick Look).
struct VideoSpeedMenu: View {
    @ObservedObject var handle: VideoPlayerHandle

    private var choice: Binding<Float> {
        Binding(get: { handle.chosenSpeed },
                set: { (speed: Float) in handle.chooseSpeed(speed) })
    }

    var body: some View {
        if handle.hasSpeedControls {
            Menu {
                Picker("Speed", selection: choice) {
                    ForEach(VideoSpeed.choices, id: \.self) { (speed: Float) in
                        Text(VideoSpeed.label(speed)).tag(speed)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Speed", systemImage: "speedometer")
            }
        }
    }
}

/// The words of the thumbnail toasts.
enum VideoThumbnailText {
    static let item = "Use this frame as thumbnail"
    static let changed = "Thumbnail changed"
    static let failed = "Couldn't change the thumbnail"
}

/// "Use this frame as thumbnail": a menu item that shows while the video in front is paused. It
/// makes the frame on screen the video's poster (the grids, exports and other apps show it too),
/// and says how it went. For a player's own ⋯ menu (Quick Look's has it; the pin page's does too).
struct UseFrameAsThumbnailButton: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    let pinID: UUID
    @ObservedObject var handle: VideoPlayerHandle

    var body: some View {
        if handle.canUseFrame {
            Button {
                useFrame()
            } label: {
                Label(VideoThumbnailText.item, systemImage: "photo")
            }
        }
    }

    private func useFrame() {
        guard let seconds = handle.currentSeconds() else { return }
        let id = pinID
        Task { @MainActor in
            let changed = await store.setPoster(for: id, frameAt: seconds)
            if changed {
                importFlow.flash(VideoThumbnailText.changed, symbol: "checkmark.circle")
            } else {
                importFlow.flash(VideoThumbnailText.failed, symbol: "exclamationmark.triangle")
            }
        }
    }
}

// MARK: - The scrub bar (the slider in the bar along the bottom)

/// True while a finger is on any player's scrub bar. Quick Look's swipes read it
/// and leave such a drag alone (it only scrubs).
@MainActor
enum PlayerScrubbing {
    static private(set) var isActive = false
    /// Scrub bars with a finger on them right now.
    private static var fingers = 0

    fileprivate static func began() {
        fingers += 1
        isActive = true
    }

    fileprivate static func ended() {
        fingers = max(0, fingers - 1)
        isActive = fingers > 0
    }
}

/// "0:07", "12:05", "1:02:03" for the controls.
enum VideoTimeText {
    /// Whole seconds, rounded down (the time played).
    static func text(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        let secondsPart = rest < 10 ? "0\(rest)" : "\(rest)"
        if hours > 0 {
            let minutesPart = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(minutesPart):\(secondsPart)"
        }
        return "\(minutes):\(secondsPart)"
    }

    /// The time left, rounded up: "-1:05".
    static func remaining(elapsed: Double, duration: Double) -> String {
        let left = duration.isFinite && elapsed.isFinite ? max(0, duration - elapsed - 0.001) : 0
        return "-" + text(left.rounded(.up))
    }
}

/// The scrub bar: a thin track filled up to where the video is, and a knob.
/// A finger anywhere on it moves there at once and drags from there.
struct VideoScrubBar: View {
    @ObservedObject var controller: VideoPlaybackController
    @ObservedObject var clock: VideoPlaybackClock
    var tint: Color
    var height: CGFloat

    /// Room at each end, so the knob stays inside.
    static let inset: CGFloat = 10

    private var fraction: Double {
        clock.duration > 0 ? min(max(clock.elapsed / clock.duration, 0), 1) : 0
    }

    /// VoiceOver's step: a tenth of the video, 1 to 10 seconds.
    private var step: Double {
        max(1, min(10, clock.duration / 10))
    }

    var body: some View {
        let knob: CGFloat = clock.isScrubbing ? 20 : 12
        GeometryReader { box in
            let track = max(1, box.size.width - VideoScrubBar.inset * 2)
            let filled = track * CGFloat(fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: track, height: 4)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, filled), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .offset(x: filled - knob / 2)
            }
            .padding(.horizontal, VideoScrubBar.inset)
            .frame(width: box.size.width, height: box.size.height, alignment: .leading)
        }
        .frame(height: height)
        .frame(minWidth: 60)
        .overlay {
            VideoScrubTouchArea(inset: VideoScrubBar.inset,
                                enabled: controller.isReady && clock.duration > 0 && controller.controlsShown,
                                onBegan: { controller.beginScrub(at: $0) },
                                onChanged: { controller.scrub(to: $0) },
                                onEnded: { controller.endScrub(at: $0) })
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(VideoTimeText.text(clock.elapsed)) of \(VideoTimeText.text(clock.duration))")
        .accessibilityAdjustableAction { direction in
            controller.step(by: direction == .increment ? step : -step)
        }
    }
}

/// The scrub bar's touch area, in UIKit so that a finger landing on the bar belongs
/// to the bar alone (see `VideoScrubTouchView`).
struct VideoScrubTouchArea: UIViewRepresentable {
    var inset: CGFloat
    var enabled: Bool
    var onBegan: (Double) -> Void
    var onChanged: (Double) -> Void
    var onEnded: (Double) -> Void

    func makeUIView(context: Context) -> VideoScrubTouchView {
        let view = VideoScrubTouchView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ view: VideoScrubTouchView, context: Context) {
        configure(view)
    }

    static func dismantleUIView(_ view: VideoScrubTouchView, coordinator: ()) {
        view.finish(at: nil)   // the bar went away under a finger: the scrub ends here
    }

    private func configure(_ view: VideoScrubTouchView) {
        view.inset = inset
        view.isScrubEnabled = enabled
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

/// Its touch-and-hold recognizer has no delay, so it starts the moment a finger
/// lands (a tap jumps there, a drag scrubs). Every other recognizer — the pagers'
/// scrolling, Quick Look's swipes, SwiftUI's gestures — must wait for it to fail,
/// so a drag that starts on the bar never pages and never closes anything.
/// `PlayerScrubbing.isActive` is true from the start to the end of each scrub.
@MainActor
final class VideoScrubTouchView: UIView, UIGestureRecognizerDelegate {
    var inset: CGFloat = 10
    /// Off until the video is ready and while the controls are hidden: then the bar takes
    /// no touches at all (they fall through, so a tap there shows the controls).
    var isScrubEnabled = false {
        didSet {
            if isScrubEnabled != oldValue {
                press?.isEnabled = isScrubEnabled
                isUserInteractionEnabled = isScrubEnabled
            }
        }
    }
    var onBegan: (Double) -> Void = { _ in }
    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }
    private var press: UILongPressGestureRecognizer? = nil
    private var isScrubbing = false
    private var lastFraction: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: self, action: #selector(VideoScrubTouchView.pressChanged(_:)))
        press.minimumPressDuration = 0                        // starts the moment a finger lands
        press.allowableMovement = .greatestFiniteMagnitude    // and follows it anywhere
        press.delegate = self
        press.isEnabled = isScrubEnabled
        isUserInteractionEnabled = isScrubEnabled
        addGestureRecognizer(press)
        self.press = press
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pressChanged(_ gesture: UILongPressGestureRecognizer) {
        let spot = share(at: gesture.location(in: self))
        switch gesture.state {
        case .began:
            guard isScrubEnabled, !isScrubbing else { return }
            isScrubbing = true
            lastFraction = spot
            PlayerScrubbing.began()
            onBegan(spot)
        case .changed:
            guard isScrubbing else { return }
            lastFraction = spot
            onChanged(spot)
        case .ended, .cancelled:
            finish(at: spot)
        case .failed:
            finish(at: nil)
        default:
            break
        }
    }

    /// Ends a scrub: the finger lifted, or the bar went away under it.
    func finish(at fraction: Double?) {
        guard isScrubbing else { return }
        isScrubbing = false
        PlayerScrubbing.ended()
        onEnded(fraction ?? lastFraction)
    }

    /// How far along the track a point is: 0 at its start, 1 at its end.
    private func share(at point: CGPoint) -> Double {
        let track = max(1, bounds.width - inset * 2)
        return Double(min(max((point.x - inset) / track, 0), 1))
    }

    // (No gestureRecognizerShouldBegin here: UIView has its own method of that name.
    // A bar that is off simply has its recognizer switched off.)

    /// Every other recognizer waits for this one to fail — which it does not while a finger is on the bar.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
