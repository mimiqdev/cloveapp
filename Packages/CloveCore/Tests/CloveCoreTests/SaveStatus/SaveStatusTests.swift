import Foundation
import Testing

@testable import CloveCore

/// The mapping from C4's state, C11's loss and C11's open failure to the PRD's copy
/// (PRD P0-08, S1's failure table).
@Suite("Save status mapping")
struct SaveStatusTests {
    private let driveLoss = FolderLocationLoss(
        reason: .externalVolumeDisconnected, date: Date(timeIntervalSince1970: 1_760_000_000))
    private let missingLoss = FolderLocationLoss(reason: .locationUnavailable, date: Date())

    private func failure(_ reason: MarkWriteFailureReason) -> MarkChangeState {
        .failed(MarkWriteFailure(reason: reason, message: "test failure"))
    }

    /// PRD P0-08's saved words: Saved only for a sidecar read-back, Saved in Clove only for
    /// Clove storage (G1 decision 6).
    @Test func savedWordsFollowTheStorageThatConfirmedThem() {
        #expect(SaveStatus.text(for: .savedInSidecar) == "Saved")
        #expect(SaveStatus.text(for: .savedInCloveOnly) == "Saved in Clove only")
        #expect(SaveStatus.text(for: nil) == "No change yet")
    }

    /// Every state has a line, and only the confirmed sidecar and Clove marks say saved.
    @Test func everyStateHasItsOwnLine() {
        let states: [MarkChangeState?] = [
            nil, .pending, .writing, .savedInSidecar, .savedInCloveOnly,
            failure(.unknown), .superseded(by: MarkChangeID()),
        ]
        var produced: Set<String> = []
        for state in states {
            let text = SaveStatus.text(for: state)
            #expect(!text.isEmpty)
            produced.insert(text)
            if !(state == .savedInSidecar || state == .savedInCloveOnly) {
                #expect(!text.hasPrefix("Saved"), "\(String(describing: state)) read as saved")
            }
        }
        // Pending and writing share one word, and every other state has its own.
        #expect(produced.count == states.count - 1)
        #expect(produced.contains("Writing…"))
    }

    /// Every write reason maps to one PRD row, and the sidecar and store refusals fall back to
    /// the single-photo failure the PRD has copy for.
    @Test func everyWriteReasonMapsToItsSituation() {
        let expected: [MarkWriteFailureReason: SaveSituation] = [
            .permissionLost: .lostPermission,
            .readOnlyStorage: .readOnly,
            .insufficientSpace: .insufficientSpace,
            .locationUnavailable: .locationUnavailable,
            .packetRefused: .singleWriteFailure,
            .ambiguousSidecar: .singleWriteFailure,
            .notConfirmed: .singleWriteFailure,
            .conflict: .singleWriteFailure,
            .unknown: .singleWriteFailure,
        ]
        #expect(expected.count == MarkWriteFailureReason.allCases.count)
        for reason in MarkWriteFailureReason.allCases {
            #expect(
                SaveStatus.situation(for: reason, folderLoss: nil) == expected[reason],
                "\(reason)")
        }
    }

    /// A missing file is the disconnected drive only when the monitor said an external volume is
    /// gone; otherwise it keeps the missing-location copy (G1 folder access).
    @Test func aMissingLocationIsADriveOnlyWithTheMonitorsEvidence() {
        #expect(
            SaveStatus.situation(for: .locationUnavailable, folderLoss: driveLoss)
                == .driveDisconnected)
        #expect(
            SaveStatus.situation(for: .locationUnavailable, folderLoss: missingLoss)
                == .locationUnavailable)
        #expect(
            SaveStatus.situation(for: .locationUnavailable, folderLoss: nil) == .locationUnavailable
        )
        // The loss never rewrites a reason that already has its own row.
        #expect(
            SaveStatus.situation(for: .readOnlyStorage, folderLoss: driveLoss) == .readOnly)
    }

    /// Both of C11's loss reasons have their own row (PRD Failure and recovery, rows 3 and 6).
    @Test func everyLocationLossReasonMapsToItsSituation() {
        let reasons: [FolderLocationLoss.Reason] = [
            .externalVolumeDisconnected, .locationUnavailable,
        ]
        for reason in reasons {
            let loss = FolderLocationLoss(reason: reason, date: Date())
            #expect(
                SaveStatus.situation(for: loss)
                    == (reason == .externalVolumeDisconnected
                        ? .driveDisconnected : .locationUnavailable),
                "\(reason)")
        }
    }

    /// A photo's latest change explains only what failed; a saved, stored or superseded change
    /// has nothing to explain (PRD P0-08, rule 8).
    @Test func onlyAFailureAsksForCopy() {
        #expect(SaveStatus.situation(for: nil, folderLoss: nil) == nil)
        #expect(SaveStatus.situation(for: .savedInSidecar, folderLoss: nil) == nil)
        #expect(SaveStatus.situation(for: .savedInCloveOnly, folderLoss: nil) == nil)
        #expect(
            SaveStatus.situation(
                for: .superseded(by: MarkChangeID()), folderLoss: driveLoss) == nil)
        #expect(
            SaveStatus.situation(for: failure(.readOnlyStorage), folderLoss: nil) == .readOnly)
        #expect(
            SaveStatus.situation(for: failure(.insufficientSpace), folderLoss: nil)
                == .insufficientSpace)
    }

    /// PRD Failure and recovery forbids keeping Writing… on screen after a loss, so an unfinished
    /// change is explained by the folder's loss until its own write reports the failure.
    @Test func anUnfinishedChangeFollowsTheFoldersLoss() {
        #expect(SaveStatus.situation(for: .writing, folderLoss: nil) == nil)
        #expect(SaveStatus.situation(for: .pending, folderLoss: driveLoss) == .driveDisconnected)
        #expect(
            SaveStatus.situation(for: .writing, folderLoss: missingLoss) == .locationUnavailable)
        #expect(SaveStatus.text(for: .writing, folderLost: true) == "Not saved")
        #expect(SaveStatus.text(for: .writing, folderLost: false) == "Writing…")
        // A confirmed change stays confirmed; the loss does not rewrite it.
        #expect(SaveStatus.text(for: .savedInSidecar, folderLost: true) == "Saved")
    }

    /// PRD P0-02's failures from opening or reopening a folder, including the cases the PRD has
    /// no row for.
    @Test func everyFolderAccessFailureMapsWhenThePRDHasCopy() {
        let chain = FolderErrorChain(CocoaError(.fileNoSuchFile))
        let keys = FolderIdentityKeys(volumeUUID: "volume", fileIdentifier: "file")
        let failures: [(FolderAccessFailure, SaveSituation?)] = [
            (.locationUnavailable(chain), .locationUnavailable),
            (.permissionDenied(chain), .lostPermission),
            (.identityMismatch(recorded: keys, found: keys), nil),
            (.readFailed(chain), nil),
            (.storageUnavailable(.unsupportedVersion(99)), nil),
            (.unknownRecent(UUID()), nil),
        ]
        for (failure, expected) in failures {
            #expect(SaveStatus.situation(for: failure) == expected, "\(failure)")
        }
    }
}
