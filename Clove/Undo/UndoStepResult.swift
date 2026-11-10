import CloveCore
import Foundation

/// The group whose finishing record one step changed, as the screens read it (PRD P0-12).
///
/// PRD P0-12 makes a group complete when every photo is rated or rejected, or when a finishing
/// action ran. Undoing that action clears the record C10 keeps for it, and the group view must
/// stop treating the group as finished; redoing it puts the record back.
struct UndoCompletionChange: Hashable, Sendable {
    /// The group the finishing action ran on (PRD P0-12).
    let groupID: GroupID
    /// Whether the step cleared the record (undo) or restored it (redo).
    let isCleared: Bool
}

/// What one undo or redo step produced, as the browsing screens read it (PRD P0-05, P0-12).
///
/// C5's ``MarkUndoHistory`` answers with per-photo outcomes and C4 statuses; the screens need
/// less: where to go back to, whether a write still needs a retry, and which group's completion
/// changed. The folder library maps C5's result to this value, and a library with no write queue
/// (the test library) can answer it directly, so both browse through one seam.
struct UndoStepResult: Hashable, Sendable {
    /// The photo the view returns to (PRD P0-05's Undo row: undo after auto-advance returns to
    /// the photo whose mark was undone).
    let photoToReturnTo: PhotoIdentity
    /// PRD P0-09's partial-failure line, or `nil` when every restored field reached its storage.
    let failureSummary: String?
    /// The group whose completion record the step changed, or `nil` when it changed none
    /// (PRD P0-12).
    let completion: UndoCompletionChange?
    /// Whether C5 dropped the step's entry because it restored nothing.
    ///
    /// A failed or unfinished write keeps its entry (PRD P0-08); a step whose every field kept a
    /// newer mark leaves nothing to undo, so the system undo stack must be rebuilt from the
    /// history instead of keeping a pair for it (PRD P0-05).
    let droppedFromHistory: Bool

    /// Maps C5's result, keeping the parts the screens and the system undo stack read.
    init(_ result: MarkUndoResult) {
        photoToReturnTo = result.photoToReturnTo
        failureSummary = result.partialFailureSummary
        completion = result.completion.map {
            UndoCompletionChange(groupID: $0.groupID, isCleared: $0.state == .cleared)
        }
        droppedFromHistory = result.droppedFromHistory
    }

    /// Describes one step for a library that applies its changes itself (PRD P0-08, P0-12).
    init(
        photoToReturnTo: PhotoIdentity,
        failureSummary: String?,
        completion: UndoCompletionChange?,
        droppedFromHistory: Bool
    ) {
        self.photoToReturnTo = photoToReturnTo
        self.failureSummary = failureSummary
        self.completion = completion
        self.droppedFromHistory = droppedFromHistory
    }
}

/// The counts of an undo or redo step whose writes did not all confirm (PRD P0-08, P0-09).
///
/// A failed step keeps its history entry, so the same Undo button is its retry; the direction is
/// kept here because a failed redo must be redone again, not undone (C5's rule).
struct UndoFailure: Hashable, Sendable {
    /// C5's partial-failure line, which the Undo row shows (PRD P0-09).
    let summary: String
    /// Whether the failed step was a redo, so Try again repeats it in the same direction.
    let isRedo: Bool
}
