/// One photo's outcome from an executed finishing action (PRD In-group culling, finishing
/// actions; PRD P0-09's per-photo results).
public struct GroupFinishingOutcome: Hashable, Sendable {
    /// The change that was requested, with the marks read just before it (DEV-PLAN C5).
    public let change: GroupFinishingChange

    /// C4's completed write result for the change.
    public let status: MarkChangeStatus

    /// The photo the outcome belongs to (C1's stable identity).
    public var photo: PhotoIdentity { change.photo }
}

/// What one executed finishing action produced, per photo and for C5 (PRD P0-12, P0-09).
///
/// The result keeps the plan that ran, one outcome per requested change in plan order, and the
/// photos dropped because their marks no longer allowed the change. The undo record carries
/// the marks from before the action (DEV-PLAN C5).
public struct GroupFinishingResult: Hashable, Sendable {
    /// The plan that ran (PRD In-group culling, finishing actions).
    public let plan: GroupFinishingPlan

    /// One outcome per requested reject, in input order.
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

    /// Photos whose requested change failed.
    public var failedCount: Int { outcomes.filter { $0.status.state.failure != nil }.count }

}
