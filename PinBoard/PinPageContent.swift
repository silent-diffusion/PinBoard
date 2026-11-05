//
//  PinPageContent.swift  —  PinBoard
//
//  What a pin's page shows, written as part of `PinDetailView`: the media box
//  with its pager, the title, link, board, tag and info sections, "Use this
//  frame as thumbnail", and the feeds under the page (More like this, then the
//  web). Its own file so PinDetailView.swift keeps the page's state and layout.
//

import SwiftUI
import UIKit
import Foundation

extension PinDetailView {
    // MARK: Media (picture / video / text / link) with the pager

    /// The natural height of a text pin's panel at this width.
    private func textPanelHeight(for pin: Pin, width: CGFloat) -> CGFloat {
        let style = settings.textStyle
        let text = TextCardStyle.measure(pin.textBody.isEmpty ? " " : pin.textBody,
                                         font: style.uiFont(size: style.pageSize),
                                         width: max(10, width - 36), maxLines: 400)
        return (text + 36 + 44).rounded()
    }

    /// How tall the media area is for this pin (the neighbours fit inside it). The rule itself is
    /// `PinPageLayout.mediaHeight` (pure, tested): in two columns the pin's own height for its
    /// column's width, in one column the same but never more than the screen's limit
    /// (`mediaHeightLimit`). `width` is the media's width: its column, or the whole reading width.
    private func mediaHeight(for pin: Pin, columns: PinPageLayout.Columns, width: CGFloat, stableHeight: CGFloat) -> CGFloat {
        let limit = PinDetailView.mediaHeightLimit(stableHeight: stableHeight,
                                                   compactHeight: verticalSizeClass == .compact,
                                                   heightBetweenBars: heightBetweenBars)
        // Only a text pin's panel is measured (that costs a little), and only the rule needs it.
        let textHeight: CGFloat? = pin.isText ? textPanelHeight(for: pin, width: width) : nil
        let height = PinPageLayout.mediaHeight(columns: columns, width: width, aspectRatio: pin.aspectRatio,
                                               naturalTextHeight: textHeight,
                                               isLinkWithoutPicture: pin.isLink && !pin.hasPreview,
                                               limit: limit)
        // The one place that keeps a video inside the window in two columns, if the owner ever wants
        // that (see `PinPageLayout.keepsVideosInWindow`; it is off).
        if pin.isVideo, columns == .two, PinPageLayout.keepsVideosInWindow {
            return min(height, limit)
        }
        return height
    }

    /// The tallest the media area may be in one column: the screen's limit (a plain rule; the
    /// harness tests it). Two columns do not use it — see `PinPageLayout.mediaHeight`. The limit is:
    ///   • 560 pt;
    ///   • on a short screen — less than 700 pt from the top of the page to the bottom of the
    ///     window (`stableHeight`) — at most 80 % of that height, so the whole picture, or a video
    ///     with its controls, fits on screen;
    ///   • on a phone in landscape (`compactHeight`) at most 80 % of the page's height between
    ///     its bars (`heightBetweenBars`), so the bottom of a video, with its controls, never sits
    ///     under the tab bar floating over the page. Until that is measured (0), 80 % of
    ///     `stableHeight`.
    /// Never more than 560 pt, never less than 120. Both heights are measured as if the keyboard
    /// were down (see `pageBody`): the keyboard coming up to type a tag never makes the picture smaller.
    nonisolated static func mediaHeightLimit(stableHeight: CGFloat, compactHeight: Bool,
                                             heightBetweenBars: CGFloat = 0) -> CGFloat {
        guard stableHeight > 0 else { return 560 }   // not measured yet
        let shortScreen = compactHeight || stableHeight < 700
        guard shortScreen else { return 560 }
        let measured = compactHeight && heightBetweenBars > 0 ? heightBetweenBars : stableHeight
        return max(120, min(560, (measured * 0.8).rounded()))
    }

    /// Settings is open over this page. It is a sheet, so the page never hears that it went out
    /// of sight; its video waits meanwhile. (A page opened inside Settings is not under it.)
    private var settingsCoversPage: Bool {
        router.showSettings && !isInsideSettings
    }

    /// The media area: the pager over the whole list, inside a box `mediaHeight` tall. Everything that
    /// depends on that height — the pager's frame, the pages' `boxHeight`, the corner marks, the
    /// "scrolled into view" check for videos — reads the one `height` made here.
    func mediaSection(_ pin: Pin, columns: PinPageLayout.Columns, width: CGFloat, scrollTop: CGFloat,
                      viewportHeight: CGFloat, stableHeight: CGFloat) -> some View {   // (not private: used by PinDetailView.swift)
        let count = itemCount
        let position = pagerIndex.wrappedValue
        let height = mediaHeight(for: pin, columns: columns, width: width, stableHeight: stableHeight)
        // Read here, in body, and handed to the pages: a change re-runs body, which refreshes
        // the pager's pages (the page closure alone is not re-run for these state changes).
        // Video: plays by itself with auto-play on; may play only while scrolled into view,
        // while Quick Look is not up (opened from the picture, or from a pin menu) and while
        // Settings is not open over the page.
        let playing = settings.autoPlayOnPage
        let mayPlay = mediaOnScreen && viewer == nil && !pinActions.isShowingQuickLook && !settingsCoversPage
        // One pager over the whole list: page i is always item i.
        return VStack(alignment: .trailing, spacing: 6) {
            MediaPager(count: count, index: pagerIndex, spacing: 8, pageID: { i in pageIdentity(at: i) }) { i in
                mediaPage(at: i, distance: abs(i - position), isCurrent: i == position, width: width,
                          boxHeight: height, playing: playing, mayPlay: mayPlay)
            }
            .frame(height: height)
            .animation(.easeInOut(duration: 0.2), value: height)
            .clipShape(RoundedRectangle(cornerRadius: PinTheme.cardRadius, style: .continuous))
            .overlay(alignment: PinPageMediaMarks.quickLookMark(columns: columns)) {
                if pin.hasImageFile, !pin.isVideo {
                    // Tapping the picture opens Quick Look; this only shows that it can.
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: PinPageMediaMarks.swipeHint(columns: columns, isText: pin.isText)) {
                if hasNeighbors, !pin.isVideo {   // a video's own controls sit along the bottom
                    Label(position + 1 < count ? "Swipe for next" : "Swipe back", systemImage: "arrow.left.arrow.right")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .background {
                // Videos: is the media box scrolled into view? Scrolling it away pauses the video.
                // (A box taller than the window — two columns allow that — counts as in view once
                // half the window shows it: PinPageLayout.isMediaInView.)
                if pin.isVideo {
                    GeometryReader { box in
                        let frame = box.frame(in: .global)
                        let shown = min(frame.maxY, scrollTop + viewportHeight) - max(frame.minY, scrollTop)
                        let onScreen = PinPageLayout.isMediaInView(boxHeight: frame.height, visibleHeight: shown,
                                                                   viewportHeight: viewportHeight)
                        Color.clear.task(id: onScreen) { mediaOnScreen = onScreen }
                    }
                }
            }
            .accessibilityLabel(mediaLabel(pin, position: position, count: count))
            if pin.isVideo, hasNeighbors {
                // The video's own controls sit along its bottom (their expand button opens
                // Quick Look), so the swipe hint goes underneath.
                Label(position + 1 < count ? "Swipe for next" : "Swipe back", systemImage: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// What VoiceOver says for the media area: "Photo 3 of 12. Swipe left or right for the
    /// others.", or just "Photo" when there are no neighbours.
    private func mediaLabel(_ pin: Pin, position: Int, count: Int) -> String {
        let kind = PinCardView.kindName(pin.kind)
        guard hasNeighbors else { return kind }
        return "\(kind) \(position + 1) of \(count). Swipe left or right for the others."
    }

    /// What is at a pager position, so a page's state belongs to one item only.
    private func pageIdentity(at i: Int) -> AnyHashable {
        switch source {
        case .stored:
            let list = storedItems
            return list.indices.contains(i) ? AnyHashable(list[i]) : AnyHashable(i)
        case .draft:
            return webContext.indices.contains(i) ? AnyHashable(webContext[i].id) : AnyHashable(i)
        }
    }

    /// One page of the pager. Only the page in front and its neighbours load
    /// full pictures; the next two load thumbnails; the rest stay empty.
    @ViewBuilder
    private func mediaPage(at i: Int, distance: Int, isCurrent: Bool, width: CGFloat, boxHeight: CGFloat,
                           playing: Bool, mayPlay: Bool) -> some View {
        switch source {
        case .stored:
            let list = storedItems
            if list.indices.contains(i), let item = store.pin(list[i]) {
                storedMediaPage(item, distance: distance, isCurrent: isCurrent, width: width,
                                boxHeight: boxHeight, playing: playing, mayPlay: mayPlay)
            } else {
                Color(uiColor: .secondarySystemFill)
            }
        case .draft:
            if webContext.indices.contains(i) {
                webMediaPage(webContext[i], distance: distance, isCurrent: isCurrent)
            } else {
                Color(uiColor: .secondarySystemFill)
            }
        }
    }

    @ViewBuilder
    private func storedMediaPage(_ pin: Pin, distance: Int, isCurrent: Bool, width: CGFloat, boxHeight: CGFloat,
                                 playing: Bool, mayPlay: Bool) -> some View {
        let quality = PageQuality(distance: distance)
        switch pin.kind {
        case .text:
            if isCurrent {
                // The whole text. Only a text taller than the media area (`boxHeight`) scrolls
                // inside its panel; otherwise dragging on it scrolls the page, as expected.
                ScrollView {
                    TextPanelView(pin: pin, style: settings.textStyle, color: settings.textPinColor) {
                        editingText = true
                    }
                }
                .scrollDisabled(textPanelHeight(for: pin, width: width) <= boxHeight)
            } else {
                TextCardView(pin: pin, style: settings.textStyle, color: settings.textPinColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
            }
        case .video:
            if isCurrent {
                // PinBoard's own player: its controls (play, scrub bar, sound, expand) sit along
                // the bottom. It starts by itself only with auto-play on, and starts over at the
                // end. Scrolled out of view or with Quick Look up it pauses — even a video you
                // started by hand — and carries on when it may play again. Expand opens Quick
                // Look (swipe on through the feed there; ⋯ has the pin's actions), which carries
                // on from the same place with the same sound.
                BroughtBack(pin: pin) {   // a video kept in iCloud only comes back first (Offloading.swift)
                    VideoPlayerView(url: store.videoFileURL(for: pin),
                                    playing: playing,
                                    mayPlay: mayPlay,
                                    onExpand: isDraft ? nil : { openViewer(pin) },
                                    handle: playerHandle)
                        .overlay(alignment: .topTrailing) { frameThumbnailButton(pin) }
                }
            } else {
                StoredImagePage(pin: pin, quality: quality)   // neighbours show their poster frame
            }
        case .link:
            if pin.hasPreview {
                StoredImagePage(pin: pin, quality: quality)
                    .contentShape(Rectangle())
                    .onTapGesture { if isCurrent { openViewer(pin) } }
            } else {
                linkHero(pin)
            }
        case .image:
            StoredImagePage(pin: pin, quality: quality)
                .contentShape(Rectangle())
                .onTapGesture { if isCurrent { openViewer(pin) } }
        }
    }

    /// A link without a preview picture: the site, big, in the media area. It has no "Open link"
    /// of its own: the link panel just under the title has it (`linkSection`), and one per page is
    /// enough — two identical buttons a few lines apart would only make you wonder which to use.
    private func linkHero(_ pin: Pin) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // only decoration
            Text(pin.linkHost ?? "Link")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private func webMediaPage(_ web: WebImage, distance: Int, isCurrent: Bool) -> some View {
        if isCurrent, let saved = draft.savedID, let storedPin = store.pin(saved) {
            StoredImagePage(pin: storedPin, quality: .full)
                .contentShape(Rectangle())
                .onTapGesture { openViewer(storedPin) }
        } else {
            Color(uiColor: .secondarySystemFill)
                .overlay {
                    if isCurrent, let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else if distance <= 2 {
                        RemoteImageView(url: web.thumbURL)   // the thumbnail is already cached from the feed
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { if isCurrent, let current = pin { openViewer(current) } }
        }
    }

    private func openViewer(_ pin: Pin) {
        switch source {
        case .stored:
            // Quick Look's "Show info" on this same video then just closes instead of pushing a second copy of the page.
            viewer = .library(seed: pin, pinPageUnder: pin.id)
        case .draft:
            if let saved = draft.savedID, let storedPin = store.pin(saved) {
                viewer = .library(seed: storedPin)
            } else if let current = currentWeb {
                // Known gap: pages through webContext only — the feed's loader can't travel in Route.webImage (Hashable).
                // Saving there lands where the feed saves: on its boards, or on this page's side of the
                // library without a board (Hidden for a result from a hidden feed).
                viewer = .web(images: webContext, startIndex: webContext.firstIndex(of: current) ?? 0, loadMore: nil,
                              boardIDs: feedBoards, hidden: draftScope == .hidden)
            }
        }
    }

    // MARK: "Use this frame as thumbnail"

    /// The page's video is paused and ready: its frame on screen can be made the thumbnail.
    private var canUseFrame: Bool { playerHandle.canUseFrame }

    /// Where the paused video stands right now, in seconds (nil when it isn't paused and ready).
    private func pausedFrameSecond() -> Double? { playerHandle.currentSeconds() }

    /// Whether "Use this frame as thumbnail" is offered for this pin right now.
    func isFrameOffered(_ pin: Pin) -> Bool {   // (not private: used by PinDetailView.swift)
        PinPageFrameThumbnail.isOffered(kind: pin.kind, isDraft: isDraft, canUseFrame: canUseFrame)
    }

    /// A small button in the corner of the video while it is paused: the frame on screen becomes
    /// the pin's thumbnail (its poster, also in the video file, so other apps show it too).
    @ViewBuilder
    private func frameThumbnailButton(_ pin: Pin) -> some View {
        if isFrameOffered(pin) {
            Button {
                useFrameAsThumbnail(pin)
            } label: {
                Label("Use as thumbnail", systemImage: "photo.badge.checkmark")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Use this frame as thumbnail")
        }
    }

    /// Takes the frame the video is paused on now (read when tapped, so a scrub just before counts).
    func useFrameAsThumbnail(_ pin: Pin) {   // (not private: used by PinDetailView.swift)
        guard let seconds = pausedFrameSecond() else { return }
        let id = pin.id
        Task { @MainActor in
            let changed = await store.setPoster(for: id, frameAt: seconds)
            importFlow.flash(PinPageFrameThumbnail.message(changed: changed),
                             symbol: changed ? "checkmark.circle" : "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    func titleSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.title.isEmpty ? "Add a title" : pin.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(pin.title.isEmpty ? Color.secondary : Color.primary)
                    if (pin.titleIsAuto && !pin.title.isEmpty) || pin.canUndoAITitle {
                        aiTitleNote(pin)
                    }
                    if !pin.aiDescription.isEmpty {
                        Text(pin.aiDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // No extra spacing: each touch area already leaves room around its circle.
                HStack(spacing: 0) {
                    if !isDraft, store.aiMaySee(pin) { retitleButton(pin) }   // (no AI on a hidden pin unless allowed)
                    roundButton("pencil", label: "Edit title") { editingTitle = true }
                }
            }
            quoteSourceRow(pin)
            HStack(alignment: .top) {
                Text(pin.note.isEmpty ? "Add a note" : pin.note)
                    .font(.body)
                    .foregroundStyle(pin.note.isEmpty ? Color.secondary : Color.primary)
                Spacer()
                roundButton("pencil", label: "Edit note") {
                    noteWhenOpened = pin.note   // what the sheet starts from (see `noteWhenOpened`)
                    editingNote = true
                }
            }
        }
    }

    /// A quote pin (an article's highlight saved as a pin) says which article it was quoted from, just
    /// above the note; the row opens that article's page, the way a "More like this" card opens a pin.
    /// The article's title is told only while the article is here, on this page's side of the library:
    /// one that is gone (deleted, in Recently Deleted), or that sits on the other side of the hidden
    /// line since (its title must never show on the wrong side), leaves a plain line of text.
    @ViewBuilder
    private func quoteSourceRow(_ pin: Pin) -> some View {
        if !isDraft, pin.quotedFromID != nil {
            let article = PinPageSourceRows.articleToName(for: pin, in: store, pageScope: pageScope)
            let text = PinPageSourceRows.quoteRowText(articleTitle: article?.title)
            if let article {
                NavigationLink(value: Route.pin(article.id, .none)) {
                    quoteRowLabel(text, opensArticle: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the article's page.")
            } else {
                quoteRowLabel(text, opensArticle: false)
            }
        }
    }

    /// The look of the quote row: the quote mark and the words. A row that opens the article also has
    /// a chevron and a soft background like the board chips, so it reads as something to tap, and is
    /// at least 44 pt tall, so it is easy to hit.
    private func quoteRowLabel(_ text: String, opensArticle: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // only decoration: the words say it
            Text(text)
                .font(.subheadline)
                .foregroundStyle(opensArticle ? Color.primary : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if opensArticle {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, opensArticle ? 12 : 0)
        .frame(minHeight: opensArticle ? 44 : 0)   // (a plain line is not a target)
        .background(opensArticle ? Color(uiColor: .secondarySystemBackground) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    /// A link pin's address with "Open link" and the preview button (LinkPanelView, LinkPins.swift),
    /// and beside it, like the pencils of the title and the note, "Edit link" (the link editor;
    /// PinActions.swift). This is the page's only "Open link" (the link hero above has none).
    func linkSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        HStack(alignment: .top) {
            LinkPanelView(pin: pin, onRefetch: refetchAction(for: pin), readsFully: settings.readsLinksFully)
            if !isDraft {
                roundButton("pencil", label: "Edit link") {
                    pinActions.perform(.editLink, on: [pin.id], side: pageScope, place: .pinPage)
                }
            }
        }
    }

    /// The link panel's button, where fetching from the web is allowed: "Read link again" when links
    /// are read fully (Settings › Links, SmartLinks.swift), else "Refresh preview" / "Fetch preview".
    private func refetchAction(for pin: Pin) -> (() -> Void)? {
        guard settings.webAllowed, settings.fetchLinkPreviews, !isDraft else { return nil }
        let id = pin.id
        if settings.readsLinksFully {
            return {
                Task { @MainActor in await store.readLink(for: id) }
            }
        }
        return {
            Task { @MainActor in await store.fetchLinkPreview(for: id) }
        }
    }

    /// The sparkles button: the AI suggests a new title (a spinner while it thinks). It works while
    /// the AI is still looking at the pin too (the store looks first). A new title shows by itself
    /// (with Undo); when none different was found, a short message says so — only when the title
    /// really is the same as before: the store also says "not changed" when the title changed
    /// meanwhile some other way (the AI naming a pin just added, or you typing one), and then the
    /// new title is there to see.
    private func retitleButton(_ pin: Pin) -> some View {
        Button {
            retitling = true
            let id = pin.id
            let before = store.livePin(id)?.title ?? pin.title
            Task { @MainActor in
                let changed = await store.regenerateTitle(for: id)
                guard currentPinID == id else { return }   // the page has moved on to another pin
                retitling = false
                let now = store.livePin(id)?.title
                if PinDetailView.saysNoDifferentTitle(changed: changed, before: before, now: now) {
                    // A link without a preview picture gives the AI nothing to go on (naming runs leave it out too).
                    let noPreviewLink = store.livePin(id).map { $0.isLink && !$0.hasPreview } ?? false
                    importFlow.flash(noPreviewLink ? AISortingText.nothingToGoOn : "No different title was found.", symbol: "info.circle")
                }
            }
        } label: {
            roundButtonLook {
                if retitling {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(retitling)
        .accessibilityLabel("Suggest a title")
    }

    /// After "Suggest a title" (a plain rule; the harness tests it): "No different title was
    /// found." only when the store changed nothing (`changed`) and the pin's title `now` is still
    /// the one it had when the button was tapped (`before`). The store also says "not changed"
    /// when the title changed meanwhile some other way, and then there is a new title to see.
    /// A pin that is gone (`now` nil) gets no message.
    nonisolated static func saysNoDifferentTitle(changed: Bool, before: String, now: String?) -> Bool {
        !changed && now == before
    }

    /// A small round icon button (the pencils).
    func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {   // (not private: used by PinPageLink.swift)
        Button(action: action) {
            roundButtonLook {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The look of a small round icon button: the symbol on a grey circle, inside a touch area
    /// of at least 44 × 44 pt (Apple's minimum; the circle itself stays small).
    func roundButtonLook<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {   // (not private: used by PinPageLink.swift)
        content()
            .padding(8)
            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// "Written by AI", and — when the AI replaced an earlier title — Undo, which puts
    /// that earlier title back.
    private func aiTitleNote(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Label("Written by AI", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if pin.canUndoAITitle {
                    Button {
                        undoAITitle()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Puts back the title from before the AI renamed this pin.")
                }
            }
            if pin.canUndoAITitle, let previous = pin.titleUndo?.previous.title, !previous.isEmpty {
                Text("was “\(previous)”")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// What tapping an AI suggestion does (see `chooseSuggested`). `onBoards`: the pin, or the
    /// result not saved yet, already shows boards (a result keeps its feed's boards too).
    private func suggestionCaption(onBoards: Bool) -> String {
        if !isDraft { return "AI suggestions — tap to add" }
        return onBoards ? "AI suggestions — tap to save there too" : "AI suggestions — tap to save there"
    }

    @ViewBuilder
    func boardSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        // Only the boards of the pin's side (a hidden pin filed on a normal board out of sight never shows it).
        let shownBoards = store.shownBoardIDs(for: pin)
        sectionHeader(isDraft ? "Save to a board" : "Boards", icon: "folder")
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if shownBoards.isEmpty {
                    Text(isDraft ? "Choose a board when saving, or save without one." : "Not on a board yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // Each board is a link: tap it to open that board.
                    FlowLayout(spacing: 8) {
                        ForEach(shownBoards, id: \.self) { boardID in
                            if let path = store.boardPath(boardID) {
                                NavigationLink(value: Route.board(boardID)) {
                                    Label(path, systemImage: store.isSecretBoard(boardID) ? "lock.fill" : "folder.fill")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let reason = pin.placementReason, !shownBoards.isEmpty {
                    Label(reason, systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isDraft, !shownBoards.isEmpty {
                    // A result from a board's feed (or a pin's) starts out on its boards.
                    Text(shownBoards.count == 1 ? "Save puts it on this board — or choose another."
                                                : "Save puts it on these boards — or choose another.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(isDraft ? "Choose" : (shownBoards.isEmpty ? "Choose" : "Add")) {
                if isDraft {
                    boardPicker = .save
                } else {
                    pinActions.perform(.addToBoard, on: [pin.id], side: pageScope, place: .pinPage)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if !isDraft, store.isHidden(pin) {
            Label("Hidden pin — it shows only in Boards › ⋯ › Hidden.", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if pin.needsAnalysis || (isDraft && draft.status != .ready) {
            Label("The AI is still looking at this pin…", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !shownBoards.isEmpty && !showSuggestionsAnyway {
            Button("Suggest other boards") { showSuggestionsAnyway = true }
                .font(.caption)
        } else if suggestions.isEmpty {
            if store.boards.isEmpty {
                Text("Create a board and the AI will start suggesting where pins belong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No board stands out for this pin yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(suggestionCaption(onBoards: !shownBoards.isEmpty))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button {
                        chooseSuggested(suggestion.board.id, for: pin)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text(suggestion.board.name)
                                Text("\(Int(suggestion.score * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            if !suggestion.evidence.isEmpty {
                                Text("because: " + suggestion.evidence.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    func yourTagsSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        sectionHeader("Your tags", icon: "tag")
        if !pin.tags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(pin.tags, id: \.self) { tag in
                    TagChip(text: tag, style: .user) {
                        removeTag(tag)
                    }
                }
            }
        }
        HStack {
            NativeTextField(placeholder: "Add a tag", text: $newTag, autocapitalization: .none) {
                submitTag()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Add", action: submitTag)
                .buttonStyle(.borderedProminent)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // While you type: your own tags that match, then tags the AI has used.
        let suggested = store.tagSuggestions(matching: newTag, excluding: pin.tags, scope: store.scope(of: pin))
        if !suggested.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(suggested) { suggestion in
                    Button {
                        addTags([suggestion.tag])
                        newTag = ""
                    } label: {
                        Label(suggestion.tag, systemImage: suggestion.isUser ? "person" : "sparkles")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(suggestion.isUser ? settings.accentColor : Color.secondary)
                }
            }
        }
    }

    /// Whether the cloud model looks at this pin too (a hidden pin only with "Include hidden pins").
    private func usesCloud(_ pin: Pin) -> Bool {
        isDraft ? settings.cloudActive && (!pin.isHidden || settings.aiIncludesHidden) : store.cloudMaySee(pin)
    }

    @ViewBuilder
    func aiTagsSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        let kept = Set(pin.tags.map { $0.lowercased() })
        let aiTags = pin.aiTags.filter { !kept.contains($0.label.lowercased()) }
        let colors = pin.colorTags.filter { !kept.contains($0.lowercased()) }
        HStack {
            sectionHeader("AI tags", icon: "sparkles")
            Spacer()
            if !isDraft {
                Button {
                    store.reanalyze([pin.id])
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(pin.needsAnalysis)
            }
        }
        if pin.needsAnalysis || (isDraft && draft.status != .ready) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(usesCloud(pin) ? "Analyzing on this device and in the cloud…" : "Analyzing on this device…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if pin.aiTags.isEmpty && pin.colorTags.isEmpty {
            Text("The AI couldn't find anything it recognizes here. Add your own tags above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if aiTags.isEmpty && colors.isEmpty {
            Text("You have kept every tag the AI found.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(aiTags, id: \.label) { tag in
                    TagChip(text: "\(tag.label) \(Int(tag.confidence * 100))%", style: .ai) {
                        addTags([tag.label])
                    }
                }
                ForEach(colors, id: \.self) { color in
                    TagChip(text: color, style: .ai) {
                        addTags([color])
                    }
                }
            }
            Text("Tap an AI tag to keep it as one of your own tags.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func textSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        if !pin.isText, !pin.ocrTags.isEmpty || !pin.ocrText.isEmpty {
            sectionHeader("Text in this image", icon: "text.viewfinder")
            if !pin.ocrTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(pin.ocrTags.filter { !pin.tags.contains($0) }, id: \.self) { word in
                        TagChip(text: word, style: .text) {
                            addTags([word])
                        }
                    }
                }
            }
            if !pin.ocrText.isEmpty {
                Text(pin.ocrText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
        }
    }

    /// Things the photo file itself said, plus the duplicate pair when there is one.
    @ViewBuilder
    func infoSection(_ pin: Pin) -> some View {   // (not private: used by PinDetailView.swift)
        let hasFileInfo = pin.capturedAt != nil || pin.cameraModel != nil || !pin.fileKeywords.isEmpty || pin.fileCaption != nil
        // Only a twin on the same side of the hidden line (a draft counts as a normal pin).
        let twin: Pin? = store.duplicateTwin(of: pin)
        if hasFileInfo || twin != nil {
            sectionHeader("Details", icon: "info.circle")
            VStack(alignment: .leading, spacing: 10) {
                if let twin {
                    if isDraft {
                        HStack(spacing: 8) {
                            Image(systemName: "square.on.square").foregroundStyle(.secondary)
                            NavigationLink(value: Route.pin(twin.id, .none)) {
                                Text("Looks like a duplicate of “\(twin.title.isEmpty ? "another pin" : twin.title)” in your library")
                                    .font(.footnote)
                            }
                            Spacer()
                            Button("Ignore") { draft.pin.duplicateOfID = nil }
                                .font(.caption)
                        }
                    } else {
                        Text("Looks like a duplicate")
                            .font(.footnote.weight(.semibold))
                        // The newer copy is the one that points at the older one.
                        DuplicatePairView(newer: pin.createdAt >= twin.createdAt ? pin : twin,
                                          older: pin.createdAt >= twin.createdAt ? twin : pin,
                                          showsCards: true)
                    }
                }
                if let taken = pin.capturedAt {
                    detailLine("calendar", "Taken \(taken.formatted(date: .long, time: .shortened))")
                }
                if let camera = pin.cameraModel { detailLine("camera", camera) }
                if pin.latitude != nil { detailLine("location", "Has location data (kept for export only, never sent)") }
                if !pin.fileKeywords.isEmpty { detailLine("tag", "Keywords in the file: " + pin.fileKeywords.joined(separator: ", ")) }
                if let caption = pin.fileCaption { detailLine("text.quote", caption) }
            }
        }
    }

    private func detailLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).font(.footnote)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Bottom feeds (library, then the web, in one scroll)

    private var webAvailable: Bool { settings.webAllowed }

    /// The two tabs. Tapping one scrolls to that section; scrolling by hand
    /// moves the highlight along with you.
    func feedTabs(_ pin: Pin, proxy: ScrollViewProxy) -> some View {   // (not private: used by PinDetailView.swift)
        Picker("Feed", selection: feedBinding(pin, proxy: proxy)) {
            let shownCount = shownRelated.count
            Text("More like this\(shownCount == 0 ? "" : " (\(shownCount)\(related.count >= relatedLimit ? "+" : ""))")").tag(PinFeedMode.related)
            if webAvailable {
                Text("From the web").tag(PinFeedMode.web)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, PinTheme.gridSpacing)
        .padding(.vertical, 8)
        .background {
            GeometryReader { proxy in
                let height = proxy.size.height
                Color.clear.task(id: height) { if height > 0 { feedTabsHeight = height } }
            }
        }
    }

    @ViewBuilder
    func feedSection(_ pin: Pin, metrics: GridMetrics, proxy: ScrollViewProxy, scrollTop: CGFloat, viewportHeight: CGFloat) -> some View {   // (not private: used by PinDetailView.swift)
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            // The tabs, in the page. When they reach the top of the screen the
            // floating copy takes over (see `pageBody`), so they never scroll away.
            feedTabs(pin, proxy: proxy)
                .id("feed-related")
                .padding(.horizontal, -PinTheme.gridSpacing)
                .background {
                    GeometryReader { marker in
                        let reached = marker.frame(in: .global).minY <= scrollTop + 1
                        Color.clear.task(id: reached) {
                            withAnimation(.easeInOut(duration: 0.15)) { feedBarVisible = reached }
                        }
                    }
                }

            sectionHeader("More like this", icon: "sparkles")
            let shown = shownRelated
            if shown.isEmpty {
                Text(pin.needsAnalysis || (isDraft && draft.status != .ready)
                     ? "Similar pins appear here once the AI has looked at this pin."
                     : "Nothing similar in your library yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                let textStyle = settings.textStyle
                let shownIDs = shown.map { $0.id }
                MasonryGrid(items: shown, metrics: metrics,
                            aspectRatio: { $0.aspectRatio },
                            footerHeight: { PinCardView.footerHeight(for: $0, caption: nil) },
                            cardHeight: { other, width in
                                PinCardView.fixedHeight(for: other, width: width, textStyle: textStyle)
                            }) { other in
                    NavigationLink(value: Route.pin(other.id, PinContext(ids: shownIDs, around: other.id))) {
                        PinCardView(pin: other)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // The same long-press actions as a grid card (all but "Select").
                        PinActionMenuItems(pins: [other.id], side: pageScope, place: .related, actions: pinActions)
                    }
                }
                if related.count >= relatedLimit {
                    Button {
                        relatedLimit += 40
                    } label: {
                        Label("Show more", systemImage: "chevron.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }

            if webAvailable {
                // The web section. It starts with a spacer as tall as the floating
                // tabs, so "jump to the web" lands with its heading fully visible, and
                // it is at least a screen tall so it can always be scrolled to the top.
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: feedTabsHeight)
                        .id("feed-web")
                        .overlay(alignment: .bottom) { Divider() }
                        .background {
                            GeometryReader { marker in
                                let active = marker.frame(in: .global).minY <= scrollTop + 2
                                Color.clear.task(id: active) { feedMode = active ? .web : .related }
                            }
                        }
                    HStack {
                        sectionHeader("From the web", icon: "globe")
                        Spacer()
                        if webWanted, !webQuery.isEmpty, !webThinking {
                            Button {
                                webVariant += 1
                                startWebQuery(for: pin, avoiding: webQuery)
                            } label: {
                                Label("Different ideas", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                    }
                    webFeed(pin, metrics: metrics)
                }
                .frame(minHeight: max(0, viewportHeight - feedTabsHeight + 24), alignment: .top)
            }
        }
    }

    /// The similar pins that still belong here: live (not in Recently Deleted) and on this
    /// page's side of the library. Read fresh from the store, so a turned or renamed pin
    /// shows its new look and a deleted or hidden one disappears at once.
    private var shownRelated: [Pin] {
        related.compactMap { store.livePin($0.id) }.filter { store.scope(of: $0) == pageScope }
    }

    /// The tabs jump to their section (and start the web search on first use).
    private func feedBinding(_ pin: Pin, proxy: ScrollViewProxy) -> Binding<PinFeedMode> {
        Binding(get: { feedMode }, set: { mode in
            feedMode = mode
            if mode == .web, !webWanted {
                webWanted = true
                startWebQuery(for: pin, avoiding: nil)
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(mode == .web ? "feed-web" : "feed-related", anchor: .top)
            }
        })
    }

    @ViewBuilder
    private func webFeed(_ pin: Pin, metrics: GridMetrics) -> some View {
        if !webWanted {
            VStack(spacing: 10) {
                Text("Search \(settings.webSource.label) for images like this one. Anything you save goes on the same boards as this pin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    webWanted = true
                    startWebQuery(for: pin, avoiding: nil)
                } label: {
                    Label("Continue from the web", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if webThinking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(settings.appleIntelligenceActive
                     ? "Apple Intelligence is composing a search from this pin…"
                     : "Choosing a search from this pin's tags…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !webQuery.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: webUsedAI ? "sparkles" : "tag")
                    .foregroundStyle(.secondary)
                Text("Searching for “\(webQuery)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Change") { editingWebQuery = true }
                    .font(.caption)
            }
            // Saved results go on this pin's (shown) boards — for a web result not saved yet, the
            // boards of the feed it came from — on the page's side: a hidden pin's (or a hidden
            // feed's web result's) results go into Hidden, a normal pin's never there.
            WebFeedView(query: webQuery, boardIDs: store.shownBoardIDs(for: pin),
                        hidden: pageScope == .hidden, metrics: metrics)
        }
    }

    /// Picks the search words: a hint the cloud model left, Apple Intelligence
    /// (given everything known about the pin, your words first), or the tags.
    /// Cancelled when the page moves on to another pin.
    private func startWebQuery(for pin: Pin, avoiding: String?) {
        webTask?.cancel()
        webThinking = true
        let names = store.boardNames(for: pin)
        let variant = webVariant
        let useAI = settings.appleIntelligenceActive && store.aiMaySee(pin)   // a hidden pin: the tags' words only
        webTask = Task { @MainActor in
            let fallback = WebQueryBuilder.fallbackQuery(for: pin, boardNames: names, variant: variant)
            let chosen = await WebQueryBuilder.query(for: pin, boardNames: names, variant: variant, avoid: avoiding, useAI: useAI)
            guard !Task.isCancelled else { return }
            webUsedAI = chosen != fallback
            webQuery = chosen
            webThinking = false
        }
    }

    func sectionHeader(_ title: String, icon: String) -> some View {   // (not private: used by PinPageLink.swift)
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func submitTag() {
        addTags([newTag])
        newTag = ""
    }
}
