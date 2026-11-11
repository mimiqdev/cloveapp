/// Applying a finishing action's plan away from C4's write queue (PRD In-group culling,
/// finishing actions; PRD P0-12).
extension GroupFinishingPlan {
    /// Rechecks the plan against shown marks at synchronous submission. A later rating or label
    /// keeps its photo out of the finishing action.
    public func changesAllowed(
        currentMarks: (PhotoIdentity) -> PhotoMarks
    ) -> [GroupFinishingChange] {
        guard availability.isAvailable else { return [] }
        var allowed: [GroupFinishingChange] = []
        if action == .keepThis {
            // The current photo is derived from the marks read now, not from the planned list: a
            // photo the plan had nothing to change can be unrated or rejected by the time the
            // action runs, and then it still has to be kept (PRD In-group culling).
            let marks = currentMarks(currentPhoto)
            let keeping = GroupFinishingPlan.keepChange(for: marks, keepRating: keepRating)
            if !keeping.isEmpty {
                allowed.append(
                    GroupFinishingChange(
                        photo: currentPhoto, kind: .keep, marksBefore: marks, change: keeping))
            }
        }
        for change in changes where change.kind == .reject {
            let marks = currentMarks(change.photo)
            // A photo that gained a rating, label or Reject since the plan is never rejected.
            guard marks.isUnmarked else { continue }
            allowed.append(
                GroupFinishingChange(
                    photo: change.photo, kind: .reject, marksBefore: marks,
                    change: change.change))
        }
        return allowed
    }
}

/// Building a finishing action's result away from C4's write queue (PRD In-group culling,
/// finishing actions; PRD P0-09).
extension GroupFinishingResult {
    /// Builds the finishing result from the submitted changes and their per-photo save states.
    /// The before marks come from desired marks at input time, so the undo record never reads
    /// a delayed confirmed value.
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
