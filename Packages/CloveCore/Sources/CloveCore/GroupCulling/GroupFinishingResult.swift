/// One photo's outcome from an executed finishing action (PRD In-group culling, finishing
/// actions; PRD P0-09's per-photo results).
public struct GroupFinishingOutcome: Hashable, Sendable {
    /// The change that was requested, with the marks read just before it (DEV-PLAN C5).
    public let change: GroupFinishingChange

    /// C4's save state for the change (PRD P0-08).
    public let status: MarkChangeStatus

    /// The photo the outcome belongs to (C1's stable identity).
    public var photo: PhotoIdentity { change.photo }
}

/// What one executed finishing action produced, per photo and for C5 (PRD P0-12, P0-09).
///
/// The result keeps the plan that ran, one outcome per requested change in plan order, the
/// photos dropped because their marks no longer allowed the change. ``savedCount`` and ``failedCount`` follow the PRD's batch rules
/// ("Partial batch failure": "Saved N photos. M photos couldn't be saved."), and the undo
/// record carries the marks from before the action (DEV-PLAN C5).
///
/// A finishing action's rejects are the rating −1, written to each set's own storage (G1
/// decisions 2 and 6), so a confirmed reject counts as saved here the way any other rating does.
/// ``failedCount`` counts only changes that still need a retry (PRD P0-09).
public struct GroupFinishingResult: Hashable, Sendable {
    /// The plan that ran (PRD In-group culling, finishing actions).
    public let plan: GroupFinishingPlan

    /// One outcome per requested change, the current photo's keep change first (PRD P0-09).
    public let outcomes: [GroupFinishingOutcome]

    /// Photos whose planned change was not requested, because their marks changed after the
    /// plan was built or their photo set was not supplied (PRD P0-12).
    public let droppedPhotos: [PhotoIdentity]

    /// The record C5 undoes from (PRD P0-12; DEV-PLAN C5).
    public let undo: GroupFinishingUndo

    /// Builds the result of an ordered finishing action.
    init(
        plan: GroupFinishingPlan,
        outcomes: [GroupFinishingOutcome],
        droppedPhotos: [PhotoIdentity],
        undo: GroupFinishingUndo
    ) {
        self.plan = plan
        self.outcomes = outcomes
        self.droppedPhotos = droppedPhotos
        self.undo = undo
    }

    /// Photos whose change reached its storage and read back, rejects included (PRD P0-08).
    public var savedCount: Int { outcomes.filter { $0.status.state.isConfirmed }.count }

    /// Photos whose change still needs a retry (PRD P0-09).
    public var failedCount: Int { outcomes.filter { $0.status.state.isUnfinished }.count }

    /// Photos whose change a newer change replaced (PRD How marks reach disk, rule 8).
    public var supersededCount: Int { outcomes.filter { $0.status.state.isSuperseded }.count }

    /// The PRD's "Partial batch failure" wording, or `nil` when every change was confirmed.
    ///
    /// The exact strings stay U7's decision; this follows the PRD's
    /// "Saved N photos. M photos couldn't be saved." copy (PRD Failure and recovery).
    public var partialFailureSummary: String? {
        guard failedCount > 0 else { return nil }
        return "Saved \(savedCount) photos. \(failedCount) photos couldn't be saved."
    }
}
