//
//  ImageCache.swift  —  PinBoard
//
//  The library's picture caches (LibraryStore's `thumbCache` and `fullCache`), bounded by memory
//  rather than only by count. A count alone doesn't bound memory: 300 small pictures can be 40 MB
//  or 400 MB depending on their size. Each picture is charged its decoded size in bytes, and the
//  cache lets older ones go once the total passes its limit. It is emptied when iOS warns that
//  memory is low (pictures are read again from disk when next needed).
//

import UIKit

final class ImageCache: NSCache<NSString, UIImage>, @unchecked Sendable {
    /// - Parameters:
    ///   - megabytes: the limit on a phone with 4 GB of memory; scaled for the actual device
    ///     (half on a 2 GB phone, at most double on 8 GB or more, e.g. a Mac).
    ///   - count: the most pictures kept, whatever their size.
    init(megabytes: Int, count: Int) {
        super.init()
        countLimit = count
        totalCostLimit = Int(Double(megabytes * 1_048_576) * Self.memoryScale)
        NotificationCenter.default.addObserver(self, selector: #selector(memoryIsLow),
                                               name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    /// Plain `setObject(_:forKey:)` calls (all of PinBoard's) are charged the picture's size.
    override func setObject(_ image: UIImage, forKey key: NSString) {
        super.setObject(image, forKey: key, cost: Self.bytes(of: image))
    }

    @objc private func memoryIsLow() { removeAllObjects() }

    /// The device's memory compared with 4 GB, kept between 0.5 and 2.
    private static let memoryScale: Double = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return min(max(gigabytes / 4, 0.5), 2)
    }()

    /// What a decoded picture takes in memory.
    static func bytes(of image: UIImage) -> Int {
        if let cgImage = image.cgImage { return cgImage.bytesPerRow * cgImage.height }
        let width = image.size.width * image.scale, height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}
