import Foundation
import Testing

@testable import CloveCore

/// The Move rejects sheet's wording and staged keeps, built from C6's plan and result.
///
/// The design handoff's "Move Rejects" copy replaces the PRD's proposed sentence: a title with
/// the count, the destination and "Nothing is deleted", a partial line and button once rejects
/// are kept, a toast, and a details sheet for failures (PRD P0-10).
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
            if let set = try? PhotoSet(
                folderID: identity.folderID, relativeFolderPath: identity.relativeFolderPath,
                rawURL: URL(fileURLWithPath: "/clove-copy/root/IMG_\(index).ARW"))
            {
                sets.append(
                    ScannedPhotoSet(
                        photoSet: set, sidecar: .absent,
                        imageFiles: set.imageFiles.map { file in
                            ScannedImageFile(file: file, size: nil, modificationDate: nil)
                        }))
            }
        }
        for index in 0..<refused {
            let identity = PhotoIdentity(
                folderID: FolderIdentity(rawValue: "folder-copy"),
                relativeFolderPath: "DCIM/100CAM", stem: "REFUSED_\(index)")
            entries.append(.refused(identity: identity, refusal: .outsideOpenedFolder))
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
        func files(_ identity: PhotoIdentity) -> [RejectMoveFilePlan] {
            [
                RejectMoveFilePlan(
                    role: .primary,
                    source: URL(fileURLWithPath: "/clove-copy/root/\(identity.stem).CR3"),
                    destination: URL(
                        fileURLWithPath: "/clove-copy/root/_Rejected/\(identity.stem).CR3")),
                RejectMoveFilePlan(
                    role: .jpegCompanion,
                    source: URL(fileURLWithPath: "/clove-copy/root/\(identity.stem).JPG"),
                    destination: URL(
                        fileURLWithPath: "/clove-copy/root/_Rejected/\(identity.stem).JPG")),
            ]
        }
        var outcomes: [RejectMoveOutcome] = []
        for index in 0..<moved {
            let id = identity("moved", index)
            outcomes.append(
                .moved(
                    RejectMoveMovedSet(
                        identity: id, files: files(id),
                        removedStoredReject: true, staleRejectRecord: nil)))
        }
        for index in 0..<failed {
            let id = identity("failed", index)
            outcomes.append(
                .failed(
                    RejectMoveFailedSet(
                        identity: id,
                        failure: RejectMoveFailure(reason: .readOnlyStorage, message: "failed"),
                        files: files(id))))
        }
        for index in 0..<split {
            let id = identity("split", index)
            outcomes.append(
                .split(
                    RejectMoveSplitSet(
                        identity: id,
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

    /// The handoff's sheet copy names the count, the configured folder and the no-delete promise.
    @Test func confirmationUsesHandoffStrings() {
        let confirmation = RejectMoveConfirmation(
            plan: makePlan(photos: 2, jpegCompanions: 2, sidecars: 2, folderName: "Outtakes"))

        #expect(confirmation.title == "Move 2 rejected photos")
        #expect(confirmation.body == "To Outtakes in this folder. Nothing is deleted.")
        #expect(confirmation.partialLine == nil)
        #expect(confirmation.moveButtonTitle == "Move")
        #expect(confirmation.refusedMessage == nil)

        let one = RejectMoveConfirmation(plan: makePlan(photos: 1))
        #expect(one.title == "Move 1 rejected photo")
        #expect(one.body == "To _Rejected in this folder. Nothing is deleted.")
    }

    /// Keeping one reject updates the count and the button, without changing the title (P0-10).
    @Test func confirmationCountsStagedKeeps() throws {
        let plan = makePlan(photos: 3, sidecars: 3)
        let selection = RejectMoveKeepSelection(plan: plan)
        let kept = try #require(plan.readyEntries.first?.identity)
        var withKeep = selection
        withKeep.toggle(kept)

        let confirmation = RejectMoveConfirmation(selection: withKeep)
        #expect(confirmation.title == "Move 3 rejected photos")
        #expect(confirmation.partialLine == "2 of 3 will move")
        #expect(confirmation.moveButtonTitle == "Move 2")
        #expect(confirmation.movingCount == 2)
    }

    /// A refused set gets its own line so the photo count never hides it (PRD P0-10).
    @Test func confirmationReportsRefusedSetsSeparately() {
        let plural = RejectMoveConfirmation(
            plan: makePlan(photos: 2, refused: 3, folderName: "_Rejected"))
        #expect(plural.refusedCount == 3)
        #expect(plural.refusedMessage == "3 photos can't be moved right now.")

        let singular = RejectMoveConfirmation(plan: makePlan(photos: 1, refused: 1))
        #expect(singular.refusedMessage == "1 photo can't be moved right now.")
    }

    /// A keep toggles both ways and keeps the kept set out of the staged moving plan (P0-10).
    @Test func keepSelectionStagesWhichSetsMove() throws {
        let plan = makePlan(photos: 3, sidecars: 3)
        var selection = RejectMoveKeepSelection(plan: plan)
        let first = try #require(plan.readyEntries.first?.identity)
        let second = try #require(plan.readyEntries.dropFirst().first?.identity)

        selection.toggle(first)
        #expect(selection.keptIdentities == [first])
        #expect(selection.movingCount == 2)
        #expect(selection.orderedKeptIdentities == [first])
        #expect(!selection.movingPlan.readyEntries.contains { $0.identity == first })
        #expect(selection.movingPlan.readyEntries.contains { $0.identity == second })

        selection.toggle(first)
        #expect(selection.keptIdentities.isEmpty)
        #expect(selection.movingCount == 3)
        #expect(selection.movingPlan.readyEntries.count == 3)
    }

    /// The all-moved toast is "Moved N to <folder>", with no failure line or Details (handoff).
    @Test func toastConfirmsAllMoved() {
        let toast = RejectMoveToast(
            result: makeResult(moved: 2), rejectsFolderName: .defaultFolderName)
        #expect(toast.message == "Moved 2 to _Rejected")
        #expect(toast.failureMessage == nil)
        #expect(toast.skippedMessage == nil)
        #expect(!toast.showsDetails)
    }

    /// A partial toast adds the failed count and Details; skipped sets get their own line (P0-10).
    @Test func toastKeepsPartialFailuresAndSkippedSetsVisible() {
        let partial = RejectMoveToast(
            result: makeResult(moved: 1, failed: 1, skipped: 1),
            rejectsFolderName: RejectsFolderName(rawValue: "Outtakes") ?? .defaultFolderName)
        #expect(partial.message == "Moved 1 to Outtakes")
        #expect(partial.failureMessage == "1 couldn't be moved")
        #expect(partial.skippedMessage == "1 photo was skipped.")
        #expect(partial.showsDetails)
    }

    /// The details sheet uses the handoff's title, subtitle, file names, reasons and retry rule.
    @Test func detailsSheetNamesFailedSetsAndReasons() {
        let details = RejectMoveDetails(result: makeResult(moved: 1, failed: 1, split: 1))

        #expect(details.title == "2 photos couldn't be moved")
        #expect(details.subtitle == "They stay rejected in Clove. Nothing was deleted.")
        #expect(details.rows.count == 2)
        #expect(details.rows[0].fileName == "failed_0.CR3 + JPG")
        #expect(details.rows[0].reason == "The location is read-only.")
        #expect(details.rows[1].fileName == "split_0")
        #expect(details.canRetry)

        let one = RejectMoveDetails(result: makeResult(failed: 1))
        #expect(one.title == "1 photo couldn't be moved")
        #expect(!RejectMoveDetails(result: makeResult(moved: 2)).canRetry)
    }

    /// The read-only sentence PRD Failure and recovery proposes lives in one place.
    @Test func readOnlyCopyMatchesThePRDSentence() {
        #expect(
            RejectMoveCopy.viewOnlyLocation
                == "You can view this location, but can't save marks here.")
    }
    /// A failed photo whose Reject was cleared is excluded from the retry and reported apart.
    @Test func retrySelectionDropsPhotosNoLongerRejected() {
        let result = makeResult(failed: 2)
        let first = result.failed[0].identity
        let second = result.failed[1].identity
        let selection = RejectMoveRetrySelection(
            result: result, keptIdentities: [], rejectedIdentities: [first])

        #expect(selection.retryable.map(\.identity) == [first])
        #expect(selection.noLongerRejected.map(\.identity) == [second])
        #expect(selection.excludedFromRetry == [second])
        #expect(selection.clearFailures.isEmpty)
    }

    /// The merge keeps earlier moves, carries the retry's handle and reports cleared rejects as
    /// skips, while a kept clear that still fails stays a failure (PRD P0-10).
    @Test func retryMergeKeepsEarlierMovesAndUnresolvedFailures() {
        let previous = makeResult(moved: 1, failed: 2)
        let retried = makeResult(moved: 1)
        let keptIdentity = previous.failed[1].identity
        let keptFailure = RejectMoveFailedSet(
            identity: keptIdentity,
            failure: RejectMoveFailure(reason: .notConfirmed, message: "clear failed"),
            files: [])

        let combined = RejectMoveRetryMerge.result(
            previous: previous, retried: retried,
            unresolvedClearFailures: [keptFailure],
            noLongerRejected: [previous.failed[0].identity])

        #expect(combined.id == retried.id)
        #expect(combined.movedCount == 2)
        #expect(combined.failedCount == 1)
        #expect(combined.noLongerRejectedCount == 1)
        #expect(combined.otherSkippedCount == 0)
        #expect(combined.skipped.first?.reason == .noLongerRejected)
    }

    /// A kept clear records confirmation or failure, and only confirmed clears are restored.
    @Test func keepClearingTracksRestoreAndFailures() {
        let plan = makePlan(photos: 2, sidecars: 2)
        var selection = RejectMoveKeepSelection(plan: plan)
        let first = plan.readyEntries[0].identity
        let second = plan.readyEntries[1].identity
        selection.toggle(first)
        selection.toggle(second)

        var clearing = RejectMoveKeepClearing()
        clearing.record(
            MarkChangeStatus(
                id: MarkChangeID(), identity: first, requested: .rating(.unrated),
                state: .savedInSidecar),
            for: first, files: plan.readyEntries[0].files)
        clearing.record(
            MarkChangeStatus(
                id: MarkChangeID(), identity: second, requested: .rating(.unrated),
                state: .failed(MarkWriteFailure(reason: .unknown, message: "failed"))),
            for: second, files: plan.readyEntries[1].files)

        #expect(clearing.clearedIdentities == [first])
        #expect(clearing.restorationIdentities == [first])
        #expect(clearing.clearFailures.map(\.identity) == [second])
        // A failed clear never changes which staged sets the move excludes.
        #expect(!selection.movingPlan.readyEntries.contains { $0.identity == first })
        #expect(!selection.movingPlan.readyEntries.contains { $0.identity == second })
    }

    /// The toast and details show a cleared reject as no longer rejected, not as a failure.
    @Test func copyReportsNoLongerRejectedSeparately() {
        let result = RejectMoveRetryMerge.result(
            previous: makeResult(failed: 1), retried: nil,
            unresolvedClearFailures: [],
            noLongerRejected: [makeResult(failed: 1).failed[0].identity])
        let toast = RejectMoveToast(result: result, rejectsFolderName: .defaultFolderName)
        #expect(toast.skippedMessage == nil)
        #expect(toast.noLongerRejectedMessage == "1 photo is no longer rejected.")
        #expect(!toast.showsDetails)
        let details = RejectMoveDetails(result: result)
        #expect(details.noLongerRejectedMessage == "1 photo is no longer rejected.")
        #expect(details.rows.isEmpty)
    }

}
