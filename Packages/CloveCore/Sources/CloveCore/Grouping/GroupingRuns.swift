import Foundation

/// One group being built from a time run, before it gets a stable ID (PRD P0-11).
struct GroupingCandidateGroup: Sendable {
    /// Members in capture-time order.
    let photos: [GroupingPhoto]
    /// How far refinement has gone for this group (PRD Similar groups step 3).
    let refinement: SimilarGroupRefinement
    /// Whether any joined boundary inside the group used the dHash fallback (G1 Grouping row).
    let usedFallback: Bool
}

/// Pure steps 1–2 of PRD Similar groups: eligibility, body buckets, ordering and time gaps.
///
/// Nothing here reads a file or a feature, so the time-only groups are ready as soon as the
/// metadata is (PRD Similar groups step 2). Step 3's splits arrive later as boundary decisions
/// and are applied by ``candidateGroups(timeRuns:decisions:)``.
enum GroupingRuns {
    /// One photo per identity, because C1's identity is what a photo is (PRD P0-01).
    /// A repeated identity keeps the last value supplied, so the result never depends on which
    /// duplicate happened to be visited first.
    static func distinct(_ photos: [GroupingPhoto]) -> [GroupingPhoto] {
        var byIdentity: [PhotoIdentity: GroupingPhoto] = [:]
        for photo in photos { byIdentity[photo.id] = photo }
        return Array(byIdentity.values)
    }

    /// The time runs of PRD Similar groups steps 1–2, each with at least two photos.
    ///
    /// Photos are separated by camera body first, then ordered by capture instant with
    /// subseconds and the numeric-aware file name for ties, then split where the gap between
    /// neighbours is not strictly less than `timeGap`. A run of one photo is not a group.
    static func runs(for photos: [GroupingPhoto], timeGap: TimeInterval) -> [[GroupingPhoto]] {
        var byBody: [CameraBody: [GroupingPhoto]] = [:]
        for photo in photos where photo.isEligibleForGrouping {
            guard let body = photo.body else { continue }
            byBody[body, default: []].append(photo)
        }
        var runs: [[GroupingPhoto]] = []
        for body in byBody.keys.sorted(by: bodyPrecedes) {
            let ordered = byBody[body, default: []].sorted(by: captureTimePrecedes)
            var run: [GroupingPhoto] = []
            for photo in ordered {
                if let previous = run.last, let gap = gap(from: previous, to: photo), gap >= timeGap
                {
                    appendRun(&runs, run)
                    run = []
                }
                run.append(photo)
            }
            appendRun(&runs, run)
        }
        return runs
    }

    /// The groups the current boundary decisions produce from the time runs (PRD step 3).
    ///
    /// A split starts a new group at the later photo; joined and unsettled boundaries stay
    /// together, so time-only groups keep showing while features arrive. Groups below two
    /// photos are dropped (PRD Similar groups rules).
    static func candidateGroups(
        timeRuns: [[GroupingPhoto]],
        decisions: [GroupingBoundaryKey: GroupingBoundaryDecision]
    ) -> [GroupingCandidateGroup] {
        var candidates: [GroupingCandidateGroup] = []
        for run in timeRuns {
            var members: [GroupingPhoto] = []
            for photo in run {
                if let previous = members.last {
                    let key = GroupingBoundaryKey(left: previous.id, right: photo.id)
                    if decisions[key]?.verdict == .split {
                        appendCandidate(&candidates, members, decisions: decisions)
                        members = []
                    }
                }
                members.append(photo)
            }
            appendCandidate(&candidates, members, decisions: decisions)
        }
        return candidates
    }

    /// Orders groups the way the grid orders their earliest member (PRD P0-03, P0-11).
    ///
    /// The key matches ``PhotoOrdering``'s capture-time order, so next and previous group follow
    /// the photo the grid is showing: instant, relative folder path, file name, then identity.
    static func gridPrecedes(_ lhs: GroupingPhoto, _ rhs: GroupingPhoto) -> Bool {
        guard let left = lhs.instant, let right = rhs.instant else { return false }
        if left != right { return left < right }
        if lhs.id.relativeFolderPath != rhs.id.relativeFolderPath {
            return lhs.id.relativeFolderPath < rhs.id.relativeFolderPath
        }
        if lhs.fileName != rhs.fileName { return lhs.fileName < rhs.fileName }
        return identityPrecedes(lhs.id, rhs.id)
    }

    /// Step 1's order inside one body: capture instant, then the numeric-aware file name,
    /// then identity so the order is total (PRD Similar groups step 1).
    /// The comparison is locale-independent, unlike a localized sort.
    static func captureTimePrecedes(_ lhs: GroupingPhoto, _ rhs: GroupingPhoto) -> Bool {
        guard let left = lhs.instant, let right = rhs.instant else { return false }
        if left != right { return left < right }
        let names = lhs.fileName.compare(rhs.fileName, options: [.numeric, .literal])
        if names != .orderedSame { return names == .orderedAscending }
        return identityPrecedes(lhs.id, rhs.id)
    }

    /// A deterministic body order, so building the runs never depends on dictionary order.
    private static func bodyPrecedes(_ lhs: CameraBody, _ rhs: CameraBody) -> Bool {
        if lhs.model != rhs.model { return lhs.model < rhs.model }
        return (lhs.serial ?? "") < (rhs.serial ?? "")
    }

    /// The gap in seconds between two adjacent photos, in either direction.
    private static func gap(from earlier: GroupingPhoto, to later: GroupingPhoto) -> TimeInterval? {
        guard let left = earlier.instant, let right = later.instant else { return nil }
        return right.timeIntervalSince(left)
    }

    /// Keeps a run only when it has at least two photos (PRD Similar groups rules).
    private static func appendRun(_ runs: inout [[GroupingPhoto]], _ run: [GroupingPhoto]) {
        if run.count >= 2 { runs.append(run) }
    }

    /// Keeps a candidate only when it has at least two photos, and records its refinement state.
    private static func appendCandidate(
        _ candidates: inout [GroupingCandidateGroup],
        _ photos: [GroupingPhoto],
        decisions: [GroupingBoundaryKey: GroupingBoundaryDecision]
    ) {
        guard photos.count >= 2 else { return }
        var settled = 0
        var usedFallback = false
        for index in photos.indices.dropFirst() {
            let key = GroupingBoundaryKey(left: photos[index - 1].id, right: photos[index].id)
            guard let decision = decisions[key] else { continue }
            if decision.verdict == .joined {
                settled += 1
                usedFallback = usedFallback || decision.usedFallback
            }
        }
        let refinement: SimilarGroupRefinement
        if settled == 0 {
            refinement = .timeOnly
        } else if settled == photos.count - 1 {
            refinement = .refined
        } else {
            refinement = .partlyRefined
        }
        candidates.append(
            GroupingCandidateGroup(
                photos: photos, refinement: refinement, usedFallback: usedFallback))
    }

    /// A total identity order, so two distinct photos never compare equal (PRD P0-01 keys).
    static func identityPrecedes(_ lhs: PhotoIdentity, _ rhs: PhotoIdentity) -> Bool {
        if lhs.folderID != rhs.folderID { return lhs.folderID.rawValue < rhs.folderID.rawValue }
        if lhs.relativeFolderPath != rhs.relativeFolderPath {
            return lhs.relativeFolderPath < rhs.relativeFolderPath
        }
        return lhs.stem < rhs.stem
    }
}
