/// A detail-view key from the PRD keyboard table, as a value the rules can read.
///
/// The keyboard handler maps hardware keys to these cases, so no UIKit type enters CloveCore
/// (PRD Gestures and keyboard). The physical key for each case is part of the case's
/// documentation; `←`, `→`, `↑`, `↓` and `⌘Z` need the named-key or modifier information the
/// handler already has, while `0`–`9` are plain characters.
public enum MarkingKey: Hashable, Sendable {
    /// `0` clears the rating; `1` to `5` set that level (PRD keyboard table).
    ///
    /// A level that Settings does not enable does nothing (PRD Enabled rating levels).
    case rating(Rating)

    /// `6` red, `7` yellow, `8` green, `9` blue, matching Lightroom (PRD keyboard table).
    ///
    /// Setting the label that is already applied clears it, the same toggle as the rating bar.
    case colourLabel(LabelColour)

    /// `↑`: raise to the next enabled rating, and do nothing at the top (PRD keyboard table).
    case nextRating

    /// `↓`: Reject, which keeps the existing rating (PRD keyboard table and Marking rules).
    case reject

    /// `←`: show the previous photo (PRD keyboard table).
    case previousPhoto

    /// `→`: show the next photo (PRD keyboard table).
    case nextPhoto

    /// `⌘Z`: undo, reported as an action for C5's undo stack to handle (PRD Undo row).
    case undo
}
