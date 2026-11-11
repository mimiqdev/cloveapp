import Testing

@testable import CloveCore

struct SaveSituationTests {
    @Test func folderProblemsOfferOnlyFolderActions() {
        #expect(SaveSituation.driveDisconnected.actions == [.reopenFolder])
        #expect(SaveSituation.locationUnavailable.actions == [.openFolder])
        #expect(SaveSituation.lostPermission.actions == [.reopenFolder])
        #expect(
            SaveSituation.driveDisconnected.message
                == "The drive disconnected. Reconnect it, then reopen this folder.")
    }
}
