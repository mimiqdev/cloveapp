import Foundation
import Testing

import CloveCore

/// PRD P0-11: similar groups can be turned off. Off means no groups and no work; turning them
/// back on starts from the cache or a fresh run.
@Test func turnedOffThereAreNoGroupsAndNoWork() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    let grouper = SimilarGrouping(similarity: scripted)

    await grouper.run(
        photos: photos,
        revision: GroupingInputRevision(rawValue: "revision-1"),
        similarGroupsEnabled: false)
    await grouper.refine()

    let result = await grouper.current
    #expect(result.groups.isEmpty)
    #expect(result.analysis == .off)
    #expect(await scripted.askCount == 0)
}

@Test func turningBackOnStartsAfresh() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    let grouper = SimilarGrouping(similarity: scripted)

    await grouper.run(
        photos: photos,
        revision: GroupingInputRevision(rawValue: "revision-1"),
        similarGroupsEnabled: false)
    await grouper.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    await grouper.refine()

    #expect(groupingStems(await grouper.current) == [["a", "b"]])
    #expect(await grouper.current.analysis == .analyzed)
}

@Test func turningBackOnUsesTheCacheWhenTheFolderWasAlreadyAnalyzed() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    let grouper = SimilarGrouping(similarity: scripted, cache: cache)
    let revision = GroupingInputRevision(rawValue: "revision-1")

    await grouper.run(photos: photos, revision: revision)
    await grouper.refine()
    let analyzed = await grouper.current
    let asksAfterAnalyzing = await scripted.askCount

    await grouper.run(photos: photos, revision: revision, similarGroupsEnabled: false)
    #expect(await grouper.current.analysis == .off)

    await grouper.run(photos: photos, revision: revision)
    #expect(await grouper.current == analyzed)
    #expect(await scripted.askCount == asksAfterAnalyzing)
}

@Test func theUpdatesStreamStartsWithTheOffState() async {
    let grouper = SimilarGrouping(similarity: ScriptedSimilarity())
    var updates = await grouper.updates().makeAsyncIterator()

    let first = await updates.next()

    #expect(first?.analysis == .off)
    #expect(first?.groups.isEmpty == true)
}
