import Foundation

/// Why a change did not reach its storage, in the situations U7 has copy for.
///
/// A failed write retains its reason, and PRD Failure and recovery
/// keeps read-only storage and insufficient space apart. The cases follow S1's
/// "Failure table and proposed PRD mapping": the mapping never infers a full or read-only
/// location from a generic failed write, so everything unrecognised stays ``unknown``.
///
/// G1's Safe writes row adds ``conflict`` for a destination that changed twice while Clove
/// was writing it, and PRD How marks reach disk, rules 3 and 7, add ``packetRefused`` for a
/// codec refusal and ``ambiguousSidecar`` for a stem with more than one candidate packet.
/// PRD P0-08's read-back gate adds ``notConfirmed`` for a write that ran but could not be
/// confirmed: a mismatched read-back, a read-back that is not a valid packet, or a sidecar
/// that vanished after the replacement. That is a known situation, not ``unknown``.
public enum MarkWriteFailureReason: String, CaseIterable, Hashable, Sendable {
    /// The folder or file can no longer be written: `EACCES`, `EPERM`, Cocoa 257 or 513.
    /// S1 maps this to "Lost folder permission" (PRD P0-02, P0-08).
    case permissionLost
    /// The location is mounted or protected read-only: `EROFS` or Cocoa 642.
    /// PRD Failure and recovery keeps this separate from insufficient space.
    case readOnlyStorage
    /// The location is full: `ENOSPC` or Cocoa 640 (PRD Failure and recovery).
    case insufficientSpace
    /// The file or its folder disappeared: `ENOENT`, Cocoa 4 or 260 (S1's table).
    case locationUnavailable
    /// The XMP codec refused the packet, so no bytes were written (PRD P0-07, G1 XMP codec).
    case packetRefused
    /// C2 found more than one candidate packet, so Clove refuses to pick one or add a second
    /// (G1 Sidecar naming; PRD How marks reach disk, rule 3).
    case ambiguousSidecar
    /// The write ran but its result could not be confirmed, so it is not saved
    /// (PRD P0-08): the read-back mismatched, was not a valid packet, or the sidecar
    /// disappeared after the replacement.
    case notConfirmed
    /// The destination changed after Clove read it, twice in a row (G1 Safe writes).
    case conflict
    /// Anything else, kept with its exact error chain instead of a guessed cause (S1).
    case unknown

    /// Maps an `NSError` chain to one of the situations U7 shows, innermost evidence first.
    /// ``notConfirmed`` is set by the write itself, never derived from an error chain.
    ///
    /// S1's table records the outer Cocoa code with a POSIX `errno` underneath. The deepest
    /// recognised code wins, so Cocoa 513 wrapping `EROFS` reports read-only storage rather
    /// than a generic permission loss. A generic write error such as Cocoa 512 maps to
    /// ``unknown``; the classifier never infers read-only or full storage from it.
    static func classify(_ chain: [MarkWriteErrorEntry]) -> MarkWriteFailureReason {
        var posixMatch: MarkWriteFailureReason?
        var cocoaMatch: MarkWriteFailureReason?
        for entry in chain {
            switch entry.domain {
            case NSPOSIXErrorDomain:
                if let reason = posixReasons[entry.code] { posixMatch = reason }
            case NSCocoaErrorDomain:
                if let reason = cocoaReasons[entry.code] { cocoaMatch = reason }
            default:
                continue
            }
        }
        return posixMatch ?? cocoaMatch ?? .unknown
    }

    /// The `errno` values S1's table names, and nothing beyond them.
    private static let posixReasons: [Int: MarkWriteFailureReason] = [
        Int(EROFS): .readOnlyStorage,
        Int(ENOSPC): .insufficientSpace,
        Int(EACCES): .permissionLost,
        Int(EPERM): .permissionLost,
        Int(ENOENT): .locationUnavailable,
    ]

    /// The Cocoa codes S1's table names, so a chain without a POSIX level still classifies.
    private static let cocoaReasons: [Int: MarkWriteFailureReason] = [
        NSFileReadNoPermissionError: .permissionLost,
        NSFileWriteNoPermissionError: .permissionLost,
        NSFileWriteVolumeReadOnlyError: .readOnlyStorage,
        NSFileWriteOutOfSpaceError: .insufficientSpace,
        NSFileNoSuchFileError: .locationUnavailable,
        NSFileReadNoSuchFileError: .locationUnavailable,
    ]
}

/// One level of an `NSError` chain, kept so a failed change explains itself.
///
/// S1's snapshot keeps domain, numeric code and description for each level, and U7 shows a
/// technical diagnostic next to the product copy. This type is the write lane's copy of that
/// shape, independent of C2's scan issues.
public struct MarkWriteErrorEntry: Hashable, Sendable {
    /// The error domain, for example `NSCocoaErrorDomain` or `NSPOSIXErrorDomain`.
    public let domain: String
    /// The numeric code within its domain.
    public let code: Int
    /// The localized description the system supplied.
    public let message: String

    /// Describes one level of an `NSError` chain (S1 failure snapshot).
    public init(domain: String, code: Int, message: String) {
        self.domain = domain
        self.code = code
        self.message = message
    }

    /// Flattens an error with each `NSUnderlyingErrorKey` and `NSMultipleUnderlyingErrorsKey`.
    ///
    /// The walk is bounded so a malformed chain cannot loop; S1 bounds it at eight levels and
    /// real chains are two or three deep.
    public static func chain(of error: any Error) -> [MarkWriteErrorEntry] {
        var entries: [MarkWriteErrorEntry] = []
        func append(_ level: NSError, depth: Int) {
            guard depth < 16 else { return }
            entries.append(
                MarkWriteErrorEntry(
                    domain: level.domain, code: level.code,
                    message: level.localizedDescription))
            if let underlying = level.userInfo[NSUnderlyingErrorKey] as? NSError {
                append(underlying, depth: depth + 1)
            }
            if let multiple = level.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                for item in multiple { append(item, depth: depth + 1) }
            }
        }
        append(error as NSError, depth: 0)
        return entries
    }
}

/// Why one requested change is not saved, with every diagnostic the write kept.
///
/// The requested marks stay on the completed result (``MarkChangeStatus/requested``);
/// this value explains the failure. It keeps the codec or store error as a typed field so a
/// later UI can choose copy without parsing text, and the full `NSError` chain so S1's
/// diagnostic survives the write (S1 failure snapshot).
public struct MarkWriteFailure: Error, Hashable, Sendable, CustomStringConvertible {
    /// The situation U7 has copy for, or ``MarkWriteFailureReason/unknown`` (PRD P0-08).
    public let reason: MarkWriteFailureReason
    /// A short developer-facing explanation; product copy belongs to the save-state UI.
    public let message: String
    /// The error and every underlying error, outermost first (S1 failure snapshot).
    public let errorChain: [MarkWriteErrorEntry]
    /// The codec's own refusal, kept when ``reason`` is `packetRefused` (PRD P0-07).
    public let codecError: XMPCodecError?
    /// Clove storage's own refusal, kept when the stored marks could not be read or written
    /// (G1 decision 6).
    public let storeError: CloveMarkStoreError?

    /// Describes a failure the write already classified, for example an ambiguous sidecar.
    public init(
        reason: MarkWriteFailureReason,
        message: String,
        errorChain: [MarkWriteErrorEntry] = [],
        codecError: XMPCodecError? = nil,
        storeError: CloveMarkStoreError? = nil
    ) {
        self.reason = reason
        self.message = message
        self.errorChain = errorChain
        self.codecError = codecError
        self.storeError = storeError
    }

    /// Classifies an error from its `NSError` chain, following S1's failure table.
    ///
    /// A codec refusal keeps its typed error and reports `packetRefused`; a Clove-storage
    /// error keeps its typed error. Everything else is mapped by ``MarkWriteFailureReason``.
    public init(classifying error: any Error) {
        let chain = MarkWriteErrorEntry.chain(of: error)
        self.errorChain = chain
        self.message = chain.first?.message ?? "The change could not be saved."
        if let codec = error as? XMPCodecError {
            self.reason = .packetRefused
            self.codecError = codec
            self.storeError = nil
        } else if let store = error as? CloveMarkStoreError {
            // A store read-back that does not match is the same unconfirmed save as a
            // sidecar mismatch (PRD P0-08); damaged storage stays unknown.
            switch store {
            case .corruptStorage, .differentFolderIdentities: self.reason = .unknown
            }
            self.codecError = nil
            self.storeError = store
        } else {
            self.reason = MarkWriteFailureReason.classify(chain)
            self.codecError = nil
            self.storeError = nil
        }
    }

    /// A one-line diagnostic for logs, matching S1's requirement to retain the exact error.
    public var description: String {
        "\(reason.rawValue): \(message)"
    }
}
