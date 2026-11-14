import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Clove
@testable import CloveImaging

@MainActor
struct LibraryCacheLifetimeTests {
    @Test func sharedCachesSurviveFolderCloseAndReopen() async throws {
        let workspace = try CacheLifetimeTestWorkspace()
        defer { workspace.remove() }

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 2 }
        let photoA = try #require(model.photos.first?.id)

        let cachesAfterFirstOpen = try #require(await workspace.library.resolvedCaches())
        _ = await workspace.library.thumbnails.thumbnail(for: photoA, priority: .visible)
        try await waitUntil {
            cachesAfterFirstOpen.thumbnails.memoryByteCount > 0
                && cachesAfterFirstOpen.features.memoryByteCount > 0
        }

        await workspace.library.closeFolder()
        #expect(cachesAfterFirstOpen.thumbnails.memoryByteCount > 0)
        #expect(cachesAfterFirstOpen.features.memoryByteCount > 0)

        await model.openPickedFolder(workspace.folderB)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 1 }

        let cachesAfterSecondOpen = try #require(await workspace.library.resolvedCaches())
        #expect(cachesAfterSecondOpen.thumbnails === cachesAfterFirstOpen.thumbnails)
        #expect(cachesAfterSecondOpen.features === cachesAfterFirstOpen.features)
        if let firstSharpness = cachesAfterFirstOpen.sharpness {
            #expect(cachesAfterSecondOpen.sharpness === firstSharpness)
        }
        #expect(cachesAfterSecondOpen.thumbnails.memoryByteCount > 0)
        #expect(cachesAfterSecondOpen.features.memoryByteCount > 0)

        await workspace.library.closeFolder()
    }

    @Test func memoryWarningNotificationReleasesAllMemoryCaches() async throws {
        let workspace = try CacheLifetimeTestWorkspace()
        defer { workspace.remove() }

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 2 }
        let photo = try #require(model.photos.first?.id)

        let caches = try #require(await workspace.library.resolvedCaches())
        let detailPipeline = try #require(workspace.library.activeDetailPipeline)
        let sharpnessResults = try #require(workspace.library.activeSharpnessResults)
        let sharpnessSource = try #require(
            workspace.library.detailImages as? DetailRegionSharpnessSource)

        _ = await workspace.library.thumbnails.thumbnail(for: photo, priority: .visible)
        _ = await workspace.library.detailImages.image(
            for: photo, request: DetailPixelRequest(displayPixels: 800, need: .preview))
        _ = await sharpnessSource.analyzeRegions(
            for: photo, group: [], nearby: [], onAutofocus: { _ in })

        try await waitUntil {
            caches.thumbnails.memoryByteCount > 0 && caches.features.memoryByteCount > 0
                && sharpnessResults.count > 0
        }
        let cachedDetailBefore = await detailPipeline.cachedImageCount
        #expect(cachedDetailBefore > 0)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        try await waitUntil {
            caches.thumbnails.memoryByteCount == 0 && caches.features.memoryByteCount == 0
                && sharpnessResults.count == 0
        }
        try await waitUntil {
            await detailPipeline.cachedImageCount == 0
        }
        #expect(!workspace.library.isPausedForMemoryPressure)

        await workspace.library.closeFolder()
    }

    @Test func criticalPressurePausesWorkersAndNormalOrUserActionResumes() async throws {
        let workspace = try CacheLifetimeTestWorkspace()
        defer { workspace.remove() }

        let model = BrowsingModel(library: workspace.library)
        await model.openPickedFolder(workspace.folderA)
        try await waitUntil { !model.isFolderOpening && model.photos.count == 2 }
        let photo = try #require(model.photos.first?.id)

        let grouping = try #require(workspace.library.activeGrouping)
        let scheduler = try #require(workspace.library.activeSharpnessScheduler)

        await workspace.library.handleMemoryPressure(.critical)
        #expect(workspace.library.isPausedForMemoryPressure)
        #expect(await grouping.featurePipeline.isPaused)
        #expect(await scheduler.isPaused)

        await workspace.library.handleMemoryPressure(.normal)
        #expect(!workspace.library.isPausedForMemoryPressure)
        #expect(!(await grouping.featurePipeline.isPaused))
        #expect(!(await scheduler.isPaused))

        await workspace.library.handleMemoryPressure(.critical)
        #expect(workspace.library.isPausedForMemoryPressure)
        #expect(await grouping.featurePipeline.isPaused)
        #expect(await scheduler.isPaused)

        await workspace.library.runGroupingAgain()
        #expect(!workspace.library.isPausedForMemoryPressure)
        #expect(!(await grouping.featurePipeline.isPaused))
        #expect(!(await scheduler.isPaused))

        await workspace.library.handleMemoryPressure(.critical)
        #expect(workspace.library.isPausedForMemoryPressure)
        _ = await workspace.library.detailImages.image(
            for: photo, request: DetailPixelRequest(displayPixels: 800, need: .preview))
        #expect(!workspace.library.isPausedForMemoryPressure)
        #expect(!(await grouping.featurePipeline.isPaused))
        #expect(!(await scheduler.isPaused))

        await workspace.library.closeFolder()
    }

    private func waitUntil(
        timeout: Duration = .seconds(60),
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
private final class CacheLifetimeTestWorkspace {
    let root: URL
    let folderA: URL
    let folderB: URL
    let library: FolderLibrarySession

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folderA = root.appendingPathComponent("folder-a")
        folderB = root.appendingPathComponent("folder-b")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        try Self.writeJPEG(
            to: folderA.appendingPathComponent("a1.jpg"), gray: 0.3,
            captureDate: "2026:11:01 12:00:00")
        try Self.writeJPEG(
            to: folderA.appendingPathComponent("a2.jpg"), gray: 0.35,
            captureDate: "2026:11:01 12:00:01")
        try Self.writeJPEG(
            to: folderB.appendingPathComponent("b.jpg"), gray: 0.7,
            captureDate: "2026:11:01 12:05:00")

        let cacheRoot = root.appendingPathComponent("caches")
        let stores = FolderLibrarySession.Stores(
            access: FolderAccess(
                store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json"))),
            writes: MarkWriteQueue(storeDirectory: root.appendingPathComponent("marks")),
            groups: SimilarGroupsCache(directory: root.appendingPathComponent("groups")))
        library = FolderLibrarySession(
            stores: Task { stores },
            caches: Task.detached(priority: .userInitiated) {
                await FolderLibrarySession.makeCaches(in: cacheRoot)
            },
            similarGroupsEnabled: { true })
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func writeJPEG(to url: URL, gray: CGFloat, captureDate: String) throws {
        let width = 128
        let height = 128
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: captureDate,
                kCGImagePropertyExifOffsetTimeOriginal: "+00:00",
            ],
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
