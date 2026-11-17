/// One published group resolved against the currently visible and ordered photos.
///
/// Grouping publishes clusters across the whole folder; under an active filter or sort order,
/// only groups with at least two visible members remain active as groups, and their visible
/// members preserve the active grid order (issue #304, decision 2).
public struct ActiveBrowsingGroup: Identifiable, Hashable, Sendable {
    /// The published group this active group corresponds to.
    public let group: BrowsingGroup

    /// Visible members in the active grid order (`browsing.photos`); always at least two.
    public let visibleMembers: [GridPhoto]

    /// The unified Representative Photo used for grid cover, filmstrip cover, Timeline landing,
    /// and Group Focus initial entry / collapse target.
    public let representative: GridPhoto

    public var id: GroupID { group.id }

    /// How many visible members are still unmarked.
    public var unmarkedCount: Int {
        visibleMembers.count { $0.marks.isUnmarked }
    }

    public init(group: BrowsingGroup, visibleMembers: [GridPhoto], representative: GridPhoto) {
        self.group = group
        self.visibleMembers = visibleMembers
        self.representative = representative
    }
}

extension BrowsingGroup {
    /// Unified Representative Photo rule (issue #304, decision 2):
    /// 1. Highest star rating (`rating > .unrated`; ties broken by first in `visibleMembers`)
    /// 2. First non-rejected member with a non-clear colour label
    /// 3. First unmarked member
    /// 4. First visible member (when all visible members are rejected)
    public static func representative(of visibleMembers: [GridPhoto]) -> GridPhoto? {
        var bestRated: GridPhoto?
        for member in visibleMembers where member.marks.rating > .unrated {
            if let current = bestRated {
                if member.marks.rating > current.marks.rating {
                    bestRated = member
                }
            } else {
                bestRated = member
            }
        }
        if let bestRated { return bestRated }
        if let labelled = visibleMembers.first(where: {
            !$0.marks.isRejected && !$0.marks.label.isClear
        }) {
            return labelled
        }
        if let unmarked = visibleMembers.first(where: { $0.marks.isUnmarked }) {
            return unmarked
        }
        return visibleMembers.first
    }

    /// Resolves published groups against `orderedPhotos`, preserving `orderedPhotos` order and
    /// keeping only groups with at least two visible members.
    public static func resolveVisibleGroups(
        in orderedPhotos: [GridPhoto],
        groups: [BrowsingGroup]
    ) -> (byGroupID: [GroupID: ActiveBrowsingGroup], byPhotoID: [PhotoIdentity: GroupID]) {
        let shownIDs = Set(orderedPhotos.map(\.id))
        var publishedByPhoto: [PhotoIdentity: BrowsingGroup] = [:]
        for group in groups {
            for member in group.members
            where shownIDs.contains(member) && publishedByPhoto[member] == nil {
                publishedByPhoto[member] = group
            }
        }
        var membersByGroup: [GroupID: [GridPhoto]] = [:]
        var groupOrder: [BrowsingGroup] = []
        var seenGroups: Set<GroupID> = []
        for photo in orderedPhotos {
            guard let group = publishedByPhoto[photo.id] else { continue }
            membersByGroup[group.id, default: []].append(photo)
            if seenGroups.insert(group.id).inserted {
                groupOrder.append(group)
            }
        }
        var activeByGroupID: [GroupID: ActiveBrowsingGroup] = [:]
        var activeByPhotoID: [PhotoIdentity: GroupID] = [:]
        for group in groupOrder {
            guard let visible = membersByGroup[group.id], visible.count >= 2,
                let rep = representative(of: visible)
            else { continue }
            activeByGroupID[group.id] = ActiveBrowsingGroup(
                group: group, visibleMembers: visible, representative: rep)
            for member in visible {
                activeByPhotoID[member.id] = group.id
            }
        }
        return (activeByGroupID, activeByPhotoID)
    }
}

/// One slot on Detail's Timeline level: either a standalone photo (including a group narrowed to
/// 1 visible member) or a collapsed multi-photo group stack.
public enum TimelineSlot: Identifiable, Hashable, Sendable {
    case photo(GridPhoto)
    case group(ActiveBrowsingGroup)

    public var id: GridCellItem.ID {
        switch self {
        case .photo(let photo): .photo(photo.id)
        case .group(let active): .group(active.id)
        }
    }

    /// The photo shown on the stage when Timeline navigation lands on this slot.
    public var stagePhoto: GridPhoto {
        switch self {
        case .photo(let photo): photo
        case .group(let active): active.representative
        }
    }

    public var activeGroup: ActiveBrowsingGroup? {
        guard case .group(let active) = self else { return nil }
        return active
    }

    public func contains(_ photoID: PhotoIdentity) -> Bool {
        switch self {
        case .photo(let photo): photo.id == photoID
        case .group(let active): active.visibleMembers.contains { $0.id == photoID }
        }
    }

    /// Whether `.nextUnmarkedPhoto` treats this slot as still having unmarked work: an unmarked
    /// standalone photo, or a group stack containing at least one visible unmarked member.
    public var isUnmarkedForAdvance: Bool {
        switch self {
        case .photo(let photo): photo.marks.isUnmarked
        case .group(let active): active.visibleMembers.contains { $0.marks.isUnmarked }
        }
    }
}

/// The two-level Detail model: ordered Timeline slots, active multi-photo groups, and pure
/// navigation / auto-advance resolution for both Timeline and Group Focus levels (issue #304).
public struct DetailTimeline: Hashable, Sendable {
    public let slots: [TimelineSlot]
    public let activeGroups: [GroupID: ActiveBrowsingGroup]
    private let groupByPhoto: [PhotoIdentity: GroupID]

    public init(photos: [GridPhoto], groups: [BrowsingGroup], groupsEnabled: Bool = true) {
        guard groupsEnabled else {
            self.slots = photos.map { .photo($0) }
            self.activeGroups = [:]
            self.groupByPhoto = [:]
            return
        }
        let resolved = BrowsingGroup.resolveVisibleGroups(in: photos, groups: groups)
        self.activeGroups = resolved.byGroupID
        self.groupByPhoto = resolved.byPhotoID
        var covered: Set<GroupID> = []
        var result: [TimelineSlot] = []
        result.reserveCapacity(photos.count)
        for photo in photos {
            if let groupID = resolved.byPhotoID[photo.id],
                let active = resolved.byGroupID[groupID]
            {
                if covered.insert(groupID).inserted {
                    result.append(.group(active))
                }
            } else {
                result.append(.photo(photo))
            }
        }
        self.slots = result
    }

    public func activeGroup(with id: GroupID) -> ActiveBrowsingGroup? {
        activeGroups[id]
    }

    public func activeGroup(containing photoID: PhotoIdentity) -> ActiveBrowsingGroup? {
        groupByPhoto[photoID].flatMap { activeGroups[$0] }
    }

    public func slotIndex(containing photoID: PhotoIdentity) -> Int? {
        slots.firstIndex { $0.contains(photoID) }
    }

    public func slotIndex(forGroup groupID: GroupID) -> Int? {
        slots.firstIndex { $0.id == .group(groupID) }
    }

    /// Stage photos in Timeline slot order (each standalone photo or each stack's representative).
    public var stagePhotos: [GridPhoto] {
        slots.map(\.stagePhoto)
    }

    /// Active visible order for Detail: `visibleMembers` when in Group Focus, or `stagePhotos`
    /// when in Timeline.
    public func stageOrder(expandedGroup: GroupID?) -> [GridPhoto] {
        if let expandedGroup, let active = activeGroup(with: expandedGroup) {
            return active.visibleMembers
        }
        return stagePhotos
    }

    /// Horizontal step (`-1` or `+1`) within the active level without wrapping or crossing levels.
    public func steppedPhoto(
        from photoID: PhotoIdentity,
        offset: Int,
        expandedGroup: GroupID?
    ) -> PhotoIdentity? {
        if let expandedGroup, let active = activeGroup(with: expandedGroup) {
            let members = active.visibleMembers
            guard let index = members.firstIndex(where: { $0.id == photoID }) else { return nil }
            let target = index + offset
            guard members.indices.contains(target) else { return nil }
            return members[target].id
        }
        guard let index = slotIndex(containing: photoID) else { return nil }
        let target = index + offset
        guard slots.indices.contains(target) else { return nil }
        return slots[target].stagePhoto.id
    }

    /// Resolves Timeline or Group Focus auto-advance before the incoming mark mutates state.
    public func autoAdvancePlan(
        after kind: MarkKind,
        change: MarkChange,
        from photoID: PhotoIdentity,
        expandedGroup: GroupID?,
        rules: MarkingInputRules
    ) -> AutoAdvancePlan {
        let stay = AutoAdvancePlan(target: .stay, markedPhoto: photoID)
        guard rules.settings.autoAdvance.shouldAdvance(after: kind) else { return stay }

        if let expandedGroup, let active = activeGroup(with: expandedGroup) {
            let members = active.visibleMembers
            let hadUnmarkedBefore = members.contains { $0.marks.isUnmarked }
            let destination = rules.settings.autoAdvance.destination

            if !hadUnmarkedBefore {
                // Second-pass review (0 unmarked members before the mark): never auto-collapse or eject.
                guard destination == .nextPhoto,
                    let index = members.firstIndex(where: { $0.id == photoID }),
                    index + 1 < members.count
                else { return stay }
                return AutoAdvancePlan(
                    target: .groupUndecidedPhoto(members[index + 1].id), markedPhoto: photoID)
            }

            // First-pass culling: stay keeps the user on this photo inside Group Focus.
            guard destination != .stay else { return stay }

            guard let index = members.firstIndex(where: { $0.id == photoID }) else { return stay }
            let updatedMarks = members[index].marks.applying(change)
            let searchOrder = members.dropFirst(index + 1) + members.prefix(index)
            if let nextUnmarked = searchOrder.first(where: { $0.marks.isUnmarked }) {
                return AutoAdvancePlan(
                    target: .groupUndecidedPhoto(nextUnmarked.id), markedPhoto: photoID)
            }
            // Clearing a mark back to unmarked leaves this photo unmarked inside the group.
            if updatedMarks.isUnmarked {
                return stay
            }
            return exitGroupPlan(
                groupID: active.id, from: photoID, destination: destination)
        }

        // Timeline mode (expandedGroup == nil): standalone photo (or < 2 visible group).
        guard activeGroup(containing: photoID) == nil,
            let slotIndex = slotIndex(containing: photoID)
        else { return stay }
        switch rules.settings.autoAdvance.destination {
        case .stay:
            return stay
        case .nextPhoto:
            let nextIndex = slotIndex + 1
            guard slots.indices.contains(nextIndex) else { return stay }
            return AutoAdvancePlan(
                target: .nextPhoto(slots[nextIndex].stagePhoto.id), markedPhoto: photoID)
        case .nextUnmarkedPhoto:
            guard
                let nextSlot = slots.dropFirst(slotIndex + 1).first(where: {
                    $0.isUnmarkedForAdvance
                })
            else { return stay }
            return AutoAdvancePlan(
                target: .nextUnmarkedPhoto(nextSlot.stagePhoto.id), markedPhoto: photoID)
        }
    }

    /// Resolves `"Reject {k} unmarked"` auto-advance from Group Focus.
    public func finishingAdvancePlan(
        groupID: GroupID,
        from photoID: PhotoIdentity,
        rules: MarkingInputRules
    ) -> AutoAdvancePlan {
        let stay = AutoAdvancePlan(target: .stay, markedPhoto: photoID)
        guard rules.settings.autoAdvance.shouldAdvance(after: .reject) else { return stay }
        let destination = rules.settings.autoAdvance.destination
        guard destination != .stay else { return stay }
        return exitGroupPlan(groupID: groupID, from: photoID, destination: destination)
    }

    private func exitGroupPlan(
        groupID: GroupID,
        from photoID: PhotoIdentity,
        destination: AutoAdvanceDestination
    ) -> AutoAdvancePlan {
        guard let slotIndex = slotIndex(forGroup: groupID) else {
            return AutoAdvancePlan(target: .stay, markedPhoto: photoID, exitsGroupFocus: true)
        }
        switch destination {
        case .stay:
            return AutoAdvancePlan(target: .stay, markedPhoto: photoID)
        case .nextPhoto:
            let nextIndex = slotIndex + 1
            guard slots.indices.contains(nextIndex) else {
                return AutoAdvancePlan(target: .stay, markedPhoto: photoID, exitsGroupFocus: true)
            }
            return AutoAdvancePlan(
                target: .nextPhoto(slots[nextIndex].stagePhoto.id), markedPhoto: photoID,
                exitsGroupFocus: true)
        case .nextUnmarkedPhoto:
            guard
                let nextSlot = slots.dropFirst(slotIndex + 1).first(where: {
                    $0.isUnmarkedForAdvance
                })
            else {
                return AutoAdvancePlan(target: .stay, markedPhoto: photoID, exitsGroupFocus: true)
            }
            return AutoAdvancePlan(
                target: .nextUnmarkedPhoto(nextSlot.stagePhoto.id), markedPhoto: photoID,
                exitsGroupFocus: true)
        }
    }
}

/// Symmetric vertical drag thresholds on Detail's filmstrip (issue #304, decision 5).
public enum FilmstripVerticalGesture: Sendable {
    public static let minimumVerticalDistance: Double = 24
    public static let dominanceRatio: Double = 1.5

    /// Upward vertical-dominant drag starting on a collapsed group stack in Timeline mode.
    public static func shouldExpand(horizontal: Double, vertical: Double) -> Bool {
        vertical <= -minimumVerticalDistance && abs(vertical) > dominanceRatio * abs(horizontal)
    }

    /// Downward vertical-dominant drag anywhere on the strip in Group Focus mode.
    public static func shouldCollapse(horizontal: Double, vertical: Double) -> Bool {
        vertical >= minimumVerticalDistance && abs(vertical) > dominanceRatio * abs(horizontal)
    }
}
