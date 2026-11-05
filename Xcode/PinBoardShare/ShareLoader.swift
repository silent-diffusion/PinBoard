//
//  ShareLoader.swift  —  PinBoard share extension
//
//  Reads what another app shares (pictures, GIFs, videos, web links, text) and copies each file
//  into the share's folder in the inbox (ShareShared.swift). Files are copied, never loaded into
//  memory whole: the share sheet runs inside the other app with very little memory, and a video
//  can be large. The app does the real import later (ShareInbox.swift).
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

@MainActor
enum ShareLoader {
    /// One shared thing → an inbox item (its file, if any, already copied into `folder`).
    /// nil: it is something PinBoard can't keep (a PDF, a contact…).
    static func load(_ provider: NSItemProvider, into folder: URL) async -> ShareInboxEntry.Item? {
        let name = provider.suggestedName
        // The order matters: a GIF is also a picture, and a file's address is also an address.
        if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            if let file = await copyFile(provider, type: .gif, into: folder) {
                return ShareInboxEntry.Item(kind: .gif, file: file, name: name)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let file = await copyFile(provider, type: .movie, into: folder) {
                return ShareInboxEntry.Item(kind: .video, file: file, name: name)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let file = await copyFile(provider, type: .image, into: folder) {
                return ShareInboxEntry.Item(kind: .picture, file: file, name: name)
            }
            // Some apps share a picture only as an image in memory (no file of it).
            if let file = await savePicture(provider, into: folder) {
                return ShareInboxEntry.Item(kind: .picture, file: file, name: name)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(provider) {
            if url.isFileURL { return await copyLocalFile(url, into: folder) }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return ShareInboxEntry.Item(kind: .link, url: url.absoluteString)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let text = await loadText(provider) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return ShareInboxEntry.Item(kind: .text, text: trimmed) }
        }
        return nil
    }

    /// Copies the provider's file of `type` into `folder`; returns the copy's name. The system's
    /// file is only there while the handler runs, so it is copied inside it.
    private static func copyFile(_ provider: NSItemProvider, type: UTType, into folder: URL) async -> String? {
        await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { (url: URL?, _: Error?) in
                guard let url else {
                    done.resume(returning: nil)
                    return
                }
                done.resume(returning: ShareLoader.copy(url, into: folder))
            }
        }
    }

    /// A file shared by its address (the Files app, some others): a picture, GIF, video or text file.
    private static func copyLocalFile(_ url: URL, into folder: URL) async -> ShareInboxEntry.Item? {
        let type = UTType(filenameExtension: url.pathExtension)
        let name = url.deletingPathExtension().lastPathComponent
        let kind: ShareInboxEntry.Kind
        if type?.conforms(to: .gif) == true {
            kind = .gif
        } else if type?.conforms(to: .movie) == true {
            kind = .video
        } else if type?.conforms(to: .image) == true {
            kind = .picture
        } else if type?.conforms(to: .plainText) == true {
            let text = await Task.detached(priority: .userInitiated) { () -> String? in
                ShareLoader.readText(url)
            }.value
            guard let text, !text.isEmpty else { return nil }
            return ShareInboxEntry.Item(kind: .text, text: text)
        } else {
            return nil
        }
        let file = await Task.detached(priority: .userInitiated) { () -> String? in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return ShareLoader.copy(url, into: folder)
        }.value
        guard let file else { return nil }
        return ShareInboxEntry.Item(kind: kind, file: file, name: name)
    }

    /// A picture shared only as an image in memory, saved as a JPEG.
    private static func savePicture(_ provider: NSItemProvider, into folder: URL) async -> String? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            _ = provider.loadObject(ofClass: UIImage.self) { (object: (any NSItemProviderReading)?, _: Error?) in
                guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.92) else {
                    done.resume(returning: nil)
                    return
                }
                let name = UUID().uuidString + ".jpg"
                let saved = (try? data.write(to: folder.appendingPathComponent(name))) != nil
                done.resume(returning: saved ? name : nil)
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
            _ = provider.loadObject(ofClass: URL.self) { (url: URL?, _: Error?) in
                done.resume(returning: url)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            _ = provider.loadObject(ofClass: String.self) { (text: String?, _: Error?) in
                done.resume(returning: text)
            }
        }
    }

    // MARK: Files (any thread)

    /// Copies a file into `folder` under a new name (keeping its extension); returns that name.
    nonisolated static func copy(_ url: URL, into folder: URL) -> String? {
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension.lowercased()
        let name = UUID().uuidString + "." + ext
        let target = folder.appendingPathComponent(name)
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        return name
    }

    /// A text file's words (at most a megabyte: a text pin, not a book).
    nonisolated static func readText(_ url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= 1_000_000, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A small picture of a shared file for the sheet's preview, as JPEG data (a video's first frame).
    nonisolated static func thumbnail(of file: URL, kind: ShareInboxEntry.Kind) async -> Data? {
        let size = 240
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: size, height: size)
            guard let frame = try? await generator.image(at: .zero).image else { return nil }
            return UIImage(cgImage: frame).jpegData(compressionQuality: 0.8)
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: small).jpegData(compressionQuality: 0.8)
    }
}
