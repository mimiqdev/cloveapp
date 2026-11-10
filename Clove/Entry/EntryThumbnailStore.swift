import CloveCore
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Four small cached previews per recent folder (handoff Entry; G1 preview strategy).
/// Entry reads only this app-private cache, never a bookmark or the original folder.
actor EntryThumbnailStore {
    static let shared = EntryThumbnailStore()

    private func directory(for folder: FolderIdentity) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EntryPreviews", isDirectory: true)
            .appendingPathComponent(Self.key(folder.rawValue), isDirectory: true)
    }

    private static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func file(for photo: PhotoIdentity) -> URL? {
        directory(for: photo.folderID)?.appendingPathComponent(
            Self.key(photo.relativeFolderPath + "/" + photo.stem) + ".jpg")
    }

    func image(for photo: PhotoIdentity) -> CGImage? {
        guard let url = file(for: photo),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func store(_ image: CGImage, for photo: PhotoIdentity, keeping photos: [PhotoIdentity]) {
        guard let url = file(for: photo), let directory = directory(for: photo.folderID) else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(
                destination, image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return }
            try (data as Data).write(to: url, options: .atomic)
            let keep = Set(photos.compactMap { file(for: $0)?.lastPathComponent })
            for old in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
            where !keep.contains(old.lastPathComponent) {
                try? FileManager.default.removeItem(at: old)
            }
        } catch {
            // A cache miss is a placeholder; it never blocks opening or reports a save failure.
        }
    }
}
