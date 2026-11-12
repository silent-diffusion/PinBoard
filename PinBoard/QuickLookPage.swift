//
//  QuickLookPage.swift  —  PinBoard
//
//  The parts Quick Look (QuickLook.swift) is built from: the info panel that
//  slides in from the right edge, one page of the feed (a zoomable picture, a
//  video, text or a link) and the zoom view under a picture.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Foundation

/// What a button in Quick Look's info panel asks for (Quick Look opens the sheet, or asks the pin
/// actions: tags, boards, and a link pin's Open link and Edit link…).
enum QuickLookInfoAction {
    case close, editTitle, editNote, editTags, addToBoard, moveToBoard, openLink, editLink, saveWeb, saveWebToBoard
}

/// Quick Look's info panel (swipe in from the right edge, or ⋯ › Show info): a pin's
/// title, note, tags and boards with buttons to change them, or a web result's source —
/// while the picture or video keeps showing (and playing) beside it.
struct QuickLookInfoPanel: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings   // the originals folder's name
    let item: ViewerItem
    var webSaved: Bool = false
    var onAction: (QuickLookInfoAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch item {
                    case .pin(let stale):
                        pinInfo(store.livePin(stale.id) ?? stale)
                    case .web(let web):
                        webInfo(web)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Info")
                .font(.headline)
            Spacer()
            Button {
                onAction(.close)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close info")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
    }

    // A stored pin

    private func pinInfo(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            titleSection(pin)
            section("Note") {
                Text(pin.note.isEmpty ? "No note yet." : pin.note)
                    .font(.subheadline)
                    .foregroundStyle(pin.note.isEmpty ? Color.secondary : Color.primary)
                actionButton(pin.note.isEmpty ? "Add a note" : "Edit note", icon: "square.and.pencil", action: .editNote)
            }
            tagsSection(pin)
            boardsSection(pin)
            if pin.isVideo {
                section("Video") {
                    Label(VideoTools.durationText(pin.duration) ?? "Length not known yet", systemImage: "timer")
                        .font(.subheadline)
                    Label(soundText(pin), systemImage: pin.hasAudio == false ? "speaker.slash" : "speaker.wave.2")
                        .font(.subheadline)
                }
            }
            if pin.isLink {
                linkSection(pin)
            }
            if pin.originalName != nil {
                originalSection(pin)
            }
            section("Added") {
                Text(pin.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
            }
        }
    }

    /// "Original · 48 MB · iCloud Drive › PinBoard Originals" (⋯ › Show original opens it).
    private func originalSection(_ pin: Pin) -> some View {
        section("Storage") {
            Label(StorageText.originalLine(bytes: pin.originalBytes, folderName: settings.originalsFolderName),
                  systemImage: "externaldrive")
                .font(.subheadline)
        }
    }

    private func titleSection(_ pin: Pin) -> some View {
        section("Title") {
            Text(pin.title.isEmpty ? "No title" : pin.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(pin.title.isEmpty ? Color.secondary : Color.primary)
            if pin.titleIsAuto, !pin.title.isEmpty {
                Label("Written by AI", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            actionButton(pin.title.isEmpty ? "Add a title" : "Edit title", icon: "pencil", action: .editTitle)
        }
    }

    private func tagsSection(_ pin: Pin) -> some View {
        section("Your tags") {
            if pin.tags.isEmpty {
                Text("No tags yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(pin.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                }
            }
            actionButton("Edit tags…", icon: "tag", action: .editTags)
        }
    }

    /// Only the boards shown for this pin: a normal pin never names a hidden board.
    private func boardsSection(_ pin: Pin) -> some View {
        let paths = store.shownBoardIDs(for: pin).compactMap { store.boardPath($0) }
        return section("Boards") {
            if paths.isEmpty {
                Text("Not on a board yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paths, id: \.self) { path in
                    Label(path, systemImage: "folder")
                        .font(.subheadline)
                }
            }
            // Named like the same commands in the pin menus (PinAction.label). They wrap onto two
            // lines when the panel is narrow rather than shortening a name.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { boardButtons(onABoard: !paths.isEmpty) }
                VStack(alignment: .leading, spacing: 8) { boardButtons(onABoard: !paths.isEmpty) }
            }
        }
    }

    /// "Add to board…" and "Move to board…", with the names and symbols of the pin menus.
    /// A pin on no board gets only "Add to board…" (there is nothing to move it from).
    @ViewBuilder
    private func boardButtons(onABoard: Bool) -> some View {
        let add = PinAction.addToBoard.label(count: 1)
        let move = PinAction.moveToBoard.label(count: 1)
        actionButton(add.text, icon: add.icon, action: .addToBoard)
        if onABoard {
            actionButton(move.text, icon: move.icon, action: .moveToBoard)
        }
    }

    /// A link pin's address, with "Open link" (a web address only) and "Edit link…" — named like
    /// the same commands in the pin menus, and wrapping onto two lines in a narrow panel.
    private func linkSection(_ pin: Pin) -> some View {
        section("Link") {
            if let link = pin.linkURL {
                Text(link)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { linkButtons(pin) }
                VStack(alignment: .leading, spacing: 8) { linkButtons(pin) }
            }
        }
    }

    @ViewBuilder
    private func linkButtons(_ pin: Pin) -> some View {
        let open = PinAction.openLink.label(count: 1)
        let edit = PinAction.editLink.label(count: 1)
        if PinActionRules.linkToOpen(pin) != nil {
            actionButton(open.text, icon: open.icon, action: .openLink)
        }
        actionButton(edit.text, icon: edit.icon, action: .editLink)
    }

    private func soundText(_ pin: Pin) -> String {
        switch pin.hasAudio {
        case true?: return "With sound"
        case false?: return "Without sound"
        case nil: return "Sound not checked yet"
        }
    }

    // A web result

    private func webInfo(_ web: WebImage) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Title") {
                Text((web.title ?? "").isEmpty ? "No title" : (web.title ?? ""))
                    .font(.title3.weight(.semibold))
                if let linked = web.linkedCredit {
                    Text(linked.attributed)   // Unsplash: the photographer and Unsplash, each a link
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let credit = web.credit, !credit.isEmpty {
                    Text(credit)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            section("Source") {
                Link(destination: web.pageURL) {
                    Label(web.pageURL.host ?? "Open source page", systemImage: "safari")
                        .font(.subheadline)
                }
            }
            section("Save") {
                Button {
                    onAction(.saveWeb)
                } label: {
                    Label(webSaved ? "Saved" : "Save to library", systemImage: webSaved ? "checkmark" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(webSaved)
                actionButton("Save to board…", icon: "folder.badge.plus", action: .saveWebToBoard)
            }
        }
    }

    // Building blocks

    private func section<Content: View>(_ heading: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func actionButton(_ title: String, icon: String, action: QuickLookInfoAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// One item of Quick Look (a stored pin or a web result), loaded at the quality
/// its distance from the page in front deserves: pictures zoomable, videos in
/// PinBoard's own player (only the one in front plays), text fitted to the screen.
/// For VoiceOver each page says what it is, its title and where it is in the feed
/// ("Photo, Sunset, 3 of 20"); symbols that only decorate are left out.
struct QuickLookPage: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    let item: ViewerItem
    var distance: Int = 0
    var isCurrent: Bool = true
    /// The page's place in the feed, from 1, and how many the feed has now (for VoiceOver).
    var number: Int = 1
    var count: Int = 1
    /// Where the video controls may go: the cover's safe area (plus the info panel's width).
    var controlsInsets: EdgeInsets = EdgeInsets()
    /// Where words may go (text and link pages, "Couldn't load"): the cover's safe area, plus
    /// the info panel's width when there is still room to read beside it.
    var textAreaInsets: EdgeInsets = EdgeInsets()
    /// Quick Look's line to its video players (speed, the video in front, paused or not).
    var videoHandle: VideoPlayerHandle? = nil
    var onZoomChange: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}

    @State private var image: UIImage? = nil
    @State private var failed = false
    @State private var hasFull = false      // the picture in `image` is the full-size one
    @State private var fromICloud = false   // the full picture is coming from iCloud (Optimize device storage)
    @State private var iCloudPercent: Double? = nil
    @State private var iCloudStalled = false   // no news from iCloud for a while: "Still downloading…" with Retry
    @State private var iCloudProblem: CloudFetchProblem? = nil   // it couldn't come, and why (the thumbnail stays)
    @State private var attempt = 0          // "Try again" counts up, which loads anew
    @State private var watch = CloudDownloadWatch()

    private var quality: PageQuality { PageQuality(distance: distance) }

    /// Goes up whenever a stored pin's picture file is rewritten (turned, flipped, cropped — the
    /// file keeps its name), so the page loads the picture again. 0 for a web result.
    private var pictureRevision: Int {
        if case .pin(let pin) = item { return pin.pictureRevision }
        return 0
    }

    var body: some View {
        page
            .overlay(alignment: .bottom) { iCloudNote }   // (outside the picture, so VoiceOver reaches "Try again")
            .task(id: "\(item.id)|\(quality)|\(pictureRevision)|\(attempt)") {
                await load()
            }
            .onDisappear { watch.stop() }
    }

    /// The page for this kind of item.
    @ViewBuilder
    private var page: some View {
        switch item {
        case .pin(let pin) where pin.isText:
            textPage(pin)
        case .pin(let pin) where pin.isVideo:
            if distance <= 1 {
                videoPage(pin)
            } else {
                // Further away: just the poster frame.
                picturePage(ZoomableImageView(image: image, failed: failed, isActive: false, onZoomChange: onZoomChange))
            }
        case .pin(let pin) where pin.isLink && !pin.hasPreview:
            linkPage(pin)
        case .pin(let pin) where pin.isLink:
            // A link's preview picture, with a way to its page.
            picturePage(ZoomableImageView(image: image, failed: failed, isActive: isCurrent,
                                          onSingleTap: onTap, onZoomChange: onZoomChange))
                .overlay(alignment: .bottom) { openLinkOverlay(pin) }
        default:
            picturePage(ZoomableImageView(image: image, failed: failed, isActive: isCurrent,
                                          onSingleTap: onTap, onZoomChange: onZoomChange))
        }
    }

    /// What VoiceOver says for the page: what it is, its title and where it is in the feed —
    /// "Photo, Sunset, 3 of 20" ("Web image, …" for a result from the web), and whether its
    /// picture couldn't be loaded.
    private var spokenName: String {
        var parts: [String] = []
        switch item {
        case .pin(let pin):
            parts.append(PinCardView.kindName(pin.kind))
            if !pin.title.isEmpty { parts.append(pin.title) }
        case .web(let web):
            parts.append("Web image")
            if let title = web.title, !title.isEmpty { parts.append(title) }
        }
        parts.append("\(number) of \(count)")
        if failed && image == nil { parts.append("couldn't be loaded") }
        return parts.joined(separator: ", ")
    }

    /// A picture (or a video's poster frame): zoomable, and one element for VoiceOver.
    private func picturePage(_ picture: ZoomableImageView) -> some View {
        picture
            .ignoresSafeArea()
            .overlay { failureNote }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenName)
            .accessibilityAddTraits(.isImage)
    }

    /// One player per video, kept while it is in front or next to it. Its controls sit at the
    /// bottom, inside `controlsInsets`, so they never meet ✕ / ⋯ at the top; the play and skip
    /// buttons are in the middle. For VoiceOver the page is named and its controls (play, skip,
    /// position, sound) stay reachable inside it. Only the page in front is "the video in front".
    private func videoPage(_ pin: Pin) -> some View {
        BroughtBack(pin: pin) {   // a video kept in iCloud only comes back first (Offloading.swift)
            VideoPlayerView(url: store.videoFileURL(for: pin), playing: isCurrent,
                            controlsInsets: controlsInsets,
                            handle: videoHandle, isFront: isCurrent)
        }
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenName)
    }

    /// Just the text, comfortably large and fitted to the screen (no scrolling of its own, so
    /// swiping up and down always moves through the feed). VoiceOver reads the name, then the text.
    private func textPage(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !pin.title.isEmpty {
                Text(pin.title)
                    .font(settings.textStyle.swiftFont(size: settings.textStyle.pageSize * 1.3, weight: .bold))
            }
            Text(pin.textBody)
                .font(settings.textStyle.swiftFont(size: settings.textStyle.pageSize * 1.1))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 720, alignment: .leading)
        .padding(textInsets(margin: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenName)
        .accessibilityValue(pin.textBody)
    }

    /// Where words may go on a page, which fills the whole screen: inside the safe area (clear
    /// of the camera housing and the home indicator; see `textAreaInsets`), below ✕ and ⋯
    /// (the room the video controls leave them too), and `margin` further in.
    private func textInsets(margin: CGFloat) -> EdgeInsets {
        EdgeInsets(top: textAreaInsets.top + VideoControlBar.topClearance,
                   leading: textAreaInsets.leading + margin,
                   bottom: textAreaInsets.bottom + margin,
                   trailing: textAreaInsets.trailing + margin)
    }

    /// A link without a preview picture: its title and address, and "Open link". For VoiceOver
    /// the page is named (its title is in the name, so the title line itself is skipped); the
    /// address and "Open link" stay inside it.
    private func linkPage(_ pin: Pin) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "link").font(.largeTitle)
                .accessibilityHidden(true)   // only decoration
            Text(pin.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                .accessibilityHidden(true)   // said in the page's name
            if let text = pin.linkURL {
                Text(text).font(.footnote).foregroundStyle(Color.white.opacity(0.7)).multilineTextAlignment(.center)
            }
            if let url = PinActionRules.linkToOpen(pin) {
                openLinkButton(url)
            }
        }
        .foregroundStyle(.white)
        .padding(textInsets(margin: 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spokenName)
    }

    /// "Open link" over a link's preview picture: at the bottom, inside the safe area (and beside
    /// the info panel while it is open). A link whose address isn't a web page has none.
    @ViewBuilder
    private func openLinkOverlay(_ pin: Pin) -> some View {
        if let url = PinActionRules.linkToOpen(pin) {
            openLinkButton(url)
                .padding(.leading, controlsInsets.leading)
                .padding(.trailing, controlsInsets.trailing)
                .padding(.bottom, controlsInsets.bottom + 24)
        }
    }

    /// The "Open link" button itself (named and drawn like the pin menus' Open link).
    private func openLinkButton(_ url: URL) -> some View {
        let label = PinAction.openLink.label(count: 1)
        return Link(destination: url) {
            Label(label.text, systemImage: label.icon)
        }
        .buttonStyle(.borderedProminent)
    }

    /// "Couldn't load this image", in the middle of the page and, like the text pages, clear of
    /// ✕ / ⋯ and the camera housing. Large text wraps instead of being cut off. (When iCloud is the
    /// reason, the note at the bottom says why instead.)
    @ViewBuilder
    private var failureNote: some View {
        if failed && image == nil && iCloudProblem == nil {
            Text("Couldn't load this image")
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(textInsets(margin: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }

    /// Under a picture whose full size is coming from iCloud: how far it has got ("Getting the
    /// picture from iCloud… 40%"); after a while with no news, "Still downloading from iCloud (40%)"
    /// with Retry; or, when it couldn't come, why (offline, missing from iCloud, iCloud's error) with
    /// Retry — the smaller copy stays on screen meanwhile.
    @ViewBuilder
    private var iCloudNote: some View {
        if fromICloud && !iCloudStalled {
            FromICloudNote(what: "picture", percent: iCloudPercent)
                .padding(.bottom, controlsInsets.bottom + 24)
                .allowsHitTesting(false)
        } else if fromICloud {
            CloudProblemNote(problem: .stillDownloading(iCloudPercent.map { Int($0.rounded()) })) {
                if case .pin(let pin) = item { store.askICloudAgain(for: pin) }
                iCloudStalled = false
            }
            .padding(textInsets(margin: 24))
        } else if let iCloudProblem {
            CloudProblemNote(problem: iCloudProblem) { attempt += 1 }
                .padding(textInsets(margin: 24))
        }
    }

    /// The full picture of a stored pin. The thumbnail shows at once while it loads; a picture
    /// kept in iCloud only (Optimize device storage), or missing here while iCloud has it, starts
    /// coming at once and shows how far iCloud has got. If it can't come, the thumbnail stays with
    /// the reason and Retry, instead of an empty page or a long spinner.
    private func loadFullPicture(of pin: Pin) async {
        if image == nil {
            image = await store.thumbnail(for: pin)
        }
        iCloudProblem = nil
        iCloudStalled = false
        let cloudFile = pin.isVideo ? nil : store.cloudFileToFetch(pin)   // (a video's poster needs no video)
        var stallWatch: Task<Void, Never>? = nil
        if let cloudFile {
            fromICloud = true
            iCloudPercent = nil
            let lastNews = NewsClock()
            watch.start(cloudFile) { (value: Double) in
                if value != iCloudPercent { lastNews.last = Date() }
                iCloudPercent = value
                iCloudStalled = false
            }
            // No news from iCloud for 20 seconds: say so, with Retry (the download goes on).
            stallWatch = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { return }
                    if Date().timeIntervalSince(lastNews.last) > 20 {
                        iCloudStalled = true
                        lastNews.last = Date()
                    }
                }
            }
        }
        let problem = cloudFile == nil ? nil : await store.ensureLocalForViewing(pin)
        let full = problem == nil ? await store.fullImage(for: pin) : nil
        stallWatch?.cancel()
        watch.stop()
        fromICloud = false
        iCloudStalled = false
        if Task.isCancelled { return }
        if let full {
            image = full
            hasFull = true
        } else if let problem {
            iCloudProblem = problem   // (no problem but no picture: it came and couldn't be shown — "Couldn't load this image")
        }
        failed = image == nil
    }

    private func load() async {
        switch quality {
        case .placeholder:
            image = nil
            hasFull = false
            failed = false
        case .thumbnail:
            switch item {
            case .pin(let pin):
                guard pin.hasImageFile else { return }
                image = await store.thumbnail(for: pin)   // the store keeps only a few full pictures anyway
                hasFull = false
            case .web(let web):
                // A full picture already fetched is kept (downloading it again would cost more than the memory).
                if hasFull { return }
                image = RemoteImageCache.shared.image(for: web.thumbURL)
            }
        case .full:
            switch item {
            case .pin(let pin):
                guard pin.hasImageFile else { return }
                if pin.isVideo, distance <= 1 { return }   // the player shows the video itself
                await loadFullPicture(of: pin)
            case .web(let web):
                if let cached = RemoteImageCache.shared.fullImage(for: web.fullURL) {
                    image = cached
                    hasFull = true
                    failed = false
                    return
                }
                if image == nil { image = RemoteImageCache.shared.image(for: web.thumbURL) }   // something to look at meanwhile
                let url = web.fullURL
                let loaded = await Task.detached(priority: .userInitiated) { () -> LoadedImage in
                    guard let data = try? await WebImageService.download(url),
                          let cgImage = ImageProcessor.downsample(data, maxPixelSize: 2048) else {
                        return LoadedImage(image: nil)
                    }
                    return LoadedImage(image: UIImage(cgImage: cgImage))
                }.value
                if Task.isCancelled { return }
                if let full = loaded.image {
                    RemoteImageCache.shared.storeFull(full, for: url)
                    image = full
                    hasFull = true
                }
                failed = image == nil
            }
        }
    }
}

/// One picture with pinch-to-zoom, pan (kept within the picture) and double-tap
/// to zoom in at the tap point — a UIScrollView, which handles all of that
/// natively and hands horizontal swipes back to the pager when not zoomed in.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    var failed: Bool = false
    var isActive: Bool = true
    var onSingleTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView(frame: .zero)
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        view.image = image
        view.showsFailure = failed
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.onSingleTap = onSingleTap
        view.onZoomChange = onZoomChange
        if view.image !== image { view.image = image }
        view.showsFailure = failed && image == nil
        if !isActive { view.resetZoom() }
    }
}

@MainActor
final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    var onSingleTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }

    var image: UIImage? {
        didSet {
            imageView.image = image
            resetZoom()
            setNeedsLayout()
            spinner.isHidden = image != nil || showsFailure
            if image != nil { spinner.stopAnimating() } else if !showsFailure { spinner.startAnimating() }
        }
    }

    /// The picture couldn't be loaded: no spinner. (QuickLookPage shows the words, in SwiftUI,
    /// where they can keep clear of ✕ / ⋯ and the camera housing.)
    var showsFailure = false {
        didSet {
            if showsFailure { spinner.stopAnimating(); spinner.isHidden = true }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(ZoomScrollView.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(ZoomScrollView.singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { nil }

    private var laidOutFor: CGSize = .zero
    private var laidOutImage: UIImage? = nil

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // The image view is exactly the picture's fitted size, so panning stays on the
        // picture. It is measured again only for a new picture or a new screen size
        // (never in the middle of a pinch, where the zoom transform is in play).
        if laidOutFor != bounds.size || laidOutImage !== image {
            laidOutFor = bounds.size
            laidOutImage = image
            let wasZoomed = zoomScale > 1.001
            if wasZoomed { zoomScale = 1 }
            let fitted = fittedSize()
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
        }
        centerImage()
    }

    private func fittedSize() -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds.size }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// Keeps a picture smaller than the screen in the middle.
    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(x: contentSize.width / 2 + offsetX, y: contentSize.height / 2 + offsetY)
    }

    func resetZoom() {
        if zoomScale != 1 { setZoomScale(1, animated: false) }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    /// Zoomed in or not, as last reported through `onZoomChange`.
    private var reportedZoomed = false

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        reportZoom()
    }

    /// Tells SwiftUI only when zoomed-in-or-not changes, and never right away: a zoom
    /// reset can happen inside SwiftUI's update (`updateUIView`), where state must not change.
    private func reportZoom() {
        let zoomed = zoomScale > 1.01
        guard zoomed != reportedZoomed else { return }
        reportedZoomed = zoomed
        Task { @MainActor [weak self] in
            self?.onZoomChange(zoomed)
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard image != nil else { return }
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            // Zoom in around the point that was tapped.
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() {
        onSingleTap()
    }
}

/// When Quick View last heard from iCloud about a download (to tell a stalled one).
@MainActor
private final class NewsClock {
    var last = Date()
}
