import CloveCore
import CloveImaging
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small app-private Entry previews, keyed by photo identity and the source revision (handoff Entry).
/// Entry reads this cache without resolving a bookmark or reading the original folder.
actor EntryThumbnailStore {
    static let shared = EntryThumbnailStore()

    struct SourceRevision: Codable, Hashable, Sendable {
        let sourceName: String
        let file: ThumbnailRevision
    }

    private let root: URL?
    private var retainedNames: [FolderIdentity: Set<String>] = [:]

    init(
        directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("EntryPreviews", isDirectory: true)
    ) {
        root = directory
    }

    private func directory(for folder: FolderIdentity) -> URL? {
        root?.appendingPathComponent(Self.key(folder.rawValue), isDirectory: true)
    }

    private static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func file(for photo: PhotoIdentity) -> URL? {
        directory(for: photo.folderID)?.appendingPathComponent(
            Self.key(photo.relativeFolderPath + "/" + photo.stem) + ".jpg")
    }

    func image(for photo: PhotoIdentity) -> CGImage? {
        guard let url = file(for: photo) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("json"))
            return nil
        }
        return image
    }

    func contains(_ photo: PhotoIdentity, revision: SourceRevision) -> Bool {
        guard let url = file(for: photo), FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url.appendingPathExtension("json")),
            let saved = try? JSONDecoder().decode(SourceRevision.self, from: data)
        else { return false }
        return saved == revision
    }

    func store(_ image: CGImage, for photo: PhotoIdentity, revision: SourceRevision) {
        guard !contains(photo, revision: revision), let url = file(for: photo),
            let directory = directory(for: photo.folderID)
        else { return }
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
            try JSONEncoder().encode(revision).write(
                to: url.appendingPathExtension("json"), options: .atomic)
        } catch {
            // A cache failure remains a placeholder, never a mark-save failure.
        }
    }

    /// Prunes once when the retained identities change, preserving names from the progress record
    /// even when a partial scan has not rediscovered their source files.
    func retain(_ photos: [PhotoIdentity], in folder: FolderIdentity) {
        guard let directory = directory(for: folder) else { return }
        let keep = Set(
            photos.filter { $0.folderID == folder }.compactMap { file(for: $0) }
                .flatMap {
                    [$0.lastPathComponent, $0.appendingPathExtension("json").lastPathComponent]
                })
        guard retainedNames[folder] != keep else { return }
        do {
            for old in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
            where !keep.contains(old.lastPathComponent) {
                try? FileManager.default.removeItem(at: old)
            }
            retainedNames[folder] = keep
        } catch {
            // There may be no previews yet.
        }
    }
}
