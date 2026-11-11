import Foundation

/// One write request against a packet.
///
/// A field left `.keep` is not inspected for writing and keeps its exact bytes, so a
/// rating save never rewrites the label and a label save never rewrites the rating
/// (PRD P0-07; How marks reach disk, rule 9). C4 creates one edit per requested change.
public struct XMPEdit: Hashable, Sendable {
    /// What happens to `xmp:Rating`; `.keep` leaves it untouched.
    public var rating: XMPRatingChange
    /// What happens to `xmp:Label`; `.keep` leaves it untouched.
    public var label: XMPLabelChange

    /// Creates an edit that touches only the fields named by the caller.
    public init(rating: XMPRatingChange = .keep, label: XMPLabelChange = .keep) {
        self.rating = rating
        self.label = label
    }

    /// An edit that only sets a rating, −1 for Reject (PRD P0-05).
    public static func rating(_ rating: Rating) -> XMPEdit {
        XMPEdit(rating: .set(rating))
    }

    /// An edit that only sets or clears a label (PRD disk rules 9–10).
    public static func label(_ label: ColourLabel) -> XMPEdit {
        XMPEdit(label: .set(label))
    }
}

/// The requested change to `xmp:Rating`.
public enum XMPRatingChange: Hashable, Sendable {
    /// Leave the on-disk rating unchanged, including an external value (PRD P0-07).
    case keep
    /// Write this −1…5 rating, where −1 is Reject (PRD P0-05).
    case set(Rating)
}

/// The requested change to `xmp:Label`.
public enum XMPLabelChange: Hashable, Sendable {
    /// Leave the on-disk label unchanged, including an unknown external text (PRD P0-07).
    case keep
    /// Write this exact text, or remove the property when it is `.clear`.
    /// PRD Marking rules describe clear as the empty label; PRD disk rule 9 requires
    /// every other byte of the packet to stay as it is.
    case set(ColourLabel)
}
