import Foundation
import Testing

@testable import CloveCore

/// The open folder's indicator and the question before leaving it (PRD P0-08).
@Suite("Folder save summary")
struct FolderSaveSummaryTests {
    private func failed(_ reason: MarkWriteFailureReason = .notConfirmed) -> MarkChangeState {
        .failed(MarkWriteFailure(reason: reason, message: "test failure"))
    }

    /// PRD P0-08 shows Writing… while a change is unfinished, Saved only once every change
    /// confirmed, and a count for the photos whose change did not.
    @Test func theSummaryReportsWritingSavedOrUnconfirmed() {
        #expect(FolderSaveSummary(states: []).text == "No changes yet")
        #expect(FolderSaveSummary(states: []).unsavedCount == 0)
        #expect(
            FolderSaveSummary(states: [.savedInSidecar, .savedInCloveOnly]).text == "All saved")
        // A Clove-stored Reject is confirmed but never saved, so the folder line says how many
        // are only stored instead of folding them into All saved (G1 decision 5, PRD P0-08).
        #expect(FolderSaveSummary(states: [.storedInClove]).text == "1 stored in Clove")
        #expect(
            FolderSaveSummary(states: [.storedInClove, .storedInClove]).text == "2 stored in Clove")
        #expect(
            FolderSaveSummary(states: [.savedInSidecar, .storedInClove]).text == "1 stored in Clove"
        )
        // A waiting or running write wins over a finished one, so the folder never reads saved
        // while a change is still on its way to storage.
        #expect(FolderSaveSummary(states: [.savedInSidecar, .pending]).text == "Writing…")
        #expect(FolderSaveSummary(states: [.writing]).text == "Writing…")
        #expect(FolderSaveSummary(states: [.savedInSidecar, failed()]).text == "1 photo not saved")
        #expect(FolderSaveSummary(states: [failed(), failed()]).text == "2 photos not saved")
        #expect(FolderSaveSummary(states: [failed(), failed()]).unsavedCount == 2)
    }

    /// A superseded change counts as neither saved nor unsaved, because a newer change the user
    /// asked for replaced it (PRD How marks reach disk, rule 8).
    @Test func aSupersededChangeDoesNotCount() {
        let superseded: MarkChangeState = .superseded(by: MarkChangeID())
        #expect(FolderSaveSummary(states: [superseded]).text == "No changes yet")
        #expect(FolderSaveSummary(states: [superseded, .savedInSidecar]).text == "All saved")
    }

    /// The question appears only when something is unfinished; a saved folder leaves silently.
    @Test func leavingAsksOnlyWithUnfinishedChanges() {
        #expect(LeaveFolderConfirmation(states: []).shouldAsk == false)
        #expect(LeaveFolderConfirmation(states: [.savedInSidecar]).shouldAsk == false)
        #expect(LeaveFolderConfirmation(states: [.storedInClove]).shouldAsk == false)
        #expect(
            LeaveFolderConfirmation(states: [.superseded(by: MarkChangeID())]).shouldAsk == false)
        #expect(LeaveFolderConfirmation(states: [.savedInSidecar]).question == nil)

        let waiting = LeaveFolderConfirmation(states: [.savedInSidecar, .writing])
        #expect(waiting.shouldAsk)
        #expect(waiting.unfinishedCount == 1)
        #expect(waiting.question == "Some marks haven't finished saving.")

        // A failed change stays unfinished until it is retried or superseded (rule 8), so it asks
        // exactly like one that has not been written yet.
        let failedOnce = LeaveFolderConfirmation(states: [failed(), failed()])
        #expect(failedOnce.shouldAsk)
        #expect(failedOnce.unfinishedCount == 2)
    }
}
