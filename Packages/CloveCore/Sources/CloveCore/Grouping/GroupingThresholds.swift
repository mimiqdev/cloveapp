import Foundation

/// How aggressively visual similarity splits time-adjacent shots into separate groups.
public enum GroupingSensitivity: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Stricter visual similarity: splits moderate framing or pose shifts.
    case tight

    /// Default visual similarity thresholds.
    case standard

    /// More tolerant visual similarity: keeps broader framing or pose shifts together.
    case loose

    /// Groups consecutive photos from the same camera body within the configured time window
    /// without visual comparison or feature extraction.
    case timeOnly

    public var id: Self { self }
}

/// The maximum capture-time gap allowed between consecutive photos in one similar group.
public enum GroupingTimeWindow: String, CaseIterable, Hashable, Identifiable, Sendable {
    case oneSecond = "1s"
    case twoSeconds = "2s"
    case fiveSeconds = "5s"
    case tenSeconds = "10s"
    case thirtySeconds = "30s"

    public var id: Self { self }

    /// The strict time gap in seconds; a gap equal to or larger than this starts a new run.
    public var seconds: TimeInterval {
        TimeInterval(wholeSeconds)
    }

    /// The whole-second duration for display formatting.
    public var wholeSeconds: Int {
        switch self {
        case .oneSecond: 1
        case .twoSeconds: 2
        case .fiveSeconds: 5
        case .tenSeconds: 10
        case .thirtySeconds: 30
        }
    }
}

/// The thresholds grouping uses for time runs and visual similarity boundaries.
///
/// Adjacent photos from the same camera body join a time run when their capture gap is strictly
/// less than `timeGap`. When `useVisualSimilarity` is true, a Vision feature-print distance at or
/// below `visionDistance` keeps a boundary joined, and a dHash fallback at or below `hashDistance`
/// differing bits keeps it joined when Vision has no usable feature. When `useVisualSimilarity` is
/// false, time runs are published directly as finished groups without visual analysis.
///
/// The type is a value so settings presets and tests can supply their own set, and so the cache
/// can tell a run under one set from a run under another.
public struct GroupingThresholds: Hashable, Sendable {
    /// The default time gap below which neighbours join one run, in seconds.
    /// The comparison is strict: a gap of exactly this many seconds starts a new run.
    public static let captureTimeGap: TimeInterval = 2

    /// The default largest Vision distance that keeps a boundary joined, inclusive.
    public static let maximumVisionDistance: Float = 0.5

    /// The default largest dHash differing-bit count that keeps a boundary joined, inclusive.
    /// It only applies when Vision has no usable feature.
    public static let maximumHashDistance: Int = 12

    /// Stricter visual similarity Vision distance for ``GroupingSensitivity/tight``.
    public static let tightVisionDistance: Float = 0.35

    /// Stricter visual similarity dHash distance for ``GroupingSensitivity/tight``.
    public static let tightHashDistance: Int = 8

    /// More tolerant visual similarity Vision distance for ``GroupingSensitivity/loose``.
    public static let looseVisionDistance: Float = 0.7

    /// More tolerant visual similarity dHash distance for ``GroupingSensitivity/loose``.
    public static let looseHashDistance: Int = 16

    /// The default grouping thresholds (`2s`, `.standard`).
    public static let standard = GroupingThresholds()

    /// The strict time gap between adjacent photos that starts a new run.
    public var timeGap: TimeInterval

    /// The inclusive Vision distance above which a boundary splits when visual similarity is used.
    public var visionDistance: Float

    /// The inclusive dHash bit distance above which a fallback boundary splits when visual
    /// similarity is used.
    public var hashDistance: Int

    /// Whether time runs are visually refined by Vision / dHash distance.
    /// When false, consecutive same-camera photos within `timeGap` form final groups immediately.
    public var useVisualSimilarity: Bool

    /// Creates a threshold set; the defaults match ``standard``.
    public init(
        timeGap: TimeInterval = GroupingThresholds.captureTimeGap,
        visionDistance: Float = GroupingThresholds.maximumVisionDistance,
        hashDistance: Int = GroupingThresholds.maximumHashDistance,
        useVisualSimilarity: Bool = true
    ) {
        self.timeGap = timeGap
        self.visionDistance = visionDistance
        self.hashDistance = hashDistance
        self.useVisualSimilarity = useVisualSimilarity
    }

    /// Creates a threshold set from the user's global time-window and sensitivity choices.
    public init(
        timeWindow: GroupingTimeWindow,
        sensitivity: GroupingSensitivity
    ) {
        switch sensitivity {
        case .tight:
            self.init(
                timeGap: timeWindow.seconds,
                visionDistance: Self.tightVisionDistance,
                hashDistance: Self.tightHashDistance,
                useVisualSimilarity: true)
        case .standard:
            self.init(
                timeGap: timeWindow.seconds,
                visionDistance: Self.maximumVisionDistance,
                hashDistance: Self.maximumHashDistance,
                useVisualSimilarity: true)
        case .loose:
            self.init(
                timeGap: timeWindow.seconds,
                visionDistance: Self.looseVisionDistance,
                hashDistance: Self.looseHashDistance,
                useVisualSimilarity: true)
        case .timeOnly:
            self.init(
                timeGap: timeWindow.seconds,
                useVisualSimilarity: false)
        }
    }

    /// The value the cache keys on, so any threshold or mode change invalidates stored groups.
    public var cacheKey: String {
        if useVisualSimilarity {
            "gap:\(timeGap)|vision:\(visionDistance)|hash:\(hashDistance)"
        } else {
            "gap:\(timeGap)|mode:timeOnly"
        }
    }
}
