import CloveCore
import SwiftUI
import UIKit

/// Adds continuous input to the native toolbar control without replacing the bar button's
/// rendering or popover source item. The recognizer uses the control's actual hit region.
struct ToolbarRatingGesture: UIViewRepresentable {
    let rating: Rating
    let enabledRatings: EnabledRatings
    let canMark: Bool
    let began: () -> Void
    let preview: (Rating) -> Void
    let commit: (Rating) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.isUserInteractionEnabled = false
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowObserver, context: Context) {
        context.coordinator.input = self
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowObserver, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class WindowObserver: UIView {
        var windowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var input: ToolbarRatingGesture
        private weak var window: UIWindow?
        private var active: ToolbarRatingGesture?
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(track(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            return pan
        }()

        init(_ input: ToolbarRatingGesture) { self.input = input }

        func attach(to next: UIWindow?) {
            guard window !== next else { return }
            window?.removeGestureRecognizer(pan)
            active = nil
            window = next
            next?.addGestureRecognizer(pan)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard input.canMark else { return false }
            // Follow UIKit's actual touch target. A modal overlay can cover the button's
            // coordinates without belonging to that control.
            var target = touch.view
            while let view = target {
                if view.accessibilityIdentifier == "clove.duo.rating" { return true }
                target = view.superview
            }
            return false
        }

        @objc private func track(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                active = input
                active?.began()
            case .changed:
                guard let active else { return }
                active.preview(resolved(pan.translation(in: pan.view).y, input: active))
            case .ended:
                guard let active else { return }
                active.commit(resolved(pan.translation(in: pan.view).y, input: active))
                self.active = nil
            case .cancelled, .failed:
                active?.cancel()
                active = nil
            default:
                break
            }
        }

        private func resolved(_ translation: CGFloat, input: ToolbarRatingGesture) -> Rating {
            let start = input.rating.starCount ?? 0
            let steps = Int((-translation / 30).rounded())
            let value = min(5, max(0, start + steps))
            return input.enabledRatings.levels.last { ($0.starCount ?? 0) <= value } ?? .unrated
        }

    }
}
