import Foundation
import Testing

import CloveCore

@Test func thresholdPresetsMatchExpectedValuesAndStrictOrdering() {
    let standard = GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .standard)
    #expect(standard == .standard)
    #expect(standard.timeGap == 2)
    #expect(standard.visionDistance == 0.5)
    #expect(standard.hashDistance == 12)
    #expect(standard.useVisualSimilarity)

    let tight = GroupingThresholds(timeWindow: .fiveSeconds, sensitivity: .tight)
    #expect(tight.timeGap == 5)
    #expect(tight.visionDistance < standard.visionDistance)
    #expect(tight.hashDistance < standard.hashDistance)
    #expect(tight.useVisualSimilarity)

    let loose = GroupingThresholds(timeWindow: .tenSeconds, sensitivity: .loose)
    #expect(loose.timeGap == 10)
    #expect(loose.visionDistance > standard.visionDistance)
    #expect(loose.hashDistance > standard.hashDistance)
    #expect(loose.useVisualSimilarity)

    let timeOnly = GroupingThresholds(timeWindow: .thirtySeconds, sensitivity: .timeOnly)
    #expect(timeOnly.timeGap == 30)
    #expect(!timeOnly.useVisualSimilarity)

    #expect(GroupingTimeWindow.oneSecond.seconds == 1)
    #expect(GroupingTimeWindow.twoSeconds.seconds == 2)
    #expect(GroupingTimeWindow.fiveSeconds.seconds == 5)
    #expect(GroupingTimeWindow.tenSeconds.seconds == 10)
    #expect(GroupingTimeWindow.thirtySeconds.seconds == 30)
}

@Test func cacheKeyIsUniqueAcrossAllTimeWindowAndSensitivityCombinations() {
    var seen: Set<String> = []
    for window in GroupingTimeWindow.allCases {
        for sensitivity in GroupingSensitivity.allCases {
            let key = GroupingThresholds(timeWindow: window, sensitivity: sensitivity).cacheKey
            #expect(seen.insert(key).inserted, "Duplicate cacheKey \(key)")
        }
    }
    #expect(seen.count == GroupingTimeWindow.allCases.count * GroupingSensitivity.allCases.count)

    let standard = GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .standard)
    let timeOnly = GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .timeOnly)
    #expect(standard.cacheKey != timeOnly.cacheKey)
    #expect(timeOnly.cacheKey.contains("timeOnly"))
}

@Test func timeOnlyModeGroupsByTimeWithoutVisualSimilarityOrFeatureWork() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 4.0),
        groupingPhoto("c", at: 8.5),
        groupingPhoto("other-body", at: 4.5, model: "X-T5"),
        groupingPhoto("d", at: 20.0),
    ]
    // Even if visual distances would split every boundary, time-only mode never consults them.
    await scripted.answerAll(.vision(distance: 9.9), between: photos)

    let thresholds = GroupingThresholds(timeWindow: .fiveSeconds, sensitivity: .timeOnly)
    let grouper = SimilarGrouping(similarity: scripted, thresholds: thresholds)
    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "time-only"))

    let immediate = await grouper.current
    #expect(immediate.analysis == .analyzed)
    #expect(groupingStems(immediate) == [["a", "b", "c"]])
    #expect(immediate.groups.first?.refinement == .timeOnly)
    #expect(immediate.groups.first?.usedFallbackSimilarity == false)
    #expect(await scripted.askCount == 0)

    // Calling refine in time-only mode is a no-op and never queries the similarity provider.
    await grouper.refine()
    #expect(await scripted.askCount == 0)
    #expect(await grouper.current == immediate)

    // Feature candidate extraction skips all work in time-only mode.
    #expect(GroupingFeatureCandidates.photos(in: photos, thresholds: thresholds).isEmpty)
    #expect(GroupingFeatureCandidates.runs(in: photos, thresholds: thresholds).isEmpty)
}

@Test func timeOnlyCacheRoundTripsWithoutCollidingWithVisualCache() async throws {
    let folder = try GroupingTestFolder()
    defer { folder.remove() }
    let cache = SimilarGroupsCache(directory: folder.url)
    let revision = GroupingInputRevision(rawValue: "rev-1")
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.5),
        groupingPhoto("c", at: 1.0),
    ]

    let timeOnlyThresholds = GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .timeOnly)
    let coldTimeOnly = SimilarGrouping(
        similarity: ScriptedSimilarity(), thresholds: timeOnlyThresholds, cache: cache)
    await coldTimeOnly.run(photos: photos, revision: revision)
    let first = await coldTimeOnly.current
    #expect(first.analysis == .analyzed)
    #expect(groupingStems(first) == [["a", "b", "c"]])
    #expect(try folder.entries().count == 1)

    // Reopening in time-only mode hits the cache and matches identically.
    let warmTimeOnly = SimilarGrouping(
        similarity: ScriptedSimilarity(), thresholds: timeOnlyThresholds, cache: cache)
    await warmTimeOnly.run(photos: photos, revision: revision)
    #expect(await warmTimeOnly.current == first)

    // Opening the same folder under standard visual thresholds must miss the time-only cache.
    let visual = SimilarGrouping(
        similarity: ScriptedSimilarity(), thresholds: .standard, cache: cache)
    await visual.run(photos: photos, revision: revision)
    #expect(await visual.current.analysis == .timeOnly)
}

@Test func sensitivityPresetsSplitAndJoinBoundariesAccordingToThresholds() async {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.3),
        groupingPhoto("c", at: 0.6),
    ]
    let scripted = ScriptedSimilarity()
    // 0.42 splits under tight (0.35), joins under standard (0.5) and loose (0.7).
    await scripted.answer(.vision(distance: 0.42), for: photos[0], photos[1])
    // 0.62 splits under tight (0.35) and standard (0.5), joins under loose (0.7).
    await scripted.answer(.vision(distance: 0.62), for: photos[1], photos[2])

    let tight = await groupingRun(
        photos,
        using: scripted,
        thresholds: GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .tight))
    #expect(tight.groups.isEmpty)
    #expect(tight.analysis == .analyzed)

    let standard = await groupingRun(
        photos,
        using: scripted,
        thresholds: GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .standard))
    #expect(groupingStems(standard) == [["a", "b"]])
    #expect(standard.analysis == .analyzed)

    let loose = await groupingRun(
        photos,
        using: scripted,
        thresholds: GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .loose))
    #expect(groupingStems(loose) == [["a", "b", "c"]])
    #expect(loose.analysis == .analyzed)
}

@Test func dynamicThresholdUpdatesRecomputeImmediatelyAndPreserveGroupIDs() async throws {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.4),
        groupingPhoto("c", at: 3.5),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answer(.vision(distance: 0.42), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.60), for: photos[1], photos[2])

    let grouper = SimilarGrouping(similarity: scripted, thresholds: .standard)
    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "rev-dynamic"))
    await grouper.refine()

    let initial = await grouper.current
    #expect(groupingStems(initial) == [["a", "b"]])
    let originalID = try #require(initial.groups.first?.id)

    // Widening to 5s + loose joins c into the existing group while preserving its stable ID.
    await grouper.setThresholds(GroupingThresholds(timeWindow: .fiveSeconds, sensitivity: .loose))
    await grouper.refine()
    let widened = await grouper.current
    #expect(groupingStems(widened) == [["a", "b", "c"]])
    #expect(widened.groups.first?.id == originalID)
    #expect(widened.analysis == .analyzed)

    // Switching to time-only finishes immediately without asking the similarity provider again.
    let asksBeforeTimeOnly = await scripted.askCount
    await grouper.setThresholds(
        GroupingThresholds(timeWindow: .fiveSeconds, sensitivity: .timeOnly))
    let timeOnly = await grouper.current
    #expect(timeOnly.analysis == .analyzed)
    #expect(groupingStems(timeOnly) == [["a", "b", "c"]])
    #expect(timeOnly.groups.first?.id == originalID)
    #expect(await scripted.askCount == asksBeforeTimeOnly)

    // Updating thresholds while disabled stores them without publishing groups.
    await grouper.run(
        photos: photos,
        revision: GroupingInputRevision(rawValue: "rev-dynamic"),
        similarGroupsEnabled: false)
    await grouper.setThresholds(GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .tight))
    #expect(await grouper.current == .off)

    // Re-enabling runs with the updated tight thresholds (0.42 > 0.35 -> splits).
    await grouper.run(
        photos: photos,
        revision: GroupingInputRevision(rawValue: "rev-dynamic"),
        similarGroupsEnabled: true)
    await grouper.refine()
    #expect(await grouper.current.groups.isEmpty)
    #expect(await grouper.current.analysis == .analyzed)
}
