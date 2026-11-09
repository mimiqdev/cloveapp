import Foundation

/// Why the Recents file could not be used (PRD P0-02).
///
/// Corrupt or unreadable storage is reported so the caller can keep the existing file instead of
/// silently replacing it with an empty list. G1 folder access makes the file app-private.
public enum RecentFolderStoreError: Error, Hashable, Sendable {
    /// The file exists but could not be read or decoded; it was left as it was.
    case unreadable(FolderErrorChain)
    /// The file was written by a newer schema version; it was left as it was.
    case unsupportedVersion(Int)
    /// The file could not be written; an earlier version may still be in place.
    case writeFailed(FolderErrorChain)
}

/// The JSON file that remembers opened folders for P0-02.
///
/// One file holds every record and is replaced atomically on save. The decode is versioned and
/// rejects unknown versions, so a newer schema is never read as if it were understood. G1 folder
/// access puts the file in app-private Application Support; tests inject their own location.
public struct RecentFolderStore: Sendable {
    /// The current on-disk schema; a different value is refused rather than guessed.
    public static let schemaVersion = 1

    /// The JSON file to read and write; injectable so tests never touch app storage.
    public let fileURL: URL

    /// Points the store at one JSON file; the parent directory is created on save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The app-private Application Support file used by the app (no cloud, no Keychain).
    ///
    /// Keeping the record inside the app container means an uninstalled app forgets its Recents,
    /// which G1 decision 5 already accepts for Clove-stored marks.
    public static func applicationSupport(
        fileManager: FileManager = .default
    ) throws -> RecentFolderStore {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return RecentFolderStore(fileURL: directory.appendingPathComponent("RecentFolders.json"))
    }

    /// Reads every record, most recently opened first; a missing file is simply empty.
    ///
    /// A file that exists but cannot be read, decoded or understood is reported and never
    /// overwritten by this type's readers.
    public func load() throws -> [RecentFolder] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try JSONDecoder().decode(StoredRecents.self, from: data)
            guard stored.version == Self.schemaVersion else {
                throw RecentFolderStoreError.unsupportedVersion(stored.version)
            }
            return stored.folders
        } catch let error as RecentFolderStoreError {
            throw error
        } catch {
            throw RecentFolderStoreError.unreadable(FolderErrorChain(error))
        }
    }

    /// Replaces the file with these records, written atomically inside its directory.
    public func save(_ folders: [RecentFolder]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let stored = StoredRecents(version: Self.schemaVersion, folders: folders)
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RecentFolderStoreError.writeFailed(FolderErrorChain(error))
        }
    }
}

/// The versioned envelope around each saved record (see `RecentFolderStore.schemaVersion`).
private struct StoredRecents: Codable {
    /// The schema that wrote this file.
    var version: Int
    /// The remembered folders, in store order.
    var folders: [RecentFolder]
}
