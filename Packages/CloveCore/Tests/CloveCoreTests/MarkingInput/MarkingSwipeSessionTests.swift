import CloveCore
import Testing

@Suite struct MarkingSwipeSessionTests {
    private static func expectedLadder(start: Int, enabled: EnabledRatings) -> [Int] {
        let higher = enabled.levels.map(\.rawValue).filter { $0 > start }
        return Array(Set([-1, 0, start] + higher)).sorted()
    }

    /// Sweep the full anchor-symmetric ladder up and down across the start in one gesture.
    @Test(arguments: [-1, 0, 1, 3, 5], [false, true])
    func crossingsFromEveryStartingRatingFollowAnchorSymmetricLadder(
        start: Int, skipLevels: Bool
    ) throws {
        let enabled = skipLevels ? try MarkingFixtures.enabled(1, 3, 5) : .all
        let initial = try #require(Rating(rawValue: start))
        let ladder = Self.expectedLadder(start: start, enabled: enabled)
        let anchor = try #require(ladder.firstIndex(of: start))
        var session = MarkingSwipeSession(startingRating: initial, enabledRatings: enabled)

        #expect(session.update(travel: 0).isEmpty)
        #expect(session.rating == initial)

        let maxRelative = (ladder.count - 1) - anchor
        let maxTravel =
            MarkingSwipeRules.deadZone + Double(maxRelative) * MarkingSwipeRules.stepDistance
        let minTravel =
            -(MarkingSwipeRules.deadZone + Double(anchor) * MarkingSwipeRules.stepDistance)

        let up = session.update(travel: maxTravel)
        #expect(up.map(\.rating.rawValue) == Array(ladder.dropFirst(anchor + 1)))

        let down = session.update(travel: 0)
        #expect(
            down.map(\.rating.rawValue) == Array(ladder.dropFirst(anchor).dropLast().reversed()))
        #expect(session.rating == initial)

        // From an existing star, downward is always Clear (0) then Reject (-1).
        if start > 0 {
            #expect(ladder.prefix(anchor) == [-1, 0])
        }

        let downPastAnchor = session.update(travel: minTravel)
        #expect(downPastAnchor.map(\.rating.rawValue) == Array(ladder.prefix(anchor).reversed()))

        let back = session.update(travel: 0)
        #expect(back.map(\.rating.rawValue) == Array(ladder.dropFirst().prefix(anchor)))
        #expect(session.rating == initial)
        #expect(session.release(travel: 0).isEmpty)
    }

    @Test func unratedDown30ptRejectsImmediatelyWithoutOriginDeadBand() {
        var session = MarkingSwipeSession(startingRating: .unrated)
        #expect(session.update(travel: -29).isEmpty)
        #expect(session.rating == .unrated)

        let crossing = session.update(travel: -30)
        #expect(crossing == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
        #expect(session.rating == .rejected)
        #expect(session.release(travel: -30).isEmpty)
    }

    @Test func unratedUpToOneStarThenReverseToRejectIsShortSymmetricRoundTrip() {
        var session = MarkingSwipeSession(startingRating: .unrated)

        let up = session.update(travel: 30)
        #expect(up == [MarkingStageCrossing(rating: Rating(rawValue: 1)!, haptic: .step)])

        // Reversal hysteresis holds 1★ at +23pt, returns to unrated at +22pt, then Rejects at -30pt.
        #expect(session.update(travel: 23).isEmpty)
        #expect(session.rating.rawValue == 1)

        let backToUnrated = session.update(travel: 22)
        #expect(backToUnrated == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])

        #expect(session.update(travel: -29).isEmpty)
        let toReject = session.update(travel: -30)
        #expect(toReject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
    }

    @Test func unratedAllowsFineSelectionUpAndDownBetweenStarsBeforeRelease() throws {
        var session = MarkingSwipeSession(startingRating: .unrated)
        #expect(session.update(travel: 30).map(\.rating.rawValue) == [1])
        #expect(session.update(travel: 75).map(\.rating.rawValue) == [2])
        #expect(session.update(travel: 120).map(\.rating.rawValue) == [3])
        #expect(session.update(travel: 112).map(\.rating.rawValue) == [2])
        #expect(session.update(travel: 67).map(\.rating.rawValue) == [1])
        #expect(session.update(travel: 22).map(\.rating.rawValue) == [0])
        #expect(session.update(travel: -30).map(\.rating.rawValue) == [-1])
        #expect(session.release(travel: 75).map(\.rating.rawValue) == [0, 1, 2])
        #expect(session.rating == (try #require(Rating(rawValue: 2))))
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func existingStarsDownOnceClearsAndDownTwiceRejectsIndependentOfStart(start: Int) throws {
        let initial = try #require(Rating(rawValue: start))
        var session = MarkingSwipeSession(startingRating: initial)

        #expect(session.update(travel: -29).isEmpty)
        #expect(session.rating == initial)

        let clear = session.update(travel: -30)
        #expect(clear == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])
        #expect(session.rating == .unrated)

        #expect(session.update(travel: -74).isEmpty)
        let reject = session.update(travel: -75)
        #expect(reject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
        #expect(session.rating == .rejected)

        // Returning crosses Clear then restores the original rating at -67 and -22.
        #expect(session.update(travel: -68).isEmpty)
        #expect(
            session.update(travel: -67) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
        #expect(session.update(travel: -23).isEmpty)
        #expect(
            session.update(travel: -22) == [MarkingStageCrossing(rating: initial, haptic: .step)])
    }

    @Test func threeStarsUpToFourThenBackToOriginCancelsToThreeStars() throws {
        let three = try #require(Rating(rawValue: 3))
        var session = MarkingSwipeSession(startingRating: three)

        let toFour = session.update(travel: 30)
        #expect(toFour.map(\.rating.rawValue) == [4])
        #expect(toFour.map(\.haptic) == [.step])

        #expect(session.update(travel: 23).isEmpty)
        #expect(session.rating.rawValue == 4)

        let back = session.update(travel: 0)
        #expect(back == [MarkingStageCrossing(rating: three, haptic: .step)])
        #expect(session.release(travel: 0).isEmpty)
        #expect(session.rating == three)
    }

    @Test func overshootTopFiveAndRejectThenReturnHasNoExtraDeadTravel() throws {
        // From unrated, overshoot 5★ (max boundary 255pt) up to +600pt.
        var topOvershoot = MarkingSwipeSession(startingRating: .unrated)
        #expect(topOvershoot.update(travel: 600).map(\.rating.rawValue) == [1, 2, 3, 4, 5])
        // Returning 53pt (45pt bucket + 8pt hysteresis) immediately steps to 4★, then 45pt per step.
        #expect(
            topOvershoot.update(travel: 547) == [
                MarkingStageCrossing(rating: Rating(rawValue: 4)!, haptic: .step)
            ])
        #expect(
            topOvershoot.update(travel: 502) == [
                MarkingStageCrossing(rating: Rating(rawValue: 3)!, haptic: .step)
            ])

        // From 3★, overshoot Reject (min boundary -120pt) down to -500pt.
        let three = try #require(Rating(rawValue: 3))
        var bottomOvershoot = MarkingSwipeSession(startingRating: three)
        #expect(bottomOvershoot.update(travel: -500).map(\.rating.rawValue) == [0, -1])
        // Moving back up 53pt reaches Clear (0); 45pt more restores 3★.
        #expect(
            bottomOvershoot.update(travel: -447) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
        #expect(
            bottomOvershoot.update(travel: -402) == [
                MarkingStageCrossing(rating: three, haptic: .step)
            ])

        // Starting at 5★ (top endpoint) and dragging up +200pt clamps at +30pt; dragging down 60pt clears.
        let five = try #require(Rating(rawValue: 5))
        var fromFive = MarkingSwipeSession(startingRating: five)
        #expect(fromFive.update(travel: 200).isEmpty)
        #expect(fromFive.rating == five)
        #expect(
            fromFive.update(travel: 140) == [MarkingStageCrossing(rating: .unrated, haptic: .clear)]
        )

        // Starting at Reject (bottom endpoint) and dragging down -200pt clamps at -30pt; dragging up 60pt clears.
        var fromReject = MarkingSwipeSession(startingRating: .rejected)
        #expect(fromReject.update(travel: -200).isEmpty)
        #expect(fromReject.rating == .rejected)
        #expect(
            fromReject.update(travel: -140) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
    }

    @Test func disabledCurrentValueIsAnchorAndOnlyHigherDisabledStarsAreSkipped() throws {
        let two = try #require(Rating(rawValue: 2))
        var session = MarkingSwipeSession(
            startingRating: two,
            enabledRatings: try MarkingFixtures.enabled(1, 3, 5))

        // Ladder from 2★ with {1, 3, 5}: [-1, 0, 2, 3, 5] (1★ is below start and excluded).
        #expect(session.update(travel: 30).map(\.rating.rawValue) == [3])
        #expect(session.update(travel: 75).map(\.rating.rawValue) == [5])
        #expect(session.update(travel: 0).map(\.rating.rawValue) == [3, 2])
        #expect(session.update(travel: -75).map(\.rating.rawValue) == [0, -1])
        #expect(session.update(travel: 0).map(\.rating.rawValue) == [0, 2])
        #expect(session.rating == two)
    }

    @Test func releaseAddsNoMomentumAfterCrossings() throws {
        var session = MarkingSwipeSession(startingRating: .unrated)
        let crossings = session.update(travel: 120)
        #expect(crossings.map(\.rating.rawValue) == [1, 2, 3])
        #expect(crossings.allSatisfy { $0.haptic == .step })
        #expect(session.release(travel: 120).isEmpty)
        #expect(session.rating.rawValue == 3)
    }
}
