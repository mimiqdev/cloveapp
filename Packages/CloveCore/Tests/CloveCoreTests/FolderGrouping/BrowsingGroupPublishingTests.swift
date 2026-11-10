import Foundation
import Testing

import CloveCore

/// How grouping's published result reaches the browsing screens (PRD P0-11, PRD P0-14).
@Suite("Similar groups as browsing groups")
struct BrowsingGroupPublishingTests {
    /// Two bursts far enough apart to be two time runs, in grid order.
    private var photos: [GroupingPhoto] {
        [
            groupingPhoto("burst_a", at: 0),
            groupingPhoto("burst_b", at: 0.4),
            groupingPhoto("later_a", at: 100),
            groupingPhoto("later_b", at: 100.4),
        ]
    }

    @Test func keepsGridOrderKeysAndMembers() async {
        let photos = photos
        let similarity = ScriptedSimilarity()
        await similarity.answerAll(.vision(distance: 0.2), between: [photos[0], photos[1]])
        await similarity.answerAll(.vision(distance: 0.2), between: [photos[2], photos[3]])

        let result = await groupingRun(photos, using: similarity)
        let mapped = result.browsingGroups

        // Grid order is each group's earliest member, and a group's members keep capture order
        // (PRD P0-03, PRD P0-11).
        #expect(mapped.map(\.members) == [photos[0...1].map(\.id), photos[2...3].map(\.id)])
        // The group keys are grouping's own, never re-keyed on the way to the grid (P0-11).
        #expect(mapped.map(\.id) == result.groups.map(\.id))
    }

    @Test func keepsAGroupsKeyWhenARefinementSplitsIt() async {
        let photos = [
            groupingPhoto("a", at: 0),
            groupingPhoto("b", at: 0.4),
            groupingPhoto("c", at: 0.8),
        ]
        let similarity = ScriptedSimilarity()
        await similarity.answerAll(.vision(distance: 0.2), between: photos)
        let grouping = SimilarGrouping(similarity: similarity)
        let revision = GroupingInputRevision(rawValue: "published-groups")
        await grouping.run(photos: photos, revision: revision)
        await grouping.refine()
        let joined = await grouping.current.browsingGroups
        #expect(joined.count == 1)

        // The second boundary now splits, as a later refinement pass would decide it.
        await similarity.answer(.vision(distance: 0.9), for: photos[1], photos[2])
        await grouping.run(photos: photos, revision: revision, reuseCache: false)
        await grouping.refine()

        let split = await grouping.current.browsingGroups
        // The split leaves a two-photo group; a one-photo group is not published (P0-11 rules).
        #expect(split.count == 1)
        // The surviving group keeps the key it had, so a grid cell does not move (P0-11).
        #expect(split.first?.id == joined.first?.id)
        #expect(split.first?.members == [photos[0].id, photos[1].id])
    }
}
