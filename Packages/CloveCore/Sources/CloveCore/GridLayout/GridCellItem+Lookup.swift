extension GridCellItem {
    /// The cell that draws one photo, when the grid shows one for it (PRD Grid, P0-11).
    ///
    /// Expanded display has the photo's own cell. Collapsed display draws one cover per group,
    /// so a photo inside a group resolves to that group's cover; this is what keeps the photo
    /// the user is looking at in place when grouping refines its members into a group with a
    /// new key.
    ///
    /// `shown` is the filtered photos the grid was built from, and it decides what counts as
    /// shown: a cover stands for the whole group, but a photo the filter hides has no cell even
    /// when its group's cover is on screen. A grid that ignores the filter here would hold a
    /// cover the hidden photo never selected, moving a photo the user is not looking at.
    ///
    /// The cells, groups and shown photos must belong to the same update; mixing an old list
    /// with new groups, or the reverse, can name a cell that list does not show.
    public static func cell(
        for photo: PhotoIdentity, in cells: [GridCellItem], groups: [BrowsingGroup],
        shown: Set<PhotoIdentity>
    ) -> GridCellItem.ID? {
        guard shown.contains(photo) else { return nil }
        let own = GridCellItem.ID.photo(photo)
        if cells.contains(where: { $0.id == own }) { return own }
        guard let group = groups.first(where: { $0.members.contains(photo) }) else { return nil }
        let cover = GridCellItem.ID.group(group.id)
        return cells.contains(where: { $0.id == cover }) ? cover : nil
    }
}
