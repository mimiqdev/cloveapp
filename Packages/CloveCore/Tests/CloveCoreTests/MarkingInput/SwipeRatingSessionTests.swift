import Testing

import CloveCore

@Suite struct SwipeRatingSessionTests {
    @Test func aNewSessionStartsInsideTheDeadZone() {
        let session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.step == 0)
        #expect(session.travel == 0)
        #expect(session.rating == nil)
        #expect(session.maximumStep == 5)
    }

    @Test func theSessionReportsRaisingAndLoweringAcrossBoundaries() {
        var session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.update(travel: 30) == nil)
        #expect(session.update(travel: 45) == .raised(to: 1))
        #expect(session.update(travel: 130) == .raised(to: 2))
        #expect(session.update(travel: 135) == nil)
        #expect(session.update(travel: 90) == .lowered(to: 1))
        #expect(session.update(travel: 20) == .lowered(to: 0))
        #expect(session.step == 0)
        #expect(session.travel == 20)
    }

    @Test func aReportedChangeCarriesTheNewStep() throws {
        var session = SwipeRatingSession(enabledRatings: .all)

        let raised = session.update(travel: 280)
        #expect(raised?.step == 5)
        #expect(raised == .raised(to: 5))
        #expect(session.rating == (try MarkingFixtures.stars(5)))

        let lowered = session.update(travel: 160)
        #expect(lowered?.step == 3)
        #expect(lowered == .lowered(to: 3))
    }

    @Test func theSessionNeverStepsPastTheEnabledLevels() {
        var session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.update(travel: 1_000) == .raised(to: 5))
        #expect(session.update(travel: 2_000) == nil)
        #expect(session.step == 5)
    }

    @Test func aThreeLevelLadderStopsAtThreeSteps() throws {
        let session = SwipeRatingSession(enabledRatings: try MarkingFixtures.enabled(1, 2, 3))

        #expect(session.maximumStep == 3)
        #expect(session.step(forTravel: 1_000) == 3)
        #expect(session.step(forTravel: 100) == 2)
    }

    @Test func releaseAtTheStartWritesNothing() {
        var session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.release(atTravel: 0) == nil)
        #expect(session.release(atTravel: 40) == nil)
        #expect(session.step == 0)
    }

    @Test func aShortFlickGivesTheLowestStep() throws {
        var session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.release(atTravel: 45) == (try MarkingFixtures.stars(1)))
    }

    @Test func theReleasePositionDecidesNotTheHighestTravel() {
        var session = SwipeRatingSession(enabledRatings: .all)

        #expect(session.update(travel: 250) == .raised(to: 4))
        #expect(session.release(atTravel: 30) == nil)
        #expect(session.step == 0)
    }

    @Test func theCappedStepAppliesTheTopEnabledLevel() throws {
        var session = SwipeRatingSession(enabledRatings: try MarkingFixtures.enabled(1, 3, 5))

        #expect(session.release(atTravel: 2_000) == (try MarkingFixtures.stars(5)))
        #expect(session.step == 3)
    }
}
