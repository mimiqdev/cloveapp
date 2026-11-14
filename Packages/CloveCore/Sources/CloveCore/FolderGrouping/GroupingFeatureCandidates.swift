import Foundation

/// The photos whose features grouping's step 3 has to compare (PRD Similar groups step 3).
///
/// A feature costs a preview read and a Vision pass per photo, and G1's Grouping row measures it
/// per photo, so the app asks for features only where a group can form. C9's own step-1–2 rules
/// already say which those are: a photo that shares a time run with a neighbour. Every other
/// photo can never enter a group, so its features would be spent on nothing.
public enum GroupingFeatureCandidates {
    /// The photos of `photos` that sit in a time run with at least one neighbour.
    ///
    /// The answer follows C9's separation by body and capture time and its time gap, so the
    /// candidates are exactly the photos some boundary can ask about. Photos with a fallback time
    /// or no camera body are never candidates, because they are never grouped (G1 decision 3,
    /// G1's Grouping row).
    public static func photos(
        in photos: [GroupingPhoto],
        thresholds: GroupingThresholds = .standard
    ) -> [GroupingPhoto] {
        GroupingRuns.runs(for: photos, timeGap: thresholds.timeGap).flatMap { $0 }
    }

    /// The candidate time-runs of `photos` that have at least one neighbour, ordered by each
    /// run's earliest photo in grid order so earlier visible bursts settle first.
    public static func runs(
        in photos: [GroupingPhoto],
        thresholds: GroupingThresholds = .standard
    ) -> [[GroupingPhoto]] {
        GroupingRuns.runs(for: photos, timeGap: thresholds.timeGap).sorted { left, right in
            guard let firstLeft = left.first, let firstRight = right.first else {
                return !left.isEmpty && right.isEmpty
            }
            return GroupingRuns.gridPrecedes(firstLeft, firstRight)
        }
    }
}
