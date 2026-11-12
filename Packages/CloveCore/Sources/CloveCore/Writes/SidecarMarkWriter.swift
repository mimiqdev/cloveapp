import Foundation

/// The result of one staged sidecar replacement.
public struct SidecarWriteResult: Hashable, Sendable {
    /// The sidecar the change targeted, with the spelling discovery resolved (G1 naming).
    public let destination: URL
    /// Why the replacement failed, or nil on success.
    public let failure: MarkWriteFailure?
    /// How many read-modify-write attempts ran: one normally, two after one external change.
    public let attemptCount: Int

    /// Creates the outcome of one sidecar write.
    public init(destination: URL, failure: MarkWriteFailure?, attemptCount: Int) {
        self.destination = destination
        self.failure = failure
        self.attemptCount = attemptCount
    }

    /// Whether the staged replacement succeeded.
    public var isSaved: Bool { failure == nil }
}

/// Applies XMP edits to one sidecar at a time, with G1's staged, confirmed replacement.
///
/// G1's Safe writes row fixes the sequence for one write: read the current packet (or nothing
/// when no sidecar exists), apply the edit through C3's codec, write a hidden staging file in
/// the same folder, synchronize it, POSIX `rename` it over the destination keeping the
/// destination's spelling. The staging file is removed on every failure path, and the
/// previous packet stays in place until the `rename`. The old
/// sidecar's POSIX permissions are applied to the staging file before it replaces the
/// destination, so a permission failure cannot report a change as failed after installing it.
///
/// The writer is an actor so all writes to one sidecar are serialized (PRD How marks reach
/// disk, rule 3; G1 Sidecar naming). Each write's read-modify-write runs without suspension
/// inside the actor, so two concurrent requests cannot lose one another's field.
public actor SidecarMarkWriter {
    // A complete read-modify-write stays serialized, including when file I/O blocks.
    private nonisolated let queue = DispatchSerialQueue(label: "Clove.SidecarMarkWriter")
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// The injectable file seam, so tests can fail any step (G1 Safe writes).
    private let fileSystem: any MarkWriteFileSystem
    /// The production codec; pure and shareable (PRD P0-07).
    private let codec: XMPCodec

    /// Creates a writer over a file system and codec, both replaceable in tests.
    public init(
        fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        codec: XMPCodec = XMPCodec()
    ) {
        self.fileSystem = fileSystem
        self.codec = codec
    }

    /// Applies `edit` to the sidecar at `destination` and confirms the result.
    ///
    /// G1's Safe writes row runs one read-modify-write. If the destination's size or
    /// modification date changed between the read and the `rename`, the attempt runs again
    /// from a fresh read; a second change is reported as ``MarkWriteFailureReason/conflict``
    /// instead of overwriting another app's newer packet. A codec refusal writes nothing and
    /// keeps the codec error. On every failure the staging file is removed, and the previous
    /// packet stays on disk unless the `rename` had already happened.
    ///
    /// - Parameters:
    ///   - edit: The rating and/or label change; fields left `.keep` keep their bytes.
    ///   - destination: The sidecar URL with its actual spelling (G1 Sidecar naming).
    /// - Returns: Whether the replacement succeeded.
    public func write(_ edit: XMPEdit, to destination: URL) -> SidecarWriteResult {
        var attempt = 1
        while true {
            switch attemptOnce(edit, to: destination) {
            case .saved:
                return SidecarWriteResult(
                    destination: destination, failure: nil, attemptCount: attempt)
            case .changed:
                if attempt == 2 {
                    return SidecarWriteResult(
                        destination: destination,
                        failure: MarkWriteFailure(
                            reason: .conflict,
                            message:
                                "The sidecar changed twice while Clove was writing it; nothing was overwritten."
                        ),
                        attemptCount: attempt)
                }
                attempt += 1
            case .failed(let failure):
                return SidecarWriteResult(
                    destination: destination, failure: failure, attemptCount: attempt)
            }
        }
    }

    /// The result of one read-modify-write attempt.
    private enum AttemptResult {
        /// The replacement succeeded.
        case saved
        /// The destination changed after Clove read it; start again from a fresh read once.
        case changed
        /// The attempt failed; nothing was confirmed.
        case failed(MarkWriteFailure)
    }

    /// Reads for merging, then stages and replaces the packet.
    private func attemptOnce(_ edit: XMPEdit, to destination: URL) -> AttemptResult {
        let staging = Self.stagingURL(for: destination)
        var replaced = false
        // Every exit path before the replacement leaves no staging file behind (G1 Safe writes).
        defer { if !replaced { try? fileSystem.remove(staging) } }
        do {
            let before = try fileSystem.attributes(of: destination)
            let packet: Data?
            do {
                packet = try fileSystem.read(destination)
            } catch {
                throw MarkWriteFailure(classifying: error)
            }

            let edited: Data
            do {
                edited = try codec.write(edit, into: packet)
            } catch let error as XMPCodecError {
                throw MarkWriteFailure(
                    reason: .packetRefused, message: error.description, codecError: error)
            } catch {
                throw MarkWriteFailure(classifying: error)
            }

            try fileSystem.writeStaging(edited, to: staging)

            // `rename` installs the staging file's inode, so the old sidecar's permissions
            // are applied to the staging file before it replaces the destination. The
            // destination is never chmod-ed: a failure here leaves it untouched (G1 Safe
            // writes).
            if let permissions = before?.permissions {
                try fileSystem.setPermissions(permissions, of: staging)
            }
            try fileSystem.synchronize(staging)

            // G1's conflict check runs immediately before the replacement, not after it, so
            // another app's newer packet is never overwritten blindly.
            let now = try fileSystem.attributes(of: destination)
            if before?.stamp != now?.stamp { return .changed }

            try fileSystem.replace(destination, withItemAt: staging)
            replaced = true

            return .saved
        } catch let failure as MarkWriteFailure {
            return .failed(failure)
        } catch {
            return .failed(MarkWriteFailure(classifying: error))
        }
    }

    /// A hidden sibling name for the staging file.
    ///
    /// The staging file must share the destination's folder so `rename` stays on one volume,
    /// and its leading dot means the scanner's hidden-file rule skips it (G1 Safe writes,
    /// scan approach). A unique suffix keeps two attempts from sharing a name.
    static func stagingURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".clove-staging-\(UUID().uuidString)")
    }
}
