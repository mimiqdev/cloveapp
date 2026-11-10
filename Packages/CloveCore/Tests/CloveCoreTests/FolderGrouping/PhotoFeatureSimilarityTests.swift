import Foundation
import Testing

import CloveCore

/// How C9's boundary questions are answered from settled features (PRD Similar groups step 3,
/// G1's Grouping row).
@Suite("Photo feature similarity")
struct PhotoFeatureSimilarityTests {
    /// A feature source whose record is a number: the fake's "distance" is the difference.
    ///
    /// A negative record stands for a feature neither kind can compare, so the test can check the
    /// final split without inventing a second feature type.
    private func source() -> PhotoFeatureSimilarity<Float> {
        PhotoFeatureSimilarity<Float> { left, right in
            guard left >= 0, right >= 0 else { return nil }
            return .vision(distance: abs(left - right))
        }
    }

    /// A pair of adjacent photos in one time run.
    private var adjacentPair: (left: GroupingPhoto, right: GroupingPhoto) {
        (groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.4))
    }

    @Test func reportsTheDistanceBetweenSettledFeatures() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id, pair.right.id])
        await source.settle(.features(0.25), for: pair.left.id)
        await source.settle(.features(0.5), for: pair.right.id)

        let answer = await source.similarity(between: pair.left, and: pair.right)

        #expect(answer == .vision(distance: 0.25))
    }

    @Test func keepsABoundaryProvisionalUntilBothFeaturesSettle() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id, pair.right.id])
        await source.settle(.features(0.25), for: pair.left.id)

        let first = await source.similarity(between: pair.left, and: pair.right)
        // Once the second settles, the next refinement pass gets the real answer.
        await source.settle(.features(0.4), for: pair.right.id)
        let second = await source.similarity(between: pair.left, and: pair.right)

        #expect(first == .notReady)
        #expect(second == .vision(distance: 0.15))
    }

    @Test func splitsForGoodWhenAPhotoHasNoUsableFeature() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id, pair.right.id])
        await source.settle(.features(0.25), for: pair.left.id)
        await source.settle(.unavailable, for: pair.right.id)

        let answer = await source.similarity(between: pair.left, and: pair.right)

        // G1's Grouping row: with no usable feature, split, and the answer is final.
        #expect(answer == .unavailable)
    }

    @Test func splitsWhenTheFeaturesHaveNoComparableKind() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id, pair.right.id])
        await source.settle(.features(-1), for: pair.left.id)
        await source.settle(.features(-1), for: pair.right.id)

        let answer = await source.similarity(between: pair.left, and: pair.right)

        #expect(answer == .unavailable)
    }

    @Test func keepsAPhotoOutsideTheFolderPending() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id])
        await source.settle(.features(0.25), for: pair.left.id)
        // A result for a photo this run never started cannot settle it.
        await source.settle(.features(0.25), for: pair.right.id)

        let answer = await source.similarity(between: pair.left, and: pair.right)

        #expect(answer == .notReady)
    }

    @Test func startingAgainDropsTheEarlierFeatures() async {
        let source = source()
        let pair = adjacentPair
        await source.start(photos: [pair.left.id, pair.right.id])
        await source.settle(.features(0.25), for: pair.left.id)
        await source.settle(.features(0.5), for: pair.right.id)
        // Run again starts over, so the earlier pass's answers must not leak into the new one.
        await source.start(photos: [pair.left.id, pair.right.id])

        let answer = await source.similarity(between: pair.left, and: pair.right)

        #expect(answer == .notReady)
    }
}
