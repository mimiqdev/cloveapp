/// Everything C5 needs to undo one executed finishing action (PRD P0-12: finishing actions can
/// be undone; DEV-PLAN C5).
///
/// The record keeps each changed photo's marks from before the action and the change that was
/// applied, plus the photo the group view should return to. It is a `Sendable` value with no
/// reference to the write queue, so C5 can hold it, and it contains only the photos the
/// executor actually requested: a photo dropped because its marks changed after the plan was
/// built was never changed and needs no undo.
public struct GroupFinishingUndo: Hashable, Sendable {
    /// The group the action finished, so C5 can clear its completion (PRD P0-12).
    public let groupID: GroupID

    /// The action that was executed (PRD In-group culling, finishing actions).
    public let action: GroupFinishingAction

    /// The photo the group view was on, where undo returns (DEV-PLAN C5).
    public let photoToReturnTo: PhotoIdentity

    /// One entry per photo the executor requested a change for, in plan order.
    public let entries: [GroupFinishingChange]

    /// Collects one record; only the executor builds these (DEV-PLAN C5).
    init(
        groupID: GroupID,
        action: GroupFinishingAction,
        photoToReturnTo: PhotoIdentity,
        entries: [GroupFinishingChange]
    ) {
        self.groupID = groupID
        self.action = action
        self.photoToReturnTo = photoToReturnTo
        self.entries = entries
    }
}
