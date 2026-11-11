/// What one photo's part of an undo or redo produced (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// The three outcomes the plan asks for are read off one value:
///
/// - **Written**: ``status`` holds C4's completed write result.
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

    /// Whether this photo went through C4.
    public var isWritten: Bool { status != nil }

    /// Whether the photo already held every value the step would restore, so nothing was written.
    public var isAlreadyAtTarget: Bool { status == nil && leftAlone.isEmpty }

    /// Whether nothing was written because every field kept a newer value (PRD P0-05).
    public var isNotUndone: Bool { status == nil && !leftAlone.isEmpty }

    /// Whether the photo now holds a value this step restored (PRD P0-05).
    ///
    /// A confirmed write reached its target, and a field already at the target needed none. A
    /// failed write did not, which is why it is not counted here.
    public var reachedTarget: Bool {
        status?.state.isConfirmed == true || !alreadyAtTarget.isEmpty
    }

    /// The fields this photo kept as they were, in report order (PRD P0-05).
    public var leftAloneFields: [MarkUndoField] { leftAlone.map(\.field) }
}

/// What one undo or redo produced, per photo and for the view (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// Each step reports per-photo outcomes and the photo to return to. ``actionName`` is the
/// short undo menu title.
public struct MarkUndoResult: Hashable, Sendable {
    /// A short action name for the undo menu title (the UI owns the final copy).
    public let actionName: String
    /// Where the view returns after this step (PRD Undo row).
    public let photoToReturnTo: PhotoIdentity
    /// One outcome per photo in the entry, in the entry's order.
    public let outcomes: [MarkUndoPhotoOutcome]
    /// Whether the step removed its entry from the history because it restored nothing.
    ///
    /// Every field kept a newer mark or its photo was unavailable. The entry is on neither
    /// stack, so the next undo reaches an older action (PRD P0-05's last-in, first-out undo).
    public let droppedFromHistory: Bool

    /// Describes the result of one step; the history builds these.
    init(
        actionName: String,
        photoToReturnTo: PhotoIdentity,
        outcomes: [MarkUndoPhotoOutcome],
        droppedFromHistory: Bool
    ) {
        self.actionName = actionName
        self.photoToReturnTo = photoToReturnTo
        self.outcomes = outcomes
        self.droppedFromHistory = droppedFromHistory
    }

    /// Photos whose restore failed through C4.
    public var failedCount: Int {
        outcomes.filter { $0.status?.state.failure != nil }.count
    }

    /// Photos that already held the restored value, so nothing was written (PRD P0-05).
    public var skippedCount: Int { outcomes.filter(\.isAlreadyAtTarget).count }

    /// Photos no field could be restored for, because newer marks won (PRD P0-05).
    public var notUndoneCount: Int { outcomes.filter(\.isNotUndone).count }

}
