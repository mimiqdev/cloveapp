/// The marks one finishing action restores together as one undo step.
/// This value holds the changes submitted to the ordered action pipeline, without any
/// completion record: whether the group is decided follows its current marks.
public struct GroupFinishingUndo: Hashable, Sendable {
    /// The photo shown when the person submitted the action.
    public let photoToReturnTo: PhotoIdentity

    /// Each changed photo's before marks and requested change, in input order.
    public let entries: [GroupFinishingChange]

    init(photoToReturnTo: PhotoIdentity, entries: [GroupFinishingChange]) {
        self.photoToReturnTo = photoToReturnTo
        self.entries = entries
    }
}
