/// Applies a finishing action's plan through C4's write queue (PRD In-group culling, finishing
/// actions; PRD P0-09; PRD P0-12).
///
/// The executor is the only part of in-group culling that writes. It first records the group's
/// completion, because the action ran even if a write later fails (PRD In-group culling, group
/// completion), then reads the latest marks for every planned photo, asks
/// ``GroupFinishingPlan/changesAllowed(currentMarks:)`` what is still allowed and writes only
/// that:
///
/// - The current photo's keep change for Keep this is derived again from the marks read now, so
///   a photo rated after the plan was built keeps that rating (PRD In-group culling).
/// - A planned reject is dropped when the photo is no longer unmarked, so a photo rated or
///   labelled after the plan was built is never rejected (PRD P0-12; PRD In-group culling,
///   finishing actions).
///
/// The rejects go through C4's batch apply, which is what gives the PRD's per-photo results,
/// the "Saved N photos. M photos couldn't be saved." counts and a retry of only the failed
/// items (PRD P0-09; PRD Failure and recovery). An empty plan or an unavailable action writes
/// nothing, and an unavailable action records no completion because it did not run
/// (PRD P0-12). Every executed plan returns C5's undo record (PRD P0-12; DEV-PLAN C5).
public struct GroupFinishingExecutor: Sendable {
    /// C4's queue, the only path a mark change takes (G1 Safe writes).
    private let queue: MarkWriteQueue

    /// The session's completion records (PRD In-group culling, group completion).
    private let completion: GroupCompletionTracker

    /// Creates an executor over one folder session's queue and completion records.
    ///
    /// The default tracker is for a caller that does not need the record itself; a folder
    /// session passes its own so completion survives across actions (PRD In-group culling).
    public init(
        queue: MarkWriteQueue,
        completion: GroupCompletionTracker = GroupCompletionTracker()
    ) {
        self.queue = queue
        self.completion = completion
    }

    /// Runs one plan, re-checking every photo's marks first, and reports per-photo results.
    ///
    /// `photoSet` supplies C1/C2's scanned set for a member, which C4 needs for the write
    /// destinations; `latestMarks` is read at execution time, so a mark written after the plan
    /// was built is respected. The re-check itself is
    /// ``GroupFinishingPlan/changesAllowed(currentMarks:)``'s, the one rule every caller that
    /// applies a finishing plan uses. A member whose set is not supplied is dropped from the write
    /// and listed in ``GroupFinishingResult/droppedPhotos``. An unavailable plan, such as Keep
    /// this with the viewed photo outside the group, writes nothing and records no completion
    /// (PRD P0-12; PRD P0-11).
    public func execute(
        _ plan: GroupFinishingPlan,
        photoSet: @Sendable (PhotoIdentity) async -> ScannedPhotoSet?,
        latestMarks: @Sendable (PhotoIdentity) async -> PhotoMarks
    ) async -> GroupFinishingResult {
        guard plan.availability.isAvailable else {
            return makeResult(plan: plan, outcomes: [], droppedPhotos: [])
        }
        // The action ran, so the group counts as finished even when a write fails
        // (PRD In-group culling, group completion; PRD P0-12).
        await completion.recordFinishingAction(on: plan.groupID)

        // Keep this reads the current photo even when the plan had nothing to change for it, so
        // the marks are read for the current photo and for every planned one.
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        if plan.action == .keepThis {
            marks[plan.currentPhoto] = await latestMarks(plan.currentPhoto)
        }
        for change in plan.changes where marks[change.photo] == nil {
            marks[change.photo] = await latestMarks(change.photo)
        }
        let allowed = plan.changesAllowed { marks[$0] ?? PhotoMarks() }

        var outcomes: [GroupFinishingOutcome] = []
        var droppedPhotos: [PhotoIdentity] = []
        for change in plan.changes where !allowed.contains(where: { $0.photo == change.photo }) {
            droppedPhotos.append(change.photo)
        }

        var keptChangeID: MarkChangeID?
        if let keep = allowed.first(where: { $0.kind == .keep }) {
            if let set = await photoSet(keep.photo) {
                let status = await queue.apply(keep.change, to: set)
                keptChangeID = status.id
                outcomes.append(GroupFinishingOutcome(change: keep, status: status))
            } else {
                droppedPhotos.append(keep.photo)
            }
        }

        var rejectChanges: [GroupFinishingChange] = []
        var rejectSets: [ScannedPhotoSet] = []
        for reject in allowed where reject.kind == .reject {
            guard let set = await photoSet(reject.photo) else {
                droppedPhotos.append(reject.photo)
                continue
            }
            rejectChanges.append(reject)
            rejectSets.append(set)
        }
        var rejectedBatchID: MarkBatchID?
        if !rejectSets.isEmpty {
            let batch = await queue.apply(MarkChange(rating: .rejected), to: rejectSets)
            rejectedBatchID = batch.id
            for change in rejectChanges {
                if let status = batch.outcomes.first(where: { $0.identity == change.photo }) {
                    outcomes.append(GroupFinishingOutcome(change: change, status: status))
                }
            }
        }

        return makeResult(
            plan: plan, outcomes: outcomes, droppedPhotos: droppedPhotos,
            keptChangeID: keptChangeID, rejectedBatchID: rejectedBatchID)
    }

    /// Retries only the changes that still need it, through C4 (PRD P0-09).
    ///
    /// A confirmed change is left alone, so retrying cannot repeat a successful write; a failed
    /// kept change goes through ``MarkWriteQueue/retry(_:)`` and failed rejects through
    /// ``MarkWriteQueue/retryFailed(in:)``. The plan, the dropped photos and the undo record
    /// stay as they were, because a retry writes the same requested changes.
    public func retryFailed(in result: GroupFinishingResult) async -> GroupFinishingResult {
        var outcomes = result.outcomes
        var rejectedBatchID = result.rejectedBatchID
        if let keptChangeID = result.keptChangeID,
            let index = outcomes.firstIndex(where: { $0.status.id == keptChangeID }),
            outcomes[index].status.state.isUnfinished,
            let retried = await queue.retry(keptChangeID)
        {
            outcomes[index] = GroupFinishingOutcome(
                change: outcomes[index].change, status: retried)
        }
        let hasUnfinishedReject = outcomes.contains {
            $0.change.kind == .reject && $0.status.state.isUnfinished
        }
        if let batchID = rejectedBatchID, hasUnfinishedReject,
            let retriedBatch = await queue.retryFailed(in: batchID)
        {
            for status in retriedBatch.outcomes {
                if let index = outcomes.firstIndex(where: { $0.status.id == status.id }) {
                    outcomes[index] = GroupFinishingOutcome(
                        change: outcomes[index].change, status: status)
                }
            }
            rejectedBatchID = retriedBatch.id
        }
        return makeResult(
            plan: result.plan, outcomes: outcomes, droppedPhotos: result.droppedPhotos,
            keptChangeID: result.keptChangeID, rejectedBatchID: rejectedBatchID,
            undo: result.undo)
    }

    /// Assembles one result, deriving C5's undo record from the changes that were requested.
    private func makeResult(
        plan: GroupFinishingPlan,
        outcomes: [GroupFinishingOutcome],
        droppedPhotos: [PhotoIdentity],
        keptChangeID: MarkChangeID? = nil,
        rejectedBatchID: MarkBatchID? = nil,
        undo: GroupFinishingUndo? = nil
    ) -> GroupFinishingResult {
        let record =
            undo
            ?? GroupFinishingUndo(
                groupID: plan.groupID,
                action: plan.action,
                photoToReturnTo: plan.currentPhoto,
                entries: outcomes.map(\.change))
        return GroupFinishingResult(
            plan: plan,
            outcomes: outcomes,
            droppedPhotos: droppedPhotos,
            keptChangeID: keptChangeID,
            rejectedBatchID: rejectedBatchID,
            undo: record)
    }
}
