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
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let before = fixture.folder.files()
        let original = try originalContents(of: sets, in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        #expect(moveResult.movedCount == sets.count)
        for path in original.keys {
            #expect(!fixture.folder.exists(path))
        }

        let result = try await fixture.mover.undo(
            undoStep(for: moveResult, returningTo: sets[0].id), currentMarks: { _ in PhotoMarks() })

        #expect(result.restoredCount == sets.count)
        #expect(result.keptCount == 0)
        #expect(result.conflictCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.splitCount == 0)
        #expect(result.isComplete)
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
            // The undo moves exactly what the move moved, including a sidecar C4 created
            // after the scan.
            let movedFiles = moveResult.moved.first { $0.identity == set.id }?.files.count
            #expect(restored.files.count == movedFiles)
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
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        await fixture.queue.apply(
            MarkChange(rating: Rating(rawValue: 3), label: ColourLabel(colour: .red)), to: kept)
        // PRD Move rejects: a keep is applied on Move, which clears only the kept photo's Reject.
        await fixture.queue.apply(.rating(.unrated), to: kept)
        let keptBytes = try originalContents(of: [kept], in: fixture.folder)
        let moveResult = try await fixture.move(try await fixture.plan([moved]))
        #expect(moveResult.movedCount == 1)
        // The run holds the keeps, so the step restores them even when the entry carries none.
        await fixture.mover.recordKeptPhotos(
            [RejectMoveKeptPhoto(set: kept, marksAfter: PhotoMarks())], for: moveResult.id)

        let result = try await fixture.mover.undo(
            undoStep(for: moveResult, returningTo: kept.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.restoredCount == 2)
        #expect(result.keptCount == 1)
        #expect(result.restoredIdentities == [moved.id, kept.id])
        #expect(try await storesReject(moved, in: fixture))
        #expect(try await storesReject(kept, in: fixture))
        // Undo re-rejects the kept photo, so its stored rating is −1 again; the stars the
        // reject replaced are gone, as the owner decided (decision record `reject-as-rating.md`).
        let keptMarks = try await fixture.queue.storedMarks(for: kept.id)
        #expect(keptMarks?.rating == .rejected)
        #expect(keptMarks?.label == ColourLabel(colour: .red))
        let restored = try #require(result.kept.first)
        #expect(restored.identity == kept.id)
        #expect(restored.files.isEmpty)
        #expect(restored.isRejectStored)
        for (path, bytes) in keptBytes {
            #expect(fixture.folder.contents(of: path) == bytes)
        }
    }

    /// A sidecar C4 created after the scan moves with the set, because it carries the reject.
    @Test func movesAndRestoresASidecarCreatedAfterTheScan() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let sidecarPath = "DCIM/IMG_0001.xmp"
        #expect(!fixture.folder.exists(sidecarPath))

        // Rejecting writes the sidecar, so the scanned set no longer describes the folder.
        let status = await fixture.queue.apply(.rating(.rejected), to: set)
        #expect(status.state == .savedInSidecar)
        #expect(fixture.folder.exists(sidecarPath))

        let plan = try await fixture.plan([set])
        let entry = try #require(plan.readyEntries.first)
        #expect(entry.files.contains { $0.role == .sidecar })

        let moveResult = try await fixture.move(plan)
        #expect(moveResult.movedCount == 1)
        #expect(!fixture.folder.exists(sidecarPath))
        #expect(fixture.folder.exists("_Rejected/\(sidecarPath)"))

        let undoResult = try await fixture.mover.undo(
            undoStep(for: moveResult, returningTo: set.id), currentMarks: { _ in PhotoMarks() })
        #expect(undoResult.restoredCount == 1)
        #expect(fixture.folder.exists(sidecarPath))
        #expect(
            try sidecarRating(at: fixture.folder.url.appendingPathComponent(sidecarPath))
                == .rated(.rejected))
    }

    /// A kept RAW set is written rating 0 to its sidecar on Move, and undo writes −1 again.
    @Test func keepingARawSetWritesRatingZeroAndUndoRejectsAgain() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let moved = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        let kept = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0002", formats: [.raw],
            sidecarName: "IMG_0002.xmp")
        for set in [moved, kept] {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let keptSidecar = try #require(kept.photoSet.sidecarURL)
        #expect(try sidecarRating(at: keptSidecar) == .rated(.rejected))

        // The confirmation's keep is the rating-0 write the move flow applies (PRD Move rejects).
        await fixture.queue.apply(.rating(.unrated), to: kept)
        #expect(try sidecarRating(at: keptSidecar) == .rated(.unrated))

        let moveResult = try await fixture.move(try await fixture.plan([moved]))
        await fixture.mover.recordKeptPhotos(
            [RejectMoveKeptPhoto(set: kept, marksAfter: PhotoMarks())], for: moveResult.id)
        let result = try await fixture.mover.undo(
            undoStep(for: moveResult, returningTo: kept.id), currentMarks: { _ in PhotoMarks() })

        #expect(result.restoredCount == 2)
        #expect(try sidecarRating(at: keptSidecar) == .rated(.rejected))
    }

    /// The run's handle stops working after one undo, whatever handle the caller holds.
    @Test func refusesASecondUndoOfTheSameRun() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let entry = undoStep(for: moveResult, returningTo: set.id)

        let result = try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        #expect(result.restoredCount == 1)

        await #expect(throws: RejectMoveUndoRefusal.alreadyUndone(entry.batch)) {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
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
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
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
        await fixture.queue.apply(.rating(.rejected), to: set)
        let moveResult = try await fixture.move(try await fixture.plan([set]))
        let entry = undoStep(for: moveResult, returningTo: set.id)
        let moves = fixture.fileSystem.count(of: .move)
        fixture.fileSystem.reportsReadOnlyVolume = true

        await #expect(throws: RejectMoveUndoRefusal.self) {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }
        #expect(fixture.fileSystem.count(of: .move) == moves)
        #expect(fixture.folder.exists("_Rejected/DCIM/IMG_0001.ARW"))

        fixture.fileSystem.reportsReadOnlyVolume = false
        let result = try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        #expect(result.restoredCount == 1)
        #expect(fixture.folder.exists("DCIM/IMG_0001.ARW"))
    }

    /// An undo pushes each photo's start and end, then its result, all under one attempt handle.
    @Test(.timeLimit(.minutes(1))) func publishesUndoProgressPerPhotoAndTheFinishedResult()
        async throws
    {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<2).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw])
        }
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let moveResult = try await fixture.move(try await fixture.plan(sets))
        let entry = undoStep(for: moveResult, returningTo: sets[0].id)
        let stream = await fixture.mover.undoProgressUpdates()
        let undoTask = Task {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }

        var events: [RejectMoveUndoProgress] = []
        for await event in stream {
            events.append(event)
            if case .finished = event { break }
        }
        let result = try await undoTask.value

        #expect(events.count == 5)
        let started = events.compactMap { event -> PhotoIdentity? in
            guard case .photoStarted(_, let photo) = event else { return nil }
            return photo
        }
        let finished = events.compactMap { event -> RejectMoveUndoOutcome? in
            guard case .photoFinished(_, let outcome) = event else { return nil }
            return outcome
        }
        #expect(started == sets.map(\.id))
        #expect(finished.map(\.identity) == sets.map(\.id))
        // Every photo event names the attempt, and the result is that same attempt.
        for event in events.dropLast() {
            switch event {
            case .photoStarted(let attempt, _), .photoFinished(let attempt, _):
                #expect(attempt == result.id)
            case .finished, .refused:
                Issue.record("Only the photos belong to the attempt's sequence")
            }
        }
        guard case .finished(let published)? = events.last else {
            Issue.record("The undo should end with its result")
            return
        }
        #expect(published == result)
    }

    /// Two undos running at once stay apart, because every photo event names its attempt.
    @Test(.timeLimit(.minutes(1))) func tagsProgressWithItsAttempt() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<2).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw])
        }
        for set in sets {
            try writeMoveSet(set, in: fixture.folder)
            await fixture.queue.apply(.rating(.rejected), to: set)
        }
        let firstRun = try await fixture.move(try await fixture.plan([sets[0]]))
        let secondRun = try await fixture.move(try await fixture.plan([sets[1]]))
        let stream = await fixture.mover.undoProgressUpdates()
        let firstEntry = undoStep(for: firstRun, returningTo: sets[0].id)
        let secondEntry = undoStep(for: secondRun, returningTo: sets[1].id)
        let first = Task {
            try await fixture.mover.undo(firstEntry, currentMarks: { _ in PhotoMarks() })
        }
        let second = Task {
            try await fixture.mover.undo(secondEntry, currentMarks: { _ in PhotoMarks() })
        }

        var events: [RejectMoveUndoProgress] = []
        var finishedCount = 0
        for await event in stream {
            events.append(event)
            if case .finished = event { finishedCount += 1 }
            if finishedCount == 2 { break }
        }
        let firstResult = try await first.value
        let secondResult = try await second.value

        let attempts = Set([firstResult.id, secondResult.id])
        let started = events.compactMap { event -> (RejectMoveUndoBatchID, PhotoIdentity)? in
            guard case .photoStarted(let attempt, let photo) = event else { return nil }
            return (attempt, photo)
        }
        let finished = events.compactMap { event -> (RejectMoveUndoBatchID, PhotoIdentity)? in
            guard case .photoFinished(let attempt, let outcome) = event else { return nil }
            return (attempt, outcome.identity)
        }
        #expect(started.count == 2)
        #expect(finished.count == 2)
        #expect(Set(started.map(\.0)) == attempts)
        #expect(Set(finished.map(\.0)) == attempts)
        // Each attempt's own photo carries its own handle, never the other attempt's.
        for (attempt, photo) in started {
            let owner = photo == sets[0].id ? firstResult.id : secondResult.id
            #expect(attempt == owner)
        }
        for (attempt, photo) in finished {
            let owner = photo == sets[0].id ? firstResult.id : secondResult.id
            #expect(attempt == owner)
        }
    }

    /// A refused undo ends the attempt on the stream instead of leaving a reader waiting.
    @Test(.timeLimit(.minutes(1))) func publishesARefusalForAnUndoThatCannotRun() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let entry = RejectMoveUndoEntry(batch: RejectMoveBatchID(), photoToReturnTo: set.id)
        let stream = await fixture.mover.undoProgressUpdates()

        await #expect(throws: RejectMoveUndoRefusal.unknownBatch(entry.batch)) {
            try await fixture.mover.undo(entry, currentMarks: { _ in PhotoMarks() })
        }

        var events: [RejectMoveUndoProgress] = []
        for await event in stream {
            events.append(event)
            break
        }
        #expect(
            events == [
                .refused(batch: entry.batch, refusal: .unknownBatch(entry.batch))
            ])
    }
}

/// The undo step U8's history would record for a run (PRD P0-10's Undo rule).
private func undoStep(
    for run: RejectMoveResult, keeping kept: [ScannedPhotoSet] = [],
    returningTo photo: PhotoIdentity
) -> RejectMoveUndoEntry {
    RejectMoveUndoEntry(
        batch: run.id,
        keptPhotos: kept.map { RejectMoveKeptPhoto(set: $0, marksAfter: PhotoMarks()) },
        photoToReturnTo: photo)
}

/// One sidecar's rating, read the way a folder open would read it.
private func sidecarRating(at url: URL) throws -> XMPRating {
    try XMPCodec().read(try Data(contentsOf: url)).rating
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

/// Whether the photo is rejected again in the storage its rating uses (G1 decisions 2 and 6).
private func storesReject(_ photo: ScannedPhotoSet, in fixture: MoveFixture) async throws -> Bool {
    switch photo.photoSet.markPersistence.rating {
    case .cloveStorage:
        return try await fixture.queue.storedMarks(for: photo.id)?.isRejected == true
    case .xmpSidecar(let url):
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try XMPCodec().read(try Data(contentsOf: url)).rating == .rated(.rejected)
    }
}
