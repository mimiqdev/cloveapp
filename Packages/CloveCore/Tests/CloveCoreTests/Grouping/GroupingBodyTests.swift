import Foundation
import Testing

import CloveCore

/// G1's grouping item separates photos by camera model plus serial when present, otherwise the
/// model alone; two same-model bodies at the same moment are unsupported, so a model without a
/// serial never joins the same model with one.
@Test func differentModelsAreKeptApart() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("alpha-a", at: 0, model: "ILCE-1M2"),
        groupingPhoto("alpha-b", at: 0.2, model: "ILCE-1M2"),
        groupingPhoto("canon-a", at: 0.1, model: "Canon EOS R6"),
        groupingPhoto("canon-b", at: 0.3, model: "Canon EOS R6"),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["alpha-a", "alpha-b"], ["canon-a", "canon-b"]])
}

@Test func sameModelWithDifferentSerialsIsKeptApart() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("first-a", at: 0, serial: "SERIAL-1"),
        groupingPhoto("first-b", at: 0.2, serial: "SERIAL-1"),
        groupingPhoto("second-a", at: 0.1, serial: "SERIAL-2"),
        groupingPhoto("second-b", at: 0.3, serial: "SERIAL-2"),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["first-a", "first-b"], ["second-a", "second-b"]])
}

@Test func sameModelWithNoSerialsIsJoined() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0, serial: nil),
        groupingPhoto("b", at: 0.2, serial: nil),
        groupingPhoto("c", at: 0.4, serial: ""),
        groupingPhoto("d", at: 0.6, serial: "   "),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b", "c", "d"]])
}

@Test func aSerialAndItsMissingNeighbourStayApart() async {
    // G1 accepts that the fallback is lossy: a model with a serial is a different body from
    // the same model without one, so the two buckets never mix.
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("known-a", at: 0, serial: "SERIAL-1"),
        groupingPhoto("known-b", at: 0.2, serial: "SERIAL-1"),
        groupingPhoto("unknown-a", at: 0.1),
        groupingPhoto("unknown-b", at: 0.3),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["known-a", "known-b"], ["unknown-a", "unknown-b"]])
}

@Test func modelAndSerialSymbolsCompareCaseInsensitively() async {
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("a", at: 0, model: "ILCE-1M2", serial: "Abc-1"),
        groupingPhoto("b", at: 0.2, model: " ilce-1m2 ", serial: "abc-1"),
        groupingPhoto("c", at: 0.4, model: "Ilce-1M2", serial: "ABC-1"),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["a", "b", "c"]])
}

@Test func bodiesAreOrderedByTheirEarliestMember() async {
    // Two bodies shooting at the same moment interleave; next and previous group follow the
    // grid, so the order comes from each group's earliest member, not from the body.
    let scripted = ScriptedSimilarity()
    let photos = [
        groupingPhoto("body-b-1", at: 0.5, model: "Canon EOS R6", serial: "B"),
        groupingPhoto("body-a-1", at: 0.0, model: "ILCE-1M2", serial: "A"),
        groupingPhoto("body-a-2", at: 0.2, model: "ILCE-1M2", serial: "A"),
        groupingPhoto("body-b-2", at: 0.7, model: "Canon EOS R6", serial: "B"),
    ]

    let result = await groupingRun(photos, using: scripted)

    #expect(groupingStems(result) == [["body-a-1", "body-a-2"], ["body-b-1", "body-b-2"]])
}
