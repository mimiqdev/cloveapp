import Foundation
import Testing

@testable import CloveCore

/// PRD P0-09's batch changes and PRD P0-05's Undo row: each photo returns to its own marks.
@Suite("Undo of a batch")
struct MarkUndoBatchTests {
    /// One batch over photos with different marks before restores each photo's own marks.
    @Test func aBatchRestoresEachPhotoToItsOwnMarksBefore() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let before = [
            PhotoMarks(),
            PhotoMarks(rating: undoRating(4)),
            PhotoMarks(label: undoGreen),
        ]
        for index in before.indices {
            await undoSeedSidecar(before[index], at: fixture.sidecar(index))
        }
        let photos = fixture.photoSets.map(\.id)
        #expect(await fixture.history.nextUndo == nil)

        let batch = try #require(await fixture.recordBatch(.rating(undoRating(5)), on: photos))
        #expect(batch.confirmedCount == 3)
        #expect(await fixture.history.nextUndoActionName == "Rating")
        #expect(await fixture.history.nextUndo?.photos.map(\.photo) == photos)

        let result = try #require(await undoStep(fixture))
        #expect(result.droppedFromHistory == false)
        #expect(result.savedCount == 3)
        #expect(result.failedCount == 0)
        #expect(result.outcomes.map(\.photo) == photos)
        // A's and C's inverse is the unrated sidecar, B's is four stars: two C4 batches.
        for index in before.indices {
            let restored = try undoSidecarMarks(at: fixture.sidecar(index))
            #expect(restored.rating == .rated(before[index].rating))
            #expect(restored.label == before[index].label)
        }
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.canRedo)
    }

    /// PRD Undo row: a newer mark written after the action is kept and reported, not overwritten.
    @Test func aNewerMarkIsKeptAndReportedAsNotUndone() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        // No sidecar yet, so the marks before the action are unmarked.
        let status = await fixture.record(.rating(undoRating(5)), on: set.id)
        #expect(status?.state == .savedInSidecar)

        // A later C4 write, or another app, leaves a different rating in the sidecar.
        _ = await fixture.queue.apply(.rating(undoRating(1)), to: set)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(1)))

        let result = try #require(await undoStep(fixture))
        #expect(result.droppedFromHistory)
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.isNotUndone)
        #expect(outcome.status == nil)
        #expect(outcome.alreadyAtTarget.isEmpty)
        #expect(undoLeftAloneFields(outcome) == [.rating])
        #expect(outcome.leftAlone.first?.reason == .newerMark)
        #expect(result.savedCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.notUndoneCount == 1)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(1)))
        // Nothing reached the target and no write is left to retry, so the entry is dropped
        // instead of blocking the next undo (PRD P0-05).
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.canRedo == false)
        #expect(await fixture.history.undoCount == 0)
    }

    /// A photo already holding the restored marks needs no write (PRD P0-05).
    @Test func aPhotoAlreadyAtTheRestoredMarkNeedsNoWrite() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let before = PhotoMarks(rating: undoRating(2))
        await undoSeedSidecar(before, at: fixture.sidecar())
        await fixture.record(.rating(undoRating(5)), on: set.id)
        let writesAfterAction = fixture.double.count(of: .writeStaging, at: fixture.sidecar())
        // Another app puts the earlier rating back before the undo runs.
        await undoSeedSidecar(before, at: fixture.sidecar())

        let result = try #require(await undoStep(fixture))
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.isAlreadyAtTarget)
        #expect(outcome.status == nil)
        #expect(outcome.alreadyAtTarget == [.rating])
        #expect(outcome.leftAlone.isEmpty)
        #expect(result.skippedCount == 1)
        #expect(result.savedCount == 0)
        #expect(
            fixture.double.count(of: .writeStaging, at: fixture.sidecar()) == writesAfterAction,
            "a photo already at the target was written again")
        // The marks are back at the earlier value, so undo counts as done and redo is offered.
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.canRedo)
    }

    /// A failed undo write is reported with counts, stays visible, and retries through C4.
    @Test func aFailedUndoReportsCountsAndRetriesThroughC4() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let batch = try #require(await fixture.recordBatch(.rating(undoRating(4)), on: photos))
        #expect(batch.confirmedCount == 3)
        // The drive runs out of space on one photo's undo write.
        fixture.double.fail(.replace, at: fixture.sidecar(1), with: POSIXError(.ENOSPC))

        let result = try #require(await undoStep(fixture))
        #expect(result.savedCount == 2)
        #expect(result.failedCount == 1)
        #expect(result.partialFailureSummary == "Saved 2 photos. 1 photos couldn't be saved.")
        let failed = try #require(result.outcomes.first { $0.status?.state.failure != nil })
        #expect(failed.photo == photos[1])
        #expect(failed.status?.state.failure?.reason == .insufficientSpace)
        #expect(try undoSidecarMarks(at: fixture.sidecar(1)).rating == .rated(undoRating(4)))
        // A failed undo stays undoable so the user can try again (DEV-PLAN C5 decision).
        #expect(await fixture.history.canUndo)
        #expect(await fixture.history.canRedo == false)

        // PRD P0-08's retry applies to exactly that change.
        let failedStatus = try #require(failed.status)
        fixture.double.stopFailing(.replace)
        let retried = try #require(await fixture.queue.retry(failedStatus.id))
        #expect(retried.state.isConfirmed)
        #expect(try undoSidecarMarks(at: fixture.sidecar(1)).rating == .rated(.unrated))
    }

    /// A failed undo that restored nothing keeps its entry for C4's retry (PRD P0-08).
    @Test func aFailedUndoThatRestoredNothingKeepsItsEntry() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(3)), on: set.id)
        // The undo's only write fails, so no field reaches the target.
        fixture.double.fail(.replace, at: fixture.sidecar(), with: POSIXError(.ENOSPC))

        let result = try #require(await undoStep(fixture))
        #expect(result.droppedFromHistory == false)
        #expect(result.failedCount == 1)
        #expect(result.savedCount == 0)
        #expect(result.outcomes[0].reachedTarget == false)
        #expect(await fixture.history.canUndo)
        #expect(await fixture.history.nextUndo != nil)
        #expect(await fixture.history.redoCount == 0)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
    }

    /// A failed redo that restored nothing keeps its entry too (PRD P0-08).
    @Test func aFailedRedoThatRestoredNothingKeepsItsEntry() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(3)), on: set.id)
        _ = try #require(await undoStep(fixture))
        #expect(await fixture.history.canRedo)
        fixture.double.fail(.replace, at: fixture.sidecar(), with: POSIXError(.ENOSPC))

        let result = try #require(await undoRedoStep(fixture))
        #expect(result.droppedFromHistory == false)
        #expect(result.failedCount == 1)
        #expect(result.outcomes[0].reachedTarget == false)
        #expect(await fixture.history.canRedo)
        #expect(await fixture.history.canUndo == false)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(.unrated))
    }

    /// A redo whose photo is gone is dropped instead of blocking the older undone action.
    @Test func aRedoWhosePhotoIsUnavailableIsDropped() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(3)), on: set.id)
        _ = try #require(await undoStep(fixture))
        // A rescan no longer finds the photo, so the redo cannot be written.
        await fixture.sets.remove(set.id)

        let result = try #require(await undoRedoStep(fixture))
        #expect(result.droppedFromHistory)
        #expect(result.outcomes[0].leftAlone.first?.reason == .photoUnavailable)
        #expect(await fixture.history.canRedo == false)
        #expect(await fixture.history.redoCount == 0)
    }

    /// A dropped undo entry does not block the older action behind it (PRD P0-05).
    @Test func theOlderEntryIsUndoneAfterANothingRestoredEntryIsDropped() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(2)), on: set.id)
        await fixture.record(.label(undoGreen), on: set.id)
        // Another app replaces the label, so undoing that change restores nothing.
        _ = await fixture.queue.apply(.label(ColourLabel(colour: .blue)), to: set)

        let dropped = try #require(await undoStep(fixture))
        #expect(dropped.droppedFromHistory)
        #expect(dropped.outcomes[0].isNotUndone)
        #expect(await fixture.history.undoCount == 1)

        // The next undo reaches the rating instead of the dropped label entry.
        let older = try #require(await undoStep(fixture))
        #expect(older.outcomes[0].isWritten)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(.unrated))
        #expect(try undoSidecarMarks(at: fixture.sidecar()).label == ColourLabel(colour: .blue))
        #expect(await fixture.history.canUndo == false)
    }

    /// A dropped unavailable-photo entry does not block the older action either (PRD P0-05).
    @Test func theOlderEntryIsUndoneAfterAnUnavailableEntryIsDropped() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B"])
        defer { fixture.remove() }
        let first = fixture.photoSets[0]
        let second = fixture.photoSets[1]
        await fixture.record(.rating(undoRating(2)), on: first.id)
        await fixture.record(.rating(undoRating(5)), on: second.id)
        // A rescan no longer finds the second photo, so its restore cannot be written.
        await fixture.sets.remove(second.id)

        let dropped = try #require(await undoStep(fixture))
        #expect(dropped.droppedFromHistory)
        #expect(dropped.outcomes[0].leftAlone.first?.reason == .photoUnavailable)
        #expect(await fixture.history.undoCount == 1)

        let older = try #require(await undoStep(fixture))
        #expect(older.outcomes[0].isWritten)
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(.unrated))
        #expect(try undoSidecarMarks(at: fixture.sidecar(1)).rating == .rated(undoRating(5)))
    }

    /// A dropped redo entry does not block the older undone action (PRD P0-05).
    @Test func theOlderRedoEntryRunsAfterANothingRestoredEntryIsDropped() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B"])
        defer { fixture.remove() }
        let first = fixture.photoSets[0]
        let second = fixture.photoSets[1]
        await fixture.record(.rating(undoRating(2)), on: first.id)
        await fixture.record(.rating(undoRating(5)), on: second.id)
        _ = try #require(await undoStep(fixture))
        _ = try #require(await undoStep(fixture))
        #expect(await fixture.history.redoCount == 2)

        // Another write replaces the first photo's restored value, so its redo restores nothing.
        _ = await fixture.queue.apply(.rating(undoRating(1)), to: first)
        let dropped = try #require(await undoRedoStep(fixture))
        #expect(dropped.droppedFromHistory)
        #expect(dropped.outcomes[0].isNotUndone)
        #expect(await fixture.history.redoCount == 1)

        // The older redo (the second photo) still runs.
        let older = try #require(await undoRedoStep(fixture))
        #expect(older.outcomes[0].isWritten)
        #expect(try undoSidecarMarks(at: fixture.sidecar(1)).rating == .rated(undoRating(5)))
    }

    /// A photo the session no longer has is reported, not written to a guessed path.
    @Test func aPhotoTheSessionNoLongerHasIsReportedAsUnavailable() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(3)), on: set.id)
        await fixture.sets.remove(set.id)

        let result = try #require(await undoStep(fixture))
        #expect(result.droppedFromHistory)
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.isNotUndone)
        #expect(undoLeftAloneFields(outcome) == [.rating])
        #expect(outcome.leftAlone.first?.reason == .photoUnavailable)
        #expect(result.notUndoneCount == 1)
        #expect(result.failedCount == 0)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.undoCount == 0)
    }

    /// Redo re-applies the change only where undo's value still holds (PRD P0-05).
    @Test func aRedoLeavesAMarkWrittenAfterTheUndoAlone() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await fixture.record(.rating(undoRating(5)), on: set.id)
        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.savedCount == 1)
        // A later write leaves a different rating in place after the undo.
        _ = await fixture.queue.apply(.rating(undoRating(1)), to: set)

        let redoResult = try #require(await undoRedoStep(fixture))
        #expect(redoResult.droppedFromHistory)
        let outcome = try #require(redoResult.outcomes.first)
        #expect(outcome.isNotUndone)
        #expect(undoLeftAloneFields(outcome) == [.rating])
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(1)))
        #expect(await fixture.history.canRedo == false)
        #expect(await fixture.history.redoCount == 0)
    }
}
