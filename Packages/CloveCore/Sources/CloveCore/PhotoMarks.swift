/// A photo's rating from −1 to 5: −1 is Rejected, 0 is unrated, and 1–5 are stars
/// (PRD P0-05 and Marking rules).
///
/// Reject is the rating value −1, the way Adobe Bridge stores it, so one value carries both
/// and a photo is never rated and rejected at once (decision record
/// `reject-as-rating.md`). `xmp:Rating` values outside −1…5 stay external to Clove (PRD P0-07).
public struct Rating: RawRepresentable, Hashable, Comparable, Sendable {
    /// The validated value: −1 for Rejected, 0 for unrated, 1–5 for stars (PRD P0-05).
    public let rawValue: Int

    /// Rejects values outside PRD P0-05's inclusive −1…5 range.
    public init?(rawValue: Int) {
        guard (-1...5).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Creates an unrated value, per PRD Marking rules.
    public init() { self.rawValue = 0 }

    /// No stars, per PRD Marking rules' clear-rating behavior.
    public static let unrated = Rating()

    /// Rejected, written as `xmp:Rating="-1"` and replacing any stars (PRD P0-05).
    public static let rejected = Rating(verified: -1)

    /// Whether the photo is rejected rather than rated (PRD P0-05).
    public var isRejected: Bool { self == .rejected }

    /// The star count to show, or `nil` when the photo has no stars: unrated or rejected.
    ///
    /// Reject is −1, so a rejected photo never reads "−1 stars" (PRD P0-05).
    public var starCount: Int? { rawValue > 0 ? rawValue : nil }

    /// Orders ratings by value for PRD P0-03's rating filter, so Reject sorts below unrated.
    public static func < (lhs: Rating, rhs: Rating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Creates a value this type already validated, for the named constants only.
    private init(verified rawValue: Int) { self.rawValue = rawValue }
}

/// Fixed English XMP color names, independent of UI language (PRD Marking rules, disk rule 10).
public enum LabelColour: String, CaseIterable, Hashable, Sendable {
    /// Default label (PRD Marking rules).
    case red = "Red"
    /// Default label (PRD Marking rules).
    case yellow = "Yellow"
    /// Default label (PRD Marking rules).
    case green = "Green"
    /// Default label (PRD Marking rules).
    case blue = "Blue"
    /// Default label (PRD Marking rules).
    case purple = "Purple"
    /// Extended label matching Capture One (PRD Marking rules).
    case orange = "Orange"
    /// Extended label matching Capture One (PRD Marking rules).
    case pink = "Pink"

    /// Whether the label is enabled through extended colors (PRD Marking rules).
    public var isExtended: Bool { self == .orange || self == .pink }
}

/// Lossless external label text, including unknown values (PRD How marks reach disk, rule 9).
/// Only exact fixed English names identify known colors; no trimming, localization or case mapping.
public struct ColourLabel: RawRepresentable, Hashable, Sendable {
    /// The exact text to pass back to metadata storage, including unknown text (PRD disk rule 9).
    public let rawValue: String

    /// Retains all supplied text unchanged, including whitespace and case (PRD disk rule 9).
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Uses a fixed English name for a user-selected color (PRD disk rule 10).
    public init(colour: LabelColour) { self.rawValue = colour.rawValue }

    /// Clear is the empty label, separate from unknown external labels (PRD Marking rules).
    public static let clear = ColourLabel(rawValue: "")

    /// The known color, or nil for clear/unknown text; raw text is always retained (PRD disk rule 9).
    public var colour: LabelColour? { LabelColour(rawValue: rawValue) }

    /// Whether no label is applied; an unknown label still counts as a label (PRD P0-12).
    public var isClear: Bool { rawValue.isEmpty }
}

/// The marks on a logical photo: one rating, which carries Reject, and one colour label
/// (PRD P0-05).
public struct PhotoMarks: Hashable, Sendable {
    /// The −1…5 rating: −1 is Rejected, 0 unrated, 1–5 stars (PRD P0-05).
    public var rating: Rating
    /// A clear, known or preserved external label (PRD disk rules 9–10).
    public var label: ColourLabel

    /// Whether the photo is rejected; Reject is the rating value −1 (PRD P0-05).
    public var isRejected: Bool { rating.isRejected }

    /// Creates marks; the default is unmarked (PRD P0-05).
    public init(rating: Rating = .unrated, label: ColourLabel = .clear) {
        self.rating = rating
        self.label = label
    }

    /// The marks Clove stores for a photo, before its sidecar read finishes (PRD P0-05, P0-08).
    ///
    /// A photo enters the grid with these so a standalone JPEG's marks are visible at once; the
    /// sidecar read that follows replaces them with ``init(stored:xmp:persistence:)``'s routing.
    public init(stored: CloveStoredMarks?) {
        self.init(rating: stored?.rating ?? .unrated, label: stored?.label ?? .clear)
    }

    /// The marks a photo shows, from the storages its persistence routes them to
    /// (PRD P0-05, P0-07; G1 decisions 2 and 6).
    ///
    /// G1 decides a destination per field, so reading follows the same route:
    /// - a RAW set's rating (Reject included) and label come from its sidecar only, and an
    ///   explicit `0` or a clear label is the user's choice rather than a reason to fall back to
    ///   a value Clove happens to store for the same identity (G1 decision 2);
    /// - a standalone JPEG or HIF keeps its rating and label in Clove storage only, because it is
    ///   never given a sidecar (G1 decision 6).
    ///
    /// `xmp` is the packet C3 read for the photo, or nil when it has none. An `xmp:Rating` of −1
    /// reads as Rejected (PRD P0-07); any other value outside −1…5 is an external value with no
    /// place in these marks, so it reads as unrated and stays on disk unchanged.
    public init(
        stored: CloveStoredMarks? = nil, xmp: XMPMarks? = nil, persistence: MarkPersistence
    ) {
        let rating: Rating
        switch persistence.rating {
        case .xmpSidecar:
            rating = xmp?.rating.rating ?? .unrated
        case .cloveStorage:
            rating = stored?.rating ?? .unrated
        }
        let label: ColourLabel
        switch persistence.label {
        case .xmpSidecar:
            label = xmp?.label ?? .clear
        case .cloveStorage:
            label = stored?.label ?? .clear
        }
        self.init(rating: rating, label: label)
    }
}

extension PhotoMarks {
    /// The marks after a request, replacing only the fields it names.
    public func applying(_ change: MarkChange) -> PhotoMarks {
        PhotoMarks(rating: change.rating ?? rating, label: change.label ?? label)
    }
}
