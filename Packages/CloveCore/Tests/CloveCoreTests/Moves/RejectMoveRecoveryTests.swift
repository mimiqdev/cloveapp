import Foundation
import Testing

@testable import CloveCore

/// After a run: counts, retry of failed items only, the stored Reject, progress and a rescan.
///
/// PRD P0-10 and "Failure and recovery" keep moved photos moved, retry only the failures, and
/// remove only what the confirmed move makes durable (G1 decision 5).
@Suite("Reject move recovery", .timeLimit(.minutes(1)))
struct RejectMoveRecoveryTests {
    /// A partial failure reports PRD P0-10's counts, and a retry sends only the failed set.
    @Test func retriesOnlyTheFailedSets() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<3).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw], sidecarName: "IMG_000\(index).xmp")
        }
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let plan = try await fixture.plan(sets)
        let failedDestination = try #require(plan.readyEntries[1].files.first?.destination)
        fixture.fileSystem.fail(.move, at: failedDestination, with: POSIXError(.EIO))
        let before = fixture.folder.fileCount()

        let result = try await fixture.move(plan)

        #expect(result.movedCount == 2)
        #expect(result.failedCount == 1)
        #expect(result.failed.first?.identity == sets[1].id)
        #expect(result.partialFailureSummary == "Moved 2 photos. 1 photos couldn't be moved.")
        #expect(fixture.folder.exists("DCIM/1/IMG_0001.ARW"))
        #expect(fixture.folder.exists("_Rejected/DCIM/0/IMG_0000.ARW"))
        #expect(fixture.folder.exists("_Rejected/DCIM/2/IMG_0002.ARW"))
        #expect(fixture.folder.fileCount() == before)

        fixture.fileSystem.stopFailing(.move)
        let retried = try await fixture.mover.retryFailed(in: result.id)
        let retry = try #require(retried)
        #expect(retry.outcomes.map(\.identity) == [sets[1].id])
        #expect(retry.movedCount == 1)
        #expect(retry.failedCount == 0)
        #expect(fixture.folder.exists("_Rejected/DCIM/1/IMG_0001.ARW"))
        #expect(fixture.folder.fileCount() == before)
        // The earlier run's handle is spent, so a second retry cannot resend moved sets.
        #expect(try await fixture.mover.retryFailed(in: result.id) == nil)
    }

    /// A retry can exclude a failed set whose Reject was cleared, and never moves it (P0-10).
    @Test func retryExcludingASetLeavesItsFilesAlone() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<2).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw], sidecarName: "IMG_000\(index).xmp")
        }
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let plan = try await fixture.plan(sets)
        fixture.fileSystem.fail(
            .move, where: { $0.path(percentEncoded: false).contains("/_Rejected/") },
            with: POSIXError(.EIO))
        let result = try await fixture.move(plan)
        #expect(result.failedCount == 2)
        #expect(fixture.folder.exists("DCIM/0/IMG_0000.ARW"))
        #expect(fixture.folder.exists("DCIM/1/IMG_0001.ARW"))

        fixture.fileSystem.stopFailing(.move)
        let retried = try await fixture.mover.retryFailed(
            in: result.id, excluding: [sets[0].id])
        let retry = try #require(retried)
        #expect(retry.outcomes.map(\.identity) == [sets[1].id])
        #expect(retry.movedCount == 1)
        #expect(fixture.folder.exists("DCIM/0/IMG_0000.ARW"))
        #expect(!fixture.folder.exists("_Rejected/DCIM/0/IMG_0000.ARW"))
        #expect(fixture.folder.exists("_Rejected/DCIM/1/IMG_0001.ARW"))
    }

    /// The stored Reject is removed only after a confirmed move (G1 decision 5).
    @Test func removesTheStoredRejectAfterAConfirmedMove() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.jpeg])
        try writeMoveSet(set, in: fixture.folder)
        let change = await fixture.queue.apply(.reject(true), to: set)
        #expect(change.state == .storedInClove)

        let result = try await fixture.move(try await fixture.plan([set]))

        #expect(result.movedCount == 1)
        #expect(result.moved.first?.removedStoredReject == true)
        #expect(result.moved.first?.staleRejectRecord == nil)
        let stored = try await fixture.queue.storedMarks(for: set.id)
        #expect(stored?.isRejected != true)
    }

    /// A stored Reject that cannot be removed leaves the set moved and reports the record.
    @Test func countsASetMovedWhenTheStoredRejectCannotBeRemoved() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001", formats: [.jpeg])
        try writeMoveSet(set, in: fixture.folder)
        _ = await fixture.queue.apply(.reject(true), to: set)
        fixture.markFileSystem.failWrites { url in
            url.path(percentEncoded: false).contains("/store/") ? POSIXError(.EIO) : nil
        }

        let result = try await fixture.move(try await fixture.plan([set]))

        #expect(result.movedCount == 1)
        #expect(result.failedCount == 0)
        let moved = try #require(result.moved.first)
        #expect(moved.removedStoredReject == false)
        #expect(moved.staleRejectRecord != nil)
        let stored = try await fixture.queue.storedMarks(for: set.id)
        #expect(stored?.isRejected == true)
    }

    /// A run pushes each set's start and end, then its result, as one sequence.
    @Test func publishesProgressPerSetAndTheFinishedResult() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let sets = try (0..<2).map { index in
            try makeMoveSet(
                root: fixture.folder.url, relativePath: "DCIM/\(index)", stem: "IMG_000\(index)",
                formats: [.raw])
        }
        for set in sets { try writeMoveSet(set, in: fixture.folder) }
        let plan = try await fixture.plan(sets)
        let stream = await fixture.mover.progressUpdates()
        let moveTask = Task { try await fixture.mover.move(plan) }

        var events: [RejectMoveProgress] = []
        for await event in stream {
            events.append(event)
            if case .finished = event { break }
        }
        let result = try await moveTask.value

        #expect(events.count == 5)
        let started = events.compactMap { event -> PhotoIdentity? in
            guard case .setStarted(let identity) = event else { return nil }
            return identity
        }
        let finished = events.compactMap { event -> RejectMoveOutcome? in
            guard case .setFinished(let outcome) = event else { return nil }
            return outcome
        }
        #expect(started == sets.map(\.id))
        #expect(finished.map(\.identity) == sets.map(\.id))
        guard case .finished(let published)? = events.last else {
            Issue.record("The run should end with its result")
            return
        }
        #expect(published == result)
    }

    /// A rescan with C12's rejects folder name lists no moved photo (G1 decision 5).
    @Test func aRescanListsNoMovedPhoto() async throws {
        let fixture = try MoveFixture(rejectsFolderName: "Keep")
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "DCIM", stem: "IMG_0001",
            formats: [.raw, .jpeg], sidecarName: "IMG_0001.xmp")
        try writeMoveSet(set, in: fixture.folder)
        let folderID = FolderIdentity(rawValue: "rescan-folder")
        let settings = moveSettings(rejectsFolderName: "Keep")
        let before = try await scanItems(
            root: fixture.folder.url, folderID: folderID,
            configuration: settings.scanConfiguration)
        #expect(before.count == 1)

        _ = try await fixture.move(try await fixture.plan([set]))
        let after = try await scanItems(
            root: fixture.folder.url, folderID: folderID,
            configuration: settings.scanConfiguration)

        #expect(after.isEmpty)
        #expect(fixture.folder.exists("Keep/DCIM/IMG_0001.ARW"))
    }
}

/// Every item a scan lists, so a rescan can prove what it no longer shows.
func scanItems(
    root: URL, folderID: FolderIdentity, configuration: ScanConfiguration
) async throws -> [ScanItem] {
    let scan = FolderScan(
        folderURL: root, folderID: folderID, configuration: configuration)
    var items: [ScanItem] = []
    for try await batch in scan { items.append(contentsOf: batch.items) }
    _ = try await scan.summary()
    return items
}
