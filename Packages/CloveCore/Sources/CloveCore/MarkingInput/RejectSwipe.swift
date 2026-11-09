/// The downward distance that rejects a photo (PRD Detail gestures: swipe down → Reject).
///
/// The PRD gives no value, so 100 pt is Clove's starting choice: more than one rating step, so
/// a rating attempt does not reject by accident, and small enough for one comfortable thumb
/// movement. It is subject to tuning with the swipe rating distances. It is in points on every
/// device and never scales with screen size.
public struct RejectSwipeRules: Hashable, Sendable {
    /// The downward travel, in points, that reaches Reject.
    public var threshold: Double

    /// The launch starting value: 100 pt.
    public static let standard = RejectSwipeRules()

    /// Creates the threshold; the default is the launch starting value.
    public init(threshold: Double = 100) {
        self.threshold = threshold
    }

    /// Whether the travel reaches the threshold; down is negative (PRD Detail gestures).
    public func isPastThreshold(travel: Double) -> Bool {
        -travel >= threshold
    }
}

/// The live state of one swipe-down gesture (PRD Detail gestures).
///
/// The UI reads `isPastThreshold` to show whether releasing would reject, and applies the
/// result only at release. Releasing back inside the threshold does nothing.
public struct RejectSwipeSession: Hashable, Sendable {
    /// The threshold this session measures with.
    public let rules: RejectSwipeRules

    /// The last travel reported, in points with up positive, so a swipe down is negative.
    public private(set) var travel: Double = 0

    /// Starts a gesture at the touch-down point with no travel.
    public init(rules: RejectSwipeRules = .standard) {
        self.rules = rules
    }

    /// Whether releasing now would reject.
    public var isPastThreshold: Bool { rules.isPastThreshold(travel: travel) }

    /// Records the travel since touch-down.
    public mutating func update(travel newTravel: Double) {
        travel = newTravel
    }

    /// Ends the gesture at the release position and reports whether it rejects.
    public mutating func release(atTravel travel: Double) -> Bool {
        update(travel: travel)
        return isPastThreshold
    }
}
