//
//  CropEditor.swift  —  PinBoard
//
//  Cropping a picture: "Edit picture ▸ Crop…" in the pin menus (PinActions.swift)
//  opens this screen, full screen and dark like Photos' editor. The picture is
//  fitted on a black canvas with a crop rectangle over it: drag inside the rectangle
//  to move it, drag a corner (or the middle of a long enough side) to make it bigger
//  or smaller. What will be cut away is dimmed. The rectangle can have any shape
//  (Free) or a fixed one: Square, 4:3, 3:4, 16:9, 9:16 or the picture's own
//  (Original). "Crop" hands the rectangle to the store, which rewrites the picture
//  file; every screen showing the picture then loads it again (see
//  `Pin.pictureRevision`).
//
//  CropGeometry does all the arithmetic, as plain rules the harness tests: fitting
//  the picture, turning the rectangle from 0…1 of the picture into points on screen
//  and back, moving, resizing (never smaller than a tenth of the picture each way,
//  never off the picture, keeping the chosen shape), changing the shape, which drag
//  a finger's movement belongs to, and what VoiceOver says and does. The views only
//  draw the result and hand on the finger's movements.
//

import SwiftUI
#if canImport(Accessibility)   // AccessibilityNotification (the crop handles' spoken values) lives there
import Accessibility
#endif
import UIKit
import Foundation

// MARK: - The shapes a crop can have

/// The crop's shape, chosen under the picture.
enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free, square, fourThree, threeFour, sixteenNine, nineSixteen, original

    var id: String { rawValue }

    /// Its name in the picker.
    var name: String {
        switch self {
        case .free: return "Free"
        case .square: return "Square"
        case .fourThree: return "4:3"
        case .threeFour: return "3:4"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        case .original: return "Original"
        }
    }

    /// Width ÷ height, or nil for Free. `picture`: the picture's own size (for Original).
    func ratio(picture: CGSize) -> CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeFour: return 3.0 / 4.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        case .original:
            guard picture.width > 0, picture.height > 0 else { return nil }
            return picture.width / picture.height
        }
    }
}

// MARK: - The grips of the rectangle

/// A grip of the crop rectangle: a corner, or the middle of a side.
enum CropHandlePosition: Hashable, Sendable {
    case topLeading, top, topTrailing, trailing, bottomTrailing, bottom, bottomLeading, leading

    /// The four corners (always there).
    static let corners: [CropHandlePosition] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
    /// The middles of the four sides (only on sides long enough, see `CropGeometry.grips`).
    static let sides: [CropHandlePosition] = [.top, .trailing, .bottom, .leading]

    /// The side it moves across: -1 the left side, 1 the right side, 0 neither.
    var horizontal: Int {
        switch self {
        case .topLeading, .leading, .bottomLeading: return -1
        case .topTrailing, .trailing, .bottomTrailing: return 1
        case .top, .bottom: return 0
        }
    }

    /// The side it moves up and down: -1 the top, 1 the bottom, 0 neither.
    var vertical: Int {
        switch self {
        case .topLeading, .top, .topTrailing: return -1
        case .bottomLeading, .bottom, .bottomTrailing: return 1
        case .leading, .trailing: return 0
        }
    }

    var isCorner: Bool { horizontal != 0 && vertical != 0 }

    /// The grip across the rectangle from this one: it stays put while this one is dragged.
    var opposite: CropHandlePosition {
        switch self {
        case .topLeading: return .bottomTrailing
        case .top: return .bottom
        case .topTrailing: return .bottomLeading
        case .trailing: return .leading
        case .bottomTrailing: return .topLeading
        case .bottom: return .top
        case .bottomLeading: return .topTrailing
        case .leading: return .trailing
        }
    }

    /// Where the grip sits on `rect`.
    func point(on rect: CGRect) -> CGPoint {
        CGPoint(x: CropHandlePosition.coordinate(horizontal, low: rect.minX, high: rect.maxX),
                y: CropHandlePosition.coordinate(vertical, low: rect.minY, high: rect.maxY))
    }

    /// The low end, the high end, or the middle of one side of the rectangle.
    private static func coordinate(_ side: Int, low: CGFloat, high: CGFloat) -> CGFloat {
        if side < 0 { return low }
        if side > 0 { return high }
        return (low + high) / 2
    }
}

/// What a drag on the picture holds: the whole rectangle (to move it) or one grip (to resize it).
enum CropDrag: Hashable, Sendable {
    case move
    case resize(CropHandlePosition)
}

/// One drag on the canvas, from the moment the finger comes down: what it holds, the crop it
/// started from (0…1 of the picture) and where the finger came down (in the canvas's points).
/// Every movement of the finger is measured from that start. See `CropGeometry.dragSession`.
struct CropDragSession: Equatable {
    let held: CropDrag
    let startCrop: CGRect
    let startLocation: CGPoint
}

// MARK: - The arithmetic (plain rules; the harness tests them)

/// Every rectangle here is in one coordinate space where the picture fills `bounds` (or `frame`):
/// points on screen for the canvas, the picture's own size for a change of shape. A "unit" rect is
/// 0…1 of the picture's width and height, top-left origin — what the store's `cropImage` takes.
enum CropGeometry {
    /// The smallest a crop may be: this part of the picture's width, and of its height.
    static let minimumFraction: CGFloat = 0.1
    /// The whole picture, as a unit rect.
    nonisolated static var whole: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }
    /// How far from a grip a finger may start and still take hold of it (points).
    static let reach: CGFloat = 30
    /// A side shows its middle grip only when it is at least this long (points), so the grip
    /// never crowds the corners' grips.
    static let sideGripLength: CGFloat = 120
    /// How far VoiceOver's "Move left / right / up / down" moves the crop: this part of the picture.
    static let nudgeFraction: CGFloat = 0.1

    /// A tenth of the picture's width and of its height.
    nonisolated static func minimumSize(of bounds: CGRect) -> CGSize {
        CGSize(width: bounds.width * minimumFraction, height: bounds.height * minimumFraction)
    }

    /// The picture as large as it fits in `area`, in the middle of it (nothing for an empty size).
    nonisolated static func fittedFrame(for picture: CGSize, in area: CGRect) -> CGRect {
        guard picture.width > 0, picture.height > 0, area.width > 0, area.height > 0 else { return .zero }
        let scale = min(area.width / picture.width, area.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// A unit rect as a rectangle over the picture shown in `frame`.
    nonisolated static func viewRect(_ unit: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + unit.minX * frame.width, y: frame.minY + unit.minY * frame.height,
               width: unit.width * frame.width, height: unit.height * frame.height)
    }

    /// A rectangle over the picture shown in `frame` as a unit rect (kept within 0…1). An empty
    /// frame gives the whole picture.
    nonisolated static func unitRect(_ rect: CGRect, in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return whole }
        let raw = CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
                         width: rect.width / frame.width, height: rect.height / frame.height)
        return clampedUnit(raw)
    }

    /// A unit rect kept within 0…1 (rounding may leave it a hair outside).
    nonisolated static func clampedUnit(_ rect: CGRect) -> CGRect {
        let minX = min(max(rect.minX, 0), 1)
        let minY = min(max(rect.minY, 0), 1)
        let maxX = min(max(rect.maxX, minX), 1)
        let maxY = min(max(rect.maxY, minY), 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The crop takes (nearly) the whole picture: there is nothing to cut away.
    nonisolated static func isWhole(_ unit: CGRect) -> Bool {
        let slack: CGFloat = 0.005
        return unit.minX <= slack && unit.minY <= slack && unit.maxX >= 1 - slack && unit.maxY >= 1 - slack
    }

    /// `rect` moved by `delta`, stopping at the picture's edges (its size stays).
    nonisolated static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = inside(rect.minX + delta.width, length: width, low: bounds.minX, high: bounds.maxX)
        let y = inside(rect.minY + delta.height, length: height, low: bounds.minY, high: bounds.maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `rect` with one grip dragged to `point` while the grip across from it stays put: at least
    /// `minSize` (as far as the picture allows), never off the picture, and with the shape
    /// `aspect` (width ÷ height) when one is chosen. With a shape, a corner slides along the
    /// rectangle's diagonal to the point nearest the finger (in makes it smaller, out bigger, and
    /// the size never jumps); the middle of a side grows or shrinks the rectangle evenly on both
    /// sides the other way (moved back onto the picture where needed).
    nonisolated static func resized(_ rect: CGRect, dragging handle: CropHandlePosition, to point: CGPoint,
                                    aspect: CGFloat?, minSize: CGSize, in bounds: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else {
            return resizedFreely(rect, dragging: handle, to: point, minSize: minSize, in: bounds)
        }
        if handle.isCorner {
            return cornerKeepingShape(rect, dragging: handle, to: point, aspect: aspect, minSize: minSize, in: bounds)
        }
        return sideKeepingShape(rect, dragging: handle, to: point, aspect: aspect, minSize: minSize, in: bounds)
    }

    /// The drag a movement of the finger belongs to. While the finger that came down at `start`
    /// keeps moving, that is the drag already going on (`current`, whose crop is changing under
    /// it). A drag that came down somewhere else is a new one, decided afresh where it came down,
    /// from the crop as it is now — also when the last drag never ended: the system cancels a
    /// drag without telling the canvas (a call, Control Center), so it can't be relied on to be
    /// cleared. Nil: the drag came down away from the rectangle and its grips (it does nothing).
    nonisolated static func dragSession(at start: CGPoint, continuing current: CropDragSession?,
                                        crop: CGRect, frame: CGRect) -> CropDragSession? {
        if let current, current.startLocation == start { return current }
        guard let held = grip(at: start, on: viewRect(crop, in: frame)) else { return nil }
        return CropDragSession(held: held, startCrop: crop, startLocation: start)
    }

    /// `rect` after a drag of `translation` that took hold of it as `drag` (moving it, or one grip).
    nonisolated static func dragged(_ rect: CGRect, _ drag: CropDrag, by translation: CGSize,
                                    aspect: CGFloat?, in bounds: CGRect) -> CGRect {
        switch drag {
        case .move:
            return moved(rect, by: translation, in: bounds)
        case .resize(let handle):
            let grip = handle.point(on: rect)
            let target = CGPoint(x: grip.x + translation.width, y: grip.y + translation.height)
            return resized(rect, dragging: handle, to: target, aspect: aspect, minSize: minimumSize(of: bounds), in: bounds)
        }
    }

    /// The crop in another shape: about as big as it was (the same area) and centred where it was,
    /// but on the picture and at least the minimum. Free keeps it as it is (only kept on the picture).
    nonisolated static func reshaped(_ rect: CGRect, to aspect: CGFloat?, minSize: CGSize, in bounds: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else { return clamped(rect, minSize: minSize, in: bounds) }
        let area = max(rect.width * rect.height, 0)
        let limits = widthLimits(aspect: aspect, minSize: minSize, room: bounds.size)
        let width = min(max((area * aspect).squareRoot(), limits.min), limits.max)
        let height = width / aspect
        let x = inside(rect.midX - width / 2, length: width, low: bounds.minX, high: bounds.maxX)
        let y = inside(rect.midY - height / 2, length: height, low: bounds.minY, high: bounds.maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The crop made `factor` times as wide and as high around its middle (VoiceOver's swipe up
    /// or down), keeping its shape when one is chosen.
    nonisolated static func scaled(_ rect: CGRect, by factor: CGFloat, aspect: CGFloat?, minSize: CGSize,
                                   in bounds: CGRect) -> CGRect {
        let width = rect.width * factor
        let height = rect.height * factor
        let grown = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        guard let aspect, aspect > 0 else { return clamped(grown, minSize: minSize, in: bounds) }
        return reshaped(grown, to: aspect, minSize: minSize, in: bounds)
    }

    /// The crop (a unit rect) moved `across` tenths of the picture to the right (negative: to the
    /// left) and `down` tenths down (negative: up) — VoiceOver's Move actions. Its size stays; it
    /// stops at the picture's edges.
    nonisolated static func nudged(_ unit: CGRect, across: Int, down: Int) -> CGRect {
        let delta = CGSize(width: CGFloat(across) * nudgeFraction, height: CGFloat(down) * nudgeFraction)
        return moved(unit, by: delta, in: whole)
    }

    /// `rect` at least `minSize` and no larger than the picture (growing or shrinking around its
    /// middle), and on the picture. A rectangle that is all of that already stays as it is.
    nonisolated static func clamped(_ rect: CGRect, minSize: CGSize, in bounds: CGRect) -> CGRect {
        let width = min(max(rect.width, minSize.width), bounds.width)
        let height = min(max(rect.height, minSize.height), bounds.height)
        let x = inside(rect.midX - width / 2, length: width, low: bounds.minX, high: bounds.maxX)
        let y = inside(rect.midY - height / 2, length: height, low: bounds.minY, high: bounds.maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The grips drawn on `rect`: the corners, and the middles of the sides long enough for one.
    nonisolated static func grips(on rect: CGRect) -> [CropHandlePosition] {
        var list = CropHandlePosition.corners
        for side in CropHandlePosition.sides {
            let length = side.horizontal == 0 ? rect.width : rect.height
            if length >= sideGripLength { list.append(side) }
        }
        return list
    }

    /// What a drag starting at `point` takes hold of: the nearest grip within reach (a corner
    /// wins a tie), else the rectangle itself when the drag starts inside it, else nothing.
    /// Inside a small rectangle the grips reach less far in, so its middle can still be moved.
    nonisolated static func grip(at point: CGPoint, on rect: CGRect) -> CropDrag? {
        let inside = rect.contains(point)
        let limit = inside ? min(reach, min(rect.width, rect.height) / 4) : reach
        var nearest: CropHandlePosition? = nil
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for handle in grips(on: rect) {
            let spot = handle.point(on: rect)
            let distance = hypot(point.x - spot.x, point.y - spot.y)
            if distance <= limit, distance < nearestDistance {
                nearest = handle
                nearestDistance = distance
            }
        }
        if let nearest { return .resize(nearest) }
        return inside ? .move : nil
    }

    /// How much of the picture the crop keeps: "80% of the width, 60% of the height".
    nonisolated static func sizeDescription(_ unit: CGRect) -> String {
        let width = Int((unit.width * 100).rounded())
        let height = Int((unit.height * 100).rounded())
        return "\(width)% of the width, \(height)% of the height"
    }

    /// Where the crop starts on the picture: "10% from the left, 20% from the top".
    nonisolated static func placeDescription(_ unit: CGRect) -> String {
        let left = Int((unit.minX * 100).rounded())
        let top = Int((unit.minY * 100).rounded())
        return "\(left)% from the left, \(top)% from the top"
    }

    /// What VoiceOver says about the crop: its size, then where it is —
    /// "80% of the width, 60% of the height, 10% from the left, 20% from the top".
    nonisolated static func spokenValue(_ unit: CGRect) -> String {
        "\(sizeDescription(unit)), \(placeDescription(unit))"
    }

    // The steps

    /// A free resize: each side the grip moves follows the finger on its own.
    private nonisolated static func resizedFreely(_ rect: CGRect, dragging handle: CropHandlePosition, to point: CGPoint,
                                                  minSize: CGSize, in bounds: CGRect) -> CGRect {
        let across = span(low: rect.minX, high: rect.maxX, side: handle.horizontal, to: point.x,
                          minLength: minSize.width, lowLimit: bounds.minX, highLimit: bounds.maxX)
        let down = span(low: rect.minY, high: rect.maxY, side: handle.vertical, to: point.y,
                        minLength: minSize.height, lowLimit: bounds.minY, highLimit: bounds.maxY)
        return CGRect(x: across.low, y: down.low, width: across.high - across.low, height: down.high - down.low)
    }

    /// One direction of a free resize: the dragged end (`side` -1 the low one, 1 the high one, 0
    /// none) goes to `value`, the other end stays; at least `minLength` long (as far as the limits
    /// allow) and within the limits.
    private nonisolated static func span(low: CGFloat, high: CGFloat, side: Int, to value: CGFloat, minLength: CGFloat,
                                         lowLimit: CGFloat, highLimit: CGFloat) -> (low: CGFloat, high: CGFloat) {
        if side < 0 {
            // The low end moves: not past the lower limit, and never closer than minLength to the high end.
            let latest = max(high - minLength, lowLimit)
            return (min(max(value, lowLimit), latest), high)
        }
        if side > 0 {
            // The high end moves: not past the upper limit, and never closer than minLength to the low end.
            let earliest = min(low + minLength, highLimit)
            return (low, max(min(value, highLimit), earliest))
        }
        return (low, high)
    }

    /// A corner dragged with a shape. In plain words: picture the line from the corner that stays
    /// through the corner held — the rectangle's diagonal. The held corner slides along that line
    /// to the point on it nearest the finger, and the rectangle, in its shape, reaches from the
    /// corner that stays to there. Then it is kept on the picture and at least the minimum, without
    /// moving the corner that stays. So:
    /// - a finger moving along the diagonal has the corner right under it;
    /// - a finger moving straight in (sideways, or up or down) still pulls the corner in, and the
    ///   crop gets smaller (a square by half as much: its diagonal goes as far across as down);
    /// - a finger moving out makes it bigger;
    /// - a finger moving a little changes the size a little, never with a jump.
    /// (The rule before followed whichever way the finger went further, and flipped from one way to
    /// the other where they were equal: a square 100 wide, its corner moved 50 up, jumped from 50
    /// wide to 150 as the finger went from 49 to 50 to the right. The one before that took the
    /// larger of the two ways, so a corner dragged in never made the crop smaller.)
    private nonisolated static func cornerKeepingShape(_ rect: CGRect, dragging handle: CropHandlePosition, to point: CGPoint,
                                                       aspect: CGFloat, minSize: CGSize, in bounds: CGRect) -> CGRect {
        let anchor = handle.opposite.point(on: rect)
        let right = handle.horizontal > 0
        let down = handle.vertical > 0
        // How far the finger is from the corner that stays, across and down, counted the way that
        // makes the rectangle bigger (for a corner on the left, further left is more; on top, higher).
        let wanted = CGSize(width: right ? point.x - anchor.x : anchor.x - point.x,
                            height: down ? point.y - anchor.y : anchor.y - point.y)
        let room = CGSize(width: right ? bounds.maxX - anchor.x : anchor.x - bounds.minX,
                          height: down ? bounds.maxY - anchor.y : anchor.y - bounds.minY)
        let limits = widthLimits(aspect: aspect, minSize: minSize, room: room)
        let onDiagonal = widthAlongDiagonal(wanted, size: rect.size, aspect: aspect)
        let width = min(max(onDiagonal, limits.min), limits.max)
        let height = width / aspect
        return CGRect(x: right ? anchor.x : anchor.x - width, y: down ? anchor.y : anchor.y - height,
                      width: width, height: height)
    }

    /// How wide the rectangle becomes when its dragged corner goes to the point of its diagonal
    /// nearest the finger (before the picture's edges and the minimum have their say). `wanted`:
    /// how far the finger is from the corner that stays, across and down, counted the way that
    /// makes the rectangle bigger; `size`: how big the rectangle is now. With the size now w × h
    /// and the finger W across and H down, s = (W × w + H × h) ÷ (w² + h²) is how far along the
    /// diagonal the finger is, counted in diagonals: 1 where the corner is now (nothing changes),
    /// 1.2 a fifth further out, 0 at the corner that stays, less than 0 past it. The new size is
    /// s × w by s × h: both sides grow or shrink alike, so the shape stays exactly. This gives the
    /// width, s × w; the height follows from the shape.
    private nonisolated static func widthAlongDiagonal(_ wanted: CGSize, size: CGSize, aspect: CGFloat) -> CGFloat {
        var sides = size
        if sides.width <= 0 || sides.height <= 0 {
            sides = CGSize(width: aspect, height: 1)   // an empty rectangle (never on screen): its shape's diagonal
        }
        let along = wanted.width * sides.width + wanted.height * sides.height
        let diagonalSquared = sides.width * sides.width + sides.height * sides.height
        let scale = along / diagonalSquared
        return scale * sides.width
    }

    /// The middle of a side dragged with a shape: that side follows the finger, the rectangle
    /// grows or shrinks evenly the other way, and is moved back onto the picture where needed.
    private nonisolated static func sideKeepingShape(_ rect: CGRect, dragging handle: CropHandlePosition, to point: CGPoint,
                                                     aspect: CGFloat, minSize: CGSize, in bounds: CGRect) -> CGRect {
        if handle.horizontal != 0 {
            let right = handle.horizontal > 0
            let anchorX = right ? rect.minX : rect.maxX
            let wanted = right ? point.x - anchorX : anchorX - point.x
            let room = CGSize(width: right ? bounds.maxX - anchorX : anchorX - bounds.minX, height: bounds.height)
            let limits = widthLimits(aspect: aspect, minSize: minSize, room: room)
            let width = min(max(wanted, limits.min), limits.max)
            let height = width / aspect
            let y = inside(rect.midY - height / 2, length: height, low: bounds.minY, high: bounds.maxY)
            return CGRect(x: right ? anchorX : anchorX - width, y: y, width: width, height: height)
        }
        let down = handle.vertical > 0
        let anchorY = down ? rect.minY : rect.maxY
        let wanted = down ? point.y - anchorY : anchorY - point.y
        let room = CGSize(width: bounds.width, height: down ? bounds.maxY - anchorY : anchorY - bounds.minY)
        let limits = widthLimits(aspect: aspect, minSize: minSize, room: room)
        let width = min(max(wanted * aspect, limits.min), limits.max)
        let height = width / aspect
        let x = inside(rect.midX - width / 2, length: width, low: bounds.minX, high: bounds.maxX)
        return CGRect(x: x, y: down ? anchorY : anchorY - height, width: width, height: height)
    }

    /// The narrowest and the widest a crop of `aspect` may be: at least `minSize` each way, at most
    /// `room` each way. Where both can't be met (a picture too small for the minimum in that shape),
    /// the room wins.
    private nonisolated static func widthLimits(aspect: CGFloat, minSize: CGSize, room: CGSize) -> (min: CGFloat, max: CGFloat) {
        let widest = max(0, min(room.width, room.height * aspect))
        let narrowest = min(max(minSize.width, minSize.height * aspect), widest)
        return (narrowest, widest)
    }

    /// Where something `length` long starting at `start` has to start to stay within low…high.
    private nonisolated static func inside(_ start: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        min(max(start, low), max(high - length, low))
    }
}

// MARK: - The crop screen

/// "Crop…" (PinActions.swift presents it as a full-screen cover, dark like Photos' editor, and
/// covered in the App Switcher for a hidden pin like the pin sheets): the picture with the crop
/// rectangle, the shape under it, Reset, Cancel and Crop. Full screen, the picture gets all the
/// room there is (an iPad too), and no drag on it is ever taken for a swipe that closes the
/// screen: only Cancel or Crop close it. Crop hands the rectangle to the store (a spinner
/// meanwhile), closes, and then says how it went with a short message on the screen underneath.
/// Nothing is typed here, so a keyboard left up underneath is put away; on an iPad keyboard
/// Escape is Cancel and Return is Crop.
struct CropEditorSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @Environment(\.dismiss) private var dismiss
    let pin: Pin
    /// Runs once the picture was cropped (a crop asked for from the selection bar ends selecting).
    var onCropped: () -> Void = {}

    @State private var image: UIImage? = nil
    @State private var loadFailed = false
    @State private var crop = CropGeometry.whole        // 0…1 of the picture, top-left origin
    @State private var aspect: CropAspect = .free
    @State private var cropping = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                bottomBar
            }
            .ignoresSafeArea(.keyboard)   // nothing is typed here: a keyboard never squeezes the picture
            .navigationTitle("Crop picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .onAppear { NativeTextField.endEditing() }   // a keyboard left up on the screen underneath goes away
        .task { await loadPicture() }
        .onChange(of: aspect) { _, choice in applyAspect(choice) }
    }

    /// The picture with its crop rectangle, or what shows until it is there.
    @ViewBuilder
    private var canvas: some View {
        if let image {
            CropCanvas(image: image, crop: $crop, aspect: aspect.ratio(picture: image.size), enabled: !cropping)
        } else if loadFailed {
            Text("This picture couldn't be loaded.")
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding()
        } else {
            ProgressView()
                .tint(Color.white)
        }
    }

    /// The shape, and Reset (the whole picture, any shape).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            AspectPicker(aspect: $aspect)
            Spacer(minLength: 0)
            Button("Reset") { reset() }
                .disabled(isUntouched)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(image == nil || cropping)
    }

    /// Cancel at the top left, Crop at the top right (where iOS puts them).
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(cropping)
        }
        ToolbarItem(placement: .confirmationAction) {
            cropButton
        }
    }

    /// "Crop": dimmed while the rectangle takes the whole picture (nothing would be cut away) and
    /// while the store is cropping — a spinner shows in it then.
    private var cropButton: some View {
        let name: String = cropping ? "Cropping" : "Crop"
        return Button {
            cropPicture()
        } label: {
            if cropping {
                ProgressView()
            } else {
                Text("Crop")
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCrop)
        .accessibilityLabel(name)
    }

    /// Crop can be asked for: the picture is there, the rectangle cuts something away, and no
    /// crop is running yet.
    private var canCrop: Bool {
        !cropping && image != nil && !CropGeometry.isWhole(crop)
    }

    /// Nothing to reset: the whole picture, any shape.
    private var isUntouched: Bool {
        aspect == .free && CropGeometry.isWhole(crop)
    }

    private func loadPicture() async {
        guard image == nil else { return }
        let loaded = await store.fullImage(for: pin)
        image = loaded
        loadFailed = loaded == nil
    }

    /// A new shape: the rectangle takes it, about as big as before and where it was.
    private func applyAspect(_ choice: CropAspect) {
        guard let image else { return }
        let bounds = CGRect(origin: .zero, size: image.size)
        let current = CropGeometry.viewRect(crop, in: bounds)
        let shaped = CropGeometry.reshaped(current, to: choice.ratio(picture: image.size),
                                           minSize: CropGeometry.minimumSize(of: bounds), in: bounds)
        crop = CropGeometry.unitRect(shaped, in: bounds)
    }

    private func reset() {
        aspect = .free
        crop = CropGeometry.whole
    }

    /// Cuts the picture down in the store, closes, and then says how it went. The screen closes
    /// first: the short message shows on the screen underneath (a full-screen cover would hide it).
    private func cropPicture() {
        guard canCrop else { return }
        cropping = true
        let id = pin.id
        let area = CropGeometry.clampedUnit(crop)
        Task { @MainActor in
            let done = await store.cropImage(id, to: area)
            cropping = false
            dismiss()
            importFlow.flash(PinActionText.cropped(done), symbol: done ? "checkmark.circle" : "exclamationmark.triangle")
            if done { onCropped() }
        }
    }
}

// MARK: - The canvas

/// The picture fitted in the space there is (with a margin, so a corner's grip at the picture's
/// edge is easy to take hold of) and the crop rectangle over it: what goes is dimmed, the grips sit
/// on the corners and on the middles of long sides, and lines at the thirds show while dragging.
/// One drag handles everything: where it starts decides whether it moves the rectangle or a grip
/// (`CropGeometry.grip`). For VoiceOver the canvas is one element that says how much is kept and
/// where; swiping up or down makes the rectangle larger or smaller, and its actions move it a
/// tenth of the picture left, right, up or down, or make it bigger or smaller.
struct CropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect          // 0…1 of the picture
    /// Width ÷ height, nil for any shape.
    let aspect: CGFloat?
    var enabled: Bool = true

    /// The drag going on: what it holds and the crop it started from (see `CropGeometry.dragSession`).
    @State private var session: CropDragSession? = nil
    /// True while a finger drags on the canvas. A gesture state goes back to false by itself when
    /// the drag ends, and also when the system cancels it (a call, Control Center), which the
    /// drag's own end never hears about: the lines at the thirds go away, and the next drag
    /// starts afresh.
    @GestureState private var isDragging = false

    private static let margin: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            layers(in: proxy.size)
        }
        .allowsHitTesting(enabled)
        .onChange(of: isDragging) { _, dragging in
            if !dragging { session = nil }   // ended or cancelled: nothing is held any more
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop area")
        .accessibilityValue(CropGeometry.spokenValue(crop))
        .accessibilityHint("Swipe up or down to make it larger or smaller.")
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
            crop = scaledCrop(direction)
        }
        .accessibilityActions { voiceOverActions }
    }

    /// The picture, the dimmed part, the lines, the border and the grips, over a canvas of `size`.
    private func layers(in size: CGSize) -> some View {
        let area = CGRect(origin: .zero, size: size).insetBy(dx: CropCanvas.margin, dy: CropCanvas.margin)
        let frame = CropGeometry.fittedFrame(for: image.size, in: area)
        let rect = CropGeometry.viewRect(crop, in: frame)
        return ZStack(alignment: .topLeading) {
            picture(in: frame)
            shade(frame: frame, crop: rect)
            if isDragging, session != nil { thirds(rect) }
            border(rect)
            ForEach(CropGeometry.grips(on: rect), id: \.self) { (position: CropHandlePosition) in
                CropHandle(position: position)
                    .position(position.point(on: rect))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(frame: frame))
    }

    private func picture(in frame: CGRect) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    /// The part of the picture that will be cut away, dimmed.
    private func shade(frame: CGRect, crop rect: CGRect) -> some View {
        Path { (path: inout Path) in
            path.addRect(frame)
            path.addRect(rect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    /// Lines at the thirds of the rectangle (for placing things), while it is dragged.
    private func thirds(_ rect: CGRect) -> some View {
        Path { (path: inout Path) in
            for step in 1...2 {
                let x = rect.minX + rect.width * CGFloat(step) / 3
                let y = rect.minY + rect.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        .allowsHitTesting(false)
    }

    private func border(_ rect: CGRect) -> some View {
        Rectangle()
            .stroke(Color.white, lineWidth: 1.5)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// Starts on a grip: resizes. Starts inside the rectangle: moves it. Anywhere else: nothing.
    /// It takes hold at once (no minimum distance). Its points are the canvas's own (the canvas
    /// never moves while it is dragged on).
    private func dragGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { (_: DragGesture.Value, dragging: inout Bool, _: inout Transaction) in
                dragging = true
            }
            .onChanged { (value: DragGesture.Value) in
                dragChanged(value, frame: frame)
            }
            .onEnded { (_: DragGesture.Value) in
                session = nil
            }
    }

    /// Every movement is measured from where the drag started: the crop it started from, moved or
    /// resized by how far the finger has gone.
    private func dragChanged(_ value: DragGesture.Value, frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        let current = CropGeometry.dragSession(at: value.startLocation, continuing: session, crop: crop, frame: frame)
        if current != session { session = current }
        guard let current else { return }
        let start = CropGeometry.viewRect(current.startCrop, in: frame)
        let changed = CropGeometry.dragged(start, current.held, by: value.translation, aspect: aspect, in: frame)
        crop = CropGeometry.unitRect(changed, in: frame)
    }

    /// VoiceOver's actions on the rectangle (besides swiping up or down).
    @ViewBuilder
    private var voiceOverActions: some View {
        Button("Move left") { applyAndSay(CropGeometry.nudged(crop, across: -1, down: 0)) }
        Button("Move right") { applyAndSay(CropGeometry.nudged(crop, across: 1, down: 0)) }
        Button("Move up") { applyAndSay(CropGeometry.nudged(crop, across: 0, down: -1)) }
        Button("Move down") { applyAndSay(CropGeometry.nudged(crop, across: 0, down: 1)) }
        Button("Bigger") { applyAndSay(scaledCrop(.increment)) }
        Button("Smaller") { applyAndSay(scaledCrop(.decrement)) }
    }

    /// A VoiceOver action's result: the rectangle takes it, and VoiceOver says how it is now
    /// (it reads the new value by itself only after a swipe up or down).
    private func applyAndSay(_ unit: CGRect) {
        crop = unit
        AccessibilityNotification.Announcement(CropGeometry.spokenValue(unit)).post()
    }

    /// The crop made larger (swipe up, Bigger) or smaller (swipe down, Smaller) around its middle,
    /// keeping its shape.
    private func scaledCrop(_ direction: AccessibilityAdjustmentDirection) -> CGRect {
        let bounds = CGRect(origin: .zero, size: image.size)
        guard bounds.width > 0, bounds.height > 0 else { return crop }
        let factor: CGFloat = direction == .increment ? 1.15 : 1 / 1.15
        let current = CropGeometry.viewRect(crop, in: bounds)
        let changed = CropGeometry.scaled(current, by: factor, aspect: aspect,
                                          minSize: CropGeometry.minimumSize(of: bounds), in: bounds)
        return CropGeometry.unitRect(changed, in: bounds)
    }
}

/// One grip, drawn: a white dot on a corner, a short white bar in the middle of a side, with a
/// soft shadow so it shows on a light picture too. Only for the eye: the canvas's drag takes
/// hold of it (a finger within `CropGeometry.reach` of it).
struct CropHandle: View {
    let position: CropHandlePosition

    var body: some View {
        grip
            .shadow(color: Color.black.opacity(0.45), radius: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var grip: some View {
        if position.isCorner {
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
        } else {
            Capsule()
                .fill(Color.white)
                .frame(width: barSize.width, height: barSize.height)
        }
    }

    /// Along its side: wide on the top and bottom, tall on the left and right.
    private var barSize: CGSize {
        position.horizontal == 0 ? CGSize(width: 26, height: 6) : CGSize(width: 6, height: 26)
    }
}

/// The crop's shape: a row of segments when all of them fit (an iPad), else a menu that shows the
/// shape chosen (a phone).
struct AspectPicker: View {
    @Binding var aspect: CropAspect

    var body: some View {
        ViewThatFits(in: .horizontal) {
            segments
            menu
        }
    }

    private var segments: some View {
        Picker("Aspect ratio", selection: $aspect) {
            options
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var menu: some View {
        Menu {
            Picker("Aspect ratio", selection: $aspect) {
                options
            }
        } label: {
            Label(aspect.name, systemImage: "aspectratio")
        }
        .accessibilityLabel("Aspect ratio")
        .accessibilityValue(aspect.name)
    }

    private var options: some View {
        ForEach(CropAspect.allCases) { (option: CropAspect) in
            Text(option.name).tag(option)
        }
    }
}
