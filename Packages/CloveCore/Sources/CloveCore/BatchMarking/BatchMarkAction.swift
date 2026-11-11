import Foundation

/// One mark the multi-select bar applies to every selected photo (PRD P0-09, PRD Marking rules).
///
/// PRD P0-09's bar offers a rating, a colour label and Reject. PRD Marking rules decide what each
/// one means: a rating from −1 to 5 where −1 is Reject and 0 clears, a colour label where Clear
/// removes it, and Reject as the rating −1. The action is the bar's request only;
/// ``BatchMarkPlan`` turns it into one change per photo through C13's rules.
public enum BatchMarkAction: Hashable, Sendable {
    /// A −1…5 rating for every photo; zero clears the rating, Reject included (PRD Marking rules).
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

    /// Reject every photo, which replaces each rating with −1 (PRD Marking rules).
    ///
    /// The rating's own storage holds the value (G1 decisions 2 and 6), and the move to the
    /// rejects folder is Reject's durable result.
    case reject
}
