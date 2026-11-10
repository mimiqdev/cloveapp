import Foundation

/// One completed Move rejects run as a single undo step.
///
/// PRD's Undo row makes Move rejects one step next to the mark changes, and PRD P0-10's Undo
/// rule says what the step does: the files go back to their original paths and Reject returns on
/// them and on the photos kept in the confirmation. The entry is the value U8's history holds
/// for that step; it is a plain `Sendable` value with no reference to C4's queue, the file
/// system or any UI type, so it outlives the call that produced it. The run itself, meaning the
/// files the move renamed, stays with the mover that did the move.
public struct RejectMoveUndoEntry: Hashable, Sendable, Identifiable {
    /// The run the step restores; a retry of that run resolves to the same step (PRD P0-10).
    public let batch: RejectMoveBatchID
    /// The photos kept in the confirmation, as C1 scanned them (PRD Move rejects).
    ///
    /// A keep is staged in the confirmation and applied on Move, which clears the kept photo's
    /// Reject and moves nothing of it (PRD Move rejects, "Keeping before the move"). Undo
    /// therefore restores only the mark. C4 keys the stored Reject by C1's identity inside the
    /// set, and the set also lets the grid show the photo again without a rescan. The mover keeps
    /// the same photos on the run as well, so the step restores them whichever handle the caller
    /// holds; passing them here is how one entry carries them all.
    public let keptPhotos: [ScannedPhotoSet]
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
    ///   - keptPhotos: The photos kept in the confirmation, which never moved.
    ///   - photoToReturnTo: The photo the view should return to after undo.
    public init(
        batch: RejectMoveBatchID,
        keptPhotos: [ScannedPhotoSet] = [],
        photoToReturnTo: PhotoIdentity
    ) {
        self.batch = batch
        self.keptPhotos = keptPhotos
        self.photoToReturnTo = photoToReturnTo
    }
}
