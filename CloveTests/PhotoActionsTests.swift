import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct PhotoActionsTests {
    private func labelledGroupScenario() -> (
        BrowsingModel, ControlledPhotoLibrary, GroupFinishingPlan
    ) {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b", "c", "d", "next"])
        let group = BrowsingGroup(
            id: GroupID(rawValue: "labelled-keep"),
            members: ["a", "b", "c", "d"].map { library.identity($0) })
        library.groups = [group]
        let model = BrowsingModel(library: library)
        model.openFolder()
        model.apply(.label(ColourLabel(colour: .green)), to: library.identity("a"))
        model.openPhoto(library.identity("b"))
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: library.identity("b"),
            marks: Dictionary(uniqueKeysWithValues: model.groupPhotos.map { ($0.id, $0.marks) }))
        return (model, library, plan)
    }

    @Test func aLabelledOnlyKeepFinishesInDetail() async {
        let (model, library, plan) = labelledGroupScenario()
        #expect(model.currentPhoto?.id == library.identity("b"))
        model.runGroupFinishing(plan)
        #expect(model.groupPhotos.allSatisfy { !$0.marks.isUnmarked })
        #expect(
            model.shownMarks(for: library.identity("a"))
                == PhotoMarks(label: ColourLabel(colour: .green)))
        #expect(model.state.route == .detail)
        #expect(model.state.currentPhoto == library.identity("b"))
        await model.drainActions()
        #expect(
            library.photos.first { $0.id == library.identity("a") }?.marks.label.colour == .green)
    }

    @Test func finishingUndoRestoresAllUnmarkedPhotosAndReturnsAfterAnAdvance() async {
        let (model, library, plan) = labelledGroupScenario()
        model.runGroupFinishing(plan)
        model.openPhoto(library.identity("next"))
        model.undoLastMark()
        #expect(model.currentPhoto?.id == library.identity("b"))
        #expect(
            model.groupPhotos.filter { $0.marks.isUnmarked }.map(\.id)
                == ["b", "c", "d"].map { library.identity($0) })
        #expect(model.shownMarks(for: library.identity("a")).label.colour == .green)
        #expect(!model.canUndoMark)
        await model.drainActions()
        #expect(library.photos.filter { $0.marks.isRejected }.isEmpty)
    }

    @Test func detailUndoRecordsTheActionAndABatchClearsTheWholeStep() async {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        model.openPhoto(photo)
        model.apply(.label(ColourLabel(colour: .blue)), to: photo)
        #expect(model.canUndoMark)
        model.openPhoto(library.identity("b"))
        model.undoLastMark()
        #expect(model.currentPhoto?.id == photo)
        #expect(model.shownMarks(for: photo).label.isClear)
        #expect(!model.canUndoMark)
        model.apply(.rating(.rejected), to: photo)
        #expect(model.canUndoMark)
        model.toggleSelection(photo)
        model.applyBatch(.rating(.unrated), settings: AppSettings())
        #expect(!model.canUndoMark)
        await model.drainActions()
    }

    @Test func aTapShowsImmediatelyAndTwoQuickMarksWriteInOrder() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        let three = try #require(Rating(rawValue: 3))
        library.heldPhoto = photo
        model.apply(.rating(three), to: photo)
        #expect(model.shownMarks(for: photo).rating == three)
        #expect(library.photos.first?.marks.rating == .unrated)
        try await waitUntil { library.writing == photo }
        model.apply(.label(ColourLabel(colour: .blue)), to: photo)
        #expect(model.shownMarks(for: photo).label.colour == .blue)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(
            library.writes.map(\.change) == [.rating(three), .label(ColourLabel(colour: .blue))])
        #expect(model.shownMarks(for: photo) == library.photos.first?.marks)
    }

    @Test func repeatedEqualEditsKeepTheNewestMarkWhileItsWriteWaits() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        let three = try #require(Rating(rawValue: 3))
        library.heldPhoto = photo
        model.apply(.rating(three), to: photo)
        try await waitUntil { library.writing == photo }
        model.apply(.rating(.unrated), to: photo)
        model.apply(.rating(three), to: photo)
        library.heldWriteNumber = 3
        library.heldPhoto = nil
        try await waitUntil { library.writes.count == 2 }
        #expect(library.photos.first?.marks.rating == .unrated)
        #expect(model.shownMarks(for: photo).rating == three)
        library.heldWriteNumber = nil
        await model.drainActions()
        #expect(model.shownMarks(for: photo).rating == three)
        #expect(
            library.writes.map(\.change) == [.rating(three), .rating(.unrated), .rating(three)])
    }

    @Test func aFailedWriteRereadsTheFileAndDoesNotCarryItsFieldsForward() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        let disk = PhotoMarks(rating: try #require(Rating(rawValue: 2)))
        library.failNext.insert(photo)
        library.rereadValues[photo] = disk
        model.apply(.label(ColourLabel(colour: .red)), to: photo)
        #expect(model.shownMarks(for: photo).label.colour == .red)
        await model.drainActions()
        #expect(library.rereads == [photo])
        #expect(model.shownMarks(for: photo) == disk)
        #expect(model.failureToastMessage == BrowsingModel.saveFailureToastMessage)
        #expect(BrowsingModel.saveFailureToastMessage == "Couldn't save the mark.")
        #expect(BrowsingModel.readFailureToastMessage == "Couldn't read some marks.")
        model.apply(.rating(.rejected), to: photo)
        await model.drainActions()
        #expect(library.writes.last?.change == .rating(.rejected))
        #expect(model.shownMarks(for: photo).label.isClear)
    }

    @Test func aBatchFailureShowsOneToastAndRestoresOnlyItsFailedPhoto() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        model.toggleSelection(a)
        model.toggleSelection(b)
        library.failNext = [a]
        let three = try #require(Rating(rawValue: 3))
        model.applyBatch(.rating(three), settings: AppSettings())
        await model.drainActions()
        #expect(model.shownMarks(for: a).rating == .unrated)
        #expect(model.shownMarks(for: b).rating == three)
        #expect(model.failureToastMessage == BrowsingModel.saveFailureToastMessage)
        #expect(model.failureToastBurst == 1)
        library.failNext = [a]
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        await model.drainActions()
        #expect(model.failureToastBurst == 1)
        model.dismissFailureToast()
        library.failNext = [a]
        model.apply(.label(ColourLabel(colour: .blue)), to: a)
        await model.drainActions()
        #expect(model.failureToastBurst == 2)
    }

    @Test func leavingWithAHeldWriteShowsEntryWithoutWaiting() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        library.heldPhoto = photo
        model.apply(.rating(.rejected), to: photo)
        try await waitUntil { library.writing == photo }
        model.back()
        #expect(model.state.route == .entry)
        #expect(model.state.folder == nil)
        #expect(library.closeCount == 0)
        library.heldPhoto = nil
        await model.drainActions()
        try await waitUntil { library.closeCount == 1 }
    }

    @Test func disconnectDropsPendingMarksAndStopsTheRemainingActions() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.heldPhoto = a
        model.apply(.rating(.rejected), to: a)
        try await waitUntil { library.writing == a }
        model.apply(.label(ColourLabel(colour: .blue)), to: b)
        library.reportDriveLoss()
        try await waitUntil { model.folderLocationLoss != nil }
        #expect(model.shownMarks(for: a) == PhotoMarks())
        #expect(model.shownMarks(for: b) == PhotoMarks())
        #expect(!model.canMark)
        library.failNext.insert(a)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(library.writes.map(\.photo) == [a])
        #expect(model.failureToastMessage == nil)
    }

    @Test func disconnectedSwipesCannotMarkOrAdvanceAndReopenUsesFreshDiskMarks() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = try #require(model.photos.first)
        model.openPhoto(photo.id)
        library.reportDriveLoss()
        try await waitUntil { model.folderLocationLoss != nil }
        var advances = 0
        let detail = markingView(model, photo: photo, advanced: { advances += 1 })
        detail.applyMarkingSwipe(.rating(travel: 100))
        detail.applyMarkingSwipe(.reject(travel: 100))
        #expect(!model.canMark)
        #expect(advances == 0)
        #expect(library.writes.isEmpty)
        library.reopenFailure = .locationUnavailable(FolderErrorChain(CocoaError(.fileNoSuchFile)))
        await model.reopenOpenFolder()
        #expect(!model.canMark)
        library.reopenFailure = nil
        let disk = PhotoMarks(rating: try #require(Rating(rawValue: 2)))
        library.rereadValues[photo.id] = disk
        await model.reopenOpenFolder()
        #expect(model.shownMarks(for: photo.id) == disk)
        #expect(model.canMark)
    }

    @Test func aSwipeDuringAMoveDoesNotMarkOrStartAutoAdvance() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = try #require(model.photos.first)
        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        library.holdsMove = true
        model.runRejectMove(plan, kept: []) { _ in }
        try await waitUntil { library.isRunningMove }
        model.openPhoto(photo.id)
        var advances = 0
        let detail = markingView(model, photo: photo, advanced: { advances += 1 })
        detail.applyMarkingSwipe(.rating(travel: 100))
        #expect(!model.canMark)
        #expect(advances == 0)
        library.holdsMove = false
        await model.drainActions()
        #expect(model.canMark)
    }

    @Test(arguments: [false, true])
    func disconnectLeavesARunningMoveToCompleteOnItsOwn(fails: Bool) async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        library.holdsMove = true
        library.failsMove = fails
        var results: [Result<RejectMoveResult, any Error>] = []
        model.runRejectMove(plan, kept: []) { results.append($0) }
        try await waitUntil { library.isRunningMove }
        defer { library.holdsMove = false }
        library.reportDriveLoss()
        try await waitUntil { model.folderLocationLoss != nil }
        #expect(results.isEmpty)
        library.holdsMove = false
        await model.drainActions()
        #expect(results.count == 1)
        if fails {
            if case .failure(let error) = results.first {
                #expect(error is PhotoActionMoveFailure)
            } else {
                Issue.record("The running move must report its own error")
            }
        } else {
            #expect(try results.first?.get().movedIdentities == [library.identity("c")])
            let completed = try #require(model.lastRejectMove)
            #expect(completed.canUndo)
            #expect(model.isRejectMoveToastVisible)
            #expect(!model.canUndoRejectMove(completed))
        }
    }

    @Test func disconnectFailsAQueuedMoveWithoutRunningIt() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = library.identity("a")
        library.heldPhoto = photo
        model.apply(.rating(.rejected), to: photo)
        try await waitUntil { library.writing == photo }
        defer { library.heldPhoto = nil }
        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        var results: [Result<RejectMoveResult, any Error>] = []
        model.runRejectMove(plan, kept: []) { results.append($0) }
        library.reportDriveLoss()
        try await waitUntil { !results.isEmpty }
        #expect(results.count == 1)
        if case .failure(let error) = results.first {
            #expect(error as? RejectMoveRefusal == .disabled)
        } else {
            Issue.record("The dropped move must fail")
        }
        library.heldPhoto = nil
        await model.drainActions()
        #expect(library.moves.isEmpty)
        #expect(results.count == 1)
    }

    @Test func queuedMoveCannotConsumeALaterRejectOrMoveAPhotoWithALaterEdit() async throws {
        let library = ControlledPhotoLibrary(rejected: ["b", "c"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        let b = library.identity("b")
        library.heldPhoto = a
        model.apply(.label(ColourLabel(colour: .red)), to: a)
        try await waitUntil { library.writing == a }
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: []) { _ in }
        model.apply(.rating(.rejected), to: a)
        model.apply(.label(ColourLabel(colour: .blue)), to: b)
        library.heldPhoto = nil
        await model.drainActions()
        #expect(library.moves == [[library.identity("c")]])
        #expect(model.shownMarks(for: a).isRejected)
        #expect(model.shownMarks(for: b).label.colour == .blue)
    }

    @Test func aFailedClearDoesNotHoldBackARejectedPhotoFromALaterMove() async throws {
        let library = ControlledPhotoLibrary(rejected: ["a"])
        let model = BrowsingModel(library: library)
        model.openFolder()
        let a = library.identity("a")
        library.failNext.insert(a)
        model.apply(.rating(.unrated), to: a)
        await model.drainActions()
        #expect(model.shownMarks(for: a).isRejected)
        let preview = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(preview, kept: []) { _ in }
        await model.drainActions()
        #expect(library.moves == [[a]])
    }

    @Test func toastUndoRestoresBothMovedAndKeptSamplePhotos() async throws {
        let model = BrowsingModel(library: TestLibrary.sample)
        model.openFolder()
        let rejected = model.allPlacedPhotos.filter(\.marks.isRejected).map(\.id)
        let kept = try #require(rejected.first)
        let moved = try #require(rejected.last)
        let plan = try await model.planRejectMove(configuration: RejectMoveConfiguration())
        model.runRejectMove(plan, kept: [kept]) { _ in }
        await model.drainActions()
        let completed = try #require(model.lastRejectMove)
        #expect(model.canUndoRejectMove(completed))
        #expect(model.shownMarks(for: kept).rating == .unrated)
        #expect(!model.photos.contains { $0.id == moved })
        model.undoRejectMove(completed)
        await model.drainActions()
        #expect(model.shownMarks(for: kept).isRejected)
        #expect(model.photos.contains { $0.id == moved && $0.marks.isRejected })
    }

    @Test func leavingAndResumingTheSampleReadsItsStoredMarks() async throws {
        let library = TestLibrary.sample
        let model = BrowsingModel(library: library)
        model.openFolder()
        let photo = try #require(model.photos.first?.id)
        let recent = try #require(library.recents.first)
        model.apply(.label(ColourLabel(colour: .blue)), to: photo)
        model.back()
        #expect(model.state.route == .entry)
        await model.resume(recent)
        #expect(model.hasFolderContents)
        #expect(model.shownMarks(for: photo).label.colour == .blue)
    }

    @Test func aReopenRefusesNewMarksUntilItsGenerationIsInstalled() async throws {
        let library = ControlledPhotoLibrary()
        let model = BrowsingModel(library: library)
        model.openFolder()
        library.holdsReopen = true
        let reopen = Task { await model.reopenOpenFolder() }
        try await waitUntil { library.isReopening }
        #expect(!model.canMark)
        model.apply(.rating(.rejected), to: library.identity("a"))
        #expect(library.writes.isEmpty)
        library.holdsReopen = false
        await reopen.value
        #expect(model.canMark)
    }

    private func markingView(
        _ model: BrowsingModel, photo: GridPhoto, advanced: @escaping () -> Void
    ) -> DetailMarkingView {
        DetailMarkingView(
            browsing: model, photo: photo, settings: AppSettings(), images: model.detailImages,
            order: model.photos,
            actions: DetailMarkingActions(
                apply: { change, photo in model.apply(change, to: photo.id) },
                marked: { _, _ in advanced() }, step: { _ in }, markingSwipeBegan: {}))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw PhotoActionWaitFailure()
    }
}

private struct PhotoActionWaitFailure: Error {}
private struct PhotoActionMoveFailure: Error {}

@MainActor
private final class ControlledPhotoLibrary: FolderLibrary {
    let folder: FolderIdentity
    private let recentID = UUID()
    var photos: [GridPhoto] = []
    var groups: [BrowsingGroup] = []
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation
    var openGeneration = 0
    var closeCount = 0
    var heldPhoto: PhotoIdentity?
    var heldWriteNumber: Int?
    var writing: PhotoIdentity?
    var failNext: Set<PhotoIdentity> = []
    var rereadValues: [PhotoIdentity: PhotoMarks] = [:]
    var rereads: [PhotoIdentity] = []
    var writes: [BatchMarkItem] = []
    var moves: [[PhotoIdentity]] = []
    var holdsMove = false
    var failsMove = false
    var isRunningMove = false
    var holdsReopen = false
    var isReopening = false
    var reopenFailure: FolderAccessFailure?

    init(rejected: Set<String> = ["c"], stems: [String] = ["a", "b", "c"]) {
        folder = FolderIdentity(rawValue: recentID.uuidString)
        (updates, continuation) = AsyncStream.makeStream()
        photos = stems.map { stem in
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

    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        var outcomes: [MarkChangeStatus] = []
        for item in items {
            writing = item.photo
            for _ in 0..<1000 {
                if heldPhoto != item.photo && heldWriteNumber != writes.count + 1 { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            writes.append(item)
            let fails = heldPhoto == item.photo || failNext.remove(item.photo) != nil
            if !fails, let index = photos.firstIndex(where: { $0.id == item.photo }) {
                photos[index].marks = photos[index].marks.applying(item.change)
            }
            outcomes.append(
                MarkChangeStatus(
                    id: MarkChangeID(), identity: item.photo, requested: item.change,
                    state: fails
                        ? .failed(MarkWriteFailure(reason: .unknown, message: "Controlled failure"))
                        : .savedInSidecar))
        }
        writing = nil
        return MarkBatchResult(
            id: MarkBatchID(), change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }

    func rereadMarks(for identities: [PhotoIdentity]) async {
        rereads.append(contentsOf: identities)
        for index in photos.indices where identities.contains(photos[index].id) {
            if let marks = rereadValues[photos[index].id] { photos[index].marks = marks }
        }
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
        isRunningMove = true
        defer { isRunningMove = false }
        for _ in 0..<1000 {
            if !holdsMove { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        if failsMove { throw PhotoActionMoveFailure() }
        let ids = plan.readyEntries.map(\.identity)
        moves.append(ids)
        photos.removeAll { ids.contains($0.id) }
        return RejectMoveResult(
            id: RejectMoveBatchID(),
            outcomes: plan.readyEntries.map {
                .moved(
                    RejectMoveMovedSet(
                        identity: $0.identity, files: $0.files, removedStoredReject: false,
                        staleRejectRecord: nil))
            })
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
        photos = []
        openGeneration += 1
    }

    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        isReopening = true
        defer { isReopening = false }
        if let reopenFailure { return reopenFailure }
        for _ in 0..<1000 {
            if !holdsReopen { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await rereadMarks(for: photos.map(\.id))
        openGeneration += 1
        return nil
    }
}
