/// What one marking input asks the detail view to do (PRD P0-06).
///
/// Every gesture, key and control tap resolves to exactly one of these outcomes, so the view
/// never re-derives a marking rule. Only `.mark` writes and can start auto-advance (PRD
/// Auto-advance); `.noChange` neither writes nor moves, and an input that would leave the marks
/// equal always reports it (PRD P0-06 acceptance).
public enum MarkingResult: Hashable, Sendable {
    /// The marks stay as they are, so nothing is written and no auto-advance starts.
    case noChange

    /// Apply the change and, for this mark kind, start auto-advance (PRD Auto-advance).
    case mark(MarkChange, MarkKind)

    /// Show the previous photo (PRD Gestures and keyboard: `←` or a left edge tap).
    case previousPhoto

    /// Show the next photo (PRD Gestures and keyboard: `→` or a right edge tap).
    case nextPhoto

    /// Undo the last change; the undo stack belongs to C5 (PRD Undo row and `⌘Z`).
    case undo
}
