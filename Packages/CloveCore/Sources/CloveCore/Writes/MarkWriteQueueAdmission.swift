/// One change the queue admitted, with the marks its photo showed just before it
/// (PRD P0-05's Undo row).
///
/// A caller that must record what a change replaced (U8's undo step) takes the value from here:
/// the queue reads it inside the actor, after the photo's last confirmed write and with every
/// change still in flight folded in admission order, so a slow write or a burst of taps cannot
/// hide the value in between.
public struct MarkChangeAdmission: Hashable, Sendable {
    /// The queue's handle for the admitted change (PRD P0-08).
    public let id: MarkChangeID
    /// The photo the change belongs to (C1's stable identity).
    public let photo: PhotoIdentity
    /// The change that was admitted (PRD P0-07, P0-09).
    public let change: MarkChange
    /// The marks the photo showed just before the admission (PRD P0-05).
    public let marksBefore: PhotoMarks

    /// Describes one admission, for the queue and for a library that applies its changes itself.
    public init(
        id: MarkChangeID, photo: PhotoIdentity, change: MarkChange, marksBefore: PhotoMarks
    ) {
        self.id = id
        self.photo = photo
        self.change = change
        self.marksBefore = marksBefore
    }
}

/// One batch the queue admitted, with each photo's marks just before its change
/// (PRD P0-09; PRD P0-05's Undo row).
public struct MarkBatchAdmission: Sendable {
    /// The queue's handle for the batch, which ``MarkWriteQueue/retryFailed(in:)`` accepts.
    public let batchID: MarkBatchID
    /// The change every photo set received (PRD P0-09).
    public let change: MarkChange
    /// One admission per photo set that held a change, in the caller's order.
    public let admissions: [MarkChangeAdmission]
    /// The refusals for a change that named no marks, in the caller's order (PRD P0-08).
    public let refused: [MarkChangeStatus]

    /// Describes one batch admission, for the queue and for a library that applies its changes
    /// itself.
    public init(
        batchID: MarkBatchID, change: MarkChange, admissions: [MarkChangeAdmission],
        refused: [MarkChangeStatus]
    ) {
        self.batchID = batchID
        self.change = change
        self.admissions = admissions
        self.refused = refused
    }
}
