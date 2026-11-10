import Testing

import CloveCore

/// How the two mark storages combine into the marks a cell shows (PRD P0-05, P0-07;
/// G1 decisions 5–6).
@Suite("Marks composition")
struct PhotoMarksCompositionTests {
    @Test func nothingStoredReadsAsUnmarked() {
        let marks = PhotoMarks(stored: nil, xmp: nil)
        #expect(marks == PhotoMarks())
    }

    @Test func aRawSetsSidecarWinsAndRejectComesFromClove() {
        let marks = PhotoMarks(
            stored: CloveStoredMarks(isRejected: true),
            xmp: XMPMarks(
                rating: .rated(Rating(rawValue: 4) ?? .unrated),
                label: ColourLabel(colour: .red)))

        #expect(marks.rating.rawValue == 4)
        #expect(marks.label.colour == .red)
        #expect(marks.isRejected)
    }

    @Test func aStandaloneSetKeepsItsCloveStoredMarks() {
        let marks = PhotoMarks(
            stored: CloveStoredMarks(
                rating: Rating(rawValue: 3) ?? .unrated, label: ColourLabel(colour: .green)),
            xmp: .unmarked)

        #expect(marks.rating.rawValue == 3)
        #expect(marks.label.colour == .green)
        #expect(!marks.isRejected)
    }

    @Test func anExternalRatingIsNeverReject() {
        // G1 decision 5 keeps xmp:Rating −1 an external value, not Clove's Reject flag.
        let external = PhotoMarks(xmp: XMPMarks(rating: XMPRating(-1)))
        #expect(external.rating == .unrated)
        #expect(!external.isRejected)

        // It also never hides a rating Clove stored for the same photo (G1 decision 6).
        let stored = PhotoMarks(
            stored: CloveStoredMarks(rating: Rating(rawValue: 2) ?? .unrated),
            xmp: XMPMarks(rating: XMPRating(-1)))
        #expect(stored.rating.rawValue == 2)
    }

    @Test func anUnknownExternalLabelIsKept() {
        let marks = PhotoMarks(xmp: XMPMarks(label: ColourLabel(rawValue: "Chartreuse")))
        #expect(marks.label.rawValue == "Chartreuse")
        #expect(marks.label.colour == nil)
        #expect(!marks.label.isClear)
    }

    @Test func aClearPacketLabelFallsBackToCloveAndClearWinsOverUnknown() {
        let stored = PhotoMarks(
            stored: CloveStoredMarks(label: ColourLabel(colour: .purple)),
            xmp: XMPMarks(label: .clear))
        #expect(stored.label.colour == .purple)
    }
}
