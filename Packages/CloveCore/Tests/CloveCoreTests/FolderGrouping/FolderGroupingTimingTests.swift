import Foundation
import Testing

import CloveCore

/// Reports what this task adds on top of C9's own timings on macOS: the time stage, the cost of
/// settling one photo's features while it runs, and one refinement pass asked through the real
/// similarity source (PRD P0-11, PRD Similar groups steps 2–3). It informs only, so it asserts no
/// threshold; the real preview and Vision cost per photo is I3's own timing test, and the app's
/// numbers come from the device checklist.
@Suite("Folder grouping timing")
struct FolderGroupingTimingTests {
    @Test(.timeLimit(.minutes(5)))
    func oneThousandPhotosThroughTheSimilaritySourceTimingIsInformational() async {
        let total = 1_000
        let photos = (0..<total).map { index in
            groupingPhoto(
                String(format: "MMQ%05d", index), at: Double(index) * 0.4,
                fileName: String(format: "MMQ%05d.ARW", index))
        }
        // One feature per photo, close enough to its neighbour to stay in the group.
        let source = PhotoFeatureSimilarity<Float> { left, right in
            .vision(distance: abs(left - right))
        }
        let grouping = SimilarGrouping(similarity: source)

        let timeOnlyStart = ContinuousClock.now
        await grouping.run(
            photos: photos, revision: GroupingInputRevision(rawValue: "timing"))
        let timeOnly = milliseconds(timeOnlyStart.duration(to: .now))

        await source.start(photos: photos.map(\.id))
        let featureStart = ContinuousClock.now
        for (index, photo) in photos.enumerated() {
            await source.settle(.features(Float(index) / Float(total)), for: photo.id)
        }
        let features = milliseconds(featureStart.duration(to: .now))

        let refinementStart = ContinuousClock.now
        await grouping.refine()
        let refinement = milliseconds(refinementStart.duration(to: .now))

        let refined = await grouping.current
        #expect(refined.analysis == .analyzed)
        #expect(refined.groups.count == 1)
        #expect(refined.groups.first?.count == total)

        print(
            String(
                format: """
                    Similar groups through the similarity source (macOS, %d photos):
                      time stage:            %.1f ms
                      settling features:     %.1f ms total, %.1f µs per photo
                      one refinement pass:   %.1f ms over %d boundaries, %.1f µs per boundary
                    """, total, timeOnly, features, features * 1_000 / Double(total), refinement,
                total - 1, refinement * 1_000 / Double(total - 1)))
    }
}
