import CloveCore
import Testing
import UIKit

@testable import Clove

@MainActor
struct ToolbarRatingGestureTests {
    @Test func ratingControlReceivesItsOwnTouches() {
        let (window, rating, _) = views()
        let glyph = UIView(frame: rating.bounds)
        rating.addSubview(glyph)
        let coordinator = coordinator()
        coordinator.attach(to: window)

        #expect(
            coordinator.gestureRecognizer(UIPanGestureRecognizer(), shouldReceive: Touch(glyph)))
    }

    @Test func modalOverlayBlocksRatingTouchesAtTheSameCoordinates() {
        let (window, _, overlay) = views()
        let coordinator = coordinator()
        coordinator.attach(to: window)
        overlay.isHidden = false
        let target = window.hitTest(CGPoint(x: 30, y: 30), with: nil)
        #expect(target === overlay)

        #expect(
            !coordinator.gestureRecognizer(UIPanGestureRecognizer(), shouldReceive: Touch(overlay)))
    }

    @Test func readOnlyRatingControlRejectsTouches() {
        let (window, rating, _) = views()
        let coordinator = coordinator(canMark: false)
        coordinator.attach(to: window)

        #expect(
            !coordinator.gestureRecognizer(UIPanGestureRecognizer(), shouldReceive: Touch(rating)))
    }

    private func coordinator(canMark: Bool = true) -> ToolbarRatingGesture.Coordinator {
        ToolbarRatingGesture.Coordinator(
            ToolbarRatingGesture(
                rating: .unrated, enabledRatings: .all, canMark: canMark,
                began: {}, preview: { _ in }, commit: { _ in }, cancel: {}))
    }

    private func views() -> (UIWindow, UIView, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.isHidden = false
        let rating = UIView(frame: CGRect(x: 20, y: 20, width: 44, height: 44))
        rating.accessibilityIdentifier = "clove.duo.rating"
        window.addSubview(rating)
        let overlay = UIView(frame: window.bounds)
        overlay.isHidden = true
        window.addSubview(overlay)
        return (window, rating, overlay)
    }

    private final class Touch: UITouch {
        private let target: UIView

        init(_ target: UIView) {
            self.target = target
            super.init()
        }

        override var view: UIView? { target }

        override func location(in view: UIView?) -> CGPoint {
            target.window?.convert(CGPoint(x: 30, y: 30), to: view) ?? .zero
        }
    }
}
