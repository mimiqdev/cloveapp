/// The destination of an explicit Continue tap in group review.
public enum GroupContinueDestination: Hashable, Sendable {
    case group(BrowsingGroup)
    case photo(PhotoIdentity)
    case grid

    /// Uses grid order and the active filter, including when marking hid the current group.
    /// Completed groups remain eligible. There is no wrapping or automatic navigation.
    public static func next(
        after group: GroupID, orderedPhotos: [GridPhoto], groups: [BrowsingGroup],
        visiblePhotos: Set<PhotoIdentity>
    ) -> GroupContinueDestination {
        let cells = GridDisplay(photos: orderedPhotos, groups: groups, display: .collapsed).cells
        guard let index = cells.firstIndex(where: { $0.group?.id == group }) else { return .grid }
        for cell in cells.dropFirst(index + 1) {
            if let mark = cell.group,
                let nextGroup = groups.first(where: { $0.id == mark.id })
            {
                if nextGroup.members.contains(where: { visiblePhotos.contains($0) }) {
                    return .group(nextGroup)
                }
            } else if visiblePhotos.contains(cell.photo.id) {
                return .photo(cell.photo.id)
            }
        }
        return .grid
    }
}
