import Foundation

/// Starting values for continuous marking, scaled proportionally to stage height and clamped to
/// physical min/max bounds on every device. Release has no momentum and holding never changes the
/// stage.
public struct MarkingSwipeRules: Hashable, Sendable {
    public static let referenceContainerHeight: Double = 760
    public static let standard = MarkingSwipeRules()

    /// The initial axis split only; reversing vertically never changes the claimed axis.
    public var verticalToHorizontalRatio: Double

    public init(verticalToHorizontalRatio: Double = 1) {
        self.verticalToHorizontalRatio = verticalToHorizontalRatio
    }

    public static func geometry(
        containerHeight: Double = referenceContainerHeight,
        enabledRatings: EnabledRatings = .all
    ) -> MarkingSwipeGeometry {
        MarkingSwipeGeometry(containerHeight: containerHeight, enabledRatings: enabledRatings)
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

/// Proportional vertical-drag bucket geometry computed from the Detail stage height `H` and
/// enabled rating count `K`.
public struct MarkingSwipeGeometry: Hashable, Sendable {
    public let containerHeight: Double
    public let enabledCount: Int
    public let upEntry: Double
    public let upSpan: Double
    public let upStep: Double
    public let clearTravel: Double
    public let rejectTravel: Double
    public let reversalHysteresis: Double

    public init(
        containerHeight: Double = MarkingSwipeRules.referenceContainerHeight,
        enabledRatings: EnabledRatings = .all
    ) {
        let resolvedHeight =
            containerHeight.isFinite && containerHeight > 0
            ? containerHeight : MarkingSwipeRules.referenceContainerHeight
        let count = max(enabledRatings.levels.count, 1)
        let upEntry = min(max(0.03 * resolvedHeight, 18), 26)
        let upSpan = min(max(0.18 * resolvedHeight, 88), 148)
        let upStep = count >= 2 ? (upSpan - upEntry) / Double(count - 1) : upEntry
        let clearTravel = min(max(0.05 * resolvedHeight, 32), 42)
        let rejectTravel = min(max(0.10 * resolvedHeight, 64), 80)
        let reversalHysteresis = min(max(0.22 * upStep, 4), 8)

        self.containerHeight = resolvedHeight
        self.enabledCount = count
        self.upEntry = upEntry
        self.upSpan = upSpan
        self.upStep = upStep
        self.clearTravel = clearTravel
        self.rejectTravel = rejectTravel
        self.reversalHysteresis = reversalHysteresis
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
/// Preview and semantic haptics respond purely to position from the first movement, with
/// proportional stage-height buckets, reversal hysteresis, and fixed touch-down origin anchoring
/// (clamping `stage` within `0 ..< ladder.count` without shifting any threshold). The session only
/// previews; its owner commits `rating` once at release or discards on cancel.
public struct MarkingSwipeSession: Hashable, Sendable {
    public let startingRating: Rating
    public let enabledRatings: EnabledRatings
    public let geometry: MarkingSwipeGeometry
    public private(set) var rating: Rating

    private let ladder: [Rating]
    private let anchor: Int
    private var stage: Int

    public init(
        startingRating: Rating,
        enabledRatings: EnabledRatings = .all,
        containerHeight: Double = MarkingSwipeRules.referenceContainerHeight
    ) {
        let geometry = MarkingSwipeGeometry(
            containerHeight: containerHeight, enabledRatings: enabledRatings)
        self.startingRating = startingRating
        self.enabledRatings = enabledRatings
        self.geometry = geometry
        self.rating = startingRating

        let higherEnabled = enabledRatings.levels.filter { $0 > startingRating }
        let sortedLadder = Array(Set([.rejected, .unrated, startingRating] + higherEnabled))
            .sorted()
        let anchorIndex = sortedLadder.firstIndex(of: startingRating) ?? 0
        self.ladder = sortedLadder
        self.anchor = anchorIndex
        self.stage = anchorIndex
    }

    /// Updates the live preview rating for `travel` (up positive) and returns any crossed stages.
    @discardableResult
    public mutating func update(travel: Double) -> [MarkingStageCrossing] {
        var crossings: [MarkingStageCrossing] = []
        while stage + 1 < ladder.count,
            travel >= upThreshold(fromStage: stage)
        {
            stage += 1
            let value = ladder[stage]
            crossings.append(MarkingStageCrossing(rating: value, haptic: Self.haptic(for: value)))
        }
        while stage - 1 >= 0,
            travel <= downThreshold(fromStage: stage)
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

    private func upThreshold(fromStage currentStage: Int) -> Double {
        if currentStage >= anchor {
            return geometry.upEntry + Double(currentStage - anchor) * geometry.upStep
        }
        return Self.downwardBoundary(
            entering: currentStage, ladder: ladder, anchor: anchor, geometry: geometry)
            + geometry.reversalHysteresis
    }

    private func downThreshold(fromStage currentStage: Int) -> Double {
        if currentStage <= anchor {
            return Self.downwardBoundary(
                entering: currentStage - 1, ladder: ladder, anchor: anchor, geometry: geometry)
        }
        let boundary =
            geometry.upEntry + Double(currentStage - 1 - anchor) * geometry.upStep
        return boundary - geometry.reversalHysteresis
    }

    private static func downwardBoundary(
        entering index: Int, ladder: [Rating], anchor: Int, geometry: MarkingSwipeGeometry
    ) -> Double {
        var boundary: Double = 0
        for i in stride(from: anchor - 1, through: index, by: -1) {
            let step = ladder[i] == .rejected ? geometry.rejectTravel : geometry.clearTravel
            boundary -= step
        }
        return boundary
    }

    private static func haptic(for rating: Rating) -> MarkingStageCrossing.Haptic {
        switch rating {
        case .rejected: .reject
        case .unrated: .clear
        default: .step
        }
    }
}
