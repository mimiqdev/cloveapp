import Foundation
import Testing

@testable import CloveCore

struct OrderedMarkMoveTests {
    @Test func failedKeepClearDropsItsPendingMarkBeforeLaterFourStars() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "kept", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        await fixture.queue.apply(.rating(.rejected), to: set)
        var desired = DesiredPhotoMarks()
        let clear = desired.apply(
            .rating(.unrated), to: set.id, confirmed: PhotoMarks(rating: .rejected))
        fixture.markFileSystem.failWrites { _ in CocoaError(.fileWriteNoPermission) }
        let failed = await fixture.queue.apply(clear.change, to: set)
        desired.finish(for: clear.photo)
        #expect(failed.state.failure != nil)
        #expect(
            desired.shown(for: set.id, confirmed: PhotoMarks(rating: .rejected)).rating == .rejected
        )
        let four = try #require(Rating(rawValue: 4))
        let newer = desired.apply(
            .rating(four), to: set.id, confirmed: PhotoMarks(rating: .rejected))
        fixture.markFileSystem.failWrites { _ in nil }
        let confirmed = await fixture.queue.apply(newer.change, to: set)
        #expect(confirmed.state.isConfirmed)
        desired.finish(for: newer.photo)
        let bytes = try Data(
            contentsOf: set.photoSet.primary.url.deletingPathExtension().appendingPathExtension(
                "xmp"))
        #expect(try XMPCodec().read(bytes).rating == .rated(four))
    }

    @Test func moveUndoReportsKeptPhotoChangedSinceAndPreservesThreeStars() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let kept = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "kept", formats: [.raw])
        try writeMoveSet(kept, in: fixture.folder)
        await fixture.queue.apply(.rating(.unrated), to: kept)
        let emptyPlan = try await fixture.plan([])
        let run = try await fixture.move(emptyPlan)
        let three = try #require(Rating(rawValue: 3))
        await fixture.queue.apply(.rating(three), to: kept)
        let entry = RejectMoveUndoEntry(
            batch: run.id,
            keptPhotos: [RejectMoveKeptPhoto(set: kept, marksAfter: PhotoMarks())],
            photoToReturnTo: kept.id)
        let result = try await fixture.mover.undo(
            entry, currentMarks: { _ in PhotoMarks(rating: three) })
        #expect(result.changedSince == [kept.id])
        #expect(result.restoredCount == 0)
        let bytes = try Data(
            contentsOf: kept.photoSet.primary.url.deletingPathExtension().appendingPathExtension(
                "xmp"))
        #expect(try XMPCodec().read(bytes).rating == .rated(three))
    }

    @Test func moveConfirmedDuringRejectWriteCarriesNewSidecarAndUndoReturnsIt() async throws {
        let fixture = try MoveFixture()
        defer { fixture.cleanup() }
        let set = try makeMoveSet(
            root: fixture.folder.url, relativePath: "", stem: "fresh", formats: [.raw])
        try writeMoveSet(set, in: fixture.folder)
        let preview = try await fixture.plan([set])
        #expect(preview.sidecarCount == 0)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let (entered, entry) = AsyncStream<Void>.makeStream()
        var entries = entered.makeAsyncIterator()
        fixture.markFileSystem.blockWrites { _ in
            entry.yield(())
            return gate
        }
        let write = Task { await fixture.queue.apply(.rating(.rejected), to: set) }
        await entries.next()
        let move = Task { try await fixture.move(preview) }
        try await eventually { fixture.fileSystem.count(of: .isReadOnlyVolume) >= 2 }
        #expect(fixture.fileSystem.count(of: .move) == 0)
        gate.signal()
        fixture.markFileSystem.blockWrites { _ in nil }
        #expect(await write.value.state.isConfirmed)
        let result = try await move.value
        #expect(result.movedCount == 1)
        #expect(result.moved.first?.files.filter { $0.role == .sidecar }.count == 1)
        #expect(result.planDifference?.actual.sidecars == 1)
        #expect(!fixture.folder.exists("fresh.xmp"))
        #expect(fixture.folder.exists("_Rejected/fresh.xmp"))
        let undo = try await fixture.mover.undo(
            RejectMoveUndoEntry(batch: result.id, photoToReturnTo: set.id),
            currentMarks: { _ in nil })
        #expect(undo.restoredCount == 1)
        #expect(fixture.folder.exists("fresh.xmp"))
        #expect(!fixture.folder.exists("_Rejected/fresh.xmp"))
        let bytes = try Data(contentsOf: fixture.folder.file("fresh.xmp"))
        #expect(try XMPCodec().read(bytes).rating == .rated(.rejected))
    }
}
