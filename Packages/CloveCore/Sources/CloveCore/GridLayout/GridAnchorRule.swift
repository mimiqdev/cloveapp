/// Holds one cell in place while the grid's cells change (PRD Grid, P0-11).
///
/// The grid's cells change under the user: a streaming scan inserts photos, capture times arrive
/// and reorder photos, a filter or order changes the list, and grouping refines a similar group
/// into different cells (PRD Grid, P0-11). PRD Grid's similar-group display requires that a
/// refinement never moves the photo the user is looking at, in expanded and collapsed display
/// alike. This rule answers the one question that keeps the photo in place: after the change,
/// which cell does the view hold where the anchor used to be?
///
/// The rule is pure and generic. It reads only the two item lists and the anchor's identity;
/// the screen supplies its own item type and measures the anchor's on-screen position itself.
public enum GridAnchorRule {
    /// The index that holds `anchor`'s place in `cells`, or nil when no old cell survives.
    ///
    /// `previous` is the list the view showed before the change and `cells` the list it is about
    /// to show. When the anchor is still shown, its own new index is returned even when it moved,
    /// because the view scrolls that same cell back to its on-screen position. When the anchor
    /// was filtered out or removed, the nearest surviving old neighbour is returned instead, so
    /// the view keeps the place it had rather than jumping to the top. The search goes forward
    /// before backward because the cell after the anchor is the one that was below it on screen.
    ///
    /// A nil anchor, or an anchor that was not in `previous`, returns nil: a view with no anchor
    /// has no place to hold, and the caller starts from the top.
    public static func newIndex<Cell: Hashable>(
        of anchor: Cell?, previous: [Cell], in cells: [Cell]
    ) -> Int? {
        guard let anchor else { return nil }
        if let index = cells.firstIndex(of: anchor) { return index }
        guard let removed = previous.firstIndex(of: anchor) else { return nil }
        for offset in 1...(previous.count + 1) {
            let index = removed + offset
            if index < previous.count, let survivor = cells.firstIndex(of: previous[index]) {
                return survivor
            }
            let behind = removed - offset
            if behind >= 0, let survivor = cells.firstIndex(of: previous[behind]) {
                return survivor
            }
            if index >= previous.count && behind < 0 { break }
        }
        return nil
    }
}
