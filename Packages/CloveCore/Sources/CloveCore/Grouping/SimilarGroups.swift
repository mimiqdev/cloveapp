import Foundation

/// How far grouping has got through PRD Similar groups step 3 (PRD Similar groups rules:
/// "Show analysis progress or Analyzed").
public enum GroupAnalysis: Hashable, Sendable {
    /// Similar groups are turned off, so there is no progress to show (PRD P0-11).
    case off
    /// Step 2's groups are published and no boundary has an answer yet (PRD Similar
    /// groups step 3).
    case timeOnly
    /// Some boundaries are decided and others are still being computed.
    case refining(decided: Int, total: Int)
    /// Every boundary has a final answer, so the folder's groups are the refined result.
    case analyzed

    /// Whether refinement finished, so the grid can show Analyzed (PRD Similar groups rules).
    public var isAnalyzed: Bool { self == .analyzed }
}

/// One published grouping of an open folder: the groups and the progress behind them
/// (PRD P0-11, PRD Similar groups).
///
/// The value is `Sendable` and holds no UI types, so the grid can wrap it in whatever state it
/// observes. Groups are ordered the way the grid is, by each group's earliest member, and a
/// group's members keep capture-time order, so next and previous group follow the visible photo
/// (PRD P0-03). ``group(containing:)`` is how the caller finds the group that holds the viewed
/// photo after a split or a regroup, so the viewed photo does not jump (P0-11).
public struct SimilarGroups: Hashable, Sendable {
    /// No groups because similar groups are turned off (PRD P0-11).
    public static let off = SimilarGroups(groups: [], analysis: .off)

    /// The groups in grid order, each with at least two members (PRD Similar groups rules).
    public let groups: [SimilarGroup]

    /// How far refinement has gone for the folder (PRD Similar groups rules).
    public let analysis: GroupAnalysis

    /// The group index of every member, so a lookup by photo is one step.
    private let indexByPhoto: [PhotoIdentity: Int]

    /// Builds one published value; only grouping creates these, from ordered groups.
    init(groups: [SimilarGroup], analysis: GroupAnalysis) {
        self.groups = groups
        self.analysis = analysis
        var indexByPhoto: [PhotoIdentity: Int] = [:]
        for (index, group) in groups.enumerated() {
            for photo in group.members { indexByPhoto[photo] = index }
        }
        self.indexByPhoto = indexByPhoto
    }

    /// Whether the folder has no group to show; single photos are never groups (PRD P0-11).
    public var isEmpty: Bool { groups.isEmpty }

    /// The group holding one photo, or nil when the photo is not grouped.
    ///
    /// After a split or a regroup this is how the caller learns which group now holds the
    /// viewed photo, so navigation does not jump (PRD P0-11).
    public func group(containing photo: PhotoIdentity) -> SimilarGroup? {
        guard let index = indexByPhoto[photo] else { return nil }
        return groups[index]
    }

    /// The group with one stable key, or nil when it is not part of this result.
    public func group(with id: GroupID) -> SimilarGroup? {
        groups.first { $0.id == id }
    }

    /// The group after the one holding `photo`, in grid order, or nil at the last group
    /// (PRD P0-11; C10 advances to the next group).
    ///
    /// A photo that is not grouped has no place in the group order, so the answer is nil.
    public func nextGroup(after photo: PhotoIdentity) -> SimilarGroup? {
        guard let index = indexByPhoto[photo], index + 1 < groups.count else { return nil }
        return groups[index + 1]
    }

    /// The group before the one holding `photo`, in grid order, or nil at the first group
    /// (PRD P0-11).
    ///
    /// A photo that is not grouped has no place in the group order, so the answer is nil.
    public func previousGroup(before photo: PhotoIdentity) -> SimilarGroup? {
        guard let index = indexByPhoto[photo], index > 0 else { return nil }
        return groups[index - 1]
    }

    /// Two results are equal when their groups and progress are; the lookup index is derived.
    public static func == (lhs: SimilarGroups, rhs: SimilarGroups) -> Bool {
        lhs.groups == rhs.groups && lhs.analysis == rhs.analysis
    }

    /// Hashes only the groups and progress, matching ``==``.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(groups)
        hasher.combine(analysis)
    }
}
