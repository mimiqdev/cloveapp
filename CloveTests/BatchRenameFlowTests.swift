import CloveCore
import CloveImaging
import CoreGraphics
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

    @Test func aRescanFailureIsReportedAlongsideTheCompletedRename() async throws {
        let library = HeldRenameLibrary()
        library.failsRescan = true
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.toggleSelection(try #require(browsing.photos.first?.id))
        let flow = BatchRenameFlow(browsing: browsing)
        flow.options.prefix = "Rescan_"
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        await flow.rename {}
        let completed = try #require(browsing.completedRename)
        #expect(completed.message == "Renamed 1 photo")
        #expect(completed.detail == RenameFlowError.rescanFailed.localizedDescription)
        #expect(completed.hasDetails)
        #expect(!browsing.canUndoMark)
    }

    @Test func zoomDuringADelayedFitReadFinishesWithNativePixels() async throws {
        let source = try DelayedRenameImages()
        let pixels = RenameCheckImages(source: source)
        let identity = try #require(TestLibrary.sample.photos.first?.id)
        let window = DetailPhotoWindow(
            id: UUID(), current: DetailNeighbour(photo: identity, position: 0),
            neighbours: [], direction: 1, mode: .rawFirst, screenPixels: 1000)
        let loading = Task { await pixels.load(window, thumbnails: SampleGridThumbnails()) }
        for _ in 0..<100 where source.releaseScreen == nil { await Task.yield() }
        #expect(source.releaseScreen != nil)
        pixels.setZoomed(true)
        #expect(source.needs == [.preview, .screenRender])
        source.releaseScreen?.resume()
        source.releaseScreen = nil
        await loading.value
        #expect(source.needs == [.preview, .screenRender, .fullResolution])
        #expect(pixels.shown?.quality == .nativeRAW)
        pixels.close()
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

    @Test func removeDropsPhotoFromBatchAndClearsPreviewWithoutChangingGridSelection() async throws
    {
        let library = TestLibrary.sample
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.setOrder(.fileName)
        let selected = Array(browsing.photos.prefix(3))
        for photo in selected { browsing.toggleSelection(photo.id) }
        let flow = BatchRenameFlow(
            browsing: browsing, defaults: BatchRenameDefaults(storage: SampleSettingsStorage()))
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        #expect(flow.preview?.rows.count == 3)
        flow.remove(selected[1].id)
        #expect(flow.order.map(\.id) == [selected[0].id, selected[2].id])
        #expect(flow.preview == nil)
        #expect(!flow.canRename)
        #expect(browsing.batchTargets.count == 3)
        flow.remove(selected[0].id)
        flow.remove(selected[2].id)
        #expect(flow.order.isEmpty)
        await library.closeFolder()
    }

    @Test func sortOrdersByCaptureTimeFileNameAndReverseAndClearsPreview() async throws {
        let library = TestLibrary.sample
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.setOrder(.captureTime)
        let selected = Array(browsing.photos.prefix(3))
        for photo in selected { browsing.toggleSelection(photo.id) }
        let flow = BatchRenameFlow(
            browsing: browsing, defaults: BatchRenameDefaults(storage: SampleSettingsStorage()))
        let initialIDs = flow.order.map(\.id)
        await flow.prepare(rejectsFolderName: .defaultFolderName)
        #expect(flow.preview != nil)

        flow.sort(by: .reverse)
        #expect(flow.order.map(\.id) == initialIDs.reversed())
        #expect(flow.preview == nil)

        flow.sort(by: .fileName)
        let expectedByFileName = selected.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        #expect(flow.order.map(\.id) == expectedByFileName.map(\.id))

        flow.sort(by: .captureTime)
        let expectedByCaptureTime = selected.sorted {
            let lhs = $0.time.time?.instant ?? .distantFuture
            let rhs = $1.time.time?.instant ?? .distantFuture
            if lhs != rhs { return lhs < rhs }
            return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        #expect(flow.order.map(\.id) == expectedByCaptureTime.map(\.id))
        await library.closeFolder()
    }

    @Test func defaultsPersistPrefixDigitsAndSeparatorAcrossFlowsAndIsolateTests() async throws {
        let storage = SampleSettingsStorage()
        let defaults = BatchRenameDefaults(storage: storage)
        #expect(defaults.prefix == "")
        #expect(defaults.digits == 3)
        #expect(defaults.separator == .underscore)

        let fixture = try await RenameFixture(existing: false)
        defer { fixture.removeFiles() }
        let firstFlow = BatchRenameFlow(browsing: fixture.browsing, defaults: defaults)
        firstFlow.options.prefix = "Wedding"
        firstFlow.options.digits = 4
        firstFlow.options.separator = .hyphen
        firstFlow.options.start = 12
        await firstFlow.prepare(rejectsFolderName: fixture.rejects)
        var completed = false
        await firstFlow.rename { completed = true }
        #expect(completed)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.photos.appendingPathComponent("Wedding-0012.jpg").path))

        let nextFlow = BatchRenameFlow(browsing: fixture.browsing, defaults: defaults)
        #expect(nextFlow.options.prefix == "Wedding")
        #expect(nextFlow.options.digits == 4)
        #expect(nextFlow.options.separator == .hyphen)
        #expect(nextFlow.options.start == 1)

        let testLaunchDefaults = BatchRenameDefaults.launch(
            environment: [TestLibrary.launchVariable: "1"])
        #expect(testLaunchDefaults.prefix == "")
        #expect(testLaunchDefaults.digits == 3)
        #expect(testLaunchDefaults.separator == .underscore)
        await fixture.library.closeFolder()
    }

    @Test func separatorOptionsDriveTemplateWithoutDuplicatingTrailingSeparator() async throws {
        let fixture = try await RenameFixture(existing: false)
        defer { fixture.removeFiles() }
        let defaults = BatchRenameDefaults(storage: SampleSettingsStorage())
        let flow = BatchRenameFlow(browsing: fixture.browsing, defaults: defaults)

        flow.options.prefix = "Trip"
        flow.options.separator = .hyphen
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.preview?.rows.first?.newStem == "Trip-001")

        flow.options.separator = .none
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.preview?.rows.first?.newStem == "Trip001")

        flow.options.prefix = "Test_"
        flow.options.separator = .underscore
        await flow.prepare(rejectsFolderName: fixture.rejects)
        #expect(flow.preview?.rows.first?.newStem == "Test_001")
        await fixture.library.closeFolder()
    }

    @Test func browsingSetSelectionAndDeselectAllVisibleKeepGridModelConsistent() async {
        let library = TestLibrary.sample
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        let cells = GridDisplay(photos: browsing.photos, groups: [], groupsEnabled: false).cells
        let subset = Set(cells.prefix(2).map(\.photo.id))
        browsing.setSelection(subset)
        #expect(browsing.state.selection == subset)
        browsing.deselectAllVisible(cells)
        #expect(browsing.state.selection.isEmpty)
        await library.closeFolder()
    }

    @Test func hiddenSelectedCountTracksFilterAndBatchActionsOperateOnlyOnVisibleTargets()
        async throws
    {
        let library = TestLibrary.sample()
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
        browsing.openFolder()
        let selected = Array(browsing.photos.dropFirst(2).prefix(3))
        for photo in selected { browsing.toggleSelection(photo.id) }
        #expect(browsing.batchTargets.count == 3)
        #expect(browsing.hiddenSelectedCount == 0)

        let fourStars = try #require(Rating(rawValue: 4))
        browsing.apply(.rating(fourStars), to: selected[0].id)
        browsing.setFilter(.ratedAtLeast(fourStars))
        #expect(browsing.isSelecting)
        #expect(browsing.batchTargets.map(\.id) == [selected[0].id])
        #expect(browsing.hiddenSelectedCount == 2)
        #expect(BatchRenameFlow(browsing: browsing).order.map(\.id) == [selected[0].id])

        browsing.applyBatch(.label(ColourLabel(colour: .blue)), settings: AppSettings())
        let firstMarks = browsing.shownMarks(for: selected[0].id)
        let secondMarks = browsing.shownMarks(for: selected[1].id)
        #expect(firstMarks.label.colour == .blue)
        #expect(secondMarks.label == .clear)

        // All selected photos hidden keeps selection mode active with 0 visible targets.
        browsing.setFilter(.rejected)
        #expect(browsing.isSelecting)
        #expect(browsing.batchTargets.isEmpty)
        #expect(browsing.hiddenSelectedCount == 3)

        // Clearing filter restores full visible selection cleanly.
        browsing.setFilter(.all)
        #expect(browsing.batchTargets.count == 3)
        #expect(browsing.hiddenSelectedCount == 0)
        await library.closeFolder()
    }

    @Test func groupedCoverSelectionUnderFilterReportsVisibleTargetsAndHiddenSelectedCount()
        async throws
    {
        let library = TestLibrary.sample()
        let browsing = BrowsingModel(library: library, similarGroupsEnabled: true)
        browsing.openFolder()
        let group = try #require(browsing.groups.last { $0.members.count >= 3 })
        let hiddenMember = try #require(group.members.last)
        browsing.apply(MarkChange(rating: .rejected), to: hiddenMember)
        browsing.setFilter(.unmarked)

        let cells = GridDisplay(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: true
        )
        .cells
        let coverCell = try #require(
            cells.first { $0.group?.id == group.id && $0.group?.isCover == true })
        browsing.beginSelection(of: coverCell)

        #expect(browsing.state.selection.contains(hiddenMember))
        #expect(
            browsing.batchTargets.count
                == browsing.photos.filter { group.members.contains($0.id) }.count)
        #expect(browsing.hiddenSelectedCount == 1)
        await library.closeFolder()
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
    var failsRescan = false
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
        if failsRescan { throw RenameFlowError.rescanFailed }
        try await sample.rescanAfterRename()
    }
}

@MainActor
private final class DelayedRenameImages: DetailImageSource {
    var releaseScreen: CheckedContinuation<Void, Never>?
    var needs: [DetailPixelRequest.Need] = []
    let image: CGImage

    init() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        image = try #require(context.makeImage())
    }

    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    { image }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        needs.append(request.need)
        if request.need == .screenRender { await withCheckedContinuation { releaseScreen = $0 } }
        return .image(
            DetailImage(
                image: image,
                source: DetailSource(
                    url: URL(fileURLWithPath: "/synthetic.ARW"),
                    revision: ThumbnailRevision(size: 0, modificationTime: .distantPast)),
                quality: request.need == .fullResolution
                    ? .nativeRAW : request.need == .preview ? .preview : .screenRAW,
                hasRAW: true, fullResolutionSize: CGSize(width: 6000, height: 4000)))
    }
}
