import Testing

import CloveCore

@Suite("Photo navigation swipes")
struct NavigationSwipeRulesTests {
    @Test func dominantStartingAxisLocksNavigationOrMarking() {
        #expect(NavigationSwipeRules.axis(horizontal: -20, vertical: 5) == .horizontal)
        #expect(NavigationSwipeRules.axis(horizontal: 5, vertical: -20) == .vertical)
        #expect(NavigationSwipeRules.axis(horizontal: 10, vertical: 10) == .vertical)
    }

    @Test func quarterWidthReleaseMovesOnlyOnePhoto() {
        #expect(step(-99) == 0)
        #expect(step(-100) == 1)
        #expect(step(100) == -1)
        #expect(step(900) == -1)
    }

    @Test func flickNeedsTravelAndMatchingVelocity() {
        #expect(step(-20, velocity: -700) == 1)
        #expect(step(20, velocity: 700) == -1)
        #expect(step(-20, velocity: 700) == 0)
        #expect(step(-5, velocity: -900) == 0)
        #expect(step(-20, velocity: -599) == 0)
    }

    @Test func endsResistAndNeverNavigateOutsideTheOrder() {
        for travel in [-800.0, -100, 100, 800] {
            #expect(
                NavigationSwipeRules.step(
                    travel: travel, velocity: travel * 10, width: 400,
                    hasPrevious: false, hasNext: false) == 0)
            let offset = NavigationSwipeRules.offset(
                travel: travel, width: 400, hasPrevious: false, hasNext: false)
            #expect(abs(offset) < abs(travel))
            #expect(abs(offset) < 400)
            #expect(offset * travel > 0)
        }
        #expect(
            NavigationSwipeRules.offset(
                travel: -120, width: 400, hasPrevious: false, hasNext: true) == -120)
        #expect(
            NavigationSwipeRules.offset(
                travel: 120, width: 400, hasPrevious: true, hasNext: false) == 120)
        #expect(
            NavigationSwipeRules.step(
                travel: -120, velocity: -900, width: 0, hasPrevious: true, hasNext: true) == 0)
    }

    private func step(_ travel: Double, velocity: Double = 0) -> Int {
        NavigationSwipeRules.step(
            travel: travel, velocity: velocity, width: 400, hasPrevious: true, hasNext: true)
    }
}
