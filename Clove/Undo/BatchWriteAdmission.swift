import CloveCore

/// One bar action C4 admitted, ready to be written (PRD P0-09; PRD P0-05's Undo row).
///
/// It keeps the queue's per-photo admissions, so the undo record takes each photo's "before"
/// marks from C4 itself, and the photos the folder no longer holds, so a retry reports them. The
/// library keeps its own handle for `retryFailed(in:)`.
struct BatchWriteAdmission: Sendable {
    /// The change the action named first, for the result's label (PRD P0-09).
    let change: MarkChange
    /// Every queue batch the action admitted, one per distinct per-photo change (PRD P0-09).
    let batches: [MarkBatchAdmission]
    /// One admission per writable photo, in the caller's item order (PRD P0-05).
    let admissions: [MarkChangeAdmission]
    /// The photos the folder no longer holds (PRD P0-08).
    let unavailable: [BatchMarkItem]
    /// The library's own handle for the action, for a retry (PRD P0-09).
    let libraryBatch: MarkBatchID
    /// The caller's item order, so the result and the record keep it (PRD P0-09).
    let order: [PhotoIdentity: Int]
}
