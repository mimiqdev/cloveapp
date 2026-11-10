/// Building a finishing action's result away from C4's write queue (PRD In-group culling,
/// finishing actions; PRD P0-09).
extension GroupFinishingResult {
    /// The result of a plan a caller applied itself, with one save state per changed photo.
    ///
    /// ``GroupFinishingExecutor`` is the product path for an open folder: it applies the plan's
    /// changes through C4's write queue, re-reads each photo's marks first and returns the handles
    /// a retry needs. A library without a queue — the in-memory library the UI test browses —
    /// applies the same planned changes through its own mark call and builds the same value here,
    /// so the group view, the partial-failure message and C5's undo record read one shape either
    /// way (PRD P0-12; PRD Failure and recovery).
    ///
    /// The plan's own changes supply each outcome's photo, kind and marks from before the action,
    /// which is what the undo record is made of. A planned photo with no entry in `statuses` is
    /// reported as dropped, the same as one the executor could not write; the queue handles are
    /// absent because no queue ran, so a retry of this result stays with the caller.
    public static func applied(
        _ plan: GroupFinishingPlan,
        statuses: [PhotoIdentity: MarkChangeStatus],
        undo: GroupFinishingUndo? = nil
    ) -> GroupFinishingResult {
        var outcomes: [GroupFinishingOutcome] = []
        var droppedPhotos: [PhotoIdentity] = []
        for change in plan.changes {
            guard let status = statuses[change.photo] else {
                droppedPhotos.append(change.photo)
                continue
            }
            outcomes.append(GroupFinishingOutcome(change: change, status: status))
        }
        return GroupFinishingResult(
            plan: plan,
            outcomes: outcomes,
            droppedPhotos: droppedPhotos,
            keptChangeID: nil,
            rejectedBatchID: nil,
            undo: undo
                ?? GroupFinishingUndo(
                    groupID: plan.groupID,
                    action: plan.action,
                    photoToReturnTo: plan.currentPhoto,
                    entries: outcomes.map(\.change)))
    }
}
