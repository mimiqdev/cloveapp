import Foundation

/// Why the codec refused a packet instead of reading or editing it.
///
/// G1's XMP codec row asks for a validated, preserving editor that refuses malformed or
/// ambiguous packets rather than repairing them, and PRD P0-08 forbids reporting an
/// unconfirmed change as saved. Each case below names one refusal so C4 can keep the
/// requested marks for a retry and explain the problem without guessing at the XML.
public enum XMPCodecError: Error, Hashable, Sendable {
    /// The sidecar exists but has no bytes. Clove refuses rather than replacing a file it
    /// cannot inspect; a new packet is only created when no sidecar exists at all.
    case emptyPacket

    /// The packet is larger than `XMPCodec.maximumPacketSize`.
    case packetTooLarge(limit: Int, byteCount: Int)

    /// The bytes are not UTF-8, or an XML declaration names another encoding.
    /// PRD P0-07 sidecars are read as UTF-8 only.
    case unsupportedEncoding

    /// The packet declares a document type. Refused before parsing, so an entity-expansion
    /// attack never reaches the XML parser (G1 XMP codec row, refusal policy).
    case documentTypeDeclaration

    /// The packet declares an entity. Clove edits sidecars, never DTD content.
    case entityDeclaration

    /// The packet is not well-formed XML, or uses markup Clove does not accept.
    case malformedXML(String)

    /// The packet has no `rdf:Description`; there is nothing to read or edit.
    case missingDescription

    /// Several top-level descriptions exist and none holds an owned mark, so there is no
    /// provable place for a new mark. Read returns unmarked for this shape.
    case ambiguousDescriptions

    /// The mark's description names another resource through a non-empty `rdf:about`,
    /// `rdf:nodeID` or `rdf:ID`, so a write cannot prove the mark belongs to this file.
    /// Read still returns the marks it finds.
    case qualifiedDescription

    /// Owned marks appear in more than one top-level `rdf:Description`, so which one
    /// belongs to this file is ambiguous (G1 XMP codec row, refusal policy).
    case marksInSeveralDescriptions

    /// One description holds the same owned property twice, in attribute and element form
    /// or as two elements.
    case duplicateMark(XMPProperty)

    /// An owned property sits somewhere other than a mark on a description, for example
    /// nested inside another app's structured property.
    case misplacedMark(XMPProperty)

    /// An owned mark carries a qualifier, a resource reference, a datatype or child
    /// elements, so a range edit cannot be proven safe (S3 hardening list).
    case qualifiedMark(XMPProperty)

    /// `xmp:Rating` is not an integer, so it is neither an in-range nor an external rating.
    case invalidRating(String)

    /// XML 1.0 cannot carry this text, so no byte-preserving write can represent it.
    case unsupportedLabelText

    /// The written packet did not read back as the requested marks; no bytes are returned.
    case writeVerificationFailed
}

extension XMPCodecError: CustomStringConvertible {
    /// A developer-facing explanation; product copy belongs to the save-state UI.
    public var description: String {
        switch self {
        case .emptyPacket:
            return "The XMP sidecar is empty."
        case .packetTooLarge(let limit, let byteCount):
            return "The XMP packet is \(byteCount) bytes; the limit is \(limit)."
        case .unsupportedEncoding:
            return "The XMP packet is not UTF-8."
        case .documentTypeDeclaration:
            return "The XMP packet declares a document type."
        case .entityDeclaration:
            return "The XMP packet declares an entity."
        case .malformedXML(let reason):
            return "The XMP packet is not well-formed XML: \(reason)"
        case .missingDescription:
            return "The XMP packet has no rdf:Description."
        case .ambiguousDescriptions:
            return "The XMP packet has several descriptions and no provable place for a mark."
        case .qualifiedDescription:
            return "The XMP description names another resource."
        case .marksInSeveralDescriptions:
            return "The XMP packet has marks in several descriptions."
        case .duplicateMark(let property):
            return "The XMP packet holds \(property.localName) twice."
        case .misplacedMark(let property):
            return "The XMP packet holds \(property.localName) outside a description."
        case .qualifiedMark(let property):
            return "The XMP packet holds a qualified or structured \(property.localName)."
        case .invalidRating(let text):
            return "The XMP rating \(text.debugDescription) is not an integer."
        case .unsupportedLabelText:
            return "The label contains a character XML 1.0 cannot carry."
        case .writeVerificationFailed:
            return "The edited XMP packet did not read back as requested."
        }
    }
}
