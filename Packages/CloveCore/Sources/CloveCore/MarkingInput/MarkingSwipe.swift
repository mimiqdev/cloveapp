import Foundation

/// Starting values for continuous marking, in points and seconds on every device.
/// Tune these on an iPhone; release has no momentum and holding never changes the stage.
public struct MarkingSwipeRules: Hashable, Sendable {
    public static let stepDistance: Double = 60
    public static let quickClearDistance: Double = 60
    public static let quickRejectDistance: Double = 180
    public static let velocityWindow: Double = 0.1
    public static let quickDownVelocity: Double = 500
    public static let standard = MarkingSwipeRules()

    /// The initial axis split only; reversing vertically never changes the claimed axis.
    public var verticalToHorizontalRatio: Double

    public init(verticalToHorizontalRatio: Double = 1) {
        self.verticalToHorizontalRatio = verticalToHorizontalRatio
    }

    public func beginsSwipe(
        horizontalTravel: Double, verticalTravel: Double, isZoomed: Bool, gesturesEnabled: Bool,
        zoomedRatingSwipe: ZoomedRatingSwipe = .twoFinger
    ) -> Bool {
        guard gesturesEnabled else { return false }
        if isZoomed && zoomedRatingSwipe != .singleFingerAxisLock {
            return false
        }
        return abs(verticalTravel) > 0
            && abs(verticalTravel) >= abs(horizontalTravel) * verticalToHorizontalRatio
    }
}

/// Pure disambiguation between a two-finger vertical rating swipe and a pinch or pan while zoomed.
public enum ZoomedTwoFingerSwipeRules {
    /// Minimum finger movement or relative spread (points) before classifying a two-touch drag.
    public static let decisionTravel: Double = 8

    /// Maximum relative separation change relative to shared vertical movement (`|meanY|`).
    public static let maximumSpreadRatio: Double = 0.7

    /// Minimum fraction of the faster finger's vertical motion the slower finger must share.
    public static let minimumCohesionRatio: Double = 0.35

    /// Minimum vertical travel (points) both touches must contribute so anchored pinches fail.
    public static let minimumPerTouchVerticalTravel: Double = 4

    public struct TouchDelta: Hashable, Sendable {
        public let horizontal: Double
        public let vertical: Double

        public init(horizontal: Double, vertical: Double) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    public enum Decision: Hashable, Sendable {
        case undecided
        case swipe
        case pinchOrOther
    }

    public static func classify(
        first: TouchDelta,
        second: TouchDelta,
        verticalToHorizontalRatio: Double = MarkingSwipeRules.standard.verticalToHorizontalRatio
    ) -> Decision {
        let travel1 = hypot(first.horizontal, first.vertical)
        let travel2 = hypot(second.horizontal, second.vertical)
        let spread = hypot(second.horizontal - first.horizontal, second.vertical - first.vertical)
        guard max(travel1, travel2, spread) >= decisionTravel else {
            return .undecided
        }
        guard first.vertical != 0, second.vertical != 0,
            (first.vertical > 0) == (second.vertical > 0)
        else {
            return .pinchOrOther
        }
        let absY1 = abs(first.vertical)
        let absY2 = abs(second.vertical)
        guard min(absY1, absY2) >= minimumPerTouchVerticalTravel,
            min(absY1, absY2) >= max(absY1, absY2) * minimumCohesionRatio
        else {
            return .pinchOrOther
        }
        guard absY1 >= abs(first.horizontal) * verticalToHorizontalRatio,
            absY2 >= abs(second.horizontal) * verticalToHorizontalRatio
        else {
            return .pinchOrOther
        }
        let meanX = (first.horizontal + second.horizontal) / 2
        let meanY = (first.vertical + second.vertical) / 2
        guard abs(meanY) > 0,
            abs(meanY) >= abs(meanX) * verticalToHorizontalRatio,
            spread <= abs(meanY) * maximumSpreadRatio
        else {
            return .pinchOrOther
        }
        return .swipe
    }
}

/// One crossed boundary, in travel order, including boundaries skipped by a touch sample.
public struct MarkingStageCrossing: Hashable, Sendable {
    public let rating: Rating
    public let haptic: Haptic

    public enum Haptic: Hashable, Sendable {
        case step
        case clear
        case reject
    }
}

/// One continuous vertical drag. Travel is measured from touch-down, with up positive.
///
/// The first approximately 100 ms select the mode once. Before then the preview stays at the
/// starting value. A release inside that window selects the mode from the available samples.
/// The session only previews; its owner commits `rating` once at release or discards on cancel.
public struct MarkingSwipeSession: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case slow
        case quickDown
    }

    public let startingRating: Rating
    public let enabledRatings: EnabledRatings
    public private(set) var mode: Mode?
    public private(set) var rating: Rating
    private var stage: Int?
    private var initialTravel: Double = 0
    private var initialElapsed: Double = 0

    public init(startingRating: Rating, enabledRatings: EnabledRatings = .all) {
        self.startingRating = startingRating
        self.enabledRatings = enabledRatings
        self.rating = startingRating
    }

    /// Classifies once using the average vertical velocity at the start of the drag, then follows
    /// position only. A quick upward start and a downward start on Reject use the slow ladder.
    @discardableResult
    public mutating func update(travel: Double, elapsed: Double) -> [MarkingStageCrossing] {
        if mode == nil {
            let window = MarkingSwipeRules.velocityWindow
            guard elapsed >= window else {
                initialTravel = travel
                initialElapsed = elapsed
                return []
            }
            // Interpolate the sample at the window boundary, so a late callback cannot make
            // acceleration after the window (or a hold) change the initial classification.
            let fraction = (window - initialElapsed) / (elapsed - initialElapsed)
            let windowTravel = initialTravel + (travel - initialTravel) * fraction
            chooseMode(travel: windowTravel, elapsed: window)
        }
        return move(to: travel)
    }

    /// Resolves a very short swipe too; otherwise release uses the already chosen mode.
    @discardableResult
    public mutating func release(travel: Double, elapsed: Double) -> [MarkingStageCrossing] {
        if mode == nil && elapsed < MarkingSwipeRules.velocityWindow {
            chooseMode(travel: travel, elapsed: elapsed)
        }
        return update(travel: travel, elapsed: elapsed)
    }

    private mutating func chooseMode(travel: Double, elapsed: Double) {
        mode =
            startingRating != .rejected && elapsed > 0
                && -travel / elapsed >= MarkingSwipeRules.quickDownVelocity ? .quickDown : .slow
    }

    private mutating func move(to travel: Double) -> [MarkingStageCrossing] {
        let ladder: [Rating]
        let initialStage: Int
        let next: Int
        if mode == .quickDown {
            ladder = [startingRating, .unrated, .rejected]
            initialStage = 0
            if -travel >= MarkingSwipeRules.quickRejectDistance {
                next = 2
            } else if -travel >= MarkingSwipeRules.quickClearDistance
                || ((stage ?? 0) > 0 && travel < 0)
            {
                // Once clear is reached, returning past the original touch cancels it.
                next = 1
            } else {
                next = 0
            }
        } else {
            // A disabled current value remains an anchor, so returning to the start restores
            // it. Away from the anchor only enabled stars (plus 0 and Reject) can be reached.
            ladder = Array(Set([.rejected, .unrated, startingRating] + enabledRatings.levels))
                .sorted()
            initialStage = ladder.prefix { $0 < startingRating }.count
            let steps = Int(min(abs(travel) / MarkingSwipeRules.stepDistance, Double(ladder.count)))
            next = min(max(initialStage + (travel >= 0 ? steps : -steps), 0), ladder.count - 1)
        }
        let previous = stage ?? initialStage
        let direction = next >= previous ? 1 : -1
        let crossed = stride(from: previous + direction, through: next, by: direction).map {
            index in
            let value = ladder[index]
            let haptic: MarkingStageCrossing.Haptic =
                mode == .quickDown && index > 0
                ? (index == 1 ? .clear : .reject) : .step
            return MarkingStageCrossing(rating: value, haptic: haptic)
        }
        stage = next
        rating = ladder[next]
        return crossed
    }
}
