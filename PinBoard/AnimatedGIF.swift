//
//  AnimatedGIF.swift  —  PinBoard
//
//  An animated GIF comes into the library as a short silent video, so it gets everything a
//  video has: it plays and loops on its card in the grid, in Quick Look and on its page, and
//  carries on from where it was left. The frames are written into an H.264 video, each shown for
//  as long as the GIF says (browsers' rule: a frame asking for less than 0.02 s gets 0.1 s), with
//  transparent parts filled white like the app's background. A GIF with only one frame stays a
//  picture. Used by `prepareImage` (LibraryImports.swift: Photos, Files, drops, links, Explore,
//  the clipboard) and the folder import (Export.swift).
//

import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Foundation

enum AnimatedGIF {
    /// The longest side of the video made from a GIF (bigger GIFs are scaled down).
    nonisolated static let maxSide = 1280

    /// Whether `data` is a GIF with more than one frame.
    nonisolated static func isAnimated(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              UTType(type)?.conforms(to: .gif) == true else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// The GIF as a video file in the temporary folder (the import takes it over, like a picked
    /// video), or nil when `data` isn't an animated GIF or the video couldn't be written.
    nonisolated static func videoFile(from data: Data) async -> URL? {
        guard isAnimated(data) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            await writeVideo(from: data)
        }.value
    }

    /// One frame of the GIF and how long it stays on screen.
    private struct Frame {
        let image: CGImage
        let seconds: Double
    }

    nonisolated private static func frames(of data: Data) -> [Frame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        var list: [Frame] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            list.append(Frame(image: image, seconds: delay(of: source, at: index)))
        }
        return list
    }

    /// How long frame `index` is shown, as browsers do it.
    nonisolated private static func delay(of source: CGImageSource, at index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let seconds = unclamped ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return seconds < 0.02 ? 0.1 : seconds
    }

    /// The video's size: the GIF's, scaled to fit `maxSide`, with even sides (H.264 needs them).
    nonisolated private static func videoSize(for image: CGImage) -> (width: Int, height: Int) {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(2, Int((Double(image.width) * scale).rounded()) / 2 * 2)
        let height = max(2, Int((Double(image.height) * scale).rounded()) / 2 * 2)
        return (width, height)
    }

    nonisolated private static func writeVideo(from data: Data) async -> URL? {
        let list = frames(of: data)
        guard list.count > 1, let first = list.first else { return nil }
        let size = videoSize(for: first.image)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        var elapsed = 0.0
        for frame in list {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)   // the encoder catches up
            }
            guard let buffer = pixelBuffer(for: frame.image, width: size.width, height: size.height, pool: adaptor.pixelBufferPool),
                  adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 600)) else {
                writer.cancelWriting()
                return nil
            }
            elapsed += frame.seconds
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: elapsed, preferredTimescale: 600))   // the last frame keeps its time
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// One frame drawn on white, scaled to the video's size.
    nonisolated private static func pixelBuffer(for image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var made: CVPixelBuffer? = nil
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(whole)
        context.interpolationQuality = .high
        context.draw(image, in: whole)
        return buffer
    }
}
