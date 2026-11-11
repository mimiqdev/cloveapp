import Foundation

/// The per-folder undo and redo history for marks (PRD P0-05, P0-12; DEV-PLAN C5).
///
/// PRD P0-05's Undo row, PRD P0-12's "both can be undone" and PRD P0-09's multi-select batches
/// cover three recorded actions: a mark change on one photo, one change applied to a batch, and
/// one of the two in-group finishing actions. U8 supplies the system `UndoManager`, the toolbar
/// button and ⌘Z; this actor is the logic behind them, with no UI or `UndoManager` types.
///
/// - **One instance per opened folder.** The history lives in memory, keeps at most
///   ``defaultDepthLimit`` actions (the oldest is dropped first), and the folder session calls
///   ``clear()`` when the folder closes. Nothing survives a launch.
/// - **Every step is a write through C4.** Undo and redo call ``MarkWriteQueue/apply(_:to:)``,
///   so PRD P0-08's save state, failure copy and retry come from the queue. A restore that
///   fails keeps its entry and stays visible in the queue, so the user can try again or retry
///   C4's change. A step that restored nothing and has no write left to retry is dropped from
///   the history instead, reported by ``MarkUndoResult/droppedFromHistory``: keeping it would
///   make the next undo hit the same entry again and never reach an older action (PRD P0-05's
///   last-in, first-out undo).
/// - **Newer marks win.** Before writing, each photo's latest marks are read from the caller's
///   source. A field that no longer holds the value the step was about to replace keeps its
///   newer value and is reported as left alone, never overwritten (PRD P0-05).
/// - **A new action clears redo.** Recording an action after an undo discards the redo future
///   (PRD P0-05's Undo row: undo is last in, first out).
public actor MarkUndoHistory {
    /// How many actions one folder session keeps.
    ///
    /// Marking sessions are long, but stepping back further than a few dozen actions is rare, and
    /// PRD P0-05 asks for undo, not for a persistent history. Fifty actions cover a full culling
    /// pass while keeping the in-memory records small; past that the oldest entry is dropped.
    public static let defaultDepthLimit = 50

    /// C4's queue, the only path a mark write takes (G1 Safe writes).
    private let queue: MarkWriteQueue
    /// The session's finishing-action records, which a finishing entry clears and restores
    /// (PRD P0-12).
    private let completion: GroupCompletionTracker
    /// The most entries each stack keeps (``defaultDepthLimit`` unless the caller supplies more).
    private let depthLimit: Int

    /// The actions still undoable, oldest first; the last element is the next undo.
    private var undoStack: [MarkUndoEntry] = []
    /// The actions still redoable, oldest first; the last element is the next redo.
    private var redoStack: [MarkUndoEntry] = []
    /// Photos that moved to `_Rejected` in this session, so no step writes their old path
    /// (PRD Move rejects; G1 decision 5).
    private var movedPhotos: Set<PhotoIdentity> = []
    /// Whether a step is running, so two steps never interleave their stack updates.
    private var isRestoring = false
    /// How many actions were recorded, so a step notices a record that arrived while it waited.
    private var recordings = 0
    /// How many times the history was cleared, so a step does not repopulate a closed folder.
    private var closes = 0

    /// Creates the history for one opened folder.
    ///
    /// A folder session passes its own C4 queue and C10 tracker, so the history writes through
    /// the same queue as marking and clears the same completion records. A non-positive depth
    /// limit is treated as one entry, so the history always has a deterministic bound.
    public init(
        queue: MarkWriteQueue,
        completion: GroupCompletionTracker = GroupCompletionTracker(),
        depthLimit: Int = MarkUndoHistory.defaultDepthLimit
    ) {
        self.queue = queue
        self.completion = completion
        self.depthLimit = max(1, depthLimit)
    }

    // MARK: - Recording

    /// Records one photo's mark change after C4 admitted it (PRD P0-05; DEV-PLAN C5).
    ///
    /// PRD P0-05's Undo row restores the previous mark, so the record keeps the marks read before
    /// the change. A change the queue reports as superseded (PRD How marks reach disk, rule 8)
    /// or one whose requested marks equal `marksBefore` (PRD P0-06's no-change rule) records
    /// nothing and returns `nil`: there is no earlier mark to restore. Pass the status C4
    /// returned for exactly this change, once.
    ///
    /// - Parameters:
    ///   - status: C4's status for the admitted change; its ``MarkChangeStatus/requested`` is
    ///     the change the record undoes.
    ///   - marksBefore: The marks read before the change (PRD P0-05).
    ///   - photoToReturnTo: The photo the view should return to, normally the marked photo from
    ///     ``AutoAdvancePlan/markedPhoto`` (PRD Undo row: undo after auto-advance returns to the
    ///     photo whose mark it restored). Defaults to the changed photo.
    /// - Returns: The entry's handle, or `nil` when nothing was recorded.
    @discardableResult
    public func record(
        _ status: MarkChangeStatus,
        marksBefore: PhotoMarks,
        photoToReturnTo: PhotoIdentity? = nil
    ) -> MarkUndoEntryID? {
        guard !status.requested.isEmpty, !status.state.isSuperseded else { return nil }
        let recorded = MarkUndoPhoto(
            photo: status.identity, marksBefore: marksBefore, change: status.requested)
        guard !recorded.changedFields.isEmpty else { return nil }
        return push(
            kind: .single,
            photos: [recorded],
            photoToReturnTo: photoToReturnTo ?? status.identity,
            groupFinishing: nil)
    }

    /// Records one multi-select batch after C4 admitted it (PRD P0-09; DEV-PLAN C5).
    ///
    /// Every photo keeps its own `marksBefore`, because PRD P0-09 applies one change to photos
    /// that may not have started from the same marks: undo restores each photo to its own marks,
    /// not to one shared snapshot. A photo missing from `marksBefore` reads as unmarked
    /// (PRD P0-05). Superseded outcomes, photos whose requested marks equal their marks before,
    /// and repeated photos are left out; if none remain, nothing is recorded.
    ///
    /// - Parameters:
    ///   - batch: C4's per-photo results for the batch.
    ///   - marksBefore: Each photo's marks before the batch, keyed by C1's identity.
    ///   - photoToReturnTo: The photo the view should return to. Defaults to the first recorded
    ///     photo.
    /// - Returns: The entry's handle, or `nil` when nothing was recorded.
    @discardableResult
    public func recordBatch(
        _ batch: MarkBatchResult,
        marksBefore: [PhotoIdentity: PhotoMarks],
        photoToReturnTo: PhotoIdentity? = nil
    ) -> MarkUndoEntryID? {
        var photos: [MarkUndoPhoto] = []
        var seen: Set<PhotoIdentity> = []
        for outcome in batch.outcomes {
            guard !outcome.requested.isEmpty, !outcome.state.isSuperseded,
                seen.insert(outcome.identity).inserted
            else { continue }
            let recorded = MarkUndoPhoto(
                photo: outcome.identity,
                marksBefore: marksBefore[outcome.identity] ?? PhotoMarks(),
                change: outcome.requested)
            guard !recorded.changedFields.isEmpty else { continue }
            photos.append(recorded)
        }
        guard let first = photos.first else { return nil }
        return push(
            kind: .batch,
            photos: photos,
            photoToReturnTo: photoToReturnTo ?? first.photo,
            groupFinishing: nil)
    }

    /// Records one executed finishing action from C10's undo record (PRD P0-12; DEV-PLAN C5).
    ///
    /// ``GroupFinishingUndo`` already holds each changed photo's marks before the action and the
    /// change that ran, so the entry restores them like any other batch. Undoing the entry also
    /// clears the group's finishing-action record through ``GroupCompletionTracker``, and
    /// redoing restores it, but only while at least one photo is written or already at the
    /// target value; a step that restored nothing leaves the record alone (PRD P0-12: finishing
    /// actions can be undone). An action that changed no marks — an empty plan, or every planned
    /// photo dropped — records nothing, because there is no mark to restore.
    ///
    /// - Parameter undo: C10's record of the action that ran.
    /// - Returns: The entry's handle, or `nil` when nothing was recorded.
    @discardableResult
    public func recordGroupFinishing(_ undo: GroupFinishingUndo) -> MarkUndoEntryID? {
        var photos: [MarkUndoPhoto] = []
        var seen: Set<PhotoIdentity> = []
        for change in undo.entries {
            guard seen.insert(change.photo).inserted else { continue }
            let recorded = MarkUndoPhoto(
                photo: change.photo, marksBefore: change.marksBefore, change: change.change)
            guard !recorded.changedFields.isEmpty else { continue }
            photos.append(recorded)
        }
        guard let first = photos.first else { return nil }
        let returnTo =
            photos.contains { $0.photo == undo.photoToReturnTo }
            ? undo.photoToReturnTo : first.photo
        return push(
            kind: .groupFinishing,
            photos: photos,
            photoToReturnTo: returnTo,
            groupFinishing: MarkUndoGroupFinishing(
                groupID: undo.groupID, action: undo.action))
    }

    // MARK: - Undo and redo

    /// Undoes the most recent recorded action, newest first (PRD P0-05's Undo row).
    ///
    /// The step reads each photo's latest marks from `latestMarks` before writing, so a newer
    /// mark from another app or a later action is kept and reported as not undone (PRD P0-05).
    /// Photos whose restore needs the same change are written together through C4's batch apply
    /// (PRD P0-09), which is what gives the per-photo results, save states and retry. A
    /// finishing-action entry also clears its group's completion record when at least one photo
    /// is written or already at the target value (PRD P0-12).
    ///
    /// - Parameters:
    ///   - photoSet: The folder session's current set for a photo, with C2's resolved sidecar
    ///     state. Returning `nil` leaves that photo's fields alone as unavailable.
    ///   - latestMarks: The marks read now for a photo, so a newer mark is kept instead of
    ///     overwritten.
    /// - Returns: The step's result, or `nil` when there is nothing to undo or another step is
    ///   still running.
    public func undo(
        photoSet: @Sendable (PhotoIdentity) async -> ScannedPhotoSet?,
        latestMarks: @Sendable (PhotoIdentity) async -> PhotoMarks
    ) async -> MarkUndoResult? {
        await restore(.undo, photoSet: photoSet, latestMarks: latestMarks)
    }

    /// Redoes the most recently undone action, re-applying its original change (PRD P0-05).
    ///
    /// Redo uses the same per-field check as ``undo(photoSet:latestMarks:)``: it re-applies the
    /// original change only where each field still holds the value undo restored, so a mark
    /// written after the undo is not overwritten. A finishing-action entry restores its group's
    /// completion record when at least one photo is written or already at the target value
    /// (PRD P0-12).
    ///
    /// - Parameters:
    ///   - photoSet: The folder session's current set for a photo.
    ///   - latestMarks: The marks read now for a photo.
    /// - Returns: The step's result, or `nil` when there is nothing to redo or another step is
    ///   still running.
    public func redo(
        photoSet: @Sendable (PhotoIdentity) async -> ScannedPhotoSet?,
        latestMarks: @Sendable (PhotoIdentity) async -> PhotoMarks
    ) async -> MarkUndoResult? {
        await restore(.redo, photoSet: photoSet, latestMarks: latestMarks)
    }

    // MARK: - Queries

    /// How many actions are still undoable (PRD P0-05).
    public var undoCount: Int { undoStack.count }

    /// How many undone actions are still redoable (PRD P0-05).
    public var redoCount: Int { redoStack.count }

    /// Whether ``undo(photoSet:latestMarks:)`` has an entry to work on.
    public var canUndo: Bool { !undoStack.isEmpty }

    /// Whether ``redo(photoSet:latestMarks:)`` has an entry to work on.
    public var canRedo: Bool { !redoStack.isEmpty }

    /// The next entry undo would restore, for a menu that shows its photos or fields.
    public var nextUndo: MarkUndoEntry? { undoStack.last }

    /// The next entry redo would re-apply.
    public var nextRedo: MarkUndoEntry? { redoStack.last }

    /// The next undo's short action name, for the undo menu title (the UI owns the copy).
    public var nextUndoActionName: String? { undoStack.last?.actionName }

    /// The next redo's short action name, for the redo menu title (the UI owns the copy).
    public var nextRedoActionName: String? { redoStack.last?.actionName }

    // MARK: - Session lifetime

    /// Clears both stacks when the folder closes (PRD P0-05).
    ///
    /// PRD P0-05 does not ask for a history across launches, so a reopened folder starts with
    /// nothing to undo; the marks themselves are in their photo's storage. A step still running
    /// finishes its writes but does not repopulate the cleared history.
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        movedPhotos.removeAll()
        closes += 1
    }

    /// Drops or narrows the entries that touch photos moved to `_Rejected` (PRD Move rejects).
    ///
    /// G1 decision 5 makes Move rejects the durable Reject result: a moved photo's files are
    /// under `_Rejected` and restoring them is the user's job, so undo must never write to the
    /// old path. Pass C6's ``RejectMoveResult/movedIdentities``; every entry loses those photos,
    /// an entry left with no photos is removed, and a moving photo also blocks a step already in
    /// flight. A finishing-action entry keeps its group record and restores only the photos it
    /// still has.
    public func forgetMovedPhotos(_ photos: [PhotoIdentity]) {
        guard !photos.isEmpty else { return }
        let moved = Set(photos)
        movedPhotos.formUnion(moved)
        undoStack = undoStack.compactMap { $0.removingPhotos(moved) }
        redoStack = redoStack.compactMap { $0.removingPhotos(moved) }
    }

    // MARK: - Recording helpers

    /// Appends one entry, clears the redo future, and keeps the depth limit.
    private func push(
        kind: MarkUndoEntryKind,
        photos: [MarkUndoPhoto],
        photoToReturnTo: PhotoIdentity,
        groupFinishing: MarkUndoGroupFinishing?
    ) -> MarkUndoEntryID {
        let entry = MarkUndoEntry(
            id: MarkUndoEntryID(),
            kind: kind,
            photos: photos,
            photoToReturnTo: photoToReturnTo,
            groupFinishing: groupFinishing)
        undoStack = appending(entry, to: undoStack)
        // PRD P0-05: undo is last in, first out, so a new action discards the redo future.
        redoStack.removeAll()
        recordings += 1
        return entry.id
    }

    // MARK: - Restoring

    /// Which way one step moves the marks, for the field check and the stack update.
    private enum Step: Hashable {
        /// Put each photo's marks from before the action back (PRD P0-05).
        case undo
        /// Re-apply the action's change over the restored marks (PRD P0-05).
        case redo
    }

    /// Plans one entry, writes the restores through C4, and updates the two stacks.
    private func restore(
        _ step: Step,
        photoSet: @Sendable (PhotoIdentity) async -> ScannedPhotoSet?,
        latestMarks: @Sendable (PhotoIdentity) async -> PhotoMarks
    ) async -> MarkUndoResult? {
        guard !isRestoring else { return nil }
        isRestoring = true
        defer { isRestoring = false }

        let entry: MarkUndoEntry
        let removedAt: Int
        switch step {
        case .undo:
            guard let last = undoStack.popLast() else { return nil }
            entry = last
            removedAt = undoStack.count
        case .redo:
            guard let last = redoStack.popLast() else { return nil }
            entry = last
            removedAt = redoStack.count
        }
        let recordedBefore = recordings
        let closesBefore = closes

        // Read every photo's latest marks first, so one step sees one snapshot of the folder.
        var plans: [MarkUndoRestorePlan] = []
        plans.reserveCapacity(entry.photos.count)
        for recorded in entry.photos {
            let current = await latestMarks(recorded.photo)
            switch step {
            case .undo: plans.append(.undo(recorded, current: current))
            case .redo: plans.append(.redo(recorded, current: current))
            }
        }

        // Photos that need the same change share one C4 batch, so a batch whose photos had
        // different marks before still writes each photo only what it needs (PRD P0-09).
        var writes: [(change: MarkChange, members: [(index: Int, set: ScannedPhotoSet)])] = []
        for index in plans.indices {
            guard let change = plans[index].change else { continue }
            let photo = plans[index].photo
            guard !movedPhotos.contains(photo), let set = await photoSet(photo) else {
                plans[index].leaveRestorableFieldsAlone(.photoUnavailable)
                continue
            }
            if let existing = writes.firstIndex(where: { $0.change == change }) {
                writes[existing].members.append((index, set))
            } else {
                writes.append((change, [(index, set)]))
            }
        }

        var statuses: [Int: MarkChangeStatus] = [:]
        for write in writes {
            let batch = await queue.apply(write.change, to: write.members.map(\.set))
            for member in write.members {
                guard
                    let status = batch.outcomes.first(where: {
                        $0.identity == plans[member.index].photo
                    })
                else { continue }
                statuses[member.index] = status
            }
        }

        let outcomes = plans.enumerated().map { index, plan in
            MarkUndoPhotoOutcome(
                photo: plan.photo,
                status: statuses[index],
                leftAlone: plan.leftAlone,
                alreadyAtTarget: plan.alreadyAtTarget)
        }
        // PRD P0-12: the finishing-action record changes only when the step actually restored
        // something, so an action whose marks were all replaced keeps its completion.
        let reachedTarget = outcomes.contains { $0.reachedTarget }
        let completionUpdate = reachedTarget ? await updateCompletion(for: entry, step: step) : nil
        let dropped = updateStacks(
            entry: entry,
            step: step,
            removedAt: removedAt,
            outcomes: outcomes,
            reachedTarget: reachedTarget,
            recordedNew: recordings - recordedBefore,
            closed: closes != closesBefore)
        return MarkUndoResult(
            actionName: entry.actionName,
            photoToReturnTo: entry.photoToReturnTo,
            outcomes: outcomes,
            completion: completionUpdate,
            droppedFromHistory: dropped)
    }

    /// Clears (undo) or restores (redo) a finishing action's group record (PRD P0-12).
    ///
    /// The caller only calls this when at least one photo reached the target, because a step
    /// that restored nothing did not undo the action; a failed write stays visible through C4
    /// instead (PRD P0-12; PRD Failure and recovery).
    private func updateCompletion(
        for entry: MarkUndoEntry,
        step: Step
    ) async -> MarkUndoCompletionUpdate? {
        guard let group = entry.groupFinishing else { return nil }
        switch step {
        case .undo: await completion.clearFinishingAction(on: group.groupID)
        case .redo: await completion.recordFinishingAction(on: group.groupID)
        }
        return MarkUndoCompletionUpdate(
            groupID: group.groupID, state: step == .undo ? .cleared : .restored)
    }

    /// Puts the entry back, moves it across the two stacks, or drops it; returns whether it was
    /// dropped because the step restored nothing.
    ///
    /// A step with an unfinished or failed write keeps its entry, so the user can try again or
    /// retry C4's change (PRD P0-08); a failed redo is the exception when a new action recorded
    /// while it ran already cleared the redo future. A step that reached no field target and has
    /// no write left to retry is dropped from both stacks: every field kept a newer mark or its
    /// photo was unavailable, and keeping the entry would make the next undo hit the same entry
    /// forever instead of reaching an older action (PRD P0-05's last-in, first-out undo).
    /// `recordedNew` counts the actions recorded while the step waited: a new recorded action
    /// clears the redo future (PRD P0-05), so a step that finishes after one must not resurrect
    /// it.
    private func updateStacks(
        entry: MarkUndoEntry,
        step: Step,
        removedAt: Int,
        outcomes: [MarkUndoPhotoOutcome],
        reachedTarget: Bool,
        recordedNew: Int,
        closed: Bool
    ) -> Bool {
        // The folder is closed, so nothing can be undone or redone in this session any more.
        guard !closed else { return false }
        let needsRetry = outcomes.contains { $0.status?.state.isUnfinished == true }
        switch step {
        case .undo:
            if needsRetry {
                undoStack = inserting(entry, into: undoStack, at: removedAt)
                return false
            }
            guard reachedTarget else { return true }
            if recordedNew == 0 { redoStack = appending(entry, to: redoStack) }
            return false
        case .redo:
            if needsRetry {
                if recordedNew == 0 {
                    redoStack = inserting(entry, into: redoStack, at: removedAt)
                }
                return false
            }
            guard reachedTarget else { return true }
            // The redone action belongs below anything recorded after it was taken.
            undoStack = inserting(
                entry, into: undoStack, at: max(0, undoStack.count - recordedNew))
            return false
        }
    }

    // MARK: - Stack helpers

    /// The stack with one entry appended, pruned to the depth limit.
    private func appending(
        _ entry: MarkUndoEntry,
        to stack: [MarkUndoEntry]
    ) -> [MarkUndoEntry] {
        guard let pruned = entry.removingPhotos(movedPhotos) else { return stack }
        var updated = stack
        updated.append(pruned)
        return bounded(updated)
    }

    /// The stack with one entry inserted at `index`, pruned to the depth limit.
    private func inserting(
        _ entry: MarkUndoEntry,
        into stack: [MarkUndoEntry],
        at index: Int
    ) -> [MarkUndoEntry] {
        guard let pruned = entry.removingPhotos(movedPhotos) else { return stack }
        var updated = stack
        updated.insert(pruned, at: min(max(0, index), updated.count))
        return bounded(updated)
    }

    /// Keeps a stack within ``depthLimit``, dropping the oldest entries first (PRD P0-05).
    private func bounded(_ stack: [MarkUndoEntry]) -> [MarkUndoEntry] {
        guard stack.count > depthLimit else { return stack }
        return Array(stack.dropFirst(stack.count - depthLimit))
    }
}
