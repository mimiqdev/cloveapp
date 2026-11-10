import CloveCore
import Foundation

/// One confirmed change to push onto the open folder's undo history (PRD P0-05, P0-12).
///
/// The browsing model records every change it applied, and this value is what it hands the
/// library, so one action produces exactly one undo step. A mark and a bar action are recorded
/// when they start — before their writes finish, in the state C4 admits a change in — so a slow
/// write cannot reorder the history and Undo is live while the write runs:
///
/// - ``mark(admission:)`` — a rating, label or Reject on one photo, from the HUD, a swipe or a
///   keyboard input (PRD P0-05).
/// - ``batch(admission:)`` — one multi-select bar action over its photos (PRD P0-09).
/// - ``groupFinishing(_:)`` — one finishing action over its group (PRD P0-12).
///
/// A later kind of step joins the same stack by adding a case here and a matching C5 record, so
/// the model, the library and the system undo bridge need no second path.
enum UndoRecordRequest: Sendable {
    /// One photo's mark change, with the marks C4 reported just before admitting it
    /// (PRD P0-05).
    ///
    /// The "before" marks come from C4's own admission, so a slow write, a burst of taps or a
    /// finishing action writing at the same time cannot hide the value in between. The step is
    /// recorded before the write is awaited, so it exists while the write runs.
    case mark(admission: MarkChangeAdmission)
    /// One bar action's per-photo admissions, with each photo's marks C4 reported
    /// (PRD P0-09).
    case batch(admission: BatchWriteAdmission)
    /// One executed finishing action, with C10's record of the marks it changed (PRD P0-12).
    case groupFinishing(GroupFinishingUndo)
}
