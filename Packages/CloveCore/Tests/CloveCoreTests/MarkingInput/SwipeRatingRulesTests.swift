import Testing

import CloveCore

@Suite struct SwipeRatingRulesTests {
    @Test func travelInsideTheDeadZoneIsStepZero() {
        let rules = SwipeRatingRules.standard

        #expect(rules.step(forTravel: 0) == 0)
        #expect(rules.step(forTravel: 20) == 0)
        #expect(rules.step(forTravel: 39.9) == 0)
        #expect(rules.step(forTravel: 40) == 0)
        #expect(rules.step(forTravel: -50) == 0)
    }

    @Test func eachStepBoundaryAddsOneStep() {
        let rules = SwipeRatingRules.standard

        #expect(rules.step(forTravel: 40.1) == 1)
        #expect(rules.step(forTravel: 99.9) == 1)
        #expect(rules.step(forTravel: 100) == 2)
        #expect(rules.step(forTravel: 159.9) == 2)
        #expect(rules.step(forTravel: 160) == 3)
        #expect(rules.step(forTravel: 220) == 4)
        #expect(rules.step(forTravel: 280) == 5)
        #expect(rules.step(forTravel: 340) == 6)
    }

    @Test func theMaximumStepCapsTheLadder() {
        let rules = SwipeRatingRules.standard

        #expect(rules.step(forTravel: 1_000, maximumStep: 5) == 5)
        #expect(rules.step(forTravel: 1_000, maximumStep: 3) == 3)
        #expect(rules.step(forTravel: 39, maximumStep: 5) == 0)
        #expect(rules.step(forTravel: 1_000, maximumStep: 0) == 0)
    }

    @Test func anUnboundedTravelCannotOverflowTheStep() {
        let rules = SwipeRatingRules.standard

        #expect(rules.step(forTravel: .infinity) == Int.max)
        #expect(rules.step(forTravel: 1_000, maximumStep: 5) == 5)
    }

    @Test func theLaunchStartingValuesAreDocumentedInOnePlace() {
        #expect(SwipeRatingRules.standard.stepDistance == 60)
        #expect(SwipeRatingRules.standard.deadZone == 40)
    }

    @Test func aNonPositiveStepDistanceOnlyReportsTheDeadZone() {
        let rules = SwipeRatingRules(stepDistance: 0, deadZone: 40)

        #expect(rules.step(forTravel: 100) == 0)
    }
}
