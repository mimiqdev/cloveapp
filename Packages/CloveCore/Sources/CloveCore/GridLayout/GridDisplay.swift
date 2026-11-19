/// How the grid joins its shown photos and published groups into cells (PRD Grid, P0-11).
///
/// The grid draws Detail's two levels (issue #304). The full folder draws standalone photos and one
/// collapsed cover per active group, using the unified Representative Photo rule, visible-member
/// count, visible-only peeking thumbnails, and all-visible-rejected dimming (issue #304,
/// decisions 1 & 2). Group Focus draws only the focused group's visible members, the same content
/// the Focus View filmstrip isolates (issue #309). Groups narrowed to fewer than two visible
/// members are never active, and `groupsEnabled == false` renders a flat 1D stream with no group
/// marks.
public struct GridDisplay: Sendable {
    /// The grid's runs in drawing order; a full folder or a focused group is one run
    /// (``GridSection``).
    public let sections: [GridSection]

    /// The grid's cells in the photos' order (PRD P0-03).
    public var cells: [GridCellItem] { sections.flatMap(\.cells) }

    /// Builds the full folder's cells for the photos a filter and an order produced (PRD P0-03,
    /// P0-11): standalone photos and one collapsed cover per active group, or inline unfolded
    /// single-photo cells when `expandGroupsInline` is true.
    public init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        groupsEnabled: Bool = true,
        expandGroupsInline: Bool = false
    ) {
        guard groupsEnabled else {
            self.sections = [
                GridSection(id: .photos, cells: photos.map(Self.standaloneCell))
            ]
            return
        }
        let resolved = BrowsingGroup.resolveVisibleGroups(in: photos, groups: groups)
        let cells =
            expandGroupsInline
            ? Self.unfoldedCells(photos: photos, resolved: resolved)
            : Self.collapsedCells(photos: photos, resolved: resolved)
        self.sections = [
            GridSection(id: .photos, cells: cells)
        ]
    }

    /// Builds the Group Focus cells: exactly `group.visibleMembers`, in the active order the
    /// Focus View filmstrip uses, as one group run with its fold header (issue #309).
    public init(focusing group: ActiveBrowsingGroup) {
        self.sections = [
            GridSection(
                id: .group(group.id),
                cells: group.visibleMembers.map { photo in
                    GridCellItem(
                        id: .photo(photo.id),
                        photo: photo,
                        group: GridCellItem.GroupMark(
                            id: group.id, count: group.visibleMembers.count,
                            showsCount: false, isCover: false),
                        isDimmed: photo.marks.isRejected)
                })
        ]
    }
}

extension GridDisplay {
    /// One run of folder cells: a standalone photo keeps its own cell, and a group's first shown
    /// member draws the group's collapsed cover in the group's place.
    private static func collapsedCells(
        photos: [GridPhoto],
        resolved: (byGroupID: [GroupID: ActiveBrowsingGroup], byPhotoID: [PhotoIdentity: GroupID])
    ) -> [GridCellItem] {
        var covered: Set<GroupID> = []
        var cells: [GridCellItem] = []
        cells.reserveCapacity(photos.count)
        for photo in photos {
            guard let groupID = resolved.byPhotoID[photo.id],
                let active = resolved.byGroupID[groupID]
            else {
                cells.append(standaloneCell(photo))
                continue
            }
            guard covered.insert(groupID).inserted else { continue }
            let cover = active.representative
            cells.append(
                GridCellItem(
                    id: .group(groupID),
                    photo: cover,
                    group: GridCellItem.GroupMark(
                        id: groupID, count: active.visibleMembers.count,
                        showsCount: true, isCover: true,
                        peekingPhotos: peekingPhotos(
                            cover: cover.id, visibleMembers: active.visibleMembers)),
                    isDimmed: active.visibleMembers.allSatisfy { $0.marks.isRejected }))
        }
        return cells
    }

    /// Unfolds every active group inline in `photos` order so each visible member gets its own
    /// selectable single-photo cell while carrying its `memberIndex` for inline tray grouping.
    private static func unfoldedCells(
        photos: [GridPhoto],
        resolved: (byGroupID: [GroupID: ActiveBrowsingGroup], byPhotoID: [PhotoIdentity: GroupID])
    ) -> [GridCellItem] {
        var memberOffsets: [GroupID: Int] = [:]
        var cells: [GridCellItem] = []
        cells.reserveCapacity(photos.count)
        for photo in photos {
            guard let groupID = resolved.byPhotoID[photo.id],
                let active = resolved.byGroupID[groupID]
            else {
                cells.append(standaloneCell(photo))
                continue
            }
            let memberIndex = memberOffsets[groupID, default: 0]
            memberOffsets[groupID] = memberIndex + 1
            cells.append(
                GridCellItem(
                    id: .photo(photo.id),
                    photo: photo,
                    group: GridCellItem.GroupMark(
                        id: groupID, count: active.visibleMembers.count,
                        showsCount: false, isCover: false,
                        memberIndex: memberIndex),
                    isDimmed: photo.marks.isRejected))
        }
        return cells
    }

    private static func standaloneCell(_ photo: GridPhoto) -> GridCellItem {
        GridCellItem(id: .photo(photo.id), photo: photo, isDimmed: photo.marks.isRejected)
    }

    /// Up to two visible member identities to peek behind a collapsed group cover in grid order
    /// (excluding the cover). Never falls back to hidden/filtered-out members (issue #304).
    public static func peekingPhotos(
        cover: PhotoIdentity, visibleMembers: [GridPhoto]
    ) -> [PhotoIdentity] {
        var result: [PhotoIdentity] = []
        for candidate in visibleMembers where candidate.id != cover {
            result.append(candidate.id)
            if result.count == 2 { break }
        }
        return result
    }
}
