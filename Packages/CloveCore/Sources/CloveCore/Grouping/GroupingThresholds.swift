import Foundation

/// The starting thresholds grouping uses (G1's Grouping row, PRD Similar groups steps 2–3).
///
/// G1 fixes three values and leaves every one a starting target, not a launch accuracy
/// promise: adjacent photos join a time run when they are strictly less than 2 s apart, a
/// Vision feature-print distance of 0.5 or less keeps a boundary joined, and a dHash fallback
/// of 12 differing bits or less keeps it joined when Vision has no usable feature. There is no
/// grouping-sensitivity setting (PRD Explicitly out of launch scope); the values are named
/// constants so a future calibration changes them in one place.
///
/// The type is a value so tests and later calibration can supply their own set, and so the
/// cache can tell a run under one set from a run under another.
public struct GroupingThresholds: Hashable, Sendable {
    /// The time gap below which neighbours join one run, in seconds (PRD Similar groups step 2).
    /// The comparison is strict: a gap of exactly this many seconds starts a new run.
    public static let captureTimeGap: TimeInterval = 2

    /// The largest Vision distance that keeps a boundary joined, inclusive (G1 Grouping row).
    /// S5 measured a ten-frame burst between 0.231 and 0.420, so 0.5 is a starting value.
    public static let maximumVisionDistance: Float = 0.5

    /// The largest dHash differing-bit count that keeps a boundary joined, inclusive
    /// (G1 Grouping row). It only applies when Vision has no usable feature.
    public static let maximumHashDistance: Int = 12

    /// The G1 starting values.
    public static let standard = GroupingThresholds()

    /// The strict time gap between adjacent photos that starts a new run (PRD step 2).
    public var timeGap: TimeInterval

    /// The inclusive Vision distance above which a boundary splits (G1 Grouping row).
    public var visionDistance: Float

    /// The inclusive dHash bit distance above which a fallback boundary splits (G1 Grouping row).
    public var hashDistance: Int

    /// Creates a threshold set; the defaults are G1's starting values.
    public init(
        timeGap: TimeInterval = GroupingThresholds.captureTimeGap,
        visionDistance: Float = GroupingThresholds.maximumVisionDistance,
        hashDistance: Int = GroupingThresholds.maximumHashDistance
    ) {
        self.timeGap = timeGap
        self.visionDistance = visionDistance
        self.hashDistance = hashDistance
    }

    /// The value the cache keys on, so any threshold change invalidates stored groups
    /// (PRD Similar groups rules: the cache is Clove's own).
    var cacheKey: String {
        "gap:\(timeGap)|vision:\(visionDistance)|hash:\(hashDistance)"
    }
}
