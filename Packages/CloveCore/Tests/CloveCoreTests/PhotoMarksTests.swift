import Testing

import CloveCore

@Test(arguments: Array(-1...5))
func validRatingsRoundTrip(value: Int) throws {
    let rating = try #require(Rating(rawValue: value))
    #expect(rating.rawValue == value)
    #expect(Rating(rawValue: rating.rawValue) == rating)
}

@Test(arguments: [Int.min, -2, 6, 7, Int.max])
func invalidRatingsAreRejected(value: Int) {
    #expect(Rating(rawValue: value) == nil)
}

@Test func defaultAndOrderedRatings() throws {
    #expect(Rating().rawValue == 0)
    #expect(Rating.unrated == Rating(rawValue: 0))
    #expect(try #require(Rating(rawValue: 2)) < #require(Rating(rawValue: 5)))
    // Reject is −1, below unrated, so "N stars or higher" never includes it (PRD P0-03).
    #expect(Rating.rejected.rawValue == -1)
    #expect(Rating.rejected.isRejected)
    #expect(!Rating.unrated.isRejected)
    #expect(Rating.rejected < .unrated)
}

@Test func fixedEnglishLabelNamesIncludeExtendedColours() {
    #expect(
        LabelColour.allCases.map(\.rawValue) == [
            "Red", "Yellow", "Green", "Blue", "Purple", "Orange", "Pink",
        ])
    #expect(LabelColour.allCases.filter(\.isExtended) == [.orange, .pink])
}

@Test(arguments: LabelColour.allCases)
func knownLabelRoundTrip(colour: LabelColour) {
    let label = ColourLabel(colour: colour)
    #expect(label.rawValue == colour.rawValue)
    #expect(label.colour == colour)
    #expect(!label.isClear)
    #expect(ColourLabel(rawValue: label.rawValue) == label)
}

@Test(arguments: [
    "Custom label", "red", "RED", " Red ", "橙色", "\nPink\t", " ", "Clear", "cafe\u{301}",
])
func unknownLabelsKeepExactExternalText(text: String) {
    let label = ColourLabel(rawValue: text)
    #expect(label.colour == nil)
    #expect(!label.isClear)
    // Compare bytes too: preserving external text must not normalize its Unicode representation.
    #expect(Array(label.rawValue.utf8) == Array(text.utf8))
    let reread = ColourLabel(rawValue: label.rawValue)
    #expect(Array(reread.rawValue.utf8) == Array(text.utf8))
}

@Test func clearAndIndependentMarks() throws {
    #expect(ColourLabel.clear.rawValue == "")
    #expect(ColourLabel.clear.isClear)
    #expect(ColourLabel.clear.colour == nil)
    #expect(PhotoMarks() == PhotoMarks(rating: .unrated, label: .clear))
    let rating = try #require(Rating(rawValue: 4))
    let label = ColourLabel(rawValue: "External workflow")
    var marks = PhotoMarks(rating: rating, label: label)
    marks.rating = .rejected
    #expect(marks.isRejected)
    #expect(marks.rating == .rejected)
    #expect(marks.label == label)
    marks.rating = .unrated
    #expect(!marks.isRejected)
    #expect(marks.rating == .unrated)
    #expect(marks.label == label)
}
