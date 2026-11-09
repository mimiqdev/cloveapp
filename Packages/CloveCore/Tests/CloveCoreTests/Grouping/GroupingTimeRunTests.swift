import Foundation
import Testing

import CloveCore

/// PRD Similar groups step 2 and G1's grouping item: adjacent photos less than 2 seconds apart
/// join, and the comparison is strict, so a gap of exactly 2 seconds starts a new run.
@Test func aGapOfExactlyTwoSecondsSplits() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 2)]

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.isEmpty)
}

@Test func aGapOfOnePointNineNineNineSecondsJoins() async {
    let scripted = ScriptedSimilarity()
    let photos = [groupingPhoto("a", at: 0), groupingPhoto("b", at: 1.999)]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b"]])
}

@Test func theTimeGapIsMeasuredBetweenAdjacentPhotos() async {
    // 1.999 s joins, then exactly 2 s splits, then 0.501 s joins again.
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0),
        groupingPhoto("b", at: 1.999),
        groupingPhoto("c", at: 3.999),
        groupingPhoto("d", at: 4.5),
    ]
    await scripted.answerAll(.vision(distance: 0.1), between: photos)

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b"], ["c", "d"]])
}

@Test func membersKeepSubsecondCaptureOrder() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("late", at: 0.75),
        groupingPhoto("early", at: 0.25),
        groupingPhoto("middle", at: 0.5),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["early", "middle", "late"]])
}

@Test func equalCaptureInstantsTieBreakOnTheNumericAwareFileName() async {
    // Numeric order is IMG_2, IMG_4, IMG_10; a plain string order would put IMG_10 second.
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("IMG_10", at: 0, fileName: "IMG_10.ARW"),
        groupingPhoto("IMG_4", at: 0, fileName: "IMG_4.ARW"),
        groupingPhoto("IMG_2", at: 0, fileName: "IMG_2.ARW"),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["img_2", "img_4", "img_10"]])
}

@Test func aLongBurstStaysOneGroupAndALaterPhotoStaysOut() async {
    // S5's device burst: ten frames about 0.2 s apart, then one photo 250 s later.
    let scripted = ScriptedSimilarity()
    var photos = (0..<10).map { index in
        groupingPhoto(String(format: "MMQ026%02d", 78 + index), at: Double(index) * 0.2)
    }
    photos.append(groupingPhoto("MMQ09999", at: 250))
    await scripted.answerAll(.vision(distance: 0.3), between: photos)

    let result = await groupingRun(photos, using: scripted)

    #expect(result.groups.count == 1)
    #expect(result.groups.first?.count == 10)
    #expect(!groupingStems(result)[0].contains("mmq09999"))
}
