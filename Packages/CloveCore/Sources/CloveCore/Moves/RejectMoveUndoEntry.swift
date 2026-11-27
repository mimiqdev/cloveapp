import Foundation

/// One completed Move rejects run as a single undo step.
///
/// PRD's Undo row makes Move rejects one step next to the mark changes, and PRD P0-10's Undo
/// rule says what the step does: the files go back to their original paths and Reject returns on
/// them. The entry is the value U8's history holds for that step; it is a plain `Sendable` value
/// with no reference to C4's queue, the file system or any UI type, so it outlives the call that
/// produced it. The run itself, meaning the files the move renamed, stays with the mover that did
/// the move.
public struct RejectMoveUndoEntry: Hashable, Sendable, Identifiable {
    /// The run the step restores; a retry of that run resolves to the same step (PRD P0-10).
    public let batch: RejectMoveBatchID
    /// Where undo sends the view back to (PRD Undo row: the photo whose mark was undone).
    public let photoToReturnTo: PhotoIdentity

    /// The step's id for a UI list; PRD P0-10's Undo applies to one run once.
    public var id: RejectMoveBatchID { batch }

    /// The undo menu's short action name; the final copy belongs to U8.
    public var actionName: String { "Move rejects" }

    /// Records one completed run as an undo step (PRD P0-10's Undo rule).
    ///
    /// - Parameters:
    ///   - batch: The run's handle, as the move or its retry returned it.
    ///   - photoToReturnTo: The photo the view should return to after undo.
    public init(batch: RejectMoveBatchID, photoToReturnTo: PhotoIdentity) {
        self.batch = batch
        self.photoToReturnTo = photoToReturnTo
    }
}
