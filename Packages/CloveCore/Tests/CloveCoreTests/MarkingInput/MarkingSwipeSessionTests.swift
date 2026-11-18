import CloveCore
import Testing

@Suite struct MarkingSwipeSessionTests {
    private static func expectedLadder(start: Int, enabled: EnabledRatings) -> [Int] {
        let higher = enabled.levels.map(\.rawValue).filter { $0 > start }
        return Array(Set([-1, 0, start] + higher)).sorted()
    }

    @Test func geometryScalesProportionallyAndClampsAcrossDeviceHeights() throws {
        // Compact / landscape floor (H = 390)
        let compact = MarkingSwipeGeometry(containerHeight: 390, enabledRatings: .all)
        #expect(compact.containerHeight == 390)
        #expect(compact.enabledCount == 5)
        #expect(compact.upEntry == 18)
        #expect(compact.upSpan == 88)
        #expect(abs(compact.upStep - 17.5) < 0.0001)
        #expect(compact.clearTravel == 32)
        #expect(compact.rejectTravel == 64)
        #expect(compact.reversalHysteresis == 4)

        let compactThree = MarkingSwipeGeometry(
            containerHeight: 390, enabledRatings: try MarkingFixtures.enabled(1, 3, 5))
        #expect(compactThree.enabledCount == 3)
        #expect(compactThree.upStep == 35)
        #expect(abs(compactThree.reversalHysteresis - 7.7) < 0.0001)

        // Duo Expanded (H = 535)
        let duoExpanded = MarkingSwipeGeometry(containerHeight: 535, enabledRatings: .all)
        #expect(duoExpanded.containerHeight == 535)
        #expect(duoExpanded.upEntry == 18)
        #expect(abs(duoExpanded.upSpan - 96.3) < 0.0001)
        #expect(abs(duoExpanded.upStep - 19.575) < 0.0001)
        #expect(duoExpanded.clearTravel == 32)
        #expect(duoExpanded.rejectTravel == 64)
        #expect(abs(duoExpanded.reversalHysteresis - (0.22 * 19.575)) < 0.0001)

        // iPhone 17 Pro reference (H = 760)
        let reference = MarkingSwipeGeometry(containerHeight: 760, enabledRatings: .all)
        #expect(reference.containerHeight == 760)
        #expect(abs(reference.upEntry - 22.8) < 0.0001)
        #expect(abs(reference.upSpan - 136.8) < 0.0001)
        #expect(abs(reference.upStep - 28.5) < 0.0001)
        #expect(abs(reference.clearTravel - 38.0) < 0.0001)
        #expect(abs(reference.rejectTravel - 76.0) < 0.0001)
        #expect(abs(reference.reversalHysteresis - 6.27) < 0.0001)

        let referenceThree = MarkingSwipeGeometry(
            containerHeight: 760, enabledRatings: try MarkingFixtures.enabled(1, 3, 5))
        #expect(abs(referenceThree.upStep - 57.0) < 0.0001)
        #expect(referenceThree.reversalHysteresis == 8)

        let referencePick = MarkingSwipeGeometry(
            containerHeight: 760, enabledRatings: try MarkingFixtures.enabled(5))
        #expect(referencePick.enabledCount == 1)
        #expect(abs(referencePick.upStep - referencePick.upEntry) < 0.0001)
        #expect(abs(referencePick.reversalHysteresis - (0.22 * 22.8)) < 0.0001)

        // iPad ceiling (H = 1200)
        let tablet = MarkingSwipeGeometry(containerHeight: 1200, enabledRatings: .all)
        #expect(tablet.containerHeight == 1200)
        #expect(tablet.upEntry == 26)
        #expect(tablet.upSpan == 148)
        #expect(abs(tablet.upStep - 30.5) < 0.0001)
        #expect(tablet.clearTravel == 42)
        #expect(tablet.rejectTravel == 80)
        #expect(abs(tablet.reversalHysteresis - 6.71) < 0.0001)

        // Fallback for non-positive or non-finite container heights
        for invalid in [0.0, -120.0, .nan, .infinity, -.infinity] {
            let fallback = MarkingSwipeRules.geometry(containerHeight: invalid)
            #expect(fallback == reference)
        }
    }

    /// Sweep the full anchor-symmetric ladder up and down across the start in one gesture.
    @Test(
        arguments: [-1, 0, 1, 3, 5],
        ["all", "odd", "pick"]
    )
    func crossingsFromEveryStartingRatingFollowAnchorSymmetricLadder(
        start: Int, preset: String
    ) throws {
        let enabled: EnabledRatings =
            switch preset {
            case "odd": try MarkingFixtures.enabled(1, 3, 5)
            case "pick": try MarkingFixtures.enabled(5)
            default: .all
            }
        let initial = try #require(Rating(rawValue: start))
        let ladder = Self.expectedLadder(start: start, enabled: enabled)
        let anchor = try #require(ladder.firstIndex(of: start))
        for height in [390.0, 535.0, 760.0, 1200.0] {
            var session = MarkingSwipeSession(
                startingRating: initial, enabledRatings: enabled, containerHeight: height)
            let g = session.geometry

            #expect(session.update(travel: 0).isEmpty)
            #expect(session.rating == initial)

            let maxRelative = (ladder.count - 1) - anchor
            let topTarget =
                maxRelative > 0
                ? g.upEntry + Double(maxRelative - 1) * g.upStep + 1
                : g.upEntry
            let bottomTarget: Double =
                switch anchor {
                case 0: -g.clearTravel
                case 1: -(g.rejectTravel + 1)
                default: -(g.clearTravel + g.rejectTravel + 1)
                }

            let up = session.update(travel: topTarget)
            #expect(up.map(\.rating.rawValue) == Array(ladder.dropFirst(anchor + 1)))

            let down = session.update(travel: 0)
            #expect(
                down.map(\.rating.rawValue)
                    == Array(ladder.dropFirst(anchor).dropLast().reversed()))
            #expect(session.rating == initial)

            // From an existing star, downward is always Clear (0) then Reject (-1).
            if start > 0 {
                #expect(ladder.prefix(anchor) == [-1, 0])
            }

            let downPastAnchor = session.update(travel: bottomTarget)
            #expect(
                downPastAnchor.map(\.rating.rawValue) == Array(ladder.prefix(anchor).reversed()))

            let back = session.update(travel: 0)
            #expect(back.map(\.rating.rawValue) == Array(ladder.dropFirst().prefix(anchor)))
            #expect(session.rating == initial)
            #expect(session.release(travel: 0).isEmpty)
        }
    }

    @Test func unratedDownRejectsAtRejectTravelWithoutOriginDeadBand() {
        var session = MarkingSwipeSession(startingRating: .unrated)
        #expect(session.update(travel: -75.9).isEmpty)
        #expect(session.rating == .unrated)

        let crossing = session.update(travel: -session.geometry.rejectTravel)
        #expect(crossing == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
        #expect(session.rating == .rejected)
        #expect(session.release(travel: -session.geometry.rejectTravel).isEmpty)
    }

    @Test func unratedUpToOneStarThenReverseToRejectIsShortSymmetricRoundTrip() {
        var session = MarkingSwipeSession(startingRating: .unrated)
        let g = session.geometry

        // At H = 760: upEntry = 22.8, reversalHysteresis = 6.27 -> reverses at 16.53.
        #expect(session.update(travel: 22.7).isEmpty)
        let up = session.update(travel: g.upEntry)
        #expect(up == [MarkingStageCrossing(rating: Rating(rawValue: 1)!, haptic: .step)])

        #expect(session.update(travel: 16.6).isEmpty)
        #expect(session.rating.rawValue == 1)

        let backToUnrated = session.update(travel: 16.5)
        #expect(backToUnrated == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])

        #expect(session.update(travel: -75.9).isEmpty)
        let toReject = session.update(travel: -g.rejectTravel)
        #expect(toReject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])

        // Reversing up from Reject crosses back to Unrated at -rejectTravel + reversalHysteresis (-69.73).
        #expect(session.update(travel: -70.0).isEmpty)
        let rejectToUnrated = session.update(travel: -69.7)
        #expect(rejectToUnrated == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])
    }

    @Test func unratedAllowsFineSelectionAcrossAllAndSubsetEnabledRatings() throws {
        // Full 5-star sweep at H = 760: 22.8, 51.3, 79.8, 108.3, 136.8.
        var full = MarkingSwipeSession(startingRating: .unrated)
        #expect(full.update(travel: 23).map(\.rating.rawValue) == [1])
        #expect(full.update(travel: 52).map(\.rating.rawValue) == [2])
        #expect(full.update(travel: 80).map(\.rating.rawValue) == [3])
        #expect(full.update(travel: 73).map(\.rating.rawValue) == [2])
        #expect(full.update(travel: 44).map(\.rating.rawValue) == [1])
        #expect(full.update(travel: 16).map(\.rating.rawValue) == [0])
        #expect(full.update(travel: -75).isEmpty)
        #expect(full.update(travel: -76).map(\.rating.rawValue) == [-1])
        #expect(full.release(travel: 52).map(\.rating.rawValue) == [0, 1, 2])
        #expect(full.rating == (try #require(Rating(rawValue: 2))))

        // Subset {1, 3, 5} at H = 760: upEntry = 22.8, upStep = 57.0 -> 22.8, 79.8, 136.8.
        var subset = MarkingSwipeSession(
            startingRating: .unrated, enabledRatings: try MarkingFixtures.enabled(1, 3, 5))
        #expect(subset.update(travel: 23).map(\.rating.rawValue) == [1])
        #expect(subset.update(travel: 79).isEmpty)
        #expect(subset.update(travel: 80).map(\.rating.rawValue) == [3])
        #expect(subset.update(travel: 137).map(\.rating.rawValue) == [5])
        // Reversal hysteresis is 8.0 for <= 3 stars: 136.8 - 8.0 = 128.8.
        #expect(subset.update(travel: 129).isEmpty)
        #expect(subset.update(travel: 128.5).map(\.rating.rawValue) == [3])

        // Single-star Pick {5} at H = 760: hits 5★ immediately at upEntry = 22.8.
        var pick = MarkingSwipeSession(
            startingRating: .unrated, enabledRatings: try MarkingFixtures.enabled(5))
        #expect(pick.update(travel: 22).isEmpty)
        #expect(pick.update(travel: 23).map(\.rating.rawValue) == [5])
        #expect(pick.update(travel: 17).map(\.rating.rawValue) == [0])
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func existingStarsDownOnceClearsAndDownTwiceRejectsIndependentOfStart(start: Int) throws {
        let initial = try #require(Rating(rawValue: start))
        var session = MarkingSwipeSession(startingRating: initial)

        // At H = 760: clearTravel = 38.0, rejectTravel = 76.0, total Reject = -114.0.
        #expect(session.update(travel: -37.9).isEmpty)
        #expect(session.rating == initial)

        let clear = session.update(travel: -38.0)
        #expect(clear == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])
        #expect(session.rating == .unrated)

        #expect(session.update(travel: -113.9).isEmpty)
        let reject = session.update(travel: -114.0)
        #expect(reject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
        #expect(session.rating == .rejected)

        // Returning crosses Clear at -114.0 + 6.27 = -107.73, then restores initial at -38.0 + 6.27 = -31.73.
        #expect(session.update(travel: -108.0).isEmpty)
        #expect(
            session.update(travel: -107.7) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
        #expect(session.update(travel: -32.0).isEmpty)
        #expect(
            session.update(travel: -31.7) == [MarkingStageCrossing(rating: initial, haptic: .step)])
    }

    @Test func threeStarsUpStepsWithoutStretchingAcrossFullSpan() throws {
        let three = try #require(Rating(rawValue: 3))
        var session = MarkingSwipeSession(startingRating: three)

        // Starting from 3★ at H = 760: 4★ enters at +22.8, 5★ enters at +22.8 + 28.5 = +51.3.
        #expect(session.update(travel: 22.7).isEmpty)
        let toFour = session.update(travel: 22.8)
        #expect(
            toFour == [
                MarkingStageCrossing(rating: try #require(Rating(rawValue: 4)), haptic: .step)
            ])

        #expect(session.update(travel: 51.2).isEmpty)
        let toFive = session.update(travel: 51.3)
        #expect(
            toFive == [
                MarkingStageCrossing(rating: try #require(Rating(rawValue: 5)), haptic: .step)
            ])

        #expect(session.update(travel: 46).isEmpty)
        #expect(session.rating.rawValue == 5)

        let back = session.update(travel: 0)
        #expect(back.map(\.rating.rawValue) == [4, 3])
        #expect(session.release(travel: 0).isEmpty)
        #expect(session.rating == three)
    }

    @Test func rapidOvershootScrubbingNeverShiftsTouchOriginOrThresholds() throws {
        // From unrated at H = 760: up thresholds stay anchored at 22.8..136.8 and Reject at -76.0.
        var fromUnrated = MarkingSwipeSession(startingRating: .unrated)
        #expect(fromUnrated.update(travel: 600).map(\.rating.rawValue) == [1, 2, 3, 4, 5])
        #expect(fromUnrated.update(travel: 0).map(\.rating.rawValue) == [4, 3, 2, 1, 0])
        #expect(fromUnrated.rating == .unrated)

        #expect(fromUnrated.update(travel: -600).map(\.rating.rawValue) == [-1])
        #expect(fromUnrated.update(travel: 0).map(\.rating.rawValue) == [0])
        #expect(fromUnrated.rating == .unrated)

        #expect(fromUnrated.update(travel: 400).map(\.rating.rawValue) == [1, 2, 3, 4, 5])
        // 5★ -> 4★ reverses at 136.8 - 6.27 = 130.53 (unchanged by prior +600 / -600 / +400 scrubs).
        #expect(fromUnrated.update(travel: 130.6).isEmpty)
        #expect(fromUnrated.update(travel: 130.5).map(\.rating.rawValue) == [4])
        #expect(fromUnrated.update(travel: 102.0).map(\.rating.rawValue) == [3])
        #expect(fromUnrated.update(travel: 73.5).map(\.rating.rawValue) == [2])
        #expect(fromUnrated.update(travel: 45.0).map(\.rating.rawValue) == [1])
        #expect(fromUnrated.update(travel: 16.5).map(\.rating.rawValue) == [0])
        #expect(fromUnrated.update(travel: -75.9).isEmpty)
        #expect(fromUnrated.update(travel: -76.0).map(\.rating.rawValue) == [-1])
        #expect(fromUnrated.update(travel: 0).map(\.rating.rawValue) == [0])
        #expect(fromUnrated.rating == .unrated)

        // From 3★ at H = 760: clearTravel = 38.0, two-step Reject = -(38.0 + 76.0) = -114.0.
        let three = try #require(Rating(rawValue: 3))
        var fromThree = MarkingSwipeSession(startingRating: three)
        #expect(fromThree.update(travel: 600).map(\.rating.rawValue) == [4, 5])
        #expect(fromThree.update(travel: 0).map(\.rating.rawValue) == [4, 3])
        #expect(fromThree.rating == three)

        #expect(fromThree.update(travel: -600).map(\.rating.rawValue) == [0, -1])
        #expect(fromThree.update(travel: 0).map(\.rating.rawValue) == [0, 3])
        #expect(fromThree.rating == three)

        #expect(fromThree.update(travel: 400).map(\.rating.rawValue) == [4, 5])
        #expect(fromThree.update(travel: -37.9).map(\.rating.rawValue) == [4, 3])
        #expect(fromThree.rating == three)
        #expect(fromThree.update(travel: -38.0).map(\.rating.rawValue) == [0])
        #expect(fromThree.update(travel: -113.9).isEmpty)
        #expect(fromThree.update(travel: -114.0).map(\.rating.rawValue) == [-1])
        #expect(fromThree.update(travel: 0).map(\.rating.rawValue) == [0, 3])
        #expect(fromThree.rating == three)

        // Endpoints (5★ and Reject): overshooting past endpoints never shifts return thresholds.
        let five = try #require(Rating(rawValue: 5))
        var fromFive = MarkingSwipeSession(startingRating: five)
        #expect(fromFive.update(travel: 600).isEmpty)
        #expect(fromFive.update(travel: 0).isEmpty)
        #expect(fromFive.rating == five)
        #expect(fromFive.update(travel: -37.9).isEmpty)
        #expect(fromFive.update(travel: -38.0).map(\.rating.rawValue) == [0])
        #expect(fromFive.update(travel: -600).map(\.rating.rawValue) == [-1])
        #expect(fromFive.update(travel: 0).map(\.rating.rawValue) == [0, 5])
        #expect(fromFive.rating == five)

        var fromReject = MarkingSwipeSession(startingRating: .rejected)
        #expect(fromReject.update(travel: -600).isEmpty)
        #expect(fromReject.update(travel: 0).isEmpty)
        #expect(fromReject.rating == .rejected)
        #expect(fromReject.update(travel: 400).map(\.rating.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(fromReject.update(travel: 0).map(\.rating.rawValue) == [4, 3, 2, 1, 0, -1])
        #expect(fromReject.rating == .rejected)
    }

    @Test func disabledCurrentValueIsAnchorAndOnlyHigherDisabledStarsAreSkipped() throws {
        let two = try #require(Rating(rawValue: 2))
        var session = MarkingSwipeSession(
            startingRating: two,
            enabledRatings: try MarkingFixtures.enabled(1, 3, 5))

        // Ladder from 2★ with {1, 3, 5} at H = 760: [-1, 0, 2, 3, 5] (upEntry = 22.8, upStep = 57.0).
        #expect(session.update(travel: 23).map(\.rating.rawValue) == [3])
        #expect(session.update(travel: 80).map(\.rating.rawValue) == [5])
        #expect(session.update(travel: 0).map(\.rating.rawValue) == [3, 2])
        #expect(session.update(travel: -114).map(\.rating.rawValue) == [0, -1])
        #expect(session.update(travel: 0).map(\.rating.rawValue) == [0, 2])
        #expect(session.rating == two)
    }

    @Test func markingInputRulesForwardsContainerHeightAndEnabledRatings() throws {
        var settings = AppSettings()
        settings.enabledRatings = try MarkingFixtures.enabled(1, 3, 5)
        let rules = MarkingInputRules(settings: settings)
        let session = rules.swipeSession(startingRating: .unrated, containerHeight: 390)
        #expect(session.geometry.containerHeight == 390)
        #expect(session.geometry.enabledCount == 3)
        #expect(session.geometry.upEntry == 18)
        #expect(session.geometry.upStep == 35)
        #expect(session.geometry.clearTravel == 32)
        #expect(session.geometry.rejectTravel == 64)
    }

    @Test func releaseAddsNoMomentumAfterCrossings() throws {
        var session = MarkingSwipeSession(startingRating: .unrated)
        let crossings = session.update(travel: 80)
        #expect(crossings.map(\.rating.rawValue) == [1, 2, 3])
        #expect(crossings.allSatisfy { $0.haptic == .step })
        #expect(session.release(travel: 80).isEmpty)
        #expect(session.rating.rawValue == 3)
    }
}
