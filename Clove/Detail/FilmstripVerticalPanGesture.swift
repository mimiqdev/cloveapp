import CloveCore
import SwiftUI
import UIKit

/// Axis-locked UIKit vertical pan gesture for Detail's filmstrip tracks.
///
/// Declines horizontal and opposite-direction drags inside `gestureRecognizerShouldBegin(_:)`
/// before recognition begins so `ScrollView`'s native horizontal pan recognizer owns horizontal
/// scrolling with zero gesture contention.
struct FilmstripVerticalPanGesture: UIGestureRecognizerRepresentable {
    enum Direction: Sendable {
        case down
        case up
    }

    let direction: Direction
    let isEnabled: Bool
    let onDragChanged: (Bool) -> Void
    let onTrigger: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(self)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        context.coordinator.parent = self
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        context.coordinator.handle(recognizer)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: FilmstripVerticalPanGesture
        private var touchStart: CGPoint?
        private var isTrackingDrag = false

        init(_ parent: FilmstripVerticalPanGesture) {
            self.parent = parent
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard parent.isEnabled, gestureRecognizer.isEnabled else { return false }
            if gestureRecognizer.state == .possible, gestureRecognizer.numberOfTouches == 0 {
                touchStart = touch.location(in: gestureRecognizer.view)
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled, gestureRecognizer.isEnabled,
                let pan = gestureRecognizer as? UIPanGestureRecognizer
            else {
                touchStart = nil
                return false
            }

            let vector = initialVector(for: pan)
            guard vector != .zero,
                abs(vector.y) > FilmstripVerticalGesture.dominanceRatio * abs(vector.x)
            else {
                touchStart = nil
                return false
            }

            let matchesDirection =
                switch parent.direction {
                case .down: vector.y > 0
                case .up: vector.y < 0
                }
            if !matchesDirection {
                touchStart = nil
            }
            return matchesDirection
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Once a vertically dominant pan in the matching direction begins, allow it to coexist
            // with an enclosing/child scroll view's pan so slight initial diagonal wobble cannot
            // swallow the expand/collapse swipe, while horizontal drags already failed before begin.
            otherGestureRecognizer.view is UIScrollView
        }

        func handle(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                if !isTrackingDrag {
                    isTrackingDrag = true
                    parent.onDragChanged(true)
                }
            case .ended:
                let translation = resolvedTranslation(for: pan)
                let shouldFire: Bool
                if parent.isEnabled {
                    switch parent.direction {
                    case .down:
                        shouldFire = FilmstripVerticalGesture.shouldExpand(
                            horizontal: Double(translation.x),
                            vertical: Double(translation.y))
                    case .up:
                        shouldFire = FilmstripVerticalGesture.shouldCollapse(
                            horizontal: Double(translation.x),
                            vertical: Double(translation.y))
                    }
                } else {
                    shouldFire = false
                }
                endTracking()
                if shouldFire {
                    parent.onTrigger()
                }
            case .cancelled, .failed:
                endTracking()
            default:
                break
            }
        }

        private func endTracking() {
            touchStart = nil
            if isTrackingDrag {
                isTrackingDrag = false
                parent.onDragChanged(false)
            }
        }

        private func initialVector(for pan: UIPanGestureRecognizer) -> CGPoint {
            let translation = pan.translation(in: pan.view)
            if translation != .zero {
                return translation
            }
            if let touchStart, pan.numberOfTouches > 0 {
                let current = pan.location(in: pan.view)
                let delta = CGPoint(x: current.x - touchStart.x, y: current.y - touchStart.y)
                if delta != .zero {
                    return delta
                }
            }
            return pan.velocity(in: pan.view)
        }

        private func resolvedTranslation(for pan: UIPanGestureRecognizer) -> CGPoint {
            let translation = pan.translation(in: pan.view)
            guard let touchStart else { return translation }
            let location = pan.location(in: pan.view)
            let delta = CGPoint(x: location.x - touchStart.x, y: location.y - touchStart.y)
            if abs(delta.y) > abs(translation.y) {
                return CGPoint(
                    x: abs(delta.x) > abs(translation.x) ? delta.x : translation.x,
                    y: delta.y)
            }
            return translation
        }
    }
}
