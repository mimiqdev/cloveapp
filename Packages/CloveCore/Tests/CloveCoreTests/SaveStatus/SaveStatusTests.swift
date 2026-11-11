import Foundation
import Testing

@testable import CloveCore

struct SaveStatusTests {
    @Test func folderLossExplainsTheLocation() {
        #expect(
            SaveStatus.situation(
                for: FolderLocationLoss(
                    reason: .externalVolumeDisconnected, date: Date())) == .driveDisconnected)
        #expect(
            SaveStatus.situation(
                for: FolderLocationLoss(
                    reason: .locationUnavailable, date: Date())) == .locationUnavailable)
    }

    @Test func failedFolderAccessKeepsItsExplanation() {
        #expect(
            SaveStatus.situation(
                for: FolderAccessFailure.locationUnavailable(
                    FolderErrorChain(CocoaError(.fileNoSuchFile)))) == .locationUnavailable)
        #expect(
            SaveStatus.situation(
                for: FolderAccessFailure.permissionDenied(
                    FolderErrorChain(CocoaError(.fileReadNoPermission)))) == .lostPermission)
    }
}
