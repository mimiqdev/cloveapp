import CloveCore
import SwiftUI
import Testing

@testable import Clove

/// The ladder the swipe indicator mirrors is 48 × 204 with a 44 pt chip and a 10 pt gap
/// (`design/handoff/components.md`, owner decision, 2026-11-13, #227).
@MainActor
struct DetailSwipeIndicatorTests {
    @Test func rightSideTouchPlacesTheWholeBarToItsLeftAndCentresOnTheStart() {
        #expect(position(at: CGPoint(x: 300, y: 300)) == CGPoint(x: 230, y: 300))
    }

    @Test func leftThirdTouchPlacesTheBarToItsRight() {
        #expect(position(at: CGPoint(x: 100, y: 300)) == CGPoint(x: 170, y: 300))
        // Exactly one third uses the left side of the finger.
        #expect(position(at: CGPoint(x: 130, y: 300)) == CGPoint(x: 60, y: 300))
    }

    @Test func topAndBottomTouchesKeepTheWholeBarClearOfChrome() {
        #expect(position(at: CGPoint(x: 300, y: 0)) == CGPoint(x: 230, y: 137))
        #expect(position(at: CGPoint(x: 300, y: 650)) == CGPoint(x: 230, y: 373))
    }

    @Test func hiddenChromeAllowsTheBarBelowTheFilmstripButInsideTheScreen() {
        #expect(
            position(at: CGPoint(x: 300, y: 650), chromeIsVisible: false)
                == CGPoint(x: 230, y: 513))
        #expect(
            position(at: CGPoint(x: 300, y: 0), chromeIsVisible: false)
                == CGPoint(x: 230, y: 137))
    }

    @Test func narrowStageClampsTheBarInsideItsHorizontalEdges() {
        let size = CGSize(width: 180, height: 650)
        #expect(position(at: CGPoint(x: 59, y: 300), in: size).x == 129)
        #expect(position(at: CGPoint(x: 60, y: 300), in: size).x == 32)
        #expect(
            position(at: CGPoint(x: 29, y: 300), in: CGSize(width: 90, height: 650)).x == 58)
    }

    @Test func verticalStarBarDisplayChipMatchesStarSwipeClearAndRejectStages() throws {
        for raw in 1...5 {
            let rating = try #require(Rating(rawValue: raw))
            let stage = VerticalStarBarDisplay.chipStage(for: rating, isReject: false)
            #expect(stage == .ratingSwipe)
            #expect(stage.symbolName == "flag.slash")
            #expect(stage.token == .secondaryText)
        }

        let clearStage = VerticalStarBarDisplay.chipStage(for: .unrated, isReject: false)
        #expect(clearStage == .clear)
        #expect(clearStage.symbolName == "star.slash")
        #expect(clearStage.token == .secondaryText)

        for rejectStage in [
            VerticalStarBarDisplay.chipStage(for: .rejected, isReject: true),
            VerticalStarBarDisplay.chipStage(for: .rejected, isReject: false),
            VerticalStarBarDisplay.chipStage(for: .unrated, isReject: true),
        ] {
            #expect(rejectStage == .reject)
            #expect(rejectStage.symbolName == "flag.slash.fill")
            #expect(rejectStage.token == .reject)
        }
    }

    @Test func markingSwipeSessionTransitionsProduceMatchingDisplayChipStages() throws {
        let threeStars = try #require(Rating(rawValue: 3))
        var session = MarkingSwipeSession(
            startingRating: threeStars, containerHeight: 650)

        let startingStage = VerticalStarBarDisplay.chipStage(
            for: session.rating, isReject: session.rating == .rejected)
        #expect(startingStage.symbolName == "flag.slash")
        #expect(startingStage.token == .secondaryText)

        session.update(travel: 30)
        let fourStarStage = VerticalStarBarDisplay.chipStage(
            for: session.rating, isReject: session.rating == .rejected)
        #expect(session.rating.rawValue == 4)
        #expect(fourStarStage.symbolName == "flag.slash")
        #expect(fourStarStage.token == .secondaryText)

        session.update(travel: -36)
        let clearStage = VerticalStarBarDisplay.chipStage(
            for: session.rating, isReject: session.rating == .rejected)
        #expect(session.rating == .unrated)
        #expect(clearStage.symbolName == "star.slash")
        #expect(clearStage.token == .secondaryText)

        session.update(travel: -120)
        let rejectStage = VerticalStarBarDisplay.chipStage(
            for: session.rating, isReject: session.rating == .rejected)
        #expect(session.rating == .rejected)
        #expect(rejectStage.symbolName == "flag.slash.fill")
        #expect(rejectStage.token == .reject)
    }

    private func position(
        at start: CGPoint, in size: CGSize = CGSize(width: 390, height: 650),
        chromeIsVisible: Bool = true
    ) -> CGPoint {
        DetailSwipeFeedbackBadge.position(
            in: size, startLocation: start, controlsHeight: 140,
            chromeIsVisible: chromeIsVisible)
    }
}
