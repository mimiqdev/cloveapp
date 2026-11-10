/// The marks in-group culling reads while a change is still being saved (PRD P0-12).
///
/// A finishing action must never reject a photo whose rating or colour label the user has already
/// asked for (PRD In-group culling, finishing actions: "Neither action ever rejects a photo that
/// already has a rating or color label"; PRD P0-12), and auto-advance can bring the next photo onto
/// the screen while the previous photo's write is still running. C4 keeps a request's marks until a
/// newer change replaces them (PRD How marks reach disk, rule 8), so a request that has not reached
/// storage yet still counts as the user's decision here: the plan and the executor's re-check read
/// the marks these two functions produce, not only the confirmed ones.
extension PhotoMarks {
    /// These marks with the fields one requested change names applied (PRD P0-12).
    ///
    /// Only the fields the request names change, so a rating that is still being written never
    /// clears a label it did not touch (PRD How marks reach disk, rule 9).
    public func including(_ change: MarkChange) -> PhotoMarks { applying(change) }
}
