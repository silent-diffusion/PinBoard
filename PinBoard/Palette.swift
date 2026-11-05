//
//  Palette.swift  —  PinBoard
//
//  "Generate colors": eight colors picked from the pictures of a board or of a
//  selection of pins (the palette engine, the sheet that shows them, and the
//  pictures made from them), plus the board page's little surprise — tap the
//  board's title and its name turns into big block letters that show the
//  board's colors sliding by behind them.
//
//  New in round 8. Paste this file into the app next to the others.
//

import SwiftUI
#if canImport(Accessibility)
import Accessibility
#endif
import UIKit
import Foundation

// MARK: - The palette engine (pure maths, runs off the main thread)

/// Finds the colors that best describe a set of pictures.
///
/// How it works, in short: every picture is shrunk to 48 pixels and its pixels
/// are turned into CIELAB (a color space where distances match how different two
/// colors look). Each picture counts the same, however many pixels it has. The
/// pixels are grouped into 16 clusters (k-means), clusters that look alike are
/// merged, and up to 8 clearly different clusters are kept — big ones first, with
/// a bonus for strong colors so a bright accent is not lost among greys.
/// Everything here is deterministic: the same pictures always give the same colors.
enum PaletteEngine {
    /// Where one picture's pixels are read from: its thumbnail, or the full picture
    /// when the thumbnail file is missing. Only file addresses, so it can cross threads.
    struct Source: Sendable, Hashable {
        var thumbnail: URL
        var fullImage: URL
    }

    /// A color in CIELAB: lightness 0…100, a (green…red), b (blue…yellow).
    struct Lab: Sendable, Equatable {
        var l: Double
        var a: Double
        var b: Double
    }

    /// One pixel taken into account, and how much it counts.
    struct Sample: Sendable {
        var lab: Lab
        var weight: Double
    }

    /// A group of similar pixels: their average color and their total weight.
    struct Cluster: Sendable {
        var center: Lab
        var weight: Double
    }

    nonisolated static let colorCount = 8           // colors in a palette (at most)
    nonisolated static let clusterCount = 16        // groups made before choosing
    nonisolated static let maxSamples = 60_000      // pixels looked at, in total
    nonisolated static let maxPictures = 120        // pictures looked at
    nonisolated static let pictureSize = 48         // pixels on the long side
    nonisolated static let mergeDistance = 12.0     // clusters closer than this become one
    nonisolated static let pickDistance = 15.0      // chosen colors are at least this far apart

    /// The palette of these pictures: up to 8 colors as "#RRGGBB", the most
    /// prominent first. Fewer when the pictures have fewer distinct colors; empty
    /// when none of them could be read. Call it off the main thread.
    nonisolated static func makePalette(from sources: [Source]) -> [String] {
        let samples = readSamples(from: sources)
        guard !samples.isEmpty else { return [] }
        let clusters = kMeans(samples, clusters: clusterCount, iterations: 12)
        let merged = merge(clusters, closerThan: mergeDistance)
        let picked = pick(merged, count: colorCount, apart: pickDistance)
        let ordered = picked.sorted { first, second in
            first.weight != second.weight ? first.weight > second.weight : first.center.l > second.center.l
        }
        return ordered.map { hex(of: $0.center) }
    }

    // MARK: Reading the pictures

    /// The pixels of every readable picture, each picture weighing the same in total.
    nonisolated static func readSamples(from sources: [Source]) -> [Sample] {
        var pictures: [[Lab]] = []
        for source in sources.prefix(maxPictures) {
            let data = (try? Data(contentsOf: source.thumbnail)) ?? (try? Data(contentsOf: source.fullImage))
            // Decoded here, on this thread (a CGImage must never cross threads).
            guard let data, let image = ImageProcessor.downsample(data, maxPixelSize: pictureSize) else { continue }
            let pixels = labPixels(of: image)
            if !pixels.isEmpty { pictures.append(pixels) }
        }
        guard !pictures.isEmpty else { return [] }
        let perPicture = max(1, maxSamples / pictures.count)
        var samples: [Sample] = []
        samples.reserveCapacity(min(maxSamples + pictures.count, pictures.count * perPicture))
        for pixels in pictures {
            // Every n-th pixel, so no picture adds more than its share.
            let step = max(1, Int((Double(pixels.count) / Double(perPicture)).rounded(.up)))
            var taken: [Lab] = []
            var index = 0
            while index < pixels.count {
                taken.append(pixels[index])
                index += step
            }
            let weight = 1.0 / Double(taken.count)
            for lab in taken { samples.append(Sample(lab: lab, weight: weight)) }
        }
        return samples
    }

    /// Every (mostly opaque) pixel of a small picture, as CIELAB.
    nonisolated static func labPixels(of image: CGImage) -> [Lab] {
        let width = min(max(1, image.width), 256)
        let height = min(max(1, image.height), 256)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { return [] }
        var result: [Lab] = []
        result.reserveCapacity(width * height)
        for start in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[start + 3])
            guard alpha >= 128 else { continue }             // see-through pixels have no real color
            // The bitmap stores colors multiplied by alpha: undo that.
            let red = min(1, Double(bytes[start]) / alpha)
            let green = min(1, Double(bytes[start + 1]) / alpha)
            let blue = min(1, Double(bytes[start + 2]) / alpha)
            result.append(lab(red: red, green: green, blue: blue))
        }
        return result
    }

    // MARK: Grouping (k-means)

    /// Groups the samples into (at most) `wanted` clusters. Starting points are chosen
    /// with "k-means++" (far-apart samples are more likely), using a fixed seed.
    nonisolated static func kMeans(_ samples: [Sample], clusters wanted: Int, iterations: Int) -> [Cluster] {
        guard !samples.isEmpty else { return [] }
        var generator = SeededGenerator(seed: 8)
        let k = max(1, min(wanted, samples.count))

        // Starting points.
        var centers: [Lab] = []
        let weights = samples.map { $0.weight }
        centers.append(samples[weightedIndex(weights, total: weights.reduce(0, +), using: &generator)].lab)
        var nearest = samples.map { distanceSquared($0.lab, centers[0]) }
        while centers.count < k {
            var chances = [Double](repeating: 0, count: samples.count)
            var total = 0.0
            for index in samples.indices {
                chances[index] = samples[index].weight * nearest[index]
                total += chances[index]
            }
            guard total > 0 else { break }   // every sample already sits on a starting point
            let chosen = samples[weightedIndex(chances, total: total, using: &generator)].lab
            centers.append(chosen)
            for index in samples.indices {
                nearest[index] = min(nearest[index], distanceSquared(samples[index].lab, chosen))
            }
        }

        // Refine: give each sample to its nearest center, move each center to the middle of its samples.
        var assignment = [Int](repeating: -1, count: samples.count)
        var totals = [Double](repeating: 0, count: centers.count)
        for _ in 0..<max(1, iterations) {
            var changed = false
            for index in samples.indices {
                let best = nearestCenter(to: samples[index].lab, among: centers)
                if assignment[index] != best {
                    assignment[index] = best
                    changed = true
                }
            }
            var sumL = [Double](repeating: 0, count: centers.count)
            var sumA = sumL
            var sumB = sumL
            totals = sumL
            for index in samples.indices {
                let cluster = assignment[index]
                let sample = samples[index]
                sumL[cluster] += sample.lab.l * sample.weight
                sumA[cluster] += sample.lab.a * sample.weight
                sumB[cluster] += sample.lab.b * sample.weight
                totals[cluster] += sample.weight
            }
            for cluster in centers.indices where totals[cluster] > 0 {
                centers[cluster] = Lab(l: sumL[cluster] / totals[cluster],
                                       a: sumA[cluster] / totals[cluster],
                                       b: sumB[cluster] / totals[cluster])
            }
            if !changed { break }
        }
        return centers.indices.compactMap { cluster in
            totals[cluster] > 0 ? Cluster(center: centers[cluster], weight: totals[cluster]) : nil
        }
    }

    /// Joins clusters that look almost the same (biggest first).
    nonisolated static func merge(_ clusters: [Cluster], closerThan limit: Double) -> [Cluster] {
        var merged: [Cluster] = []
        for cluster in clusters.sorted(by: { $0.weight > $1.weight }) {
            if let index = merged.firstIndex(where: { distance($0.center, cluster.center) < limit }) {
                let kept = merged[index]
                let weight = kept.weight + cluster.weight
                merged[index] = Cluster(center: Lab(l: (kept.center.l * kept.weight + cluster.center.l * cluster.weight) / weight,
                                                    a: (kept.center.a * kept.weight + cluster.center.a * cluster.weight) / weight,
                                                    b: (kept.center.b * kept.weight + cluster.center.b * cluster.weight) / weight),
                                        weight: weight)
            } else {
                merged.append(cluster)
            }
        }
        return merged
    }

    /// Chooses up to `count` clusters that are clearly different from each other.
    /// Big clusters come first; strong (colorful) ones get a bonus of up to 40%.
    nonisolated static func pick(_ clusters: [Cluster], count: Int, apart: Double) -> [Cluster] {
        func score(_ cluster: Cluster) -> Double {
            let chroma = (cluster.center.a * cluster.center.a + cluster.center.b * cluster.center.b).squareRoot()
            return cluster.weight * (0.6 + 0.4 * min(1, chroma / 60))
        }
        var chosen: [Cluster] = []
        for cluster in clusters.sorted(by: { score($0) > score($1) }) {
            guard chosen.count < count else { break }
            if chosen.allSatisfy({ distance($0.center, cluster.center) >= apart }) {
                chosen.append(cluster)
            }
        }
        return chosen
    }

    // MARK: Small helpers

    nonisolated static func nearestCenter(to lab: Lab, among centers: [Lab]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in centers.indices {
            let d = distanceSquared(lab, centers[index])
            if d < bestDistance {
                bestDistance = d
                best = index
            }
        }
        return best
    }

    /// Picks an index with a chance proportional to its weight.
    nonisolated static func weightedIndex(_ weights: [Double], total: Double, using generator: inout SeededGenerator) -> Int {
        guard total > 0, !weights.isEmpty else { return 0 }
        let bits: UInt64 = generator.next() >> 11
        let scale: Double = 9_007_199_254_740_992   // 2^53: 53 random bits → a fraction below 1
        let fraction: Double = Double(bits) / scale
        var target = fraction * total
        for index in weights.indices {
            target -= weights[index]
            if target < 0 { return index }
        }
        return weights.count - 1
    }

    nonisolated static func distanceSquared(_ x: Lab, _ y: Lab) -> Double {
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return dl * dl + da * da + db * db
    }

    /// How different two colors look (CIE76 ΔE; about 2.3 is just noticeable).
    nonisolated static func distance(_ x: Lab, _ y: Lab) -> Double {
        distanceSquared(x, y).squareRoot()
    }

    // MARK: Color conversions (sRGB ⇄ CIELAB, D65 white)

    nonisolated static func lab(red: Double, green: Double, blue: Double) -> Lab {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.0
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? pow(t, 1.0 / 3.0) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Red, green and blue (0…1, clamped) for a CIELAB color.
    nonisolated static func rgb(of lab: Lab) -> (red: Double, green: Double, blue: Double) {
        let fy = (lab.l + 16) / 116
        let fx = fy + lab.a / 500
        let fz = fy - lab.b / 200
        func inverse(_ t: Double) -> Double {
            let cube = t * t * t
            return cube > 216.0 / 24389.0 ? cube : (116 * t - 16) / (24389.0 / 27.0)
        }
        let x = 0.95047 * inverse(fx), y = 1.0 * inverse(fy), z = 1.08883 * inverse(fz)
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        func gamma(_ c: Double) -> Double {
            let value = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
            return min(1, max(0, value))
        }
        return (gamma(r), gamma(g), gamma(b))
    }

    /// "#RRGGBB" (upper case) for a CIELAB color.
    nonisolated static func hex(of lab: Lab) -> String {
        let color = rgb(of: lab)
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
}

// MARK: - Choosing the pictures, caching the result

extension LibraryStore {
    /// The pictures a palette is made from: up to 120 of these pins that have a
    /// picture, spread evenly from newest to oldest, with `coverID` (a board's
    /// cover) first. Always the same pictures for the same pins, in any order.
    func paletteSources(for pinIDs: [UUID], coverID: UUID? = nil) -> [PaletteEngine.Source] {
        let wanted = Set(pinIDs)
        var withPictures = livePins.filter { wanted.contains($0.id) && $0.hasImageFile }
        withPictures.sort { first, second in
            first.createdAt != second.createdAt ? first.createdAt > second.createdAt : first.id.uuidString < second.id.uuidString
        }
        var chosen: [Pin] = []
        if let coverID, let cover = withPictures.first(where: { $0.id == coverID }) {
            chosen.append(cover)
            withPictures.removeAll { $0.id == coverID }
        }
        let room = PaletteEngine.maxPictures - chosen.count
        if room > 0 { chosen += LibraryStore.evenSample(withPictures, limit: room) }
        return chosen.map { pin in
            PaletteEngine.Source(thumbnail: thumbsURL.appendingPathComponent(pin.thumbFileName),
                                 fullImage: imageFileURL(for: pin))
        }
    }

    /// The board's saved colors, if they were made after its last change (nil otherwise).
    func freshPalette(for boardID: UUID) -> [String]? {
        guard let board = board(boardID), let hex = board.paletteHex, let made = board.paletteMadeAt,
              made >= lastEditedDate(for: boardID) else { return nil }
        return hex
    }
}

/// Makes a palette in the background and, when the pins are exactly a board's
/// whole content (its sub-boards included), keeps it on the board.
@MainActor
enum PaletteMaker {
    static func colors(for pinIDs: [UUID], boardID: UUID?, store: LibraryStore) async -> [String] {
        let cover = boardID.flatMap { store.board($0)?.coverPinID }
        let sources = store.paletteSources(for: pinIDs, coverID: cover)
        let hex: [String]
        if sources.isEmpty {
            hex = []
        } else {
            hex = await Task.detached(priority: .userInitiated) { () -> [String] in
                PaletteEngine.makePalette(from: sources)
            }.value
        }
        // Checked after the work: if the board changed meanwhile, the colors are not kept.
        if let boardID, store.board(boardID) != nil, Set(pinIDs) == store.pinIDs(in: boardID, includeNested: true) {
            store.setPalette(hex.isEmpty ? nil : hex, for: boardID)
        }
        return hex
    }
}

// MARK: - The "Generate colors" sheet

/// Shows the colors of exactly these pins as swatches with their hex codes.
/// Tap a swatch to copy its hex code; touch and hold it to copy, share or save it; the
/// ⋯ menu does the same for the whole palette. "Save as pin" puts a picture of the palette on
/// `boardID` (nil = Unsorted of `scope`; straight into Hidden for `.hidden`).
/// Results come as short confirmations: "Copied …" in the sheet's own little note, and saving
/// to Photos (or a failure) as the app's usual confirmation, which shows over this sheet while
/// it is up (it is an import-flow "cover", like Settings and Quick Look).
struct PaletteSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var importFlow: ImportFlow
    @Environment(\.dismiss) private var dismiss

    let title: String
    let pinIDs: [UUID]
    let boardID: UUID?
    let scope: PinScope

    @State private var colors: [String] = []
    @State private var working = true
    @State private var note: String? = nil
    /// Goes up with every note, so a note's timer only ever hides (and reads out) its own note.
    @State private var noteNumber = 0
    @State private var share: PaletteShareRequest? = nil
    /// "Save as pin": the palette picture, imported once this sheet has closed.
    @State private var pinPicture: UIImage? = nil

    /// The symbol of a confirmation that says something went wrong.
    private static let warning = "exclamationmark.triangle"

    init(title: String, pinIDs: [UUID], boardID: UUID? = nil, scope: PinScope = .visible) {
        self.title = title
        self.pinIDs = pinIDs
        self.boardID = boardID
        self.scope = scope
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
            }
            .overlay(alignment: .bottom) { copiedNote }
            .navigationTitle("Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    moreMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The app's confirmations (and any import question) show over this sheet while it is up.
        // Apply outside any NavigationStack: the cover counts the screens it is on as they appear
        // and disappear.
        .importFlowCover()
        .onDisappear { importPinPicture() }
        .presentationDetents([.medium, .large])
        .task { await load() }
        .sheet(item: $share) { request in
            ActivityShareSheet(items: request.items, isPresented: sharePresented)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if working {
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking at the pictures…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if colors.isEmpty {
            EmptyStateView(icon: "paintpalette", title: "No pictures to take colors from",
                           message: "Colors come from pictures, videos and link previews. Text pins have none.")
                .padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(colors.count) color\(colors.count == 1 ? "" : "s") from “\(title)”. Tap a color to copy its hex code; touch and hold it to share or save it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                swatchGrid
            }
            .padding(.bottom, 44)   // room for the "Copied" note, so it never covers the last swatch
        }
    }

    private var swatchGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 14) {
            ForEach(Array(colors.enumerated()), id: \.offset) { entry in
                // A tap copies the hex code; touch and hold still opens the full menu.
                Button {
                    copy(entry.element)
                } label: {
                    PaletteSwatch(hex: entry.element)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copies the hex code")
                .contextMenu { swatchMenu(entry.element) }
            }
        }
    }

    /// The short "Copied …" confirmation. It floats at the bottom of the sheet, so it is seen
    /// wherever the swatch was (under the swatches it could be out of sight).
    @ViewBuilder
    private var copiedNote: some View {
        if let note {
            Text(note)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func swatchMenu(_ hex: String) -> some View {
        Button { copy(hex) } label: { Label("Copy \(hex)", systemImage: "doc.on.doc") }
        Button { shareSwatch(hex) } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        Button { savePaletteToPhotos() } label: { Label("Save palette to Photos", systemImage: "photo.badge.arrow.down") }
        Button { saveAsPin() } label: { Label("Save palette as a pin", systemImage: "pin") }
    }

    private var moreMenu: some View {
        Menu {
            Button { copyAll() } label: { Label("Copy all hex codes", systemImage: "doc.on.doc") }
            Button { sharePalette() } label: { Label("Share palette…", systemImage: "square.and.arrow.up") }
            Button { savePaletteToPhotos() } label: { Label("Save palette image to Photos", systemImage: "photo.badge.arrow.down") }
            Button { saveAsPin() } label: { Label("Save as pin", systemImage: "pin") }
        } label: {
            MoreMenuLabel()
        }
        .disabled(colors.isEmpty)
        .accessibilityLabel("More")
    }

    private var sharePresented: Binding<Bool> {
        Binding(get: { share != nil }, set: { if !$0 { share = nil } })
    }

    // MARK: Actions

    private func load() async {
        // A board's saved colors are used when they are still up to date.
        if let boardID, Set(pinIDs) == store.pinIDs(in: boardID, includeNested: true),
           let fresh = store.freshPalette(for: boardID) {
            colors = fresh
            working = false
            return
        }
        colors = await PaletteMaker.colors(for: pinIDs, boardID: boardID, store: store)
        working = false
    }

    private func copy(_ hex: String) {
        UIPasteboard.general.string = hex
        showNote("Copied \(hex).")
    }

    private func copyAll() {
        UIPasteboard.general.string = colors.joined(separator: "\n")
        showNote("Copied \(colors.count) hex codes.")
    }

    private func shareSwatch(_ hex: String) {
        var items: [Any] = [hex]
        if let image = PaletteImages.swatch(hex) { items.append(image) }
        share = PaletteShareRequest(items: items)
    }

    private func sharePalette() {
        var items: [Any] = []
        if let image = PaletteImages.palette(colors, title: posterTitle) { items.append(image) }
        items.append(colors.joined(separator: " "))
        share = PaletteShareRequest(items: items)
    }

    /// The result is a short confirmation (a warning one when it failed), not an alert to tap away.
    private func savePaletteToPhotos() {
        guard let image = PaletteImages.palette(colors, title: posterTitle) else {
            confirm("The palette picture couldn't be made.", symbol: PaletteSheet.warning)
            return
        }
        Task { @MainActor in
            if await PhotosSaver.save(image) {
                confirm("Saved the palette to Photos.")
            } else {
                confirm(PhotosSaver.problem("Photos didn't take the palette picture."), symbol: PaletteSheet.warning)
            }
        }
    }

    /// A picture of the palette becomes a new pin (the import reports where it went). The sheet
    /// closes first; the import starts once it is gone (`importPinPicture`), so the import's
    /// question — if the same picture is a pin already — and its confirmation show over the
    /// screen underneath, not over a sheet that is on its way out.
    private func saveAsPin() {
        guard let image = PaletteImages.palette(colors, title: posterTitle) else {
            confirm("The palette picture couldn't be made.", symbol: PaletteSheet.warning)
            return
        }
        pinPicture = image
        dismiss()
    }

    /// The sheet has closed: imports the picture "Save as pin" left, if any.
    private func importPinPicture() {
        guard let image = pinPicture else { return }
        pinPicture = nil
        let boards = boardID.map { [$0] } ?? []
        let hidden = boardID == nil && scope == .hidden
        importFlow.importCaptured(image, boardIDs: boards, hidden: hidden)
    }

    /// The name printed on a palette picture. A picture of hidden pins carries no name,
    /// so nothing hidden is written into Photos or onto a shared image.
    private var posterTitle: String? {
        scope == .hidden ? nil : title
    }

    /// Shows "Copied …" in the sheet's note for 1.8 seconds. Each note has its own number, so the
    /// timer of an earlier note (the same swatch tapped twice, say) never hides a later one.
    /// VoiceOver reads it out half a second later, as the app's confirmations do, so a menu that
    /// is still closing doesn't cut it off — unless another note has taken its place by then.
    /// The newest message wins: the app's confirmation, if one is showing, goes away.
    private func showNote(_ text: String) {
        importFlow.clearToast()
        noteNumber += 1
        let number = noteNumber
        withAnimation(.easeOut(duration: 0.15)) { note = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard noteNumber == number else { return }   // replaced meanwhile
            AccessibilityNotification.Announcement(text).post()   // VoiceOver says it too
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard noteNumber == number else { return }
            withAnimation(.easeOut(duration: 0.3)) { note = nil }
        }
    }

    /// The app's short confirmation (over this sheet while it is up), in place of the note.
    private func confirm(_ text: String, symbol: String = "checkmark.circle") {
        noteNumber += 1   // a note still showing goes, and its timer does nothing more
        withAnimation(.easeOut(duration: 0.15)) { note = nil }
        importFlow.flash(text, symbol: symbol)
    }
}

/// Things handed to the share sheet (kept for as long as it is open).
struct PaletteShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// One color: a rounded swatch with its hex code under it.
struct PaletteSwatch: View {
    let hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hexString: hex) ?? Color.gray)
                .aspectRatio(1.3, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
            Text(hex)
                .font(.body.monospaced())
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Color \(hex)")
    }
}

// MARK: - Pictures of a palette

/// Pictures made from colors: the whole palette (swatches and hex codes, about
/// 1600 × 1000 pixels) and a single 600 × 600 swatch.
@MainActor
enum PaletteImages {
    static func palette(_ colors: [String], title: String?) -> UIImage? {
        guard !colors.isEmpty else { return nil }
        let renderer = ImageRenderer(content: PalettePoster(colors: colors, title: title))
        renderer.scale = 1
        return renderer.uiImage
    }

    static func swatch(_ hex: String) -> UIImage? {
        let renderer = ImageRenderer(content: SwatchPoster(hex: hex))
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// The palette as one picture: a row of tall swatches, each with its hex code.
struct PalettePoster: View {
    let colors: [String]
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
            }
            HStack(spacing: 18) {
                ForEach(Array(colors.enumerated()), id: \.offset) { entry in
                    VStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(hexString: entry.element) ?? Color.gray)
                        Text(entry.element)
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
        }
        .padding(60)
        .frame(width: 1600, height: 1000)
        .background(Color.white)
    }
}

/// One color as a square picture, its hex code in the corner.
struct SwatchPoster: View {
    let hex: String

    var body: some View {
        (Color(hexString: hex) ?? Color.gray)
            .frame(width: 600, height: 600)
            .overlay(alignment: .bottomLeading) {
                Text(hex)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(28)
            }
    }
}

// MARK: - The board title's surprise

/// The board's name in big serif letters on a dark rounded block. The letters are
/// windows onto a gradient of the board's colors that glides steadily sideways
/// behind them: each color fills most of the word, then flows into the next —
/// one color every 2.5 seconds, looping forever. Still (a plain gradient across
/// the word) when Reduce Motion is on. Works on iOS 17.
struct PaletteTitleBlock: View {
    let name: String
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The word itself. Used twice: once to take up the room, once as the stencil.
    private var letters: some View {
        Text(name)
            .font(.system(size: 76, weight: .black, design: .serif))
            .lineLimit(1)
            .minimumScaleFactor(0.2)
    }

    var body: some View {
        letters
            .foregroundStyle(Color.clear)
            .overlay {
                GeometryReader { geometry in
                    fill(size: geometry.size)
                }
                .mask { letters }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }

    @ViewBuilder
    private func fill(size: CGSize) -> some View {
        let shown = colors.isEmpty ? [Color.gray] : colors
        if reduceMotion || shown.count < 2 {
            LinearGradient(colors: shown.count < 2 ? [shown[0], shown[0]] : shown,
                           startPoint: .leading, endPoint: .trailing)
        } else {
            TimelineView(.animation) { timeline in
                PanningGradient(colors: shown, size: size,
                                seconds: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

/// A long strip of colors (one word-width per color, each solid for 70% of it with
/// 30% blends) that glides to the left at an even speed, one color every
/// `secondsPerColor`. The strip is the colors once round, with the last color added
/// in front and the first two again at the end, so the word always has the right
/// neighbours on both sides and the loop repeats exactly — no seam.
struct PanningGradient: View {
    /// How long each color takes to slide by.
    static let secondsPerColor: Double = 2.5

    let colors: [Color]
    let size: CGSize
    let seconds: Double

    var body: some View {
        let segment = max(size.width, 1)
        let strip = Self.strip(for: colors)
        // +1: the word starts on the first real color (the strip begins with the last one).
        let shift = Self.position(seconds: seconds, count: colors.count) + 1
        LinearGradient(stops: Self.stops(for: strip), startPoint: .leading, endPoint: .trailing)
            .frame(width: segment * CGFloat(strip.count), height: size.height)
            .offset(x: -CGFloat(shift) * segment)
            .frame(width: size.width, height: size.height, alignment: .leading)
    }

    /// How many colors have gone by (0 ..< count), growing evenly with time — no stops,
    /// so the glide is smooth.
    static func position(seconds: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let colorsGoneBy = seconds / secondsPerColor
        return colorsGoneBy.truncatingRemainder(dividingBy: Double(count))
    }

    /// [last, c0 … c(n−1), c0, c1]: what the word slides over during one round.
    static func strip(for colors: [Color]) -> [Color] {
        guard let first = colors.first, let last = colors.last else { return [] }
        let second = colors.count > 1 ? colors[1] : first
        return [last] + colors + [first, second]
    }

    /// Each color holds from 15% to 85% of its stretch; the gaps between are the blends.
    static func stops(for strip: [Color]) -> [Gradient.Stop] {
        let segments = max(strip.count, 1)
        var stops: [Gradient.Stop] = []
        for (index, color) in strip.enumerated() {
            stops.append(Gradient.Stop(color: color, location: (CGFloat(index) + 0.15) / CGFloat(segments)))
            stops.append(Gradient.Stop(color: color, location: (CGFloat(index) + 0.85) / CGFloat(segments)))
        }
        return stops
    }
}
