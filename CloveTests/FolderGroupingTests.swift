import CloveCore
@testable import CloveImaging
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Clove

@MainActor
struct FolderGroupingTests {
    @Test func warmCacheHitSkipsFeatureAnalysisAndRunAgainReanalyzes() async throws {
        let fixture = try await GroupingTestWorkspace()
        defer { fixture.remove() }

        var coldActivity: [Bool] = []
        var coldSetsLookups = 0
        var coldPublished: [[BrowsingGroup]] = []
        let coldGrouping = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.coldFeatures,
            previewCache: fixture.coldThumbnails,
            sets: { id in
                coldSetsLookups += 1
                return fixture.sets[id]
            },
            publish: { groups in coldPublished.append(groups) },
            analysisChanged: { active in coldActivity.append(active) })

        await coldGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil { coldActivity.contains(true) && coldActivity.last == false }
        #expect(coldSetsLookups == fixture.groupingPhotos.count)
        let finishedCold = try #require(coldPublished.last)
        await coldGrouping.close()

        // Reopen with the same SimilarGroupsCache but empty feature and preview caches.
        var warmActivity: [Bool] = []
        var warmSetsLookups = 0
        var warmPublished: [[BrowsingGroup]] = []
        let warmGrouping = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.warmFeatures,
            previewCache: fixture.warmThumbnails,
            sets: { id in
                warmSetsLookups += 1
                return fixture.sets[id]
            },
            publish: { groups in warmPublished.append(groups) },
            analysisChanged: { active in warmActivity.append(active) })

        await warmGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        // Yield briefly to verify no background analysis task was scheduled.
        try await Task.sleep(for: .milliseconds(50))

        #expect(warmPublished.last == finishedCold)
        #expect(!warmActivity.contains(true))
        #expect(warmSetsLookups == 0)
        let warmFeatureFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.warmFeatureDirectory, includingPropertiesForKeys: nil)
        #expect(warmFeatureFiles.filter { $0.pathExtension == "feature" }.isEmpty)

        // Calling Run again after a warm hit must bypass the cache and re-analyze.
        await warmGrouping.runAgain(photos: fixture.groupingPhotos)
        try await waitUntil { warmActivity.contains(true) && warmActivity.last == false }
        #expect(warmSetsLookups == fixture.groupingPhotos.count)
        await warmGrouping.close()
        await fixture.session.end()
    }

    @Test func changedThresholdsAfterWarmHitTriggersAnalysis() async throws {
        let fixture = try await GroupingTestWorkspace()
        defer { fixture.remove() }

        var coldActivity: [Bool] = []
        let coldGrouping = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.coldFeatures,
            previewCache: fixture.coldThumbnails,
            sets: { fixture.sets[$0] },
            publish: { _ in },
            analysisChanged: { coldActivity.append($0) })

        await coldGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil { coldActivity.contains(true) && coldActivity.last == false }
        await coldGrouping.close()

        var recalibratedActivity: [Bool] = []
        var recalibratedSetsLookups = 0
        let recalibrated = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.warmFeatures,
            previewCache: fixture.warmThumbnails,
            thresholds: GroupingThresholds(visionDistance: 0.25),
            sets: { id in
                recalibratedSetsLookups += 1
                return fixture.sets[id]
            },
            publish: { _ in },
            analysisChanged: { recalibratedActivity.append($0) })

        await recalibrated.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil {
            recalibratedActivity.contains(true) && recalibratedActivity.last == false
        }
        #expect(recalibratedSetsLookups == fixture.groupingPhotos.count)
        await recalibrated.close()
        await fixture.session.end()
    }

    @Test func incrementalColdGroupingRefinesEarlyBurstsBeforePassCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photosDir = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let access = FolderAccess(
            store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json")))
        guard case .opened(let opened) = await access.pick(photosDir) else {
            Issue.record("Expected test folder to open")
            return
        }
        let session = opened.session
        let folderID = session.folder.id

        // Two time-runs: burst 1 (a, b, c) where a is white (splits) and b, c are black (join);
        // burst 2 (d, e) whose preview reads are held on a test gate so we can observe burst 1
        // settling before burst 2 finishes.
        let names = ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"]
        let grays: [CGFloat] = [1.0, 0.0, 0.0, 0.0, 0.0]
        let timestamps: [TimeInterval] = [0.0, 0.2, 0.4, 10.0, 10.2]
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sets: [PhotoIdentity: PhotoSet] = [:]
        var groupingPhotos: [GroupingPhoto] = []
        var imagesByName: [String: CGImage] = [:]
        for index in names.indices {
            let fileURL = photosDir.appendingPathComponent(names[index])
            let image = GroupingTestWorkspace.makeGrayImage(gray: grays[index])
            try GroupingTestWorkspace.writeJPEG(image, to: fileURL)
            imagesByName[names[index]] = image
            let set = try PhotoSet(
                folderID: folderID, relativeFolderPath: "", jpegURL: fileURL)
            sets[set.id] = set
            groupingPhotos.append(
                GroupingPhoto(
                    id: set.id,
                    fileName: names[index],
                    time: .known(
                        PhotoTime(
                            captureTime: base.addingTimeInterval(timestamps[index]),
                            hasUTCOffset: true)),
                    cameraModel: "TestCam"))
        }

        let gate = GatedPreviewReader(
            images: imagesByName, heldNames: ["d.jpg", "e.jpg"])
        let featureCache = try ImageFeatureCache(
            directory: root.appendingPathComponent("features"))
        let previewCache = try ThumbnailCache(
            directory: root.appendingPathComponent("thumbs"))
        let groupCache = SimilarGroupsCache(directory: root.appendingPathComponent("groups"))
        let pipeline = ImageFeaturePipeline(
            cache: featureCache, previews: gate, prints: DeterministicFeaturePrintReader(),
            workers: 2)

        var published: [[BrowsingGroup]] = []
        var activity: [Bool] = []
        let grouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            featurePipeline: pipeline,
            sets: { sets[$0] },
            publish: { published.append($0) },
            analysisChanged: { activity.append($0) })

        await grouping.begin(
            photos: groupingPhotos,
            revision: GroupingInputRevision(rawValue: "cold-incremental"),
            enabled: true)

        // Initial publication is time-only: two groups ([a, b, c], [d, e]).
        #expect(
            published.last?.map(\.members) == [
                [groupingPhotos[0].id, groupingPhotos[1].id, groupingPhotos[2].id],
                [groupingPhotos[3].id, groupingPhotos[4].id],
            ])

        // Wait for burst 1 to refine and publish while burst 2 is still blocked.
        try await waitUntil {
            published.last?.map(\.members) == [
                [groupingPhotos[1].id, groupingPhotos[2].id],
                [groupingPhotos[3].id, groupingPhotos[4].id],
            ]
        }
        #expect(activity.last == true)
        #expect(Set(await gate.startedNames.prefix(3)) == ["a.jpg", "b.jpg", "c.jpg"])

        await gate.releaseHeld()
        try await waitUntil { activity.contains(true) && activity.last == false }
        #expect(
            published.last?.map(\.members) == [
                [groupingPhotos[1].id, groupingPhotos[2].id],
                [groupingPhotos[3].id, groupingPhotos[4].id],
            ])

        await grouping.close()
        await session.end()
    }

    private func waitUntil(
        timeout: Duration = .seconds(60),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class GroupingTestWorkspace {
    let root: URL
    let session: FolderAccessSession
    let folderID: FolderIdentity
    let groupCache: SimilarGroupsCache
    let coldFeatures: ImageFeatureCache
    let coldThumbnails: ThumbnailCache
    let warmFeatureDirectory: URL
    let warmFeatures: ImageFeatureCache
    let warmThumbnails: ThumbnailCache
    let sets: [PhotoIdentity: PhotoSet]
    let groupingPhotos: [GroupingPhoto]
    let revision: GroupingInputRevision

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photosDir = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let access = FolderAccess(
            store: RecentFolderStore(fileURL: root.appendingPathComponent("recents.json")))
        guard case .opened(let opened) = await access.pick(photosDir) else {
            throw CocoaError(.fileNoSuchFile)
        }
        session = opened.session
        folderID = opened.session.folder.id

        let firstURL = photosDir.appendingPathComponent("a.jpg")
        let secondURL = photosDir.appendingPathComponent("b.jpg")
        try Self.writeJPEG(to: firstURL, gray: 0.2)
        try Self.writeJPEG(to: secondURL, gray: 0.8)

        let firstSet = try PhotoSet(
            folderID: folderID, relativeFolderPath: "", jpegURL: firstURL)
        let secondSet = try PhotoSet(
            folderID: folderID, relativeFolderPath: "", jpegURL: secondURL)
        sets = [firstSet.id: firstSet, secondSet.id: secondSet]

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        groupingPhotos = [
            GroupingPhoto(
                id: firstSet.id,
                fileName: firstSet.primary.url.lastPathComponent,
                time: .known(PhotoTime(captureTime: base, hasUTCOffset: true)),
                cameraModel: "TestCam"),
            GroupingPhoto(
                id: secondSet.id,
                fileName: secondSet.primary.url.lastPathComponent,
                time: .known(
                    PhotoTime(captureTime: base.addingTimeInterval(0.2), hasUTCOffset: true)),
                cameraModel: "TestCam"),
        ]
        revision = GroupingInputRevision(rawValue: "test-revision")

        groupCache = SimilarGroupsCache(directory: root.appendingPathComponent("groups"))
        coldFeatures = try ImageFeatureCache(
            directory: root.appendingPathComponent("cold-features"))
        coldThumbnails = try ThumbnailCache(
            directory: root.appendingPathComponent("cold-thumbs"))
        warmFeatureDirectory = root.appendingPathComponent("warm-features")
        warmFeatures = try ImageFeatureCache(directory: warmFeatureDirectory)
        warmThumbnails = try ThumbnailCache(
            directory: root.appendingPathComponent("warm-thumbs"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    static func makeGrayImage(gray: CGFloat) -> CGImage {
        let width = 128
        let height = 128
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func writeJPEG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    private static func writeJPEG(to url: URL, gray: CGFloat) throws {
        try writeJPEG(makeGrayImage(gray: gray), to: url)
    }
}

private actor GatedPreviewReader: ImageFeaturePreviewReading {
    private let images: [String: CGImage]
    private var heldNames: Set<String>
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startedNames: [String] = []

    init(images: [String: CGImage], heldNames: Set<String>) {
        self.images = images
        self.heldNames = heldNames
    }

    func preview(for request: ThumbnailRequest) async -> ImageFeaturePreviewRead {
        let name = request.source.lastPathComponent
        startedNames.append(name)
        if heldNames.contains(name) {
            await withCheckedContinuation { waiters.append($0) }
        }
        guard let image = images[name] else { return .unavailable(.cannotOpen) }
        return .preview(ImageFeaturePreview(image: image, route: .ifAbsent))
    }

    func releaseHeld() {
        heldNames.removeAll()
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct DeterministicFeaturePrintReader: FeaturePrintReading {
    let revision = VisionFeaturePrintReader.requestRevision

    func featurePrint(of image: CGImage) async -> Result<VisionFeaturePrint, FeatureFailure> {
        var sample: UInt8 = 0
        withUnsafeMutableBytes(of: &sample) { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let value = Float(sample) / 255
        return .success(
            VisionFeaturePrint(revision: revision, elements: [value, value, value, value]))
    }
}
