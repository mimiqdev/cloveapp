/// The destination of an explicit Continue tap in group review.
public enum GroupContinueDestination: Hashable, Sendable {
    case group(BrowsingGroup)
    case photo(PhotoIdentity)
    case grid

    /// Filter before collapsing, exactly as the grid does. A group's cover is its first visible
    /// member, which can fall after an interleaved single photo. If marking hid the current group,
    /// its cover at entry anchors the search in the full order. Completed groups remain eligible.
    public static func next(
        after group: GroupID, orderedPhotos: [GridPhoto], groups: [BrowsingGroup],
        visiblePhotos: Set<PhotoIdentity>, entryCover: PhotoIdentity? = nil
    ) -> GroupContinueDestination {
        let visible = orderedPhotos.filter { visiblePhotos.contains($0.id) }
        let cells = GridDisplay(photos: visible, groups: groups, display: .collapsed).cells
        let candidate: GridCellItem?
        if let index = cells.firstIndex(where: { $0.group?.id == group }) {
            candidate = cells.dropFirst(index + 1).first
        } else {
            let members = Set(groups.first(where: { $0.id == group })?.members ?? [])
            guard
                let anchor = entryCover
                    ?? orderedPhotos.first(where: { members.contains($0.id) })?.id,
                let index = orderedPhotos.firstIndex(where: { $0.id == anchor })
            else { return .grid }
            let later = Set(orderedPhotos.dropFirst(index + 1).map(\.id))
            candidate = cells.first { later.contains($0.photo.id) }
        }
        guard let candidate else { return .grid }
        if let mark = candidate.group, let next = groups.first(where: { $0.id == mark.id }) {
            return .group(next)
        }
        return .photo(candidate.photo.id)
    }
}
