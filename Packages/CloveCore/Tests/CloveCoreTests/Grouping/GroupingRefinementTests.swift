import Foundation
import Testing

import CloveCore

/// G1's grouping row: a Vision distance at or below 0.5 keeps a boundary joined, a larger one
/// splits it. PRD Similar groups step 3 carries the same inclusive comparison.
@Test func visionDistanceAtTheThresholdJoins() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.vision(distance: 0.5), for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b"]])
    #expect(result.analysis == .analyzed)
    #expect(result.groups.first?.refinement == .refined)
    #expect(result.groups.first?.usedFallbackSimilarity == false)
}

@Test func visionDistanceAboveTheThresholdSplits() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.vision(distance: 0.5001), for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.isEmpty)
    #expect(result.analysis == .analyzed)
}

/// G1's fallback: a dHash distance at or below 12 bits joins, and it only answers boundaries
/// Vision had no usable feature for.
@Test func hashDistanceAtTheThresholdJoinsOnlyWhenVisionIsMissing() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.differenceHash(distance: 12), for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b"]])
    #expect(result.groups.first?.usedFallbackSimilarity == true)
}

@Test func hashDistanceAboveTheThresholdSplits() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.differenceHash(distance: 13), for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.isEmpty)
}

@Test func noUsableFeatureSplits() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.unavailable, for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.isEmpty)
    #expect(result.analysis == .analyzed)
}

@Test func eachBoundaryUsesOnlyTheAnswerItWasGiven() async {
    // The first boundary's Vision distance splits even though a dHash would have joined; the
    // second joins on the fallback because Vision has no feature there. No boundary consults
    // two kinds (G1's grouping row).
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    await scripted.answer(.vision(distance: 0.9), for: photos[0], photos[1])
    await scripted.answer(.differenceHash(distance: 0), for: photos[1], photos[2])

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["b", "c"]])
    #expect(result.groups.first?.usedFallbackSimilarity == true)
}

@Test func aNonFiniteOrNegativeDistanceIsNoUsableFeature() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await scripted.answer(.vision(distance: .nan), for: photos[0], photos[1])

    let nanResult = await groupingRun(photos, using: scripted)
    #expect(nanResult.groups.isEmpty)

    let negativeHash = ScriptedSimilarity()
    let hashPhotos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 0.2)]
    await negativeHash.answer(.differenceHash(distance: -1), for: hashPhotos[0], hashPhotos[1])
    let hashResult = await groupingRun(hashPhotos, using: negativeHash)
    #expect(hashResult.groups.isEmpty)
}

/// PRD Similar groups step 3: refinement runs in the background. A feature that is not ready
/// yet leaves the boundary provisional, so the time-only group keeps showing.
@Test func aFeatureThatIsNotReadyLeavesTheBoundaryProvisional() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b", "c"]])
    #expect(result.groups.first?.refinement == .timeOnly)
    #expect(result.analysis == .timeOnly)
    #expect(await scripted.askCount == 2)
}

@Test func aGroupWithSomeBoundariesDecidedIsPartlyRefined() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[1])

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b", "c"]])
    #expect(result.groups.first?.refinement == .partlyRefined)
    #expect(result.analysis == .refining(decided: 1, total: 2))
}

@Test func aFullyDecidedRunIsRefinedAndAnalyzed() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
    ]
    await scripted.answerAll(.vision(distance: 0.3), between: photos)

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b", "c", "d"]])
    #expect(result.groups.first?.refinement == .refined)
    #expect(result.analysis == .analyzed)
}

/// PRD P0-11 and Similar groups step 2: time-only groups appear before any feature exists.
@Test func timeOnlyGroupsArePublishedBeforeAnyFeatureAnswer() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    let grouper = SimilarGrouping(similarity: scripted)
    var updates = await grouper.updates().makeAsyncIterator()

    let initial = await updates.next()
    #expect(initial?.analysis == .off)

    await grouper.run(
        photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    let timeOnly = await updates.next()
    #expect(timeOnly?.analysis == .timeOnly)
    #expect(timeOnly.map(groupingStems) == [["a", "b", "c"]])
    #expect(timeOnly?.groups.first?.refinement == .timeOnly)
    #expect(await scripted.askCount == 0)

    await scripted.answerAll(.vision(distance: 0.3), between: photos)
    await grouper.refine()
    let refined = await updates.next()
    #expect(refined?.analysis == .analyzed)
    #expect(refined?.groups.first?.refinement == .refined)
}

/// PRD Similar groups step 3: features arrive in the background, so the final result must not
/// depend on the order their answers come back in.
@Test func theFinalResultDoesNotDependOnArrivalOrder() async {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
        groupingPhoto("d", at: 0.6),
    ]
    let answers: [(Int, PhotoSimilarity)] = [
        (1, .vision(distance: 0.1)),
        (2, .vision(distance: 0.9)),
        (3, .differenceHash(distance: 12)),
    ]

    func result(arrivingIn order: [Int]) async -> SimilarGroups {
        let scripted = ScriptedSimilarity()
        let grouper = SimilarGrouping(similarity: scripted)
        await grouper.run(
            photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
        for index in order {
            guard let answer = answers.first(where: { $0.0 == index })?.1 else { continue }
            await scripted.answer(answer, for: photos[index - 1], photos[index])
            await grouper.refine()
        }
        return await grouper.current
    }

    let forward = await result(arrivingIn: [1, 2, 3])
    let backward = await result(arrivingIn: [3, 2, 1])
    let mixed = await result(arrivingIn: [2, 1, 3])

    #expect(groupingStems(forward) == [["a", "b"], ["c", "d"]])
    #expect(forward == backward)
    #expect(forward == mixed)
    #expect(forward.analysis == .analyzed)
}

@Test func answeringEverythingInOnePassMatchesArrivingOneByOne() async {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answerAll(.vision(distance: 0.3), between: photos)
    let grouper = SimilarGrouping(similarity: scripted)
    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    await grouper.refine()
    let onePass = await grouper.current

    let stepwise = await groupingRun(photos, using: scripted, passes: 2)

    #expect(onePass == stepwise)
}

@Test func incrementalRefineQueriesOnlySettledBoundaries() async {
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 0.2),
        groupingPhoto("c", at: 0.4),
    ]
    let scripted = ScriptedSimilarity()
    await scripted.answer(.vision(distance: 0.9), for: photos[0], photos[1])
    await scripted.answer(.vision(distance: 0.1), for: photos[1], photos[2])
    let grouper = SimilarGrouping(similarity: scripted)

    await grouper.run(photos: photos, revision: GroupingInputRevision(rawValue: "revision-1"))
    await grouper.refine(settledPhotos: [photos[0].id, photos[1].id])

    let intermediate = await grouper.current
    #expect(await scripted.askCount == 1)
    #expect(intermediate.analysis == .refining(decided: 1, total: 2))
    #expect(groupingStems(intermediate) == [["b", "c"]])

    await grouper.refine()
    let final = await grouper.current
    #expect(await scripted.askCount == 2)
    #expect(final.analysis == .analyzed)
    #expect(groupingStems(final) == [["b", "c"]])
}
