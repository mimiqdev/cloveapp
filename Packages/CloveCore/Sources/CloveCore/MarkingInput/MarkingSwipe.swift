/// Which marking swipe a one-finger drag on the detail preview has become (PRD Detail gestures).
///
/// PRD Detail gestures gives the fit view two vertical swipes: up rates by distance and down
/// rejects. The view asks ``MarkingSwipeRules`` once, as the drag is about to begin, and the
/// answer says whether the drag is a marking swipe at all or is left unclaimed.
public enum MarkingSwipe: Hashable, Sendable {
    /// Swiping up: rate by distance (PRD Rating by swipe distance).
    case rating

    /// Swiping down: Reject (PRD Detail gestures).
    case reject
}

/// The drag that begins a marking swipe, and the drags that must not (PRD Detail gestures).
///
/// A marking swipe shares the preview with the other gestures PRD Detail gestures lists: the
/// horizontal swipe that navigates, the edge single taps and the centre double tap, and the
/// scroll view's own pinch and pan. The taps need no help, because a pan never begins without
/// movement. A drag begins a marking swipe only when it is vertical enough, so a more horizontal
/// drag is left unclaimed and a horizontal navigation gesture stays available.
///
/// PRD Detail gestures turns vertical marking swipes off while zoomed, where a one-finger drag
/// pans instead, and PRD Gesture-related settings can turn marking gestures off entirely. Both
/// answer nil here rather than at the call site, so the view asks one question and keeps no
/// marking rule of its own.
public struct MarkingSwipeRules: Hashable, Sendable {
    /// How much larger the vertical travel must be than the horizontal travel, as a ratio.
    ///
    /// The launch value of 1 is the 45° split: a drag at least as steep as a diagonal is a
    /// marking swipe, anything flatter stays navigation. It is a starting value, tunable with
    /// the other gesture distances.
    public var verticalToHorizontalRatio: Double

    /// The launch starting value: a drag as steep as 45° begins a marking swipe.
    public static let standard = MarkingSwipeRules()

    /// Creates the direction split; the default is the launch starting value.
    public init(verticalToHorizontalRatio: Double = 1) {
        self.verticalToHorizontalRatio = verticalToHorizontalRatio
    }

    /// The marking swipe a drag has become, or nil when it must not start one.
    ///
    /// The travel is measured from touch-down in points, with up positive to match
    /// ``SwipeRatingSession`` and ``RejectSwipeSession``; the caller negates UIKit's downward y.
    /// A drag begins a marking swipe when marking gestures are on, the view is at fit, and the
    /// vertical travel is at least ``verticalToHorizontalRatio`` times the horizontal travel.
    /// The result is the direction only: how far the finger is decides the step, which is the
    /// session's job (PRD Rating by swipe distance).
    public func swipe(
        horizontalTravel: Double,
        verticalTravel: Double,
        isZoomed: Bool,
        gesturesEnabled: Bool
    ) -> MarkingSwipe? {
        guard gesturesEnabled, !isZoomed else { return nil }
        let vertical = abs(verticalTravel)
        guard vertical > 0, vertical >= abs(horizontalTravel) * verticalToHorizontalRatio else {
            return nil
        }
        return verticalTravel > 0 ? .rating : .reject
    }
}
