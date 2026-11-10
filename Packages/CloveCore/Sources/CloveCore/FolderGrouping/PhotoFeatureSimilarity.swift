import Foundation

/// What one photo contributes to a boundary comparison (PRD Similar groups step 3).
///
/// The three cases keep G1's fallback apart from pending work: a photo whose feature work has not
/// settled yet leaves its boundaries provisional, a photo whose work settled without a usable
/// feature splits them for good, and two settled features answer with one distance.
public enum PhotoFeatureState<Feature: Sendable>: Sendable {
    /// The photo's feature work has not settled, so its boundaries stay provisional
    /// (PRD Similar groups step 3: refinement runs in the background).
    case pending

    /// The photo's work settled with two features that can be compared.
    case features(Feature)

    /// The photo's work settled without a feature either kind can use, so its boundaries split
    /// (G1's Grouping row: with no usable feature, split).
    case unavailable
}

/// Answers grouping's adjacent-boundary questions from the features settled for a folder's
/// photos (PRD Similar groups step 3, G1's Grouping row).
///
/// `CloveCore` carries no Vision or CoreGraphics types, so the app keeps I3's record as an opaque
/// `Feature` and supplies the one comparison that turns two records into G1's answer; the two
/// kinds stay in `CloveImaging`, and the thresholds stay in C9. This type owns the two rules that
/// belong to grouping rather than to the feature pipeline:
///
/// - A photo whose feature work has not settled keeps its boundaries provisional
///   (``PhotoSimilarity/notReady``), so C9's next refinement pass asks again.
/// - A photo whose work settled without a usable feature splits its boundaries for good
///   (``PhotoSimilarity/unavailable``), which is G1's "with no usable feature, split".
///
/// The caller starts a folder's photos as pending and then settles each one as its result
/// arrives, so the result never depends on the order the answers land in.
public actor PhotoFeatureSimilarity<Feature: Sendable>: PhotoSimilarityProviding {
    /// The photos started for the current folder, so a photo outside the folder stays pending.
    private var states: [PhotoIdentity: PhotoFeatureState<Feature>] = [:]

    /// The one comparison the app, which owns the feature type, supplies. Nil means neither of
    /// G1's kinds can compare the pair, which is a final split.
    private let comparison: @Sendable (Feature, Feature) -> PhotoSimilarity?

    /// Creates the source over the comparison of two settled feature records.
    public init(comparison: @escaping @Sendable (Feature, Feature) -> PhotoSimilarity?) {
        self.comparison = comparison
    }

    /// Starts a folder's photos as pending and drops every earlier photo.
    ///
    /// Run again and a changed setting restart feature work, so the source starts from the new
    /// input instead of keeping an answer that belonged to the earlier photos.
    public func start(photos: [PhotoIdentity]) {
        states = [:]
        for photo in photos { states[photo] = .pending }
    }

    /// Records what one photo's feature work settled on.
    ///
    /// A photo this run did not start is ignored, so a result left over from an earlier pass or
    /// another folder cannot enter the current one.
    public func settle(_ state: PhotoFeatureState<Feature>, for photo: PhotoIdentity) {
        guard states[photo] != nil else { return }
        states[photo] = state
    }

    /// One boundary's answer, from the two photos' settled features (PRD Similar groups step 3).
    ///
    /// A photo this run never started is pending, because nothing is known about it yet.
    public func similarity(
        between left: GroupingPhoto,
        and right: GroupingPhoto
    ) async -> PhotoSimilarity {
        switch (states[left.id], states[right.id]) {
        case (.unavailable, _), (_, .unavailable):
            return .unavailable
        case (.features(let leftFeature), .features(let rightFeature)):
            return comparison(leftFeature, rightFeature) ?? .unavailable
        default:
            return .notReady
        }
    }
}
