import Foundation

/// A similar group's stable key (PRD P0-11: group IDs survive refinement and Run again).
///
/// The value is opaque to callers. A group keeps the ID it had before a refinement or a
/// Run again when its membership overlaps the earlier group (see ``SimilarGrouping``); a new
/// group takes an ID derived from its earliest member. Nothing is written to XMP: the ID lives
/// only in Clove's memory and, for a finished folder, in Clove's group cache (PRD Similar
/// groups rules).
public struct GroupID: RawRepresentable, Hashable, Sendable {
    /// The opaque key. Its spelling is an implementation detail and may change.
    public let rawValue: String

    /// Wraps a key read back from the group cache.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How far refinement has gone for one group (PRD Similar groups step 3, P0-11).
///
/// The grid shows "Analyzed" only once a group is ``refined``; ``SimilarGroups/analysis``
/// reports the same progress for the whole folder.
public enum SimilarGroupRefinement: Hashable, Sendable {
    /// Step 2's published groups: no boundary inside the group has an answer yet.
    case timeOnly
    /// Some internal boundaries are decided and others are still provisional.
    case partlyRefined
    /// Every internal boundary has a final answer, so the group is the refined result.
    case refined
}

/// One published group of photos that belong together (PRD P0-11, PRD Similar groups).
///
/// A group always holds at least two photos (PRD Similar groups rules) and never holds the
/// same photo twice. It carries no marks and no file URLs: C10 and the grid look those up by
/// identity. Grouping never writes or changes a mark (PRD P0-11, PRD Similar groups rules).
public struct SimilarGroup: Identifiable, Hashable, Sendable {
    /// The stable key this group keeps through refinement and Run again (PRD P0-11).
    public let id: GroupID

    /// Members in capture-time order, the order the group view and C10 move through (PRD
    /// Similar groups step 1).
    public let members: [PhotoIdentity]

    /// How far refinement has gone for this group's internal boundaries (PRD step 3).
    public let refinement: SimilarGroupRefinement

    /// Whether a joined boundary inside this group used the dHash fallback (G1 Grouping row).
    ///
    /// G1 keeps fallback results identifiable for evaluation, because dHash is a provisional
    /// degraded mode rather than an equivalent replacement for Vision.
    public let usedFallbackSimilarity: Bool

    /// Builds one published group; only grouping creates these, in membership order.
    init(
        id: GroupID,
        members: [PhotoIdentity],
        refinement: SimilarGroupRefinement,
        usedFallbackSimilarity: Bool
    ) {
        self.id = id
        self.members = members
        self.refinement = refinement
        self.usedFallbackSimilarity = usedFallbackSimilarity
    }

    /// How many photos the group holds, for the grid's collapsed count (PRD Grid).
    public var count: Int { members.count }

    /// Whether this group holds one photo (PRD P0-11).
    public func contains(_ photo: PhotoIdentity) -> Bool {
        members.contains(photo)
    }
}
