import Testing

import CloveCore

@Suite struct MarkingKeyTests {
    @Test func ratingKeysSetTheirLevelAndZeroClears() throws {
        let rules = MarkingInputRules()
        let one = try MarkingFixtures.stars(1)
        let five = try MarkingFixtures.stars(5)

        #expect(
            rules.result(for: .rating(one), marks: PhotoMarks())
                == .mark(MarkChange(rating: one), .rating))
        #expect(
            rules.result(for: .rating(five), marks: PhotoMarks())
                == .mark(MarkChange(rating: five), .rating))
        #expect(
            rules.result(for: .rating(.unrated), marks: PhotoMarks(rating: five))
                == .mark(MarkChange(rating: .unrated), .rating))
        #expect(rules.result(for: .rating(.unrated), marks: PhotoMarks()) == .noChange)
    }

    @Test func settingTheRatingAlreadyAppliedIsNoChange() throws {
        let rules = MarkingInputRules()
        let three = try MarkingFixtures.stars(3)

        #expect(rules.result(for: .rating(three), marks: PhotoMarks(rating: three)) == .noChange)
    }

    @Test func aDisabledLevelKeyDoesNothing() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 3, 5)))
        let two = try MarkingFixtures.stars(2)
        let four = try MarkingFixtures.stars(4)
        let five = try MarkingFixtures.stars(5)

        #expect(rules.result(for: .rating(two), marks: PhotoMarks()) == .noChange)
        #expect(rules.result(for: .rating(four), marks: PhotoMarks(rating: two)) == .noChange)
        // Zero is not a level, so clearing still works.
        #expect(
            rules.result(for: .rating(.unrated), marks: PhotoMarks(rating: five))
                == .mark(MarkChange(rating: .unrated), .rating))
    }

    @Test func labelKeysSetRedYellowGreenAndBlue() {
        let rules = MarkingInputRules()
        let cases: [(LabelColour, ColourLabel)] = [
            (.red, ColourLabel(colour: .red)),
            (.yellow, ColourLabel(colour: .yellow)),
            (.green, ColourLabel(colour: .green)),
            (.blue, ColourLabel(colour: .blue)),
        ]

        for (colour, label) in cases {
            #expect(
                rules.result(for: .colourLabel(colour), marks: PhotoMarks())
                    == .mark(MarkChange(label: label), .colourLabel))
        }
    }

    @Test func pressingTheAppliedLabelAgainClearsIt() {
        let rules = MarkingInputRules()
        let red = ColourLabel(colour: .red)

        #expect(
            rules.result(for: .colourLabel(.red), marks: PhotoMarks(label: red))
                == .mark(MarkChange(label: .clear), .colourLabel))
    }

    @Test func anotherLabelReplacesTheAppliedOne() {
        let rules = MarkingInputRules()
        let marks = PhotoMarks(label: ColourLabel(colour: .red))
        let blue = ColourLabel(colour: .blue)

        #expect(
            rules.result(for: .colourLabel(.blue), marks: marks)
                == .mark(MarkChange(label: blue), .colourLabel))
    }

    @Test func anUnknownExternalLabelIsReplacedByTheChosenColour() {
        let rules = MarkingInputRules()
        let marks = PhotoMarks(label: ColourLabel(rawValue: "Teal"))
        let green = ColourLabel(colour: .green)

        #expect(
            rules.result(for: .colourLabel(.green), marks: marks)
                == .mark(MarkChange(label: green), .colourLabel))
    }

    @Test func upArrowRaisesToTheNextEnabledRating() throws {
        let rules = MarkingInputRules()
        let one = try MarkingFixtures.stars(1)
        let two = try MarkingFixtures.stars(2)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(for: .nextRating, marks: PhotoMarks())
                == .mark(MarkChange(rating: one), .rating))
        #expect(
            rules.result(for: .nextRating, marks: PhotoMarks(rating: two))
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func upArrowAtTheTopDoesNothing() throws {
        let rules = MarkingInputRules()
        let five = try MarkingFixtures.stars(5)

        #expect(rules.result(for: .nextRating, marks: PhotoMarks(rating: five)) == .noChange)
    }

    @Test func upArrowSkipsDisabledLevelsAboveADisabledCurrentRating() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 3, 5)))
        let two = try MarkingFixtures.stars(2)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(for: .nextRating, marks: PhotoMarks(rating: two))
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func downArrowRejectsAndReplacesTheRating() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 4, label: .green)

        #expect(
            rules.result(for: .reject, marks: marks)
                == .mark(MarkChange(rating: .rejected), .reject))
    }

    @Test func downArrowOnARejectedPhotoDoesNothing() throws {
        let rules = MarkingInputRules()

        #expect(
            rules.result(for: .reject, marks: try MarkingFixtures.marks(rejected: true))
                == .noChange)
    }

    @Test func arrowsNavigateAndCommandZReportsUndo() {
        let rules = MarkingInputRules()

        #expect(rules.result(for: .previousPhoto, marks: PhotoMarks()) == .previousPhoto)
        #expect(rules.result(for: .nextPhoto, marks: PhotoMarks()) == .nextPhoto)
        #expect(rules.result(for: .undo, marks: PhotoMarks()) == .undo)
    }

    @Test func aPositiveKeyboardRatingReplacesReject() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(rejected: true)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(for: .rating(three), marks: marks)
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func theZeroKeyReplacesRejectWithUnrated() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(rejected: true)

        #expect(
            rules.result(for: .rating(.unrated), marks: marks)
                == .mark(MarkChange(rating: .unrated), .rating))
    }

}
