import Testing

import CloveCore

@Suite struct RatingBarRulesTests {
    @Test func tappingTheAppliedRatingClearsIt() throws {
        let rules = MarkingInputRules()
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forRating: three, marks: PhotoMarks(rating: three))
                == .mark(MarkChange(rating: .unrated), .rating))
    }

    @Test func tappingAnotherRatingSetsIt() throws {
        let rules = MarkingInputRules()
        let two = try MarkingFixtures.stars(2)
        let four = try MarkingFixtures.stars(4)

        #expect(
            rules.result(forRating: four, marks: PhotoMarks(rating: two))
                == .mark(MarkChange(rating: four), .rating))
    }

    @Test func tappingARatingOnARejectedPhotoReplacesReject() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(rejected: true)

        // Reject is the rating −1, so choosing stars replaces it (PRD P0-05).
        #expect(
            rules.result(forRating: try MarkingFixtures.stars(3), marks: marks)
                == .mark(MarkChange(rating: try MarkingFixtures.stars(3)), .rating))
    }

    @Test func aDisabledLevelTapDoesNothing() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 3, 5)))
        let two = try MarkingFixtures.stars(2)

        #expect(rules.result(forRating: two, marks: PhotoMarks()) == .noChange)
    }

    @Test func tappingZeroClearsTheRating() throws {
        let rules = MarkingInputRules()
        let five = try MarkingFixtures.stars(5)

        #expect(
            rules.result(forRating: .unrated, marks: PhotoMarks(rating: five))
                == .mark(MarkChange(rating: .unrated), .rating))
        #expect(rules.result(forRating: .unrated, marks: PhotoMarks()) == .noChange)
    }

    @Test func aPositiveRatingTapReplacesReject() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(rejected: true)
        let four = try MarkingFixtures.stars(4)

        #expect(
            rules.result(forRating: four, marks: marks)
                == .mark(MarkChange(rating: four), .rating))
    }

    @Test func aRatingOnAnUnknownExternalLabelKeepsTheLabel() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 2, label: .red)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forRating: three, marks: marks)
                == .mark(MarkChange(rating: three), .rating))
    }
}
