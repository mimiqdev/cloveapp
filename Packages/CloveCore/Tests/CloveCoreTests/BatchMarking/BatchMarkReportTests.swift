import Foundation
import Testing

import CloveCore

/// PRD P0-09 and PRD Failure and recovery: what the bar reports after a batch and what a retry
/// resends. The copy comes from C4's `MarkBatchResult`, so these tests pin the counts behind it
/// and the failed photos a retry may touch.
@Suite("Batch mark report")
struct BatchMarkReportTests {
    /// A partial batch reports the PRD copy and the photos a retry would resend, keeping the
    /// saved ones out of it.
    @Test func aPartialBatchReportsTheCopyAndTheFailedPhotos() throws {
        let saved = [
            status("a", .savedInSidecar), status("b", .savedInSidecar),
        ]
        let failed = status(
            "c",
            .failed(
                MarkWriteFailure(reason: .notConfirmed, message: "The sidecar did not read back.")))
        let result = MarkBatchResult(
            id: MarkBatchID(), change: MarkChange(rating: BatchMarkFixtures.stars(2)),
            outcomes: saved + [failed])
        let report = BatchMarkReport(result)

        #expect(report.summary == "Saved 2 photos. 1 photos couldn't be saved.")
        #expect(report.savedCount == 2)
        #expect(report.failedCount == 1)
        #expect(report.failedPhotos == [BatchMarkFixtures.photo("c")])
        #expect(report.savedPhotos == ["a", "b"].map(BatchMarkFixtures.photo))
        #expect(report.canRetry)
        #expect(report.batch == result.id)
        #expect(report.change == MarkChange(rating: BatchMarkFixtures.stars(2)))
    }

    /// A batch where every photo was saved has nothing to report and nothing to retry
    /// (PRD P0-09: "All saved: a short confirmation, or nothing").
    @Test func aFullySavedBatchHasNothingToReport() {
        let result = MarkBatchResult(
            id: MarkBatchID(), change: MarkChange(label: ColourLabel(colour: .red)),
            outcomes: [status("a", .savedInSidecar), status("b", .savedInSidecar)])
        let report = BatchMarkReport(result)

        #expect(report.summary == nil)
        #expect(!report.canRetry)
        #expect(report.failedCount == 0)
    }

    /// A superseded photo is neither saved nor failed, so a retry leaves it alone
    /// (PRD How marks reach disk, rule 8).
    @Test func aSupersededPhotoIsNeitherSavedNorRetried() {
        let result = MarkBatchResult(
            id: MarkBatchID(), change: MarkChange(rating: .rejected),
            outcomes: [
                status("a", .savedInSidecar),
                status("b", .superseded(by: MarkChangeID())),
            ])
        let report = BatchMarkReport(result)

        #expect(report.summary == nil)
        #expect(!report.canRetry)
        #expect(report.failedPhotos.isEmpty)
        // Reject writes the sidecar like any rating, so a confirmed reject is Saved.
        #expect(report.savedPhotos == [BatchMarkFixtures.photo("a")])
    }

    /// One change's status for one fixture photo.
    private func status(_ stem: String, _ state: MarkChangeState) -> MarkChangeStatus {
        MarkChangeStatus(
            id: MarkChangeID(), identity: BatchMarkFixtures.photo(stem),
            requested: MarkChange(rating: BatchMarkFixtures.stars(2)), state: state)
    }

    /// A retry that saves the last failed photo clears the copy and counts the whole action
    /// (PRD P0-09).
    @Test func aSuccessfulRetryClearsTheSummaryAndKeepsTheActionsCount() throws {
        let report = BatchMarkReport(
            MarkBatchResult(
                id: MarkBatchID(), change: MarkChange(rating: BatchMarkFixtures.stars(2)),
                outcomes: [
                    status("a", .savedInSidecar), status("b", .savedInSidecar),
                    status("c", .failed(MarkWriteFailure(reason: .notConfirmed, message: ""))),
                ]))
        let retry = MarkBatchID()
        let merged = report.merging(
            MarkBatchResult(
                id: retry, change: report.change,
                outcomes: [status("c", .savedInSidecar)]))

        #expect(merged.summary == nil)
        #expect(merged.savedCount == 3)
        #expect(!merged.canRetry)
        #expect(merged.batch == retry)
    }

    /// A retry that fails again keeps the action's copy instead of reporting that none of its
    /// photos were saved (PRD P0-09, PRD Failure and recovery).
    @Test func aFailedRetryKeepsTheActionsCopy() {
        let failure = MarkWriteFailure(reason: .notConfirmed, message: "")
        let report = BatchMarkReport(
            MarkBatchResult(
                id: MarkBatchID(), change: MarkChange(rating: BatchMarkFixtures.stars(2)),
                outcomes: [
                    status("a", .savedInSidecar), status("b", .savedInSidecar),
                    status("c", .failed(failure)),
                ]))
        let merged = report.merging(
            MarkBatchResult(
                id: MarkBatchID(), change: report.change,
                outcomes: [status("c", .failed(failure))]))

        #expect(merged.summary == "Saved 2 photos. 1 photos couldn't be saved.")
        #expect(merged.failedPhotos == [BatchMarkFixtures.photo("c")])
        #expect(merged.canRetry)
    }
}
