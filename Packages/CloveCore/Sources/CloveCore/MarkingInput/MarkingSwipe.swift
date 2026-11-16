import Foundation

/// Starting values for continuous marking, in points on every device.
/// Tune these on an iPhone; release has no momentum and holding never changes the stage.
public struct MarkingSwipeRules: Hashable, Sendable {
    public static let deadZone: Double = 30
    public static let stepDistance: Double = 45
    public static let reversalHysteresis: Double = 8
    public static let standard = MarkingSwipeRules()

    /// The initial axis split only; reversing vertically never changes the claimed axis.
    public var verticalToHorizontalRatio: Double

    public init(verticalToHorizontalRatio: Double = 1) {
        self.verticalToHorizontalRatio = verticalToHorizontalRatio
    }

    public func beginsSwipe(
        horizontalTravel: Double, verticalTravel: Double, isZoomed: Bool, gesturesEnabled: Bool,
        zoomedGestures: ZoomedGestures = .rateAndSwitch
    ) -> Bool {
        guard gesturesEnabled else { return false }
        if isZoomed && zoomedGestures != .rateAndSwitch {
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

    public init(rating: Rating, haptic: Haptic) {
        self.rating = rating
        self.haptic = haptic
    }

    public enum Haptic: Hashable, Sendable {
        case step
        case clear
        case reject
    }
}

/// One continuous vertical drag. Travel is measured from touch-down, with up positive.
///
/// The session uses an anchor-symmetric ladder around `startingRating`:
/// `sortedUnique([-1, 0, startingRating] ∪ { enabledStars > startingRating })`.
/// Preview and semantic haptics respond purely to position from the first movement, with uniform
/// buckets, reversal hysteresis, and endpoint overshoot clamping. The session only previews; its
/// owner commits `rating` once at release or discards on cancel.
public struct MarkingSwipeSession: Hashable, Sendable {
    public let startingRating: Rating
    public let enabledRatings: EnabledRatings
    public private(set) var rating: Rating

    private let ladder: [Rating]
    private let anchor: Int
    private let minTravel: Double
    private let maxTravel: Double
    private var stage: Int
    private var originOffset: Double = 0

    public init(startingRating: Rating, enabledRatings: EnabledRatings = .all) {
        self.startingRating = startingRating
        self.enabledRatings = enabledRatings
        self.rating = startingRating

        let higherEnabled = enabledRatings.levels.filter { $0 > startingRating }
        let sortedLadder = Array(Set([.rejected, .unrated, startingRating] + higherEnabled))
            .sorted()
        let anchorIndex = sortedLadder.firstIndex(of: startingRating) ?? 0
        self.ladder = sortedLadder
        self.anchor = anchorIndex
        self.stage = anchorIndex

        let minRelative = -anchorIndex
        let maxRelative = (sortedLadder.count - 1) - anchorIndex
        self.minTravel =
            -(MarkingSwipeRules.deadZone + Double(-minRelative) * MarkingSwipeRules.stepDistance)
        self.maxTravel =
            MarkingSwipeRules.deadZone + Double(maxRelative) * MarkingSwipeRules.stepDistance
    }

    /// Updates the live preview rating for `travel` (up positive) and returns any crossed stages.
    @discardableResult
    public mutating func update(travel: Double) -> [MarkingStageCrossing] {
        var effectiveTravel = travel - originOffset
        if effectiveTravel > maxTravel {
            originOffset = travel - maxTravel
            effectiveTravel = maxTravel
        } else if effectiveTravel < minTravel {
            originOffset = travel - minTravel
            effectiveTravel = minTravel
        }

        var crossings: [MarkingStageCrossing] = []
        while stage + 1 < ladder.count,
            effectiveTravel >= Self.upThreshold(fromRelativeStage: stage - anchor)
        {
            stage += 1
            let value = ladder[stage]
            crossings.append(MarkingStageCrossing(rating: value, haptic: Self.haptic(for: value)))
        }
        while stage - 1 >= 0,
            effectiveTravel <= Self.downThreshold(fromRelativeStage: stage - anchor)
        {
            stage -= 1
            let value = ladder[stage]
            crossings.append(MarkingStageCrossing(rating: value, haptic: Self.haptic(for: value)))
        }
        rating = ladder[stage]
        return crossings
    }

    /// Resolves the final position on release; no momentum is added after release.
    @discardableResult
    public mutating func release(travel: Double) -> [MarkingStageCrossing] {
        update(travel: travel)
    }

    private static func upThreshold(fromRelativeStage relative: Int) -> Double {
        if relative >= 0 {
            return MarkingSwipeRules.deadZone + Double(relative) * MarkingSwipeRules.stepDistance
        }
        return
            -(MarkingSwipeRules.deadZone
            + Double(-relative - 1) * MarkingSwipeRules.stepDistance)
            + MarkingSwipeRules.reversalHysteresis
    }

    private static func downThreshold(fromRelativeStage relative: Int) -> Double {
        if relative <= 0 {
            return
                -(MarkingSwipeRules.deadZone
                + Double(-relative) * MarkingSwipeRules.stepDistance)
        }
        return MarkingSwipeRules.deadZone + Double(relative - 1) * MarkingSwipeRules.stepDistance
            - MarkingSwipeRules.reversalHysteresis
    }

    private static func haptic(for rating: Rating) -> MarkingStageCrossing.Haptic {
        switch rating {
        case .rejected: .reject
        case .unrated: .clear
        default: .step
        }
    }
}
