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
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        // PRD P0-10's Undo rule: a file that now uses an original path blocks its whole set.
        try fixture.folder.write("intruder", to: relativePath(of: jpeg.source, in: fixture.folder))
        let moves = fixture.fileSystem.count(of: .move)

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

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

    /// A path that becomes taken between the check and the rename is a conflict, never a write
    /// over it.
    @Test func reportsAConflictWhenAnOriginalPathAppearsDuringTheUndo() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let raw = try #require(moveResult.moved.first?.files.first)
        fixture.fileSystem.fail(.move, at: raw.source, with: POSIXError(.EEXIST))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.conflictCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.splitCount == 0)
        let conflict = try #require(result.conflicts.first)
        #expect(conflict.takenPaths == [raw.source])
        #expect(conflict.failure.reason == .conflict)
        for (path, contents) in bytes {
            #expect(fixture.folder.contents(of: "_Rejected/\(path)") == contents)
        }
    }

    /// One file that cannot come back rolls its set into the rejects folder, untouched.
    @Test func rollsASetBackIntoTheRejectsFolderWhenAFileCannotComeBack() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        fixture.fileSystem.fail(.move, at: jpeg.source, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

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

    /// A move back that cannot be confirmed rolls its set into the rejects folder too.
    @Test func rollsASetBackWhenItsMoveBackCannotBeConfirmed() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let raw = try #require(moveResult.moved.first?.files.first)
        // G1 decision 5's confirmation reads the size back at the original path.
        fixture.fileSystem.fail(.fileSize, at: raw.source, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.failedCount == 1)
        #expect(result.restoredCount == 0)
        #expect(result.splitCount == 0)
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
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let jpeg = try #require(moveResult.moved.first?.files.first { $0.role == .jpegCompanion })
        fixture.fileSystem.fail(.move, at: jpeg.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(
            .move, where: { $0.path(percentEncoded: false).contains("/_Rejected/") },
            with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.splitCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.restoredCount == 0)
        let split = try #require(result.split.first)
        #expect(!split.rollbackFailures.isEmpty)
        #expect(split.files.map(\.location) == [.source, .destination, .destination])
        // The split set's files are in two places, so a retry is never offered for it.
        #expect(
            try await fixture.mover.retryFailedUndo(
                in: result.id, currentMarks: { _ in PhotoMarks() }) == nil)
    }

    /// A file the rollback returned is under the rejects folder even when its old path is reused.
    @Test func reportsTheFileTheRollbackReturnedDespiteAReusedPath() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let files = try #require(moveResult.moved.first?.files)
        let raw = try #require(files.first)
        let jpeg = try #require(files.first { $0.role == .jpegCompanion })
        let sidecar = try #require(files.first { $0.role == .sidecar })
        let jpegPath = relativePath(of: jpeg.source, in: fixture.folder)
        // The sidecar cannot come back, so the RAW and JPEG roll into the rejects folder; the RAW's
        // rollback then fails, which splits the set. The JPEG's rollback succeeds, and something
        // else takes the JPEG's original path afterwards.
        fixture.fileSystem.fail(.move, at: sidecar.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(.move, at: raw.destination, with: POSIXError(.EIO))
        fixture.fileSystem.beforeOperation = { record in
            guard record.step == .move, record.url == raw.destination else { return }
            try? Data("intruder".utf8).write(to: jpeg.source)
        }

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        let split = try #require(result.split.first)
        #expect(split.files.map(\.location) == [.source, .destination, .destination])
        #expect(split.files[1].url == jpeg.destination)
        #expect(fixture.folder.contents(of: "_Rejected/\(jpegPath)") == bytes[jpegPath])
        #expect(fixture.folder.contents(of: jpegPath) == Data("intruder".utf8))
    }

    /// A location whose path cannot be read is unknown, never the other path's file.
    @Test func reportsAnUnreadableLocationAsUnknown() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let files = try #require(moveResult.moved.first?.files)
        let jpeg = try #require(files.first { $0.role == .jpegCompanion })
        let sidecar = try #require(files.first { $0.role == .sidecar })
        // A failure partway through the set starts the rollback, and a failed rollback leaves the
        // set split, which is when every file's location is reported.
        fixture.fileSystem.fail(.move, at: jpeg.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(
            .move, where: { $0.path(percentEncoded: false).contains("/_Rejected/") },
            with: POSIXError(.EIO))
        // The sidecar's rejects-folder path is read only after the rollback, so failing it leaves
        // the report unable to answer for that file.
        fixture.fileSystem.beforeOperation = { record in
            guard record.step == .exists, record.url == sidecar.destination else { return }
            fixture.fileSystem.fail(.exists, at: sidecar.destination, with: POSIXError(.EIO))
        }

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        let split = try #require(result.split.first)
        #expect(split.files.map(\.location) == [.source, .destination, .unknown])
        #expect(fixture.folder.exists("_Rejected/DCIM/IMG_0001.xmp"))
    }

    /// A Reject that cannot be stored after a confirmed move back is a diagnostic, not a failure.
    ///
    /// A standalone JPEG keeps its rating in Clove storage, so a store write failure is the one
    /// that leaves the restored Reject unconfirmed (G1 decision 6).
    @Test func keepsAStoredRejectFailureAsADiagnostic() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.jpeg])
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        fixture.markFileSystem.failWrites { url in
            url.path(percentEncoded: false).contains("/store/") ? POSIXError(.EIO) : nil
        }

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

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
        #expect(fixture.folder.exists("DCIM/IMG_0001.JPG"))
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
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        let blocked = try #require(moveResult.moved.last?.files.first)
        fixture.fileSystem.fail(.move, at: blocked.source, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: sets[0].id), currentMarks: { _ in PhotoMarks() }
        )

        #expect(result.restoredCount == 1)
        #expect(result.failedCount == 1)
        #expect(result.restoredIdentities == [sets[0].id])
        #expect(fixture.folder.exists("_Rejected/DCIM/100BBBBB/IMG_0002.ARW"))

        fixture.fileSystem.stopFailing(.move)
        let retried = try await fixture.mover.retryFailedUndo(
            in: result.id, currentMarks: { _ in PhotoMarks() })
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
        #expect(
            try await fixture.mover.retryFailedUndo(
                in: result.id, currentMarks: { _ in PhotoMarks() }) == nil)
    }

    /// A retry sends the failed photos of a mixed attempt: no restored, conflicted or split one.
    @Test func retriesOnlyTheFailedPhotosOfAMixedAttempt() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let restored = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
            formats: [.raw])
        let conflicted = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100BBBBB", stem: "IMG_0002",
            formats: [.raw])
        let failed = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100CCCCC", stem: "IMG_0003",
            formats: [.raw, .jpeg], sidecarName: "IMG_0003.xmp")
        let split = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM/100DDDDD", stem: "IMG_0004",
            formats: [.raw, .jpeg], sidecarName: "IMG_0004.xmp")
        let sets = [restored, conflicted, failed, split]
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        #expect(moveResult.movedCount == 4)
        let files = moveResult.moved.map { set in
            Dictionary(uniqueKeysWithValues: set.files.map { ($0.role, $0) })
        }
        let conflictedRaw = try #require(files[1][.primary])
        let failedRaw = try #require(files[2][.primary])
        let splitRaw = try #require(files[3][.primary])
        let splitJpeg = try #require(files[3][.jpegCompanion])
        try fixture.folder.write(
            "intruder", to: relativePath(of: conflictedRaw.source, in: fixture.folder))
        fixture.fileSystem.fail(.move, at: failedRaw.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(.move, at: splitJpeg.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(.move, at: splitRaw.destination, with: POSIXError(.EIO))

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: restored.id),
            currentMarks: { _ in PhotoMarks() })

        #expect(result.restoredIdentities == [restored.id])
        #expect(result.conflicts.map(\.identity) == [conflicted.id])
        #expect(result.failed.map(\.identity) == [failed.id])
        #expect(result.split.map(\.identity) == [split.id])

        fixture.fileSystem.stopFailing(.move)
        let retried = try await fixture.mover.retryFailedUndo(
            in: result.id, currentMarks: { _ in PhotoMarks() })
        let retry = try #require(retried)

        #expect(retry.outcomes.map(\.identity) == [failed.id])
        #expect(retry.restoredCount == 1)
        #expect(fixture.folder.exists("DCIM/100CCCCC/IMG_0003.ARW"))
        // The conflict's and the split's files stay exactly where the undo left them.
        #expect(
            fixture.folder.contents(of: relativePath(of: conflictedRaw.source, in: fixture.folder))
                == Data("intruder".utf8))
        #expect(fixture.folder.exists(relativePath(of: splitRaw.source, in: fixture.folder)))
        #expect(fixture.folder.exists(relativePath(of: splitJpeg.destination, in: fixture.folder)))
    }

    /// A retry after the undo is refused, so nothing moves into the rejects folder again.
    @Test func refusesARetryOfAMoveThatWasUndone() async throws {
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
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let plan = try await fixture.plan([first, second])
        let blocked = try #require(plan.readyEntries.last?.files.first?.destination)
        try fixture.folder.write("intruder", to: relativePath(of: blocked, in: fixture.folder))
        let firstRun = try await fixture.move(plan)
        let entry = undoEntry(for: firstRun, returningTo: first.id)
        _ = try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        #expect(fixture.folder.exists("DCIM/100AAAAA/IMG_0001.ARW"))

        try FileManager.default.removeItem(at: blocked)
        let moves = fixture.fileSystem.count(of: .move)

        // PRD P0-10's Undo rule closes the step, so the failed set can no longer move.
        await #expect(throws: RejectMoveRefusal.undone(firstRun.id)) {
            try await fixture.mover.retryFailed(in: firstRun.id)
        }
        #expect(fixture.fileSystem.count(of: .move) == moves)
        #expect(fixture.folder.exists("DCIM/100BBBBB/IMG_0002.ARW"))
        #expect(!fixture.folder.exists("_Rejected/DCIM/100BBBBB/IMG_0002.ARW"))
        // The set never moved, so its Reject was never removed and is still there.
        #expect(try await undoTestStoresReject(second, in: fixture))
        await #expect(throws: RejectMoveUndoRefusal.alreadyUndone(entry.batch)) {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }
    }

    /// A file the user moved back before the undo is reported, never promised as still there.
    @Test func reportsASetWhoseFileIsNoLongerUnderTheRejectsFolder() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let bytes = try undoTestContents(of: [set], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let files = try #require(moveResult.moved.first?.files)
        let sidecar = try #require(files.first { $0.role == .sidecar })
        // The user moved one file back by hand, so the set cannot be restored as a unit.
        try FileManager.default.removeItem(at: sidecar.destination)
        let moves = fixture.fileSystem.count(of: .move)

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.missingFilesCount == 1)
        #expect(result.failedCount == 0)
        #expect(result.restoredCount == 0)
        #expect(result.splitCount == 0)
        #expect(result.partialFailureSummary == "Restored 0 photos. 1 photos couldn't be restored.")
        let missing = try #require(result.missingFiles.first)
        #expect(missing.identity == set.id)
        #expect(missing.files.map(\.location) == [.destination, .destination, .missing])
        // Nothing was renamed, the set's other files are still where the move left them, and the
        // set is not offered for a retry that could not do anything.
        #expect(fixture.fileSystem.count(of: .move) == moves)
        for file in files where file.role != .sidecar {
            let path = relativePath(of: file.destination, in: fixture.folder)
            let original = bytes[relativePath(of: file.source, in: fixture.folder)]
            #expect(fixture.folder.contents(of: path) == original)
        }
        #expect(
            try await fixture.mover.retryFailedUndo(
                in: result.id, currentMarks: { _ in PhotoMarks() }) == nil)
    }

    /// A file no longer where the last rename put it is unknown, never the file at its old path.
    @Test func reportsAFileThatLeftItsPlaceAsUnknown() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let files = try #require(moveResult.moved.first?.files)
        let raw = try #require(files.first)
        let jpeg = try #require(files.first { $0.role == .jpegCompanion })
        let sidecar = try #require(files.first { $0.role == .sidecar })
        let jpegPath = relativePath(of: jpeg.source, in: fixture.folder)
        // The sidecar cannot come back and the RAW's rollback fails, which splits the set; the
        // JPEG's rollback succeeds, and then the JPEG leaves the rejects folder while something
        // else takes its old path.
        fixture.fileSystem.fail(.move, at: sidecar.source, with: POSIXError(.EIO))
        fixture.fileSystem.fail(.move, at: raw.destination, with: POSIXError(.EIO))
        fixture.fileSystem.beforeOperation = { record in
            guard record.step == .move, record.url == raw.destination else { return }
            try? Data("intruder".utf8).write(to: jpeg.source)
            try? FileManager.default.removeItem(at: jpeg.destination)
        }

        let result = try await fixture.mover.undo(
            undoEntry(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })

        let split = try #require(result.split.first)
        #expect(split.files.map(\.location) == [.source, .unknown, .destination])
        #expect(fixture.folder.contents(of: jpegPath) == Data("intruder".utf8))
    }

    /// A second undo is refused while the first one is still running.
    @Test(.timeLimit(.minutes(1))) func refusesASecondUndoWhileTheFirstIsRunning() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let entry = undoEntry(for: moveResult, returningTo: set.id)
        let gate = DispatchSemaphore(value: 0)
        fixture.markFileSystem.blockWrites { _ in gate }
        // A regression that lets the second undo reach the store must still end the test, so the
        // gate releases itself if the step below never does.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            for _ in 0..<2 { gate.signal() }
        }
        defer { watchdog.cancel() }
        let stream = await fixture.mover.undoProgressUpdates()
        let undoTask = Task {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }
        var iterator = stream.makeAsyncIterator()
        let announced = await iterator.next()
        guard case .photoStarted? = announced else {
            Issue.record("The undo should announce the photo before it waits for the store")
            gate.signal()
            return
        }

        await #expect(throws: RejectMoveUndoRefusal.alreadyUndone(entry.batch)) {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }
        gate.signal()
        let result = try await undoTask.value
        #expect(result.restoredCount == 1)
        #expect(try await undoTestStoresReject(set, in: fixture))
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

/// Whether the photo is rejected again in the storage its rating uses (G1 decisions 2 and 6).
private func undoTestStoresReject(_ photo: ScannedPhotoSet, in fixture: MoveFixture) async throws
    -> Bool
{
    switch photo.photoSet.markPersistence.rating {
    case .cloveStorage:
        return try await fixture.queue.storedMarks(for: photo.id)?.isRejected == true
    case .xmpSidecar(let url):
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try XMPCodec().read(try Data(contentsOf: url)).rating == .rated(.rejected)
    }
}
