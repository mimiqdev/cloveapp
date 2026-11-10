import Foundation
import Testing

@testable import CloveCore

/// The PRD's "Failure and recovery" copy, one test per situation (PRD P0-08).
@Suite("Save situations")
struct SaveSituationTests {
    /// PRD Failure and recovery requires read-only storage and insufficient space to be
    /// explained separately, so their copy must differ.
    @Test func readOnlyAndInsufficientSpaceNeverShareCopy() {
        #expect(SaveSituation.readOnly.message != SaveSituation.insufficientSpace.message)
        #expect(
            !SaveSituation.readOnly.actions.contains(.freeSpaceAndRetry),
            "Read-only storage offered the insufficient-space action")
    }

    /// Every situation carries the PRD's copy and its own actions, so no screen falls back to
    /// empty text and no two rows can be mixed up.
    @Test func everySituationHasCopyAndThePRDsActions() {
        let expected: [SaveSituation: [SaveAction]] = [
            .singleWriteFailure: [.retry, .cancel],
            .lostPermission: [.reopenFolder],
            .locationUnavailable: [.openFolder],
            .readOnly: [.cancel, .openFolder],
            .insufficientSpace: [.freeSpaceAndRetry],
            .driveDisconnected: [.reopenFolder],
        ]
        #expect(expected.count == SaveSituation.allCases.count)
        for situation in SaveSituation.allCases {
            #expect(!situation.message.isEmpty, "\(situation) had no copy")
            #expect(situation.actions == expected[situation], "\(situation)")
        }
    }

    /// PRD Failure and recovery keeps a lost permission and a missing location apart.
    @Test func lostPermissionAndMissingLocationSayDifferentThings() {
        #expect(SaveSituation.lostPermission.message != SaveSituation.locationUnavailable.message)
        #expect(SaveSituation.lostPermission.message.contains("Access"))
        #expect(SaveSituation.locationUnavailable.message.contains("found"))
    }

    /// Every action has a button title, and the two the leaving question uses follow the PRD.
    @Test func everyActionHasATitleAndTheLeavingQuestionUsesItsOwn() {
        for action in SaveAction.allCases {
            #expect(!action.title.isEmpty, "\(action) had no title")
        }
        #expect(SaveAction.retry.title == "Retry")
        #expect(SaveAction.cancel.title == "Cancel")
        let confirmation = LeaveFolderConfirmation.ask(unfinished: 1)
        #expect(confirmation.waitTitle == "Wait for writes")
        #expect(confirmation.leaveTitle == "Leave anyway")
        #expect(LeaveFolderConfirmation.message == "Some marks haven't finished saving.")
    }
}
