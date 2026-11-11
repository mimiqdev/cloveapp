import Foundation
import Testing

@testable import CloveCore

/// The history itself: no-change inputs, redo clearing, the depth limit and moved photos.
@Suite("Undo history")
struct MarkUndoHistoryTests {
    /// PRD P0-06's no-change rule: a change that leaves the marks equal has nothing to restore.
    @Test func aChangeThatLeavesTheMarksEqualRecordsNothing() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        // An unrated photo asked for the unrated value: C4 writes it, but nothing changed.
        let status = await fixture.queue.apply(.rating(.unrated), to: set)
        #expect(status.state.isConfirmed)

        let entry = await fixture.history.record(status, marksBefore: PhotoMarks())

        #expect(entry == nil)
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.undoCount == 0)
    }

    /// A request naming no marks is refused by C4 and never recorded.
    @Test func anEmptyChangeRecordsNothing() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)

        let status = await fixture.queue.apply(MarkChange(), to: set)
        let entry = await fixture.history.record(status, marksBefore: PhotoMarks())

        #expect(status.state.failure != nil)
        #expect(entry == nil)
        #expect(await fixture.history.canUndo == false)
    }

    /// PRD P0-05: undo is last in, first out, and a new recorded action discards the redo future.
    @Test func aNewRecordedChangeClearsTheRedoHistory() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(3)), on: set.id)
        _ = try #require(await undoStep(fixture))
        #expect(await fixture.history.canRedo)
        #expect(await fixture.history.nextRedoActionName == "Rating")

        await fixture.record(.label(undoGreen), on: set.id)

        #expect(await fixture.history.canRedo == false)
        #expect(await fixture.history.redoCount == 0)
        #expect(await fixture.history.nextUndoActionName == "Label")
        #expect(await fixture.history.nextRedo == nil)
    }

    /// The depth limit keeps the newest actions and drops the oldest (DEV-PLAN C5 decision).
    @Test func theHistoryKeepsOnlyTheNewestDefaultDepthActions() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let limit = MarkUndoHistory.defaultDepthLimit
        // Record a few more actions than the limit, alternating ratings so each changes a field.
        for step in 0..<(limit + 3) {
            let rating = undoRating(step.isMultiple(of: 2) ? 3 : 4)
            await fixture.record(.rating(rating), on: set.id)
        }

        #expect(await fixture.history.undoCount == limit)
        #expect(await fixture.history.nextUndo?.photos.first?.change.rating == undoRating(3))

        var undone = 0
        while await fixture.history.canUndo, undone < limit {
            #expect(await undoStep(fixture) != nil)
            undone += 1
        }

        #expect(undone == limit)
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.redoCount == limit)
    }

    /// PRD Move rejects: entries lose moved photos, and an entry left with none is removed.
    @Test func movedPhotosAreDroppedAndAnEmptiedEntryIsRemoved() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        // Two entries: a rating on A alone, then a label batch over A, B and C.
        await fixture.record(.rating(undoRating(3)), on: photos[0])
        _ = try #require(await fixture.recordBatch(.label(undoGreen), on: photos))
        #expect(await fixture.history.undoCount == 2)

        // C6 confirmed moving A to _Rejected.
        await fixture.history.forgetMovedPhotos([photos[0]])

        #expect(await fixture.history.undoCount == 1)
        #expect(await fixture.history.nextUndo?.photos.map(\.photo) == [photos[1], photos[2]])
        #expect(await fixture.history.nextUndo?.photoToReturnTo == photos[1])

        let result = try #require(await undoStep(fixture))
        #expect(result.outcomes.map(\.photo) == [photos[1], photos[2]])
        #expect(result.photoToReturnTo == photos[1])
        // The moved photo's old sidecar keeps both marks: undo wrote nothing to it.
        #expect(
            try undoSidecarMarks(at: fixture.sidecar(0))
                == XMPMarks(rating: .rated(undoRating(3)), label: undoGreen))
    }
}
