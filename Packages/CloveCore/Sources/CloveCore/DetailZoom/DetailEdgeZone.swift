import CoreGraphics

/// Where one tap in the detail preview goes (PRD P0-04, PRD Detail and marking).
///
/// PRD Detail and marking gives the left and right edges single-tap navigation and no
/// double-tap action, so a tap there never waits for a double tap. The middle keeps the
/// double-tap-to-100% action, which is why a tap is classified before its gesture is handled.
public enum DetailEdgeZone: Hashable, Sendable {
    /// The left edge: the previous photo in the grid's order and filter (PRD P0-04).
    case previous
    /// The right edge: the next photo in the grid's order and filter (PRD P0-04).
    case next
    /// The middle: the double-tap to 100% and back to fit (PRD P0-04).
    case centre

    /// The fraction of the preview's width each edge zone covers.
    ///
    /// A starting value taken from the design's edge hints, which cover the outer 18% on each
    /// side, so 36% of the width navigates and 64% belongs to the centre gesture.
    public static let edgeFraction: CGFloat = 0.18
}
