/// One cell the grid shows: a photo's own cell, or a collapsed similar group's cover
/// (PRD Grid, P0-11).
///
/// The grid reads its photos from the browsing model and its groups from grouping. This value
/// joins them once, so the collection view's data source carries only what a cell draws: the
/// photo, the similar group it belongs to or stands for, and the group's count. It performs no
/// I/O and runs no grouping; grouping (C9) publishes the groups, and the browsing model keeps
/// them (PRD P0-11).
public struct GridCellItem: Identifiable, Hashable, Sendable {
    /// The cell's stable identity across grid updates (PRD P0-11, P0-14).
    ///
    /// A photo's cell keeps its identity while its marks, thumbnail and group change, so a
    /// diffable update moves an existing cell rather than replacing it. A collapsed cover keeps
    /// its group's key through refinement (``GroupID``), so the cover does not blink when the
    /// group's members change.
    public enum ID: Hashable, Sendable {
        /// One photo's own cell (PRD P0-03).
        case photo(PhotoIdentity)

        /// A collapsed similar group's cover cell (PRD Grid, collapsed).
        case group(GroupID)
    }

    /// The identity a diffable data source tracks (PRD P0-11).
    public let id: ID

    /// The photo the cell draws, chosen by `GridDisplay` from the shown members.
    public let photo: GridPhoto

    /// How the cell takes part in a similar group, or nil when grouping is off or the photo is
    /// not grouped (PRD P0-11).
    public let group: GroupMark?

    /// Whether the tile is dimmed. A collapsed stack requires every shown member to be rejected.
    public let isDimmed: Bool

    /// Collects the presentation decided by `GridDisplay`.
    public init(id: ID, photo: GridPhoto, group: GroupMark? = nil, isDimmed: Bool) {
        self.id = id
        self.photo = photo
        self.group = group
        self.isDimmed = isDimmed
    }
}

extension GridCellItem {
    /// How one cell takes part in a similar group (PRD Grid, P0-11).
    ///
    /// Expanded display draws the count on the first shown cell, without an outline.
    /// Collapsed display draws one cover per group with its count (handoff components.md).
    public struct GroupMark: Hashable, Sendable {
        /// The group's stable key; opening the group view uses it (PRD P0-11).
        public let id: GroupID

        /// The group's member count as grouping published it (PRD Grid).
        ///
        /// It is the published group's count, not the number of members a filter happens to
        /// show, so the badge always names the group the user can open.
        public let count: Int

        /// Whether this cell draws the count: a group's first shown cell, or its cover
        /// (PRD Grid).
        public let showsCount: Bool

        /// Whether the cell is the collapsed cover; tapping it opens the group (PRD Grid).
        public let isCover: Bool

        /// Up to two member identities peeking behind a collapsed cover in grid order.
        public let peekingPhotos: [PhotoIdentity]

        /// Describes one cell's part in a group.
        public init(
            id: GroupID, count: Int, showsCount: Bool, isCover: Bool,
            peekingPhotos: [PhotoIdentity] = []
        ) {
            self.id = id
            self.count = count
            self.showsCount = showsCount
            self.isCover = isCover
            self.peekingPhotos = peekingPhotos
        }
    }
}
