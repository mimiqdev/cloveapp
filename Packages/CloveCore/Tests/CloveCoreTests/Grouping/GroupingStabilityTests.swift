import Foundation
import Testing

import CloveCore

/// PRD P0-11: group IDs survive refinement. The fragment with the earlier photos keeps the ID,
/// and the caller can ask which group now holds the viewed photo after a split.
@Test func aGroupKeepsItsIDThroughRefinementAndTheSplitIsReported() async throws {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
        groupingPhoto("e", at: 0.8),
    ]
    let grouper = SimilarGrouping(similarity: scripted)
    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))

    let timeOnly = await grouper.current
    let originalID = try #require(timeOnly.group(containing: photos[0].id)?.id)
    #expect(timeOnly.groups.count == 1)
    #expect(timeOnly.group(containing: photos[3].id)?.id == originalID)

    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.1), for: photos[1], photos[2])
    await scripted.answer(.vision(distance: 0.9), for: photos[2], photos[3])
    await scripted.answer(.vision(distance: 0.1), for: photos[3], photos[4])
    await grouper.refine()

    let refined = await grouper.current
    #expect(groupingStems(refined) == [["a", "b", "c"], ["d", "e"]])
    #expect(refined.group(containing: photos[0].id)?.id == originalID)
    #expect(refined.group(containing: photos[1].id)?.id == originalID)
    let newGroup = try #require(refined.group(containing: photos[3].id))
    #expect(newGroup.id != originalID)
    #expect(groupingStems(newGroup) == ["d", "e"])
}

/// PRD P0-11 and Similar groups rules: Run again is always available and keeps IDs where the
/// membership overlaps.
@Test func runAgainKeepsIDsWhereMembershipOverlaps() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
    ]
    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.9), for: photos[1], photos[2])
    await scripted.answer(.vision(distance: 0.1), for: photos[2], photos[3])
    let grouper = SimilarGrouping(similarity: scripted)
    let revision = GroupingInputRevision(rawValue: "revision-1")
    await grouper.run(photos: photos, revision: revision)
    await grouper.refine()

    let first = await grouper.current
    #expect(groupingStems(first) == [["a", "b"], ["c", "d"]])
    let firstIDs = first.groups.map(\.id)

    await grouper.run(photos: photos, revision: revision, reuseCache: false)
    await grouper.refine()
    let second = await grouper.current

    #expect(second == first)
    #expect(second.groups.map(\.id) == firstIDs)
}

/// PRD P0-11: after a split or a regroup the caller is told which group holds the viewed photo,
/// so the viewed photo does not jump.
@Test func runAgainFollowsThePhotoThatMovedToTheOtherFragment() async throws {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
        groupingPhoto("e", at: 0.8),
    ]
    let grouper = SimilarGrouping(similarity: scripted)
    let revision = GroupingInputRevision(rawValue: "revision-1")
    await grouper.run(photos: photos, revision: revision)
    let timeOnlyID = try #require(await grouper.current.group(containing: photos[3].id)?.id)

    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.1), for: photos[1], photos[2])
    await scripted.answer(.vision(distance: 0.9), for: photos[2], photos[3])
    await scripted.answer(.vision(distance: 0.1), for: photos[3], photos[4])
    await grouper.refine()
    let splitID = try #require(await grouper.current.group(containing: photos[3].id)?.id)
    #expect(splitID != timeOnlyID)

    // Run again republishes one time-only group first, so the caller looking at d is told it is
    // back in the earlier group, then the same split returns it to its own group.
    await grouper.run(photos: photos, revision: revision, reuseCache: false)
    #expect(await grouper.current.group(containing: photos[3].id)?.id == timeOnlyID)
    await grouper.refine()
    #expect(await grouper.current.group(containing: photos[3].id)?.id == splitID)
}

/// PRD P0-11: an overlapping group keeps its ID even when its earliest member left the folder,
/// so a photo that stays in the group never changes group.
@Test func aGroupKeepsItsIDWhenAnEarlierMemberLeaves() async throws {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
    ]
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    let grouper = SimilarGrouping(similarity: scripted)
    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    await grouper.refine()
    let originalID = try #require(
        await grouper.current.group(containing: photos[2].id)?.id)

    // a leaves the folder; b, c and d stay and still overlap the finished group.
    await grouper.run(
        photos: Array(photos[1...]),
        revision: GroupingInputRevision(rawValue: "revision-2"),
        reuseCache: false)
    await grouper.refine()

    let result = await grouper.current
    #expect(groupingStems(result) == [["b", "c", "d"]])
    #expect(result.group(containing: photos[2].id)?.id == originalID)
}
