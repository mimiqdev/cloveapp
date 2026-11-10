/// Where the group view goes once its group is complete (PRD In-group culling, group
/// completion; PRD P0-12).
///
/// PRD In-group culling defines a complete group as one whose photos are all rated or rejected,
/// or one the user finished with a finishing action. The setting "After a group is complete"
/// then keeps the group on screen or opens the next incomplete group, and a folder with nothing
/// left returns to the grid (PRD In-group culling; PRD Gesture-related settings). The value keeps
/// the group view's answer explicit, so a caller never mistakes "stay" for "nothing left".
public enum GroupViewCompletion: Hashable, Sendable {
    /// The group still has undecided photos and no finishing action has run on it (PRD P0-12).
    case inProgress

    /// The group is complete and the setting keeps it on screen (PRD In-group culling).
    case stay

    /// The group is complete and this group is the next one in grid order that is not complete,
    /// skipping completed groups (PRD In-group culling: "Going to the next group skips completed
    /// groups").
    case nextGroup(BrowsingGroup)

    /// The group is complete and no later group is incomplete, so the group view returns to the
    /// grid (PRD In-group culling, group completion).
    case grid
}

extension GroupCompletionTracker {
    /// Where the group view goes after `groupID` completes, or that it has not completed
    /// (PRD In-group culling, group completion; PRD P0-12).
    ///
    /// The completion rules are ``GroupCompletionTracker``'s: a group is complete when every
    /// member is rated or rejected, or when a finishing action ran on it in this session. The
    /// behaviour is C12's setting, and the search for the next group starts after this one in grid
    /// order and never wraps, so the last complete group returns ``GroupViewCompletion/grid``
    /// instead of two groups back.
    ///
    /// - Parameters:
    ///   - groupID: The group the view is on.
    ///   - groups: The folder's published groups, in grid order (PRD P0-11).
    ///   - behaviour: C12's "After a group is complete" (PRD Gesture-related settings).
    ///   - marks: The marks read now, one entry per photo.
    public func viewCompletion(
        after groupID: GroupID,
        in groups: [BrowsingGroup],
        behaviour: GroupCompletionBehaviour,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> GroupViewCompletion {
        guard let group = groups.first(where: { $0.id == groupID }) else {
            // A group the folder no longer publishes has no place in the order, so nothing can
            // have completed it here.
            return .inProgress
        }
        guard isComplete(group.cullingGroup, marks: marks) else { return .inProgress }
        switch behaviour {
        case .stay:
            return .stay
        case .nextGroup:
            return nextIncompleteGroup(after: groupID, in: groups, marks: marks)
                .map(GroupViewCompletion.nextGroup) ?? .grid
        }
    }
}
