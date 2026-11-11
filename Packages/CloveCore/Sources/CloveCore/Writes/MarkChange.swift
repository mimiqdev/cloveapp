import Foundation

/// One request to change marks on a photo set: the rating and/or the label.
///
/// PRD P0-07 and P0-09 describe single and batch writes of a rating (Reject included, as −1)
/// and a colour label. A field left `nil` is not part of the request and keeps its stored
/// value, so a rating change never rewrites the label (PRD How marks reach disk, rule 9).
public struct MarkChange: Hashable, Sendable {
    /// The requested rating, −1 for Reject, or `nil` to leave the stored rating alone
    /// (PRD P0-05).
    public var rating: Rating?
    /// The requested label, or `nil` to leave the stored label alone (PRD disk rules 9–10).
    public var label: ColourLabel?

    /// Creates a request that touches only the fields the caller names (PRD P0-07).
    public init(rating: Rating? = nil, label: ColourLabel? = nil) {
        self.rating = rating
        self.label = label
    }

    /// A request that changes only the rating; `.rejected` writes Reject (PRD P0-05).
    public static func rating(_ rating: Rating) -> MarkChange {
        MarkChange(rating: rating)
    }

    /// A request that changes only the colour label (PRD disk rules 9–10).
    public static func label(_ label: ColourLabel) -> MarkChange {
        MarkChange(label: label)
    }

    /// Whether the request names no field at all; an empty change writes nothing.
    public var isEmpty: Bool { rating == nil && label == nil }

}

/// Identifies one returned write result.
public struct MarkChangeID: Hashable, Sendable, CustomStringConvertible {
    /// The underlying identifier; two queues never share a value by construction.
    public let rawValue: UUID

    /// Creates a fresh identifier for an admitted change.
    public init() { self.rawValue = UUID() }

    /// A stable, log-friendly spelling.
    public var description: String { rawValue.uuidString }
}

/// A partial change to the marks Clove keeps in its own storage.
///
/// Standalone JPEG/HIF marks live here. A nil field keeps its stored value.
public struct CloveMarkChange: Hashable, Sendable {
    /// The requested stored rating, or `nil` to keep the stored value (G1 decision 6).
    public var rating: Rating?
    /// The requested stored label, or `nil` to keep the stored value (G1 decision 6).
    public var label: ColourLabel?

    /// Creates a request against Clove storage (G1 decision 6).
    public init(rating: Rating? = nil, label: ColourLabel? = nil) {
        self.rating = rating
        self.label = label
    }

    /// Whether the request names no field at all.
    public var isEmpty: Bool { rating == nil && label == nil }
}

/// The marks Clove keeps for one photo in its own storage.
///
/// G1 decision 6 stores new marks for a standalone JPEG/HIF here, Reject included as the
/// rating −1. The rating and label are absent for a RAW set, whose marks belong to the sidecar
/// (PRD How marks reach disk, rule 2).
public struct CloveStoredMarks: Hashable, Sendable {
    /// A stored rating, or `nil` when Clove stores no rating for the photo (G1 decision 6).
    public var rating: Rating?
    /// A stored label, or `nil` when Clove stores no label for the photo (G1 decision 6).
    public var label: ColourLabel?

    /// Creates the stored marks for one photo; the default is nothing stored.
    public init(rating: Rating? = nil, label: ColourLabel? = nil) {
        self.rating = rating
        self.label = label
    }

    /// Whether the photo is rejected, which is the stored rating −1 (PRD P0-05).
    public var isRejected: Bool { rating?.isRejected == true }

    /// Whether Clove stores nothing at all for the photo.
    public var isEmpty: Bool { rating == nil && label == nil }
}
