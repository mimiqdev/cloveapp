import Foundation
import Testing

@testable import CloveCore

/// PRD P0-05's Undo row on one photo: rating, label and Reject are restored separately.
///
/// Every step goes through C4's queue, so the sidecar and Clove storage are checked on disk
/// instead of trusting the returned state alone (PRD P0-08; G1 decisions 5–6).
@Suite("Undo of one photo")
struct MarkUndoSinglePhotoTests {
    /// A rating undo restores the sidecar rating and leaves the label it did not set alone.
    @Test func aRatingUndoRestoresTheSidecarAndRedoReappliesIt() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let before = PhotoMarks(rating: undoRating(2), label: undoGreen)
        await undoSeedSidecar(before, at: fixture.sidecar())

        let status = await fixture.record(.rating(undoRating(5)), on: set.id)
        #expect(status?.state == .savedInSidecar)
        #expect(await fixture.history.canUndo)
        #expect(await fixture.history.nextUndoActionName == "Rating")
        #expect(await fixture.history.nextUndo?.photoToReturnTo == set.id)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(5)))

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.actionName == "Rating")
        #expect(undoResult.photoToReturnTo == set.id)
        #expect(undoResult.failedCount == 0)
        #expect(undoResult.outcomes.count == 1)
        #expect(undoResult.outcomes[0].isWritten)
        #expect(undoResult.outcomes[0].status?.state == .savedInSidecar)
        // PRD P0-05: the label was not part of the change, so it keeps its value.
        #expect(
            try undoSidecarMarks(at: fixture.sidecar())
                == XMPMarks(rating: .rated(undoRating(2)), label: undoGreen))
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.canRedo)

        _ = try #require(await undoRedoStep(fixture))
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(5)))
        #expect(await fixture.history.canUndo)
        #expect(await fixture.history.canRedo == false)
    }

    /// A label undo restores the sidecar label and leaves the rating it did not set alone.
    @Test func aLabelUndoRestoresTheSidecarAndRedoReappliesIt() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await undoSeedSidecar(PhotoMarks(rating: undoRating(4)), at: fixture.sidecar())

        let status = await fixture.record(.label(undoGreen), on: set.id)
        #expect(status?.state == .savedInSidecar)
        #expect(await fixture.history.nextUndoActionName == "Label")

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.outcomes[0].leftAlone.isEmpty)
        #expect(
            try undoSidecarMarks(at: fixture.sidecar())
                == XMPMarks(rating: .rated(undoRating(4)), label: .clear))

        _ = try #require(await undoRedoStep(fixture))
        #expect(
            try undoSidecarMarks(at: fixture.sidecar())
                == XMPMarks(rating: .rated(undoRating(4)), label: undoGreen))
    }

    /// A Reject undo restores the stars it replaced, in the sidecar; redo writes −1 again.
    @Test func aRejectUndoRestoresTheStarsAndRedoRejectsAgain() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        await undoSeedSidecar(PhotoMarks(rating: undoRating(3)), at: fixture.sidecar())

        let status = await fixture.record(.rating(.rejected), on: set.id)
        #expect(status?.state == .savedInSidecar)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(.rejected))
        #expect(await fixture.history.nextUndoActionName == "Reject")

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.outcomes[0].status?.state == .savedInSidecar)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
        #expect(try await fixture.queue.storedMarks(for: set.id) == nil)

        _ = try #require(await undoRedoStep(fixture))
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(.rejected))
    }

    /// A rating replaces Reject; undo restores −1, and redo writes the stars again (C13).
    @Test func aRatingThatReplacedRejectRestoresItOnUndo() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let before = PhotoMarks(rating: .rejected)
        _ = await fixture.queue.apply(.rating(.rejected), to: set)

        let marking = MarkingInputRules().result(forRating: undoRating(3), marks: before)
        guard case .mark(let change, _) = marking else {
            Issue.record("A rating on a rejected photo should replace Reject (C13)")
            return
        }
        #expect(change == MarkChange(rating: undoRating(3)))

        let status = await fixture.record(change, on: set.id)
        #expect(status?.state == .savedInSidecar)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
        #expect(try await fixture.queue.storedMarks(for: set.id) == nil)

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.outcomes[0].isWritten)
        // PRD P0-05: undo restores the Reject rating the change replaced.
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(.rejected))

        _ = try #require(await undoRedoStep(fixture))
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
        #expect(try await fixture.queue.storedMarks(for: set.id) == nil)
    }

    /// PRD Undo row: undo after auto-advance returns to the photo whose mark was undone.
    @Test func undoAfterAutoAdvanceReturnsTheMarkedPhoto() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B"])
        defer { fixture.remove() }
        let marked = fixture.photoSets[0]
        let next = fixture.photoSets[1]
        // The detail view moved on after the mark; the plan keeps the photo it marked.
        let plan = AutoAdvancePlan(target: .nextPhoto(next.id), markedPhoto: marked.id)
        #expect(plan.advances)

        await fixture.record(
            .rating(undoRating(4)), on: marked.id, photoToReturnTo: plan.markedPhoto)
        #expect(await fixture.history.nextUndo?.photoToReturnTo == plan.markedPhoto)

        let result = try #require(await undoStep(fixture))
        #expect(result.photoToReturnTo == marked.id)
        #expect(result.photoToReturnTo != next.id)
    }
}
