import Foundation

/// Grouping for one open folder: time-only groups first, then refinement by visual similarity
/// (PRD P0-11, PRD Similar groups, G1's Grouping row).
///
/// The actor holds the folder's inputs, the groups it last published and the boundary answers
/// gathered so far, so the whole state is Sendable without a lock. The app drives it in two
/// steps:
///
/// 1. ``run(photos:revision:similarGroupsEnabled:reuseCache:)`` separates bodies, orders by
///    capture time and publishes step 2's time-only groups, or the cache's finished result.
/// 2. ``refine()`` asks the provider about every boundary that has no final answer yet and
///    publishes once the pass changes something. Calling it as features arrive moves a folder
///    from time-only to partly refined to refined (PRD Similar groups step 3).
///
/// Every published value is delivered through ``updates()``. Groups keep their ID while their
/// membership overlaps the earlier result, so refinement and Run again do not make the viewed
/// photo jump; after a split the caller asks ``SimilarGroups/group(containing:)`` where the
/// photo went (PRD P0-11).
///
/// Grouping reads only the values it is given. It never writes a mark, a sidecar or an XMP
/// packet (PRD P0-11, PRD Similar groups rules); its only output besides memory is
/// ``SimilarGroupsCache``'s file in Clove's app-private storage.
public actor SimilarGrouping {
    /// The feature source for step 3; the app wires I3 behind it (PRD Similar groups step 3).
    private let similarity: any PhotoSimilarityProviding
    /// G1's starting thresholds (G1 Grouping row).
    private let thresholds: GroupingThresholds
    /// Clove's own group cache, or nil when the caller keeps no cache (PRD Similar groups rules).
    private let cache: SimilarGroupsCache?

    /// The folder's photos, one per identity, as last supplied.
    private var inputs: [GroupingPhoto] = []
    /// The inputs' revision, part of the cache key for what the fingerprint cannot see.
    private var revision = GroupingInputRevision(rawValue: "")
    /// The grouper's own digest of the eligible inputs, part of the cache key.
    private var inputFingerprint = GroupingInputFingerprint.digest(of: [])
    /// Whether similar groups are turned on (PRD P0-11, `AppSettings.similarGroupsEnabled`).
    private var isEnabled = true
    /// Incremented by every run, so a refinement pass that a later run superseded stops.
    private var generation = 0
    /// Step 2's runs, each with at least two photos (PRD Similar groups steps 1–2).
    private var timeRuns: [[GroupingPhoto]] = []
    /// Every boundary answer gathered so far, by adjacent pair.
    private var decisions: [GroupingBoundaryKey: GroupingBoundaryDecision] = [:]
    /// The last finished assignment, used to keep a group's ID while its membership overlaps.
    private var ancestry: [PhotoIdentity: GroupID] = [:]
    /// The last finished group order, the tiebreak when two ancestors overlap a new group.
    private var ancestryOrder: [GroupID: Int] = [:]
    /// The open folder, when the inputs agree on one; the cache is per folder identity.
    private var folder: FolderIdentity?
    /// The last published value, available without waiting for the stream.
    private var published: SimilarGroups = .off
    /// Whether the published result is the cache's finished answer, which needs no refinement.
    private var cacheIsAuthoritative = false
    /// Everyone observing published values, keyed so a finished stream can be removed.
    private var observers: [UUID: AsyncStream<SimilarGroups>.Continuation] = [:]

    /// Creates the grouper over a similarity source and, optionally, Clove's group cache.
    public init(
        similarity: any PhotoSimilarityProviding,
        thresholds: GroupingThresholds = .standard,
        cache: SimilarGroupsCache? = nil
    ) {
        self.similarity = similarity
        self.thresholds = thresholds
        self.cache = cache
    }

    /// The last published groups and progress (PRD P0-11).
    public var current: SimilarGroups { published }

    /// Every published value, starting with the current one (PRD P0-11).
    ///
    /// The grid wraps this stream in its own state; nothing here is a UI type. Each element is
    /// a complete result, so a slow observer may see fewer intermediate states but never a
    /// partial one.
    public func updates() -> AsyncStream<SimilarGroups> {
        let (stream, continuation) = AsyncStream.makeStream(of: SimilarGroups.self)
        let id = UUID()
        observers[id] = continuation
        continuation.yield(published)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    /// Replaces the folder's inputs and publishes step 2's groups (PRD Similar groups steps 1–2).
    ///
    /// Call with the scanner's current photos and a revision token for anything the photos
    /// themselves do not show, such as a feature or file revision; the grouper fingerprints
    /// the eligible photos so a missed input change cannot restore a stale result. Opening a
    /// folder uses `reuseCache: true`, which publishes the cache's finished result when the
    /// revision, fingerprint and thresholds still match. Run again (PRD Similar groups rules,
    /// P0-11) passes `reuseCache: false` so the current inputs are recomputed; group IDs stay
    /// put through the ancestry of the last finished result.
    ///
    /// When `similarGroupsEnabled` is false the grouper publishes no groups, does no work and
    /// leaves the cache alone; turning similar groups back on starts from the cache or a fresh
    /// run (PRD P0-11).
    public func run(
        photos: [GroupingPhoto],
        revision: GroupingInputRevision,
        similarGroupsEnabled: Bool = true,
        reuseCache: Bool = true
    ) async {
        generation += 1
        isEnabled = similarGroupsEnabled
        self.revision = revision
        inputs = GroupingRuns.distinct(photos)
        inputFingerprint = GroupingInputFingerprint.digest(of: inputs)
        folder = sharedFolder(of: inputs)
        decisions = [:]
        cacheIsAuthoritative = false
        timeRuns = []

        guard isEnabled else {
            published = .off
            emit()
            return
        }

        if reuseCache, let cache, let folder,
            let groups = cache.load(
                folderID: folder,
                revision: revision,
                fingerprint: inputFingerprint,
                thresholds: thresholds,
                photos: inputs)
        {
            cacheIsAuthoritative = true
            ancestry = Self.assignment(of: groups)
            ancestryOrder = Self.order(of: groups)
            published = SimilarGroups(groups: groups, analysis: .analyzed)
            emit()
            return
        }

        timeRuns = GroupingRuns.runs(for: inputs, timeGap: thresholds.timeGap)
        publish()
    }

    /// One refinement pass over every boundary without a final answer (PRD Similar groups
    /// step 3).
    ///
    /// The pass asks the provider once per unsettled adjacent pair, applies the G1 rule and
    /// publishes a new result when anything changed. A pair the provider reports as not ready
    /// stays provisional, so call again as features arrive; the final result does not depend
    /// on the order answers arrive in. Nothing happens while similar groups are off, while the
    /// cache's finished result is showing, or for a run a later ``run(photos:revision:
    /// similarGroupsEnabled:reuseCache:)`` superseded.
    public func refine() async {
        guard isEnabled, !cacheIsAuthoritative else { return }
        let generation = self.generation
        var changed = false
        for run in timeRuns {
            for index in run.indices.dropFirst() {
                let left = run[index - 1]
                let right = run[index]
                let key = GroupingBoundaryKey(left: left.id, right: right.id)
                if decisions[key]?.verdict.isSettled == true { continue }
                let answer = await similarity.similarity(between: left, and: right)
                guard generation == self.generation else { return }
                let decision = GroupingBoundaryRule.decision(for: answer, thresholds: thresholds)
                if decisions[key] != decision {
                    decisions[key] = decision
                    changed = true
                }
            }
        }
        if changed { publish() }
    }

    // MARK: - Publishing

    /// Builds the current groups, allocates their IDs and publishes them.
    private func publish() {
        let candidates = GroupingRuns.candidateGroups(timeRuns: timeRuns, decisions: decisions)
            .sorted {
                guard let left = $0.photos.first, let right = $1.photos.first else {
                    return !$0.photos.isEmpty && $1.photos.isEmpty
                }
                return GroupingRuns.gridPrecedes(left, right)
            }
        let groups = allocateIDs(for: candidates)
        let analysis = analysisState()
        published = SimilarGroups(groups: groups, analysis: analysis)
        emit()
        guard analysis == .analyzed else { return }
        ancestry = Self.assignment(of: groups)
        ancestryOrder = Self.order(of: groups)
        if let cache, let folder {
            cache.save(
                groups,
                folderID: folder,
                revision: revision,
                fingerprint: inputFingerprint,
                thresholds: thresholds)
        }
    }

    /// The folder's progress: every boundary inside a time run counts, split or not
    /// (PRD Similar groups rules: "Show analysis progress or Analyzed").
    private func analysisState() -> GroupAnalysis {
        var total = 0
        var decided = 0
        for run in timeRuns {
            for index in run.indices.dropFirst() {
                total += 1
                let key = GroupingBoundaryKey(left: run[index - 1].id, right: run[index].id)
                if decisions[key]?.verdict.isSettled == true { decided += 1 }
            }
        }
        if total == 0 || decided == total { return .analyzed }
        if decided == 0 { return .timeOnly }
        return .refining(decided: decided, total: total)
    }

    /// Gives each group its stable ID (PRD P0-11).
    ///
    /// A new group takes the ID of the finished group it overlaps most, so a group keeps its
    /// key through refinement and Run again; when two new groups overlap one finished group
    /// equally, the earlier one in grid order keeps it and the other takes a fresh key. A group
    /// with no finished ancestor takes a key derived from its earliest member, which is why IDs
    /// also stay put while a first analysis splits a folder that had no finished result yet.
    private func allocateIDs(for candidates: [GroupingCandidateGroup]) -> [SimilarGroup] {
        var groups: [SimilarGroup] = []
        var claimed: Set<GroupID> = []
        for candidate in candidates {
            let inherited = inheritedID(for: candidate, claimed: claimed)
            let id = inherited ?? freshID(seed: candidate.photos[0].id, claimed: claimed)
            claimed.insert(id)
            groups.append(
                SimilarGroup(
                    id: id,
                    members: candidate.photos.map(\.id),
                    refinement: candidate.refinement,
                    usedFallbackSimilarity: candidate.usedFallback))
        }
        return groups
    }

    /// The unclaimed ancestor ID most of the candidate's members belonged to.
    private func inheritedID(
        for candidate: GroupingCandidateGroup,
        claimed: Set<GroupID>
    ) -> GroupID? {
        var overlaps: [GroupID: Int] = [:]
        for photo in candidate.photos {
            guard let ancestor = ancestry[photo.id], !claimed.contains(ancestor) else { continue }
            overlaps[ancestor, default: 0] += 1
        }
        return overlaps.max { left, right in
            if left.value != right.value { return left.value < right.value }
            let leftOrder = ancestryOrder[left.key] ?? Int.max
            let rightOrder = ancestryOrder[right.key] ?? Int.max
            if leftOrder != rightOrder { return leftOrder > rightOrder }
            return left.key.rawValue > right.key.rawValue
        }?.key
    }

    /// A new key derived from the earliest member, kept unique among the current groups.
    private func freshID(seed: PhotoIdentity, claimed: Set<GroupID>) -> GroupID {
        let base =
            seed.relativeFolderPath.isEmpty
            ? seed.stem : "\(seed.relativeFolderPath)/\(seed.stem)"
        let taken = claimed.union(Set(ancestry.values))
        var raw = "group:\(base)"
        var suffix = 2
        while taken.contains(GroupID(rawValue: raw)) {
            raw = "group:\(base)#\(suffix)"
            suffix += 1
        }
        return GroupID(rawValue: raw)
    }

    /// Hands the published value to every observer.
    private func emit() {
        for continuation in observers.values { continuation.yield(published) }
    }

    /// Drops a finished stream, so a closed observer holds no memory of the grouper.
    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    // MARK: - Derived state

    /// The one folder every input belongs to, or nil when the inputs are empty or mixed.
    private func sharedFolder(of photos: [GroupingPhoto]) -> FolderIdentity? {
        guard let first = photos.first else { return nil }
        let folder = first.id.folderID
        return photos.allSatisfy { $0.id.folderID == folder } ? folder : nil
    }

    /// Every member's group, ready to become the next run's ancestry.
    private static func assignment(of groups: [SimilarGroup]) -> [PhotoIdentity: GroupID] {
        var assignment: [PhotoIdentity: GroupID] = [:]
        for group in groups {
            for photo in group.members { assignment[photo] = group.id }
        }
        return assignment
    }

    /// Every group's place in grid order, the tiebreak between two overlapping ancestors.
    private static func order(of groups: [SimilarGroup]) -> [GroupID: Int] {
        var order: [GroupID: Int] = [:]
        for (index, group) in groups.enumerated() { order[group.id] = index }
        return order
    }
}
