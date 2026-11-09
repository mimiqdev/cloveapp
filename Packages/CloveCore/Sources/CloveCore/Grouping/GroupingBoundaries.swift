import Foundation

/// One adjacent pair inside a time run, in capture-time order (PRD Similar groups steps 2–3).
struct GroupingBoundaryKey: Hashable, Sendable {
    /// The earlier photo of the pair.
    let left: PhotoIdentity
    /// The later photo of the pair.
    let right: PhotoIdentity
}

/// What one boundary does to the time run that contains it (PRD Similar groups step 3).
enum GroupingBoundaryVerdict: Hashable, Sendable {
    /// The two photos belong in one group.
    case joined
    /// The later photo starts a new group.
    case split
    /// The pair has no answer yet, so it stays joined provisionally while time-only groups show
    /// (PRD Similar groups step 3: refinement moves the result from time-only to refined).
    case unsettled

    /// Whether the answer is final; only ``unsettled`` is asked again.
    var isSettled: Bool { self != .unsettled }
}

/// One boundary's verdict plus how it was reached, for evaluation (G1's dHash fallback).
struct GroupingBoundaryDecision: Hashable, Sendable {
    /// What the boundary does to its time run.
    let verdict: GroupingBoundaryVerdict
    /// Whether the answer came from the dHash fallback rather than Vision (G1 Grouping row).
    let usedFallback: Bool

    /// The state of a boundary no answer has reached yet.
    static let unsettled = GroupingBoundaryDecision(verdict: .unsettled, usedFallback: false)
}

/// Turns a provider's answer into a boundary decision (G1's Grouping row, PRD Similar groups
/// step 3).
///
/// The rule is G1's: a Vision distance at or below 0.5 joins, a larger one splits; only when
/// Vision has no usable feature a dHash distance at or below 12 bits joins; with no usable
/// feature at all the boundary splits; and a feature that is not ready yet leaves the boundary
/// provisional. A non-finite or negative distance is not a usable feature, so it splits.
enum GroupingBoundaryRule {
    /// The decision one similarity answer produces under `thresholds`.
    static func decision(
        for similarity: PhotoSimilarity,
        thresholds: GroupingThresholds
    ) -> GroupingBoundaryDecision {
        switch similarity {
        case .vision(let distance):
            guard distance.isFinite, distance >= 0 else {
                return GroupingBoundaryDecision(verdict: .split, usedFallback: false)
            }
            let verdict: GroupingBoundaryVerdict =
                distance <= thresholds.visionDistance ? .joined : .split
            return GroupingBoundaryDecision(verdict: verdict, usedFallback: false)
        case .differenceHash(let distance):
            let verdict: GroupingBoundaryVerdict =
                distance >= 0 && distance <= thresholds.hashDistance ? .joined : .split
            return GroupingBoundaryDecision(verdict: verdict, usedFallback: true)
        case .unavailable:
            return GroupingBoundaryDecision(verdict: .split, usedFallback: false)
        case .notReady:
            return .unsettled
        }
    }
}
