//
//  VideoScrubbing.swift  —  PinBoard
//
//  The scrub bar in the bar along the bottom of PinBoard's own player (VideoPlayer.swift), and
//  how a finger or a mouse moves it — the way Apple's own player does:
//    • a tap (a finger that lifts without moving) jumps to the tapped spot, on lift;
//    • a drag does nothing until the finger has moved `ScrubTouchState.slop` points; from then on
//      it is a scrub that moves the playhead *from where it is* by the distance the finger travels
//      (the bar's whole width is the whole video). It never jumps to where the finger landed, and
//      lifting after a scrub does not jump either;
//    • while scrubbing, the further the finger is above (or below) the bar, the slower the scrub:
//      full, half, quarter and fine speed (`ScrubSpeed`), with a small label such as
//      "Half-speed scrubbing" above the bar. No haptics.
//  On a Mac ("Designed for iPad") a click and a mouse or trackpad drag arrive as touches and follow
//  the same rules. The rules are a small pure type (`ScrubTouchState`), so they can be tested
//  without a screen.
//

import SwiftUI
import UIKit
import Foundation

// MARK: - Scrubbing (pure rules)

/// How fast a scrub moves the playhead, by how far the finger is from the bar (in points, up or
/// down; 0 while it is on the bar). Each band is `bandHeight` points tall.
enum ScrubSpeed: Equatable, Sendable {
    case full, half, quarter, fine

    /// The height of each band: on the bar and up to 50 pt off it is full speed, then half up to
    /// 100 pt, quarter up to 150 pt, and fine beyond.
    static let bandHeight: Double = 50

    init(distanceFromBar distance: Double) {
        let bands = distance.isFinite ? max(0, distance) / ScrubSpeed.bandHeight : 0
        switch bands {
        case ..<1: self = .full
        case ..<2: self = .half
        case ..<3: self = .quarter
        default: self = .fine
        }
    }

    /// How much of the finger's travel reaches the playhead.
    var factor: Double {
        switch self {
        case .full: return 1
        case .half: return 0.5
        case .quarter: return 0.25
        case .fine: return 0.1
        }
    }

    /// The label above the bar (none at full speed).
    var label: String? {
        switch self {
        case .full: return nil
        case .half: return "Half-speed scrubbing"
        case .quarter: return "Quarter-speed scrubbing"
        case .fine: return "Fine scrubbing"
        }
    }
}

/// One touch on the scrub bar, from landing to lifting. Positions are in points in the bar's own
/// coordinates; places on the video are fractions, 0 (start) to 1 (end).
///
/// Landing does nothing. A finger that lifts without having moved more than `slop` is a tap: it
/// jumps to where it lifted. Once it moves further, it scrubs: the scrub starts from where the video
/// is now, and every move after that adds the finger's sideways travel since the move before,
/// divided by the track's width and slowed by the `ScrubSpeed` of that moment. Adding up the steps
/// (rather than measuring from where the finger landed) means changing speed never makes the
/// playhead jump.
struct ScrubTouchState: Equatable, Sendable {
    /// A finger that moves this far (in any direction) is dragging, not tapping: the usual touch slop.
    static let slop: Double = 8

    /// What the caller should do.
    enum Action: Equatable, Sendable {
        case none
        /// A scrub begins. The playhead stays where it is (`from`).
        case begin(from: Double)
        /// The scrub moved the playhead to `to`, at `speed`.
        case move(to: Double, speed: ScrubSpeed)
        /// A tap: jump to `to`.
        case jump(to: Double)
        /// The scrub ended at `at` (no jump: it is where the scrub left it).
        case end(at: Double)
    }

    /// Where the finger landed (nil: no finger).
    private var downX: Double? = nil
    private var downY: Double = 0
    /// The finger's last sideways position during a scrub.
    private var lastX: Double = 0
    /// Moving more than the slop has made this touch a scrub.
    private(set) var isScrubbing = false
    /// Where the scrub has the playhead.
    private(set) var fraction: Double = 0

    /// A finger landed. Nothing happens yet.
    mutating func down(x: Double, y: Double) {
        self = ScrubTouchState()
        downX = x
        downY = y
    }

    /// The finger moved to (`x`, `y`). `track` is the track's width, `distanceFromBar` how far the
    /// finger is above or below the bar, and `current` where the video is now (read only when a
    /// scrub begins).
    mutating func moved(x: Double, y: Double, track: Double, distanceFromBar: Double, current: Double) -> Action {
        guard let startX = downX else { return .none }
        if !isScrubbing {
            let dx = x - startX
            let dy = y - downY
            guard (dx * dx + dy * dy).squareRoot() > ScrubTouchState.slop else { return .none }
            isScrubbing = true
            fraction = ScrubTouchState.clamped(current)
            lastX = x
            return .begin(from: fraction)
        }
        let speed = ScrubSpeed(distanceFromBar: distanceFromBar)
        let width = max(1, track)
        fraction = ScrubTouchState.clamped(fraction + (x - lastX) / width * speed.factor)
        lastX = x
        return .move(to: fraction, speed: speed)
    }

    /// The finger lifted; `tapped` is the place under it (used only for a tap).
    mutating func up(tapped: Double) -> Action {
        defer { self = ScrubTouchState() }
        guard downX != nil else { return .none }
        return isScrubbing ? .end(at: fraction) : .jump(to: ScrubTouchState.clamped(tapped))
    }

    /// The touch was taken away (the bar went away, the system cancelled it): a scrub ends where it
    /// is; a tap that never finished does nothing.
    mutating func cancel() -> Action {
        defer { self = ScrubTouchState() }
        return isScrubbing ? .end(at: fraction) : .none
    }

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
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

/// The scrub bar: a thin track filled up to where the video is, and a knob. A tap jumps; a drag
/// scrubs from where the video is (see `ScrubTouchState`).
struct VideoScrubBar: View {
    @ObservedObject var controller: VideoPlaybackController
    @ObservedObject var clock: VideoPlaybackClock
    var tint: Color
    var height: CGFloat

    /// How fast the scrub in progress goes (for the label above the bar).
    @State private var speed: ScrubSpeed = .full

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
        .overlay(alignment: .top) { speedLabel }
        .overlay {
            VideoScrubTouchArea(inset: VideoScrubBar.inset,
                                enabled: controller.isReady && clock.duration > 0 && controller.controlsShown,
                                current: { clock.duration > 0 ? clock.elapsed / clock.duration : 0 },
                                onAction: act)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(VideoTimeText.text(clock.elapsed)) of \(VideoTimeText.text(clock.duration))")
        .accessibilityAdjustableAction { direction in
            controller.step(by: direction == .increment ? step : -step)
        }
    }

    /// "Half-speed scrubbing" and the like, just above the bar while a slow scrub is under way.
    @ViewBuilder
    private var speedLabel: some View {
        if clock.isScrubbing, let text = speed.label {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6), in: Capsule())
                .fixedSize()
                .offset(y: -30)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func act(_ action: ScrubTouchState.Action) {
        switch action {
        case .none:
            break
        case .begin:
            speed = .full
            controller.beginScrub()
        case .move(let to, let newSpeed):
            if speed != newSpeed { speed = newSpeed }
            controller.scrub(to: to)
        case .jump(let to):
            controller.jump(to: to)
        case .end(let at):
            speed = .full
            controller.endScrub(at: at)
        }
    }
}

/// The scrub bar's touch area, in UIKit so that a finger landing on the bar belongs
/// to the bar alone (see `VideoScrubTouchView`).
struct VideoScrubTouchArea: UIViewRepresentable {
    var inset: CGFloat
    var enabled: Bool
    /// Where the video is now, 0 to 1 (a scrub starts from here).
    var current: () -> Double
    var onAction: (ScrubTouchState.Action) -> Void

    func makeUIView(context: Context) -> VideoScrubTouchView {
        let view = VideoScrubTouchView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ view: VideoScrubTouchView, context: Context) {
        configure(view)
    }

    static func dismantleUIView(_ view: VideoScrubTouchView, coordinator: ()) {
        view.finish(cancelled: true, at: nil)   // the bar went away under a finger: the scrub ends here
    }

    private func configure(_ view: VideoScrubTouchView) {
        view.inset = inset
        view.isScrubEnabled = enabled
        view.current = current
        view.onAction = onAction
    }
}

/// Its touch-and-hold recognizer has no delay, so it owns the touch the moment a finger lands
/// (nothing visible happens then: `ScrubTouchState` decides between a tap and a scrub). Every other
/// recognizer — the pagers' scrolling, Quick Look's swipes, SwiftUI's gestures — must wait for it
/// to fail, so a drag that starts on the bar never pages and never closes anything.
/// `PlayerScrubbing.isActive` is true from landing to lifting.
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
    var current: () -> Double = { 0 }
    var onAction: (ScrubTouchState.Action) -> Void = { _ in }
    private var press: UILongPressGestureRecognizer? = nil
    private var state = ScrubTouchState()
    /// A finger is on the bar (from landing to lifting).
    private var isTouching = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: self, action: #selector(VideoScrubTouchView.pressChanged(_:)))
        press.minimumPressDuration = 0                        // owns the touch the moment a finger lands
        press.allowableMovement = .greatestFiniteMagnitude    // and follows it anywhere
        press.delegate = self
        press.isEnabled = isScrubEnabled
        isUserInteractionEnabled = isScrubEnabled
        addGestureRecognizer(press)
        self.press = press
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pressChanged(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard isScrubEnabled, !isTouching else { return }
            isTouching = true
            PlayerScrubbing.began()
            state.down(x: Double(point.x), y: Double(point.y))
        case .changed:
            guard isTouching else { return }
            onAction(state.moved(x: Double(point.x), y: Double(point.y),
                                 track: Double(trackWidth),
                                 distanceFromBar: distanceFromBar(point),
                                 current: current()))
        case .ended:
            finish(cancelled: false, at: point)
        case .cancelled, .failed:
            finish(cancelled: true, at: nil)
        default:
            break
        }
    }

    /// Ends the touch: the finger lifted (a tap jumps, a scrub ends where it is), or the touch was
    /// taken away (the bar went away under it).
    func finish(cancelled: Bool, at point: CGPoint?) {
        guard isTouching else { return }
        isTouching = false
        PlayerScrubbing.ended()
        if cancelled || point == nil {
            onAction(state.cancel())
        } else if let point {
            onAction(state.up(tapped: share(at: point)))
        }
    }

    private var trackWidth: CGFloat {
        max(1, bounds.width - inset * 2)
    }

    /// How far along the track a point is: 0 at its start, 1 at its end.
    private func share(at point: CGPoint) -> Double {
        Double(min(max((point.x - inset) / trackWidth, 0), 1))
    }

    /// How far above or below the bar a point is (0 on it).
    private func distanceFromBar(_ point: CGPoint) -> Double {
        if point.y < 0 { return Double(-point.y) }
        if point.y > bounds.height { return Double(point.y - bounds.height) }
        return 0
    }

    // (No gestureRecognizerShouldBegin here: UIView has its own method of that name.
    // A bar that is off simply has its recognizer switched off.)

    /// Every other recognizer waits for this one to fail — which it does not while a finger is on the bar.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
