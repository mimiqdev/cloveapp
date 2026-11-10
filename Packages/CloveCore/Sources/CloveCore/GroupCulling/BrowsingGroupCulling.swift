/// In-group culling over the group the browsing screens hold (PRD In-group culling; PRD P0-12).
///
/// Grouping publishes its result in two shapes. The grid, the group view and restore validation
/// read ``BrowsingGroup``: a stable key and the member order (PRD P0-11, P0-14). C10's culling
/// rules take ``SimilarGroup``, the grouping result, and read the same two facts from it. The
/// conversion below keeps one group view reading the value it already holds instead of building a
/// second copy of the grouping result, and it fills the two fields in-group culling never reads:
/// how far refinement has gone and whether a join used the fallback similarity. Browsing publishes
/// neither, and no culling rule may depend on them.
extension BrowsingGroup {
    /// The group as C10's culling rules read it (PRD In-group culling).
    ///
    /// The refinement marker is the time-only stage, which is the state grouping's first
    /// publication has for every group; browsing does not carry the later progress, and
    /// in-group culling never reads it (PRD Similar groups step 3).
    var cullingGroup: SimilarGroup {
        SimilarGroup(
            id: id, members: members, refinement: .timeOnly, usedFallbackSimilarity: false)
    }
}

extension GroupPhotoNavigation {
    /// Builds the navigation for one published group (PRD In-group culling; PRD P0-12).
    ///
    /// Undecided only, the next and previous rules and the next undecided photo are C10's; this
    /// only supplies the group the browsing screens hold.
    public init(group: BrowsingGroup, undecidedOnly: Bool = false) {
        self.init(group: group.cullingGroup, undecidedOnly: undecidedOnly)
    }
}

extension GroupCompletionTracker {
    /// The next published group in grid order that is not complete, skipping completed ones
    /// (PRD In-group culling, group completion; PRD P0-12).
    ///
    /// The completion definition and the search are C10's
    /// (``GroupCompletionTracker/nextIncompleteGroup(after:in:marks:)``); this supplies the
    /// groups the browsing screens hold and answers with the published group, so the group view
    /// never keeps a second copy of the rule. Only the analysis marker differs: browsing does not
    /// publish refinement progress, and no completion rule reads it.
    public func nextIncompleteGroup(
        after groupID: GroupID,
        in groups: [BrowsingGroup],
        marks: [PhotoIdentity: PhotoMarks]
    ) -> BrowsingGroup? {
        let published = SimilarGroups(groups: groups.map(\.cullingGroup), analysis: .timeOnly)
        guard let next = nextIncompleteGroup(after: groupID, in: published, marks: marks) else {
            return nil
        }
        return groups.first { $0.id == next.id }
    }
}

extension GroupFinishingPlan {
    /// Plans one finishing action for one published group (PRD In-group culling; PRD P0-12).
    ///
    /// The rules stay C10's: the current photo's keep change, the never-reject-a-marked-photo
    /// rule and the availability of each action are all decided by ``GroupFinishingPlan`` itself.
    public init(
        group: BrowsingGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks],
        enabledRatings: EnabledRatings
    ) {
        self.init(
            group: group.cullingGroup, action: action, currentPhoto: currentPhoto, marks: marks,
            enabledRatings: enabledRatings)
    }
}
