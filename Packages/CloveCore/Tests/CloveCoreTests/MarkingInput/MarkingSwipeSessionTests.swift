import CloveCore
import Testing

@Suite struct MarkingSwipeSessionTests {
    /// Sweep every stage in both directions, returning across the start in the same gesture.
    @Test(arguments: [-1, 0, 1, 3, 5], [false, true])
    func slowCrossingsFromEveryStartingRating(start: Int, skipLevels: Bool) throws {
        let enabled = skipLevels ? try MarkingFixtures.enabled(1, 3, 5) : .all
        let initial = try #require(Rating(rawValue: start))
        let ladder = [-1, 0] + enabled.levels.map(\.rawValue)
        let anchor = try #require(ladder.firstIndex(of: start))
        var session = MarkingSwipeSession(startingRating: initial, enabledRatings: enabled)
        #expect(session.update(travel: 0, elapsed: 0.1).isEmpty)
        #expect(session.mode == .slow)
        let up = session.update(travel: 600, elapsed: 2)
        #expect(up.map(\.rating.rawValue) == Array(ladder.dropFirst(anchor + 1)))
        #expect(up.allSatisfy { $0.haptic == .step })
        let down = session.update(travel: -600, elapsed: 4)
        #expect(down.map(\.rating.rawValue) == Array(ladder.dropLast().reversed()))
        #expect(down.allSatisfy { $0.haptic == .step })
        let back = session.update(travel: 0, elapsed: 6)
        #expect(back.map(\.rating.rawValue) == Array(ladder.dropFirst().prefix(anchor)))
        #expect(session.rating == initial)
        #expect(session.release(travel: 0, elapsed: 7).isEmpty)
    }

    @Test(arguments: [-1, 0, 1, 3, 5], [false, true])
    func slowDistancesAndReverseAcrossStart(start: Int, skipLevels: Bool) throws {
        let enabled = skipLevels ? try MarkingFixtures.enabled(1, 3, 5) : .all
        let ladder = [-1, 0] + enabled.levels.map(\.rawValue)
        let anchor = try #require(ladder.firstIndex(of: start))
        var session = MarkingSwipeSession(
            startingRating: try #require(Rating(rawValue: start)), enabledRatings: enabled)
        session.update(travel: 0, elapsed: 0.1)
        for steps in [1, 2, 3, 4, 5, 6, 0, -1, -2, -3, -4, -5, -6, 0, 1] {
            session.update(travel: Double(steps) * MarkingSwipeRules.stepDistance, elapsed: 10)
            #expect(
                session.rating.rawValue == ladder[min(max(anchor + steps, 0), ladder.count - 1)])
        }
    }

    @Test(arguments: [-1, 0, 1, 3, 5], [false, true])
    func quickStopsReversalAndCancel(start: Int, skipLevels: Bool) throws {
        let initial = try #require(Rating(rawValue: start))
        let enabled = skipLevels ? try MarkingFixtures.enabled(1, 3, 5) : .all
        var session = MarkingSwipeSession(startingRating: initial, enabledRatings: enabled)
        let clear = session.update(travel: -60, elapsed: 0.1)
        if start == -1 {
            #expect(session.mode == .slow)
            #expect(clear.isEmpty)
            session.update(travel: 60, elapsed: 0.3)
            #expect(session.rating == .unrated)
            session.update(travel: 120, elapsed: 0.5)
            #expect(session.rating.rawValue == 1)
            return
        }
        #expect(session.mode == .quickDown)
        #expect(clear.map(\.rating) == [.unrated])
        #expect(clear.map(\.haptic) == [.clear])
        #expect(session.update(travel: -179, elapsed: 0.3).isEmpty)
        let reject = session.update(travel: -180, elapsed: 0.5)
        #expect(reject.map(\.rating) == [.rejected])
        #expect(reject.map(\.haptic) == [.reject])
        // Holding has no special meaning, and a return from Reject passes through clear.
        #expect(session.update(travel: -180, elapsed: 5).isEmpty)
        #expect(session.update(travel: -100, elapsed: 6).map(\.rating) == [.unrated])
        #expect(session.update(travel: -1, elapsed: 6.5).isEmpty)
        #expect(session.rating == .unrated)
        #expect(session.update(travel: 60, elapsed: 7).map(\.rating) == [initial])
        #expect(session.rating == initial)
        #expect(session.release(travel: 600, elapsed: 8).isEmpty)
        #expect(session.rating == initial)
    }

    @Test func oneQuickSampleReportsBothStopsAndBothReturnCrossings() throws {
        let initial = try #require(Rating(rawValue: 3))
        var session = MarkingSwipeSession(startingRating: initial)
        #expect(
            session.release(travel: -200, elapsed: 0.08).map(\.rating) == [.unrated, .rejected])
        #expect(session.update(travel: 10, elapsed: 1).map(\.rating) == [.unrated, initial])
    }

    @Test func aQuickStartFollowedByAHoldKeepsItsModeAndClearPreview() throws {
        var session = MarkingSwipeSession(startingRating: try #require(Rating(rawValue: 3)))
        session.update(travel: -70, elapsed: 0.06)
        // The UI's one-shot window sample also runs when no further touch movement arrives.
        #expect(session.update(travel: -70, elapsed: 0.1).map(\.rating) == [.unrated])
        #expect(session.mode == .quickDown)
        #expect(session.update(travel: -70, elapsed: 5).isEmpty)
        #expect(session.release(travel: -70, elapsed: 6).isEmpty)
        #expect(session.rating == .unrated)
    }

    @Test func lateSamplesUseTheInitialWindowAndNotLaterAcceleration() {
        var session = MarkingSwipeSession(startingRating: .unrated)
        session.update(travel: -10, elapsed: 0.09)
        session.update(travel: -200, elapsed: 0.3)
        #expect(session.mode == .slow)
        var held = MarkingSwipeSession(startingRating: .unrated)
        held.update(travel: -70, elapsed: 0.06)
        held.release(travel: -70, elapsed: 2)
        #expect(held.mode == .quickDown)
        #expect(held.rating == .unrated)
    }

    @Test func firstWindowSelectsModeOnceAndQuickUpIsSlow() {
        var slow = MarkingSwipeSession(startingRating: .unrated)
        #expect(slow.update(travel: -10, elapsed: 0.05).isEmpty)
        #expect(slow.mode == nil)
        slow.update(travel: -20, elapsed: 0.1)
        slow.update(travel: -200, elapsed: 0.15)
        #expect(slow.mode == .slow)
        var up = MarkingSwipeSession(startingRating: .rejected)
        up.update(travel: 120, elapsed: 0.1)
        #expect(up.mode == .slow)
        #expect(up.rating.rawValue == 1)
        up.update(travel: -200, elapsed: 0.2)
        #expect(up.mode == .slow)
        #expect(up.rating == .rejected)
    }

    @Test func disabledCurrentValueIsAnAnchorAndOtherDisabledValuesAreSkipped() throws {
        var session = MarkingSwipeSession(
            startingRating: try #require(Rating(rawValue: 4)),
            enabledRatings: try MarkingFixtures.enabled(1, 3, 5))
        session.update(travel: 0, elapsed: 0.1)
        #expect(session.update(travel: -120, elapsed: 1).map(\.rating.rawValue) == [3, 1])
        #expect(session.update(travel: 0, elapsed: 2).map(\.rating.rawValue) == [3, 4])
        #expect(session.update(travel: 60, elapsed: 3).map(\.rating.rawValue) == [5])
    }

    @Test func twoSlowStepsFromThreePreviewOneAndReleaseAddsNoMomentum() throws {
        var session = MarkingSwipeSession(startingRating: try #require(Rating(rawValue: 3)))
        session.update(travel: -10, elapsed: 0.1)
        #expect(session.update(travel: -120, elapsed: 1).map(\.rating.rawValue) == [2, 1])
        #expect(session.release(travel: -120, elapsed: 1.1).isEmpty)
        #expect(session.rating.rawValue == 1)
    }
}
