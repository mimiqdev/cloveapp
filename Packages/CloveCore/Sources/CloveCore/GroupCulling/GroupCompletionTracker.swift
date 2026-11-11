/// Which groups of one open folder session are complete, and where the group view goes next
/// (PRD In-group culling, group completion; PRD P0-12).
///
/// A group is complete in two ways (PRD In-group culling, group completion):
///
/// - **By its marks**: every member is rated or rejected. This is derived from the marks read
///   now, so it needs no record and a label alone does not complete a group.
/// - **By a finishing action**: the user ran Reject unmarked on the group in this session. The record stands even when some writes failed,
///   because the action ran and the failures stay visible through C4's state (PRD P0-12;
///   PRD Failure and recovery). Undoing the action clears the record (PRD P0-12).
///
/// The finishing-action records live in memory, one tracker per opened folder, keyed by
/// ``GroupID``. They do not persist across launches: Reject itself does, in XMP (G1 decision 2), and
/// completion follows the marks again when the folder reopens. When groups refine and their
/// IDs change, completion follows the photos: a group whose members are all rated or rejected
/// is complete by definition, and a finishing-action record carries over to the group with the
/// same ID, which C9 keeps when membership overlaps (PRD Similar groups, rules; PRD P0-11).
///
/// The tracker is an actor because the grid, the group view and the write results all read and
/// update it during one session; every input is a plain value, so it holds no UI types.
public actor GroupCompletionTracker {
    /// The groups a finishing action ran on in this session (PRD In-group culling).
    private var finishedGroups: Set<GroupID> = []

    /// Creates an empty tracker; the folder session owns one per opened folder.
    public init() {}

    /// Records that a finishing action ran on one group, even if a later write fails
    /// (PRD In-group culling, group completion; PRD P0-12).
    public func recordFinishingAction(on groupID: GroupID) {
        finishedGroups.insert(groupID)
    }

    /// Clears a finishing-action record, for C5's undo (PRD P0-12; DEV-PLAN C5).
    ///
    /// The group can still be complete by its marks; only the session record is removed.
    public func clearFinishingAction(on groupID: GroupID) {
        finishedGroups.remove(groupID)
    }

    /// Whether a finishing action ran on this group in this session (PRD In-group culling).
    public func hasFinishingAction(on groupID: GroupID) -> Bool {
        finishedGroups.contains(groupID)
    }

    /// Whether the group is complete now, by its marks or by a finishing action
    /// (PRD In-group culling, group completion).
    public func isComplete(
        _ group: SimilarGroup,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> Bool {
        if finishedGroups.contains(group.id) { return true }
        return GroupUndecidedCount(group: group, marks: marks).isCompleteByMarks
    }

    /// The next group in grid order that is not complete, skipping completed groups
    /// (PRD In-group culling: "Going to the next group skips completed groups").
    ///
    /// The search starts after `groupID` and does not wrap, so finishing the last group returns
    /// `nil` and the view stays there. An unknown group has no place in the grid order, so the
    /// answer is `nil` too.
    public func nextIncompleteGroup(
        after groupID: GroupID,
        in groups: SimilarGroups,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> SimilarGroup? {
        guard let index = groups.groups.firstIndex(where: { $0.id == groupID }),
            index + 1 < groups.groups.count
        else { return nil }
        return groups.groups[(index + 1)...].first { !isComplete($0, marks: marks) }
    }

    /// The previous group in grid order that is not complete, for explicit navigation
    /// (PRD In-group culling).
    ///
    /// The search starts before `groupID` and does not wrap; the first group has none.
    public func previousIncompleteGroup(
        before groupID: GroupID,
        in groups: SimilarGroups,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> SimilarGroup? {
        guard let index = groups.groups.firstIndex(where: { $0.id == groupID }), index > 0
        else { return nil }
        return groups.groups[..<index].reversed().first { !isComplete($0, marks: marks) }
    }

}
