/// How one photo's marks place it in in-group culling (PRD In-group culling; PRD P0-12).
///
/// The PRD uses three words that are easy to confuse, and they are deliberately not one
/// enumeration because an unmarked photo is also undecided:
///
/// - **Undecided**: no rating and no Reject (PRD In-group culling, layout). A colour label
///   alone keeps the photo undecided, because the header counts the photos that still need a
///   decision.
/// - **Unmarked**: no rating, no colour label and no Reject. Only these photos may be rejected
///   by a finishing action, so a rated or labelled photo is never rejected (PRD P0-12; PRD
///   In-group culling, finishing actions).
/// - **Marked**: any of the three, the inverse of unmarked.
extension PhotoMarks {
    /// No rating and no Reject; a colour label alone still counts as undecided (PRD In-group
    /// culling, layout, and its "Undecided N / M total" header).
    public var isUndecided: Bool { rating == .unrated && !isRejected }

    /// No rating, no colour label and no Reject; the only photos a finishing action may reject
    /// (PRD P0-12; PRD In-group culling, finishing actions).
    public var isUnmarked: Bool { rating == .unrated && label.isClear && !isRejected }

    /// Has a rating, a colour label or Reject, so a finishing action leaves it alone
    /// (PRD In-group culling, finishing actions).
    public var isMarked: Bool { !isUnmarked }
}
