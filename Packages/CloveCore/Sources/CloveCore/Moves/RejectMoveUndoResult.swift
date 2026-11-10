import Foundation

/// A stable handle for one undo attempt, so its failed photos can be retried.
///
/// PRD P0-10's Undo rule and PRD "Failure and recovery" keep the restored photos restored and
/// retry only the ones that did not come back, so an undo's result has to stay addressable after
/// the toast has shown its counts.
public struct RejectMoveUndoBatchID: Hashable, Sendable, CustomStringConvertible {
    /// The underlying identifier; a new value per undo attempt.
    public let rawValue: UUID

    /// Creates a fresh identifier for one undo attempt.
    public init() { self.rawValue = UUID() }

    /// A stable, log-friendly spelling.
    public var description: String { rawValue.uuidString }
}

/// Why an undo request was refused before any file was touched (PRD P0-10's Undo rule).
///
/// PRD P0-10 undoes a completed move once and PRD Move rejects leaves restoring moves outside
/// the undo history to the user, so a handle the mover does not hold, or one it already
/// restored, touches nothing. A read-only location is refused as a whole request, like the move
/// itself, so the UI shows one message instead of a failure per photo (PRD "Failure and
/// recovery").
public enum RejectMoveUndoRefusal: Error, Hashable, Sendable, CustomStringConvertible {
    /// The run is not in memory, for example after the folder was closed or the app relaunched.
    ///
    /// PRD Move rejects: restoring moves outside the undo history is not in launch scope, so the
    /// user moves those files back.
    case unknownBatch(RejectMoveBatchID)
    /// The run was already undone; PRD P0-10's Undo applies to a completed move once.
    case alreadyUndone(RejectMoveBatchID)
    /// The opened location reports itself read-only (PRD "Failure and recovery").
    case readOnlyLocation(RejectMoveFailure)

    /// A developer-facing explanation; product copy belongs to the result UI.
    public var description: String {
        switch self {
        case .unknownBatch(let batch):
            "The move \(batch) is no longer available to undo."
        case .alreadyUndone(let batch):
            "The move \(batch) was already undone."
        case .readOnlyLocation(let failure):
            failure.description
        }
    }
}

/// One photo set that is back at its original path, with Reject stored again.
///
/// PRD P0-10's Undo rule moves a completed move's files back and restores Reject on them, and
/// PRD Move rejects' "Keeping before the move" adds the photos the user kept in the
/// confirmation. A kept photo never moved, so ``keptInConfirmation`` is `true` and ``files`` is
/// empty: only its Reject was cleared, and only its Reject comes back.
public struct RejectMoveUndoRestoredPhoto: Hashable, Sendable, Identifiable {
    /// C1's stable identity, which the grid uses to put the photo back (PRD P0-10).
    public let identity: PhotoIdentity
    /// C1's set as it was scanned before the move, so the grid can show the photo again without
    /// a rescan (PRD P0-10's Undo rule).
    public let set: ScannedPhotoSet
    /// Every file and its original path, or empty for a kept photo (PRD P0-10).
    public let files: [RejectMoveFilePlan]
    /// Whether the confirmation kept the photo, so only its Reject was restored (PRD Move rejects).
    public let keptInConfirmation: Bool
    /// C4's failure when the stored Reject could not be written again, or `nil` when it was.
    ///
    /// G1 decision 5 keeps a stale Clove record as a diagnostic, and PRD P0-08 keeps an
    /// unconfirmed change from counting as saved. The files are back either way, so this never
    /// turns a confirmed move back into a failure (PRD P0-10's Undo rule).
    public let rejectStoreFailure: RejectMoveFailure?

    /// Whether Clove stores Reject for the photo again (G1 decision 5).
    public var isRejectStored: Bool { rejectStoreFailure == nil }

    /// The photo's id for a SwiftUI list (PRD P0-10).
    public var id: PhotoIdentity { identity }

    /// Describes one restored photo (PRD P0-10).
    public init(
        identity: PhotoIdentity,
        set: ScannedPhotoSet,
        files: [RejectMoveFilePlan],
        keptInConfirmation: Bool,
        rejectStoreFailure: RejectMoveFailure?
    ) {
        self.identity = identity
        self.set = set
        self.files = files
        self.keptInConfirmation = keptInConfirmation
        self.rejectStoreFailure = rejectStoreFailure
    }
}

/// One photo set left under the rejects folder because an original path is taken.
///
/// PRD P0-10's Undo rule never overwrites a file that now occupies an original path: the set
/// stays in the rejects folder, both files are left exactly as they were, and the taken paths
/// are reported so the UI can name the conflict.
public struct RejectMoveUndoConflict: Hashable, Sendable, Identifiable {
    /// C1's stable identity of the set that stayed (PRD P0-10).
    public let identity: PhotoIdentity
    /// The set's files, all still together under the rejects folder (PRD P0-10).
    public let files: [RejectMoveFilePlan]
    /// The original paths that are now taken, so the UI can name what blocks the undo.
    public let takenPaths: [URL]
    /// Why the set stayed: ``RejectMoveFailureReason/conflict`` (PRD P0-10).
    public let failure: RejectMoveFailure

    /// The set's id for a SwiftUI list (PRD P0-10).
    public var id: PhotoIdentity { identity }

    /// Describes one set that a taken original path kept in the rejects folder (PRD P0-10).
    public init(
        identity: PhotoIdentity,
        files: [RejectMoveFilePlan],
        takenPaths: [URL],
        failure: RejectMoveFailure
    ) {
        self.identity = identity
        self.files = files
        self.takenPaths = takenPaths
        self.failure = failure
    }
}

/// One photo set that is still entirely under the rejects folder, with the reason.
///
/// PRD P0-10 keeps a photo set a unit: an undo that cannot finish rolls its files back into the
/// rejects folder, so this set is exactly as the move left it and a retry can address it again
/// (PRD "Failure and recovery": retry only the failed items).
public struct RejectMoveUndoFailedPhoto: Hashable, Sendable, Identifiable {
    /// C1's stable identity of the set (PRD P0-10).
    public let identity: PhotoIdentity
    /// Why the set did not come back, with its `NSError` chain (PRD P0-10).
    public let failure: RejectMoveFailure
    /// The set's files as the move planned them, all still under the rejects folder (PRD P0-10).
    public let files: [RejectMoveFilePlan]

    /// The set's id for a SwiftUI list (PRD P0-10).
    public var id: PhotoIdentity { identity }

    /// Describes one set that stayed under the rejects folder (PRD P0-10).
    public init(
        identity: PhotoIdentity, failure: RejectMoveFailure, files: [RejectMoveFilePlan]
    ) {
        self.identity = identity
        self.failure = failure
        self.files = files
    }
}

/// One photo set that is partly back and partly under the rejects folder (PRD P0-10).
///
/// PRD P0-10 never loses track of a file: when the rollback into the rejects folder also fails,
/// the set reports every file's actual location, and a file found at neither URL is reported as
/// missing instead of assumed to be somewhere.
public struct RejectMoveUndoSplitPhoto: Hashable, Sendable, Identifiable {
    /// C1's stable identity of the set (PRD P0-10).
    public let identity: PhotoIdentity
    /// Why the set was coming back (PRD P0-10).
    public let failure: RejectMoveFailure
    /// Every error the rollback into the rejects folder hit (PRD P0-10).
    public let rollbackFailures: [RejectMoveFailure]
    /// Every file's actual location (PRD P0-10).
    public let files: [RejectMoveFileLocation]

    /// The set's id for a SwiftUI list (PRD P0-10).
    public var id: PhotoIdentity { identity }

    /// Describes one set left in both places (PRD P0-10).
    public init(
        identity: PhotoIdentity,
        failure: RejectMoveFailure,
        rollbackFailures: [RejectMoveFailure],
        files: [RejectMoveFileLocation]
    ) {
        self.identity = identity
        self.failure = failure
        self.rollbackFailures = rollbackFailures
        self.files = files
    }
}

/// One photo's result after undoing a Move rejects run (PRD P0-10's Undo rule).
public enum RejectMoveUndoOutcome: Hashable, Sendable, Identifiable {
    /// The photo is back at its original path, or was kept and never moved, with Reject stored.
    case restored(RejectMoveUndoRestoredPhoto)
    /// The photo's original path is taken, so the set stays under the rejects folder untouched.
    case conflict(RejectMoveUndoConflict)
    /// The photo is still under the rejects folder because the move back failed.
    case failed(RejectMoveUndoFailedPhoto)
    /// The photo is in both places because the rollback into the rejects folder failed too.
    case split(RejectMoveUndoSplitPhoto)

    /// The photo's stable identity, whatever the result (G1 decision 5).
    public var identity: PhotoIdentity {
        switch self {
        case .restored(let photo): photo.identity
        case .conflict(let photo): photo.identity
        case .failed(let photo): photo.identity
        case .split(let photo): photo.identity
        }
    }

    /// The id the grid and the result list key on (G1 decision 5).
    public var id: PhotoIdentity { identity }
}

/// What one undo attempt produced, with the per-photo counts and retry inputs (PRD P0-10).
///
/// PRD P0-10's Undo rule restores a completed move as one step, and PRD "Failure and recovery"
/// keeps the photos that came back where they are and retries only the ones that did not. The
/// result keeps one outcome per requested photo in the caller's order: ``restoredIdentities``
/// tells the grid which photos to show again, ``failed`` tells the toast's Details list which
/// photos a retry can still send, and a conflict or a split set is reported apart because a
/// blind retry would overwrite or duplicate a file.
public struct RejectMoveUndoResult: Hashable, Sendable {
    /// The attempt's handle for ``RejectMover/retryFailedUndo(in:)`` (PRD P0-10).
    public let id: RejectMoveUndoBatchID
    /// One outcome per requested photo, in the caller's order (PRD P0-10).
    public let outcomes: [RejectMoveUndoOutcome]

    /// Describes one undo attempt's outcomes (PRD P0-10).
    public init(id: RejectMoveUndoBatchID, outcomes: [RejectMoveUndoOutcome]) {
        self.id = id
        self.outcomes = outcomes
    }

    /// Photos that are back at their original path with Reject stored (PRD P0-10).
    public var restored: [RejectMoveUndoRestoredPhoto] {
        outcomes.compactMap { outcome in
            guard case .restored(let photo) = outcome else { return nil }
            return photo
        }
    }

    /// Photos the confirmation kept, restored with Reject (PRD Move rejects).
    public var kept: [RejectMoveUndoRestoredPhoto] { restored.filter(\.keptInConfirmation) }

    /// Photos whose original path is taken, left under the rejects folder (PRD P0-10).
    public var conflicts: [RejectMoveUndoConflict] {
        outcomes.compactMap { outcome in
            guard case .conflict(let photo) = outcome else { return nil }
            return photo
        }
    }

    /// Photos that are still entirely under the rejects folder (PRD P0-10).
    public var failed: [RejectMoveUndoFailedPhoto] {
        outcomes.compactMap { outcome in
            guard case .failed(let photo) = outcome else { return nil }
            return photo
        }
    }

    /// Photos that are in both places because the rollback failed (PRD P0-10).
    public var split: [RejectMoveUndoSplitPhoto] {
        outcomes.compactMap { outcome in
            guard case .split(let photo) = outcome else { return nil }
            return photo
        }
    }

    /// PRD P0-10's "Restored N photos".
    public var restoredCount: Int { restored.count }

    /// How many restored photos the confirmation had kept (PRD Move rejects).
    public var keptCount: Int { kept.count }

    /// Photos a taken original path kept under the rejects folder (PRD P0-10).
    public var conflictCount: Int { conflicts.count }

    /// Photos a retry can send again: failed, never a conflict or a split (PRD P0-10).
    public var failedCount: Int { failed.count }

    /// Photos left in both places; a retry never resends these (PRD P0-10).
    public var splitCount: Int { split.count }

    /// PRD P0-10's "M photos couldn't be restored": conflicts, failures and split photos.
    public var unrestoredCount: Int { conflictCount + failedCount + splitCount }

    /// Every photo the grid shows again, in the caller's order (PRD P0-10's Undo rule).
    public var restoredIdentities: [PhotoIdentity] { restored.map(\.identity) }

    /// Whether every requested photo is back and every Reject is stored (PRD P0-10).
    public var isComplete: Bool { unrestoredCount == 0 && restored.allSatisfy(\.isRejectStored) }

    /// PRD P0-10's "Restored N photos. M photos couldn't be restored.", or `nil` when all came
    /// back.
    ///
    /// The wording follows the PRD's proposed "Partial Move rejects failure" sentence with the
    /// undo's verb; the exact strings stay U8's decision. A photo whose files came back while
    /// its Reject could not be stored is not counted as unrestored, because its files are where
    /// they belong and the stale mark is a diagnostic (G1 decision 5).
    public var partialFailureSummary: String? {
        guard unrestoredCount > 0 else { return nil }
        return "Restored \(restoredCount) photos. \(unrestoredCount) photos couldn't be restored."
    }
}

/// One observable step of an undo attempt (PRD P0-10's Undo rule).
///
/// PRD P0-10 asks for progress during a move, and an undo renames the same files and stores a
/// Reject for every photo, so a run of hundreds takes as long as the move did. The stream yields
/// each photo as it starts and finishes, then the attempt's result, so the toast can show
/// movement without polling; a retry of failed photos publishes its own sequence.
public enum RejectMoveUndoProgress: Hashable, Sendable {
    /// A photo's files are about to be renamed back (PRD P0-10's Undo rule).
    case photoStarted(PhotoIdentity)
    /// A photo reached its final outcome (PRD P0-10's Undo rule).
    case photoFinished(RejectMoveUndoOutcome)
    /// The attempt ended; every requested photo has an outcome (PRD P0-10's Undo rule).
    case finished(RejectMoveUndoResult)
}
