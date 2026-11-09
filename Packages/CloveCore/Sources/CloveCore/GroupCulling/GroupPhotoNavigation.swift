/// Moving through one group's photos, in the group's member order (PRD In-group culling;
/// PRD P0-12).
///
/// The group view keeps zoom and position while navigating (PRD In-group culling, comparison
/// and elimination), so navigation is a pure question: which member comes next? Every call
/// takes the marks read now, so a caller never navigates by a stale copy, and nothing here
/// writes a mark. A photo that is not a member has no place in the order, so every answer for
/// it is `nil`.
///
/// With Undecided only on, a plain next or previous skips every rated or rejected photo
/// (PRD In-group culling, comparison and elimination). After marking, the group view asks for
/// the next undecided photo, which searches forward and then wraps to the start, and returns
/// `nil` when no other member is undecided (PRD In-group culling, comparison and elimination).
public struct GroupPhotoNavigation: Hashable, Sendable {
    /// The group whose member order navigation follows (PRD Similar groups step 1).
    public let group: SimilarGroup

    /// Whether the group view's Undecided only switch is on (PRD In-group culling).
    public var undecidedOnly: Bool

    /// Builds the navigation for one group and the current Undecided only state.
    public init(group: SimilarGroup, undecidedOnly: Bool = false) {
        self.group = group
        self.undecidedOnly = undecidedOnly
    }

    /// The next member after `photo`, or `nil` at the group's end.
    ///
    /// With ``undecidedOnly`` on, rated and rejected members are skipped and the search still
    /// stops at the end instead of wrapping (PRD In-group culling, comparison and elimination).
    public func nextPhoto(
        after photo: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> PhotoIdentity? {
        guard let index = group.members.firstIndex(of: photo) else { return nil }
        for candidate in group.members[(index + 1)...] {
            if !undecidedOnly || marksOf(candidate, marks).isUndecided { return candidate }
        }
        return nil
    }

    /// The member before `photo`, or `nil` at the group's start.
    ///
    /// With ``undecidedOnly`` on, rated and rejected members are skipped and the search still
    /// stops at the start instead of wrapping (PRD In-group culling, comparison and
    /// elimination).
    public func previousPhoto(
        before photo: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> PhotoIdentity? {
        guard let index = group.members.firstIndex(of: photo) else { return nil }
        for offset in stride(from: index - 1, through: 0, by: -1) {
            let candidate = group.members[offset]
            if !undecidedOnly || marksOf(candidate, marks).isUndecided { return candidate }
        }
        return nil
    }

    /// The next undecided member after `photo`, wrapping to the group's start.
    ///
    /// This is the photo the group view shows after a mark is written (PRD In-group culling,
    /// comparison and elimination; PRD P0-12): rated and rejected members are skipped, the
    /// search continues from the start after the last member, and `nil` means no other member
    /// is undecided. The current photo is never its own answer, because advancing must move.
    public func nextUndecidedPhoto(
        after photo: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> PhotoIdentity? {
        guard let index = group.members.firstIndex(of: photo) else { return nil }
        for candidate in group.members[(index + 1)...] where marksOf(candidate, marks).isUndecided {
            return candidate
        }
        for candidate in group.members[..<index] where marksOf(candidate, marks).isUndecided {
            return candidate
        }
        return nil
    }

    /// The marks read for one member; a member without an entry is unmarked (PRD P0-05).
    private func marksOf(
        _ photo: PhotoIdentity,
        _ marks: [PhotoIdentity: PhotoMarks]
    ) -> PhotoMarks {
        marks[photo] ?? PhotoMarks()
    }
}
