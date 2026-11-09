/// A finishing action's changes, built before anything is written (PRD In-group culling,
/// finishing actions; PRD P0-12).
///
/// The plan is a pure value: the group, the action, the photo the group view is on, and the
/// marks read now in, and every photo and change out. Nothing here writes, so the group view
/// can show the plan and a test can check it without a file system. Only members of the given
/// group ever appear in ``changes``, and a photo with a rating, a colour label or Reject is
/// never planned for a reject (PRD P0-12; PRD In-group culling, finishing actions).
///
/// Keep this, reject the rest gives the current photo the lowest enabled rating when it has
/// none, clears its Reject when it is rejected, and leaves an existing rating and label alone;
/// every other unmarked member is rejected (PRD In-group culling, finishing actions).
/// Keep rated, reject the rest leaves rated photos unchanged and rejects the other unmarked
/// members; it is unavailable when no member is rated
/// (``GroupFinishingAvailability/noRatedPhoto``).
public struct GroupFinishingPlan: Hashable, Sendable {
    /// The group the action finishes; the completion record is keyed by it (PRD P0-12).
    public let groupID: GroupID

    /// The action this plan runs (PRD In-group culling, finishing actions).
    public let action: GroupFinishingAction

    /// The photo the group view is showing; C5's undo returns here (DEV-PLAN C5).
    public let currentPhoto: PhotoIdentity

    /// The rating Keep this gives an unrated current photo, C12's lowest enabled level
    /// (PRD In-group culling, finishing actions).
    public let keepRating: Rating

    /// Whether the action may run; when it may not, ``changes`` is empty (PRD P0-12).
    public let availability: GroupFinishingAvailability

    /// The changes to apply, the current photo's keep change first and then rejects in member
    /// order (PRD In-group culling, finishing actions).
    public let changes: [GroupFinishingChange]

    /// Plans one finishing action from the marks read now.
    ///
    /// A member with no entry in `marks` reads as unmarked (PRD P0-05). A photo outside the
    /// group never enters the plan, and the current photo's own change is planned only when it
    /// is a member (PRD In-group culling, finishing actions).
    public init(
        group: SimilarGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks],
        enabledRatings: EnabledRatings
    ) {
        func marksOf(_ photo: PhotoIdentity) -> PhotoMarks { marks[photo] ?? PhotoMarks() }
        let keepRating = enabledRatings.lowest
        var changes: [GroupFinishingChange] = []
        switch action {
        case .keepThis:
            if group.members.contains(currentPhoto) {
                let current = marksOf(currentPhoto)
                let change = GroupFinishingPlan.keepChange(
                    for: current, keepRating: keepRating)
                if !change.isEmpty {
                    changes.append(
                        GroupFinishingChange(
                            photo: currentPhoto, kind: .keep, marksBefore: current,
                            change: change))
                }
            }
            for member in group.members where member != currentPhoto {
                let memberMarks = marksOf(member)
                guard memberMarks.isUnmarked else { continue }
                changes.append(
                    GroupFinishingChange(
                        photo: member, kind: .reject, marksBefore: memberMarks,
                        change: MarkChange(reject: true)))
            }
            self.availability = .available
        case .keepRated:
            let hasRatedPhoto = group.members.contains {
                marksOf($0).rating > .unrated
            }
            if hasRatedPhoto {
                for member in group.members {
                    let memberMarks = marksOf(member)
                    guard memberMarks.isUnmarked else { continue }
                    changes.append(
                        GroupFinishingChange(
                            photo: member, kind: .reject, marksBefore: memberMarks,
                            change: MarkChange(reject: true)))
                }
            }
            self.availability = hasRatedPhoto ? .available : .noRatedPhoto
        }
        self.groupID = group.id
        self.action = action
        self.currentPhoto = currentPhoto
        self.keepRating = keepRating
        self.changes = changes
    }

    /// Whether the plan changes nothing, so executing it writes nothing (PRD P0-12).
    public var isEmpty: Bool { changes.isEmpty }

    /// The current photo's own keep change, or `nil` when it needs none (PRD In-group culling).
    public var keptPhoto: GroupFinishingChange? {
        changes.first { $0.kind == .keep }
    }

    /// The photos this plan rejects, in member order (PRD P0-12).
    public var rejects: [GroupFinishingChange] {
        changes.filter { $0.kind == .reject }
    }

    /// Keep this's change for the marks read now, used to plan and again at execution.
    ///
    /// The rule is independent of when it runs: an unrated photo gets `keepRating`, a rejected
    /// photo has its Reject cleared, and an existing rating and label stay untouched (PRD
    /// In-group culling, finishing actions). Running it again at execution means a photo rated
    /// after the plan was built keeps its rating instead of being overwritten.
    static func keepChange(for marks: PhotoMarks, keepRating: Rating) -> MarkChange {
        MarkChange(
            rating: marks.rating == .unrated ? keepRating : nil,
            reject: marks.isRejected ? false : nil)
    }
}
