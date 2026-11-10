import Foundation
import Testing

@testable import CloveCore

/// Undoing a completed move: every set back in place, Reject stored, kept photos re-rejected.
///
/// PRD P0-10's Undo rule moves a completed move's files back to their original paths and never
/// overwrites, and PRD Move rejects' "Keeping before the move" adds the photos the confirmation
/// kept. Each test checks the files' actual bytes, not only the reported outcome, so a passing
/// test proves nothing was lost, copied or overwritten.
@Suite("Reject move undo", .timeLimit(.minutes(1)))
struct RejectMoveUndoTests {
    /// Every moved set comes back byte for byte, across subfolders and companion kinds.
    @Test func restoresEverySetAtItsOriginalPath() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = [
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0001",
                formats: [.raw]),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100AAAAA", stem: "IMG_0002",
                formats: [.raw, .jpeg], sidecarName: "IMG_0002.xmp"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100BBBBB", stem: "IMG_0003",
                formats: [.raw, .heif], sidecarName: "IMG_0003.XMP"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/100BBBBB", stem: "IMG_0004",
                formats: [.raw, .jpeg, .heif], sidecarName: "IMG_0004.xmp"),
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "", stem: "IMG_0005", formats: [.jpeg]),
        ]
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.reject(true), to: set)
        }
        let before = fixture.folder.files()
        let original = try originalContents(of: sets, in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        #expect(moveResult.movedCount == sets.count)
        for path in original.keys {
            #expect(!fixture.folder.exists(path))
        }

        let result = try await fixture.mover.undo(
            undoStep(for: moveResult, returningTo: sets[0].id))

        #expect(result.restoredCount == sets.count)
        #expect(result.keptCount == 0)
        #expect(result.conflictCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.splitCount == 0)
        #expect(result.isComplete)
        #expect(result.partialFailureSummary == nil)
        #expect(result.restoredIdentities == sets.map(\.id))
        for (path, bytes) in original {
            #expect(fixture.folder.contents(of: path) == bytes)
        }
        // A move renames and an undo renames back, so the folder holds exactly what it did.
        #expect(fixture.folder.files() == before)
        // PRD P0-10's Undo rule deletes nothing, including the folders the move created.
        #expect(fixture.folder.isDirectory("_Rejected/DCIM/100AAAAA"))
        #expect(fixture.folder.isDirectory("_Rejected/DCIM/100BBBBB"))
        for set in sets {
            #expect(try await storesReject(set, in: fixture))
            let restored = try #require(result.restored.first { $0.identity == set.id })
            #expect(restored.keptInConfirmation == false)
            #expect(restored.isRejectStored)
            #expect(restored.files.count == set.photoSet.fileURLs.count)
            #expect(restored.set == set)
        }
    }

    /// A kept photo never moved, so undo restores only the Reject the move cleared.
    @Test func restoresRejectOnThePhotosTheConfirmationKept() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let moved = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        // A standalone JPEG keeps its rating and label in Clove, so the test can read them back
        // without a sidecar (G1 decision 6).
        let kept = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0002", formats: [.jpeg])
        for set in [moved, kept] {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.reject(true), to: set)
        }
        await fixture.queue.apply(
            MarkChange(rating: Rating(rawValue: 3), label: ColourLabel(colour: .red)), to: kept)
        // PRD Move rejects: a keep is applied on Move, which clears only the kept photo's Reject.
        await fixture.queue.apply(.reject(false), to: kept)
        let keptBytes = try originalContents(of: [kept], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([moved]))
        #expect(moveResult.movedCount == 1)

        let result = try await fixture.mover.undo(
            undoStep(for: moveResult, keeping: [kept], returningTo: kept.id))

        #expect(result.restoredCount == 2)
        #expect(result.keptCount == 1)
        #expect(result.restoredIdentities == [moved.id, kept.id])
        #expect(try await storesReject(moved, in: fixture))
        #expect(try await storesReject(kept, in: fixture))
        let keptMarks = try await fixture.queue.storedMarks(for: kept.id)
        #expect(keptMarks?.rating == Rating(rawValue: 3))
        #expect(keptMarks?.label == ColourLabel(colour: .red))
        let restored = try #require(result.kept.first)
        #expect(restored.identity == kept.id)
        #expect(restored.files.isEmpty)
        #expect(restored.isRejectStored)
        for (path, bytes) in keptBytes {
            #expect(fixture.folder.contents(of: path) == bytes)
        }
    }

    /// A retry moves more of the same run, and one undo still restores the whole run.
    @Test func undoCoversTheSetsARetryMoved() async throws {
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
        let original = try originalContents(of: [first, second], in: fixture.folder)
        let plan = try await fixture.plan([first, second])
        let blocked = try #require(plan.readyEntries.last?.files.first?.destination)
        // A file at the second set's destination makes that set fail its first attempt.
        try fixture.folder.write("intruder", to: relativePath(of: blocked, in: fixture.folder))
        let firstRun = try await fixture.move(plan)
        #expect(firstRun.movedCount == 1)
        #expect(firstRun.failedCount == 1)
        try FileManager.default.removeItem(at: blocked)
        let retried = try await fixture.mover.retryFailed(in: firstRun.id)
        let retry = try #require(retried)
        #expect(retry.movedCount == 1)

        let result = try await fixture.mover.undo(
            undoStep(for: firstRun, returningTo: first.id))

        #expect(result.restoredIdentities == [first.id, second.id])
        #expect(result.isComplete)
        for (path, bytes) in original {
            #expect(fixture.folder.contents(of: path) == bytes)
        }
        #expect(try await storesReject(first, in: fixture))
        #expect(try await storesReject(second, in: fixture))
    }

    /// The run's handle stops working after one undo, whatever handle the caller holds.
    @Test func refusesASecondUndoOfTheSameRun() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let entry = undoStep(for: moveResult, returningTo: set.id)

        let result = try await fixture.mover.undo(entry)
        #expect(result.restoredCount == 1)

        await #expect(throws: RejectMoveUndoRefusal.alreadyUndone(entry.batch)) {
            try await fixture.mover.undo(entry)
        }
        #expect(fixture.folder.exists("DCIM/IMG_0001.ARW"))
        #expect(try await storesReject(set, in: fixture))
    }

    /// A handle the mover never handed out touches nothing and says so.
    @Test func refusesARunTheMoverDoesNotHold() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let entry = RejectMoveUndoEntry(
            batch: RejectMoveBatchID(), photoToReturnTo: set.id)

        await #expect(throws: RejectMoveUndoRefusal.unknownBatch(entry.batch)) {
            try await fixture.mover.undo(entry)
        }
        #expect(fixture.folder.exists("DCIM/IMG_0001.ARW"))
    }

    /// A read-only location is refused as a whole request and leaves the step undoable.
    @Test func refusesAReadOnlyLocationWithoutSpendingTheStep() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.reject(true), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let entry = undoStep(for: moveResult, returningTo: set.id)
        let moves = fixture.fileSystem.count(of: .move)
        fixture.fileSystem.reportsReadOnlyVolume = true

        await #expect(throws: RejectMoveUndoRefusal.self) {
            try await fixture.mover.undo(entry)
        }
        #expect(fixture.fileSystem.count(of: .move) == moves)
        #expect(fixture.folder.exists("_Rejected/DCIM/IMG_0001.ARW"))

        fixture.fileSystem.reportsReadOnlyVolume = false
        let result = try await fixture.mover.undo(entry)
        #expect(result.restoredCount == 1)
        #expect(fixture.folder.exists("DCIM/IMG_0001.ARW"))
    }

    /// An undo pushes each photo's start and end, then its result, as one sequence.
    @Test func publishesUndoProgressPerPhotoAndTheFinishedResult() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<2).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw])
        }
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.reject(true), to: set)
        }
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        let entry = undoStep(for: moveResult, returningTo: sets[0].id)
        let stream = await fixture.mover.undoProgressUpdates()
        let undoTask = Task { try await fixture.mover.undo(entry) }

        var events: [RejectMoveUndoProgress] = []
        for await event in stream {
            events.append(event)
            if case .finished = event { break }
        }
        let result = try await undoTask.value

        #expect(events.count == 5)
        let started = events.compactMap { event -> PhotoIdentity? in
            guard case .photoStarted(let identity) = event else { return nil }
            return identity
        }
        let finished = events.compactMap { event -> RejectMoveUndoOutcome? in
            guard case .photoFinished(let outcome) = event else { return nil }
            return outcome
        }
        #expect(started == sets.map(\.id))
        #expect(finished.map(\.identity) == sets.map(\.id))
        guard case .finished(let published)? = events.last else {
            Issue.record("The undo should end with its result")
            return
        }
        #expect(published == result)
    }
}

/// The undo step U8's history would record for a run (PRD P0-10's Undo rule).
private func undoStep(
    for run: RejectMoveResult, keeping kept: [ScannedPhotoSet] = [],
    returningTo photo: PhotoIdentity
) -> RejectMoveUndoEntry {
    RejectMoveUndoEntry(batch: run.id, keptPhotos: kept, photoToReturnTo: photo)
}

/// Every file of `sets` with the exact bytes it held before a move, by relative path.
private func originalContents(
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
private func storesReject(_ photo: ScannedPhotoSet, in fixture: MoveFixture) async throws -> Bool {
    try await fixture.queue.storedMarks(for: photo.id)?.isRejected == true
}
