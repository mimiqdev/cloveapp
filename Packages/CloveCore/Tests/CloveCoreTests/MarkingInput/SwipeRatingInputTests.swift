import Testing

import CloveCore

@Suite struct SwipeRatingInputTests {
    @Test func aReleaseInsideTheDeadZoneChangesNothing() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 4)

        #expect(rules.result(forSwipeUpTravel: 0, marks: marks, isZoomed: false) == .noChange)
        #expect(rules.result(forSwipeUpTravel: 40, marks: marks, isZoomed: false) == .noChange)
    }

    @Test func aShortFlickAppliesTheLowestEnabledRating() throws {
        let rules = MarkingInputRules()
        let one = try MarkingFixtures.stars(1)

        #expect(
            rules.result(forSwipeUpTravel: 45, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: one), .rating))
    }

    @Test func eachSwipeStepAppliesItsEnabledRating() throws {
        let rules = MarkingInputRules()
        let one = try MarkingFixtures.stars(1)
        let two = try MarkingFixtures.stars(2)
        let three = try MarkingFixtures.stars(3)
        let four = try MarkingFixtures.stars(4)
        let five = try MarkingFixtures.stars(5)

        #expect(
            rules.result(forSwipeUpTravel: 40.5, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: one), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 100, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: two), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 160, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 220, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: four), .rating))
        // Past the top step the ladder stays on the highest enabled level.
        #expect(
            rules.result(forSwipeUpTravel: 10_000, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: five), .rating))
    }

    @Test func enabledOneThroughThreeCapTheSwipeAtThree() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 2, 3)))
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forSwipeUpTravel: 160, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 10_000, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func enabledOneThreeFiveGiveOneThenThree() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 3, 5)))
        let one = try MarkingFixtures.stars(1)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forSwipeUpTravel: 40.5, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: one), .rating))
        #expect(
            rules.result(forSwipeUpTravel: 100, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func aDisabledCurrentRatingStillTakesTheStepsEnabledLevel() throws {
        let rules = MarkingInputRules(
            settings: AppSettings(enabledRatings: try MarkingFixtures.enabled(1, 3, 5)))
        let marks = PhotoMarks(rating: try MarkingFixtures.stars(4))
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forSwipeUpTravel: 100, marks: marks, isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func swipingUpOnARejectedPhotoReplacesReject() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(rejected: true)
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forSwipeUpTravel: 160, marks: marks, isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }

    @Test func aSwipeNeverClearsARating() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 4)

        #expect(rules.result(forSwipeUpTravel: 20, marks: marks, isZoomed: false) == .noChange)
        #expect(rules.result(forSwipeUpTravel: -500, marks: marks, isZoomed: false) == .noChange)
    }

    @Test func applyingTheRatingAlreadyShownIsNoChange() throws {
        let rules = MarkingInputRules()
        let three = try MarkingFixtures.stars(3)

        #expect(
            rules.result(forSwipeUpTravel: 160, marks: PhotoMarks(rating: three), isZoomed: false)
                == .noChange)
    }

    @Test func gesturesOffSuppressesBothVerticalSwipes() throws {
        let rules = MarkingInputRules(settings: AppSettings(gesturesEnabled: false))
        let marks = try MarkingFixtures.marks(stars: 2)

        #expect(rules.result(forSwipeUpTravel: 160, marks: marks, isZoomed: false) == .noChange)
        #expect(
            rules.result(forSwipeDownTravel: -500, marks: marks, isZoomed: false) == .noChange)
    }

    @Test func theZoomedViewSuppressesBothVerticalSwipes() throws {
        let rules = MarkingInputRules()
        let marks = try MarkingFixtures.marks(stars: 2)

        #expect(rules.result(forSwipeUpTravel: 160, marks: marks, isZoomed: true) == .noChange)
        #expect(rules.result(forSwipeDownTravel: -500, marks: marks, isZoomed: true) == .noChange)
    }

    @Test func theSessionAndTheResolvedResultAgree() throws {
        let rules = MarkingInputRules()
        var session = rules.swipeRatingSession()

        let released = session.release(atTravel: 160)
        let three = try MarkingFixtures.stars(3)

        #expect(released == three)
        #expect(
            rules.result(forSwipeUpTravel: 160, marks: PhotoMarks(), isZoomed: false)
                == .mark(MarkChange(rating: three), .rating))
    }
}
