import Foundation
import Testing

import CloveCore

/// Reports what grouping costs on macOS for 2,000 photos with an instant feature source
/// (PRD P0-11 and Similar groups; G1's Grouping row). It informs only, so it asserts no
/// threshold: the numbers are recorded in the pull request, not used as a gate.
@Test func groupingTwoThousandPhotosTimingIsInformational() async {
    let total = 2_000
    let photos = (0..<total).map { index in
        groupingPhoto(
            String(format: "DSC_%05d", index),
            at: Double(index) * 0.4,
            fileName: String(format: "DSC_%05d.ARW", index))
    }
    let featureSource = InstantSimilarity(answer: .vision(distance: 0.1))
    let grouper = SimilarGrouping(similarity: featureSource)

    let timeOnlyStart = ContinuousClock.now
    await grouper.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "timing"))
    let timeOnly = milliseconds(timeOnlyStart.duration(to: .now))
    let timeOnlyGroups = await grouper.current

    let refinementStart = ContinuousClock.now
    await grouper.refine()
    let refinement = milliseconds(refinementStart.duration(to: .now))
    let refined = await grouper.current

    #expect(timeOnlyGroups.analysis == .timeOnly)
    #expect(timeOnlyGroups.groups.first?.count == total)
    #expect(refined.analysis == .analyzed)
    #expect(refined.groups.first?.count == total)

    print(
        String(
            format: "Similar groups: macOS 2,000 photos, time-only %.1f ms, "
                + "full refinement %d boundaries %.1f ms (informational)",
            timeOnly, total - 1, refinement))
}
