import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Clove
@testable import CloveImaging

@Suite(.serialized)
@MainActor
struct FolderPreparationIntegrationTests {
    @Test func realFolderCompletesAcrossViewsAndFiltersWithoutFullResolutionRender() async throws {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("IMG_0001.jpg"),
            gray: 0.25,
            subjectArea: [64, 64, 24, 24])
        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("IMG_0002.jpg"),
            gray: 0.55,
            subjectArea: nil)
        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("IMG_0003.jpg"),
            gray: 0.8,
            subjectArea: nil)

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)

        try await waitUntil {
            !model.isFolderOpening
                && model.preparationStatus.phase == .complete
                && model.preparationStatus.readyForBothCount == 3
        }

        let baseline = model.preparationStatus
        #expect(baseline.totalPhotos == 3)
        #expect(baseline.analysis.completed == 3)
        #expect(baseline.previews.completed == 3)
        #expect(baseline.readyForBothCount == 3)
        #expect(baseline.issues.isEmpty)
        #expect(baseline.generation == model.openGeneration)

        // Whole-folder full-resolution RAW rendering must never be triggered by background prep.
        let detailPipeline = try #require(workspace.library.activeDetailPipeline)
        #expect(await detailPipeline.nativeRAWRenderCount == 0)
        #expect(await detailPipeline.activeRenderCount == 0)

        // Switching Grid -> Detail -> Grid, filtering (even to 0 matching photos), and reordering
        // must keep the single shared folder-level preparation aggregate intact.
        let firstPhoto = try #require(model.photos.first?.id)
        model.setFilter(.rejected)
        #expect(model.photos.isEmpty)
        #expect(model.preparationStatus == baseline)

        model.setFilter(.all)
        model.setLabelFilter(.red)
        #expect(model.preparationStatus == baseline)

        model.setFilter(.all)
        model.setOrder(.fileName)
        model.openPhoto(firstPhoto)
        #expect(model.state.route == .detail)
        #expect(model.preparationStatus == baseline)

        model.back()
        #expect(model.state.route == .grid)
        #expect(model.preparationStatus == baseline)

        await workspace.library.closeFolder()
        await model.drainActions()
    }

    @Test func reopenUsesDiskCachesWithoutDecodingThumbnailsIntoMemoryOrRerunningAnalysis()
        async throws
    {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("IMG_0101.jpg"),
            gray: 0.3,
            subjectArea: [64, 64, 24, 24])
        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("IMG_0102.jpg"),
            gray: 0.65,
            subjectArea: nil)

        // First library populates disk caches.
        let model1 = BrowsingModel(library: workspace.library)
        await model1.openPickedFolder(workspace.folderA)
        try await waitUntil {
            !model1.isFolderOpening
                && model1.preparationStatus.phase == .complete
                && model1.preparationStatus.readyForBothCount == 2
        }
        await workspace.library.reloadRecents()
        let recent = try #require(workspace.library.recents.first)
        await workspace.library.closeFolder()

        // Second library shares the same Recents identity and disk cache directory with
        // completely fresh, empty in-memory thumbnail and sharpness stores.
        let secondLibrary = workspace.makeSecondLibrary()
        let model2 = BrowsingModel(library: secondLibrary)
        await model2.reopen(recent)
        try await waitUntil {
            !model2.isFolderOpening
                && model2.preparationStatus.phase == .complete
                && model2.preparationStatus.readyForBothCount == 2
        }

        let caches2 = try #require(await secondLibrary.resolvedCaches())
        // Disk thumbnail cache checks satisfy previews without decoding CGImages into memory LRU.
        #expect(caches2.thumbnails.memoryByteCount == 0)
        // Disk sharpness cache inspection satisfies analysis without populating memory LRU.
        #expect(secondLibrary.activeSharpnessResults?.count == 0)

        await secondLibrary.closeFolder()
    }

    @Test func unreadableFileReportsExplicitIssuesInsteadOfFalseCompletion() async throws {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderA.appendingPathComponent("GOOD_0001.jpg"),
            gray: 0.4,
            subjectArea: nil)
        try Data("not-a-valid-raw".utf8).write(
            to: workspace.folderA.appendingPathComponent("CORRUPT_0002.ARW"))

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)

        try await waitUntil {
            !model.isFolderOpening
                && model.preparationStatus.phase == .completeWithIssues
        }

        let status = model.preparationStatus
        #expect(status.totalPhotos == 2)
        #expect(status.readyForBothCount == 1)
        #expect(status.bothSettledCount == 2)
        #expect(status.previews.completed == 1)
        #expect(status.previews.failed == 1)
        #expect(status.analysis.completed == 1)
        #expect(status.analysis.failed == 1)
        #expect(status.issues.contains { $0.fileName == "CORRUPT_0002.ARW" })

        await workspace.library.closeFolder()
    }

    @Test func retryingCannotOpenPhotoRecoversWithoutRescanningAndRespectsPauseState() async throws
    {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        let goodURL = workspace.folderA.appendingPathComponent("GOOD_0001.jpg")
        let recoverURL = workspace.folderA.appendingPathComponent("RECOVER_0002.jpg")
        try PreparationTestWorkspace.writeJPEG(
            to: goodURL, gray: 0.4, subjectArea: [64, 64, 24, 24])
        try PreparationTestWorkspace.writeJPEG(
            to: recoverURL, gray: 0.7, subjectArea: [64, 64, 24, 24])
        // Remove read permissions temporarily so opening fails with cannotOpen while scan/stat succeeds.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: recoverURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: recoverURL.path)
        }

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)

        try await waitUntil {
            !model.isFolderOpening
                && model.preparationStatus.phase == .completeWithIssues
        }

        let initialGeneration = model.openGeneration
        let failedStatus = model.preparationStatus
        #expect(failedStatus.totalPhotos == 2)
        #expect(failedStatus.readyForBothCount == 1)
        #expect(failedStatus.previews.completed == 1)
        #expect(failedStatus.previews.failed == 1)
        #expect(failedStatus.analysis.completed == 1)
        #expect(failedStatus.analysis.failed == 1)
        #expect(failedStatus.canRetryIssues)
        #expect(failedStatus.issues.contains { $0.fileName == "RECOVER_0002.jpg" })

        // Restore readability without changing file size or mtime.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: recoverURL.path)

        // While paused for memory pressure, retry must be ignored.
        await workspace.library.handleMemoryPressure(.critical)
        #expect(!model.preparationStatus.canRetryIssues)
        await model.retryPreparationIssues()
        #expect(model.preparationStatus.previews.failed == 1)
        #expect(model.preparationStatus.analysis.failed == 1)

        // Resuming from memory pressure makes Retry available again.
        await workspace.library.handleMemoryPressure(.normal)
        try await waitUntil { model.preparationStatus.canRetryIssues }

        await model.retryPreparationIssues()

        try await waitUntil {
            model.preparationStatus.phase == .complete
                && model.preparationStatus.readyForBothCount == 2
        }
        #expect(model.openGeneration == initialGeneration)
        #expect(model.preparationStatus.issues.isEmpty)
        #expect(model.preparationStatus.previews.completed == 2)
        #expect(model.preparationStatus.analysis.completed == 2)

        await workspace.library.closeFolder()
    }

    @Test func replacingAndClosingFolderIsolatesStaleGenerations() async throws {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        for index in 1...6 {
            try PreparationTestWorkspace.writeJPEG(
                to: workspace.folderA.appendingPathComponent("A_\(index).jpg"),
                gray: 0.2 + CGFloat(index) * 0.1,
                subjectArea: nil)
        }
        try PreparationTestWorkspace.writeJPEG(
            to: workspace.folderB.appendingPathComponent("B_1.jpg"),
            gray: 0.5,
            subjectArea: [64, 64, 24, 24])

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)
        let folderAID = workspace.library.folder
        let generationA = workspace.library.openGeneration

        // Immediately replace folderA with folderB while folderA may still be finishing.
        await model.openPickedFolder(workspace.folderB)
        let folderBID = workspace.library.folder
        let generationB = workspace.library.openGeneration
        #expect(folderBID != folderAID)
        #expect(generationB > generationA)

        try await waitUntil {
            !model.isFolderOpening
                && model.preparationStatus.folder == folderBID
                && model.preparationStatus.generation == generationB
                && model.preparationStatus.phase == .complete
        }
        #expect(model.preparationStatus.totalPhotos == 1)
        #expect(model.preparationStatus.readyForBothCount == 1)

        await workspace.library.closeFolder()
        try await waitUntil { model.preparationStatus == .idle }
    }

    @Test func coordinatorPausesForMemoryPressureAndReportsLocationLossWithoutLeakingStaleEvents()
        async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderURL = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = folderURL.appendingPathComponent("IMG_0001.jpg")
        try PreparationTestWorkspace.writeJPEG(
            to: imageURL, gray: 0.45, subjectArea: [64, 64, 24, 24])

        let thumbCache = try ThumbnailCache(
            directory: root.appendingPathComponent("thumbs"), configuration: .deviceAware())
        let thumbPipeline = ThumbnailPipeline(cache: thumbCache)
        let detailPipeline = DetailPipeline(cache: DetailCache(configuration: .deviceAware()))
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(
                reader: DetailRegionSharpnessReading(details: detailPipeline)))
        await scheduler.pause()

        let access = FolderAccess(
            store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json")))
        guard case .opened(let opened) = await access.pick(folderURL) else {
            Issue.record("Expected FolderAccess.pick to open temporary folder")
            return
        }
        let session = opened.session
        let folderID = session.folder.id

        var published: [FolderPreparationStatus] = []
        let coordinator = FolderPreparationCoordinator(
            folder: folderID,
            folderName: "Coord",
            generation: 5,
            session: session,
            thumbnailCache: thumbCache,
            thumbnailPipeline: thumbPipeline,
            regionScheduler: scheduler,
            publish: { status in published.append(status) })

        let photoSet = try PhotoSet(folderID: folderID, relativeFolderPath: "", jpegURL: imageURL)
        let scanned = ScannedPhotoSet(
            photoSet: photoSet,
            sidecar: .absent,
            imageFiles: [
                ScannedImageFile(file: photoSet.primary, size: 1024, modificationDate: Date())
            ])

        coordinator.start()
        #expect(coordinator.currentStatus.phase == .enumeratingUnknown)

        // Wrong generation must be ignored completely.
        coordinator.registerDiscovered([scanned], generation: 4)
        #expect(coordinator.currentStatus.totalPhotos == 0)

        coordinator.registerDiscovered([scanned], generation: 5)
        coordinator.finishScan(isPartial: false, generation: 5)
        #expect(coordinator.currentStatus.totalPhotos == 1)

        // Memory pressure pauses coordinator cleanly.
        coordinator.setMemoryPressurePaused(true)
        #expect(coordinator.currentStatus.phase == .waiting(.memoryPressure))

        // Resuming allows scheduler + coordinator to finish cleanly.
        coordinator.setMemoryPressurePaused(false)
        await scheduler.resume()
        try await waitUntil { coordinator.currentStatus.phase == .complete }
        #expect(coordinator.currentStatus.readyForBothCount == 1)

        // Location loss transition after work is closed / stopped.
        let coordinator2 = FolderPreparationCoordinator(
            folder: folderID,
            folderName: "Coord2",
            generation: 6,
            session: session,
            thumbnailCache: thumbCache,
            thumbnailPipeline: thumbPipeline,
            regionScheduler: scheduler,
            publish: { _ in })
        coordinator2.start()
        coordinator2.registerDiscovered([scanned], generation: 6)
        coordinator2.finishScan(isPartial: false, generation: 6)
        coordinator2.markLocationLost(.externalVolumeDisconnected)
        #expect(
            coordinator2.currentStatus.phase
                == .waiting(.folderUnavailable(.externalVolumeDisconnected)))

        await coordinator.close()
        await coordinator2.close()
        await scheduler.close()
        await thumbPipeline.close()
        await detailPipeline.close()
        await session.end()
    }

    @Test func criticalMemoryPressureAndNormalRecoveryFinishRealFolderPreparation() async throws {
        let workspace = try PreparationTestWorkspace()
        defer { workspace.remove() }

        for index in 1...4 {
            try PreparationTestWorkspace.writeJPEG(
                to: workspace.folderA.appendingPathComponent("MP_\(index).jpg"),
                gray: 0.2 * CGFloat(index),
                subjectArea: nil)
        }

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)
        await workspace.library.handleMemoryPressure(.critical)
        #expect(workspace.library.isPausedForMemoryPressure)
        if model.preparationStatus.phase != .complete {
            #expect(
                model.preparationStatus.phase == .waiting(.memoryPressure)
                    || model.preparationStatus.waitingReason == .memoryPressure)
        }

        await workspace.library.handleMemoryPressure(.normal)
        #expect(!workspace.library.isPausedForMemoryPressure)

        try await waitUntil {
            !model.isFolderOpening
                && model.preparationStatus.phase == .complete
                && model.preparationStatus.readyForBothCount == 4
        }

        await workspace.library.closeFolder()
    }

    private func waitUntil(
        timeout: Duration = .seconds(90),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while await !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class PreparationTestWorkspace {
    let root: URL
    let folderA: URL
    let folderB: URL
    let cacheRoot: URL
    let library: FolderLibrarySession

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folderA = root.appendingPathComponent("folder-a")
        folderB = root.appendingPathComponent("folder-b")
        cacheRoot = root.appendingPathComponent("caches")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        library = Self.makeLibrary(in: root, recentsRoot: root, cacheRoot: cacheRoot)
    }

    func makeSecondLibrary() -> FolderLibrarySession {
        Self.makeLibrary(
            in: root.appendingPathComponent("second-stores"),
            recentsRoot: root,
            cacheRoot: cacheRoot)
    }

    private static func makeLibrary(
        in storeRoot: URL,
        recentsRoot: URL,
        cacheRoot: URL
    ) -> FolderLibrarySession {
        try? FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(
                    fileURL: recentsRoot.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: storeRoot.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: storeRoot.appendingPathComponent("groups")))
        return FolderLibrarySession(
            stores: Task { stores },
            caches: Task.detached(priority: .userInitiated) {
                await FolderLibrarySession.makeCaches(in: cacheRoot)
            },
            similarGroupsEnabled: { false })
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    static func writeJPEG(to url: URL, gray: CGFloat, subjectArea: [Int]?) throws {
        let width = 128
        let height = 128
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        var exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2026:11:01 12:00:00",
            kCGImagePropertyExifOffsetTimeOriginal: "+00:00",
        ]
        if let subjectArea {
            exif[kCGImagePropertyExifPixelXDimension] = width
            exif[kCGImagePropertyExifPixelYDimension] = height
            exif[kCGImagePropertyExifSubjectArea] = subjectArea
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: "TestCam"
            ],
        ]
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }
}
