import Foundation

/// One boundary's similarity answer, as the feature provider reports it (G1's Grouping row).
///
/// A boundary consults exactly one answer, so the kinds are never mixed: the provider returns
/// a Vision distance when Vision produced one, the dHash distance only when Vision has no
/// usable feature for that pair, and otherwise says that no feature exists or that it is not
/// ready yet. PRD Similar groups step 3 and G1 decide what each answer means.
public enum PhotoSimilarity: Hashable, Sendable {
    /// A Vision feature-print distance between the two photos (PRD Similar groups step 3).
    /// Values at or below ``GroupingThresholds/maximumVisionDistance`` join; larger ones split.
    case vision(distance: Float)

    /// A difference-hash bit distance, reported only when Vision has no usable feature
    /// (PRD Similar groups step 3). Values at or below
    /// ``GroupingThresholds/maximumHashDistance`` join; larger ones split.
    case differenceHash(distance: Int)

    /// No usable feature exists for the pair, so the final result splits the boundary
    /// (PRD Similar groups step 3). This answer is final.
    case unavailable

    /// The feature is still being computed, so the boundary stays provisional and is asked
    /// again on a later refinement pass (PRD Similar groups step 3: refinement runs in the
    /// background and moves the result from time-only to refined).
    case notReady
}

/// Supplies adjacent-boundary similarity to grouping (PRD Similar groups step 3).
///
/// The app wires I3's image features behind this protocol, so C9 never imports `CloveImaging`
/// and tests supply fake distances. Implementations may compute features anywhere; grouping
/// only awaits one answer per adjacent pair and re-asks unresolved ones on later passes.
///
/// The contract keeps the fallback identifiable for evaluation:
/// - return ``PhotoSimilarity/notReady`` while a feature is still being computed;
/// - return ``PhotoSimilarity/unavailable`` only when no feature will ever exist, which is a
///   final split (PRD Similar groups step 3);
/// - return a `differenceHash` distance only when Vision cannot answer for that pair.
public protocol PhotoSimilarityProviding: Sendable {
    /// The similarity of two photos that are adjacent in a time run (PRD Similar groups step 3).
    /// The pair's order is the capture-time order, so `left` is the earlier photo.
    func similarity(between left: GroupingPhoto, and right: GroupingPhoto) async -> PhotoSimilarity
}
