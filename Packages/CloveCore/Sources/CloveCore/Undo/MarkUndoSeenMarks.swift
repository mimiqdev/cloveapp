/// The marks the user last saw for one photo, including a change C4 has not confirmed yet
/// (PRD P0-05's Undo row).
///
/// PRD P0-05's Undo row restores "the previous mark". A mark that is still writing is already on
/// the screen — the rating bar, the grid overlay and the swipe badge show the value the user asked
/// for while C4 confirms it — so the previous mark is what the user saw, not the last confirmed
/// value. Recording only the confirmed value would lose the value in between: with ★3 still
/// writing, a second mark to ★4 would record "unrated" as what it replaces, and undo would then
/// skip ★3 entirely.
///
/// A failed or superseded change was never on the screen: its value never landed, and the photo
/// shows its confirmed marks with the failure beside them, so those are what the user saw and what
/// undo restores.
public enum MarkUndoSeenMarks {
    /// The marks one photo shows now, including a request still being written (PRD P0-05).
    ///
    /// - Parameters:
    ///   - confirmed: The marks C4 has confirmed for the photo.
    ///   - latest: The photo's latest change, or `nil` when nothing was requested.
    public static func marks(confirmed: PhotoMarks, latest: MarkChangeStatus?) -> PhotoMarks {
        guard let latest, latest.state.isInProgress else { return confirmed }
        return confirmed.including(latest.requested)
    }
}
