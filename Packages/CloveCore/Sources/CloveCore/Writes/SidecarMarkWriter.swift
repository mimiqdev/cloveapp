import Foundation

/// The confirmed result of one sidecar write.
///
/// G1's Safe writes row makes the destination read-after-write the only proof: the change is
/// saved when this value carries no failure, and ``attemptCount`` records whether the
/// destination changed once before the replacement. PRD P0-08 forbids reporting a change as
/// saved on anything less.
public struct SidecarWriteResult: Hashable, Sendable {
    /// The sidecar the change targeted, with the spelling discovery resolved (G1 naming).
    public let destination: URL
    /// Why the write is not confirmed, or `nil` when the read-back matched the request.
    public let failure: MarkWriteFailure?
    /// How many read-modify-write attempts ran: one normally, two after one external change.
    public let attemptCount: Int

    /// Creates the outcome of one sidecar write.
    public init(destination: URL, failure: MarkWriteFailure?, attemptCount: Int) {
        self.destination = destination
        self.failure = failure
        self.attemptCount = attemptCount
    }

    /// Whether the destination read back as the requested marks (PRD P0-08's "Saved").
    public var isSaved: Bool { failure == nil }
}

/// Applies XMP edits to one sidecar at a time, with G1's staged, confirmed replacement.
///
/// G1's Safe writes row fixes the sequence for one write: read the current packet (or nothing
/// when no sidecar exists), apply the edit through C3's codec, write a hidden staging file in
/// the same folder, synchronize it, POSIX `rename` it over the destination keeping the
/// destination's spelling, then read the destination back and decode it. Only a read-back
/// that equals the requested marks is saved (PRD P0-08). The staging file is removed on every
/// failure path, and the previous packet stays in place until the `rename`.
///
/// The writer is an actor so all writes to one sidecar are serialized (PRD How marks reach
/// disk, rule 3; G1 Sidecar naming). Each write's read-modify-write runs without suspension
/// inside the actor, so two concurrent requests cannot lose one another's field.
public actor SidecarMarkWriter {
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
    /// - Returns: The confirmed outcome; ``SidecarWriteResult/isSaved`` is true only when the
    ///   destination read back as the requested marks (PRD P0-08).
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
        /// The destination read back as the requested marks.
        case saved
        /// The destination changed after Clove read it; start again from a fresh read once.
        case changed
        /// The attempt failed; nothing was confirmed.
        case failed(MarkWriteFailure)
    }

    /// Runs one staged replacement and the read-back G1's Safe writes row requires.
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
            try fileSystem.synchronize(staging)

            // G1's conflict check runs immediately before the replacement, not after it, so
            // another app's newer packet is never overwritten blindly.
            let now = try fileSystem.attributes(of: destination)
            if before?.stamp != now?.stamp { return .changed }

            try fileSystem.replace(destination, withItemAt: staging)
            replaced = true

            // `rename` installs the staging file's inode, so the old sidecar's permissions
            // are re-applied (G1 Safe writes).
            if let permissions = before?.permissions {
                try fileSystem.setPermissions(permissions, of: destination)
            }

            let readBack: Data?
            do {
                readBack = try fileSystem.read(destination)
            } catch {
                throw MarkWriteFailure(classifying: error)
            }
            guard let readBack else {
                throw MarkWriteFailure(
                    reason: .unknown,
                    message: "The sidecar disappeared after Clove replaced it.")
            }
            let marks: XMPMarks
            do {
                marks = try codec.read(readBack)
            } catch let error as XMPCodecError {
                throw MarkWriteFailure(
                    reason: .unknown,
                    message: "The written sidecar did not read back as an XMP packet.",
                    codecError: error)
            } catch {
                throw MarkWriteFailure(classifying: error)
            }
            guard Self.matches(edit, marks) else {
                throw MarkWriteFailure(
                    reason: .unknown,
                    message: "The sidecar did not read back as the requested marks.")
            }
            return .saved
        } catch let failure as MarkWriteFailure {
            return .failed(failure)
        } catch {
            return .failed(MarkWriteFailure(classifying: error))
        }
    }

    /// Whether the marks read back from the destination equal the fields the edit set.
    ///
    /// PRD P0-08 asks for the requested change, not the whole packet: a rating-only edit is
    /// confirmed by the rating, and an untouched label keeps whatever another app wrote.
    static func matches(_ edit: XMPEdit, _ marks: XMPMarks) -> Bool {
        if case .set(let rating) = edit.rating, marks.rating != .rated(rating) { return false }
        if case .set(let label) = edit.label {
            if label.isClear {
                if !marks.label.isClear { return false }
            } else if marks.label != label {
                return false
            }
        }
        return true
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
