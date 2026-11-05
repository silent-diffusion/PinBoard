//
//  PinPageLayout.swift  —  PinBoard
//
//  How a pin's page is arranged. On a wide page: two columns — the picture or video on the left,
//  everything about it on the right — with "More like this" and the web ideas below both. On a
//  narrow page: one column, as always (the media, then the details).
//
//  The choice is a plain rule by the page's own width and its size class — never by which device
//  it is or which way it is held — so an iPad in a narrow Split View gets one column and a large
//  iPhone turned sideways may get two. Two columns only when the details column gets at least
//  320 pt (a page about 768 pt wide); narrower than that the page stacks. `PinPageColumns` is the one place that puts the columns
//  side by side: a later adapter for a folding screen would split them at the fold right there, in
//  this file only. (The iPhone Duo APIs are not in the SDK PinBoard is built with, so nothing
//  here uses them.)
//
//  The same file holds how tall the media area is (`mediaHeight`). In two columns the picture or
//  video takes its whole column and is as tall as its own shape asks, so nothing sits in a grey
//  box; in one column the old rule still keeps it inside the screen.
//

import SwiftUI
import Foundation

/// The rules for the pin page's columns (pure, so the harness tests them).
enum PinPageLayout {
    enum Columns: Equatable {
        case one, two
    }

    /// The details column (title, note, tags, boards) needs at least this much room to be a
    /// comfortable reading column; the page goes to two columns only when it gets this much.
    /// (Under it, a stacked page reads better than a squeezed column.)
    nonisolated static let minDetailsWidth: CGFloat = 320

    /// The padding around the page's content, and the gaps: between the two columns, and between
    /// the media and the details when they are stacked.
    nonisolated static let sidePadding: CGFloat = 16
    nonisolated static let columnGap: CGFloat = 24
    nonisolated static let stackGap: CGFloat = 18

    /// How wide the page's content block may get (padding included): a comfortable reading
    /// column for one column, more room for two.
    nonisolated static let oneColumnMaxWidth: CGFloat = 900
    nonisolated static let twoColumnMaxWidth: CGFloat = 1280

    /// The media's share of the two columns.
    nonisolated static let mediaShare: CGFloat = 0.55

    /// The least page width (points) that gives the details column `minDetailsWidth`: what is left
    /// after the paddings and the gap is shared 55 / 45, so the details need 320 / 0.45 = 712 pt of
    /// it. With the paddings and the gap that is 768 pt. A plain threshold on the width (not a
    /// check of the details' rounded width) so a wider page can never go back to one column.
    nonisolated static var twoColumnMinWidth: CGFloat {
        let room = (minDetailsWidth / (1 - mediaShare)).rounded(.up)
        return room + sidePadding * 2 + columnGap
    }

    /// One column or two, for a page `width` points wide. Two only when the size class is
    /// regular, the page is at least `twoColumnMinWidth` wide (the details column then gets at
    /// least `minDetailsWidth`) and the text is not in one of the large accessibility sizes
    /// (whose text needs the width for itself).
    nonisolated static func columns(sizeClass: UserInterfaceSizeClass?, width: CGFloat, largeText: Bool = false) -> Columns {
        guard sizeClass == .regular, !largeText else { return .one }
        return width >= twoColumnMinWidth ? .two : .one
    }

    /// The widths the page works with.
    struct Sizing: Equatable {
        var columns: Columns
        /// The whole content block, padding included (it is centred when the page is wider).
        var pageWidth: CGFloat
        /// The media's width: its column, or the whole reading width when stacked.
        var mediaWidth: CGFloat
        /// The details' width: its column, or the whole reading width when stacked.
        var detailsWidth: CGFloat
    }

    /// The widths for `columns` on a page `available` points wide.
    nonisolated static func sizing(columns: Columns, available: CGFloat) -> Sizing {
        switch columns {
        case .one:
            let page = min(available, oneColumnMaxWidth)
            let reading = max(0, page - sidePadding * 2)
            return Sizing(columns: .one, pageWidth: page, mediaWidth: reading, detailsWidth: reading)
        case .two:
            let page = min(available, twoColumnMaxWidth)
            let inner = max(0, page - sidePadding * 2 - columnGap)
            let media = (inner * mediaShare).rounded(.down)
            return Sizing(columns: .two, pageWidth: page, mediaWidth: media, detailsWidth: inner - media)
        }
    }

    // MARK: How tall the media area is

    /// The least height the media area ever has, in either layout. (A link without a picture gets
    /// exactly this much: its site name and a link symbol need no more.)
    nonisolated static let minMediaHeight: CGFloat = 180

    /// In two columns the media area is never more than this many times as tall as it is wide. A pin
    /// can have any shape — a phone screenshot is about 1:2, a long web capture 1:10 — and without a
    /// bound one of those would make the page thousands of points tall. A picture taller than this is
    /// still shown whole, a little narrower than its column.
    nonisolated static let maxMediaHeightPerWidth: CGFloat = 2.5

    /// The tallest shape (width ÷ height) a picture counts as in one column: 1:5, the same limit the
    /// grid's cards use, so a sliver of a picture doesn't ask for a sliver of a box.
    nonisolated static let tallestPictureShape: CGFloat = 0.2

    /// The owner's choice for round 15: in two columns a video is as tall as its own shape asks, even
    /// taller than the window (the page scrolls; the middle of the player is always in reach). To keep
    /// videos inside the window there, as one column does, change this one line to `true`.
    nonisolated static let keepsVideosInWindow = false

    /// How tall the media area is — the picture, video, text panel or link hero at the top of the page.
    ///
    /// **Two columns:** the pin's own height for the width of its column, with no cap by the screen
    /// (the page scrolls). Only a sanity bound keeps it sensible: never under 180 pt, never over
    /// 2.5 × the width (so a 1:10 screenshot can't make a 6,000-pt page). A text pin gets the natural
    /// height of its panel (`naturalTextHeight`, measured by the caller; nil for every other kind of
    /// pin) within the same bound, and a link without a picture gets the 180-pt minimum. `limit` is
    /// not used here.
    ///
    /// **One column** (a phone, a narrow window): the rule the page always had — the same heights, but
    /// never more than `limit` (`PinDetailView.mediaHeightLimit`: the screen), which keeps a picture,
    /// or a video with its controls, inside the screen.
    ///
    /// A shape that is not a real number (0, infinity, not-a-number, negative) counts as unknown and
    /// gets the minimum, so a bad record can never make a huge or an empty box.
    nonisolated static func mediaHeight(columns: Columns, width: CGFloat, aspectRatio: CGFloat,
                                        naturalTextHeight: CGFloat?, isLinkWithoutPicture: Bool,
                                        limit: CGFloat) -> CGFloat {
        let natural = naturalMediaHeight(width: width, aspectRatio: aspectRatio,
                                         naturalTextHeight: naturalTextHeight,
                                         isLinkWithoutPicture: isLinkWithoutPicture)
        switch columns {
        case .one:
            return min(limit, max(minMediaHeight, natural))
        case .two:
            // The minimum is applied last, so it wins even in a column too narrow for 2.5 × its width.
            return max(minMediaHeight, min(natural, width * maxMediaHeightPerWidth))
        }
    }

    /// The height the pin asks for before any bound: a text pin's panel, a link hero's minimum, or
    /// the picture's own shape for the column's width (rounded to a whole point).
    private nonisolated static func naturalMediaHeight(width: CGFloat, aspectRatio: CGFloat,
                                                       naturalTextHeight: CGFloat?,
                                                       isLinkWithoutPicture: Bool) -> CGFloat {
        if let text = naturalTextHeight {
            return text.isFinite ? text : minMediaHeight
        }
        if isLinkWithoutPicture { return minMediaHeight }
        guard width.isFinite, aspectRatio.isFinite, aspectRatio > 0 else { return minMediaHeight }
        return (width / max(aspectRatio, tallestPictureShape)).rounded()
    }

    // MARK: A video's media area, scrolled into view

    /// A video plays only while its media area is scrolled into view (it pauses when you scroll
    /// away). It counts as in view when at least 30 % of the area is on screen — or, for an area
    /// much taller than the window (two columns allow that), when at least half of the window shows
    /// it. Without the second part a tall video in a short window could never reach 30 % of itself
    /// and would never play. `visibleHeight`: how much of the area is on screen now (negative or zero
    /// when none); `viewportHeight`: the height of the scrolling page.
    nonisolated static func isMediaInView(boxHeight: CGFloat, visibleHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard visibleHeight > 0 else { return false }
        let needed = min(boxHeight * 0.3, viewportHeight * 0.5)
        return visibleHeight >= needed
    }
}

/// The media and the details of a pin, in two columns or stacked. `AnyLayout` switches between
/// the two without rebuilding what is inside them, so a video keeps playing and the pager keeps
/// its page when the window is resized across the line. The choice sits here, below the page's
/// state, never above it.
struct PinPageColumns<Media: View, Details: View>: View {
    let sizing: PinPageLayout.Sizing
    let media: Media
    let details: Details

    init(sizing: PinPageLayout.Sizing, @ViewBuilder media: () -> Media, @ViewBuilder details: () -> Details) {
        self.sizing = sizing
        self.media = media()
        self.details = details()
    }

    var body: some View {
        arrangement {
            column(media, width: sizing.mediaWidth)
            column(details, width: sizing.detailsWidth)
        }
    }

    /// Side by side (media left), or one above the other.
    private var arrangement: AnyLayout {
        if sizing.columns == .two {
            return AnyLayout(HStackLayout(alignment: .top, spacing: PinPageLayout.columnGap))
        }
        return AnyLayout(VStackLayout(alignment: .leading, spacing: PinPageLayout.stackGap))
    }

    /// A column: a fixed width side by side, the whole width when stacked.
    private func column<Content: View>(_ content: Content, width: CGFloat) -> some View {
        content
            .frame(width: sizing.columns == .two ? width : nil, alignment: .topLeading)
            .frame(maxWidth: sizing.columns == .two ? nil : .infinity, alignment: .leading)
    }
}
