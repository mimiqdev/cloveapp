import Foundation

/// One XMP property Clove owns: the rating or the colour label.
///
/// PRD P0-07 limits XMP interoperability to ratings and colour labels, so there is
/// deliberately no Clove namespace and no separate Reject field: Reject is the standard rating
/// −1 (decision record `reject-as-rating.md`). A property is identified by its namespace URI and
/// local name, never by a prefix, so `photo:Rating` and `xmp:Rating` are the same field when both
/// prefixes name the XMP namespace (PRD How marks reach disk, rule 4).
public enum XMPProperty: String, CaseIterable, Hashable, Sendable {
    /// `xmp:Rating`, PRD P0-05's five-star scale, which carries −1 for Reject and external values.
    case rating
    /// `xmp:Label`, the fixed English colour names from PRD Marking rules.
    case label

    /// The `http://ns.adobe.com/xap/1.0/` namespace URI shared by both owned properties.
    /// PRD P0-07 and How marks reach disk, rule 4.
    public static let namespaceURI = "http://ns.adobe.com/xap/1.0/"

    /// The standard local name this property is written with (PRD disk rule 4).
    public var localName: String {
        switch self {
        case .rating: return "Rating"
        case .label: return "Label"
        }
    }
}

/// A rating exactly as a packet holds it.
///
/// PRD P0-05 bounds Clove's own ratings to −1…5, where −1 is Reject. Other software can leave
/// another out-of-range integer such as `6` or `-2` in `xmp:Rating`. PRD P0-07 keeps such a
/// value as an external mark: it is never clamped, it reads as unrated, and a write that does
/// not change the rating leaves its bytes alone.
public enum XMPRating: Hashable, Sendable {
    /// A rating inside PRD P0-05's −1…5 range; −1 is Reject and zero is unrated.
    case rated(Rating)
    /// An integer outside −1…5, kept verbatim, for example `6` or `-2` from another app.
    case external(Int)

    /// The reading of a packet with no `xmp:Rating` property (PRD P0-05).
    public static let unrated = XMPRating.rated(.unrated)

    /// Classifies an integer without clamping it, so out-of-range values stay external.
    public init(_ value: Int) {
        if let rating = Rating(rawValue: value) {
            self = .rated(rating)
        } else {
            self = .external(value)
        }
    }

    /// The in-range rating, or `nil` when the packet holds an external value.
    public var rating: Rating? {
        guard case .rated(let rating) = self else { return nil }
        return rating
    }

    /// The external integer, or `nil` when the value is inside PRD P0-05's range.
    public var externalValue: Int? {
        guard case .external(let value) = self else { return nil }
        return value
    }
}

/// Ratings and colour labels read from one XMP packet.
///
/// Reject needs no field of its own: it is the rating −1 written by the same `xmp:Rating`
/// property (decision record `reject-as-rating.md`). An unknown label keeps its exact external
/// text (PRD disk rule 9).
public struct XMPMarks: Hashable, Sendable {
    /// The −1…5 rating, Reject included, or an external value kept verbatim (PRD P0-07).
    public var rating: XMPRating
    /// The label's exact external text; empty means no label (PRD disk rules 9–10).
    public var label: ColourLabel

    /// Creates marks; the default is the reading of a packet with no owned properties.
    public init(rating: XMPRating = .unrated, label: ColourLabel = .clear) {
        self.rating = rating
        self.label = label
    }

    /// The marks of a packet that holds neither owned property.
    public static let unmarked = XMPMarks()
}
