import Foundation

/// A stable handle for one completed Move rejects run and its Undo.
public struct RejectMoveBatchID: Hashable, Sendable, CustomStringConvertible {
    /// The underlying identifier; a new value per run.
    public let rawValue: UUID

    /// Creates a fresh identifier for one run.
    public init() { self.rawValue = UUID() }

    /// A stable, log-friendly spelling.
    public var description: String { rawValue.uuidString }
}

/// Where one file of a split set actually is (PRD P0-10).
///
/// A set that could not be moved back keeps every file's actual location, including a file the
/// move lane could no longer find. The value never guesses: a file that is at neither URL is
/// reported as ``Location/missing`` instead of being assumed to be somewhere.
public struct RejectMoveFileLocation: Hashable, Sendable {
    /// Where a file of a split set ended up (PRD P0-10).
    public enum Location: String, CaseIterable, Hashable, Sendable {
        /// The file is back where the set came from.
        case source
        /// The file is under the rejects folder.
        case destination
        /// Both URLs were checked and neither holds the file, so the move lost it (PRD P0-10).
        case missing
        /// The file system could not answer for either URL, so no location is claimed.
        ///
        /// A broken check is not evidence that a file is gone, so the result says it could not
        /// be confirmed instead of reporting the file as missing (PRD P0-10).
        case unknown
    }

    /// The file's part in the set (G1 decision 5).
    public let role: RejectMoveFileRole
    /// Where the file was (PRD P0-10).
    public let source: URL
    /// Where the move was taking it (PRD P0-10).
    public let destination: URL
    /// The URL that holds the file now, or `nil` when neither does (PRD P0-10).
    public let location: Location

    /// Describes one file's actual location (PRD P0-10).
    public init(
        role: RejectMoveFileRole, source: URL, destination: URL, location: Location
    ) {
        self.role = role
        self.source = source
        self.destination = destination
        self.location = location
    }

    /// The URL that holds the file now, or `nil` when no location is confirmed (PRD P0-10).
    public var url: URL? {
        switch location {
        case .source: source
        case .destination: destination
        case .missing, .unknown: nil
        }
    }
}

/// One photo set that moved as a unit, with its new URLs (PRD P0-10).
///
/// G1 decision 5 makes the confirmed move the durable Reject result, so the caller drops this
/// set from the grid and lets a later scan skip the rejects folder. The stored Reject record is
/// removed after the move; a record that could not be removed stays a diagnostic and never
/// makes the set count as unmoved (PRD P0-08).
public struct RejectMoveMovedSet: Hashable, Sendable {
    /// C1's stable identity of the set, for dropping it from the grid (PRD P0-10).
    public let identity: PhotoIdentity
    /// Every file with its source and its confirmed destination (PRD P0-10).
    public let files: [RejectMoveFilePlan]
    /// Whether a stored Reject was cleared and confirmed after the move (PRD P0-08).
    public let removedStoredReject: Bool
    /// A stored Reject that could not be removed, kept for a later cleanup (PRD P0-08).
    public let staleRejectRecord: RejectMoveFailure?

    /// Describes one confirmed set (PRD P0-10).
    public init(
        identity: PhotoIdentity, files: [RejectMoveFilePlan], removedStoredReject: Bool,
        staleRejectRecord: RejectMoveFailure?
    ) {
        self.identity = identity
        self.files = files
        self.removedStoredReject = removedStoredReject
        self.staleRejectRecord = staleRejectRecord
    }
}

/// One photo set that stayed entirely in place, with its failure (PRD P0-10).
///
/// Every file is back at its source; the failure retains the reason the set did not move.
public struct RejectMoveFailedSet: Hashable, Sendable {
    /// C1's stable identity of the set (G1 decision 5).
    public let identity: PhotoIdentity
    /// Why the set did not move, with its `NSError` chain (PRD P0-10).
    public let failure: RejectMoveFailure
    /// The files as they are, all at their sources (PRD P0-10).
    public let files: [RejectMoveFilePlan]

    /// Describes one set that stayed in place (PRD P0-10).
    public init(identity: PhotoIdentity, failure: RejectMoveFailure, files: [RejectMoveFilePlan]) {
        self.identity = identity
        self.failure = failure
        self.files = files
    }
}

/// One photo set that is partly in both places because the move back also failed (PRD P0-10).
///
/// PRD P0-10 never loses track of a file: this outcome lists every file's actual location, and
/// a file that could not be found at either URL is reported as missing rather than assumed.
public struct RejectMoveSplitSet: Hashable, Sendable {
    /// C1's stable identity of the set (G1 decision 5).
    public let identity: PhotoIdentity
    /// Why the set was being moved back (PRD P0-10).
    public let failure: RejectMoveFailure
    /// Every error the move back hit, so the user sees why the set split (PRD P0-10).
    public let rollbackFailures: [RejectMoveFailure]
    /// Every file's actual location (PRD P0-10).
    public let files: [RejectMoveFileLocation]

    /// Describes one set left in both places (PRD P0-10).
    public init(
        identity: PhotoIdentity, failure: RejectMoveFailure,
        rollbackFailures: [RejectMoveFailure], files: [RejectMoveFileLocation]
    ) {
        self.identity = identity
        self.failure = failure
        self.rollbackFailures = rollbackFailures
        self.files = files
    }
}

/// One photo set that was deliberately not attempted, with the condition to resolve first.
///
/// A skipped set's files stay where they were.
public struct RejectMoveSkippedSet: Hashable, Sendable {
    /// C1's stable identity of the set (G1 decision 5).
    public let identity: PhotoIdentity
    /// Why the set was left alone (PRD P0-10).
    public let reason: RejectMoveSkipReason
    /// A short developer-facing explanation; product copy belongs to the UI.
    public let message: String

    /// Describes one set that was not attempted (PRD P0-10).
    public init(identity: PhotoIdentity, reason: RejectMoveSkipReason, message: String) {
        self.identity = identity
        self.reason = reason
        self.message = message
    }
}

/// One requested set's result (PRD P0-10).
public enum RejectMoveOutcome: Hashable, Sendable, Identifiable {
    /// Every file of the set is under the rejects folder and confirmed (G1 decision 5).
    case moved(RejectMoveMovedSet)
    /// The set is untouched because its move failed and every earlier file moved back.
    case failed(RejectMoveFailedSet)
    /// The set is in both places because the move back failed too (PRD P0-10).
    case split(RejectMoveSplitSet)
    /// The set was not attempted, with the condition that has to change first (PRD P0-10).
    case skipped(RejectMoveSkippedSet)

    /// The set's stable identity, whatever the result (G1 decision 5).
    public var identity: PhotoIdentity {
        switch self {
        case .moved(let set): set.identity
        case .failed(let set): set.identity
        case .split(let set): set.identity
        case .skipped(let set): set.identity
        }
    }

    /// The id the grid and the result list key on (G1 decision 5).
    public var id: PhotoIdentity { identity }
}

/// What one Move rejects run produced, with one outcome per requested set in caller order.
/// ``movedIdentities`` tells the grid which sets to drop; failed and split sets remain in Details.
public struct RejectMoveResult: Hashable, Sendable {
    /// The run's handle for Undo.
    public let id: RejectMoveBatchID
    /// One outcome per requested set, in the caller's order (PRD P0-10).
    public let outcomes: [RejectMoveOutcome]
    public let planDifference: RejectMovePlanDifference?

    /// Describes confirmed outcomes and any change from the confirmation preview.
    public init(
        id: RejectMoveBatchID, outcomes: [RejectMoveOutcome],
        planDifference: RejectMovePlanDifference? = nil
    ) {
        self.id = id
        self.outcomes = outcomes
        self.planDifference = planDifference
    }

    /// Sets whose every file is confirmed under the rejects folder (G1 decision 5).
    public var moved: [RejectMoveMovedSet] {
        outcomes.compactMap { outcome in
            guard case .moved(let set) = outcome else { return nil }
            return set
        }
    }

    /// Sets that failed and are entirely back in place.
    public var failed: [RejectMoveFailedSet] {
        outcomes.compactMap { outcome in
            guard case .failed(let set) = outcome else { return nil }
            return set
        }
    }

    /// Sets that are in both places because the move back failed (PRD P0-10).
    public var split: [RejectMoveSplitSet] {
        outcomes.compactMap { outcome in
            guard case .split(let set) = outcome else { return nil }
            return set
        }
    }

    /// Sets that were not attempted, with the condition to resolve first (PRD P0-10).
    public var skipped: [RejectMoveSkippedSet] {
        outcomes.compactMap { outcome in
            guard case .skipped(let set) = outcome else { return nil }
            return set
        }
    }

    /// PRD P0-10's "Moved N photos".
    public var movedCount: Int { moved.count }

    /// Sets that failed and are entirely back in place.
    public var failedCount: Int { failed.count }

    /// Sets left in both places.
    public var splitCount: Int { split.count }

    /// Sets not attempted.
    public var skippedCount: Int { skipped.count }

    /// PRD P0-10's "M photos couldn't be moved": failed and split sets, never skipped ones.
    public var unmovedCount: Int { failedCount + splitCount }

    /// The identities the grid drops after a confirmed run (PRD P0-10).
    public var movedIdentities: [PhotoIdentity] { moved.map(\.identity) }

}

/// One observable step of a Move rejects run (PRD P0-10).
///
/// PRD P0-10 asks for progress during a run, and U10 shows a per-photo list. The stream yields
/// each set as it starts and finishes, then the run's result, so a UI can show movement without
/// polling. Cancellation only stops the run between sets, so no set is left half-reported.
public enum RejectMoveProgress: Hashable, Sendable {
    /// A set's files are about to be renamed (PRD P0-10).
    case setStarted(PhotoIdentity)
    /// A set reached its final outcome (PRD P0-10).
    case setFinished(RejectMoveOutcome)
    /// The run ended; every requested set has an outcome (PRD P0-10).
    case finished(RejectMoveResult)
}
