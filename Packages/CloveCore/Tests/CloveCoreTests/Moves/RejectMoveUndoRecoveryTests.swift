import Foundation
import Testing

@testable import CloveCore

/// Undoing a move that cannot fully come back: taken paths, rollbacks, split sets and retries.
///
/// PRD P0-10's Undo rule never overwrites a file that now occupies an original path, keeps a
/// photo set a unit, and reports every file's actual location when the rollback fails too. PRD
/// "Failure and recovery" retries only the failed items and keeps a failed Reject mark as a
/// diagnostic instead of an unrestored photo (G1 decision 5).
@Suite("Reject move undo recovery", .timeLimit(.minutes(1)))
struct RejectMoveUndoRecoveryTests {
    /// A taken original path leaves the whole set under the rejects folder, both files intact.
    @Test func leavesASetUnderTheRejectsFolderWhenAnOriginalPathIsTaken() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        // PRD P0-10's Undo rule: a file that now uses an original path blocks its whole set.
        try fixture.folder.write("intruder", to: relativePath(of: jpeg.source, in: fixture.folder))
        let moves = fixture.fileSystem.count(of: .move)

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id))

        #expect(result.conflictCount == 1)
        #expect(result.restoredCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.splitCount == 0)
        #expect(result.restoredIdentities.isEmpty)
        #expect(result.partialFailureSummary == "Restored 0 photos. 1 photos couldn't be restored.")
        let conflict = try #require(result.conflicts.first)
        #expect(conflict.identity == set.id)
        #expect(conflict.takenPaths == [jpeg.source])
        #expect(conflict.failure.reason == .conflict)
        // The check runs before any rename, so the set's other files never left the rejects folder.
        #expect(fixture.fileSystem.count(of: .move) == moves)
        #expect(
            fixture.folder.contents(of: relativePath(of: jpeg.source, in: fixture.folder))
                == Data("intruder".utf8))
        for (path, contents) in bytes {
            #expect(fixture.folder.contents(of: "_Rejected/\(path)") == contents)
        }
        // The set is still moved, so the move's durable result stands: its Reject was removed.
        #expect(try await fixture.queue.storedMarks(for: set.id) == nil)
    }

    /// One file that cannot come back rolls its set into the rejects folder, untouched.
    @Test func rollsASetBackIntoTheRejectsFolderWhenAFileCannotComeBack() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        fixture.fileSystem.fail(.move, at: jpeg.source, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id))

        #expect(result.failedCount == 1)
        #expect(result.restoredCount == 0)
        #expect(result.conflictCount == 0)
        #expect(result.splitCount == 0)
        let failure = try #require(result.failed.first)
        #expect(
            failure.failure.errorChain.contains {
                $0.domain == NSPOSIXErrorDomain && $0.code == EIO
            })
        for (path, contents) in bytes {
            #expect(!fixture.folder.exists(path))
            #expect(fixture.folder.contents(of: "_Rejected/\(path)") == contents)
        }
    }

    /// A rollback that also fails reports every file's location and is never retried blindly.
    @Test func reportsEveryFilesLocationWhenTheRollbackAlsoFails() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        fixture.fileSystem.fail(.move, at: jpeg.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(
            .move, where: { $0.path(percentEncoded: false).contains("/_Rejected/") },
            with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id))

        #expect(result.splitCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.restoredCount == 0)
        let split = try #require(result.split.first)
        #expect(!split.rollbackFailures.isEmpty)
        #expect(
            split.files.map(\.location) == [.source, .destination, .destination])
        // The split set's files are in two places, so a retry is never offered for it.
        #expect(try await fixture.mover.retryFailedUndo(in: result.id) == nil)
    }

    /// A Reject that cannot be stored after a confirmed move back is a diagnostic, not a failure.
    @Test func keepsAStoredRejectFailureAsADiagnostic() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        fixture.markFileSystem.failWrites { url in
            url.path(percentEncoded: false).contains("/store/") ? POSIXError(.EIO) : nil
        }

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id))

        #expect(result.restoredCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.conflictCount == 0)
        #expect(result.restoredIdentities == [set.id])
        let restored = try #require(result.restored.first)
        #expect(restored.isRejectStored == false)
        #expect(restored.rejectStoreFailure != nil)
        // The files are where they belong, so the photo is not counted as unrestored; PRD P0-08
        // still forbids calling the whole step complete while the mark is unconfirmed.
        #expect(result.partialFailureSummary == nil)
        #expect(result.isComplete == false)
        #expect(fixture.folder.exists("DCIM/IMG_0001.ARW"))
    }

    /// A retry sends the failed photos only, and the attempt's handle is spent afterwards.
    @Test func retriesOnlyThePhotosThatFailedToComeBack() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = [
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
                formats: [.raw]),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100BBBBB", stem: "IMG_0002",
                formats: [.raw, .jpeg], sidecarName: "IMG_0002.xmp"),
        ]
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.reject(true), to: set)
        }
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        let blocked = try #require(moveResult.moved.last?.files.first)
        fixture.fileSystem.fail(.move, at: blocked.source, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: sets[0].id))

        #expect(result.restoredCount == 1)
        #expect(result.failedCount == 1)
        #expect(result.restoredIdentities == [sets[0].id])
        #expect(fixture.folder.exists("_Rejected/DCIM/100BBBBB/IMG_0002.ARW"))

        fixture.fileSystem.stopFailing(.move)
        let retried = try await fixture.mover.retryFailedUndo(in: result.id)
        let retry = try #require(retried)

        #expect(retry.outcomes.map(\.identity) == [sets[1].id])
        #expect(retry.restoredCount == 1)
        #expect(retry.failedCount == 0)
        for set in sets {
            #expect(try await undoTestStoresReject(set, in: fixture))
            for url in set.photoSet.fileURLs {
                #expect(fixture.folder.exists(relativePath(of: url, in: fixture.folder)))
            }
        }
        #expect(try await fixture.mover.retryFailedUndo(in: result.id) == nil)
    }

    /// A retry of the move after an undo restores only the sets that retry moved.
    @Test func undoesTheSetsARetryMovedAfterAnEarlierUndo() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let first = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
            formats: [.raw])
        let second = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100BBBBB", stem: "IMG_0002",
            formats: [.raw, .jpeg], sidecarName: "IMG_0002.xmp")
        for set in [first, second] {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.reject(true), to: set)
        }
        let plan = try await fixture.plan([first, second])
        let blocked = try #require(plan.readyEntries.last?.files.first?.destination)
        try fixture.folder.write("intruder", to: relativePath(of: blocked, in: fixture.folder))
        let firstRun = try await fixture.move(plan)
        let entry = undoEntry(for: firstRun, returningTo: first.id)
        _ = try await fixture.mover.undo(entry)
        #expect(fixture.folder.exists("DCIM/100AAAAA/IMG_0001.ARW"))

        try FileManager.default.removeItem(at: blocked)
        let retried = try await fixture.mover.retryFailed(in: firstRun.id)
        #expect(try #require(retried).movedCount == 1)
        let secondUndo = try await fixture.mover.undo(entry)

        #expect(secondUndo.restoredIdentities == [second.id])
        #expect(secondUndo.isComplete)
        #expect(fixture.folder.exists("DCIM/100BBBBB/IMG_0002.ARW"))
        #expect(try await undoTestStoresReject(first, in: fixture))
        #expect(try await undoTestStoresReject(second, in: fixture))
    }
}

/// The undo step U8's history would record for a run (PRD P0-10's Undo rule).
private func undoEntry(
    for run: RejectMoveResult, returningTo photo: PhotoIdentity
) -> RejectMoveUndoEntry {
    RejectMoveUndoEntry(batch: run.id, photoToReturnTo: photo)
}

/// Every file of `sets` with the exact bytes it held before a move, by relative path.
private func undoTestContents(
    of sets: [ScannedPhotoSet], in folder: MoveTestFolder
) throws -> [String: Data] {
    var contents: [String: Data] = [:]
    for set in sets {
        for url in set.photoSet.fileURLs {
            let path = relativePath(of: url, in: folder)
            contents[path] = try #require(folder.contents(of: path))
        }
    }
    return contents
}

/// Whether Clove stores Reject for the photo again (G1 decision 5).
private func undoTestStoresReject(_ photo: ScannedPhotoSet, in fixture: MoveFixture) async throws
    -> Bool
{
    try await fixture.queue.storedMarks(for: photo.id)?.isRejected == true
}
