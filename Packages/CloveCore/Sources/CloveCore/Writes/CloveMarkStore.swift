import CryptoKit
import Foundation

/// Why Clove's own mark storage could not be read or written.
///
/// G1 decision 6 keeps new standalone JPEG/HIF marks there, Reject included, so a damaged file
/// must be reported rather than silently replaced: the stored marks are the only copy, and PRD
/// How marks reach disk, rule 7, forbids reporting an unconfirmed change as saved. The location
/// stays injectable through ``CloveMarkStore``'s initializer so tests use a temporary folder.
public enum CloveMarkStoreError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The stored file is not a valid Clove mark file, or names a different folder.
    /// The store refuses to overwrite it and reports the path and reason.
    case corruptStorage(URL, reason: String)
    /// The stored file did not read back as the values just written (PRD P0-08).
    case readBackMismatch(URL)

    /// A developer-facing explanation; product copy belongs to the save-state UI.
    public var description: String {
        switch self {
        case .corruptStorage(let url, let reason):
            return "Clove's stored marks at \(url.lastPathComponent) are unreadable: \(reason)"
        case .readBackMismatch(let url):
            return "Clove's stored marks at \(url.lastPathComponent) did not read back as written."
        }
    }
}

/// Clove's own mark storage: one atomic JSON file per folder identity.
///
/// G1 decision 6 keeps new standalone JPEG/HIF marks in Clove rather than in XMP or in the
/// image, Reject included as the rating −1. PRD P0-08 shows them as "Saved in Clove only"
/// only after the stored copy is confirmed, and PRD How marks reach disk, rule 1, reads that
/// storage when a folder opens. Each folder identity gets one file at `marks-v1-<hash>.json`
/// below the injected directory, written through the same staged replacement and read-back the
/// sidecar write uses; the production directory is app-private Application Support.
///
/// The store is an actor because the write queue and the open path can read and write the
/// same folder's file, and its actor isolation is the only lock it needs.
public actor CloveMarkStore {
    /// The directory holding one file per folder identity; injectable for tests.
    private let directory: URL
    /// The staged replacement seam shared with the sidecar writer (G1 Safe writes).
    private let fileSystem: any MarkWriteFileSystem

    /// Creates a store rooted at `directory`, creating it on the first confirmed write.
    ///
    /// Production passes ``applicationSupportDirectory()``; tests pass a temporary folder so
    /// nothing touches the real Application Support container.
    public init(
        directory: URL, fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem()
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    /// The production location: an app-private folder below Application Support.
    ///
    /// G1 decision 6 accepts that standalone marks do not survive a reinstall or move to
    /// another device. One file per folder identity keeps a corrupt file from taking the
    /// other folders' marks with it, and the folder name keeps Clove's storage separate from
    /// C11's Recents.
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        return base.appendingPathComponent("Clove", isDirectory: true)
            .appendingPathComponent("StoredMarks", isDirectory: true)
    }

    /// The stored marks for every photo of an opened folder (PRD How marks reach disk, rule 1).
    ///
    /// G1 decision 6 keys standalone marks by folder identity and file, and this read gives the
    /// open path the whole folder in one step. A missing file is an empty result, not an error; a
    /// damaged file throws ``CloveMarkStoreError/corruptStorage(_:reason:)`` so the caller can
    /// report it instead of showing photos as unmarked.
    public func marks(for folderID: FolderIdentity) throws -> [PhotoIdentity: CloveStoredMarks] {
        let storage = try load(folderID: folderID)
        var marks: [PhotoIdentity: CloveStoredMarks] = [:]
        for photo in storage.photos {
            marks[
                PhotoIdentity(
                    folderID: folderID, relativeFolderPath: photo.relativeFolderPath,
                    stem: photo.stem)] = photo.marks
        }
        return marks
    }

    /// The stored marks for one photo, or `nil` when Clove stores nothing for it.
    ///
    /// Used to read a standalone JPEG/HIF mark after an open (G1 decision 6); a damaged file is
    /// reported as in ``marks(for:)``.
    public func marks(for identity: PhotoIdentity) throws -> CloveStoredMarks? {
        try load(folderID: identity.folderID).photo(for: identity)?.marks
    }

    /// Confirms a partial change into Clove storage and reads the file back.
    ///
    /// G1 decision 6 sends standalone marks here, Reject included, and PRD P0-08 permits
    /// "Saved in Clove only" only after this returns: the file is staged, synchronized,
    /// renamed into place, then decoded again and compared. A failed or unconfirmed write
    /// throws and leaves the previous file untouched; a damaged file throws instead of being
    /// overwritten.
    public func apply(_ change: CloveMarkChange, to identity: PhotoIdentity) throws {
        guard !change.isEmpty else { return }
        var storage = try load(folderID: identity.folderID)
        var marks = storage.photo(for: identity)?.marks ?? CloveStoredMarks()
        // PRD P0-05 reads zero as unrated, so clearing a stored rating removes the value.
        if let rating = change.rating { marks.rating = rating == .unrated ? nil : rating }
        if let label = change.label { marks.label = label.isClear ? nil : label }
        storage.set(marks, for: identity)
        try save(storage, folderID: identity.folderID)
    }

    /// Drops a stored Reject after C6 confirms the move to `_Rejected`.
    ///
    /// The move is the durable Reject result, so the stored rating −1 is cleared only after C6
    /// reports the confirmed move; the photo's stored label stays. Undo of the move writes the
    /// Reject again through C4. A photo that is not stored as rejected is a no-op, and the
    /// removal is confirmed by read-back.
    /// - Returns: `true` when a stored Reject was cleared and confirmed, `false` otherwise.
    @discardableResult
    public func clearReject(for identity: PhotoIdentity) throws -> Bool {
        var storage = try load(folderID: identity.folderID)
        guard var marks = storage.photo(for: identity)?.marks, marks.isRejected else {
            return false
        }
        marks.rating = nil
        storage.set(marks, for: identity)
        try save(storage, folderID: identity.folderID)
        return true
    }

    /// The file holding one folder identity's marks, named by a hash of the identity.
    ///
    /// A folder identity is an opaque bookmark-derived key (C1's `FolderIdentity`) that can
    /// contain any character, so the file name is a SHA-256 digest rather than the raw value.
    /// One file per identity keeps G1 decision 6's per-folder storage independent.
    func fileURL(for folderID: FolderIdentity) -> URL {
        let digest = SHA256.hash(data: Data(folderID.rawValue.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("marks-v1-\(name).json")
    }

    /// Reads one folder's storage, refusing a damaged or foreign file.
    private func load(folderID: FolderIdentity) throws -> CloveMarkStorageFile {
        let url = fileURL(for: folderID)
        guard let data = try fileSystem.read(url) else {
            return CloveMarkStorageFile(folderID: folderID.rawValue, photos: [])
        }
        do {
            let storage = try JSONDecoder().decode(CloveMarkStorageFile.self, from: data)
            guard storage.version == CloveMarkStorageFile.currentVersion else {
                throw CloveMarkStoreError.corruptStorage(
                    url,
                    reason:
                        "version \(storage.version) is not \(CloveMarkStorageFile.currentVersion)")
            }
            guard storage.folderID == folderID.rawValue else {
                throw CloveMarkStoreError.corruptStorage(
                    url, reason: "the file names another folder")
            }
            guard storage.hasUniqueIdentities, storage.hasValidRatings else {
                throw CloveMarkStoreError.corruptStorage(
                    url, reason: "the photo list repeats an identity or holds an invalid rating")
            }
            return storage
        } catch let error as CloveMarkStoreError {
            throw error
        } catch {
            throw CloveMarkStoreError.corruptStorage(url, reason: "\(error)")
        }
    }

    /// Writes one folder's storage atomically and confirms the read-back (PRD P0-08).
    private func save(_ storage: CloveMarkStorageFile, folderID: FolderIdentity) throws {
        let url = fileURL(for: folderID)
        let data: Data
        do {
            data = try JSONEncoder().encode(storage)
        } catch {
            throw CloveMarkStoreError.corruptStorage(url, reason: "\(error)")
        }
        try Task.checkCancellation()
        try fileSystem.createDirectory(directory)
        let staging = directory.appendingPathComponent(".clove-marks-\(UUID().uuidString)")
        var replaced = false
        defer { if !replaced { try? fileSystem.remove(staging) } }
        try fileSystem.writeStaging(data, to: staging)
        try fileSystem.synchronize(staging)
        try Task.checkCancellation()
        try fileSystem.replace(url, withItemAt: staging)
        replaced = true
        guard let readBack = try fileSystem.read(url),
            let decoded = try? JSONDecoder().decode(CloveMarkStorageFile.self, from: readBack),
            decoded == storage
        else {
            throw CloveMarkStoreError.readBackMismatch(url)
        }
    }
}

/// The JSON shape of one folder identity's stored marks, versioned for a later migration.
struct CloveMarkStorageFile: Codable, Hashable, Sendable {
    /// The shape this build writes and reads; an unknown value is damaged storage.
    static let currentVersion = 1
    /// The envelope version, so a later build can migrate instead of guessing.
    var version: Int = CloveMarkStorageFile.currentVersion
    /// The folder identity the file belongs to, checked on every read.
    var folderID: String
    /// One entry per photo with something stored, sorted by path then stem before writing.
    var photos: [CloveStoredPhoto]

    /// The entry for one photo, matched the way ``PhotoIdentity`` builds its key.
    func photo(for identity: PhotoIdentity) -> CloveStoredPhoto? {
        photos.first { $0.matches(identity) }
    }

    /// Replaces or removes one photo's entry, keeping the file sorted and compact.
    mutating func set(_ marks: CloveStoredMarks, for identity: PhotoIdentity) {
        photos.removeAll { $0.matches(identity) }
        guard !marks.isEmpty else { return }
        photos.append(CloveStoredPhoto(identity: identity, marks: marks))
        photos.sort { lhs, rhs in
            (lhs.relativeFolderPath, lhs.stem) < (rhs.relativeFolderPath, rhs.stem)
        }
    }

    /// Whether every stored rating is inside the −1…5 range that PRD P0-05 defines.
    var hasValidRatings: Bool {
        photos.allSatisfy { photo in
            photo.rating.map { Rating(rawValue: $0) != nil } ?? true
        }
    }

    /// Whether two entries name the same photo, which would make the file ambiguous.
    var hasUniqueIdentities: Bool {
        Set(photos.map { "\($0.relativeFolderPath)\u{0}\($0.stem)" }).count == photos.count
    }
}

/// One photo's stored marks in the JSON file.
struct CloveStoredPhoto: Codable, Hashable, Sendable {
    /// The containing directory relative to the opened folder, empty at its root.
    var relativeFolderPath: String
    /// The case-folded stem C1 uses as the photo's key.
    var stem: String
    /// A stored rating, −1 for Reject, absent when none is stored (G1 decision 6).
    var rating: Int?
    /// Stored label text, absent when no label is stored (G1 decision 6).
    var label: String?

    /// Builds the stored entry for one photo from confirmed marks.
    init(identity: PhotoIdentity, marks: CloveStoredMarks) {
        self.relativeFolderPath = identity.relativeFolderPath
        self.stem = identity.stem
        self.rating = marks.rating?.rawValue
        self.label = marks.label?.rawValue
    }

    /// Whether this entry names `identity`, using C1's folded stem and relative folder.
    func matches(_ identity: PhotoIdentity) -> Bool {
        relativeFolderPath == identity.relativeFolderPath
            && stem == identity.stem
    }

    /// The typed marks the rest of the write lane uses.
    var marks: CloveStoredMarks {
        CloveStoredMarks(
            rating: rating.flatMap { Rating(rawValue: $0) },
            label: label.map { ColourLabel(rawValue: $0) })
    }
}
