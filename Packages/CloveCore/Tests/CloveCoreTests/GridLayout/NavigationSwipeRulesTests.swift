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

    @Test func endsNeverNavigateOutsideTheOrder() {
        for travel in [-800.0, -100, 100, 800] {
            #expect(
                NavigationSwipeRules.step(
                    travel: travel, velocity: travel * 10, width: 400,
                    hasPrevious: false, hasNext: false) == 0)
        }
        #expect(
            NavigationSwipeRules.step(
                travel: -120, velocity: -900, width: 0, hasPrevious: true, hasNext: true) == 0)
    }

    private func step(_ travel: Double, velocity: Double = 0) -> Int {
        NavigationSwipeRules.step(
            travel: travel, velocity: velocity, width: 400, hasPrevious: true, hasNext: true)
    }
}
