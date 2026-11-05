//
//  SmartLinksViews.swift  —  PinBoard
//
//  The screens of "Read links fully" (SmartLinks.swift): its switch, the YouTube key, what sites
//  are read and "Read existing links" in Settings › Links; the panel on a pin's page with what reading its link
//  found (an article's byline and "Read article"; a YouTube video's "Play", details,
//  description and top comments; where a Pinterest pin or a picture from the web came from);
//  the article reader (its text as one selectable piece, highlights drawn on it and listed
//  under it; the rules behind them are in ArticleHighlights.swift); and YouTube's own player.
//

import SwiftUI
import UIKit
import WebKit
import Foundation

// MARK: - Settings › Links

/// Settings › Links: "Read links fully", the YouTube API key, and "Read existing links".
struct SmartLinkSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @ObservedObject private var job = LinkReadingJob.shared
    @State private var showsKey = false

    var body: some View {
        Section {
            Toggle(SettingsCatalog.title(.readLinksFully), isOn: $settings.readLinksFully)
                .disabled(!settings.fetchLinkPreviews)
                .settingsRow(.readLinksFully)
            keyRow
                .settingsRow(.youTubeKey)
            if !settings.youTubeAPIKey.isEmpty {
                Toggle(SettingsWords.showKeys, isOn: $showsKey)
            }
            youTubeTermsRow
            readExistingRow
                .settingsRow(.readExistingLinks)
        } header: {
            SettingsHeader(section: .reading)
        } footer: {
            Text(footerText)
        }
    }

    private var keyRow: some View {
        HStack {
            Text(SettingsCatalog.title(.youTubeKey))
            NativeTextField(placeholder: "Optional",
                            text: $settings.youTubeAPIKey,
                            autocapitalization: .none,
                            autocorrection: false,
                            alignment: .right,
                            secure: !showsKey,
                            accessibilityLabel: "YouTube API key")   // (VoiceOver would say "Optional")
        }
    }

    /// YouTube's Terms of Service and Google's Privacy Policy, which YouTube's developer policies
    /// ask an app that uses its Data API to link to.
    private var youTubeTermsRow: some View {
        HStack {
            Link("YouTube Terms of Service", destination: SmartLinkSettingsSection.youTubeTermsURL)
            Spacer()
            Link("Google Privacy Policy", destination: SmartLinkSettingsSection.googlePrivacyURL)
        }
        .font(.footnote)
        .buttonStyle(.borderless)   // two links in one row: each is its own button
    }

    static let youTubeTermsURL = URL(string: "https://www.youtube.com/t/terms")!
    static let googlePrivacyURL = URL(string: "https://policies.google.com/privacy")!

    /// "Read existing links" — or, while it runs, how far it has got and "Stop". The normal side's
    /// links only (hidden pins have nothing here, as everywhere in Settings).
    @ViewBuilder
    private var readExistingRow: some View {
        if job.isRunning {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(job.progressText)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { job.stop() }
                    .buttonStyle(.borderless)   // only "Stop" is the button, not the whole row
                    .disabled(job.isStopping)
            }
        } else {
            Button(readExistingTitle) { startReading() }
                .disabled(!settings.readsLinksFully || unreadCount == 0)
        }
    }

    /// Links of the normal side that "Read existing links" takes: never read fully, or read
    /// without finding a picture (`LibraryStore.wantsReading`, the same rule the run goes by).
    private var unreadCount: Int {
        store.pins(scope: .visible).filter { (pin: Pin) -> Bool in LibraryStore.wantsReading(pin) }.count
    }

    private var readExistingTitle: String {
        let count = unreadCount
        let title = SettingsCatalog.title(.readExistingLinks)
        return count == 0 ? title : "\(title) (\(count))"
    }

    private func startReading() {
        let flow = importFlow
        job.start(store: store) { (summary: LinkReadingSummary) in
            flow.flash(summary.text, symbol: summary.read > 0 ? "checkmark.circle" : "info.circle")
        }
    }

    /// Which sites are read, and what can't be (said in the footer; the harness checks it mentions them).
    /// Videos are never saved from these sites or from inside a page (App Review guideline 5.2.3).
    static let sitesText = "Posts on Reddit, TikTok, Instagram and X are read as far as each site shows them to a visitor without an account: the caption, who posted it and its picture. A video on these sites, on Pinterest or inside any other web page is kept as a link with its picture and title; PinBoard doesn't download it. Pages behind a login (Facebook, private accounts) can't be read: such a link is added as a plain link, never as the login page."

    /// What "Read existing links" does, for the footer (the harness checks that it says it looks for pictures).
    static let readExistingText = "“Read existing links” reads the links you saved before, one at a time, and looks for a picture for those that have none (a link whose page has no picture to find stays in the list); links to a Pinterest picture pin or a picture file become picture pins."

    private var footerText: String {
        var lines = ["When you add a link, PinBoard reads the page: an article's text, writer and date; a Pinterest pin's picture and the page it links to; a YouTube video's title, channel and thumbnail from YouTube's own service — and its length, description and top comments with a YouTube Data API key (free from Google Cloud: enable “YouTube Data API v3”, then create an API key). YouTube videos play in YouTube's own player; nothing is downloaded from YouTube. A link straight to a picture or a video file (.mp4, .mov) becomes a picture or video pin."]
        lines.append(SmartLinkSettingsSection.sitesText)
        lines.append(SettingsWords.videoNote)
        lines.append("The key is sent only to YouTube's own service, under YouTube's Terms of Service and Google's Privacy Policy (the links above). " + SmartLinkSettingsSection.readExistingText)
        if !settings.fetchLinkPreviews {
            lines.append("Reading links needs “Fetch link previews” (above).")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - The pin page's panel

/// What reading a pin's link found, on the pin's page: right under the link panel of a link pin,
/// or under the title of a picture or video pin a link became. An article: its byline and "Read
/// article". A YouTube video: "Play", its details, description and top comments. A Pinterest pin
/// or a picture or video from the web: where it came from, and the page it links to. Any other
/// pin with a writer or a date: a byline. Nothing for a link that was never read.
struct LinkDetailsPanel: View {
    let pin: Pin

    /// Whether the panel has anything to show for `pin` (the page leaves it out otherwise). A
    /// plain rule, so the harness tests it.
    nonisolated static func hasContent(for pin: Pin) -> Bool {
        switch pin.linkFlavor {
        case .article?, .youTube?, .pinterest?, .imageFile?, .videoFile?:
            return true
        case .page?, nil:
            return LinkDetailsText.plainByline(for: pin) != nil
        }
    }

    var body: some View {
        switch pin.linkFlavor {
        case .article?:
            ArticleDetailsView(pin: pin)
        case .youTube?:
            YouTubeDetailsView(pin: pin)
        case .pinterest?, .imageFile?, .videoFile?:
            LinkSourceDetailsView(pin: pin)
        case .page?, nil:
            if let line = LinkDetailsText.plainByline(for: pin) {
                BylineText(text: line)
            }
        }
    }
}

/// The friendly note on a link pin from a site whose videos PinBoard doesn't download (TikTok,
/// Instagram, Reddit, X, Pinterest — App Review guideline 5.2.3): how to get the video in anyway.
/// Shown once, on the first such pin opened, until "Got it"; never again after that, so it doesn't nag.
struct PlatformVideoNote: View {
    let pin: Pin
    /// Kept on this device for all profiles: it is a hint, not a setting.
    @AppStorage("platformVideoNoteSeen") private var seen = false

    /// Whether `pin` is a link from one of those sites that may well be a video: kept as an ordinary
    /// link (a picture post became a picture pin, a post on X or a Reddit text post is an article),
    /// and for Reddit not a post that links on to another page. A plain rule, so the harness tests it.
    nonisolated static func applies(to pin: Pin) -> Bool {
        guard pin.isLink, pin.linkFlavor == .page, let link = pin.linkURL, let url = URL(string: link) else { return false }
        if RedditReader.isReddit(url) { return pin.linkedURL == nil }
        return TikTokReader.isTikTok(url) || InstagramReader.shortcode(in: url) != nil
            || TwitterReader.isPostLink(url) || LinkClassifier.isPinterest(url)
    }

    var body: some View {
        if !seen, PlatformVideoNote.applies(to: pin) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(SettingsWords.videoNote)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.subheadline)
                Button("Got it") { seen = true }
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// A byline: small, grey, one line or more.
struct BylineText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An article: "By Jane Doe · The Verge · Jan 2, 2024 · 5 min read", "Read article" and, when
/// passages were highlighted in it, the list of them (see `ArticleHighlightsSection`).
struct ArticleDetailsView: View {
    let pin: Pin
    @EnvironmentObject private var store: LibraryStore
    @State private var reading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let line = LinkDetailsText.articleByline(for: pin) {
                BylineText(text: line)
            }
            if !pin.textBody.isEmpty {
                Button {
                    reading = true
                } label: {
                    Label("Read article", systemImage: "doc.plaintext")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)   // at least 44 points tall, like the pin page's other buttons
            }
            if !pin.highlights.isEmpty {
                ArticleHighlightsSection(pin: pin)   // the passages marked in the reader: five rows, then "Show all"
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $reading) {
            // A sheet is a screen of its own: the pin page's cover doesn't reach it, so a hidden
            // pin's article gets its own (it never shows in the App Switcher).
            ArticleReaderSheet(pin: pin)
                .hiddenPrivacyCover(store.isHidden(pin))
        }
    }
}

/// A YouTube video: "Play" (YouTube's own player), "Channel · date · length · views", the
/// description (four lines, "More" shows it all) and the top comments.
struct YouTubeDetailsView: View {
    let pin: Pin
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @State private var playing = false
    @State private var expanded = false

    /// The video's id, from the pin's address.
    private var videoID: String? {
        guard let link = pin.linkURL, let url = URL(string: link) else { return nil }
        return LinkClassifier.youTubeID(in: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let videoID, settings.webAllowed {
                playButton(videoID)
            }
            if let line = LinkDetailsText.videoLine(for: pin, views: pin.viewCount) {
                BylineText(text: line)
            }
            if !pin.textBody.isEmpty {
                descriptionView
            }
            if !pin.comments.isEmpty {
                YouTubeCommentsView(comments: pin.comments)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Play": the page's one prominent button for a video (the link panel's "Open link" is
    /// plain then, see `LinkPanelView`).
    private func playButton(_ videoID: String) -> some View {
        Button {
            playing = true
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)   // at least 44 points tall
        .sheet(isPresented: $playing) {
            // Covered like every sheet of a hidden pin (see ArticleDetailsView). A hidden pin's video
            // never goes full screen: WebKit shows full screen in a window of its own, which no cover reaches.
            YouTubePlayerSheet(videoID: videoID, allowsFullScreen: !store.isHidden(pin))
                .hiddenPrivacyCover(store.isHidden(pin))
        }
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pin.textBody)
                .font(.body)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
            if LinkDetailsText.isLong(pin.textBody) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Less" : "More")
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44)   // a comfortable target, though the word is small
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

/// "Top comments": each comment's writer, text and likes.
struct YouTubeCommentsView: View {
    let comments: [PinComment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Top comments", systemImage: "text.bubble")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)   // VoiceOver's rotor can jump to it
            ForEach(comments.indices, id: \.self) { (index: Int) in
                YouTubeCommentRow(comment: comments[index])
            }
        }
    }
}

struct YouTubeCommentRow: View {
    let comment: PinComment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(comment.author)
                .font(.subheadline.weight(.semibold))
            Text(comment.text)
                .font(.body)
                .textSelection(.enabled)
            Text("♡ " + SmartLinkText.compactCount(comment.likes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LinkDetailsText.commentLabel(comment))   // (VoiceOver read "♡" as "white heart suit")
    }
}

/// A Pinterest pin, or a picture or video from the web: "From Pinterest", "By Jane Baker ·
/// date", "Open linked page (bakery.com)", and the pin's description when it has one of its own.
struct LinkSourceDetailsView: View {
    let pin: Pin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let from = LinkDetailsText.sourceLine(for: pin) {
                Label(from, systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
            }
            if let byline = LinkDetailsText.sourceByline(for: pin) {
                BylineText(text: byline)
            }
            if let linked = LinkDetailsText.linkedPage(for: pin) {
                Link(destination: linked.url) {
                    Label("Open linked page (\(linked.host))", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44)          // a comfortable target, though the text is small
                        .contentShape(Rectangle())
                }
                .font(.subheadline)
            }
            if let description = LinkDetailsText.extraDescription(for: pin) {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The lines the panel shows, worked out from a pin (plain rules; the harness tests them).
enum LinkDetailsText {
    /// "Jan 2, 2024" (the date the way this device writes dates, medium length).
    static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// "By Jane Doe · The Verge · Jan 2, 2024 · 5 min read" — whatever is known.
    static func articleByline(for pin: Pin) -> String? {
        let words = SmartLinkText.wordCount(pin.textBody)
        let minutes: String? = words > 0 ? "\(SmartLinkText.readingMinutes(words: words)) min read" : nil
        return SmartLinkText.joinedLine([pin.author.map { (name: String) -> String in "By " + name },
                                         pin.siteName, pin.publishedAt.map(mediumDate), minutes])
    }

    /// "Rick Astley · Oct 24, 2009 · 3:33" (and "1.6B views" once pins keep a view count) — whatever is known.
    static func videoLine(for pin: Pin, views: Int? = nil) -> String? {
        let length = pin.duration.flatMap { (seconds: Double) -> String? in SmartLinkText.lengthText(seconds) }
        let viewText = views.map { (count: Int) -> String in SmartLinkText.compactCount(count) + " views" }
        return SmartLinkText.joinedLine([pin.author, pin.publishedAt.map(mediumDate), length, viewText])
    }

    /// "From Pinterest", "From images.example.com": the site a picture or video came from.
    static func sourceLine(for pin: Pin) -> String? {
        let address = pin.sourceURL ?? pin.linkURL
        let host = address.flatMap { (link: String) -> String? in Pin.host(ofLink: link) }
        guard let site = SmartLinkText.cleaned(pin.siteName) ?? host else { return nil }
        return "From " + site
    }

    /// "By Jane Baker · Nov 12, 2019".
    static func sourceByline(for pin: Pin) -> String? {
        SmartLinkText.joinedLine([pin.author.map { (name: String) -> String in "By " + name }, pin.publishedAt.map(mediumDate)])
    }

    /// A byline for a pin with nothing flavour-specific to show: "By Jane Doe · Jan 2, 2024".
    static func plainByline(for pin: Pin) -> String? {
        sourceByline(for: pin)
    }

    /// The page a pin points on to (a Pinterest pin's destination), as an address and its host.
    static func linkedPage(for pin: Pin) -> (url: URL, host: String)? {
        guard let text = pin.linkedURL, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = Pin.host(ofLink: text) else { return nil }
        return (url, host)
    }

    /// A picture or video pin's own description from its link (a Pinterest pin's), unless the line
    /// under the title already shows exactly that (a shortened one, or the AI's, doesn't count).
    static func extraDescription(for pin: Pin) -> String? {
        guard !pin.isLink, let text = SmartLinkText.cleaned(pin.textBody) else { return nil }
        return text == SmartLinkText.collapse(pin.aiDescription) ? nil : text
    }

    /// A description longer than four lines' worth (so "More" is worth showing).
    static func isLong(_ text: String) -> Bool {
        text.count > 280 || text.components(separatedBy: "\n").count > 4
    }

    /// What VoiceOver says for a comment: "@fan: Still a classic. 1200 likes".
    static func commentLabel(_ comment: PinComment) -> String {
        let likes = comment.likes == 1 ? "1 like" : "\(comment.likes) likes"
        return "\(comment.author): \(comment.text). \(likes)"
    }
}

// MARK: - The article reader

/// "Read article": the article's text in a comfortable column — its title and byline, then the
/// text as one piece that can be selected across paragraphs (headings, list items and quotes
/// each set their own way), then the highlights made in it. Select a passage to highlight it,
/// save it as a pin or copy it; highlights stay with the article, on every device. Dynamic Type
/// sizes the text.
struct ArticleReaderSheet: View {
    let pin: Pin
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArticleReaderPage(pin: pin)
                .navigationTitle(pin.siteName ?? "Article")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        // The app's confirmations ("Saved as a pin") show over this sheet while it is up. Applied
        // outside the NavigationStack: the cover counts the screens it is on.
        .importFlowCover()
        .presentationDetents([.large])
        .largeSheetSizing()   // on iPad: a page-sized sheet, not the small form sheet
    }
}

/// The reader's scrolling page. It reads the article from the library as it is *now*, so a
/// highlight made here (or taken off in the list) shows at once, and the article's text is only
/// worked out again when it changes (`ArticleTextMemo`).
private struct ArticleReaderPage: View {
    let pin: Pin
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @State private var memo = ArticleTextMemo()

    /// The article as the library has it now.
    private var live: Pin {
        store.pin(pin.id) ?? pin
    }

    var body: some View {
        let article = live
        let text = memo.text(for: article.textBody)
        let resolved = ArticleHighlights.resolve(article.highlights, in: text)
        return page(article, text: text, resolved: resolved)
    }

    /// The scrolling page: title, text, then the list of highlights.
    private func page(_ article: Pin, text: ArticleText, resolved: [ResolvedHighlight]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock(article)
                ArticleBodyView(text: text,
                                highlights: resolved,
                                onHighlight: { (selection: NSRange) -> Void in
                                    highlight(selection, resolved: resolved, in: text)
                                },
                                onRemove: { (mark: TextHighlight) -> Void in
                                    store.removeHighlight(mark.id, from: article.id)
                                },
                                onSaveQuote: { (quote: String) -> Void in
                                    ArticleQuoteActions.saveAsPin(quote, from: article.id, store: store, importFlow: importFlow)
                                })
                highlightsList(article, resolved: resolved)
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { writeBackMovedHighlights() }
        .onChange(of: article.textBody) { writeBackMovedHighlights() }
    }

    /// The title, the byline and a line under them.
    private func titleBlock(_ article: Pin) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(article.title.isEmpty ? "Article" : article.title)
                .font(.title2.bold())
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if let line = LinkDetailsText.articleByline(for: article) {
                BylineText(text: line)
            }
            Divider()
        }
    }

    /// "Highlights (3)" under the text, when there are any.
    @ViewBuilder
    private func highlightsList(_ article: Pin, resolved: [ResolvedHighlight]) -> some View {
        if !article.highlights.isEmpty {
            ArticleHighlightsList(total: article.highlights.count,
                                  items: ArticleHighlights.inReadingOrder(resolved),
                                  limit: nil,
                                  actions: ArticleQuoteActions.rowActions(for: article.id, store: store, importFlow: importFlow))
        }
    }

    /// "Highlight" in the selection menu: the passage is added, folded together with any
    /// highlight it overlaps.
    private func highlight(_ selection: NSRange, resolved: [ResolvedHighlight], in text: ArticleText) {
        guard let marks = ArticleHighlights.adding(selection: selection, to: resolved, in: text) else { return }
        store.setHighlights(marks, for: pin.id)
    }

    /// An article that was read again has its text a little different: highlights that moved are
    /// saved at their new place, once, so the next opening finds them where they say they are.
    private func writeBackMovedHighlights() {
        let article = live
        let text = memo.text(for: article.textBody)
        let resolved = ArticleHighlights.resolve(article.highlights, in: text)
        if let marks = ArticleHighlights.updated(article.highlights, with: resolved) {
            store.setHighlights(marks, for: article.id)
        }
    }
}

/// The article's shown text, worked out from the saved text once and kept until the saved text
/// changes — the reader's page is drawn again for every change in the library, and splitting a
/// long article each time would be wasted work.
@MainActor
final class ArticleTextMemo {
    private var body: String? = nil
    private var text = ArticleText.empty

    /// The shown text for the saved text `body`.
    func text(for body: String) -> ArticleText {
        if let known = self.body, known == body { return text }
        let made = ArticleText.display(from: body)
        self.body = body
        text = made
        return made
    }
}

// MARK: - What a quote can do

/// What the highlight rows and the selection menu do with a quote.
@MainActor
enum ArticleQuoteActions {
    /// "Save as pin": a text pin with the quote, next to the article (see
    /// `LibraryStore.addQuotePin`), and a short confirmation. A hidden article's quote is hidden
    /// as well, and the confirmation names no board.
    static func saveAsPin(_ quote: String, from article: UUID, store: LibraryStore, importFlow: ImportFlow) {
        guard store.addQuotePin(from: article, quote: quote) != nil else { return }
        importFlow.flash("Saved as a pin", symbol: "quote.opening")
    }

    /// "Copy": the quote goes on the clipboard.
    static func copy(_ quote: String, importFlow: ImportFlow) {
        UIPasteboard.general.string = quote
        importFlow.flash("Copied", symbol: "doc.on.doc")
    }

    /// The three things a highlight's row can do, for the article `article`.
    static func rowActions(for article: UUID, store: LibraryStore, importFlow: ImportFlow) -> ArticleHighlightRowActions {
        ArticleHighlightRowActions(
            saveAsPin: { (mark: TextHighlight) -> Void in
                saveAsPin(mark.text, from: article, store: store, importFlow: importFlow)
            },
            copy: { (mark: TextHighlight) -> Void in
                copy(mark.text, importFlow: importFlow)
            },
            remove: { (mark: TextHighlight) -> Void in
                store.removeHighlight(mark.id, from: article)
            })
    }
}

/// What a highlight's row does: save its quote as a pin, copy it, take the highlight off.
struct ArticleHighlightRowActions {
    var saveAsPin: (TextHighlight) -> Void
    var copy: (TextHighlight) -> Void
    var remove: (TextHighlight) -> Void
}

// MARK: - The list of highlights

/// "Highlights (3)": each highlighted passage as a quote, with ⋯ (and a long press) for "Save as
/// pin", "Copy" and "Remove highlight". A passage that can't be found in the article any more
/// (it was read again and the words changed) is listed with "Text changed", not drawn in the text.
/// `limit`: how many rows show before "Show all 7" (the pin page uses 5; the reader shows all).
struct ArticleHighlightsList: View {
    /// How many highlights the article has.
    let total: Int
    /// The ones to list, in the order of the article.
    let items: [ResolvedHighlight]
    var limit: Int? = nil
    let actions: ArticleHighlightRowActions
    @State private var showsAll = false

    /// The rows to show now.
    private var visible: [ResolvedHighlight] {
        guard let limit, !showsAll, items.count > limit else { return items }
        return Array(items.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Highlights (\(total))", systemImage: "highlighter")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)   // VoiceOver's rotor can jump to it
            ForEach(visible) { (item: ResolvedHighlight) in
                ArticleHighlightRow(item: item, actions: actions)
            }
            if let limit, items.count > limit {
                showAllButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showAllButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showsAll.toggle() }
        } label: {
            Text(showsAll ? "Show fewer" : "Show all \(items.count)")
                .font(.subheadline)
                .frame(minHeight: 44, alignment: .leading)   // a comfortable target
                .contentShape(Rectangle())
        }
    }
}

/// One highlight in the list: the quote, set in like a quote in the article, with ⋯.
struct ArticleHighlightRow: View {
    let item: ResolvedHighlight
    let actions: ArticleHighlightRowActions
    @Environment(\.pinAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(accent.opacity(0.7))
                .frame(width: 3)
            quote
            Menu {
                rowMenu
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)   // a comfortable target
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Highlight options")
        }
        .contextMenu { rowMenu }
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.mark.text)
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.displayRange == nil {
                Text("Text changed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    /// "Save as pin", "Copy", "Remove highlight" (the ⋯ menu and the long press show the same).
    @ViewBuilder
    private var rowMenu: some View {
        Button {
            actions.saveAsPin(item.mark)
        } label: {
            Label("Save as pin", systemImage: "quote.opening")
        }
        Button {
            actions.copy(item.mark)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            actions.remove(item.mark)
        } label: {
            Label("Remove highlight", systemImage: "highlighter")
        }
    }
}

/// The highlights on the pin page, under "Read article": the same rows, at most `limit` and then
/// "Show all N". The article's text is only worked out when there are highlights to place.
struct ArticleHighlightsSection: View {
    let pin: Pin
    var limit: Int? = 5
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @State private var memo = ArticleTextMemo()

    var body: some View {
        if !pin.highlights.isEmpty {
            let text = memo.text(for: pin.textBody)
            ArticleHighlightsList(total: pin.highlights.count,
                                  items: ArticleHighlights.inReadingOrder(ArticleHighlights.resolve(pin.highlights, in: text)),
                                  limit: limit,
                                  actions: ArticleQuoteActions.rowActions(for: pin.id, store: store, importFlow: importFlow))
        }
    }
}

// MARK: - The article's text, as one selectable piece

/// The article's words as one piece of text (a read-only `UITextView`, not scrolling by itself:
/// the reader's page scrolls). It is one view so a selection can run across paragraphs and the
/// selection menu can carry PinBoard's own items — "Highlight" (or "Remove highlight") and
/// "Save as pin" — before the system's (Copy, Look Up, Share…). Highlights are drawn as a
/// background colour on the words; tapping one selects it, so the menu is one tap away.
struct ArticleBodyView: UIViewRepresentable {
    let text: ArticleText
    let highlights: [ResolvedHighlight]
    /// "Highlight" was chosen for this selection (places in `text.string`).
    var onHighlight: (NSRange) -> Void
    /// "Remove highlight" was chosen: this highlight goes.
    var onRemove: (TextHighlight) -> Void
    /// "Save as pin" was chosen: this quote becomes a pin.
    var onSaveQuote: (String) -> Void

    /// What the text view was last given. When none of it changed an update leaves the view
    /// alone, so a selection (and the menu on it) is not thrown away for nothing.
    struct Look: Equatable {
        var text: ArticleText
        var places: [NSRange]
        var accent: Color
        var typeSize: DynamicTypeSize
    }

    /// The object that answers the text view (its menu and its taps).
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// The text view: read-only, selectable, as tall as its text, with no background of its own.
    func makeUIView(context: Context) -> UITextView {
        // TextKit 1 on purpose: finding the letter under a tap needs its layout manager.
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false   // the reader's page scrolls; this view is as tall as its text
        view.contentInsetAdjustmentBehavior = .never   // no extra room for the bars: the page already keeps clear of them
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tappedText(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.textView = view
        return view
    }

    /// Gives the text view the article's words and highlights — only when something changed.
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let style = NativeTextField.interfaceStyle(for: context.environment.colorScheme)
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        let places: [NSRange] = highlights.compactMap { (item: ResolvedHighlight) -> NSRange? in item.displayRange }
        let look = Look(text: text, places: places, accent: context.environment.pinAccent, typeSize: context.environment.dynamicTypeSize)
        guard coordinator.look != look else { return }
        coordinator.look = look
        let selection = view.selectedRange
        let tint = UIColor(look.accent).withAlphaComponent(0.28)
        view.attributedText = text.attributed(highlights: highlights, tint: tint, traits: view.traitCollection)
        if selection.location + selection.length <= text.length { view.selectedRange = selection }
    }

    /// How tall the text is at the width the page gives it.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var width = proposal.width ?? 320
        if !width.isFinite || width <= 0 { width = 320 }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    /// Answers the text view: the menu on a selection, and a tap on a highlight.
    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ArticleBodyView
        var look: Look? = nil
        weak var textView: UITextView? = nil

        /// `parent` is replaced at every update, so the actions below always see the latest highlights.
        init(_ parent: ArticleBodyView) {
            self.parent = parent
        }

        // MARK: The selection menu

        /// PinBoard's items first, then the system's (Copy, Look Up, Share…).
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let ours = pinBoardActions(for: range)
            guard !ours.isEmpty else { return nil }
            return UIMenu(children: ours + suggestedActions)
        }

        /// "Highlight" unless the selection is all in one highlight already; "Remove highlight"
        /// when it touches one; "Save as pin" for any passage.
        private func pinBoardActions(for range: NSRange) -> [UIMenuElement] {
            var actions: [UIMenuElement] = []
            if ArticleHighlights.adding(selection: range, to: parent.highlights, in: parent.text) != nil {
                actions.append(UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] (action: UIAction) in
                    self?.highlight(range)
                })
            }
            if !ArticleHighlights.touching(range, resolved: parent.highlights).isEmpty {
                actions.append(UIAction(title: "Remove highlight", image: UIImage(systemName: "highlighter"), attributes: .destructive) { [weak self] (action: UIAction) in
                    self?.removeHighlights(touching: range)
                })
            }
            if ArticleHighlights.quote(for: range, in: parent.text) != nil {
                actions.append(UIAction(title: "Save as pin", image: UIImage(systemName: "quote.opening")) { [weak self] (action: UIAction) in
                    self?.saveQuote(of: range)
                })
            }
            return actions
        }

        /// "Highlight": the selection becomes a highlight.
        private func highlight(_ range: NSRange) {
            parent.onHighlight(range)
            collapseSelection(after: range)
        }

        /// "Remove highlight": every highlight the selection touches goes.
        private func removeHighlights(touching range: NSRange) {
            for item in ArticleHighlights.touching(range, resolved: parent.highlights) { parent.onRemove(item.mark) }
            collapseSelection(after: range)
        }

        /// "Save as pin": the selected words become a pin of their own.
        private func saveQuote(of range: NSRange) {
            guard let quote = ArticleHighlights.quote(for: range, in: parent.text) else { return }
            parent.onSaveQuote(quote)
            collapseSelection(after: range)
        }

        /// The selection is done with: the cursor goes to its end (nothing is selected any more).
        private func collapseSelection(after range: NSRange) {
            textView?.selectedRange = NSRange(location: range.location + range.length, length: 0)
        }

        // MARK: Tapping a highlight

        /// A tap on a highlighted passage selects all of it (the system's own menu is then one tap
        /// on the selection away). Best effort: the list under the text always has the same actions.
        @objc func tappedText(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? UITextView,
                  let item = highlight(under: gesture.location(in: view), in: view),
                  let range = item.displayRange else { return }
            view.becomeFirstResponder()
            view.selectedRange = range
        }

        /// Only a tap on a highlight starts this gesture; any other tap is the text view's own.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view as? UITextView else { return false }
            return highlight(under: gestureRecognizer.location(in: view), in: view) != nil
        }

        /// Both this tap and the text view's own may happen (the text view's own does nothing to a selectable text).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        /// The highlight at `point` of the text view, if one is drawn there.
        private func highlight(under point: CGPoint, in view: UITextView) -> ResolvedHighlight? {
            guard let index = letterIndex(at: point, in: view) else { return nil }
            return ArticleHighlights.highlight(atDisplayIndex: index, in: parent.highlights)
        }

        /// The letter under `point` — nil when the point is in the empty part of a line, or below the text.
        private func letterIndex(at point: CGPoint, in view: UITextView) -> Int? {
            let inset = view.textContainerInset
            let place = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
            let index = view.layoutManager.characterIndex(for: place, in: view.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard index >= 0, index < parent.text.length else { return nil }
            let glyphs = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let box = view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
            return box.insetBy(dx: -2, dy: -2).contains(place) ? index : nil
        }
    }
}

// MARK: - How the text looks

extension ArticleText {
    /// The text as the text view shows it: body text in the reader's size, headings bigger and
    /// bold, list items hung from their bullet, quotes set in, italic and grey; a gap of a few
    /// points between paragraphs; and every highlight as a coloured background (`tint`: the
    /// accent, faint, so the words read the same in light and dark). Fonts are the system's
    /// preferred ones, so Dynamic Type sizes them (`traits`: the text view's, so the size it has
    /// is the one used).
    func attributed(highlights: [ResolvedHighlight], tint: UIColor, traits: UITraitCollection?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: string)
        let everything = NSRange(location: 0, length: length)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        let plain: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: ArticleText.paragraphStyle(.plain, font: bodyFont, traits: traits)
        ]
        result.addAttributes(plain, range: everything)
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            ArticleText.style(part, isLast: isLast, in: result, bodyFont: bodyFont, traits: traits)
        }
        for item in highlights {
            guard let range = item.displayRange, range.length > 0, range.location + range.length <= length else { continue }
            result.addAttribute(.backgroundColor, value: tint, range: range)
        }
        return result
    }

    /// Gives one paragraph its look. The paragraph's style also covers the first of the two line
    /// breaks after it; the second one is a line of its own, made almost flat so the gap between
    /// paragraphs is the style's `paragraphSpacing`, not a whole blank line.
    private static func style(_ part: Part, isLast: Bool, in result: NSMutableAttributedString, bodyFont: UIFont, traits: UITraitCollection?) {
        let words = part.displayRange
        let paragraph = NSRange(location: words.location, length: words.length + (isLast ? 0 : 1))
        let font = fontFor(part.kind, bodyFont: bodyFont, traits: traits)
        result.addAttribute(.paragraphStyle, value: paragraphStyle(part.kind, font: font, traits: traits), range: paragraph)
        result.addAttribute(.font, value: font, range: words)
        if part.kind == .quote {
            result.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: words)
        }
        if !isLast {
            let flat: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 1), .paragraphStyle: NSParagraphStyle.default]
            result.addAttributes(flat, range: NSRange(location: words.location + words.length + 1, length: 1))
        }
    }

    /// Headings are the title-3 size in bold, quotes italic, everything else the body font.
    private static func fontFor(_ kind: ArticleParagraph.Kind, bodyFont: UIFont, traits: UITraitCollection?) -> UIFont {
        switch kind {
        case .heading:
            return withTrait(.traitBold, of: UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traits))
        case .quote:
            return withTrait(.traitItalic, of: bodyFont)
        case .plain, .bullet:
            return bodyFont
        }
    }

    /// The same font with one more trait (bold or italic); the font itself when that can't be done.
    private static func withTrait(_ trait: UIFontDescriptor.SymbolicTraits, of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(trait.union(font.fontDescriptor.symbolicTraits)) else { return font }
        return UIFont(descriptor: descriptor, size: 0)   // (size 0: the descriptor's own)
    }

    /// Spacing and indents for a paragraph of this kind, scaled with the text size.
    private static func paragraphStyle(_ kind: ArticleParagraph.Kind, font: UIFont, traits: UITraitCollection?) -> NSParagraphStyle {
        let metrics = UIFontMetrics(forTextStyle: .body)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = metrics.scaledValue(for: 12, compatibleWith: traits)
        switch kind {
        case .heading:
            style.paragraphSpacingBefore = metrics.scaledValue(for: 6, compatibleWith: traits)
        case .bullet:
            // The bullet hangs: wrapped lines line up with the words, not under the bullet.
            let indent = metrics.scaledValue(for: 12, compatibleWith: traits)
            let bullet = NSString(string: "• ").size(withAttributes: [.font: font]).width
            style.firstLineHeadIndent = indent
            style.headIndent = indent + ceil(bullet)
        case .quote:
            let indent = metrics.scaledValue(for: 14, compatibleWith: traits)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        case .plain:
            break
        }
        return style
    }
}

// MARK: - YouTube's player

/// "Play": the video in YouTube's own embedded player (nothing is downloaded), with Done. Always
/// dark, like Quick Look: the black around the video runs up under the bar, where a light
/// title would otherwise be black on black.
struct YouTubePlayerSheet: View {
    let videoID: String
    /// Off for a hidden pin (see YouTubeDetailsView).
    var allowsFullScreen: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubePlayerView(videoID: videoID, allowsFullScreen: allowsFullScreen)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .navigationTitle("YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .largeSheetSizing()   // on iPad: room for a bigger picture than the small form sheet
    }
}

/// YouTube's embedded player in a web view. It plays in place (not full screen by itself); a
/// link tapped inside it ("Watch on YouTube", the channel) opens in the YouTube app or the default browser.
/// Nothing the player stores is kept after the sheet closes.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    var allowsFullScreen: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = allowsFullScreen   // the player's own full-screen button works
        configuration.allowsPictureInPictureMediaPlayback = allowsFullScreen
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        context.coordinator.openURL = context.environment.openURL
        if let page = YouTubeReader.playerPage(videoID: videoID, allowsFullScreen: allowsFullScreen) {
            webView.loadHTMLString(page, baseURL: YouTubeReader.playerBaseURL(appID: Bundle.main.bundleIdentifier))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = context.environment.openURL
    }

    /// The sheet closed: the page goes, so its sound stops at once.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    /// Sends links tapped in the player out of the app (the player itself stays).
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var openURL: OpenURLAction? = nil

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return .allow }
            open(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { open(url) }
            return nil   // never a second web view: the link opens outside the app
        }

        private func open(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
            if let openURL { openURL(url) }
        }
    }
}
