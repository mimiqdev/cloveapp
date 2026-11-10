/// A rating bounded to 0–5; zero means unrated (PRD P0-05 and Marking rules).
/// Reject is independent and is never represented by a negative rating (G1 decision 5).
public struct Rating: RawRepresentable, Hashable, Comparable, Sendable {
    /// The validated star count from PRD P0-05.
    public let rawValue: Int

    /// Rejects values outside PRD P0-05's inclusive 0–5 range.
    public init?(rawValue: Int) {
        guard (0...5).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Creates an unrated value, per PRD Marking rules.
    public init() { self.rawValue = 0 }

    /// No stars, per PRD Marking rules' clear-rating behavior.
    public static let unrated = Rating()

    /// Orders ratings by star count for PRD P0-03's rating filter.
    public static func < (lhs: Rating, rhs: Rating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
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

/// Independent marks on a logical photo (PRD P0-05 and G1 decision 5).
public struct PhotoMarks: Hashable, Sendable {
    /// The 0–5 rating, unchanged by toggling Reject (PRD Marking rules).
    public var rating: Rating
    /// A clear, known or preserved external label (PRD disk rules 9–10).
    public var label: ColourLabel
    /// Clove-only Reject, independent of rating and label (G1 decision 5).
    public var isRejected: Bool

    /// Creates marks independently; the default is unmarked (PRD P0-05).
    public init(rating: Rating = .unrated, label: ColourLabel = .clear, isRejected: Bool = false) {
        self.rating = rating
        self.label = label
        self.isRejected = isRejected
    }

    /// The marks Clove stores for a photo, before its sidecar read finishes (PRD P0-05, P0-08).
    ///
    /// A photo enters the grid with these so a Reject or a standalone JPEG's marks are visible at
    /// once; the sidecar read that follows replaces them with
    /// ``init(stored:xmp:persistence:)``'s routing.
    public init(stored: CloveStoredMarks?) {
        self.init(
            rating: stored?.rating ?? .unrated, label: stored?.label ?? .clear,
            isRejected: stored?.isRejected ?? false)
    }

    /// The marks a photo shows, from the storages its persistence routes them to
    /// (PRD P0-05, P0-07; G1 decisions 2, 5–6).
    ///
    /// G1 decides a destination per field, so reading follows the same route:
    /// - a RAW set's rating and label come from its sidecar only, and an explicit `0` or a clear
    ///   label is the user's choice rather than a reason to fall back to a value Clove happens to
    ///   store for the same identity (G1 decision 2);
    /// - a standalone JPEG or HIF keeps its rating and label in Clove storage only, because it is
    ///   never given a sidecar (G1 decision 6);
    /// - Reject always comes from Clove storage (G1 decision 5).
    ///
    /// `xmp` is the packet C3 read for the photo, or nil when it has none. An `xmp:Rating` outside
    /// PRD P0-05's 0–5 range is an external value with no place in these marks, so it reads as
    /// unrated rather than as Reject (PRD P0-07).
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
        self.init(rating: rating, label: label, isRejected: stored?.isRejected ?? false)
    }
}
