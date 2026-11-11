/// How the grid joins its shown photos and published groups into cells (PRD Grid, P0-11).
///
/// The browsing model already decides which photos show, in which order and with which filter
/// (PRD P0-03); grouping decides which photos form a similar group (PRD P0-11). This value only
/// composes the two, so the grid's data source and its tests share one reading of PRD Grid's
/// similar-group display instead of the collection view inventing a second one.
///
/// Expanded display keeps every photo and marks each cell that belongs to a group with the
/// group's key and count (handoff components.md). Collapsed display keeps one cover per
/// group, keyed by the group, and leaves ungrouped photos as their own cells (PRD Grid,
/// collapsed). With grouping off, no cell carries a group mark, because PRD Grid hides the
/// badges and PRD P0-11 allows grouping to be turned off.
public struct GridDisplay: Sendable {
    /// The grid's cells in the photos' order (PRD P0-03).
    public let cells: [GridCellItem]

    /// Builds the cells for the photos a filter and an order produced (PRD P0-03, P0-11).
    ///
    /// - Parameters:
    ///   - photos: The shown photos, in grid order; a photo that is not here never gets a cell.
    ///   - groups: The groups grouping published, empty when it published none (PRD P0-11).
    ///   - groupsEnabled: Similar groups setting; off hides the badges and covers
    ///     (PRD Grid, P0-11).
    ///   - display: C12's grid group display; expanded is the launch default (PRD Grid).
    ///
    /// A photo that two groups name, which grouping does not publish, is marked with the first
    /// group in `groups` order so a cell never belongs to two groups.
    public init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        groupsEnabled: Bool = true,
        display: GridGroupDisplay = .expanded
    ) {
        let marked = groupsEnabled ? Self.marksByPhoto(photos: photos, groups: groups) : [:]
        switch (groupsEnabled, display) {
        case (true, .expanded):
            self.cells = Self.expandedCells(photos: photos, marks: marked)
        case (true, .collapsed):
            self.cells = Self.collapsedCells(photos: photos, marks: marked)
        case (false, _):
            self.cells = photos.map {
                GridCellItem(id: .photo($0.id), photo: $0, isDimmed: $0.marks.isRejected)
            }
        }
    }
}

extension GridDisplay {
    /// The group that names each shown photo, first published group winning (PRD P0-11).
    private static func marksByPhoto(
        photos: [GridPhoto], groups: [BrowsingGroup]
    ) -> [PhotoIdentity: BrowsingGroup] {
        let shown = Set(photos.map(\.id))
        var marked: [PhotoIdentity: BrowsingGroup] = [:]
        for group in groups {
            for member in group.members where shown.contains(member) && marked[member] == nil {
                marked[member] = group
            }
        }
        return marked
    }

    /// Expanded display: every photo, with the group's count on its first shown cell
    /// (PRD Grid, expanded).
    private static func expandedCells(
        photos: [GridPhoto], marks: [PhotoIdentity: BrowsingGroup]
    ) -> [GridCellItem] {
        var counted: Set<GroupID> = []
        return photos.map { photo in
            guard let group = marks[photo.id] else {
                return GridCellItem(
                    id: .photo(photo.id), photo: photo, isDimmed: photo.marks.isRejected)
            }
            let showsCount = counted.insert(group.id).inserted
            return GridCellItem(
                id: .photo(photo.id),
                photo: photo,
                group: GridCellItem.GroupMark(
                    id: group.id, count: group.members.count, showsCount: showsCount,
                    isCover: false),
                isDimmed: photo.marks.isRejected)
        }
    }

    /// Collapsed display: one cover per group, on its first shown member (PRD Grid, collapsed).
    ///
    /// A group whose members the filter hid has no cover, because the grid never shows a cell
    /// that names no photo it can draw (PRD P0-03).
    private static func collapsedCells(
        photos: [GridPhoto], marks: [PhotoIdentity: BrowsingGroup]
    ) -> [GridCellItem] {
        var shownByGroup: [GroupID: [GridPhoto]] = [:]
        for photo in photos {
            if let group = marks[photo.id] {
                shownByGroup[group.id, default: []].append(photo)
            }
        }
        var covered: Set<GroupID> = []
        var cells: [GridCellItem] = []
        for photo in photos {
            guard let group = marks[photo.id] else {
                cells.append(
                    GridCellItem(
                        id: .photo(photo.id), photo: photo, isDimmed: photo.marks.isRejected))
                continue
            }
            guard covered.insert(group.id).inserted else { continue }
            let shown = shownByGroup[group.id] ?? [photo]
            let cover = shown.first { !$0.marks.isRejected } ?? photo
            cells.append(
                GridCellItem(
                    id: .group(group.id),
                    photo: cover,
                    group: GridCellItem.GroupMark(
                        id: group.id, count: group.members.count, showsCount: true,
                        isCover: true),
                    isDimmed: shown.allSatisfy { $0.marks.isRejected }))
        }
        return cells
    }
}
