/// In-group culling over the group the browsing screens hold (PRD In-group culling; PRD P0-12).
///
/// Grouping publishes its result in two shapes. The grid and detail
/// read ``BrowsingGroup``: a stable key and the member order (PRD P0-11, P0-14). C10's culling
/// rules take ``SimilarGroup``, the grouping result, and read the same two facts from it. The
/// conversion below keeps detail reading the value it already holds instead of building a
/// second copy of the grouping result, and it fills the two fields in-group culling never reads:
/// how far refinement has gone and whether a join used the fallback similarity. Browsing publishes
/// neither, and no culling rule may depend on them.
extension BrowsingGroup {
    /// The members the current grid filter shows, retaining the published group identity.
    public func visible(in photos: Set<PhotoIdentity>) -> BrowsingGroup {
        BrowsingGroup(id: id, members: members.filter { photos.contains($0) })
    }

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
    /// Builds navigation for one published group.
    public init(group: BrowsingGroup) {
        self.init(group: group.cullingGroup)
    }
}

extension GroupFinishingPlan {
    /// Plans one finishing action for one published group (PRD In-group culling; PRD P0-12).
    ///
    /// Availability and protection of marked photos are decided by ``GroupFinishingPlan``.
    public init(
        group: BrowsingGroup,
        action: GroupFinishingAction,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks]
    ) {
        self.init(
            group: group.cullingGroup, action: action, currentPhoto: currentPhoto, marks: marks)
    }
}
