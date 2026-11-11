/// Moving through one group's photos, in the group's member order (PRD In-group culling;
/// PRD P0-12).
///
/// Navigation is a pure question: which visible member comes next? Every call takes the marks
/// read now, so a caller never navigates by a stale copy, and nothing here writes a mark.
/// The next unmarked search wraps once and returns nil when no other visible member is unmarked.
/// A photo that is not a member has no place in the order, so its next unmarked answer is nil.
/// Once no unmarked member remains, auto-advance follows the next visible grid cell.
public struct GroupPhotoNavigation: Hashable, Sendable {
    /// The group whose member order navigation follows (PRD Similar groups step 1).
    public let group: SimilarGroup

    /// Builds navigation for one published group.
    public init(group: SimilarGroup) {
        self.group = group
    }

    /// The next visible unmarked member, wrapping once and excluding the photo just marked.
    ///
    /// This is the photo detail shows after a mark is written (PRD In-group culling,
    /// comparison and elimination; PRD P0-12): rated, labelled and rejected members are skipped,
    /// the search continues from the start after the last member, and nil means no other visible
    /// member is unmarked. The current photo is never its own answer, because advancing must move.
    public func nextUndecidedPhoto(
        after photo: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks], visiblePhotos: Set<PhotoIdentity>
    ) -> PhotoIdentity? {
        guard let index = group.members.firstIndex(of: photo) else { return nil }
        return (group.members.dropFirst(index + 1) + group.members.prefix(index)).first {
            visiblePhotos.contains($0) && (marks[$0] ?? PhotoMarks()).isUnmarked
        }
    }

    /// Resolve a mark's group destination before its photo can disappear from a live filter.
    public func advance(
        after photo: PhotoIdentity, marks: [PhotoIdentity: PhotoMarks],
        orderedPhotos: [GridPhoto], groups: [BrowsingGroup], visiblePhotos: Set<PhotoIdentity>
    ) -> GroupAdvance {
        let next =
            nextUndecidedPhoto(after: photo, marks: marks, visiblePhotos: visiblePhotos)
            ?? photoAfterGroup(
                orderedPhotos: orderedPhotos, groups: groups, visiblePhotos: visiblePhotos)
        return next.map(GroupAdvance.nextUndecidedPhoto) ?? .complete
    }

    /// Leaves the group's collapsed grid cell, including singles interleaved with its members.
    /// The full order anchors the search when marking hides the group from a live filter.
    public func photoAfterGroup(
        orderedPhotos: [GridPhoto], groups: [BrowsingGroup], visiblePhotos: Set<PhotoIdentity>
    ) -> PhotoIdentity? {
        let cells = GridDisplay(
            photos: orderedPhotos.filter { visiblePhotos.contains($0.id) },
            groups: groups, display: .collapsed
        ).cells
        if let index = cells.firstIndex(where: { $0.group?.id == group.id }) {
            return cells.dropFirst(index + 1).first?.photo.id
        }
        let members = Set(group.members)
        guard let index = orderedPhotos.firstIndex(where: { members.contains($0.id) }) else {
            return nil
        }
        let later = Set(orderedPhotos.dropFirst(index + 1).map(\.id))
        return cells.first { later.contains($0.photo.id) }?.photo.id
    }
}
