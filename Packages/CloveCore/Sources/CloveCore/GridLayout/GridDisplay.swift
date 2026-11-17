/// How the grid joins its shown photos and published groups into cells (PRD Grid, P0-11).
///
/// With `groupsEnabled == true`, any published group with at least two visible members in `photos`
/// collapses into one cover cell keyed by `.group(group.id)`, using the unified Representative Photo
/// rule, visible-member count, visible-only peeking thumbnails, and all-visible-rejected dimming
/// (issue #304, decisions 1 & 2). Groups narrowed to fewer than two visible members behave as
/// standalone photos, and `groupsEnabled == false` renders a flat 1D stream with no group marks.
///
/// One active group can be expanded in place instead of drawn as its cover (owner decision, #225;
/// issue #304, decision 6). `SplitFolderGridPane` uses it for the active `expandedGroup`.
public struct GridDisplay: Sendable {
    /// The grid's runs in drawing order; a grid without an expanded group is one run
    /// (``GridSection``).
    public let sections: [GridSection]

    /// The grid's cells in the photos' order (PRD P0-03).
    public var cells: [GridCellItem] { sections.flatMap(\.cells) }

    /// Builds the cells for the photos a filter and an order produced (PRD P0-03, P0-11).
    public init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        groupsEnabled: Bool = true,
        expandedGroup: GroupID? = nil
    ) {
        guard groupsEnabled else {
            self.sections = [
                GridSection(
                    id: .photos(0),
                    cells: photos.map {
                        GridCellItem(id: .photo($0.id), photo: $0, isDimmed: $0.marks.isRejected)
                    })
            ]
            return
        }
        let resolved = BrowsingGroup.resolveVisibleGroups(in: photos, groups: groups)
        self.sections = Self.collapsedSections(
            photos: photos, resolved: resolved, expandedGroup: expandedGroup)
    }
}

extension GridDisplay {
    private static func collapsedSections(
        photos: [GridPhoto],
        resolved: (byGroupID: [GroupID: ActiveBrowsingGroup], byPhotoID: [PhotoIdentity: GroupID]),
        expandedGroup: GroupID?
    ) -> [GridSection] {
        var covered: Set<GroupID> = []
        var before: [GridCellItem] = []
        var members: [GridCellItem] = []
        var after: [GridCellItem] = []

        for photo in photos {
            guard let groupID = resolved.byPhotoID[photo.id],
                let active = resolved.byGroupID[groupID]
            else {
                let cell = GridCellItem(
                    id: .photo(photo.id), photo: photo, isDimmed: photo.marks.isRejected)
                if members.isEmpty { before.append(cell) } else { after.append(cell) }
                continue
            }
            if groupID == expandedGroup {
                members.append(
                    GridCellItem(
                        id: .photo(photo.id),
                        photo: photo,
                        group: GridCellItem.GroupMark(
                            id: groupID, count: active.visibleMembers.count,
                            showsCount: false, isCover: false),
                        isDimmed: photo.marks.isRejected))
                continue
            }
            guard covered.insert(groupID).inserted else { continue }
            let cover = active.representative
            let peeking = Self.peekingPhotos(
                cover: cover.id, visibleMembers: active.visibleMembers)
            let cell = GridCellItem(
                id: .group(groupID),
                photo: cover,
                group: GridCellItem.GroupMark(
                    id: groupID, count: active.visibleMembers.count,
                    showsCount: true, isCover: true, peekingPhotos: peeking),
                isDimmed: active.visibleMembers.allSatisfy { $0.marks.isRejected })
            if members.isEmpty { before.append(cell) } else { after.append(cell) }
        }
        var sections: [GridSection] = []
        if !before.isEmpty {
            sections.append(GridSection(id: .photos(0), cells: before))
        }
        if !members.isEmpty, let expandedGroup {
            sections.append(GridSection(id: .group(expandedGroup), cells: members))
        }
        if !after.isEmpty {
            sections.append(GridSection(id: .photos(1), cells: after))
        }
        return sections.isEmpty ? [GridSection(id: .photos(0), cells: [])] : sections
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
