import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct PhotoActionsTests {
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
        #expect(model.latestChange(for: b)?.state.isConfirmed == true)
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
        #expect(model.latestChange(for: c)?.state.isConfirmed == true)
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
        #expect(model.latestChange(for: b)?.state.isConfirmed == true)
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

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
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
    var events: [String] = []
    var moves: [[PhotoIdentity]] = []

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
            writing = item.photo
            for _ in 0..<200 {
                if heldPhoto != item.photo { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            events.append("write:\(item.photo.stem)")
            let fails = heldPhoto == item.photo || failNext.remove(item.photo) != nil
            let state: MarkChangeState =
                fails
                ? .failed(MarkWriteFailure(reason: .notConfirmed, message: "Controlled failure"))
                : .savedInSidecar
            if !fails, let index = photos.firstIndex(where: { $0.id == item.photo }) {
                photos[index].marks = photos[index].marks.applying(item.change)
            }
            let status = MarkChangeStatus(
                id: MarkChangeID(), identity: item.photo, requested: item.change, state: state)
            statuses[item.photo] = status
            outcomes.append(status)
            continuation.yield(.change(status))
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
        _ entry: RejectMoveUndoEntry, currentMarks: [PhotoIdentity: PhotoMarks]
    ) async throws -> RejectMoveUndoResult {
        var outcomes: [RejectMoveUndoOutcome] = []
        for photo in movedPhotos.removeValue(forKey: entry.batch) ?? [] {
            photos.append(photo)
        }
        for kept in entry.keptPhotos {
            guard currentMarks[kept.set.id] == kept.marksAfter else {
                outcomes.append(.changedSince(kept.set.id))
                continue
            }
            _ = await apply([BatchMarkItem(photo: kept.set.id, change: .rating(.rejected))])
        }
        continuation.yield(.photos(photos))
        return RejectMoveUndoResult(id: RejectMoveUndoBatchID(), outcomes: outcomes)
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
        photos = closedPhotos
        isClosed = false
        openGeneration += 1
        continuation.yield(.photos(photos))
        return nil
    }
}
