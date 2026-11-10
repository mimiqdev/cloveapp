import CloveCore
import Foundation

/// What the open folder's undo history offers the screens right now (PRD P0-05).
///
/// PRD P0-05's Undo row drives three entry points — the toolbar button, ⌘Z and the three-finger
/// gestures — from one history, so every screen reads the same answer. The library keeps this
/// value in step with C5's history and the model copies it, because the library itself is not
/// observable.
struct UndoAvailability: Hashable, Sendable {
    /// Whether there is an action to undo (PRD P0-05).
    var canUndo: Bool
    /// Whether there is an undone action to redo (PRD P0-05).
    var canRedo: Bool
    /// C5's short name for the next undo's action, which the system menu shows (PRD P0-05).
    var undoName: String?
    /// C5's short name for the next redo's action (PRD P0-05).
    var redoName: String?

    /// A folder with no recorded action, which is what opening one starts from (PRD P0-05).
    static let none = UndoAvailability(canUndo: false, canRedo: false)
}
