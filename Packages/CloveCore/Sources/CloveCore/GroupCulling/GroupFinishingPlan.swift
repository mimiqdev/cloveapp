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
        groupID: GroupID,
        members: [PhotoIdentity],
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) {
        let hasKeptPhoto = members.contains {
            let value = marks[$0] ?? PhotoMarks()
            return value.rating > .unrated || value.label != .clear
        }
        self.groupID = groupID
        self.action = action
        self.currentPhoto = currentPhoto
        self.availability = hasKeptPhoto ? .available : .noRatedOrLabelledPhoto
        self.changes =
            hasKeptPhoto
            ? members.compactMap { member in
                let value = marks[member] ?? PhotoMarks()
                guard value.isUnmarked else { return nil }
                return GroupFinishingChange(
                    photo: member, marksBefore: value, change: .rating(.rejected))
            } : []
    }

    public init(
        group: SimilarGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) {
        self.init(
            groupID: group.id,
            members: group.members,
            action: action,
            currentPhoto: currentPhoto,
            marks: marks)
    }

    public init(
        group: ActiveBrowsingGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity
    ) {
        self.init(
            groupID: group.id,
            members: group.visibleMembers.map(\.id),
            action: action,
            currentPhoto: currentPhoto,
            marks: Dictionary(
                uniqueKeysWithValues: group.visibleMembers.map { ($0.id, $0.marks) }))
    }

    public var isEmpty: Bool { changes.isEmpty }
    public var rejects: [GroupFinishingChange] { changes }
}
