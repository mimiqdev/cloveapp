import Foundation

/// The production XMP codec for ratings and colour labels.
///
/// G1's XMP codec row selects a validated, preserving editor: it changes only the fields
/// Clove owns, keeps every other byte another app wrote, and refuses malformed or ambiguous
/// packets instead of repairing them. PRD P0-07 limits the fields to the star rating and
/// the colour label, so Reject and any Clove namespace never reach XMP (G1 decision 5).
///
/// The codec is pure: it takes packet bytes, or `nil` when no sidecar exists yet, and
/// returns marks or new bytes. Staging, renaming, read-back and the write queue belong to
/// C4, and sidecar discovery belongs to C1/C2.
public struct XMPCodec: Sendable {
    /// The largest packet the codec will read or edit: 4 MiB.
    ///
    /// A sidecar is metadata, not image data. The committed fixtures are under 4 KB and a
    /// Lightroom history block is the only part that grows in practice, so 4 MiB leaves a
    /// wide margin while still refusing a file that would make every scan pay for it.
    public static let maximumPacketSize = 4 * 1024 * 1024

    /// Creates the stateless codec; it can be shared across tasks (Swift 6 concurrency).
    public init() {}

    /// Reads the rating and colour label from `packet`.
    ///
    /// - Parameter packet: The sidecar bytes, or `nil` when no sidecar exists yet.
    /// - Returns: The marks, unmarked when `packet` is `nil` or has no owned properties.
    /// - Throws: `XMPCodecError` for each refusal case; `emptyPacket` when a present
    ///   sidecar has no bytes, so C4 can keep the requested marks for a retry.
    ///
    /// Reading can succeed where writing refuses: a packet with several descriptions and
    /// no marks, or one whose description names another resource, reads its marks but has
    /// no provable place for a new one (PRD P0-07).
    public func read(_ packet: Data?) throws -> XMPMarks {
        guard let packet else { return .unmarked }
        return try XMPPacket(packet).read()
    }

    /// Applies `edit` to `packet` and returns the new bytes.
    ///
    /// Only the value bytes of the requested rating and/or label change; prefixes,
    /// whitespace, comments, CDATA, other namespaces, develop settings and history are
    /// kept byte for byte (PRD P0-07; How marks reach disk, rule 9). A label set to
    /// `.clear` loses its property; rating zero is written as `xmp:Rating="0"`, which other
    /// software reads as unrated, so clearing the rating is an explicit value and not a
    /// missing field.
    ///
    /// - Parameters:
    ///   - edit: The changes to make. Fields left `.keep` are not touched.
    ///   - packet: The sidecar bytes, or `nil` to create a minimal wrapped packet.
    /// - Returns: The edited packet, after reading the requested marks back from it.
    /// - Throws: `XMPCodecError` for each refusal case. No bytes are returned on failure,
    ///   so the previous packet is always the one on disk.
    public func write(_ edit: XMPEdit, into packet: Data?) throws -> Data {
        guard let packet else { return try Self.newPacket(for: edit) }
        return try XMPPacket(packet).applying(edit)
    }
}
