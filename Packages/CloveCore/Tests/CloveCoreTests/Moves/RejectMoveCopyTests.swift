import Foundation
import Testing

@testable import CloveCore

/// The Move rejects sheet's wording, built from C6's plan and result (PRD Move rejects, P0-10).
///
/// PRD "Proposed copy" and Failure and recovery fix the meaning of these sentences: the
/// confirmation names the counts, the travelling file kinds and the destination folder, and the
/// result keeps moved, failed and skipped sets separate.
@Suite("Reject move copy", .timeLimit(.minutes(1)))
struct RejectMoveCopyTests {
    /// A plan with the requested companion kinds, sidecars and refused sets.
    private func makePlan(
        photos: Int = 2,
        jpegCompanions: Int = 0,
        heifCompanions: Int = 0,
        sidecars: Int = 0,
        refused: Int = 0,
        folderName: String = "_Rejected"
    ) -> RejectMovePlan {
        let root = URL(fileURLWithPath: "/clove-copy/root", isDirectory: true)
        let configuration = RejectMoveConfiguration(
            rejectsFolderName: RejectsFolderName(rawValue: folderName) ?? .defaultFolderName)
        let destination = root.appendingPathComponent(folderName, isDirectory: true)
        var entries: [RejectMovePlanEntry] = []
        var sets: [ScannedPhotoSet] = []
        for index in 0..<photos {
            let identity = PhotoIdentity(
                folderID: FolderIdentity(rawValue: "folder-copy"),
                relativeFolderPath: "DCIM/100CAM", stem: String(format: "IMG_%04d", index))
            var members: [RejectMoveFilePlan] = [
                RejectMoveFilePlan(
                    role: .primary,
                    source: URL(fileURLWithPath: "/clove-copy/root/IMG_\(index).ARW"),
                    destination: destination.appendingPathComponent("IMG_\(index).ARW"))
            ]
            if index < jpegCompanions {
                members.append(
                    RejectMoveFilePlan(
                        role: .jpegCompanion,
                        source: URL(fileURLWithPath: "/clove-copy/root/IMG_\(index).JPG"),
                        destination: destination.appendingPathComponent("IMG_\(index).JPG")))
            }
            if index < heifCompanions {
                members.append(
                    RejectMoveFilePlan(
                        role: .heifCompanion,
                        source: URL(fileURLWithPath: "/clove-copy/root/IMG_\(index).HIF"),
                        destination: destination.appendingPathComponent("IMG_\(index).HIF")))
            }
            if index < sidecars {
                members.append(
                    RejectMoveFilePlan(
                        role: .sidecar,
                        source: URL(fileURLWithPath: "/clove-copy/root/IMG_\(index).xmp"),
                        destination: destination.appendingPathComponent("IMG_\(index).xmp")))
            }
            entries.append(
                .ready(
                    RejectMoveSetPlan(
                        identity: identity, relativeFolderPath: "DCIM/100CAM",
                        destinationFolder: destination, files: members)))
        }
        for index in 0..<refused {
            let identity = PhotoIdentity(
                folderID: FolderIdentity(rawValue: "folder-copy"),
                relativeFolderPath: "DCIM/100CAM", stem: "REFUSED_\(index)")
            entries.append(
                .refused(identity: identity, refusal: .outsideOpenedFolder))
        }
        return RejectMovePlan(
            rootURL: root, configuration: configuration, sets: sets, entries: entries,
            destinationURL: destination)
    }

    /// A result with the requested outcomes and no file details.
    private func makeResult(
        moved: Int = 0, failed: Int = 0, split: Int = 0, skipped: Int = 0
    ) -> RejectMoveResult {
        let folderID = FolderIdentity(rawValue: "folder-copy")
        func identity(_ kind: String, _ index: Int) -> PhotoIdentity {
            PhotoIdentity(
                folderID: folderID, relativeFolderPath: "DCIM/100CAM",
                stem: "\(kind)_\(index)")
        }
        var outcomes: [RejectMoveOutcome] = []
        for index in 0..<moved {
            outcomes.append(
                .moved(
                    RejectMoveMovedSet(
                        identity: identity("moved", index), files: [],
                        removedStoredReject: true, staleRejectRecord: nil)))
        }
        for index in 0..<failed {
            outcomes.append(
                .failed(
                    RejectMoveFailedSet(
                        identity: identity("failed", index),
                        failure: RejectMoveFailure(reason: .unknown, message: "failed"),
                        files: [])))
        }
        for index in 0..<split {
            outcomes.append(
                .split(
                    RejectMoveSplitSet(
                        identity: identity("split", index),
                        failure: RejectMoveFailure(reason: .notConfirmed, message: "split"),
                        rollbackFailures: [], files: [])))
        }
        for index in 0..<skipped {
            outcomes.append(
                .skipped(
                    RejectMoveSkippedSet(
                        identity: identity("skipped", index),
                        reason: .unfinishedMarkChange, message: "skipped")))
        }
        return RejectMoveResult(id: RejectMoveBatchID(), outcomes: outcomes)
    }

    /// PRD's proposed Move confirmation names every travelling kind and the configured folder.
    @Test func confirmationNamesThePlanKindsAndFolder() {
        let confirmation = RejectMoveConfirmation(
            plan: makePlan(
                photos: 2, jpegCompanions: 1, heifCompanions: 1, sidecars: 2,
                folderName: "Outtakes"))

        #expect(confirmation.photoCount == 2)
        #expect(confirmation.companionCount == 2)
        #expect(confirmation.sidecarCount == 2)
        #expect(confirmation.refusedCount == 0)
        #expect(confirmation.refusedMessage == nil)
        #expect(
            confirmation.message
                == "Move 2 rejected photos, with their JPEG companion, HIF companion and XMP,"
                + " to the \"Outtakes\" folder? Originals won't be deleted.")
    }

    /// The sentence names only the kinds the plan contains; no lost companions or invented XMP.
    @Test func confirmationOmitsKindsThePlanDoesNotContain() {
        let xmpOnly = RejectMoveConfirmation(
            plan: makePlan(photos: 1, sidecars: 1, folderName: "_Rejected"))
        #expect(
            xmpOnly.message
                == "Move 1 rejected photo, with their XMP, to the \"_Rejected\" folder?"
                + " Originals won't be deleted.")

        let jpegOnly = RejectMoveConfirmation(
            plan: makePlan(photos: 3, jpegCompanions: 3, folderName: "_Rejected"))
        #expect(
            jpegOnly.message
                == "Move 3 rejected photos, with their JPEG companions, to the \"_Rejected\""
                + " folder? Originals won't be deleted.")

        let noFiles = RejectMoveConfirmation(
            plan: makePlan(photos: 1, folderName: "_Rejected"))
        #expect(
            noFiles.message
                == "Move 1 rejected photo to the \"_Rejected\" folder? Originals won't be deleted.")
    }

    /// A refused set gets its own line so the photo count never hides it (PRD P0-10).
    @Test func confirmationReportsRefusedSetsSeparately() {
        let plural = RejectMoveConfirmation(
            plan: makePlan(photos: 2, sidecars: 2, refused: 3, folderName: "_Rejected"))
        #expect(plural.refusedCount == 3)
        #expect(plural.refusedMessage == "3 photos can't be moved right now.")
        #expect(plural.message.contains("Move 2 rejected photos"))

        let singular = RejectMoveConfirmation(
            plan: makePlan(photos: 1, refused: 1, folderName: "_Rejected"))
        #expect(singular.refusedMessage == "1 photo can't be moved right now.")
    }

    /// All moved shows a short confirmation, and skipped sets are counted apart from failures.
    @Test func resultConfirmsAllMovedAndNamesSkippedSets() {
        let allMoved = RejectMoveResultSummary(result: makeResult(moved: 2))
        #expect(allMoved.message == "Moved 2 photos.")
        #expect(allMoved.skippedMessage == nil)
        #expect(!allMoved.canRetry)

        let oneMoved = RejectMoveResultSummary(result: makeResult(moved: 1))
        #expect(oneMoved.message == "Moved 1 photo.")

        let skipped = RejectMoveResultSummary(result: makeResult(moved: 2, skipped: 1))
        #expect(skipped.message == "Moved 2 photos.")
        #expect(skipped.skippedMessage == "1 photo was skipped.")
        #expect(!skipped.canRetry)
    }

    /// PRD's partial move copy counts failed and split sets, and only failed ones can retry.
    @Test func resultKeepsPartialFailuresRetryable() {
        let partial = RejectMoveResultSummary(result: makeResult(moved: 2, failed: 1, skipped: 1))
        #expect(partial.message == "Moved 2 photos. 1 photos couldn't be moved.")
        #expect(partial.skippedMessage == "1 photo was skipped.")
        #expect(partial.canRetry)

        let splitOnly = RejectMoveResultSummary(result: makeResult(moved: 1, split: 1))
        #expect(splitOnly.message == "Moved 1 photos. 1 photos couldn't be moved.")
        #expect(!splitOnly.canRetry)
    }

    /// The read-only sentence PRD Failure and recovery proposes lives in one place.
    @Test func readOnlyCopyMatchesThePRDSentence() {
        #expect(
            RejectMoveCopy.viewOnlyLocation
                == "You can view this location, but can't save marks here.")
    }
}
