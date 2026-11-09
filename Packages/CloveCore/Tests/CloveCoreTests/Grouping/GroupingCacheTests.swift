import Foundation
import Testing

import CloveCore

/// PRD Similar groups rules: groups are cached only in Clove, so a reopened folder shows its
/// finished groups without asking for features again.
@Test func aFinishedResultRoundTripsThroughTheCache() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.9), for: photos[1], photos[2])
    await scripted.answer(.vision(distance: 0.1), for: photos[2], photos[3])

    let first = await groupingRun(photos, using: scripted, cache: cache)
    #expect(first.analysis == .analyzed)
    #expect(try folder.entries().count == 1)

    let coldFeatureSource = ScriptedSimilarity()
    let reopened = SimilarGrouping(similarity: coldFeatureSource, cache: cache)
    await reopened.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    #expect(await reopened.current == first)
    await reopened.refine()
    #expect(await coldFeatureSource.askCount == 0)
}

@Test func aChangedInputRevisionInvalidatesTheCache() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    _ = await groupingRun(photos, using: scripted, cache: cache)

    let reopened = SimilarGrouping(similarity: ScriptedSimilarity(), cache: cache)
    await reopened.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-2"))

    let regrouped = await reopened.current
    #expect(regrouped.analysis == .timeOnly)
    #expect(groupingStems(regrouped) == [["a", "b", "c"]])
}

@Test func aChangedThresholdSetInvalidatesTheCache() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    let scripted = ScriptedSimilarity()
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    _ = await groupingRun(photos, using: scripted, cache: cache)

    let recalibrated = SimilarGrouping(
        similarity: ScriptedSimilarity(),
        thresholds: GroupingThresholds(timeGap: 1),
        cache: cache)
    await recalibrated.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))

    #expect(await recalibrated.current.analysis == .timeOnly)
}

/// A cache for a different folder identity is a different file, so it can never leak in.
@Test func anotherFoldersCacheIsIgnored() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let otherFolder = FolderIdentity(rawValue: "another-folder")
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    let otherPhotos = [
        groupingPhoto("a", at: 0, folder: otherFolder),
        groupingPhoto("b", at: 0.2, folder: otherFolder),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    _ = await groupingRun(photos, using: scripted, cache: cache)

    let neighbour = SimilarGrouping(similarity: ScriptedSimilarity(), cache: cache)
    await neighbour.run(
        photos: otherPhotos, revision: GroupingInputRevision(rawValue: "revision-1"))

    #expect(await neighbour.current.analysis == .timeOnly)
}

/// PRD Similar groups rules: a corrupt cache is ignored and rebuilt, never trusted.
@Test func aCorruptCacheIsRebuilt() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    let scripted = ScriptedSimilarity()
    await scripted.answerAll(.vision(distance: 0.1), between: photos)
    _ = await groupingRun(photos, using: scripted, cache: cache)

    let name = try #require(try folder.entries().first)
    try Data("{ not a group file".utf8).write(to: folder.file(name))

    let rebuilt = SimilarGrouping(similarity: scripted, cache: cache)
    await rebuilt.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    #expect(await rebuilt.current.analysis == .timeOnly)
    await rebuilt.refine()
    #expect(await rebuilt.current.analysis == .analyzed)

    // The rebuilt file is usable again.
    let reopened = SimilarGrouping(similarity: ScriptedSimilarity(), cache: cache)
    await reopened.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    #expect(await reopened.current.analysis == .analyzed)
}

/// A time-only result is not a finished one, so it is not cached.
@Test func anUnfinishedResultIsNotCached() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]

    let result = await groupingRun(photos, using: ScriptedSimilarity(), cache: cache)

    #expect(result.analysis == .timeOnly)
    #expect(try folder.entries().isEmpty)
}

@Test func applicationSupportDirectoryIsAppPrivate() throws {
    let directory = try SimilarGroupsCache.applicationSupportDirectory()

    #expect(directory.lastPathComponent == "SimilarGroups")
    #expect(directory.deletingLastPathComponent().lastPathComponent == "Clove")
}
