/// The marks the user last saw for one photo, with every request still being written folded over
/// the confirmed marks in the order it was made (PRD P0-05's Undo row).
///
/// PRD P0-05's Undo row restores "the previous mark". A mark that is still writing already counts
/// as the value the user asked for, and C4 can have more than one request for a photo in flight at
/// once: on slow media a rating, a label and another rating can all be waiting. Folding them in
/// order keeps the value in between — with ★3 still writing, a second mark to ★4 replaces ★3, so
/// undo puts ★3 back rather than the confirmed value before it.
///
/// A request whose write failed is not part of the fold: the caller drops it when its write
/// returns, because the photo shows its confirmed marks with the failure beside them. The same
/// holds for a request a newer one superseded.
public enum MarkUndoSeenMarks {
    /// The marks one photo shows now, given what C4 confirmed and the requests still writing
    /// (PRD P0-05).
    ///
    /// - Parameters:
    ///   - confirmed: The marks C4 has confirmed for the photo.
    ///   - requests: The photo's requests that have not returned yet, oldest first.
    public static func marks(confirmed: PhotoMarks, requests: [MarkChange]) -> PhotoMarks {
        requests.reduce(confirmed) { marks, change in marks.including(change) }
    }
}
