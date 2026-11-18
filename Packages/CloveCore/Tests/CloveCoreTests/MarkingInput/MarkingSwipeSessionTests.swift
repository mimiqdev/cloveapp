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
        #expect(compact.clearTravel == 26)
        #expect(compact.rejectTravel == 44)
        #expect(compact.reversalHysteresis == 4)

        let compactThree = MarkingSwipeGeometry(
            containerHeight: 390, enabledRatings: try MarkingFixtures.enabled(1, 3, 5))
        #expect(compactThree.enabledCount == 3)
        #expect(compactThree.upStep == 35)
        #expect(abs(compactThree.reversalHysteresis - 7.7) < 0.0001)

        // iPhone 17 Pro reference (H = 760)
        let reference = MarkingSwipeGeometry(containerHeight: 760, enabledRatings: .all)
        #expect(reference.containerHeight == 760)
        #expect(abs(reference.upEntry - 22.8) < 0.0001)
        #expect(abs(reference.upSpan - 136.8) < 0.0001)
        #expect(abs(reference.upStep - 28.5) < 0.0001)
        #expect(abs(reference.clearTravel - 34.2) < 0.0001)
        #expect(abs(reference.rejectTravel - 60.8) < 0.0001)
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
        #expect(tablet.clearTravel == 40)
        #expect(tablet.rejectTravel == 68)
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
        for height in [390.0, 760.0, 1200.0] {
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
        #expect(session.update(travel: -60.0).isEmpty)
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

        #expect(session.update(travel: -60.0).isEmpty)
        let toReject = session.update(travel: -g.rejectTravel)
        #expect(toReject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])

        // Reversing up from Reject crosses back to Unrated at -rejectTravel + reversalHysteresis (-54.53).
        #expect(session.update(travel: -55.0).isEmpty)
        let rejectToUnrated = session.update(travel: -54.5)
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
        #expect(full.update(travel: -61).map(\.rating.rawValue) == [-1])
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

        // At H = 760: clearTravel = 34.2, rejectTravel = 60.8, total Reject = -95.0.
        #expect(session.update(travel: -34.0).isEmpty)
        #expect(session.rating == initial)

        let clear = session.update(travel: -34.2)
        #expect(clear == [MarkingStageCrossing(rating: .unrated, haptic: .clear)])
        #expect(session.rating == .unrated)

        #expect(session.update(travel: -94.5).isEmpty)
        let reject = session.update(travel: -95.0)
        #expect(reject == [MarkingStageCrossing(rating: .rejected, haptic: .reject)])
        #expect(session.rating == .rejected)

        // Returning crosses Clear at -95.0 + 6.27 = -88.73, then restores initial at -34.2 + 6.27 = -27.93.
        #expect(session.update(travel: -89.0).isEmpty)
        #expect(
            session.update(travel: -88.7) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
        #expect(session.update(travel: -28.5).isEmpty)
        #expect(
            session.update(travel: -27.9) == [MarkingStageCrossing(rating: initial, haptic: .step)])
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

    @Test func overshootTopFiveAndRejectThenReturnHasNoExtraDeadTravel() throws {
        // From unrated at H = 760: maxTravel = 136.8 + 28.5 = 165.3. Dragging to +600 clamps at 165.3.
        var topOvershoot = MarkingSwipeSession(startingRating: .unrated)
        #expect(topOvershoot.update(travel: 600).map(\.rating.rawValue) == [1, 2, 3, 4, 5])
        // Returning one upStep + reversalHysteresis (28.5 + 6.27 = 34.77) steps to 4★ immediately.
        #expect(topOvershoot.update(travel: 565.5).isEmpty)
        #expect(
            topOvershoot.update(travel: 565.0) == [
                MarkingStageCrossing(rating: Rating(rawValue: 4)!, haptic: .step)
            ])
        // One upStep more (28.5) steps to 3★.
        #expect(
            topOvershoot.update(travel: 536.5) == [
                MarkingStageCrossing(rating: Rating(rawValue: 3)!, haptic: .step)
            ])

        // From 3★ at H = 760: minTravel = -(2 * 34.2 + 60.8) = -129.2. Dragging to -500 clamps at -129.2.
        let three = try #require(Rating(rawValue: 3))
        var bottomOvershoot = MarkingSwipeSession(startingRating: three)
        #expect(bottomOvershoot.update(travel: -500).map(\.rating.rawValue) == [0, -1])
        // Moving back up clearTravel + reversalHysteresis (34.2 + 6.27 = 40.47) reaches Clear (0).
        #expect(bottomOvershoot.update(travel: -460.0).isEmpty)
        #expect(
            bottomOvershoot.update(travel: -459.5) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
        // Moving up rejectTravel more (60.8) restores 3★.
        #expect(
            bottomOvershoot.update(travel: -398.5) == [
                MarkingStageCrossing(rating: three, haptic: .step)
            ])

        // Starting at 5★ (top endpoint) clamps at +upEntry (22.8); dragging down upEntry + clearTravel (57.0) clears.
        let five = try #require(Rating(rawValue: 5))
        var fromFive = MarkingSwipeSession(startingRating: five)
        #expect(fromFive.update(travel: 200).isEmpty)
        #expect(fromFive.rating == five)
        #expect(fromFive.update(travel: 143.5).isEmpty)
        #expect(
            fromFive.update(travel: 142.9) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ]
        )

        // Starting at Reject (bottom endpoint) clamps at -clearTravel (-34.2); dragging up clearTravel + upEntry (57.0) clears.
        var fromReject = MarkingSwipeSession(startingRating: .rejected)
        #expect(fromReject.update(travel: -200).isEmpty)
        #expect(fromReject.rating == .rejected)
        #expect(fromReject.update(travel: -143.5).isEmpty)
        #expect(
            fromReject.update(travel: -142.9) == [
                MarkingStageCrossing(rating: .unrated, haptic: .clear)
            ])
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
        #expect(session.update(travel: -95).map(\.rating.rawValue) == [0, -1])
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
        #expect(session.geometry.rejectTravel == 44)
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
