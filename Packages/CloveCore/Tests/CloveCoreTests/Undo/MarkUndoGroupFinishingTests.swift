import Foundation
import Testing

@testable import CloveCore

/// PRD P0-12's finishing actions and DEV-PLAN C5: both can be undone, and completion follows.
@Suite("Undo of a finishing action")
struct MarkUndoGroupFinishingTests {
    /// Runs one finishing action through C10's executor and records it in the history.
    private func run(
        _ action: GroupFinishingAction,
        group: SimilarGroup,
        currentPhoto: PhotoIdentity,
        marks: [PhotoIdentity: PhotoMarks],
        fixture: UndoTestFixture,
        completion: GroupCompletionTracker
    ) async -> (result: GroupFinishingResult, entry: MarkUndoEntryID?) {
        let executor = GroupFinishingExecutor(queue: fixture.queue, completion: completion)
        let plan = GroupFinishingPlan(
            group: group,
            action: action,
            currentPhoto: currentPhoto,
            marks: marks,
            enabledRatings: EnabledRatings.all)
        let reader = fixture.reader
        let photoSets = fixture.photoSets
        let result = await executor.execute(
            plan,
            photoSet: { identity in photoSets.first { $0.id == identity } },
            latestMarks: { await reader.marks(for: $0) })
        let entry = await fixture.history.recordGroupFinishing(result.undo)
        return (result, entry)
    }

    /// Keep this, reject the rest: undo restores every photo and clears the group's completion.
    @Test func keepThisUndoRestoresEveryPhotoAndClearsCompletion() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let completion = fixture.completion
        let group = groupCullingGroup("keep", members: photos)

        let (result, entry) = await run(
            .keepThis, group: group, currentPhoto: photos[0], marks: [:],
            fixture: fixture, completion: completion)

        #expect(result.savedCount == 3)
        #expect(result.failedCount == 0)
        #expect(entry != nil)
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(await fixture.history.nextUndoActionName == "Keep this, reject the rest")

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.actionName == "Keep this, reject the rest")
        #expect(undoResult.photoToReturnTo == photos[0])
        #expect(undoResult.completion?.groupID == group.id)
        #expect(undoResult.completion?.state == .cleared)
        #expect(undoResult.savedCount == 3)
        #expect(await completion.hasFinishingAction(on: group.id) == false)
        // Every photo is back: no rating in A's sidecar, no stored Reject for B and C.
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(.unrated))
        #expect(try await fixture.queue.storedMarks(for: photos[1]) == nil)
        #expect(try await fixture.queue.storedMarks(for: photos[2]) == nil)

        let redoResult = try #require(await undoRedoStep(fixture))
        #expect(redoResult.completion?.state == .restored)
        #expect(await completion.hasFinishingAction(on: group.id))
        // Keep this gave the unrated current photo the lowest enabled rating (1).
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(undoRating(1)))
        #expect(try await fixture.queue.storedMarks(for: photos[1])?.isRejected == true)
        #expect(try await fixture.queue.storedMarks(for: photos[2])?.isRejected == true)
    }

    /// Keep rated, reject the rest: undo restores the rejects and redo restores completion.
    @Test func keepRatedUndoRestoresTheRejectsAndRedoRestoresCompletion() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        await undoSeedSidecar(PhotoMarks(rating: undoRating(4)), at: fixture.sidecar(0))
        let marks: [PhotoIdentity: PhotoMarks] = [photos[0]: PhotoMarks(rating: undoRating(4))]
        let completion = fixture.completion
        let group = groupCullingGroup("rated", members: photos)

        let (result, entry) = await run(
            .keepRated, group: group, currentPhoto: photos[0], marks: marks,
            fixture: fixture, completion: completion)

        #expect(result.savedCount == 2)
        #expect(entry != nil)
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(await fixture.history.nextUndoActionName == "Keep rated, reject the rest")

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.completion?.groupID == group.id)
        #expect(undoResult.completion?.state == .cleared)
        #expect(await completion.hasFinishingAction(on: group.id) == false)
        #expect(try await fixture.queue.storedMarks(for: photos[1]) == nil)
        #expect(try await fixture.queue.storedMarks(for: photos[2]) == nil)
        // The rated photo was not part of the action, so its rating never changed.
        #expect(try undoSidecarMarks(at: fixture.sidecar(0)).rating == .rated(undoRating(4)))

        let redoResult = try #require(await undoRedoStep(fixture))
        #expect(redoResult.completion?.state == .restored)
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(try await fixture.queue.storedMarks(for: photos[1])?.isRejected == true)
        #expect(try await fixture.queue.storedMarks(for: photos[2])?.isRejected == true)
    }

    /// Undoing a finishing action that restores nothing leaves the group completion alone.
    @Test func anUndoThatRestoresNothingLeavesTheCompletionAlone() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let completion = fixture.completion
        let group = groupCullingGroup("single", members: [set.id])

        let (result, entry) = await run(
            .keepThis, group: group, currentPhoto: set.id, marks: [:],
            fixture: fixture, completion: completion)
        #expect(result.savedCount == 1)
        #expect(entry != nil)
        #expect(await completion.hasFinishingAction(on: group.id))
        // Another app replaces the rating the action wrote, so the undo restores nothing.
        _ = await fixture.queue.apply(.rating(undoRating(3)), to: set)

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.droppedFromHistory)
        #expect(undoResult.completion == nil)
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.undoCount == 0)
        #expect(try undoSidecarMarks(at: fixture.sidecar()).rating == .rated(undoRating(3)))
    }

    /// Completion changes when a field already holds the target, even if none was written.
    @Test func aCompletionClearsWhenAFieldIsAlreadyAtTheTarget() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let completion = fixture.completion
        let group = groupCullingGroup("mixed", members: photos)

        let (result, _) = await run(
            .keepThis, group: group, currentPhoto: photos[0], marks: [:],
            fixture: fixture, completion: completion)
        #expect(result.savedCount == 2)
        // Another app puts the kept rating back to the target before the undo runs.
        _ = await fixture.queue.apply(.rating(.unrated), to: fixture.photoSets[0])

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.droppedFromHistory == false)
        #expect(undoResult.completion?.state == .cleared)
        #expect(await completion.hasFinishingAction(on: group.id) == false)
        #expect(await fixture.history.canRedo)
        let kept = try #require(undoResult.outcomes.first { $0.photo == photos[0] })
        #expect(kept.isAlreadyAtTarget)
        let rejected = try #require(undoResult.outcomes.first { $0.photo == photos[1] })
        #expect(rejected.isWritten)
    }

    /// Undoing a finishing action whose photos are gone leaves the completion alone too.
    @Test func aFinishingActionUndoWithUnavailablePhotosLeavesTheCompletionAlone() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let completion = fixture.completion
        let group = groupCullingGroup("unavailable", members: photos)

        let (result, _) = await run(
            .keepThis, group: group, currentPhoto: photos[0], marks: [:],
            fixture: fixture, completion: completion)
        #expect(result.savedCount == 2)
        // A rescan drops both photos, so neither the kept rating nor the reject can be restored.
        await fixture.sets.remove(photos[0])
        await fixture.sets.remove(photos[1])

        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.droppedFromHistory)
        #expect(undoResult.completion == nil)
        #expect(undoResult.outcomes.allSatisfy { $0.isNotUndone })
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(await fixture.history.canUndo == false)
        #expect(await fixture.history.undoCount == 0)
    }

    /// A redo that restores nothing leaves the cleared completion cleared.
    @Test func aRedoThatRestoresNothingLeavesTheCompletionCleared() async throws {
        let fixture = try UndoTestFixture()
        defer { fixture.remove() }
        let set = try #require(fixture.photoSets.first)
        let completion = fixture.completion
        let group = groupCullingGroup("single-redo", members: [set.id])

        let (result, _) = await run(
            .keepThis, group: group, currentPhoto: set.id, marks: [:],
            fixture: fixture, completion: completion)
        #expect(result.savedCount == 1)
        let undoResult = try #require(await undoStep(fixture))
        #expect(undoResult.completion?.state == .cleared)
        #expect(await completion.hasFinishingAction(on: group.id) == false)
        // Another app replaces the restored rating, so the redo cannot re-apply the change.
        _ = await fixture.queue.apply(.rating(undoRating(4)), to: set)

        let redoResult = try #require(await undoRedoStep(fixture))
        #expect(redoResult.droppedFromHistory)
        #expect(redoResult.completion == nil)
        #expect(await completion.hasFinishingAction(on: group.id) == false)
        #expect(await fixture.history.canRedo == false)
        #expect(await fixture.history.redoCount == 0)
    }

    /// An action that changes no marks records no entry, because there is no mark to restore.
    @Test func aFinishingActionThatChangesNothingRecordsNoEntry() async throws {
        let fixture = try UndoTestFixture(stems: ["A", "B", "C"])
        defer { fixture.remove() }
        let photos = fixture.photoSets.map(\.id)
        let marks = [
            photos[0]: PhotoMarks(rating: undoRating(3)),
            photos[1]: PhotoMarks(rating: undoRating(2)),
            photos[2]: PhotoMarks(rating: undoRating(1)),
        ]
        for (index, photo) in photos.enumerated() {
            if let photoMarks = marks[photo] {
                await undoSeedSidecar(photoMarks, at: fixture.sidecar(index))
            }
        }
        let completion = fixture.completion
        let group = groupCullingGroup("nothing", members: photos)

        let (result, entry) = await run(
            .keepThis, group: group, currentPhoto: photos[0], marks: marks,
            fixture: fixture, completion: completion)

        #expect(result.outcomes.isEmpty)
        #expect(result.undo.entries.isEmpty)
        #expect(entry == nil)
        #expect(await fixture.history.canUndo == false)
        // The action still ran, so its completion record stays for the group view (PRD P0-12).
        #expect(await completion.hasFinishingAction(on: group.id))
    }
}
