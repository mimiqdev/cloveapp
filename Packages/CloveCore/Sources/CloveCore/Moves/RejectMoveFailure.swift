import Foundation

/// Why one photo set did not move, named after the situation U7 has copy for.
///
/// PRD P0-10 requires a failed set to keep its reason and its full `NSError` chain, and PRD
/// Failure and recovery keeps read-only storage, insufficient space and a lost location apart.
/// The cases reuse C4's classification for everything it already maps and add only what a
/// move can hit beyond a mark write:
///
/// - ``differentVolume`` for `EXDEV`. PRD P0-10 makes the move same-volume only and forbids a
///   copy followed by a delete, so this is a failure rather than a fallback.
/// - ``conflict`` for an exclusive rename that found the destination already present, which is
///   the race PRD P0-10's "never overwrite" rule must survive.
/// - ``ambiguousSidecar`` for a set whose packet choice C2 could not resolve; the set is never
///   moved and no candidate is picked (G1 Sidecar naming).
/// - ``outsideOpenedFolder`` and ``insideRejectsFolder`` for a set that must not be touched at
///   all, so no file leaves the opened folder or is moved into it twice.
public enum RejectMoveFailureReason: String, CaseIterable, Hashable, Sendable {
    /// The folder or file can no longer be written: `EACCES` or `EPERM` (S1's failure table).
    case permissionLost
    /// The volume is mounted or protected read-only: `EROFS` (PRD P0-10).
    case readOnlyStorage
    /// The volume is full: `ENOSPC` (PRD Failure and recovery).
    case insufficientSpace
    /// The file or its folder disappeared: `ENOENT` (S1's failure table).
    case locationUnavailable
    /// The source and destination are on different volumes: `EXDEV` (PRD P0-10).
    case differentVolume
    /// A destination name was already taken when the exclusive rename ran (PRD P0-10).
    case conflict
    /// The rename ran but the per-file confirmation did not match (PRD P0-10, P0-08).
    case notConfirmed
    /// C2 found more than one candidate packet, so no file of the set moves (G1 Sidecar naming).
    case ambiguousSidecar
    /// The set's files are not inside the opened folder, so the move would leave its scope.
    case outsideOpenedFolder
    /// Anything else, kept with its exact error chain instead of a guessed cause (S1).
    case unknown

    /// Maps a reason C4 already classifies into the move's vocabulary.
    ///
    /// G1 decision 5's move reuses C4's failure classification rather than writing a second
    /// one; only `EXDEV`, `EEXIST`, an unconfirmed move and the move's own refusals are decided
    /// here. A codec refusal cannot arise from a move and stays ``unknown``.
    init(_ reason: MarkWriteFailureReason) {
        switch reason {
        case .permissionLost: self = .permissionLost
        case .readOnlyStorage: self = .readOnlyStorage
        case .insufficientSpace: self = .insufficientSpace
        case .locationUnavailable: self = .locationUnavailable
        case .conflict: self = .conflict
        case .notConfirmed: self = .notConfirmed
        case .ambiguousSidecar: self = .ambiguousSidecar
        case .packetRefused, .unknown: self = .unknown
        }
    }
}

/// One failed set's reason, message and `NSError` chain (PRD P0-10, P0-08).
///
/// PRD P0-08 forbids reporting an unconfirmed move as successful and PRD Failure and recovery
/// keeps the failure visible for a retry, so the set keeps every diagnostic: the reason the UI
/// chooses copy from, a short developer-facing message, and C4's flattened error chain.
public struct RejectMoveFailure: Error, Hashable, Sendable, CustomStringConvertible {
    /// The situation U7 has copy for (PRD P0-10).
    public let reason: RejectMoveFailureReason
    /// A short developer-facing explanation; product copy belongs to the result UI.
    public let message: String
    /// The error and every underlying error, outermost first (S1 failure snapshot).
    public let errorChain: [MarkWriteErrorEntry]

    /// Describes a failure the move already knows, such as a mismatched confirmation.
    public init(
        reason: RejectMoveFailureReason, message: String,
        errorChain: [MarkWriteErrorEntry] = []
    ) {
        self.reason = reason
        self.message = message
        self.errorChain = errorChain
    }

    /// Classifies a thrown error through C4's mapper, adding the move's own two codes.
    ///
    /// `EXDEV` and `EEXIST` are checked first because C4's table has no entry for them and
    /// `unknown` would hide the two situations PRD P0-10 names. Everything else is C4's
    /// ``MarkWriteFailure`` reason, so both lanes report one vocabulary (G1 decision 5).
    public init(classifying error: any Error) {
        let chain = MarkWriteErrorEntry.chain(of: error)
        self.errorChain = chain
        self.message = chain.first?.message ?? "The photo set couldn't be moved."
        if chain.contains(NSPOSIXErrorDomain, Int(EXDEV)) {
            self.reason = .differentVolume
        } else if chain.contains(NSPOSIXErrorDomain, Int(EEXIST))
            || chain.contains(NSCocoaErrorDomain, NSFileWriteFileExistsError)
        {
            self.reason = .conflict
        } else {
            self.reason = RejectMoveFailureReason(MarkWriteFailure(classifying: error).reason)
        }
    }

    /// A one-line diagnostic for logs, matching S1's requirement to retain the exact error.
    public var description: String { "\(reason.rawValue): \(message)" }
}

/// Why a requested photo set was left in place without being attempted (PRD P0-10).
///
/// A skipped set is not a failed move: PRD P0-10 and "Failure and recovery" retry only failed
/// items, so a skip names the condition the user has to resolve and leaves every file where it
/// was.
public enum RejectMoveSkipReason: String, CaseIterable, Hashable, Sendable {
    /// The set already sits inside the rejects folder, so moving it again would nest the
    /// rejects folder inside itself (PRD P0-10).
    case insideRejectsFolder
}

extension Array where Element == MarkWriteErrorEntry {
    /// Whether any level of the chain carries `code` in `domain`.
    fileprivate func contains(_ domain: String, _ code: Int) -> Bool {
        contains { $0.domain == domain && $0.code == code }
    }
}
