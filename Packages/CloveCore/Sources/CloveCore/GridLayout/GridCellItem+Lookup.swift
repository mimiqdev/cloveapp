extension GridCellItem {
    /// The cell that draws one photo, when the grid shows one for it (PRD Grid, P0-11).
    ///
    /// Expanded display has the photo's own cell. Collapsed display draws one cover per group,
    /// so a photo inside a group resolves to that group's cover; this is what keeps the photo
    /// the user is looking at in place when grouping refines its members into a group with a
    /// new key. A photo the filter hides, or one inside a group whose cover the filter hides,
    /// has no cell and answers nil.
    ///
    /// The cells and groups must belong to the same update; resolving the photo against an old
    /// cell list with new groups, or the reverse, can name a cell that list does not show.
    public static func cell(
        for photo: PhotoIdentity, in cells: [GridCellItem], groups: [BrowsingGroup]
    ) -> GridCellItem.ID? {
        let own = GridCellItem.ID.photo(photo)
        if cells.contains(where: { $0.id == own }) { return own }
        guard let group = groups.first(where: { $0.members.contains(photo) }) else { return nil }
        let cover = GridCellItem.ID.group(group.id)
        return cells.contains(where: { $0.id == cover }) ? cover : nil
    }
}
