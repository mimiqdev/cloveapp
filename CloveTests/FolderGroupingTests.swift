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

        var coldProgress: [FolderGroupingProgress] = []
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
            progressChanged: { progress in coldProgress.append(progress) })

        await coldGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil {
            coldProgress.contains { $0.isAnalyzing } && coldProgress.last == .complete
        }
        #expect(coldProgress.first == .analyzing(completed: 0, total: 2))
        #expect(coldProgress.contains(.analyzing(completed: 1, total: 2)))
        #expect(coldProgress.contains(.analyzing(completed: 2, total: 2)))
        #expect(coldSetsLookups == fixture.groupingPhotos.count)
        let finishedCold = try #require(coldPublished.last)
        await coldGrouping.close()

        // Reopen with the same SimilarGroupsCache but empty feature and preview caches.
        var warmProgress: [FolderGroupingProgress] = []
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
            progressChanged: { progress in warmProgress.append(progress) })

        await warmGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        // Yield briefly to verify no background analysis task was scheduled.
        try await Task.sleep(for: .milliseconds(50))

        #expect(warmPublished.last == finishedCold)
        #expect(!warmProgress.contains { $0.isAnalyzing })
        #expect(warmProgress == [.complete])
        #expect(warmSetsLookups == 0)
        let warmFeatureFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.warmFeatureDirectory, includingPropertiesForKeys: nil)
        #expect(warmFeatureFiles.filter { $0.pathExtension == "feature" }.isEmpty)

        // Calling Run again after a warm hit must bypass the cache and re-analyze.
        await warmGrouping.runAgain(photos: fixture.groupingPhotos)
        try await waitUntil {
            warmProgress.contains { $0.isAnalyzing } && warmProgress.last == .complete
        }
        #expect(warmProgress.contains(.analyzing(completed: 0, total: 2)))
        #expect(warmSetsLookups == fixture.groupingPhotos.count)
        await warmGrouping.close()
        await fixture.session.end()
    }

    @Test func changedThresholdsAfterWarmHitTriggersAnalysis() async throws {
        let fixture = try await GroupingTestWorkspace()
        defer { fixture.remove() }

        var coldProgress: [FolderGroupingProgress] = []
        let coldGrouping = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.coldFeatures,
            previewCache: fixture.coldThumbnails,
            sets: { fixture.sets[$0] },
            publish: { _ in },
            progressChanged: { coldProgress.append($0) })

        await coldGrouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil {
            coldProgress.contains { $0.isAnalyzing } && coldProgress.last == .complete
        }
        await coldGrouping.close()

        var recalibratedProgress: [FolderGroupingProgress] = []
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
            progressChanged: { recalibratedProgress.append($0) })

        await recalibrated.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await waitUntil {
            recalibratedProgress.contains { $0.isAnalyzing }
                && recalibratedProgress.last == .complete
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
        var progressHistory: [FolderGroupingProgress] = []
        let grouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            featurePipeline: pipeline,
            sets: { sets[$0] },
            publish: { published.append($0) },
            progressChanged: { progressHistory.append($0) })

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
        #expect(progressHistory.first == .analyzing(completed: 0, total: 5))
        #expect(progressHistory.last?.isAnalyzing == true)
        let started = await gate.startedNames
        #expect(Set(started.prefix(4)).isSuperset(of: ["a.jpg", "b.jpg", "c.jpg"]))

        await gate.releaseHeld()
        try await waitUntil {
            progressHistory.contains { $0.isAnalyzing } && progressHistory.last == .complete
        }
        #expect(progressHistory.contains(.analyzing(completed: 5, total: 5)))
        #expect(
            published.last?.map(\.members) == [
                [groupingPhotos[1].id, groupingPhotos[2].id],
                [groupingPhotos[3].id, groupingPhotos[4].id],
            ])

        await grouping.close()
        await session.end()
    }

    @Test func timeOnlyModeGroupsImmediatelyWithoutFeatureExtraction() async throws {
        let fixture = try await GroupingTestWorkspace()
        defer { fixture.remove() }

        var progressHistory: [FolderGroupingProgress] = []
        var setsLookups = 0
        var published: [[BrowsingGroup]] = []
        let timeOnly = GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .timeOnly)
        let grouping = FolderGrouping(
            folder: fixture.folderID,
            session: fixture.session,
            cache: fixture.groupCache,
            featureCache: fixture.warmFeatures,
            previewCache: fixture.warmThumbnails,
            thresholds: timeOnly,
            sets: { id in
                setsLookups += 1
                return fixture.sets[id]
            },
            publish: { published.append($0) },
            progressChanged: { progressHistory.append($0) })

        await grouping.begin(
            photos: fixture.groupingPhotos, revision: fixture.revision, enabled: true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(published.last?.map(\.members) == [fixture.groupingPhotos.map(\.id)])
        #expect(!progressHistory.contains { $0.isAnalyzing })
        #expect(progressHistory == [.complete])
        #expect(setsLookups == 0)
        let featureFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.warmFeatureDirectory, includingPropertiesForKeys: nil)
        #expect(featureFiles.filter { $0.pathExtension == "feature" }.isEmpty)

        await grouping.close()
        await fixture.session.end()
    }

    @Test func updatingThresholdsRecomputesImmediatelyAndReusesCachedFeatures() async throws {
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

        // a (gray 0.0) and b (gray 0.21) are 0.2s apart:
        // DeterministicFeaturePrintReader produces Euclidean distance ~0.42 between 0.0 and 0.21,
        // which joins at standard (0.5) and splits at tight (0.35).
        // c (gray 1.0) is 3.5s after b (so outside 2s, inside 5s) and visually far from b.
        let names = ["a.jpg", "b.jpg", "c.jpg"]
        let grays: [CGFloat] = [0.0, 0.21, 1.0]
        let timestamps: [TimeInterval] = [0.0, 0.2, 3.7]
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

        let previewReader = GatedPreviewReader(images: imagesByName, heldNames: [])
        let featureCache = try ImageFeatureCache(
            directory: root.appendingPathComponent("features"))
        let previewCache = try ThumbnailCache(
            directory: root.appendingPathComponent("thumbs"))
        let groupCache = SimilarGroupsCache(directory: root.appendingPathComponent("groups"))
        let pipeline = ImageFeaturePipeline(
            cache: featureCache, previews: previewReader, prints: DeterministicFeaturePrintReader(),
            workers: 2)

        var published: [[BrowsingGroup]] = []
        var progressHistory: [FolderGroupingProgress] = []
        let grouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            thresholds: .standard,
            featurePipeline: pipeline,
            sets: { sets[$0] },
            publish: { published.append($0) },
            progressChanged: { progressHistory.append($0) })

        // Standard (2s, 0.5): a & b join; c is outside 2s.
        await grouping.begin(
            photos: groupingPhotos,
            revision: GroupingInputRevision(rawValue: "dynamic-thresholds"),
            enabled: true)
        try await waitUntil {
            progressHistory.contains { $0.isAnalyzing } && progressHistory.last == .complete
        }
        #expect(published.last?.map(\.members) == [[groupingPhotos[0].id, groupingPhotos[1].id]])
        let previewsAfterStandard = await previewReader.startedNames.count
        #expect(previewsAfterStandard == 2)

        // Tight (2s, 0.35): splits a & b without decoding previews again (reuses cached features).
        progressHistory.removeAll()
        await grouping.setThresholds(
            GroupingThresholds(timeWindow: .twoSeconds, sensitivity: .tight),
            photos: groupingPhotos)
        try await waitUntil {
            progressHistory.contains { $0.isAnalyzing } && progressHistory.last == .complete
        }
        #expect(published.last?.isEmpty == true)
        #expect(await previewReader.startedNames.count == previewsAfterStandard)

        // Time-only (5s): joins a, b, and c immediately with zero visual analysis or preview reads.
        progressHistory.removeAll()
        await grouping.setThresholds(
            GroupingThresholds(timeWindow: .fiveSeconds, sensitivity: .timeOnly),
            photos: groupingPhotos)
        try await Task.sleep(for: .milliseconds(50))
        #expect(
            published.last?.map(\.members) == [
                [groupingPhotos[0].id, groupingPhotos[1].id, groupingPhotos[2].id]
            ])
        #expect(!progressHistory.contains { $0.isAnalyzing })
        #expect(progressHistory == [.complete])
        #expect(await previewReader.startedNames.count == previewsAfterStandard)

        await grouping.close()
        await session.end()
    }

    @Test func disabledOrClosedMidAnalysisEmitsIdleWithoutComplete() async throws {
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

        let names = ["a.jpg", "b.jpg"]
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sets: [PhotoIdentity: PhotoSet] = [:]
        var groupingPhotos: [GroupingPhoto] = []
        var imagesByName: [String: CGImage] = [:]
        for (index, name) in names.enumerated() {
            let fileURL = photosDir.appendingPathComponent(name)
            let image = GroupingTestWorkspace.makeGrayImage(gray: 0.3)
            try GroupingTestWorkspace.writeJPEG(image, to: fileURL)
            imagesByName[name] = image
            let set = try PhotoSet(folderID: folderID, relativeFolderPath: "", jpegURL: fileURL)
            sets[set.id] = set
            groupingPhotos.append(
                GroupingPhoto(
                    id: set.id,
                    fileName: name,
                    time: .known(
                        PhotoTime(
                            captureTime: base.addingTimeInterval(Double(index) * 0.2),
                            hasUTCOffset: true)),
                    cameraModel: "TestCam"))
        }

        // 1. Disabled grouping emits .idle without .analyzing or .complete.
        let featureCache = try ImageFeatureCache(
            directory: root.appendingPathComponent("features"))
        let previewCache = try ThumbnailCache(
            directory: root.appendingPathComponent("thumbs"))
        let groupCache = SimilarGroupsCache(directory: root.appendingPathComponent("groups"))
        let disabledPipeline = ImageFeaturePipeline(
            cache: featureCache,
            previews: GatedPreviewReader(images: imagesByName, heldNames: ["b.jpg"]),
            prints: DeterministicFeaturePrintReader(),
            workers: 2)
        var disabledProgress: [FolderGroupingProgress] = []
        let disabledGrouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            featurePipeline: disabledPipeline,
            sets: { sets[$0] },
            publish: { _ in },
            progressChanged: { disabledProgress.append($0) })
        await disabledGrouping.begin(
            photos: groupingPhotos,
            revision: GroupingInputRevision(rawValue: "disabled"),
            enabled: false)
        #expect(disabledProgress == [.idle])

        // 2. Enabling starts analysis; closing mid-analysis emits .idle and never .complete.
        disabledProgress.removeAll()
        let closeGate = GatedPreviewReader(images: imagesByName, heldNames: ["b.jpg"])
        let closePipeline = ImageFeaturePipeline(
            cache: featureCache,
            previews: closeGate,
            prints: DeterministicFeaturePrintReader(),
            workers: 2)
        let closeGrouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            featurePipeline: closePipeline,
            sets: { sets[$0] },
            publish: { _ in },
            progressChanged: { disabledProgress.append($0) })
        await closeGrouping.begin(
            photos: groupingPhotos,
            revision: GroupingInputRevision(rawValue: "close-mid-analysis"),
            enabled: true)
        try await waitUntil {
            disabledProgress.contains(.analyzing(completed: 1, total: 2))
        }
        try await waitUntil { await closeGate.waiterCount == 1 }
        let closeTask = Task { await closeGrouping.close() }
        try await Task.sleep(for: .milliseconds(20))
        await closeGate.releaseHeld()
        await closeTask.value
        await disabledGrouping.close()
        #expect(!disabledProgress.contains(.complete))
        #expect(disabledProgress.last == .idle)
        await session.end()
    }

    @Test func tenCandidateBatchEmitsMonotonicThrottledProgressToCompletion() async throws {
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

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var sets: [PhotoIdentity: PhotoSet] = [:]
        var groupingPhotos: [GroupingPhoto] = []
        var imagesByName: [String: CGImage] = [:]
        for index in 0..<10 {
            let name = String(format: "burst_%02d.jpg", index)
            let fileURL = photosDir.appendingPathComponent(name)
            let image = GroupingTestWorkspace.makeGrayImage(gray: 0.4)
            try GroupingTestWorkspace.writeJPEG(image, to: fileURL)
            imagesByName[name] = image
            let set = try PhotoSet(folderID: folderID, relativeFolderPath: "", jpegURL: fileURL)
            sets[set.id] = set
            groupingPhotos.append(
                GroupingPhoto(
                    id: set.id,
                    fileName: name,
                    time: .known(
                        PhotoTime(
                            captureTime: base.addingTimeInterval(Double(index) * 0.2),
                            hasUTCOffset: true)),
                    cameraModel: "TestCam"))
        }

        let featureCache = try ImageFeatureCache(
            directory: root.appendingPathComponent("features"))
        let previewCache = try ThumbnailCache(
            directory: root.appendingPathComponent("thumbs"))
        let groupCache = SimilarGroupsCache(directory: root.appendingPathComponent("groups"))
        let pipeline = ImageFeaturePipeline(
            cache: featureCache,
            previews: GatedPreviewReader(images: imagesByName, heldNames: []),
            prints: DeterministicFeaturePrintReader(),
            workers: 2)

        var progressHistory: [FolderGroupingProgress] = []
        let grouping = FolderGrouping(
            folder: folderID,
            session: session,
            cache: groupCache,
            featureCache: featureCache,
            previewCache: previewCache,
            featurePipeline: pipeline,
            sets: { sets[$0] },
            publish: { _ in },
            progressChanged: { progressHistory.append($0) })

        await grouping.begin(
            photos: groupingPhotos,
            revision: GroupingInputRevision(rawValue: "ten-burst"),
            enabled: true)
        try await waitUntil { progressHistory.last == .complete }

        let analyzingCounts = progressHistory.compactMap { progress -> Int? in
            guard case .analyzing(let completed, let total) = progress else { return nil }
            #expect(total == 10)
            return completed
        }
        #expect(analyzingCounts.first == 0)
        #expect(analyzingCounts.contains(1))
        #expect(analyzingCounts.last == 10)
        #expect(analyzingCounts == analyzingCounts.sorted())
        #expect(Set(analyzingCounts).count == analyzingCounts.count)
        #expect(progressHistory.last == .complete)

        await grouping.close()
        await session.end()
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
    var waiterCount: Int { waiters.count }

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
