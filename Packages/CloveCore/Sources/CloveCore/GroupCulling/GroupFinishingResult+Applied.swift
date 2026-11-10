/// Applying a finishing action's plan away from C4's write queue (PRD In-group culling,
/// finishing actions; PRD P0-12).
extension GroupFinishingPlan {
    /// The plan's changes that the marks read now still allow (PRD P0-12; PRD In-group culling,
    /// finishing actions).
    ///
    /// This is the rule ``GroupFinishingExecutor`` re-checks before every write. The current
    /// photo's keep change is derived again from the marks read now, so a rating added after the
    /// plan was built is kept instead of overwritten; a planned reject survives only while the
    /// photo is unmarked, so a photo rated or labelled since the plan is never rejected
    /// (PRD In-group culling: "Neither action ever rejects a photo that already has a rating or
    /// color label"). A library that applies a plan without C4's write queue uses this instead of
    /// planning a second copy of the rule.
    public func changesAllowed(
        currentMarks: (PhotoIdentity) -> PhotoMarks
    ) -> [GroupFinishingChange] {
        var allowed: [GroupFinishingChange] = []
        for change in changes {
            let marks = currentMarks(change.photo)
            switch change.kind {
            case .keep:
                let keeping = GroupFinishingPlan.keepChange(
                    for: marks, keepRating: keepRating)
                guard !keeping.isEmpty else { continue }
                allowed.append(
                    GroupFinishingChange(
                        photo: change.photo, kind: .keep, marksBefore: marks, change: keeping))
            case .reject:
                // A photo that gained a rating, label or Reject since the plan is never rejected.
                guard marks.isUnmarked else { continue }
                allowed.append(
                    GroupFinishingChange(
                        photo: change.photo, kind: .reject, marksBefore: marks,
                        change: change.change))
            }
        }
        return allowed
    }
}

/// Building a finishing action's result away from C4's write queue (PRD In-group culling,
/// finishing actions; PRD P0-09).
extension GroupFinishingResult {
    /// The result of a plan a caller applied itself, with one save state per changed photo.
    ///
    /// ``GroupFinishingExecutor`` is the product path for an open folder: it applies the plan's
    /// changes through C4's write queue, re-reads each photo's marks first and returns the handles
    /// a retry needs. A library without a queue — the in-memory library the UI test browses —
    /// applies the plan's still-allowed changes through its own mark call and builds the same value
    /// here, so the group view, the partial-failure message and C5's undo record read one shape
    /// either way (PRD P0-12; PRD Failure and recovery).
    ///
    /// The changes supply each outcome's photo, kind and marks from before the action, which is
    /// what the undo record is made of; that is why a caller applies
    /// ``GroupFinishingPlan/changesAllowed(currentMarks:)`` and passes its answer rather than the
    /// plan's original list. A change with no entry in `statuses` is reported as dropped, the same
    /// as one the executor could not write; the queue handles are absent because no queue ran, so
    /// a retry of this result stays with the caller.
    public static func applied(
        _ plan: GroupFinishingPlan,
        changes: [GroupFinishingChange],
        statuses: [PhotoIdentity: MarkChangeStatus],
        undo: GroupFinishingUndo? = nil
    ) -> GroupFinishingResult {
        var outcomes: [GroupFinishingOutcome] = []
        var droppedPhotos: [PhotoIdentity] = []
        for change in changes {
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

    /// The result of applying every change the plan asks for, for a caller that already checked
    /// them against the marks read now (PRD P0-12).
    public static func applied(
        _ plan: GroupFinishingPlan,
        statuses: [PhotoIdentity: MarkChangeStatus],
        undo: GroupFinishingUndo? = nil
    ) -> GroupFinishingResult {
        applied(plan, changes: plan.changes, statuses: statuses, undo: undo)
    }
}
