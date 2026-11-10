import CloveCore

/// A request to bring one photo's cell into view in the grid (PRD P0-05's Undo row).
///
/// Undoing a batch from the grid returns to the photos it restored (PRD P0-09), and the grid
/// answers by scrolling the step's photo into view. The token makes a repeated request for the
/// same photo a new request, so undoing the same photo twice still scrolls to it.
struct GridRevealRequest: Hashable, Sendable {
    /// The photo whose cell the grid scrolls to (PRD P0-05).
    let photo: PhotoIdentity
    /// A value that changes with every request, so the grid never ignores a second one.
    let token: Int
}
