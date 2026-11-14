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
///
/// One collapsed group can be expanded in place instead of drawn as its cover (owner decision,
/// 2026-11-13, #225). The Duo's split uses it for the photo on screen, so the person browses
/// the group's members without losing the folder around them.
public struct GridDisplay: Sendable {
    /// The grid's runs in drawing order; a grid without an expanded group is one run
    /// (``GridSection``).
    public let sections: [GridSection]

    /// The grid's cells in the photos' order (PRD P0-03).
    public var cells: [GridCellItem] { sections.flatMap(\.cells) }

    /// Builds the cells for the photos a filter and an order produced (PRD P0-03, P0-11).
    ///
    /// - Parameters:
    ///   - photos: The shown photos, in grid order; a photo that is not here never gets a cell.
    ///   - groups: The groups grouping published, empty when it published none (PRD P0-11).
    ///   - groupsEnabled: Similar groups setting; off hides the badges and covers
    ///     (PRD Grid, P0-11).
    ///   - display: C12's grid group display; expanded is the launch default (PRD Grid).
    ///   - expandedGroup: The group to expand in place instead of drawing its cover, or nil.
    ///     Only a collapsed display has a cover to replace, so an expanded display ignores it.
    ///
    /// A photo that two groups name, which grouping does not publish, is marked with the first
    /// group in `groups` order so a cell never belongs to two groups.
    public init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        groupsEnabled: Bool = true,
        display: GridGroupDisplay = .expanded,
        expandedGroup: GroupID? = nil
    ) {
        let marked = groupsEnabled ? Self.marksByPhoto(photos: photos, groups: groups) : [:]
        switch (groupsEnabled, display) {
        case (true, .expanded):
            self.sections = [
                GridSection(
                    id: .photos(0), cells: Self.expandedCells(photos: photos, marks: marked))
            ]
        case (true, .collapsed):
            self.sections = Self.collapsedSections(
                photos: photos, marks: marked, expandedGroup: expandedGroup)
        case (false, _):
            self.sections = [
                GridSection(
                    id: .photos(0),
                    cells: photos.map {
                        GridCellItem(id: .photo($0.id), photo: $0, isDimmed: $0.marks.isRejected)
                    })
            ]
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

    /// Collapsed display keeps each group's first shown position, with the first non-rejected
    /// shown member as cover. All-rejected groups use the first shown member and are dimmed.
    /// A group whose members the filter hid has no cover, because the grid never shows a cell
    /// that names no photo it can draw (PRD P0-03).
    ///
    /// `expandedGroup` replaces one group's cover with its shown members at that same position
    /// (owner decision, 2026-11-13, #225). The members become their own run, so the split can
    /// draw the group's header and its members' shared surface around them while every other
    /// cell keeps its place. Their marks carry no count badge: the run's header names the group.
    private static func collapsedSections(
        photos: [GridPhoto], marks: [PhotoIdentity: BrowsingGroup], expandedGroup: GroupID?
    ) -> [GridSection] {
        var shownByGroup: [GroupID: [GridPhoto]] = [:]
        for photo in photos {
            if let group = marks[photo.id] {
                shownByGroup[group.id, default: []].append(photo)
            }
        }
        var covered: Set<GroupID> = []
        var before: [GridCellItem] = []
        var members: [GridCellItem] = []
        var after: [GridCellItem] = []
        for photo in photos {
            guard let group = marks[photo.id] else {
                let cell = GridCellItem(
                    id: .photo(photo.id), photo: photo, isDimmed: photo.marks.isRejected)
                if members.isEmpty { before.append(cell) } else { after.append(cell) }
                continue
            }
            if group.id == expandedGroup {
                members.append(
                    GridCellItem(
                        id: .photo(photo.id), photo: photo,
                        group: GridCellItem.GroupMark(
                            id: group.id, count: group.members.count, showsCount: false,
                            isCover: false),
                        isDimmed: photo.marks.isRejected))
                continue
            }
            guard covered.insert(group.id).inserted else { continue }
            let shown = shownByGroup[group.id] ?? [photo]
            let cover = shown.first { !$0.marks.isRejected } ?? photo
            let peeking = Self.peekingPhotos(cover: cover.id, shown: shown, group: group)
            let cell = GridCellItem(
                id: .group(group.id),
                photo: cover,
                group: GridCellItem.GroupMark(
                    id: group.id, count: group.members.count, showsCount: true,
                    isCover: true, peekingPhotos: peeking),
                isDimmed: shown.allSatisfy { $0.marks.isRejected })
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

    /// Up to two member identities to peek behind a collapsed group cover, preferring shown
    /// members in grid order and falling back to remaining group members when filtered.
    public static func peekingPhotos(
        cover: PhotoIdentity, shown: [GridPhoto], group: BrowsingGroup
    ) -> [PhotoIdentity] {
        let limit = min(2, max(0, group.members.count - 1))
        guard limit > 0 else { return [] }
        var result: [PhotoIdentity] = []
        for candidate in shown where candidate.id != cover {
            result.append(candidate.id)
            if result.count == limit { return result }
        }
        for candidate in group.members where candidate != cover && !result.contains(candidate) {
            result.append(candidate)
            if result.count == limit { return result }
        }
        return result
    }
}
