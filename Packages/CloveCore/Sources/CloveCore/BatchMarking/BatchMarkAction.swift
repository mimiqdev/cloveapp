import Foundation

/// One mark the multi-select bar applies to every selected photo (PRD P0-09, PRD Marking rules).
///
/// PRD P0-09's bar offers a rating, a colour label and Reject. PRD Marking rules decide what each
/// one means: a rating from 0 to 5 where 0 clears, a colour label where Clear removes it, and
/// Reject as its own toggle that keeps the rating (G1 decision 5 keeps Reject in Clove, never in
/// XMP). The action is the bar's request only; ``BatchMarkPlan`` turns it into one change per
/// photo through C13's rules.
public enum BatchMarkAction: Hashable, Sendable {
    /// A 0–5 rating for every photo; zero clears the rating and keeps Reject (PRD Marking rules).
    ///
    /// Only a level Settings enables can be applied, except zero, which always clears
    /// (PRD Enabled rating levels).
    case rating(Rating)

    /// A colour label for every photo, or ``ColourLabel/clear`` to remove it
    /// (PRD Marking rules).
    ///
    /// ``LabelColour/orange`` and ``LabelColour/pink`` apply only while extended colours are on
    /// (PRD Marking rules and PRD Gesture-related settings).
    case label(ColourLabel)

    /// Reject every photo, which keeps each rating (PRD Marking rules).
    ///
    /// G1 decision 5 keeps Reject in Clove's storage for every photo set, never in XMP, and the
    /// move to the rejects folder is its durable result.
    case reject
}
