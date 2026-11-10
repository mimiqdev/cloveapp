import Foundation

/// What the multi-select bar reports after one batch write (PRD P0-09, PRD Failure and recovery).
///
/// PRD P0-09 counts successes and failures per photo, keeps the successful writes, and retries
/// only the failed items; the PRD's "Partial batch failure" row gives the copy "Saved N photos.
/// M photos couldn't be saved." C4 already keeps those counts on ``MarkBatchResult``. This value
/// adds the two things the bar needs, and the tests pin both: whether every requested photo was
/// saved, and which photos a retry would resend, so the grid can keep a failed photo free of the
/// mark it did not save.
///
/// The summary uses C4's ``MarkBatchResult/partialFailureSummary`` unchanged, so the batch bar
/// and the rest of Clove cannot drift into two readings of the same failure. A retry's own
/// result is merged with this one, so the copy keeps counting the whole action instead of the few
/// photos the retry resent. U7 owns the final save-state copy for the other failures.
public struct BatchMarkReport: Hashable, Sendable, Identifiable {
    /// The action's per-photo results, with every retry's results merged in (PRD P0-09).
    private let result: MarkBatchResult

    /// The batch a retry resends, and the handle the bar reports (PRD P0-09).
    ///
    /// C4's ``MarkBatchResult/id`` is the retry input: a retry of this handle touches only the
    /// photos the batch still has not saved.
    public var batch: MarkBatchID { result.id }

    /// The change the batch asked for, kept so a report can name the action it repeated
    /// (PRD P0-09).
    public var change: MarkChange { result.change }

    /// The photos whose marks were confirmed in their storage, in the batch's order
    /// (PRD P0-08).
    public var savedPhotos: [PhotoIdentity] { result.saved.map(\.identity) }

    /// The photos whose marks the batch did not save, in the batch's order (PRD P0-09).
    ///
    /// A photo here still shows the marks it had before the batch: PRD P0-08 forbids showing an
    /// unconfirmed change as saved.
    public var failedPhotos: [PhotoIdentity] { result.failed.map(\.identity) }

    /// PRD Failure and recovery's partial-batch copy, or nil when the batch failed nothing.
    public var summary: String? { result.partialFailureSummary }

    /// The batch a retry resends (PRD P0-09).
    public var id: MarkBatchID { result.id }

    /// PRD P0-09's "Saved N photos" (PRD P0-08's Saved, not U7's copy).
    public var savedCount: Int { result.savedCount }

    /// PRD P0-09's "M photos couldn't be saved".
    public var failedCount: Int { result.failedCount }

    /// Whether a retry has something to resend (PRD P0-09).
    public var canRetry: Bool { failedCount > 0 }

    /// Reads one batch result as the bar's report (PRD P0-09).
    ///
    /// A superseded photo is neither saved nor failed: a newer change replaced its write, so a
    /// retry must leave it alone (PRD How marks reach disk, rule 8).
    public init(_ result: MarkBatchResult) {
        self.result = result
    }

    /// The report after a retry of some of the failed photos (PRD P0-09).
    ///
    /// A retry's result counts only the photos it resent, so reporting it alone would tell the
    /// user that an action with two saved photos saved none. The retry's outcomes replace the
    /// photos it retried and the action's confirmed photos stay, which keeps the copy's counts on
    /// the whole action while still naming only the photos a further retry would resend.
    public func merging(_ retried: MarkBatchResult) -> BatchMarkReport {
        var outcomes = retried.outcomes
        outcomes.append(contentsOf: result.outcomes.filter { $0.state.isConfirmed })
        return BatchMarkReport(
            MarkBatchResult(id: retried.id, change: change, outcomes: outcomes))
    }
}
