//
//  PinBoardWidgets.swift  —  PinBoard's widgets
//
//  Three widgets, each in several sizes, each set to one board or to all of them (touch and hold
//  the widget › Edit Widget):
//    • Photo — one photo, filling the widget.
//    • Photo Grid — a small grid of photos.
//    • Quote — one of your text pins, set like a quote.
//  They change every hour. Each widget also has a "Pick" (1st, 2nd, 3rd…): widgets on the same board
//  with different picks never show the same photo (or quote) at the same time — each takes its own
//  share of that board's order for the hour (`Rotation`). iOS gives a widget no identity of its
//  own and draws widgets with exactly the same settings from one timeline, so the pick (set by the
//  person, 1st unless changed) is the only way to tell two widgets on one board apart.
//  Everything comes from the snapshot the app writes (WidgetShared.swift): never the Hidden section.
//  Tapping opens the pin in PinBoard.
//
//  On a Mac: use the Mac's own PinBoard widgets (the PinBoard app installed on the Mac). The iPhone's
//  copies that macOS can borrow ("Use iPhone widgets") are marked `disfavoredLocations
//  (.iPhoneWidgetsOnMac)`: the Mac can't run them, only show pictures the iPhone sends now and then,
//  and in build 18 they sat as grey placeholders on the owner's desktop.
//

import WidgetKit
import SwiftUI
import AppIntents
import ImageIO

@main
struct PinBoardWidgets: WidgetBundle {
    var body: some Widget {
        PhotoWidget()
        PhotoGridWidget()
        QuoteWidget()
    }
}

// MARK: - Choosing a board

struct BoardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Board"
    static let defaultQuery = BoardQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BoardQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BoardEntity] {
        allBoards().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BoardEntity] {
        allBoards()
    }

    private func allBoards() -> [BoardEntity] {
        (WidgetShared.readSnapshot()?.boards ?? []).map { BoardEntity(id: $0.id, name: $0.name) }
    }
}

/// Which share of a board's photos a widget takes (see the top of this file).
struct PickEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pick"
    static let defaultQuery = PickQuery()
    static let count = 12

    var id: Int

    var displayRepresentation: DisplayRepresentation {
        let ordinal = NumberFormatter.localizedString(from: NSNumber(value: id), number: .ordinal)
        return DisplayRepresentation(title: "\(ordinal)")
    }
}

struct PickQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [PickEntity] {
        identifiers.filter { (1...PickEntity.count).contains($0) }.map { PickEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [PickEntity] {
        (1...PickEntity.count).map { PickEntity(id: $0) }
    }

    func defaultResult() async -> PickEntity? {
        PickEntity(id: 1)
    }
}

struct ChooseBoardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a board"
    static let description = IntentDescription("Show pins from one board, or from all your boards.")

    @Parameter(title: "Board", description: "Leave empty for all boards.")
    var board: BoardEntity?

    @Parameter(title: "Pick", description: "Two widgets on the same board? Give each a different pick and they never show the same photo.")
    var pick: PickEntity?

    init() {}
}

// MARK: - Taking turns

/// Each hour has its own order of a board's items, the same for every widget; a widget with pick
/// n takes the n-th share of it (`take` items from position (n − 1) × take). So widgets with
/// different picks differ until the board runs out of items.
enum Rotation {
    /// The hour `date` falls in, counted from 1970.
    static func slot(of date: Date) -> Int { Int(date.timeIntervalSince1970 / 3600) }

    static func positions(poolCount: Int, take: Int, key: String, slot: Int, pick: Int) -> [Int] {
        guard poolCount > 0, take > 0 else { return [] }
        let order = shuffledOrder(count: poolCount, seed: stableHash(key) &+ UInt64(slot))
        let start = max(pick - 1, 0) * take
        return (0..<min(take, poolCount)).map { order[(start + $0) % poolCount] }
    }

    /// 0..<count in an order that depends only on `seed` (the same in every widget).
    private static func shuffledOrder(count: Int, seed: UInt64) -> [Int] {
        var generator = SeededGenerator(state: seed)
        return Array(0..<count).shuffled(using: &generator)
    }

    /// A hash that is the same in every run (Swift's own `hashValue` changes from run to run).
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// SplitMix64: small and good enough for shuffling pictures.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Timelines

struct PinEntry: TimelineEntry {
    enum Problem { case noSnapshot, nothingHere }

    var date: Date
    var photos: [WidgetSnapshot.Photo] = []
    var quote: WidgetSnapshot.Quote? = nil
    var boardName: String? = nil   // nil: all boards
    var problem: Problem? = nil
    var isPlaceholder = false
}

/// The hours a timeline covers: now, then the start of each of the next five hours.
private func timelineDates() -> [Date] {
    let now = Date()
    let hourStart = Date(timeIntervalSince1970: Double(Rotation.slot(of: now)) * 3600)
    return [now] + (1...5).map { hourStart.addingTimeInterval(Double($0) * 3600) }
}

private func boardKey(_ board: BoardEntity?) -> String { board?.id.uuidString ?? "all" }

/// How many photos the grid shows in each size.
private func gridCount(_ family: WidgetFamily) -> Int {
    switch family {
    case .systemSmall: return 4
    case .systemMedium: return 8
    case .systemLarge: return 9
    case .systemExtraLarge: return 18
    default: return 4
    }
}

/// Photo and Photo Grid: `count(family)` photos per hour from the chosen board.
struct PhotoProvider: AppIntentTimelineProvider {
    var count: @Sendable (WidgetFamily) -> Int

    func placeholder(in context: Context) -> PinEntry {
        PinEntry(date: Date(), isPlaceholder: true)
    }

    func snapshot(for configuration: ChooseBoardIntent, in context: Context) async -> PinEntry {
        entries(for: configuration, family: context.family, dates: [Date()]).first ?? placeholder(in: context)
    }

    func timeline(for configuration: ChooseBoardIntent, in context: Context) async -> Timeline<PinEntry> {
        Timeline(entries: entries(for: configuration, family: context.family, dates: timelineDates()), policy: .atEnd)
    }

    private func entries(for configuration: ChooseBoardIntent, family: WidgetFamily, dates: [Date]) -> [PinEntry] {
        guard let snapshot = WidgetShared.readSnapshot() else { return dates.map { PinEntry(date: $0, problem: .noSnapshot) } }
        let pool = snapshot.photos(in: configuration.board?.id)
        let name = configuration.board?.name
        guard !pool.isEmpty else { return dates.map { PinEntry(date: $0, boardName: name, problem: .nothingHere) } }
        let take = count(family)
        return dates.map { (date: Date) -> PinEntry in
            let positions = Rotation.positions(poolCount: pool.count, take: take, key: "photo|" + boardKey(configuration.board),
                                               slot: Rotation.slot(of: date), pick: configuration.pick?.id ?? 1)
            return PinEntry(date: date, photos: positions.map { pool[$0] }, boardName: name)
        }
    }
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PinEntry {
        PinEntry(date: Date(), quote: WidgetSnapshot.Quote(id: UUID(), text: "The best ideas start as a pin.", title: "", boardIDs: []),
                 isPlaceholder: true)
    }

    func snapshot(for configuration: ChooseBoardIntent, in context: Context) async -> PinEntry {
        entries(for: configuration, dates: [Date()]).first ?? placeholder(in: context)
    }

    func timeline(for configuration: ChooseBoardIntent, in context: Context) async -> Timeline<PinEntry> {
        Timeline(entries: entries(for: configuration, dates: timelineDates()), policy: .atEnd)
    }

    private func entries(for configuration: ChooseBoardIntent, dates: [Date]) -> [PinEntry] {
        guard let snapshot = WidgetShared.readSnapshot() else { return dates.map { PinEntry(date: $0, problem: .noSnapshot) } }
        let pool = snapshot.quotes(in: configuration.board?.id)
        let name = configuration.board?.name
        guard !pool.isEmpty else { return dates.map { PinEntry(date: $0, boardName: name, problem: .nothingHere) } }
        return dates.map { (date: Date) -> PinEntry in
            let position = Rotation.positions(poolCount: pool.count, take: 1, key: "quote|" + boardKey(configuration.board),
                                              slot: Rotation.slot(of: date), pick: configuration.pick?.id ?? 1).first ?? 0
            return PinEntry(date: date, quote: pool[position], boardName: name)
        }
    }
}

// MARK: - Widgets

struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.photoKind, intent: ChooseBoardIntent.self,
                               provider: PhotoProvider(count: { _ in 1 })) { (entry: PinEntry) in
            PhotoView(entry: entry)
        }
        .configurationDisplayName("Photo")
        .description("A photo from one board, or from all of them. For two on the same board, give each its own Pick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct PhotoGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.gridKind, intent: ChooseBoardIntent.self,
                               provider: PhotoProvider(count: { gridCount($0) })) { (entry: PinEntry) in
            PhotoGridView(entry: entry)
        }
        .configurationDisplayName("Photo Grid")
        .description("A small grid of photos from one board, or from all of them. For two on the same board, give each its own Pick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct QuoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.quoteKind, intent: ChooseBoardIntent.self,
                               provider: QuoteProvider()) { (entry: PinEntry) in
            QuoteView(entry: entry)
        }
        .configurationDisplayName("Quote")
        .description("One of your text pins, from one board or from all of them. For two on the same board, give each its own Pick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

/// PinBoard's red (the app's default accent).
private let pinRed = Color(red: 0.86, green: 0.16, blue: 0.22)

/// A snapshot picture, decoded at about the size it is shown (widgets have little memory).
private func picture(_ photo: WidgetSnapshot.Photo, maxPixels: Int) -> UIImage? {
    guard let url = WidgetShared.picturesFolder?.appendingPathComponent(photo.file),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

/// What a photo widget shows while its photos are on the way (WidgetKit's "placeholder"): the
/// pin mark, so a widget that is still waiting looks like PinBoard and not like a broken grey box.
private struct PlaceholderView: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.title)
            .foregroundStyle(pinRed.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What a widget says when it has nothing to show.
private struct ProblemView: View {
    let entry: PinEntry
    var what = "photos"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.title2)
                .foregroundStyle(pinRed)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var message: String {
        if entry.problem == .noSnapshot { return "Open PinBoard to fill this widget." }
        if let board = entry.boardName { return "No \(what) on “\(board)” yet." }
        return "No \(what) yet."
    }
}

struct PhotoView: View {
    let entry: PinEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let photo = entry.photos.first, let image = picture(photo, maxPixels: family == .systemSmall ? 400 : 800) {
                GeometryReader { (geometry: GeometryProxy) in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay(alignment: .bottomLeading) { caption(photo) }
                }
                .widgetURL(WidgetShared.link(toPin: photo.id))
            } else if entry.isPlaceholder {
                PlaceholderView()
            } else {
                ProblemView(entry: entry)
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
    }

    /// The pin's title, on the larger sizes only.
    @ViewBuilder
    private func caption(_ photo: WidgetSnapshot.Photo) -> some View {
        if family != .systemSmall, !photo.title.isEmpty {
            Text(photo.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct PhotoGridView: View {
    let entry: PinEntry
    @Environment(\.widgetFamily) private var family

    private var columns: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        case .systemLarge: return 3
        case .systemExtraLarge: return 6
        default: return 2
        }
    }

    var body: some View {
        Group {
            if !entry.photos.isEmpty {
                GeometryReader { (geometry: GeometryProxy) in
                    let spacing: CGFloat = 3
                    let rows = Int((Double(entry.photos.count) / Double(columns)).rounded(.up))
                    let width = (geometry.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
                    let height = (geometry.size.height - spacing * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))
                    VStack(spacing: spacing) {
                        ForEach(0..<rows, id: \.self) { (row: Int) in
                            HStack(spacing: spacing) {
                                ForEach(0..<columns, id: \.self) { (column: Int) in
                                    cell(at: row * columns + column, width: width, height: height)
                                }
                            }
                        }
                    }
                }
                .widgetURL(entry.photos.first.map { WidgetShared.link(toPin: $0.id) })
            } else if entry.isPlaceholder {
                PlaceholderView()
            } else {
                ProblemView(entry: entry)
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }
    }

    /// One photo of the grid (a tap opens that pin; a small widget opens the first one).
    @ViewBuilder
    private func cell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < entry.photos.count {
            let photo = entry.photos[index]
            let image = picture(photo, maxPixels: Int(max(width, height) * 3))
            Link(destination: WidgetShared.link(toPin: photo.id)) {
                ZStack {
                    Color.gray.opacity(0.2)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: width, height: height)
                .clipped()
            }
        } else {
            Color.gray.opacity(0.12).frame(width: width, height: height)
        }
    }
}

struct QuoteView: View {
    let entry: PinEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let quote = entry.quote {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
                    Image(systemName: "quote.opening")
                        .font(family == .systemSmall ? .body : .title2)
                        .foregroundStyle(pinRed)
                    Text(quote.text)
                        .font(.system(size: textSize, weight: .medium, design: .serif))
                        .minimumScaleFactor(0.5)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if let attribution = attribution(quote) {
                        Text("— " + attribution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .redacted(reason: entry.isPlaceholder ? .placeholder : [])
                .widgetURL(entry.isPlaceholder ? nil : WidgetShared.link(toPin: quote.id))
            } else {
                ProblemView(entry: entry, what: "text pins")
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var textSize: CGFloat {
        switch family {
        case .systemSmall: return 15
        case .systemMedium: return 18
        default: return 24
        }
    }

    /// The pin's title, else the board's name (nothing on a small widget, to give the words room).
    private func attribution(_ quote: WidgetSnapshot.Quote) -> String? {
        guard family != .systemSmall else { return nil }
        if !quote.title.isEmpty { return quote.title }
        return entry.boardName
    }
}
