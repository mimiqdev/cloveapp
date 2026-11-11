import Testing

import CloveCore

private func rating(_ value: Int) throws -> Rating {
    try #require(Rating(rawValue: value))
}

@Test func allFiveLevelsGiveFiveOrderedSteps() throws {
    let enabled = EnabledRatings.all
    let one = try rating(1)
    let two = try rating(2)
    let three = try rating(3)
    let four = try rating(4)
    let five = try rating(5)

    #expect(enabled.levels == [one, two, three, four, five])
    #expect(enabled.count == 5)
    for step in 1...5 {
        #expect(enabled.rating(forSwipeStep: step) == (try rating(step)))
    }
}

@Test func levelsOneThroughThreeGiveThreeSteps() throws {
    let one = try rating(1)
    let two = try rating(2)
    let three = try rating(3)
    let four = try rating(4)
    let enabled = try #require(EnabledRatings([one, two, three]))

    #expect(enabled.count == 3)
    #expect(enabled.rating(forSwipeStep: 1) == one)
    #expect(enabled.rating(forSwipeStep: 2) == two)
    #expect(enabled.rating(forSwipeStep: 3) == three)
    // A longer swipe keeps the highest enabled level rather than inventing a fourth step.
    #expect(enabled.rating(forSwipeStep: 4) == three)
    #expect(enabled.rating(forSwipeStep: 0) == nil)
    #expect(enabled.rating(forSwipeStep: -1) == nil)
    #expect(!enabled.canApply(four))
    #expect(enabled.next(after: three) == nil)
}

@Test func levelsOneThreeFiveMapToTheirOwnSteps() throws {
    let one = try rating(1)
    let three = try rating(3)
    let five = try rating(5)
    let enabled = try #require(EnabledRatings([one, three, five]))

    #expect(enabled.count == 3)
    #expect(enabled.rating(forSwipeStep: 1) == one)
    #expect(enabled.rating(forSwipeStep: 2) == three)
    #expect(enabled.rating(forSwipeStep: 3) == five)
    #expect(enabled.rating(forSwipeStep: 4) == five)
    #expect(enabled.canApply(one))
    #expect(!enabled.canApply(try rating(2)))
}

@Test func aSingleLevelStillHasOneStep() throws {
    let three = try rating(3)
    let enabled = try #require(EnabledRatings([three]))

    #expect(enabled.count == 1)
    #expect(enabled.rating(forSwipeStep: 1) == three)
    #expect(enabled.rating(forSwipeStep: 2) == three)
    #expect(enabled.canApply(three))
    #expect(!enabled.canApply(try rating(1)))
    #expect(!enabled.canApply(try rating(5)))
    #expect(enabled.next(after: three) == nil)
}

@Test func enabledRatingsAreNeverEmpty() throws {
    let three = try rating(3)
    let single = try #require(EnabledRatings([three]))

    #expect(EnabledRatings([Rating]()) == nil)
    #expect(EnabledRatings([Rating.unrated]) == nil)
    #expect(EnabledRatings([Rating.unrated, three]) == nil)
    // Reject is not a star level, so the ladder can never produce it.
    #expect(EnabledRatings([Rating.rejected]) == nil)
    #expect(EnabledRatings([Rating.rejected, three]) == nil)

    // Turning off the last remaining level is refused; the set keeps its one step.
    #expect(single.with(three, enabled: false) == single)
    // Zero is not a level, so toggling it changes nothing.
    #expect(single.with(.unrated, enabled: true) == single)
    #expect(single.with(.unrated, enabled: false) == single)
}

@Test func applyingRatingsAcceptsClearAndEnabledLevelsOnly() throws {
    let one = try rating(1)
    let two = try rating(2)
    let three = try rating(3)
    let four = try rating(4)
    let five = try rating(5)
    let enabled = try #require(EnabledRatings([one, three, five]))

    #expect(enabled.canApply(.unrated))
    #expect(!enabled.canApply(.rejected))
    #expect(enabled.canApply(one))
    #expect(enabled.canApply(three))
    #expect(enabled.canApply(five))
    #expect(!enabled.canApply(two))
    #expect(!enabled.canApply(four))
}

@Test func nextEnabledRatingRaisesAndStopsAtTheTop() throws {
    let one = try rating(1)
    let two = try rating(2)
    let three = try rating(3)
    let four = try rating(4)
    let five = try rating(5)
    let enabled = try #require(EnabledRatings([one, three, five]))

    #expect(enabled.next(after: .unrated) == one)
    #expect(enabled.next(after: one) == three)
    #expect(enabled.next(after: two) == three)
    #expect(enabled.next(after: three) == five)
    #expect(enabled.next(after: four) == five)
    #expect(enabled.next(after: five) == nil)

    let all = EnabledRatings.all
    #expect(all.next(after: .unrated) == one)
    #expect(all.next(after: .rejected) == one)
    #expect(all.next(after: one) == two)
    #expect(all.next(after: four) == five)
    #expect(all.next(after: five) == nil)
}

@Test func togglingLevelsKeepsOrderAndNeverEmptiesTheSet() throws {
    let one = try rating(1)
    let two = try rating(2)
    let three = try rating(3)
    let five = try rating(5)
    let enabled = try #require(EnabledRatings([one, three, five]))

    #expect(enabled.with(three, enabled: false).levels == [one, five])
    #expect(enabled.with(two, enabled: true).levels == [one, two, three, five])
    // Enabling an already enabled level and disabling an absent one are no-ops.
    #expect(enabled.with(three, enabled: true) == enabled)
    #expect(enabled.with(two, enabled: false) == enabled)
    // Turning off the last remaining level is refused.
    let lastRemaining = enabled.with(three, enabled: false).with(five, enabled: false)
    #expect(lastRemaining.levels == [one])
    #expect(lastRemaining.with(one, enabled: false) == lastRemaining)
}

@Test func levelsAreSortedAndDeduplicated() throws {
    let one = try rating(1)
    let three = try rating(3)
    let five = try rating(5)
    let enabled = try #require(EnabledRatings([five, one, three, one, five]))

    #expect(enabled.levels == [one, three, five])
}
