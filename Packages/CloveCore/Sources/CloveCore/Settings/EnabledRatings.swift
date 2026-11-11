/// The rating levels that may be applied as input, in ascending order and never empty.
///
/// Swipe steps map in order onto these levels, and the rating bar and keyboard accept only
/// these levels (PRD Enabled rating levels and PRD Rating by swipe distance). Display and
/// filtering still use the full 0–5 range, so a level that is turned off still shows when
/// another app wrote it, and it is never rewritten (PRD P0-06 acceptance).
public struct EnabledRatings: Hashable, Sendable {
    private let sortedLevels: [Rating]

    /// The enabled levels, ascending; never empty (PRD Enabled rating levels).
    public var levels: [Rating] { sortedLevels }

    /// The number of enabled levels, which is also the number of swipe steps.
    public var count: Int { sortedLevels.count }

    /// The first enabled star level for rating input.
    public var lowest: Rating { sortedLevels[0] }

    /// Accepts levels from 1 to 5, sorting and de-duplicating them.
    ///
    /// Returns nil when the input is empty or names a value that is not a star level. Zero means
    /// unrated and −1 means Reject, and every configuration needs at least one star step; both
    /// are enforced rather than repaired. The −1…5 `Rating` type still represents stored and
    /// displayed ratings outside this set.
    public init?<Levels: Sequence>(_ levels: Levels) where Levels.Element == Rating {
        let chosen = Set(levels)
        guard !chosen.isEmpty, chosen.allSatisfy({ $0 > .unrated }) else { return nil }
        self.sortedLevels = chosen.sorted()
    }

    /// Every level from 1 to 5, the launch default (PRD Enabled rating levels).
    public static let all = EnabledRatings(
        verifiedLevels: Set((1...5).compactMap(Rating.init(rawValue:))))

    /// Whether the level is one of the enabled input levels (PRD Enabled rating levels).
    public func contains(_ rating: Rating) -> Bool {
        sortedLevels.contains(rating)
    }

    /// The rating a 1-based swipe step applies, or nil before the first step.
    ///
    /// Steps past the last enabled level keep the highest one, so the longest swipe never
    /// exceeds the configured maximum (PRD Rating by swipe distance and P0-06 acceptance).
    public func rating(forSwipeStep step: Int) -> Rating? {
        guard step > 0 else { return nil }
        return sortedLevels[min(step, sortedLevels.count) - 1]
    }

    /// The next enabled level above `rating`, for the `↑` key (PRD Gestures and keyboard).
    ///
    /// Zero raises to the lowest enabled level. At the highest enabled level there is no next
    /// value, so the key does nothing. A current rating that is disabled still advances from
    /// its star count, which keeps the key predictable after another app wrote that rating.
    public func next(after rating: Rating) -> Rating? {
        sortedLevels.first { $0 > rating }
    }

    /// Whether the level may be applied to a photo (PRD Enabled rating levels).
    ///
    /// Zero (clear) is always allowed: clearing is not one of the five levels, and the rating
    /// bar and `0` key must still remove a mark. Disabled levels are refused as input only.
    public func canApply(_ rating: Rating) -> Bool {
        rating == .unrated || contains(rating)
    }

    /// The set with one level turned on or off, for the Settings screen.
    ///
    /// Turning off the last enabled level is refused and returns the receiver unchanged. The
    /// alternative — falling back to all five — would silently re-enable levels the user just
    /// turned off, and an empty set would leave the gesture with no steps at all. Zero is not a
    /// level, so toggling it changes nothing.
    public func with(_ rating: Rating, enabled: Bool) -> EnabledRatings {
        guard rating > .unrated else { return self }
        if enabled {
            guard !contains(rating) else { return self }
            return EnabledRatings(verifiedLevels: Set(sortedLevels).union([rating]))
        }
        guard contains(rating), sortedLevels.count > 1 else { return self }
        return EnabledRatings(verifiedLevels: Set(sortedLevels).subtracting([rating]))
    }

    /// Stable storage text for `SettingsPersistence`; parsing is tested through that type.
    var storageText: String {
        sortedLevels.map { String($0.rawValue) }.joined(separator: ",")
    }

    /// Parses one storage value strictly; any malformed level makes the whole field fall back
    /// to its default, including zero and out-of-range digits (PRD Enabled rating levels).
    init?(storageText: String) {
        var levels: [Rating] = []
        for part in storageText.split(separator: ",", omittingEmptySubsequences: false) {
            guard part.count == 1, let value = Int(part),
                let rating = Rating(rawValue: value)
            else { return nil }
            levels.append(rating)
        }
        self.init(levels)
    }

    private init(verifiedLevels: Set<Rating>) {
        self.sortedLevels = verifiedLevels.sorted()
    }
}
