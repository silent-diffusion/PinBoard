//
//  ShareFamiliarCheck.swift  —  PinBoard share extension
//
//  "Looks familiar" in the share sheet: each shared thing is compared with the normal library,
//  by the app's own import rules (8.4 of the spec), against the index the app writes
//  (ShareFamiliar.swift in the app, the format in ShareShared.swift):
//    • a picture (a GIF or a video by its first frame): its 64-step light-and-dark signature
//      differs from a pin's in at most 6 steps, and their shapes are close (0.85–1.18) — the
//      closest one counts. A look-alike, so the person chooses.
//    • a link: the same page (the common kinds of tracking taken out first) — an exact copy.
//    • text: the same words, ignoring capitals and blank space at the ends — an exact copy.
//  Each thing is looked at on its own, from a small copy, so many at once use little memory.
//  The index never holds a hidden pin, so the sheet can never point at one.
//

import Foundation
import UIKit
import ImageIO
import AVFoundation

/// A shared thing that looks like a pin you already have.
struct FamiliarMatch: Sendable {
    var existing: ShareFamiliarIndex.Known
    /// The same link or text (today's rule: the pin you have goes on the board, with a note);
    /// false: a look-alike picture or video (the person chooses).
    var exact: Bool
}

enum ShareFamiliarCheck {
    /// The app's limits (LibraryStore.duplicateHashDistance, LibraryStore.bestMatch).
    nonisolated static let maxDistance = 6

    /// Every shared thing that looks familiar, by its id. Run away from the screen.
    nonisolated static func check(_ items: [ShareInboxEntry.Item], in folder: URL,
                                  index: ShareFamiliarIndex) async -> [UUID: FamiliarMatch] {
        let known = Dictionary(index.pins.map { ($0.id, $0) }, uniquingKeysWith: { (first, _) in first })
        let pictures: [(id: UUID, hash: UInt64, aspect: Double)] = index.pictures.compactMap { (picture: ShareFamiliarIndex.Picture) in
            ShareFamiliarIndex.hash(fromHex: picture.hash).map { (id: picture.id, hash: $0, aspect: picture.aspect) }
        }
        var found: [UUID: FamiliarMatch] = [:]
        for item in items {
            guard let match = await match(item, in: folder, index: index, pictures: pictures),
                  let pin = known[match.id] else { continue }
            found[item.id] = FamiliarMatch(existing: pin, exact: match.exact)
        }
        return found
    }

    private nonisolated static func match(_ item: ShareInboxEntry.Item, in folder: URL, index: ShareFamiliarIndex,
                                          pictures: [(id: UUID, hash: UInt64, aspect: Double)]) async -> (id: UUID, exact: Bool)? {
        switch item.kind {
        case .link:
            return item.url.flatMap { linkMatch($0, index: index) }.map { (id: $0, exact: true) }
        case .text:
            let text = item.text ?? ""
            if let link = webAddress(in: text) { return linkMatch(link, index: index).map { (id: $0, exact: true) } }
            return index.texts[ShareFamiliarIndex.textKey(text)].map { (id: $0, exact: true) }
        case .picture, .gif, .video:
            guard let file = item.file else { return nil }
            let url = folder.appendingPathComponent(file)
            guard let signature = await signature(of: url, video: item.kind == .video) else { return nil }
            return closest(signature.hash, aspect: signature.aspect, among: pictures).map { (id: $0, exact: false) }
        }
    }

    /// The same page as a link pin (the app keeps each link pin's page already normalized).
    private nonisolated static func linkMatch(_ address: String, index: ShareFamiliarIndex) -> UUID? {
        let key = ShareFamiliarIndex.normalized(ShareFamiliarIndex.withoutCommonTracking(address))
        return index.links[key]
    }

    /// Text that is just one web address (as the app reads it: LibraryStore.linkURL).
    private nonisolated static func webAddress(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return trimmed
    }

    /// The closest look-alike (LibraryStore.bestMatch): at most 6 steps apart, shapes close.
    nonisolated static func closest(_ hash: UInt64, aspect: Double,
                                    among pictures: [(id: UUID, hash: UInt64, aspect: Double)]) -> UUID? {
        guard hash != 0 else { return nil }
        var best: (id: UUID, distance: Int)? = nil
        for picture in pictures {
            let distance = (hash ^ picture.hash).nonzeroBitCount
            guard distance <= maxDistance else { continue }
            let ratio = picture.aspect / max(aspect, 0.01)
            guard ratio > 0.85 && ratio < 1.18 else { continue }
            if best == nil || distance < best!.distance { best = (picture.id, distance) }
        }
        return best?.id
    }

    // MARK: The signature (ImageSignals.differenceHash, the same steps as the app)

    /// A picture's (or a video's first frame's) signature and shape, from a small copy.
    nonisolated static func signature(of file: URL, video: Bool) async -> (hash: UInt64, aspect: Double)? {
        let image: CGImage?
        if video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            image = try? await generator.image(at: .zero).image
        } else {
            image = smallCopy(of: file)
        }
        guard let image, let hash = differenceHash(image) else { return nil }
        return (hash, Double(max(image.width, 1)) / Double(max(image.height, 1)))
    }

    private nonisolated static func smallCopy(of file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The picture drawn 9 × 8 pixels; each bit says whether a pixel is lighter than its right-hand neighbour.
    nonisolated static func differenceHash(_ image: CGImage) -> UInt64? {
        let width = 9
        let height = 8
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<8 {
            for column in 0..<8 {
                let left = luminance(buffer, (row * 9 + column) * 4)
                let right = luminance(buffer, (row * 9 + column + 1) * 4)
                if left > right { hash |= (1 << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }

    private nonisolated static func luminance(_ rgba: [UInt8], _ index: Int) -> Double {
        0.299 * Double(rgba[index]) + 0.587 * Double(rgba[index + 1]) + 0.114 * Double(rgba[index + 2])
    }

    /// A pin's tiny picture from the shared folder (nil: none).
    nonisolated static func thumbnail(of pin: ShareFamiliarIndex.Known, in folder: URL?) -> UIImage? {
        guard let name = pin.thumb, let folder else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }
}
