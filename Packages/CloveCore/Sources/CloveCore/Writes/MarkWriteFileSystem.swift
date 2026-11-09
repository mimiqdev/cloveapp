import Darwin
import Foundation

/// The size, modification date and permissions a mark write reads around its replacement.
///
/// G1's Safe writes row asks for a staged replacement and a read-back confirmation, and
/// PRD How marks reach disk, rules 3 and 7, ask the write to keep everything else the packet
/// already carries. Size and modification date are the values the conflict check compares;
/// the POSIX permission bits are carried across the `rename` because the staging file's own
/// mode would otherwise become the sidecar's.
public struct MarkFileAttributes: Hashable, Sendable {
    /// The file's size in bytes, from the last `stat`.
    public let size: Int
    /// The modification date the file system reports.
    public let modificationDate: Date
    /// The POSIX permission bits, for example `0o644`, that the file currently has.
    public let permissions: UInt16

    /// Describes one file's state before or after a staged replacement.
    public init(size: Int, modificationDate: Date, permissions: UInt16) {
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }

    /// The size and modification date pair G1's conflict check compares, not the content.
    public var stamp: MarkFileStamp {
        MarkFileStamp(size: size, modificationDate: modificationDate)
    }
}

/// The pair of file facts that shows another app replaced the sidecar after Clove read it.
///
/// G1's Safe writes row says to start again once when the destination changes, then report a
/// conflict, and never to overwrite another app's newer write blindly. Size and modification
/// date are the cheap signal the scan already prefetches; content is compared only by the
/// final read-back of the marks Clove owns.
public struct MarkFileStamp: Hashable, Sendable {
    /// The destination's size when Clove last read it.
    public let size: Int
    /// The destination's modification date when Clove last read it.
    public let modificationDate: Date

    /// Stores the two values the conflict check compares.
    public init(size: Int, modificationDate: Date) {
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Every file operation a mark write performs, injectable so tests can fail any step.
///
/// G1's Safe writes row fixes the sequence: read, stage in the same folder, synchronize the
/// staging file, POSIX `rename`, then read the destination back. A mark write also captures
/// the destination's attributes for the conflict check and its permissions, and removes its
/// own staging file on every failure path. Keeping the seam this small lets a test fail
/// `read`, `writeStaging`, `synchronize`, `replace` or the permissions step with a specific
/// `NSError`, which is how C4's failure reasons are exercised without a real disk fault.
///
/// Production uses ``FoundationMarkWriteFileSystem``; the write lane never touches
/// `FileManager` or `Darwin` directly.
public protocol MarkWriteFileSystem: Sendable {
    /// Returns the file's bytes, or `nil` when the file does not exist.
    ///
    /// A missing file is not an error here: G1's Sidecar naming row creates a packet when
    /// none exists, and C3's `XMPCodec.write` receives `nil` for that case.
    func read(_ url: URL) throws -> Data?

    /// Returns the file's size, date and permissions, or `nil` when it does not exist.
    ///
    /// Used for G1's conflict check before the replacement and for the sidecar's POSIX
    /// permissions, which the replacement must keep.
    func attributes(of url: URL) throws -> MarkFileAttributes?

    /// Creates `url` and any missing parents, doing nothing when it already exists.
    ///
    /// Clove's own storage lives below Application Support, so the first write may need to
    /// create its directory (G1 decision 5).
    func createDirectory(_ url: URL) throws

    /// Creates the staging file with exactly `data`, failing if it already exists.
    ///
    /// The staging file lives in the destination's folder so the following `rename` stays on
    /// one volume; its name is hidden, so a scan never lists it (G1 Safe writes).
    func writeStaging(_ data: Data, to url: URL) throws

    /// Flushes the staging file to the file system before the replacement (G1 Safe writes).
    func synchronize(_ url: URL) throws

    /// Replaces `destination` with `staging` using POSIX `rename`, keeping no other file.
    ///
    /// G1's Safe writes row selects POSIX `rename` for the replacement, so the destination's
    /// spelling and folder never change and a reader either sees the old packet or the new
    /// one. The caller keeps the permissions separately.
    func replace(_ destination: URL, withItemAt staging: URL) throws

    /// Applies the destination's previous POSIX permissions after the replacement.
    ///
    /// G1's Safe writes row notes that `rename` installs the staging file's own inode, so a
    /// write that did not re-apply the old mode would silently change the sidecar's access.
    func setPermissions(_ permissions: UInt16, of url: URL) throws

    /// Removes `url`, treating an already absent file as success.
    ///
    /// Every mark-write failure path removes its own staging file; C6's confirmed move calls
    /// this through the store to drop a Reject (G1 decision 5).
    func remove(_ url: URL) throws
}

/// Production file operations: Foundation reads and checks, POSIX staged replacement.
///
/// G1's Safe writes row runs on local APFS at launch and defers external media to #29, so
/// this implementation uses `Data(contentsOf:)` and `attributesOfItem`, then writes the
/// staging file with `Data.write`, flushes it through `FileHandle.synchronize`, and replaces
/// the destination with `rename(2)`. It imports `Darwin` for the POSIX calls on both macOS
/// and iOS; nothing here is private API.
public struct FoundationMarkWriteFileSystem: MarkWriteFileSystem {
    /// Creates the production file system; it holds no state and can be shared.
    public init() {}

    /// Reads the file, mapping "not found" to `nil` (G1 Sidecar naming creates a packet).
    public func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            if isMissingFileError(error) { return nil }
            throw error
        }
    }

    /// Reads size, modification date and permissions, mapping "not found" to `nil`.
    public func attributes(of url: URL) throws -> MarkFileAttributes? {
        do {
            let values = try FileManager.default.attributesOfItem(atPath: url.path)
            return MarkFileAttributes(
                size: (values[.size] as? NSNumber)?.intValue ?? 0,
                modificationDate: values[.modificationDate] as? Date ?? .distantPast,
                permissions: (values[.posixPermissions] as? NSNumber)?.uint16Value ?? 0)
        } catch {
            if isMissingFileError(error) { return nil }
            throw error
        }
    }

    /// Creates the directory and any missing parents (Clove's Application Support storage).
    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Creates the staging file, refusing to overwrite one that already exists.
    public func writeStaging(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
    }

    /// Flushes the staging file with `fsync` through `FileHandle.synchronize`.
    public func synchronize(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// Replaces the destination with `rename(2)` so the swap stays on one volume.
    public func replace(_ destination: URL, withItemAt staging: URL) throws {
        let status = rename(staging.path, destination.path)
        guard status == 0 else { throw POSIXError(posixErrorCode()) }
    }

    /// Applies the previous permission bits with `chmod(2)` after the replacement.
    public func setPermissions(_ permissions: UInt16, of url: URL) throws {
        guard chmod(url.path, mode_t(permissions)) == 0 else {
            throw POSIXError(posixErrorCode())
        }
    }

    /// Removes the file, treating an absent file as success.
    public func remove(_ url: URL) throws {
        guard unlink(url.path) != 0 else { return }
        let code = errno
        guard code != ENOENT else { return }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    /// The current `errno` as a `POSIXErrorCode`, or `EIO` when the value is unknown.
    private func posixErrorCode() -> POSIXErrorCode {
        POSIXErrorCode(rawValue: errno) ?? .EIO
    }
}

/// Whether an error chain means the file is simply not there, per S1's failure table.
///
/// S1 records `NSCocoaErrorDomain` 4 and 260, and `NSPOSIXErrorDomain` 2 (`ENOENT`), for a
/// deleted or unavailable location. A mark write treats those as "no packet yet" on read,
/// and as the location-unavailable reason on every later step.
func isMissingFileError(_ error: any Error) -> Bool {
    var current: NSError? = error as NSError
    // A malformed chain must not loop; real ones are two or three levels deep.
    var depth = 0
    while let level = current, depth < 16 {
        if level.domain == NSPOSIXErrorDomain, level.code == Int(ENOENT) { return true }
        if level.domain == NSCocoaErrorDomain,
            level.code == NSFileNoSuchFileError || level.code == NSFileReadNoSuchFileError
        {
            return true
        }
        current = level.userInfo[NSUnderlyingErrorKey] as? NSError
        depth += 1
    }
    return false
}
