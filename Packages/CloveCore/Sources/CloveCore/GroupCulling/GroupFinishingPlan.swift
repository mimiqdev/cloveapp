/// A pure snapshot of the unmarked photos one finishing action will reject.
/// Ratings, labels and existing rejects always protect a photo from this action.
public struct GroupFinishingPlan: Hashable, Sendable {
    public let groupID: GroupID
    public let action: GroupFinishingAction
    /// Undo returns to the photo shown when the action was submitted.
    public let currentPhoto: PhotoIdentity
    public let availability: GroupFinishingAvailability
    public let changes: [GroupFinishingChange]

    public init(
        group: SimilarGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) {
        let hasKeptPhoto = group.members.contains {
            let value = marks[$0] ?? PhotoMarks()
            return value.rating > .unrated || value.label != .clear
        }
        self.groupID = group.id
        self.action = action
        self.currentPhoto = currentPhoto
        self.availability = hasKeptPhoto ? .available : .noRatedOrLabelledPhoto
        self.changes =
            hasKeptPhoto
            ? group.members.compactMap { member in
                let value = marks[member] ?? PhotoMarks()
                guard value.isUnmarked else { return nil }
                return GroupFinishingChange(
                    photo: member, marksBefore: value, change: .rating(.rejected))
            } : []
    }

    public var isEmpty: Bool { changes.isEmpty }
    public var rejects: [GroupFinishingChange] { changes }
}
