/// Auto-advance within a group and then into the following photos in grid order.
public struct GroupPhotoNavigation: Hashable, Sendable {
    public let group: SimilarGroup

    public init(group: SimilarGroup) {
        self.group = group
    }

    /// The next unmarked member, wrapping once and excluding the photo just marked.
    public func nextUndecidedPhoto(
        after photo: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) -> PhotoIdentity? {
        guard let index = group.members.firstIndex(of: photo) else { return nil }
        return (group.members.dropFirst(index + 1) + group.members.prefix(index)).first {
            (marks[$0] ?? PhotoMarks()).isUnmarked
        }
    }

    /// Resolve a mark's group destination before its photo can disappear from a live filter.
    public func advance(
        after photo: PhotoIdentity, marks: [PhotoIdentity: PhotoMarks],
        orderedPhotos: [GridPhoto], groups: [BrowsingGroup], visiblePhotos: Set<PhotoIdentity>
    ) -> GroupAdvance {
        let next =
            nextUndecidedPhoto(after: photo, marks: marks)
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
