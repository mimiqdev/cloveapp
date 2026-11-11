import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct PhotoActionsTests {
    private func finishingPlan(
        group: BrowsingGroup, model: BrowsingModel, library: ControlledPhotoLibrary
    ) -> GroupFinishingPlan {
        let protected = library.identity("c")
        model.apply(.label(ColourLabel(colour: .blue)), to: protected)
        return GroupFinishingPlan(
            group: BrowsingGroup(id: group.id, members: group.members + [protected]),
            action: .rejectUnmarked, currentPhoto: group.members[0],
            marks: Dictionary(uniqueKeysWithValues: model.allPlacedPhotos.map { ($0.id, $0.marks) })
        )
    }

    @Test func queuedMoveCannotConsumeALaterReject() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        library.heldPhoto = a
        model.apply(.rating(try #require(Rating(rawValue: 2))), to: a)
        try await waitUntil { library.writing == a }
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: []) { _ in }
        model.apply(.rating(.rejected), to: b)
        #expect(model.shownMarks(for: b).isRejected)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(library.moves == [[c]])
        #expect(library.events == ["write:a", "move:c", "write:b"])
        #expect(model.photos.contains { $0.id == b && $0.marks.isRejected })
        try await waitUntil { model.latestChange(for: b)?.state.isConfirmed == true }
    }

    @Test func laterEditKeepsItsPhotoOutOfAnEarlierMove() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let c = library.identity("c")
        library.heldPhoto = a
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        try await waitUntil { library.writing == a }
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: []) { _ in }
        model.apply(.label(ColourLabel(colour: .blue)), to: c)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(library.moves == [[]])
        #expect(model.photos.contains { $0.id == c && $0.marks.label.colour == .blue })
        try await waitUntil { model.latestChange(for: c)?.state.isConfirmed == true }
    }

    @Test func resumeWaitsForDepartureAndAcceptsNewMarks() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.heldPhoto = a
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        try await waitUntil { library.writing == a }
        model.back()
        #expect(model.leaveConfirmation.unfinishedCount == 1)
        let leave = Task { await model.leaveAnyway() }
        try await waitUntil { model.state.route == .entry && model.state.folder == nil }
        let recent = try #require(library.recents.first)
        let resume = Task { await model.resume(recent) }
        library.heldPhoto = nil
        await leave.value
        await resume.value
        #expect(library.closeCount == 1)
        #expect(library.reopenCount == 1)
        #expect(!library.isClosed)
        #expect(model.state.folder == library.folder)
        let three = try #require(Rating(rawValue: 3))
        model.apply(.rating(three), to: b)
        #expect(model.shownMarks(for: b).rating == three)
        await model.drainActions()
        try await waitUntil { model.latestChange(for: b)?.state.isConfirmed == true }
    }

    @Test func failedKeepRetryThroughConsumerPreservesLaterFourStars() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let kept = library.identity("a")
        library.failNext.insert(kept)
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: [kept]) { _ in }
        await model.drainActions()
        #expect(model.shownMarks(for: kept).rating == .unrated)
        #expect(model.latestChange(for: kept)?.state.failure != nil)
        let completed = try #require(model.lastRejectMove)
        let four = try #require(Rating(rawValue: 4))
        model.apply(.rating(four), to: kept)
        await model.drainActions()
        model.retryRejectMove(completed) { _ in }
        await model.drainActions()
        #expect(model.shownMarks(for: kept).rating == four)
        #expect(model.lastRejectMove?.result.noLongerRejectedCount == 1)
        #expect(library.photos.first { $0.id == kept }?.marks.rating == four)
    }

    @Test func moveUndoThroughConsumerReportsKeptPhotoChangedSince() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let kept = library.identity("a")
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: [kept]) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        let three = try #require(Rating(rawValue: 3))
        model.apply(.rating(three), to: kept)
        await model.drainActions()
        let set = try #require(library.scannedSet(for: kept))
        model.submitMoveUndo(
            RejectMoveUndoEntry(
                batch: completed.id,
                keptPhotos: [RejectMoveKeptPhoto(set: set, marksAfter: PhotoMarks())],
                photoToReturnTo: kept))
        await model.drainActions()
        let outcome = try #require(model.lastMoveUndo)
        let result = try outcome.get()
        #expect(result.changedSince == [kept])
        #expect(model.shownMarks(for: kept).rating == three)
    }

    @Test func retryingALaterMarkDoesNotFinishTheGroupAgain() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        let group = BrowsingGroup(id: GroupID(rawValue: "group"), members: [a, b])
        model.openGroup(group)
        model.runGroupFinishing(finishingPlan(group: group, model: model, library: library))
        await model.drainActions()
        let finished = try #require(model.lastGroupFinishing)
        let runs = model.groupFinishingRuns
        model.back()
        model.openGroup(group)
        library.failNext.insert(a)
        model.apply(.rating(try #require(Rating(rawValue: 4))), to: a)
        await model.drainActions()
        model.retryAllUnfinishedChanges()
        await model.drainActions()
        try await waitUntil { model.latestChange(for: a)?.state.isConfirmed == true }
        #expect(model.lastGroupFinishing == finished)
        #expect(model.groupFinishingRuns == runs)
        #expect(model.state.route == .group)
        #expect(model.state.groupPosition?.group == group.id)
    }

    @Test func onlyRetriesOfUnfinishedGroupPhotosUpdateFinishingState() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        let group = BrowsingGroup(id: GroupID(rawValue: "group"), members: [a, b])
        library.failNext.insert(a)
        model.runGroupFinishing(finishingPlan(group: group, model: model, library: library))
        await model.drainActions()
        let finished = try #require(model.lastGroupFinishing)
        let runs = model.groupFinishingRuns
        library.failNext.insert(c)
        model.apply(.label(ColourLabel(colour: .red)), to: c)
        await model.drainActions()
        model.retryFailedChange(for: c)
        await model.drainActions()
        #expect(model.lastGroupFinishing == finished)
        #expect(model.groupFinishingRuns == runs)
        model.retryFailedChange(for: a)
        await model.drainActions()
        #expect(model.groupFinishingRuns == runs + 1)
        #expect(model.lastGroupFinishing?.failedCount == 0)
        #expect(model.lastGroupFinishing?.savedCount == 2)
    }

    @Test func rowRetryResendsOnlyItsPhoto() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.failNext = [a, b]
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        model.apply(.label(ColourLabel(colour: .blue)), to: b)
        await model.drainActions()
        let writes = library.events.count
        model.retryFailedChange(for: a)
        await model.drainActions()
        try await waitUntil { model.latestChange(for: a)?.state.isConfirmed == true }
        #expect(Array(library.events.dropFirst(writes)) == ["write:a"])
        #expect(model.latestChange(for: b)?.state.failure != nil)
        #expect(model.shownMarks(for: b).label.colour == .blue)
    }

    @Test func rowRetryKeepsTheSameCompareAndSetRule() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.failNext.insert(a)
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        await model.drainActions()
        library.heldPhoto = b
        model.apply(.label(ColourLabel(colour: .blue)), to: b)
        try await waitUntil { library.writing == b }
        let writes = library.events.count
        model.retryFailedChange(for: a)
        let four = try #require(Rating(rawValue: 4))
        model.apply(.rating(four), to: a)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(Array(library.events.dropFirst(writes)) == ["write:b", "write:a"])
        #expect(model.shownMarks(for: a).rating == four)
        try await waitUntil { model.latestChange(for: a)?.state.isConfirmed == true }
    }

    @Test func aReopenRefusesNewMarksUntilItsGenerationIsInstalled() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let four = try #require(Rating(rawValue: 4))
        library.holdsReopen = true
        let reopen = Task { await model.reopenOpenFolder() }
        try await waitUntil { library.isReopening }
        #expect(model.isChangingFolder)
        model.apply(.rating(four), to: a)
        #expect(model.shownMarks(for: a).rating == .unrated)
        #expect(model.lastMarkEdits.isEmpty)
        library.holdsReopen = false
        await reopen.value
        #expect(!model.isChangingFolder)
        #expect(model.shownMarks(for: a).rating == .unrated)
        model.apply(.rating(four), to: a)
        #expect(model.shownMarks(for: a).rating == four)
        await model.drainActions()
        try await waitUntil { model.latestChange(for: a)?.state.isConfirmed == true }
    }

    @Test func shownPhotoCacheTracksConfirmationAndReindexesAfterAMove() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let b = library.identity("b")
        let c = library.identity("c")
        model.openPhoto(b)
        model.apply(.label(ColourLabel(colour: .red)), to: b)
        #expect(model.currentPhoto?.marks.label.colour == .red)
        await model.drainActions()
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: []) { _ in }
        await model.drainActions()
        #expect(library.photos.map(\.id) == [b, c])
        let five = try #require(Rating(rawValue: 5))
        model.apply(.rating(five), to: b)
        #expect(
            model.currentPhoto?.marks == PhotoMarks(rating: five, label: ColourLabel(colour: .red)))
        #expect(model.shownMarks(for: c).rating == .unrated)
        await model.drainActions()
        #expect(library.photos.first { $0.id == b }?.marks.rating == five)
        #expect(model.photos.first { $0.id == b }?.marks.rating == five)
    }

    @Test func supersededFinishingFailureDoesNotBlockCompletionOrRetry() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.failNext.insert(a)
        let group = BrowsingGroup(id: GroupID(rawValue: "group"), members: [a, b])
        let plan = finishingPlan(group: group, model: model, library: library)
        model.runGroupFinishing(plan)
        await model.drainActions()
        #expect(model.groupFinishingFailure?.failedCount == 1)
        model.apply(.rating(try #require(Rating(rawValue: 4))), to: a)
        await model.drainActions()
        try await waitUntil { model.groupFinishingFailure == nil }
        let writes = library.events.count
        model.retryGroupFinishing()
        await model.drainActions()
        #expect(model.groupFinishingFailure == nil)
        #expect(library.events.count == writes)
    }

    @Test func confirmedFinishingDoesNotRegressWhileItsStatusStreamIsPending() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.withholdsFinalStatuses = true
        let a = library.identity("a")
        let b = library.identity("b")
        let group = BrowsingGroup(id: GroupID(rawValue: "group"), members: [a, b])
        model.runGroupFinishing(finishingPlan(group: group, model: model, library: library))
        await model.drainActions()
        try await waitUntil { model.latestChange(for: a)?.state == .pending }
        #expect(model.lastGroupFinishing?.savedCount == 2)
        #expect(model.groupFinishingFailure == nil)
    }

    @Test func moveUndoFoldsTheCompleteConfirmedDesiredMarks() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        library.failNext.insert(a)
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        await model.drainActions()
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        library.failNext.insert(a)
        model.runRejectMove(preview, kept: [a]) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        let set = try #require(library.scannedSet(for: a))
        let expected = PhotoMarks(label: ColourLabel(colour: .red))
        model.submitMoveUndo(
            RejectMoveUndoEntry(
                batch: completed.id,
                keptPhotos: [RejectMoveKeptPhoto(set: set, marksAfter: expected)],
                photoToReturnTo: a))
        await model.drainActions()
        try await waitUntil { model.latestChange(for: a)?.state.isConfirmed == true }
        #expect(
            model.shownMarks(for: a)
                == PhotoMarks(rating: .rejected, label: ColourLabel(colour: .red)))
        #expect(library.photos.first { $0.id == a }?.marks.label.colour == .red)
        #expect(library.writtenMarks[a]?.label.colour == .red)
    }

    @Test func moveDetailsDoesNotRepeatAClearAlreadyRecoveredByTheGlyph() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let kept = library.identity("a")
        library.failNext.insert(kept)
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: [kept]) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        model.retryAllUnfinishedChanges()
        await model.drainActions()
        try await waitUntil { model.latestChange(for: kept)?.state.isConfirmed == true }
        let writes = library.events.count
        library.failNext.insert(kept)
        model.retryRejectMove(completed) { _ in }
        await model.drainActions()
        #expect(library.events.count == writes)
        #expect(library.failNext.contains(kept))
        #expect(model.lastRejectMove?.result.failedCount == 0)
        #expect(model.latestChange(for: kept)?.state.isConfirmed == true)
        #expect(!model.isSaveFailureToastVisible)
    }

    @Test func moveDetailsRetriesTheCurrentFailedRevision() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let kept = library.identity("a")
        library.failNext.insert(kept)
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: [kept]) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        model.apply(.rating(try #require(Rating(rawValue: 4))), to: kept)
        await model.drainActions()
        library.failNext.insert(kept)
        model.apply(.rating(.unrated), to: kept)
        await model.drainActions()
        #expect(model.latestChange(for: kept)?.state.failure != nil)
        model.retryRejectMove(completed) { _ in }
        await model.drainActions()
        try await waitUntil { model.latestChange(for: kept)?.state.isConfirmed == true }
        #expect(model.shownMarks(for: kept).rating == .unrated)
        #expect(model.lastRejectMove?.result.failedCount == 0)
    }

    @Test func saveFailuresShareOneToastUntilItHidesAndRetryResendsAll() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        model.toggleSelection(a)
        model.toggleSelection(b)
        library.failNext = [a, b]
        model.applyBatch(.rating(try #require(Rating(rawValue: 3))), settings: AppSettings())
        await model.drainActions()
        #expect(model.isSaveFailureToastVisible)
        #expect(model.saveFailureToastBurst == 1)
        library.failNext.insert(c)
        model.apply(.label(ColourLabel(colour: .red)), to: c)
        await model.drainActions()
        #expect(model.saveFailureToastBurst == 1)
        model.dismissSaveFailureToast()
        library.failNext.insert(a)
        model.apply(.label(ColourLabel(colour: .blue)), to: a)
        await model.drainActions()
        #expect(model.saveFailureToastBurst == 2)
        model.recordRejectMove(
            RejectMoveResult(id: RejectMoveBatchID(), outcomes: []), keptIdentities: [],
            rejectsFolderName: .defaultFolderName, folder: library.folder, openGeneration: 0)
        #expect(!model.isSaveFailureToastVisible)
        #expect(model.isRejectMoveToastVisible)
        library.failNext.insert(b)
        model.apply(.label(ColourLabel(colour: .green)), to: b)
        await model.drainActions()
        #expect(model.saveFailureToastBurst == 3)
        #expect(!model.isRejectMoveToastVisible)
        let writes = library.events.count
        model.retryAllUnfinishedChanges()
        await model.drainActions()
        try await waitUntil { model.unsavedChanges.isEmpty }
        #expect(library.events.count == writes + 3)
        #expect(!model.isSaveFailureToastVisible)
    }

    @Test func failureAfterTheFailedCountReturnsToZeroStartsANewBurst() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        library.failNext.insert(photo)
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        await model.drainActions()
        #expect(model.saveFailureToastBurst == 1)
        library.failNext.insert(photo)
        model.apply(.label(ColourLabel(colour: .blue)), to: photo)
        await model.drainActions()
        #expect(model.saveFailureToastBurst == 2)
        #expect(model.isSaveFailureToastVisible)
    }

    @Test func saveToastIsSuppressedForLostAccessAndDriveLoss() async throws {
        for reason in [MarkWriteFailureReason.permissionLost, .locationUnavailable] {
            let library = ControlledPhotoLibrary()
            let model = BrowsingModel(library: library)
            model.openFolder()
            let photo = library.identity("a")
            library.failureReason = reason
            library.failNext.insert(photo)
            model.apply(.label(ColourLabel(colour: .red)), to: photo)
            await model.drainActions()
            #expect(!model.isSaveFailureToastVisible)
            #expect(model.shownMarks(for: photo).label.colour == .red)
        }
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.reportDriveLoss()
        try await waitUntil { model.folderLocationLoss != nil }
        let photo = library.identity("a")
        library.failNext.insert(photo)
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        await model.drainActions()
        #expect(!model.isSaveFailureToastVisible)
        #expect(model.shownMarks(for: photo).label.colour == .red)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TestWaitFailure()
    }
}

private struct TestWaitFailure: Error {}

/// A bounded, controllable storage seam. Tests drive the real BrowsingModel consumer above it.
@MainActor
private final class ControlledPhotoLibrary: FolderLibrary {
    let folder: FolderIdentity
    private let recentID: UUID
    var photos: [GridPhoto] = []
    let groups: [BrowsingGroup] = []
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation
    private var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
    private var closedPhotos: [GridPhoto] = []
    private var movedPhotos: [RejectMoveBatchID: [GridPhoto]] = [:]
    var openGeneration = 0
    var isClosed = false
    var closeCount = 0
    var reopenCount = 0
    var heldPhoto: PhotoIdentity?
    var writing: PhotoIdentity?
    var failNext: Set<PhotoIdentity> = []
    var failureReason: MarkWriteFailureReason = .notConfirmed
    var withholdsFinalStatuses = false
    var holdsReopen = false
    var isReopening = false
    var events: [String] = []
    var moves: [[PhotoIdentity]] = []
    var writtenMarks: [PhotoIdentity: PhotoMarks] = [:]

    init(rejected: Set<String> = ["c"]) {
        recentID = UUID()
        folder = FolderIdentity(rawValue: recentID.uuidString)
        (updates, continuation) = AsyncStream.makeStream()
        photos = ["a", "b", "c"].map { stem in
            GridPhoto(
                id: identity(stem), fileName: "\(stem).ARW", time: .unavailable,
                marks: PhotoMarks(rating: rejected.contains(stem) ? .rejected : .unrated))
        }
    }

    var recents: [RecentFolder] {
        [RecentFolder(id: recentID, bookmark: Data(), pathSummary: "/Library", lastOpened: Date())]
    }

    func identity(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem)
    }

    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { statuses[photo] }

    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        var outcomes: [MarkChangeStatus] = []
        for item in items {
            let id = MarkChangeID()
            continuation.yield(
                .change(
                    MarkChangeStatus(
                        id: id, identity: item.photo, requested: item.change, state: .pending)))
            writing = item.photo
            for _ in 0..<1000 {
                if heldPhoto != item.photo { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            events.append("write:\(item.photo.stem)")
            let fails = heldPhoto == item.photo || failNext.remove(item.photo) != nil
            let state: MarkChangeState =
                fails
                ? .failed(MarkWriteFailure(reason: failureReason, message: "Controlled failure"))
                : .savedInSidecar
            if !fails, let index = photos.firstIndex(where: { $0.id == item.photo }) {
                let carried = statuses[item.photo].flatMap {
                    $0.state.failure != nil ? $0.requested : nil
                }
                let effective = MarkChange(
                    rating: item.change.rating ?? carried?.rating,
                    label: item.change.label ?? carried?.label)
                writtenMarks[item.photo] = (writtenMarks[item.photo] ?? photos[index].marks)
                    .applying(effective)
                photos[index].marks = photos[index].marks.applying(item.change)
            }
            let status = MarkChangeStatus(
                id: id, identity: item.photo, requested: item.change, state: state)
            statuses[item.photo] = status
            outcomes.append(status)
            if !withholdsFinalStatuses { continuation.yield(.change(status)) }
        }
        writing = nil
        continuation.yield(.photos(photos))
        return MarkBatchResult(
            id: MarkBatchID(), change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }

    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? {
        guard
            let set = try? PhotoSet(
                folderID: folder, relativeFolderPath: "",
                rawURL: URL(fileURLWithPath: "/Library/\(photo.stem).ARW"))
        else { return nil }
        return ScannedPhotoSet(photoSet: set, sidecar: .absent, imageFiles: [])
    }

    func planRejectMove(
        configuration: RejectMoveConfiguration, rejected: [PhotoIdentity]
    ) async throws -> RejectMovePlan {
        let root = URL(fileURLWithPath: "/Library")
        let destination = root.appendingPathComponent("_Rejected")
        let sets = rejected.compactMap { scannedSet(for: $0) }
        return RejectMovePlan(
            rootURL: root, configuration: configuration, sets: sets,
            entries: sets.map { set in
                .ready(
                    RejectMoveSetPlan(
                        identity: set.id, relativeFolderPath: "", destinationFolder: destination,
                        files: [
                            RejectMoveFilePlan(
                                role: .primary, source: set.photoSet.primary.url,
                                destination: destination.appendingPathComponent(
                                    set.photoSet.primary.url.lastPathComponent))
                        ]))
            }, destinationURL: destination)
    }

    func runRejectMove(_ plan: RejectMovePlan) async throws -> RejectMoveResult {
        let ids = plan.readyEntries.map(\.identity)
        moves.append(ids)
        events.append("move:" + ids.map(\.stem).joined(separator: ","))
        let result = RejectMoveResult(
            id: RejectMoveBatchID(),
            outcomes: plan.readyEntries.map {
                .moved(
                    RejectMoveMovedSet(
                        identity: $0.identity, files: $0.files, removedStoredReject: false,
                        staleRejectRecord: nil))
            })
        movedPhotos[result.id] = photos.filter { ids.contains($0.id) }
        photos.removeAll { ids.contains($0.id) }
        continuation.yield(.photos(photos))
        return result
    }

    func undoRejectMove(
        _ entry: RejectMoveUndoEntry, currentMarks: [PhotoIdentity: PhotoMarks],
        restoring edits: [DesiredMarkEdit]
    ) async throws -> RejectMoveUndoResult {
        var outcomes: [RejectMoveUndoOutcome] = []
        for photo in movedPhotos.removeValue(forKey: entry.batch) ?? [] {
            photos.append(photo)
            guard let set = scannedSet(for: photo.id) else { continue }
            _ = await apply([BatchMarkItem(photo: photo.id, change: .rating(.rejected))])
            outcomes.append(
                .restored(
                    RejectMoveUndoRestoredPhoto(
                        identity: photo.id, set: set, files: [], keptInConfirmation: false,
                        rejectStoreFailure: nil)))
        }
        for kept in entry.keptPhotos {
            guard currentMarks[kept.set.id] == kept.marksAfter else {
                outcomes.append(.changedSince(kept.set.id))
                continue
            }
            _ = await apply([BatchMarkItem(photo: kept.set.id, change: .rating(.rejected))])
            outcomes.append(
                .restored(
                    RejectMoveUndoRestoredPhoto(
                        identity: kept.set.id, set: kept.set, files: [], keptInConfirmation: true,
                        rejectStoreFailure: nil)))
        }
        let restored = Set(
            outcomes.compactMap { outcome -> PhotoIdentity? in
                guard case .restored(let photo) = outcome else { return nil }
                return photo.identity
            })
        for edit in edits where restored.contains(edit.photo) {
            if let index = photos.firstIndex(where: { $0.id == edit.photo }) {
                photos[index].marks = edit.after
            }
        }
        continuation.yield(.photos(photos))
        return RejectMoveUndoResult(id: RejectMoveUndoBatchID(), outcomes: outcomes)
    }

    func reportDriveLoss() {
        continuation.yield(
            .locationLost(
                folder: folder,
                loss: FolderLocationLoss(reason: .externalVolumeDisconnected, date: Date()),
                generation: openGeneration))
    }

    func closeFolder() async {
        closeCount += 1
        closedPhotos = photos
        photos = []
        statuses = [:]
        isClosed = true
        openGeneration += 1
        continuation.yield(.photos([]))
    }

    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        reopenCount += 1
        isReopening = true
        defer { isReopening = false }
        for _ in 0..<1000 {
            if !holdsReopen { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard !holdsReopen else {
            return .locationUnavailable(FolderErrorChain(CocoaError(.fileReadUnknown)))
        }
        if isClosed { photos = closedPhotos }
        statuses = [:]
        isClosed = false
        openGeneration += 1
        continuation.yield(.photos(photos))
        return nil
    }
}
