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

    private func position(
        at start: CGPoint, in size: CGSize = CGSize(width: 390, height: 650),
        chromeIsVisible: Bool = true
    ) -> CGPoint {
        DetailSwipeFeedbackBadge.position(
            in: size, startLocation: start, controlsHeight: 140,
            chromeIsVisible: chromeIsVisible)
    }
}
