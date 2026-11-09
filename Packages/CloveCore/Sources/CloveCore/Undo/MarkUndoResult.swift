/// What one photo's part of an undo or redo produced (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// The three outcomes the plan asks for are read off one value:
///
/// - **Written**: ``status`` holds C4's final state, so the UI can show PRD P0-08's save state
///   and offer the queue's retry.
/// - **Skipped, already at the target**: nothing was written because the photo already held the
///   value the step would restore (``alreadyAtTarget``).
/// - **Not undone**: at least one field kept its newer value, with the field and reason in
///   ``leftAlone`` (PRD P0-05: undo restores the previous mark and never overwrites a newer one).
///
/// A photo can both write some fields and leave others alone when another app changed only one
/// of them, so the value keeps both parts instead of choosing one outcome.
public struct MarkUndoPhotoOutcome: Hashable, Sendable {
    /// The photo this outcome belongs to (C1's stable identity).
    public let photo: PhotoIdentity
    /// C4's final status when a write restored at least one field, otherwise `nil`.
    public let status: MarkChangeStatus?
    /// The fields a newer value replaced, with the reason each kept its newer value (PRD P0-05).
    public let leftAlone: [MarkUndoLeftAloneField]
    /// The fields already at the target value, which needed no write (PRD P0-05).
    public let alreadyAtTarget: [MarkUndoField]

    /// Describes one photo's part of a step; the history builds these.
    init(
        photo: PhotoIdentity,
        status: MarkChangeStatus?,
        leftAlone: [MarkUndoLeftAloneField],
        alreadyAtTarget: [MarkUndoField]
    ) {
        self.photo = photo
        self.status = status
        self.leftAlone = leftAlone
        self.alreadyAtTarget = alreadyAtTarget
    }

    /// Whether this photo went through C4, with its status for PRD P0-08's save state.
    public var isWritten: Bool { status != nil }

    /// Whether the photo already held every value the step would restore, so nothing was written.
    public var isAlreadyAtTarget: Bool { status == nil && leftAlone.isEmpty }

    /// Whether nothing was written because every field kept a newer value (PRD P0-05).
    public var isNotUndone: Bool { status == nil && !leftAlone.isEmpty }

    /// The fields this photo kept as they were, in report order (PRD P0-05).
    public var leftAloneFields: [MarkUndoField] { leftAlone.map(\.field) }
}

/// The completion record one finishing-action step changed (PRD P0-12; DEV-PLAN C5).
///
/// PRD P0-12's group completion has two sources: the group's marks and the finishing action the
/// user ran. Undoing the action removes the session record through C10's
/// ``GroupCompletionTracker``, and redoing it puts the record back; a group can still be complete
/// by its marks either way.
public struct MarkUndoCompletionUpdate: Hashable, Sendable {
    /// Whether the step cleared the record or restored it (PRD P0-12).
    public enum State: Hashable, Sendable {
        /// Undo removed the session's finishing-action record for the group.
        case cleared
        /// Redo restored the session's finishing-action record for the group.
        case restored
    }

    /// The group the finishing action ran on (PRD P0-12).
    public let groupID: GroupID
    /// What the step did to the group's completion record (PRD P0-12).
    public let state: State

    /// Describes the completion change one step made.
    init(groupID: GroupID, state: State) {
        self.groupID = groupID
        self.state = state
    }
}

/// What one undo or redo produced, per photo and for the view (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// The plan's C5 row asks every step to report per-photo outcomes, the batch counts behind
/// "Saved N photos. M photos couldn't be saved." (PRD Failure and recovery, partial batch
/// failure), the photo to return to, and — for a finishing action — the group whose completion
/// changed. ``actionName`` is the short menu title; the final user-facing copy belongs to U8.
///
/// A confirmed restore counts as saved here even when the marks live in Clove storage rather
/// than XMP, matching C10's ``GroupFinishingResult``: a Reject undo restores a stored reject
/// (G1 decision 5), and reporting "Saved 0 photos" for a successful undo would misstate it.
/// PRD P0-08 keeps the word **Saved** for XMP writes, so U8 decides the copy it shows.
public struct MarkUndoResult: Hashable, Sendable {
    /// A short action name for the undo menu title (the UI owns the final copy).
    public let actionName: String
    /// Where the view returns after this step (PRD Undo row).
    public let photoToReturnTo: PhotoIdentity
    /// One outcome per photo in the entry, in the entry's order.
    public let outcomes: [MarkUndoPhotoOutcome]
    /// The group whose completion changed, for a finishing-action step (PRD P0-12).
    public let completion: MarkUndoCompletionUpdate?

    /// Describes the result of one step; the history builds these.
    init(
        actionName: String,
        photoToReturnTo: PhotoIdentity,
        outcomes: [MarkUndoPhotoOutcome],
        completion: MarkUndoCompletionUpdate?
    ) {
        self.actionName = actionName
        self.photoToReturnTo = photoToReturnTo
        self.outcomes = outcomes
        self.completion = completion
    }

    /// Photos whose restore C4 confirmed in the storage the marks use (PRD P0-08).
    public var savedCount: Int {
        outcomes.filter { $0.status?.state.isConfirmed == true }.count
    }

    /// Photos whose restore still needs a retry through C4 (PRD P0-09).
    public var failedCount: Int {
        outcomes.filter { $0.status?.state.isUnfinished == true }.count
    }

    /// Photos that already held the restored value, so nothing was written (PRD P0-05).
    public var skippedCount: Int { outcomes.filter(\.isAlreadyAtTarget).count }

    /// Photos no field could be restored for, because newer marks won (PRD P0-05).
    public var notUndoneCount: Int { outcomes.filter(\.isNotUndone).count }

    /// The PRD's "Partial batch failure" wording, or `nil` when no restore needs a retry.
    ///
    /// This follows the PRD's "Saved N photos. M photos couldn't be saved." copy; the exact
    /// strings stay U8's decision (PRD Failure and recovery).
    public var partialFailureSummary: String? {
        guard failedCount > 0 else { return nil }
        return "Saved \(savedCount) photos. \(failedCount) photos couldn't be saved."
    }
}
