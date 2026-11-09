import Darwin
import Foundation

/// Every file-system operation a rejects move performs, injectable so a test can fail any step.
///
/// G1 decision 5 and PRD P0-10 fix the shape of the move: one photo set is renamed into the
/// rejects folder on the same volume, and per-file confirmation decides success. The seam
/// therefore offers no `remove`, no `copy` and no plain `rename`: the move lane cannot delete a
/// file or duplicate one across volumes even by mistake. A collision is refused by the
/// exclusive rename itself, so a check followed by an ordinary rename is never enough.
///
/// Tests fail folder creation, the exclusive rename, `EXDEV`, `EACCES`, `EROFS`, `ENOSPC` and
/// `ENOENT`, and the move back that follows a partial set (PRD P0-10, "Failure and recovery").
public protocol RejectMoveFileSystem: Sendable {
    /// The file's size in bytes, or `nil` when nothing exists at `url`.
    ///
    /// G1 decision 5's confirmation compares the destination's size with the source's size
    /// recorded before the move, so a size is both the existence check and the evidence.
    func fileSize(at url: URL) throws -> Int?

    /// Whether anything exists at `url`; used for collisions and after a move.
    ///
    /// PRD P0-10's plan checks a destination name before choosing a suffix, and the confirmed
    /// move checks that the source is gone (G1 decision 5).
    func exists(at url: URL) throws -> Bool

    /// The identifier of the volume holding `url`, or `nil` when the system reports none.
    ///
    /// PRD P0-10 limits the move to one volume. A destination folder that does not exist yet
    /// is resolved through its nearest existing ancestor, so the plan compares the two volumes
    /// before creating anything.
    func volumeIdentifier(of url: URL) throws -> String?

    /// Whether the volume holding `url` reports itself read-only.
    ///
    /// PRD P0-10 and PRD Failure and recovery refuse the whole request on a read-only
    /// location. Only the volume's own read-only value is evidence here; a generic failed
    /// rename is classified separately and never inferred as read-only (S1's failure table).
    func isReadOnlyVolume(at url: URL) throws -> Bool

    /// Creates `url` and every missing parent, doing nothing when it already exists.
    ///
    /// PRD P0-10 preserves the subfolder structure under the rejects folder, so the
    /// destination's folders may be created as needed. An existing folder is never replaced.
    func createDirectory(_ url: URL) throws

    /// Renames `source` to `destination`, refusing when `destination` already exists.
    ///
    /// G1 decision 5 and PRD P0-10 say the move never overwrites; the production call is
    /// `renamex_np` with `RENAME_EXCL`, so the refusal comes from the rename itself. The
    /// kernel also refuses a cross-volume rename with `EXDEV`, which is reported as a failure
    /// and never retried as a copy (PRD P0-10).
    func moveExclusively(from source: URL, to destination: URL) throws
}

/// Production file operations: Foundation for reads and folders, POSIX for the exclusive move.
///
/// G1 decision 5 runs the move on local APFS at launch; external media waits for #29. Folder
/// creation uses `FileManager.createDirectory(withIntermediateDirectories:)`, sizes and
/// existence use `attributesOfItem`, and the move is `renamex_np(2)` with `RENAME_EXCL` so an
/// existing destination is refused with `EEXIST` and a different volume with `EXDEV`. The
/// implementation imports `Darwin` for both Apple platforms and uses no private API.
public struct FoundationRejectMoveFileSystem: RejectMoveFileSystem {
    /// Creates the production file system; it holds no state and can be shared.
    public init() {}

    /// Reads the file's size, mapping "not found" to `nil` (PRD P0-10's confirmation).
    public func fileSize(at url: URL) throws -> Int? {
        do {
            let values = try FileManager.default.attributesOfItem(atPath: path(of: url))
            return (values[.size] as? NSNumber)?.intValue
        } catch {
            // The scan's own "no such file" mapping is reused so one error shape covers both
            // lanes (S1's failure table).
            if isMissingFileError(error) { return nil }
            throw error
        }
    }

    /// Reports existence without reading the file, mapping "not found" to `false`.
    public func exists(at url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: path(of: url))
            return true
        } catch {
            if isMissingFileError(error) { return false }
            throw error
        }
    }

    /// Reads the volume's UUID through the nearest existing ancestor of `url`.
    ///
    /// A destination folder usually does not exist before the move, so the nearest existing
    /// ancestor is the volume that `createDirectory` would create it on (PRD P0-10).
    public func volumeIdentifier(of url: URL) throws -> String? {
        let existing = nearestExistingAncestor(of: url)
        return try existing.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    /// Reads the volume's read-only value for the nearest existing ancestor (PRD P0-10).
    public func isReadOnlyVolume(at url: URL) throws -> Bool {
        let existing = nearestExistingAncestor(of: url)
        return try existing.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
            ?? false
    }

    /// Creates the destination folder and its parents, doing nothing when it exists.
    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: nil)
    }

    /// Renames with `renamex_np(2)` and `RENAME_EXCL`, so an existing destination is refused.
    public func moveExclusively(from source: URL, to destination: URL) throws {
        let status = renamex_np(path(of: source), path(of: destination), UInt32(RENAME_EXCL))
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// The file-system path without percent escapes, which Foundation may otherwise keep.
    private func path(of url: URL) -> String { url.path(percentEncoded: false) }

    /// The nearest existing entry at or above `url`, for a destination that does not exist yet.
    ///
    /// Walking stops at the file-system root, so a nonexistent path still reports the volume of
    /// the mount it belongs to; reading that root's values is left to the caller's `try`.
    private func nearestExistingAncestor(of url: URL) -> URL {
        var candidate = url
        while true {
            if FileManager.default.fileExists(atPath: path(of: candidate)) { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if path(of: parent) == path(of: candidate) { return candidate }
            candidate = parent
        }
    }
}

/// Path comparisons for the plan, so two spellings of one folder compare equal.
///
/// The scan may address the opened folder as `/var/...` while the enumerator reports
/// `/private/var/...` (C2's walk records the same difference), so the plan compares resolved,
/// standardized paths and never the raw spelling. The spelling the caller supplied is still
/// what the destination is built from, so file names and extension case stay exactly as they
/// are on disk (PRD P0-10).
enum RejectMovePath {
    /// The resolved path without a trailing slash.
    static func canonical(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Whether two URLs name the same folder or file on disk.
    static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        canonical(lhs) == canonical(rhs)
    }
}

/// The one suffix rule for a set whose destination names are taken.
///
/// PRD P0-10 adds a suffix when a destination name exists and never overwrites. The suffix is
/// inserted before the file's last extension and the same suffix is applied to every file of
/// the set, so the primary, its JPEG/HIF companions and the `.xmp` still pair by stem after the
/// move (G1 decision 5). The spelling around it is untouched, including the extension's case.
enum RejectMoveNaming {
    /// The file name as it is for attempt 0, or with `-attempt` before its extension.
    ///
    /// A sidecar uses the replaced-extension form G1's Sidecar naming row requires, so
    /// `IMG_0001.xmp` and `IMG_0001.XMP` keep their spelling and only gain the suffix. A set
    /// whose packet appends an extension is refused as ambiguous before this rule applies.
    static func suffixed(_ name: String, attempt: Int) -> String {
        guard attempt > 0 else { return name }
        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        let suffixedStem = "\(stem)-\(attempt)"
        return pathExtension.isEmpty ? suffixedStem : "\(suffixedStem).\(pathExtension)"
    }
}
