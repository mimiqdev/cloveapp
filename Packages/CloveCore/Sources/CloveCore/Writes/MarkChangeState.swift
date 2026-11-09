import Foundation

/// The save state of one requested change, named after the storage that confirmed it.
///
/// PRD P0-08 requires the state to reflect the storage used: "Saved" belongs to XMP writes
/// that read back, "Saved in Clove only" to standalone JPEG/HIF marks confirmed in Clove, and
/// a Reject that is merely stored is neither of those until the move confirms (G1 decisions
/// 5–6). The cases are deliberately separate so a UI cannot show Clove-stored Reject or an
/// unconfirmed write as **Saved**.
public enum MarkChangeState: Hashable, Sendable {
    /// The request is admitted and waiting for its write (PRD P0-08's "Writing…" period).
    case pending
    /// The write is running; nothing is confirmed yet (PRD P0-08).
    case writing
    /// The sidecar read back as the requested marks: PRD P0-08's **Saved**.
    case savedInSidecar
    /// A standalone JPEG/HIF mark was confirmed in Clove storage: PRD P0-08's
    /// **Saved in Clove only** (G1 decision 6).
    case savedInCloveOnly
    /// Reject was confirmed in Clove storage (G1 decision 5). This is not **Saved**: that
    /// word belongs to XMP writes and to a confirmed move, so U7 shows it as stored only.
    case storedInClove
    /// The change is not confirmed; the requested marks stay for a retry (PRD disk rule 8).
    case failed(MarkWriteFailure)
    /// A newer change to the same photo replaced this one; retrying it does nothing
    /// (PRD How marks reach disk, rule 8).
    case superseded(by: MarkChangeID)

    /// Whether no further work will change this state.
    public var isFinished: Bool {
        switch self {
        case .pending, .writing: false
        case .savedInSidecar, .savedInCloveOnly, .storedInClove, .failed, .superseded: true
        }
    }

    /// Whether the write is still running or waiting (PRD P0-08).
    public var isInProgress: Bool {
        switch self {
        case .pending, .writing: true
        default: false
        }
    }

    /// Whether the change needs attention: failed, or still not confirmed.
    ///
    /// U7's "Some marks haven't finished saving" covers every admitted change that is not
    /// confirmed yet, and a failed change stays in that list until it is retried or
    /// superseded (PRD Failure and recovery, last row).
    public var isUnfinished: Bool {
        switch self {
        case .pending, .writing, .failed: true
        default: false
        }
    }

    /// Whether the change reached its storage and was confirmed there (PRD P0-08).
    ///
    /// This includes Reject stored in Clove, which is confirmed but is not **Saved**.
    public var isConfirmed: Bool {
        switch self {
        case .savedInSidecar, .savedInCloveOnly, .storedInClove: true
        default: false
        }
    }

    /// Whether the state may be shown as **Saved** or **Saved in Clove only** (PRD P0-08).
    ///
    /// A Clove-stored Reject is confirmed but is not Saved, and a failed or superseded change
    /// never appears saved.
    public var isSaved: Bool {
        switch self {
        case .savedInSidecar, .savedInCloveOnly: true
        default: false
        }
    }

    /// Whether a newer change replaced this one (PRD disk rule 8).
    public var isSuperseded: Bool {
        if case .superseded = self { return true }
        return false
    }

    /// The failure, when the change could not be confirmed (PRD P0-08).
    public var failure: MarkWriteFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

/// One admitted change with the marks it requested and its current save state.
///
/// PRD P0-08 keeps the requested marks after a failure so the user can retry, and P0-09 needs
/// per-photo batch results. The request is kept exactly as it was admitted, so a retry sends
/// the same fields; a newer change to the same photo supersedes it instead (PRD disk rule 8).
public struct MarkChangeStatus: Hashable, Sendable, Identifiable {
    /// The change's handle for retry and state queries.
    public let id: MarkChangeID
    /// The photo set the change belongs to (C1's stable identity).
    public let identity: PhotoIdentity
    /// The fields the request named, kept for a retry after failure (PRD disk rule 8).
    public let requested: MarkChange
    /// The current save state (PRD P0-08).
    public let state: MarkChangeState

    /// Describes one change at one point in time.
    public init(
        id: MarkChangeID, identity: PhotoIdentity, requested: MarkChange, state: MarkChangeState
    ) {
        self.id = id
        self.identity = identity
        self.requested = requested
        self.state = state
    }

    /// A copy with a new state, used when the queue publishes a transition.
    func withState(_ state: MarkChangeState) -> MarkChangeStatus {
        MarkChangeStatus(id: id, identity: identity, requested: requested, state: state)
    }
}

/// A stable handle for one batch of changes applied to many photo sets.
///
/// PRD P0-09 requires the batch to report per-photo results and to retry only its failed
/// items, so the queue keeps the batch's change identifiers under this handle.
public struct MarkBatchID: Hashable, Sendable, CustomStringConvertible {
    /// The underlying identifier; a new value per batch application.
    public let rawValue: UUID

    /// Creates a fresh identifier for an applied batch.
    public init() { self.rawValue = UUID() }

    /// A stable, log-friendly spelling.
    public var description: String { rawValue.uuidString }
}

/// What one batch produced, with the per-photo results and P0-09's counts.
///
/// PRD P0-09 and the PRD's "Partial batch failure" row require "Saved N photos. M photos
/// couldn't be saved." and a retry that applies to the failed items only. ``outcomes`` keeps
/// the order the caller supplied; the counts below count each state once.
public struct MarkBatchResult: Hashable, Sendable {
    /// The batch's handle for ``MarkWriteQueue/retryFailed(in:)``.
    public let id: MarkBatchID
    /// The change every photo set received.
    public let change: MarkChange
    /// One result per requested photo set, in the caller's order.
    public let outcomes: [MarkChangeStatus]

    /// Describes one applied batch (PRD P0-09).
    public init(id: MarkBatchID, change: MarkChange, outcomes: [MarkChangeStatus]) {
        self.id = id
        self.change = change
        self.outcomes = outcomes
    }

    /// Results that reached their storage and read back (PRD P0-08).
    public var confirmed: [MarkChangeStatus] { outcomes.filter { $0.state.isConfirmed } }

    /// Results that may be shown as **Saved** or **Saved in Clove only** (PRD P0-08).
    public var saved: [MarkChangeStatus] { outcomes.filter { $0.state.isSaved } }

    /// Results that still need a retry (PRD P0-09).
    public var failed: [MarkChangeStatus] { outcomes.filter { $0.state.isUnfinished } }

    /// Results a newer change replaced (PRD disk rule 8).
    public var superseded: [MarkChangeStatus] { outcomes.filter { $0.state.isSuperseded } }

    /// PRD P0-09's "Saved N photos": confirmed in the storage the marks use.
    public var confirmedCount: Int { confirmed.count }

    /// PRD P0-09's "Saved N photos", counting only the states that show as saved.
    public var savedCount: Int { saved.count }

    /// PRD P0-09's "M photos couldn't be saved": failed or still writing.
    public var failedCount: Int { failed.count }

    /// Results a newer change replaced, which a retry leaves alone (PRD disk rule 8).
    public var supersededCount: Int { superseded.count }

    /// A ready-to-show partial-batch summary, or `nil` for a fully confirmed batch.
    ///
    /// The wording follows the PRD's proposed "Saved N photos. M photos couldn't be saved."
    /// copy; the exact strings stay U7's decision. The count uses ``savedCount`` so a batch of
    /// Rejects, which is confirmed in Clove but never "Saved", reports no saved photos.
    public var partialFailureSummary: String? {
        guard failedCount > 0 else { return nil }
        return "Saved \(savedCount) photos. \(failedCount) photos couldn't be saved."
    }
}
