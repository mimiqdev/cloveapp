import CloveCore
import SwiftUI
import Testing

@testable import Clove

@MainActor
struct DetailSwipeIndicatorTests {
    @Test func rightSideTouchPlacesTheWholeBarToItsLeftAndCentresOnTheStart() {
        #expect(position(at: CGPoint(x: 300, y: 300)) == CGPoint(x: 234, y: 300))
    }

    @Test func leftThirdTouchPlacesTheBarToItsRight() {
        #expect(position(at: CGPoint(x: 100, y: 300)) == CGPoint(x: 166, y: 300))
        // Exactly one third uses the left side of the finger.
        #expect(position(at: CGPoint(x: 130, y: 300)) == CGPoint(x: 64, y: 300))
    }

    @Test func topAndBottomTouchesKeepTheWholeBarClearOfChrome() {
        #expect(position(at: CGPoint(x: 300, y: 0)) == CGPoint(x: 234, y: 130))
        #expect(position(at: CGPoint(x: 300, y: 650)) == CGPoint(x: 234, y: 380))
    }

    @Test func hiddenChromeAllowsTheBarBelowTheFilmstripButInsideTheScreen() {
        #expect(
            position(at: CGPoint(x: 300, y: 650), chromeIsVisible: false)
                == CGPoint(x: 234, y: 520))
        #expect(
            position(at: CGPoint(x: 300, y: 0), chromeIsVisible: false)
                == CGPoint(x: 234, y: 130))
    }

    @Test func narrowStageClampsTheBarInsideItsHorizontalEdges() {
        let size = CGSize(width: 180, height: 650)
        #expect(position(at: CGPoint(x: 59, y: 300), in: size).x == 125)
        #expect(position(at: CGPoint(x: 60, y: 300), in: size).x == 28)
        #expect(
            position(at: CGPoint(x: 29, y: 300), in: CGSize(width: 90, height: 650)).x == 62)
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
