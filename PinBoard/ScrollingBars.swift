//
//  ScrollingBars.swift  —  PinBoard
//
//  Scrolling down a page tucks the app's bars away (the title bar at the top and the
//  tab bar at the bottom), so only the pins are on screen; scrolling back up, or
//  getting back to the top, brings them back. Used by the pin grid (PinGrid.swift),
//  the Boards tab (BoardViews.swift) and Explore (WebImages.swift).
//

import SwiftUI

/// Where a page's scroll is, as far as the bars care: how far down from the top it is,
/// and how far down it can go at most.
struct ScrollSpot: Equatable {
    var offset: CGFloat
    var maximum: CGFloat
}

/// The numbers behind when the bars go and come back, kept in one place so they are easy to tune.
enum ScrollingBarsRule {
    /// How far (in points) the page must keep moving one way before the bars change. A little
    /// wobble of the finger shouldn't make them flicker.
    static let travelNeeded: CGFloat = 24
    /// Near the very top the bars always show, so the title and the buttons are there to start with.
    static let topZone: CGFloat = 40
    /// While the bars slide in or out the page shifts a little by itself. For this long after a
    /// change that shift is not counted as scrolling, or it could flip the bars straight back.
    static let settleTime: TimeInterval = 0.4
}

/// Hides the title bar and the tab bar while you scroll down the page it is on, and shows them
/// again when you scroll up or reach the top. Put it on a page's ScrollView.
/// Reading the scroll needs iOS 18; on iOS 17 the bars simply stay where they are.
struct HidesBarsOnScroll: ViewModifier {
    /// Off while the page needs its bars (selecting pins): they show and stay.
    var enabled: Bool

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var barsHidden = false
    @State private var lastOffset: CGFloat = 0
    /// How far the page has moved in its current direction (down is positive, up negative).
    @State private var travel: CGFloat = 0
    @State private var lastChange = Date.distantPast

    /// With VoiceOver on, the bars always stay: a bar that vanished would take its buttons
    /// away from under the reader.
    private var hide: Bool { barsHidden && enabled && !voiceOver }

    func body(content: Content) -> some View {
        // Not hiding means "leave the bars as they would be", not "show them": the Boards tab's
        // own list stays underneath a board's page, and a firm "show" from it would win over the
        // board page asking to hide the tab bar.
        let visibility: Visibility = hide ? .hidden : .automatic
        watchingScroll(content)
            .toolbar(visibility, for: .navigationBar)
            .toolbar(visibility, for: .tabBar)
            // Coming back to the page (from a pin, say), the bars are there again.
            .onAppear { barsHidden = false }
            .onChange(of: enabled) { _, on in
                if !on { setHidden(false) }
            }
    }

    /// The page, with the scroll read on iOS 18 and later.
    @ViewBuilder
    private func watchingScroll(_ content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: ScrollSpot.self) { (geometry: ScrollGeometry) -> ScrollSpot in
                Self.spot(of: geometry)
            } action: { (_: ScrollSpot, spot: ScrollSpot) in
                scrolled(to: spot)
            }
        } else {
            content
        }
    }

    /// Measured from the page's own top, so the bars coming and going (which changes the
    /// space around the page) doesn't look like scrolling.
    @available(iOS 18, *)
    private static func spot(of geometry: ScrollGeometry) -> ScrollSpot {
        let top = geometry.contentInsets.top
        let offset = geometry.contentOffset.y + top
        let room = geometry.contentSize.height + top + geometry.contentInsets.bottom - geometry.containerSize.height
        return ScrollSpot(offset: offset, maximum: max(room, 0))
    }

    /// Decides, after each little move of the page, whether the bars should go or come back.
    private func scrolled(to spot: ScrollSpot) {
        // The bounce past either end is not scrolling: only the part inside the page counts.
        // (A page too short to scroll stays at 0, inside the top zone, so its bars never go.)
        let offset = min(max(spot.offset, 0), spot.maximum)
        let moved = offset - lastOffset
        lastOffset = offset
        if offset < ScrollingBarsRule.topZone {
            setHidden(false)
            return
        }
        if moved == 0 { return }
        if Date().timeIntervalSince(lastChange) < ScrollingBarsRule.settleTime {
            travel = 0
            return
        }
        // Travel adds up while the page keeps going one way, and starts over when it turns.
        let goingDown = moved > 0
        let wasGoingDown = travel > 0
        if travel != 0 && goingDown != wasGoingDown { travel = 0 }
        travel += moved
        if travel > ScrollingBarsRule.travelNeeded {
            setHidden(true)
        } else if travel < -ScrollingBarsRule.travelNeeded {
            setHidden(false)
        }
    }

    private func setHidden(_ hidden: Bool) {
        travel = 0
        guard hidden != barsHidden else { return }
        lastChange = Date()
        withAnimation(.easeInOut(duration: 0.25)) {
            barsHidden = hidden
        }
    }
}

extension View {
    /// Hides the title bar and the tab bar while scrolling down this ScrollView (see `HidesBarsOnScroll`).
    func hidesBarsOnScroll(enabled: Bool = true) -> some View {
        modifier(HidesBarsOnScroll(enabled: enabled))
    }
}
