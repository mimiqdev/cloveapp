import CloveCore
import Foundation

/// One confirmed change to push onto the open folder's undo history (PRD P0-05, P0-12).
///
/// The browsing model records every change it applied, and this value is what it hands the
/// library, so one action produces exactly one undo step:
///
/// - ``mark(change:photo:marksBefore:)`` — a rating, label or Reject on one photo, from the HUD, a
///   swipe or a keyboard input (PRD P0-05).
/// - ``batch(result:marksBefore:)`` — one multi-select bar action over its photos (PRD P0-09).
/// - ``groupFinishing(_:)`` — one finishing action over its group (PRD P0-12).
///
/// A later kind of step joins the same stack by adding a case here and a matching C5 record, so
/// the model, the library and the system undo bridge need no second path.
enum UndoRecordRequest: Sendable {
    /// One photo's mark change, with the marks the photo had before it (PRD P0-05).
    ///
    /// It carries the request rather than C4's final status because the model records it as soon
    /// as the write is admitted, so a mark whose write is still running can be undone and the
    /// history keeps the order the user marked in even when two writes finish in another order.
    case mark(change: MarkChange, photo: PhotoIdentity, marksBefore: PhotoMarks)
    /// One bar action's per-photo results, with each photo's marks before it (PRD P0-09).
    case batch(result: MarkBatchResult, marksBefore: [PhotoIdentity: PhotoMarks])
    /// One executed finishing action, with C10's record of the marks it changed (PRD P0-12).
    case groupFinishing(GroupFinishingUndo)
}
