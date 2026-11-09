import Foundation
import Testing

import CloveCore

/// PRD Similar groups and G1's grouping item group only photos whose time comes from capture
/// metadata; PRD extends that with "Files without a capture time are not grouped". C9's
/// model-less default excludes a photo whose metadata read found no camera model.
@Test func fileTimeFallbacksAreNeverGrouped() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("capture-a", at: 0),
        groupingPhoto(
            "creation", at: 0.2,
            time: .known(PhotoTime(fileCreation: groupingSeconds(0.2)))),
        groupingPhoto(
            "modification", at: 0.4,
            time: .known(PhotoTime(fileModification: groupingSeconds(0.4)))),
        groupingPhoto("capture-b", at: 0.6),
    ]

    await scripted.answer(.vision(distance: 0.1), for: photos[0], photos[3])

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["capture-a", "capture-b"]])
    #expect(result.analysis == .analyzed)
    // Two eligible photos make one boundary; the fallback photos make none.
    #expect(await scripted.askCount == 1)
}

@Test func pendingAndUnavailableTimesAreNeverGrouped() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("pending", at: 0, time: .pending),
        groupingPhoto("unavailable", at: 0.2, time: .unavailable),
        groupingPhoto("capture-a", at: 0.4),
        groupingPhoto("capture-b", at: 0.6),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["capture-a", "capture-b"]])
}

@Test func aPhotoWithoutACameraModelIsNeverGrouped() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("modelled-a", at: 0),
        groupingPhoto("unknown-model", at: 0.2, model: nil),
        groupingPhoto("modelled-b", at: 0.4),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["modelled-a", "modelled-b"]])
    for group in result.groups {
        #expect(!group.members.contains { $0.stem == "unknown-model" })
    }
}

@Test func aBlankModelOrSerialFallsBackLikeMissingMetadata() async {
    // A whitespace-only model is no model at all, so the photo stays ungrouped; a blank serial
    // is a missing serial, so the body falls back to its model (G1's grouping item).
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("blank-model", at: 0, model: "   "),
        groupingPhoto("blank-serial-a", at: 0.2, serial: "  "),
        groupingPhoto("blank-serial-b", at: 0.4),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["blank-serial-a", "blank-serial-b"]])
}

@Test func aSinglePhotoIsNeverAGroup() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("lonely", at: 0), groupingPhoto("distant", at: 30)]

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.isEmpty)
    #expect(result.analysis == .analyzed)
    #expect(await scripted.askCount == 0)
}
