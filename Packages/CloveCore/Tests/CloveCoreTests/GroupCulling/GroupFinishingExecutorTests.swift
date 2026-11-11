import Foundation
import Testing

@testable import CloveCore

/// Reads one packet's marks through the codec, independent of the queue's confirmation.
private func groupCullingSidecarMarks(at url: URL) throws -> XMPMarks {
    try XMPCodec().read(try Data(contentsOf: url))
}

/// PRD In-group culling, finishing actions, PRD P0-09 and PRD P0-12: plans through the queue.
@Suite("Group finishing execution")
struct GroupFinishingExecutorTests {
    /// Three RAW sets in one test folder, in group member order.
    private func makeSets(_ folder: WriteTestFolder) throws -> [ScannedPhotoSet] {
        let identity = makeFolderIdentity()
        return try ["A", "B", "C"].map {
            try makeScannedSet(folder: identity, root: folder.url, stem: $0)
        }
    }

    /// The marks snapshot the executor reads, before any test writes a newer mark.
    private func makeSource(_ marks: [PhotoIdentity: PhotoMarks]) -> GroupCullingMarksSource {
        GroupCullingMarksSource(marks)
    }

    @Test func keepThisWritesTheRatingAndStoresTheRejects() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let completion = GroupCompletionTracker()
        let executor = GroupFinishingExecutor(queue: queue, completion: completion)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("keep", members: members)
        let marks = makeSource([:])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await marks.marks(for: $0) })

        #expect(result.outcomes.count == 3)
        #expect(result.savedCount == 3)
        #expect(result.failedCount == 0)
        #expect(result.droppedPhotos.isEmpty)
        #expect(result.partialFailureSummary == nil)
        // PRD In-group culling: the kept photo gets the lowest enabled rating, in XMP.
        #expect(
            try groupCullingSidecarMarks(at: folder.file("A.xmp")).rating
                == .rated(groupCullingRating(2)))
        // PRD P0-12: every other unmarked photo is rejected as −1 in its own sidecar, so a RAW
        // set's marks go to one storage only (decision record `reject-as-rating.md`).
        #expect(try groupCullingSidecarMarks(at: folder.file("B.xmp")).rating == .rated(.rejected))
        #expect(try groupCullingSidecarMarks(at: folder.file("C.xmp")).rating == .rated(.rejected))
        #expect(try folder.stagingNames().isEmpty)
        // A RAW set's marks never reach Clove storage, so there is no store folder to check.
        #expect(await completion.hasFinishingAction(on: group.id))
        #expect(await completion.isComplete(group, marks: [:]))

        // DEV-PLAN C5: the undo record holds each marks value from before the action.
        #expect(result.undo.groupID == group.id)
        #expect(result.undo.action == .keepThis)
        #expect(result.undo.photoToReturnTo == members[0])
        #expect(result.undo.entries.map(\.photo) == members)
        #expect(result.undo.entries[0].marksBefore == PhotoMarks())
        #expect(result.undo.entries[0].change == MarkChange(rating: groupCullingRating(2)))
        #expect(result.undo.entries[1].change == MarkChange(rating: .rejected))
    }

    @Test func anEmptyPlanWritesNothingAndStillCompletesTheGroup() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let completion = GroupCompletionTracker()
        let executor = GroupFinishingExecutor(queue: queue, completion: completion)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("empty", members: members)
        let snapshot = groupCullingMarks([
            (members[0], PhotoMarks(rating: groupCullingRating(4))),
            (members[1], PhotoMarks(label: ColourLabel(colour: .red))),
            (members[2], PhotoMarks(label: ColourLabel(colour: .green))),
        ])
        let source = makeSource(snapshot)
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: snapshot,
            enabledRatings: groupCullingTwoAndFour)
        #expect(plan.isEmpty)

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        #expect(result.outcomes.isEmpty)
        #expect(result.savedCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.undo.entries.isEmpty)
        #expect(result.undo.photoToReturnTo == members[0])
        #expect(double.allRecords.isEmpty)
        // The action ran, so the group counts as finished even with nothing to write.
        #expect(await completion.isComplete(group, marks: [:]))
    }

    @Test func keepThisWithTheCurrentPhotoOutsideTheGroupWritesNothing() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let completion = GroupCompletionTracker()
        let executor = GroupFinishingExecutor(queue: queue, completion: completion)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("outside", members: members)
        let source = makeSource([:])
        let outsider = groupCullingPhoto("outsider")
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: outsider,
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        // After a C9 refinement (PRD P0-11) the viewed photo can be outside the group; Keep
        // this must not reject the whole group with nothing kept (PRD P0-12).
        #expect(result.plan.availability == .currentPhotoNotInGroup)
        #expect(result.outcomes.isEmpty)
        #expect(result.droppedPhotos.isEmpty)
        #expect(result.savedCount == 0)
        #expect(result.undo.entries.isEmpty)
        #expect(result.undo.photoToReturnTo == outsider)
        #expect(double.allRecords.isEmpty)
        // The action did not run, so it records no completion (PRD In-group culling).
        #expect(!(await completion.hasFinishingAction(on: group.id)))
        #expect(!(await completion.isComplete(group, marks: [:])))
    }

    @Test func aPartialFailureReportsCountsAndRetriesOnlyTheFailedItems() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let completion = GroupCompletionTracker()
        let executor = GroupFinishingExecutor(queue: queue, completion: completion)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("partial", members: members)
        let source = makeSource([:])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)
        let keptSidecar = folder.file("A.xmp")
        double.fail(.replace, at: keptSidecar, with: POSIXError(.ENOSPC))
        let storeDirectory = folder.file("store")
        func storeWrites() -> Int {
            double.allRecords.filter {
                $0.step == .replace && $0.url.path.hasPrefix(storeDirectory.path)
            }.count
        }

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        // PRD Failure and recovery, "Partial batch failure": the rejects were confirmed and
        // the kept photo's rating was not.
        #expect(result.outcomes.count == 3)
        #expect(result.savedCount == 2)
        #expect(result.failedCount == 1)
        #expect(
            result.partialFailureSummary
                == "Saved 2 photos. 1 photos couldn't be saved.")
        #expect(result.undo.entries.count == 3)
        let keptOutcome = try #require(result.outcomes.first)
        #expect(keptOutcome.change.photo == members[0])
        #expect(keptOutcome.status.state.failure?.reason == .insufficientSpace)
        #expect(!FileManager.default.fileExists(atPath: keptSidecar.path))
        // PRD In-group culling, group completion: the action ran, so the group stays complete
        // even though one write failed.
        #expect(await completion.isComplete(group, marks: [:]))
        let writesBeforeRetry = storeWrites()

        double.stopFailing(.replace)
        let retried = await executor.retryFailed(in: result)

        // PRD P0-09: retry failed items only, so the saved rejects are not written again.
        #expect(retried.savedCount == 3)
        #expect(retried.failedCount == 0)
        #expect(retried.partialFailureSummary == nil)
        #expect(storeWrites() == writesBeforeRetry)
        #expect(
            try groupCullingSidecarMarks(at: keptSidecar).rating
                == .rated(groupCullingRating(2)))
        #expect(retried.undo == result.undo)
    }

    @Test func aPhotoMarkedAfterThePlanIsNotRejected() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let queue = MarkWriteQueue(
            storeDirectory: folder.file("store"), fileSystem: WriteFileSystemDouble())
        let executor = GroupFinishingExecutor(queue: queue)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("recheck", members: members)
        let source = makeSource([:])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)
        // Between planning and execution, another window rates B and labels C.
        await source.set(PhotoMarks(rating: groupCullingRating(3)), for: members[1])
        await source.set(PhotoMarks(label: ColourLabel(colour: .purple)), for: members[2])

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        // PRD P0-12: a photo rated or labelled after the plan is never rejected.
        #expect(result.droppedPhotos == [members[1], members[2]])
        #expect(result.outcomes.map(\.photo) == [members[0]])
        #expect(result.savedCount == 1)
        let storedB = try await queue.storedMarks(for: members[1])
        let storedC = try await queue.storedMarks(for: members[2])
        #expect(storedB == nil)
        #expect(storedC == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.file("B.xmp").path))
        #expect(!FileManager.default.fileExists(atPath: folder.file("C.xmp").path))
    }

    /// A rating that is still being written already counts as marked, so the executor never
    /// rejects that photo (PRD P0-12; PRD How marks reach disk, rule 8).
    ///
    /// Auto-advance can show the next photo of the group within the write's time, so the group view
    /// plans the next action while the rating is only requested. C4 keeps the request until a newer
    /// change replaces it, so the requested rating is what the re-check reads.
    @Test func aPhotoWithAPendingRatingIsNotRejected() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let executor = GroupFinishingExecutor(queue: queue)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("pending-rating", members: members)
        let source = makeSource([:])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)
        // B's rating is admitted and not saved yet; its requested marks are what the app holds.
        let pending = MarkChange(rating: groupCullingRating(3))
        await source.set(PhotoMarks().including(pending), for: members[1])

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        #expect(result.droppedPhotos == [members[1]])
        #expect(result.outcomes.map(\.photo) == [members[0], members[2]])
        #expect(!FileManager.default.fileExists(atPath: folder.file("B.xmp").path))
    }

    @Test func keepThisKeepsARatingWrittenAfterThePlan() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let double = WriteFileSystemDouble()
        let queue = MarkWriteQueue(storeDirectory: folder.file("store"), fileSystem: double)
        let executor = GroupFinishingExecutor(queue: queue)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("new-rating", members: members)
        let source = makeSource([:])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)
        await source.set(PhotoMarks(rating: groupCullingRating(5)), for: members[0])

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        // "Keep" means keep: the rating written after the plan is not lowered to the lowest
        // enabled level (PRD In-group culling, finishing actions).
        #expect(result.droppedPhotos == [members[0]])
        #expect(result.outcomes.map(\.photo) == [members[1], members[2]])
        #expect(double.count(of: .replace, at: folder.file("A.xmp")) == 0)
        #expect(!FileManager.default.fileExists(atPath: folder.file("A.xmp").path))
    }

    @Test func undoRecordsMarksBeforeAndTheChangeApplied() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let queue = MarkWriteQueue(
            storeDirectory: folder.file("store"), fileSystem: WriteFileSystemDouble())
        let executor = GroupFinishingExecutor(queue: queue)
        let sets = try makeSets(folder)
        let members = sets.map(\.id)
        let group = groupCullingGroup("undo", members: members)
        let source = makeSource(
            [
                members[0]: PhotoMarks(rating: .rejected),
                members[1]: PhotoMarks(label: ColourLabel(colour: .red)),
            ])
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepThis,
            currentPhoto: members[0],
            marks: [:],
            enabledRatings: groupCullingTwoAndFour)

        let result = await executor.execute(
            plan,
            photoSet: { identity in sets.first { $0.id == identity } },
            latestMarks: { await source.marks(for: $0) })

        // DEV-PLAN C5: marks before the action, the change applied, and where to return.
        #expect(result.undo.action == .keepThis)
        #expect(result.undo.photoToReturnTo == members[0])
        #expect(result.undo.entries.map(\.photo) == [members[0], members[2]])
        let kept = result.undo.entries[0]
        #expect(kept.marksBefore == PhotoMarks(rating: .rejected))
        #expect(kept.change == MarkChange(rating: groupCullingRating(2)))
        let rejected = result.undo.entries[1]
        #expect(rejected.marksBefore == PhotoMarks())
        #expect(rejected.change == MarkChange(rating: .rejected))
        // A labelled photo is untouched, so it has no undo entry.
        #expect(!result.undo.entries.contains { $0.photo == members[1] })
    }

    @Test func keepRatedLeavesMarkedPhotosAloneInALargeGroup() async throws {
        let folder = try WriteTestFolder()
        defer { folder.remove() }
        let queue = MarkWriteQueue(
            storeDirectory: folder.file("store"), fileSystem: WriteFileSystemDouble())
        let executor = GroupFinishingExecutor(queue: queue)
        let identity = makeFolderIdentity()
        let sets = try (0..<24).map {
            try makeScannedSet(
                folder: identity, root: folder.url,
                stem: String(format: "S%02d", $0))
        }
        let members = sets.map(\.id)
        let group = groupCullingGroup("large", members: members)
        var entries: [(PhotoIdentity, PhotoMarks)] = []
        for index in 0..<6 {
            entries.append((members[index], PhotoMarks(rating: groupCullingRating(3))))
        }
        for index in 6..<12 {
            entries.append((members[index], PhotoMarks(label: ColourLabel(colour: .green))))
        }
        for index in 12..<16 {
            entries.append((members[index], PhotoMarks(rating: .rejected)))
        }
        let source = makeSource(groupCullingMarks(entries))
        let plan = GroupFinishingPlan(
            group: group,
            action: .keepRated,
            currentPhoto: members[0],
            marks: groupCullingMarks(entries),
            enabledRatings: groupCullingTwoAndFour)

        let result = await executor.execute(
            plan,
            photoSet: { photo in sets.first { $0.id == photo } },
            latestMarks: { await source.marks(for: $0) })

        // PRD P0-12: Keep rated, reject the rest rejects only unmarked photos.
        #expect(result.outcomes.count == 8)
        #expect(result.outcomes.map(\.photo) == Array(members[16...]))
        for index in 0..<16 {
            let stored = try await queue.storedMarks(for: members[index])
            #expect(stored == nil, "a marked photo was rejected")
        }
        for index in 16..<24 {
            let set = try #require(sets.first { $0.id == members[index] })
            let url = try #require(
                set.sidecar.resolvedURL
                    ?? set.photoSet.primary.url.deletingPathExtension()
                    .appendingPathExtension("xmp"))
            #expect(
                try groupCullingSidecarMarks(at: url).rating == .rated(.rejected),
                "an unmarked photo was not rejected")
        }
        #expect(result.undo.photoToReturnTo == members[0])
    }
}
