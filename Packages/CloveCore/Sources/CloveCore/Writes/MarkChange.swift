import Foundation

/// One request to change marks on a photo set: any of rating, label, Reject.
///
/// PRD P0-07 and P0-09 describe single and batch writes of a rating, a colour label, and
/// Reject. A field left `nil` is not part of the request and keeps its stored value, so a
/// rating change never rewrites the label (PRD How marks reach disk, rule 9). G1 decision 5
/// keeps Reject independent of the rating; the change carries no negative rating.
public struct MarkChange: Hashable, Sendable {
    /// The requested rating, or `nil` to leave the stored rating alone (PRD P0-05).
    public var rating: Rating?
    /// The requested label, or `nil` to leave the stored label alone (PRD disk rules 9–10).
    public var label: ColourLabel?
    /// The requested Reject state, or `nil` to leave it alone (G1 decision 5).
    public var reject: Bool?

    /// Creates a request that touches only the fields the caller names (PRD P0-07).
    public init(rating: Rating? = nil, label: ColourLabel? = nil, reject: Bool? = nil) {
        self.rating = rating
        self.label = label
        self.reject = reject
    }

    /// A request that changes only the rating (PRD P0-05).
    public static func rating(_ rating: Rating) -> MarkChange {
        MarkChange(rating: rating)
    }

    /// A request that changes only the colour label (PRD disk rules 9–10).
    public static func label(_ label: ColourLabel) -> MarkChange {
        MarkChange(label: label)
    }

    /// A request that turns Reject on or off without touching rating or label (G1 decision 5).
    public static func reject(_ isRejected: Bool) -> MarkChange {
        MarkChange(reject: isRejected)
    }

    /// Whether the request names no field at all; an empty change writes nothing.
    public var isEmpty: Bool { rating == nil && label == nil && reject == nil }

    /// The cumulative request used when two changes to one photo join one write.
    ///
    /// PRD How marks reach disk, rule 8, keeps a failed request until it is confirmed, and
    /// G1 decision 5 makes the fields independent. The newer change wins per field and the
    /// older request's other fields stay, so nothing the user asked for is dropped.
    func merged(with newer: MarkChange) -> MarkChange {
        MarkChange(
            rating: newer.rating ?? rating,
            label: newer.label ?? label,
            reject: newer.reject ?? reject)
    }

    /// Whether every field `other` asked for still appears unchanged in this request.
    ///
    /// A waiting request whose field a newer change overwrote is superseded rather than
    /// saved (PRD How marks reach disk, rule 8).
    func covers(_ other: MarkChange) -> Bool {
        (rating == other.rating || other.rating == nil)
            && (label == other.label || other.label == nil)
            && (reject == other.reject || other.reject == nil)
    }
}

/// A stable handle for one admitted change, used by retry, batches and state queries.
///
/// PRD P0-08 requires per-change save state and a retry that applies to exactly that change,
/// and P0-09 requires a batch to retry only its failed items. The identifier is created when
/// the queue admits the request and stays valid for the rest of the session.
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
/// G1 decision 5 stores Reject in Clove, and G1 decision 6 stores new marks on standalone
/// JPEG/HIF there with the "Saved in Clove only" status. A field left `nil` keeps its stored
/// value so a rating change never clears Reject and a Reject toggle never clears a label.
public struct CloveMarkChange: Hashable, Sendable {
    /// The requested stored rating, or `nil` to keep the stored value (G1 decision 6).
    public var rating: Rating?
    /// The requested stored label, or `nil` to keep the stored value (G1 decision 6).
    public var label: ColourLabel?
    /// The requested Reject state, or `nil` to keep the stored value (G1 decision 5).
    public var reject: Bool?

    /// Creates a request against Clove storage (G1 decisions 5–6).
    public init(rating: Rating? = nil, label: ColourLabel? = nil, reject: Bool? = nil) {
        self.rating = rating
        self.label = label
        self.reject = reject
    }

    /// Whether the request names no field at all.
    public var isEmpty: Bool { rating == nil && label == nil && reject == nil }
}

/// The marks Clove keeps for one photo in its own storage.
///
/// G1 decision 5 stores Reject here for every set until the move to `_Rejected`, and G1
/// decision 6 stores new marks for a standalone JPEG/HIF here. The rating and label are
/// absent for a RAW set, whose marks belong to the sidecar (PRD How marks reach disk, rule 2).
public struct CloveStoredMarks: Hashable, Sendable {
    /// A stored rating (G1 decision 6), or `nil` when Clove stores no rating for the photo.
    public var rating: Rating?
    /// A stored label (G1 decision 6), or `nil` when Clove stores no label for the photo.
    public var label: ColourLabel?
    /// Whether the photo is rejected and not yet moved (G1 decision 5).
    public var isRejected: Bool

    /// Creates the stored marks for one photo; the default is nothing stored.
    public init(rating: Rating? = nil, label: ColourLabel? = nil, isRejected: Bool = false) {
        self.rating = rating
        self.label = label
        self.isRejected = isRejected
    }

    /// Whether Clove stores nothing at all for the photo.
    public var isEmpty: Bool { rating == nil && label == nil && !isRejected }
}
