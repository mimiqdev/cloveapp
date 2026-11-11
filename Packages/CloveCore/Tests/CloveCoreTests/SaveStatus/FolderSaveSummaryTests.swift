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
    /// confirmed in a sidecar, and a count for the photos whose change did not.
    @Test func theSummaryReportsWritingSavedOrUnconfirmed() {
        #expect(FolderSaveSummary(states: []).text == "No changes yet")
        #expect(FolderSaveSummary(states: []).hasUnfinished == false)
        #expect(FolderSaveSummary(states: [.savedInSidecar, .savedInSidecar]).text == "All saved")
        // A waiting or running write wins over a finished one, so the folder never reads saved
        // while a change is still on its way to storage.
        #expect(FolderSaveSummary(states: [.savedInSidecar, .pending]).text == "Writing…")
        #expect(FolderSaveSummary(states: [.writing]).text == "Writing…")
        #expect(FolderSaveSummary(states: [.savedInSidecar, failed()]).text == "1 photo not saved")
        #expect(FolderSaveSummary(states: [failed(), failed()]).text == "2 photos not saved")
        #expect(FolderSaveSummary(states: [failed(), failed()]).failed == 2)
        #expect(FolderSaveSummary(states: [.writing]).hasUnfinished)
    }

    /// PRD Failure and recovery keeps a failure visible while other writes run, so a running
    /// write never hides the count or takes the unsaved list away.
    @Test func aRunningWriteDoesNotHideAFailure() {
        let summary = FolderSaveSummary(states: [.writing, failed(), .savedInSidecar])
        #expect(summary.text == "Writing…, 1 not saved")
        #expect(summary.hasUnfinished)
    }

    /// G1 decision 6 keeps the confirmed kinds apart: a Clove-only mark is not Saved and is never
    /// folded into All saved.
    @Test func cloveStorageKeepsItsOwnWords() {
        #expect(FolderSaveSummary(states: [.savedInCloveOnly]).text == "1 saved in Clove only")
        #expect(
            FolderSaveSummary(states: [.savedInCloveOnly, .savedInCloveOnly]).text
                == "2 saved in Clove only")
        #expect(
            FolderSaveSummary(states: [.savedInSidecar, .savedInCloveOnly]).text
                == "1 saved, 1 saved in Clove only")
        #expect(!FolderSaveSummary(states: [.savedInCloveOnly]).isAllSaved)
        #expect(!FolderSaveSummary(states: [.savedInCloveOnly]).text.contains("All saved"))
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
        #expect(LeaveFolderConfirmation(states: [.savedInCloveOnly]).shouldAsk == false)
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
