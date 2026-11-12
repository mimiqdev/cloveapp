import CloveCore
import Foundation
import Testing

@testable import Clove

@MainActor
struct BatchRenameFlowTests {
    @Test func orderStartsInGridOrderAndStaysLocalUntilConfirmation() async throws {
        let library = TestLibrary.sample
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.setOrder(.fileName)
        let selected = Array(browsing.photos.prefix(3))
        for photo in selected.reversed() { browsing.toggleSelection(photo.id) }
        let flow = BatchRenameFlow(browsing: browsing)
        #expect(flow.order.map(\.id) == selected.map(\.id))
        flow.move(selected[2].id, to: 0)
        #expect(flow.order.map(\.id) == [selected[2].id, selected[0].id, selected[1].id])
        flow.move(selected[2].id, to: -1)
        #expect(flow.order.first?.id == selected[2].id)
        #expect(browsing.batchTargets == selected)
        #expect(BatchRenameFlow(browsing: browsing).order == selected)
        await library.closeFolder()
    }

    @Test func warningsAllowReplacementAndProblemsBlockTheWholeBatch() async throws {
        let fixture = try await RenameFixture(existing: true)
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.options.prefix = "Test_"
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.preview?.replacementCount == 1)
        #expect(flow.canRename)
        #expect(flow.preview?.rows.first?.replacement?.rejectsRelativeFolder == "Archive")
        flow.options.prefix = "Invalid/"
        #expect(!flow.canRename)
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.preview?.rows.allSatisfy { !$0.problems.isEmpty } == true)
        #expect(!flow.canRename)
        flow.options.prefix = String(repeating: "界", count: 90)
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(
            flow.preview?.rows.first?.problems.contains(where: {
                if case .nameTooLong = $0 { return true }; return false
            }) == true)
        #expect(!flow.canRename)
        await fixture.library.closeFolder()
    }

    @Test func renameDrainsMarksPreservesReplacementsRemapsCurrentAndClearsUndo() async throws {
        let fixture = try await RenameFixture(existing: true)
        defer { fixture.removeFiles() }
        let browsing = fixture.browsing
        let third = fixture.selected[2]
        browsing.openPhoto(third.id)
        browsing.apply(.label(ColourLabel(colour: .green)), to: third.id)
        #expect(browsing.canUndoMark)
        let flow = fixture.flow()
        flow.move(third.id, to: 0)
        flow.options.prefix = "Test_"
        await flow.prepare(rejectsFolderName: fixture.rejects)
        var completed = false
        await flow.rename { completed = true }
        #expect(completed)
        #expect(!flow.isRunning)
        #expect(flow.finishedCount == 3)
        #expect(browsing.completedRename?.message == "Renamed 3 photos")
        #expect(browsing.completedRename?.result.replacementCount == 1)
        #expect(browsing.state.currentPhoto?.stem == "test_001")
        #expect(browsing.currentPhoto?.marks.label.colour == .green)
        #expect(browsing.state.selection.isEmpty)
        #expect(!browsing.canUndoMark)
        #expect(browsing.lastRejectMove == nil)
        #expect(browsing.state.route == .grid)
        #expect(browsing.canMark)
        #expect(
            try Data(contentsOf: fixture.photos.appendingPathComponent("Test_001.jpg"))
                == Data("c".utf8))
        #expect(
            try Data(contentsOf: fixture.photos.appendingPathComponent("Archive/Test_001.jpg"))
                == Data("existing".utf8))
        #expect(browsing.photos.count == 3)
        await fixture.library.closeFolder()
    }

    @Test func movingToANewFolderKeepsPhotosVisibleAndRejectsInvalidDestination() async throws {
        let fixture = try await RenameFixture(existing: false)
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        flow.options.movesToFolder = true
        flow.options.folderName = "Archive"
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(!flow.canRename)
        flow.options.folderName = "Ordered"
        flow.options.prefix = "Trip_"
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.canRename)
        #expect(flow.preview?.rows.allSatisfy { $0.destinationRelativeFolder == "Ordered" } == true)
        await flow.rename {}
        #expect(fixture.browsing.photos.count == 3)
        #expect(fixture.browsing.photos.allSatisfy { $0.id.relativeFolderPath == "Ordered" })
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.photos.appendingPathComponent("Ordered/Trip_001.jpg").path))
        await fixture.library.closeFolder()
    }

    @Test func aChangedFolderCannotExecuteAnOldConfirmation() async throws {
        let fixture = try await RenameFixture(existing: false)
        defer { fixture.removeFiles() }
        let flow = fixture.flow()
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.canRename)
        await fixture.browsing.reopenOpenFolder()
        var completed = false
        await flow.rename { completed = true }
        #expect(!completed)
        #expect(flow.message == RenameFlowError.folderChanged.localizedDescription)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.photos.appendingPathComponent("a.jpg").path))
        await fixture.library.closeFolder()
    }

    @Test func confirmationWaitsForQueuedWritesAndBlocksAnotherRun() async throws {
        let library = HeldRenameLibrary()
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        let photo = try #require(browsing.photos.first)
        browsing.toggleSelection(photo.id)
        browsing.apply(.label(ColourLabel(colour: .blue)), to: photo.id)
        for _ in 0..<100 where library.releaseWrite == nil { await Task.yield() }
        #expect(library.releaseWrite != nil)
        let flow = BatchRenameFlow(browsing: browsing)
        flow.options.prefix = "Held_"
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        let running = Task { await flow.rename {} }
        for _ in 0..<100 where !flow.isRunning { await Task.yield() }
        #expect(flow.isRunning)
        #expect(!browsing.canMark)
        #expect(!flow.canRename)
        #expect(!library.events.contains("rename"))
        await flow.rename { Issue.record("A second confirmation must not run") }
        library.releaseWrite?.resume()
        library.releaseWrite = nil
        await running.value
        #expect(library.events == ["write", "drain", "rename", "rescan"])
        #expect(browsing.photos.first { $0.id.stem == "held_001" }?.marks.label.colour == .blue)
        #expect(browsing.canMark)
    }

    @Test func partialFailureRescansAndReportsTemporaryNamesWithoutUndo() async throws {
        let files = FailingRenameFiles()
        let fixture = try await RenameFixture(existing: false, fileSystem: files)
        defer { fixture.removeFiles() }
        // Reverse these names so the engine needs its temporary pass.
        let first = fixture.photos.appendingPathComponent("a.jpg")
        try FileManager.default.moveItem(
            at: first, to: fixture.photos.appendingPathComponent("1.jpg"))
        await fixture.browsing.reopenOpenFolder()
        try await fixture.waitForScan()
        fixture.browsing.clearSelection()
        for photo in fixture.browsing.photos { fixture.browsing.toggleSelection(photo.id) }
        let reordered = BatchRenameFlow(browsing: fixture.browsing)
        reordered.options.digits = 1
        reordered.move(reordered.order[0].id, to: 2)
        await reordered.prepare(rejectsFolderName: fixture.rejects)
        #expect(reordered.preview?.requiresTemporaryNames == true)
        files.failFinalMove = true
        await reordered.rename {}
        let completed = try #require(fixture.browsing.completedRename)
        #expect(completed.result.failure != nil)
        #expect(completed.message == "Renamed 0 of 3")
        #expect(completed.result.temporarySets.count == 3)
        #expect(completed.hasDetails)
        #expect(fixture.browsing.photos.count == 3)
        #expect(fixture.browsing.photos.allSatisfy { $0.id.stem.hasPrefix("clove-rename-") })
        #expect(!fixture.browsing.canUndoMark)
        await fixture.library.closeFolder()
    }
}

@MainActor
private final class RenameFixture {
    let root: URL
    let photos: URL
    let library: FolderLibrarySession
    let browsing: BrowsingModel
    let rejects: RejectsFolderName
    let selected: [GridPhoto]

    init(existing: Bool, fileSystem: any PhotoFileSystem = FoundationPhotoFileSystem()) async throws
    {
        let rejects = try RejectsFolderName.validated("Archive")
        self.rejects = rejects
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        for name in ["a", "b", "c"] {
            try Data(name.utf8).write(to: photos.appendingPathComponent("\(name).jpg"))
        }
        if existing {
            try Data("existing".utf8).write(to: photos.appendingPathComponent("Test_001.jpg"))
        }
        let marks = CloveMarkStore(directory: root.appendingPathComponent("marks"))
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(store: marks),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")),
            renamer: BatchRenamer(store: marks, fileSystem: fileSystem))
        library = FolderLibrarySession(
            stores: Task { stores }, rejectsFolderName: { rejects },
            similarGroupsEnabled: { false })
        browsing = BrowsingModel(library: library)
        await browsing.openPickedFolder(photos)
        browsing.setOrder(.fileName)
        for _ in 0..<1000 {
            if !browsing.isFolderOpening && browsing.photos.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        selected = browsing.photos.filter { ["a", "b", "c"].contains($0.id.stem) }
        #expect(selected.count == 3)
        for photo in selected { browsing.toggleSelection(photo.id) }
    }

    func flow() -> BatchRenameFlow { BatchRenameFlow(browsing: browsing) }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
    func waitForScan() async throws {
        for _ in 0..<1000 {
            if !browsing.isFolderOpening { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw RenameFlowError.rescanFailed
    }
}

private final class FailingRenameFiles: PhotoFileSystem, @unchecked Sendable {
    private let backing = FoundationPhotoFileSystem()
    private let lock = NSLock()
    private var shouldFail = false
    var failFinalMove: Bool {
        get { lock.withLock { shouldFail } }
        set { lock.withLock { shouldFail = newValue } }
    }
    func fileSize(at url: URL) throws -> Int? { try backing.fileSize(at: url) }
    func exists(at url: URL) throws -> Bool { try backing.exists(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try backing.contentsOfDirectory(at: url)
    }
    func isDirectory(at url: URL) throws -> Bool { try backing.isDirectory(at: url) }
    func creationDate(at url: URL) throws -> Date? { try backing.creationDate(at: url) }
    func volumeIdentifier(of url: URL) throws -> String? { try backing.volumeIdentifier(of: url) }
    func isReadOnlyVolume(at url: URL) throws -> Bool { false }
    func createDirectory(_ url: URL) throws { try backing.createDirectory(url) }
    func moveExclusively(from source: URL, to destination: URL) throws {
        if failFinalMove, source.lastPathComponent.hasPrefix("clove-rename-"),
            !destination.lastPathComponent.hasPrefix("clove-rename-")
        {
            throw CocoaError(.fileWriteNoPermission)
        }
        try backing.moveExclusively(from: source, to: destination)
    }
}

@MainActor
private final class HeldRenameLibrary: FolderLibrary {
    let sample = TestLibrary.sample
    var releaseWrite: CheckedContinuation<Void, Never>?
    var events: [String] = []
    var folder: FolderIdentity { sample.folder }
    var photos: [GridPhoto] { sample.photos }
    var groups: [BrowsingGroup] { [] }
    var updates: AsyncStream<FolderLibraryUpdate> { sample.updates }

    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        await withCheckedContinuation { releaseWrite = $0 }
        events.append("write")
        return await sample.apply(items)
    }
    func drainWrites() async { events.append("drain") }
    func planBatchRename(
        order: [PhotoIdentity], template: RenameTemplate, destination: RenameDestination,
        rejectsFolderName: RejectsFolderName
    ) async throws -> BatchRenamePlan {
        try await sample.planBatchRename(
            order: order, template: template, destination: destination,
            rejectsFolderName: rejectsFolderName)
    }
    func runBatchRename(
        _ plan: BatchRenamePlan,
        progress: @escaping @MainActor @Sendable (BatchRenameProgress) -> Void
    ) async throws -> BatchRenameResult {
        events.append("rename")
        return try await sample.runBatchRename(plan, progress: progress)
    }
    func rescanAfterRename() async throws {
        events.append("rescan")
        try await sample.rescanAfterRename()
    }
}
