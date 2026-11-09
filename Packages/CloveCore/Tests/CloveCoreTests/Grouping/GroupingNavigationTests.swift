import Foundation
import Testing

import CloveCore

/// PRD P0-11 and C10: the caller asks which group holds a photo, and the groups are navigable
/// in grid order.
@Test func groupContainingFindsOnlyGroupedPhotos() async throws {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("lonely", at: 30),
    ]

    let result = await groupingRun(photos, using: scripted)

    let group = try #require(result.group(containing: photos[0].id))
    #expect(groupingStems(group) == ["a", "b"])
    #expect(result.group(containing: photos[2].id) == nil)
    #expect(result.group(with: group.id) == group)
}

/// PRD P0-11: next and previous group follow the grid, which orders groups by their earliest
/// member across camera bodies and time.
@Test func nextAndPreviousGroupFollowGridOrder() async throws {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("body-b-1", at: 0.1, model: "Canon EOS R6"),
        groupingPhoto("body-a-1", at: 0.0),
        groupingPhoto("body-b-2", at: 0.3, model: "Canon EOS R6"),
        groupingPhoto("body-a-2", at: 0.2),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["body-a-1", "body-a-2"], ["body-b-1", "body-b-2"]])
    let first = try #require(result.group(containing: photos[1].id))
    let second = try #require(result.group(containing: photos[0].id))
    #expect(result.nextGroup(after: photos[1].id) == second)
    #expect(result.nextGroup(after: photos[0].id) == nil)
    #expect(result.previousGroup(before: photos[0].id) == first)
    #expect(result.previousGroup(before: photos[1].id) == nil)
    #expect(result.nextGroup(after: photos[2].id) == nil)
}

@Test func aPhotoOutsideEveryGroupHasNoNeighbours() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("ungrouped", at: 40),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(result.nextGroup(after: photos[2].id) == nil)
    #expect(result.previousGroup(before: photos[2].id) == nil)
}

@Test func membersKeepCaptureOrderInsideTheGroup() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("third", at: 0.4),
        groupingPhoto("first", at: 0),
        groupingPhoto("second", at: 0.2),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["first", "second", "third"]])
}
