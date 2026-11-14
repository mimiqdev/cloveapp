import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import CloveImaging

/// Tests for the app-private sharpness disk tier (#239):
/// - session-free disk keys across folder reopens,
/// - revision / parametersVersion / payloadVersion invalidation,
/// - LRU byte-budget eviction,
/// - refusal to persist `staleSource` and contention outcomes,
/// - reopening a folder serves disk hits with zero analysis jobs scheduled.
@Suite(.serialized)
struct RegionSharpnessCacheTests {
    private static let baseRevision = ThumbnailRevision(
        size: 24_000_000, modificationTime: Date(timeIntervalSince1970: 1_700_000_000))

    private final class TempCacheDirectory {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "clove-sharpness-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var cacheURL: URL { root.appendingPathComponent("RegionSharpness", isDirectory: true) }

        func makeCache(
            configuration: RegionSharpnessCache.Configuration = .init()
        ) throws -> RegionSharpnessCache {
            try RegionSharpnessCache(directory: cacheURL, configuration: configuration)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class CountingReader: RegionSharpnessReading, @unchecked Sendable {
        private struct Counts {
            var properties = 0
            var preview = 0
        }

        private let lock = Mutex(Counts())
        var propertiesAnswer: ImageProperties? = ImageProperties([
            "{ExifAux}": ["AFInfo": [0.25, 0.25, 0.1, 0.1, "f"]]
        ])
        var previewResult: Result<CGImage, RegionImageFailure> = .success(
            SharpnessScene.flat(width: 64, height: 48))

        func properties(of url: URL) async -> ImageProperties? {
            lock.withLock { $0.properties += 1 }
            return propertiesAnswer
        }

        func preview(
            _ request: RegionSharpnessRequest
        ) async -> Result<CGImage, RegionImageFailure> {
            lock.withLock { $0.preview += 1 }
            return previewResult
        }

        var totalCalls: Int {
            lock.withLock { $0.properties + $0.preview }
        }
    }

    private final class CountingFaceDetector: FaceRegionDetecting, @unchecked Sendable {
        private let count = Mutex(0)
        var outcome: FaceDetectionOutcome = .faces([
            DetectedFaceRegion(
                face: NormalizedRegion(x: 0.3, y: 0.3, width: 0.25, height: 0.25),
                leftEye: NormalizedRegion(x: 0.35, y: 0.36, width: 0.04, height: 0.04),
                rightEye: NormalizedRegion(x: 0.45, y: 0.36, width: 0.04, height: 0.04))
        ])

        func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
            count.withLock { $0 += 1 }
            return outcome
        }

        var callCount: Int { count.withLock { $0 } }
    }

    private func makeKey(
        _ name: String = "MMQ00001.ARW",
        session: String = "session-1",
        revision: ThumbnailRevision = RegionSharpnessCacheTests.baseRevision,
        parametersVersion: Int = 1
    ) -> SharpnessResultKey {
        SharpnessResultKey(
            folderSession: session,
            photo: URL(fileURLWithPath: "/photos/\(name)"),
            revision: revision,
            parametersVersion: parametersVersion)
    }

    private func makeRequest(
        _ name: String = "MMQ00001.ARW",
        session: String = "session-1",
        revision: ThumbnailRevision = RegionSharpnessCacheTests.baseRevision
    ) -> RegionSharpnessRequest {
        RegionSharpnessRequest(
            raw: DetailSource(
                url: URL(fileURLWithPath: "/photos/\(name)"),
                revision: revision),
            locationIdentity: session)
    }

    private func sampleAnalysis(
        acquisitionFailure: RegionImageFailure? = nil,
        previewFailure: RegionImageFailure? = nil
    ) -> RegionSharpnessAnalysis {
        let afRegion = RegionSharpnessEvidence(
            kind: .cameraAutofocus,
            groupIndex: nil,
            region: NormalizedRegion(x: 0.2, y: 0.3, width: 0.1, height: 0.1),
            score: RegionSharpnessScore(
                tenengradMeanSquare: 142.5, sampledPixels: 2500, sampledWidth: 50,
                sampledHeight: 50),
            unavailableBecause: nil)
        let faceRegion = RegionSharpnessEvidence(
            kind: .face,
            groupIndex: 0,
            region: NormalizedRegion(x: 0.4, y: 0.2, width: 0.25, height: 0.3),
            score: RegionSharpnessScore(
                tenengradMeanSquare: 98.25, sampledPixels: 6400, sampledWidth: 80,
                sampledHeight: 80),
            unavailableBecause: nil)
        let eyeRegion = RegionSharpnessEvidence(
            kind: .eye,
            groupIndex: 0,
            region: NormalizedRegion(x: 0.45, y: 0.26, width: 0.05, height: 0.05),
            score: nil,
            unavailableBecause: .regionTooSmall)
        let facesPath: RegionSharpnessPathResult =
            if let previewFailure {
                .unavailable(.previewFailed(previewFailure))
            } else {
                .regions([faceRegion, eyeRegion])
            }
        let timings = RegionSharpnessTimings(
            metadataRead: .milliseconds(3),
            previewRead: .milliseconds(8),
            faceDetection: .milliseconds(35),
            pixelAcquisition: .milliseconds(12),
            regionScoring: .milliseconds(4))
        return RegionSharpnessAnalysis(
            autofocus: .regions([afRegion]),
            faces: facesPath,
            acquisitionFailure: acquisitionFailure,
            timings: timings)
    }

    @Test func persistAndNewSessionHitIgnoringFolderSession() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let analysis = sampleAnalysis()
        let sessionOneKey = makeKey(session: "session-alpha")
        let sessionTwoKey = makeKey(session: "session-beta")

        let cache = try dir.makeCache()
        try cache.store(analysis, for: sessionOneKey)

        // Reopen with a new cache instance and a different folder session.
        let reopened = try dir.makeCache()
        let loaded = try #require(reopened.analysis(for: sessionTwoKey))
        #expect(loaded == analysis)

        // Standardized path spelling matches too.
        let unstandardizedKey = SharpnessResultKey(
            folderSession: "session-gamma",
            photo: URL(fileURLWithPath: "/photos/sub/../MMQ00001.ARW"),
            revision: Self.baseRevision,
            parametersVersion: 1)
        #expect(reopened.analysis(for: unstandardizedKey) == analysis)

        // ResultStore promotes disk hits into memory under the caller's session-bound key, while
        // keeping memory isolated per folderSession.
        let store1 = RegionSharpnessResultStore(capacity: 16, disk: reopened)
        let store2 = RegionSharpnessResultStore(capacity: 16, disk: reopened)
        #expect(store1.result(for: sessionOneKey) == analysis)
        #expect(store1.memoryResult(for: sessionTwoKey) == nil)
        #expect(store2.result(for: sessionTwoKey) == analysis)
        #expect(store2.memoryResult(for: sessionTwoKey) == analysis)

        // Memory answers even after disk files are deleted; releaseMemory drops only memory.
        try reopened.clear()
        #expect(store2.result(for: sessionTwoKey) == analysis)
        store2.releaseMemory()
        #expect(store2.result(for: sessionTwoKey) == nil)
    }

    @Test func revisionChangeIsAMiss() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let cache = try dir.makeCache()
        try cache.store(sampleAnalysis(), for: makeKey(session: "s1"))

        let changedSize = makeKey(
            session: "s2",
            revision: ThumbnailRevision(
                size: Self.baseRevision.size + 1,
                modificationTime: Self.baseRevision.modificationTime))
        let changedMTime = makeKey(
            session: "s2",
            revision: ThumbnailRevision(
                size: Self.baseRevision.size,
                modificationTime: Self.baseRevision.modificationTime.addingTimeInterval(0.25)))

        let reopened = try dir.makeCache()
        #expect(reopened.analysis(for: changedSize) == nil)
        #expect(reopened.analysis(for: changedMTime) == nil)
    }

    @Test func parametersAndPayloadVersionInvalidation() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let cacheV1 = try dir.makeCache()
        try cacheV1.store(sampleAnalysis(), for: makeKey(session: "s1", parametersVersion: 1))

        #expect(cacheV1.analysis(for: makeKey(session: "s2", parametersVersion: 1)) != nil)
        #expect(cacheV1.analysis(for: makeKey(session: "s2", parametersVersion: 2)) == nil)

        var configV2 = RegionSharpnessCache.Configuration()
        configV2.payloadVersion = 2
        let cachePayloadV2 = try dir.makeCache(configuration: configV2)
        #expect(cachePayloadV2.analysis(for: makeKey(session: "s2", parametersVersion: 1)) == nil)
    }

    @Test func budgetEvictionEvictsLeastRecentlyUsed() async throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let probe = try dir.makeCache()
        let payload = sampleAnalysis()
        try probe.store(payload, for: makeKey("probe.ARW"))
        let singleRecordBytes = probe.diskByteCount
        #expect(singleRecordBytes > 200)
        #expect(singleRecordBytes < 4_096)

        // Allow room for 2 records, not 3.
        var config = RegionSharpnessCache.Configuration()
        config.diskBytes = singleRecordBytes * 2 + 64
        let budgetedDir = dir.root.appendingPathComponent("Budgeted", isDirectory: true)
        let budgeted = try RegionSharpnessCache(directory: budgetedDir, configuration: config)

        let keyA = makeKey("a.ARW")
        let keyB = makeKey("b.ARW")
        let keyC = makeKey("c.ARW")

        try budgeted.store(payload, for: keyA)
        try await Task.sleep(for: .milliseconds(20))
        try budgeted.store(payload, for: keyB)
        #expect(budgeted.diskEntryCount == 2)

        // Touch A so B becomes least recently used.
        try await Task.sleep(for: .milliseconds(20))
        #expect(budgeted.analysis(for: keyA) != nil)

        try await Task.sleep(for: .milliseconds(20))
        try budgeted.store(payload, for: keyC)

        #expect(budgeted.diskByteCount <= config.diskBytes)
        #expect(budgeted.diskEntryCount == 2)

        // Verify persistence after reopen.
        let reopened = try RegionSharpnessCache(directory: budgetedDir, configuration: config)
        #expect(reopened.analysis(for: keyA) != nil)
        #expect(reopened.analysis(for: keyB) == nil)
        #expect(reopened.analysis(for: keyC) != nil)

        // Reopening with a smaller budget trims oldest entries during init.
        var tighterConfig = RegionSharpnessCache.Configuration()
        tighterConfig.diskBytes = singleRecordBytes + 64
        let trimmed = try RegionSharpnessCache(directory: budgetedDir, configuration: tighterConfig)
        #expect(trimmed.diskByteCount <= tighterConfig.diskBytes)
        #expect(trimmed.diskEntryCount == 1)
        #expect(trimmed.analysis(for: keyA) == nil)
        #expect(trimmed.analysis(for: keyC) != nil)
    }

    @Test func noAutofocusMetadataEvidenceRoundTripsCleanly() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let evidence = AutofocusMetadataEvidence(
            inspected: [
                .init(path: "{ExifAux}.AFInfo", finding: .missing),
                .init(path: "MakerNote.0x2027", finding: .unreadable("empty tag")),
            ],
            cameraMake: "SONY",
            exifOrientation: 6)
        let analysis = RegionSharpnessAnalysis(
            autofocus: .unavailable(.noAutofocusMetadata(evidence)),
            faces: .unavailable(.noFacesDetected),
            acquisitionFailure: nil,
            timings: RegionSharpnessTimings(metadataRead: .milliseconds(2)))
        let key = makeKey("noaf.ARW", session: "s1")
        let cache = try dir.makeCache()
        try cache.store(analysis, for: key)

        let reopened = try dir.makeCache()
        #expect(reopened.analysis(for: makeKey("noaf.ARW", session: "s2")) == analysis)
    }

    @Test func staleSourceAndContentionNeverPersisted() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let cache = try dir.makeCache()
        try cache.store(sampleAnalysis(acquisitionFailure: .staleSource), for: makeKey("stale.ARW"))
        try cache.store(sampleAnalysis(acquisitionFailure: .queueFull), for: makeKey("full.ARW"))
        try cache.store(sampleAnalysis(acquisitionFailure: .closed), for: makeKey("closed.ARW"))
        try cache.store(
            sampleAnalysis(previewFailure: .staleSource), for: makeKey("stale-preview.ARW"))

        #expect(cache.diskEntryCount == 0)
        #expect(cache.diskByteCount == 0)
        #expect(cache.analysis(for: makeKey("stale.ARW")) == nil)
        #expect(cache.analysis(for: makeKey("full.ARW")) == nil)
        #expect(cache.analysis(for: makeKey("closed.ARW")) == nil)
        #expect(cache.analysis(for: makeKey("stale-preview.ARW")) == nil)

        // Real photo facts (e.g. unreadable / no usable preview) are persisted.
        try cache.store(
            sampleAnalysis(acquisitionFailure: .cannotOpen), for: makeKey("unreadable.ARW"))
        #expect(cache.diskEntryCount == 1)
        #expect(cache.analysis(for: makeKey("unreadable.ARW")) != nil)
    }

    @Test func corruptFileIsRemovedAndStagingFilesCleanedOnInit() throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let cache = try dir.makeCache()
        let key = makeKey("corrupt.ARW")
        try cache.store(sampleAnalysis(), for: key)
        #expect(cache.diskEntryCount == 1)

        let files = try FileManager.default.contentsOfDirectory(
            at: dir.cacheURL, includingPropertiesForKeys: nil)
        for file in files {
            try Data("corrupt json".utf8).write(to: file)
        }
        // Leftover staging file should be swept on init.
        let staging = dir.cacheURL.appendingPathComponent("orphan.staging")
        try Data("partial".utf8).write(to: staging)

        let reopened = try dir.makeCache()
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(reopened.analysis(for: key) == nil)
        #expect(reopened.diskByteCount == 0)
        #expect(reopened.diskEntryCount == 0)

        try reopened.store(sampleAnalysis(), for: key)
        #expect(reopened.analysis(for: key) != nil)
    }

    @Test func schedulerReopenServesDiskHitsWithoutSchedulingJobs() async throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let firstReader = CountingReader()
        let firstDetector = CountingFaceDetector()
        let firstCache = try dir.makeCache()
        let firstScheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: firstReader, faces: firstDetector),
            results: RegionSharpnessResultStore(capacity: 64, disk: firstCache),
            parametersVersion: 1)

        let currentS1 = makeRequest("current.ARW", session: "open-1")
        let nearbyS1 = makeRequest("nearby.ARW", session: "open-1")

        let firstResult = await firstScheduler.analyzeCurrent(currentS1)
        await firstScheduler.submit([nearbyS1], priority: .nearby)
        // Wait for background job to finish by joining it.
        let nearbyFirstResult = await firstScheduler.analyzeCurrent(nearbyS1)
        #expect(firstResult != nil)
        #expect(nearbyFirstResult != nil)
        #expect(firstReader.totalCalls > 0)
        #expect(firstDetector.callCount == 2)
        await firstScheduler.close()

        // Reopen the folder in a fresh session with an empty memory tier and fresh dependencies.
        let secondReader = CountingReader()
        let secondDetector = CountingFaceDetector()
        let reopenedCache = try dir.makeCache()
        let secondScheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: secondReader, faces: secondDetector),
            results: RegionSharpnessResultStore(capacity: 64, disk: reopenedCache),
            parametersVersion: 1)

        let currentS2 = makeRequest("current.ARW", session: "open-2")
        let nearbyS2 = makeRequest("nearby.ARW", session: "open-2")

        let earlyAF = Mutex<RegionSharpnessPathResult?>(nil)
        let reopenedCurrent = await secondScheduler.analyzeCurrent(currentS2) { result in
            earlyAF.withLock { $0 = result }
        }
        await secondScheduler.submit([nearbyS2], priority: .nearby)
        let reopenedNearby = await secondScheduler.analyzeCurrent(nearbyS2)

        #expect(reopenedCurrent == firstResult)
        #expect(reopenedNearby == nearbyFirstResult)
        #expect(earlyAF.withLock { $0 } == firstResult?.autofocus)
        #expect(secondReader.totalCalls == 0)
        #expect(secondDetector.callCount == 0)

        let snapshot = await secondScheduler.snapshot()
        for stage in SharpnessAnalysisStage.allCases {
            #expect(snapshot.stages[stage]?.startedCount == 0)
        }
        await secondScheduler.close()
    }

    @Test func schedulerDoesNotPersistStaleSourceAndRerunsOnReopen() async throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let staleReader = CountingReader()
        staleReader.previewResult = .failure(.staleSource)
        let detector1 = CountingFaceDetector()
        let cache1 = try dir.makeCache()
        let scheduler1 = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: staleReader, faces: detector1),
            results: RegionSharpnessResultStore(capacity: 64, disk: cache1),
            parametersVersion: 1)

        let staleResult = await scheduler1.analyzeCurrent(
            makeRequest("race.ARW", session: "open-1"))
        #expect(staleResult?.faces == .unavailable(.previewFailed(.staleSource)))
        #expect(cache1.diskEntryCount == 0)
        await scheduler1.close()

        // Reopen with a healthy reader: must not serve staleSource from disk, must run analysis.
        let healthyReader = CountingReader()
        let detector2 = CountingFaceDetector()
        let cache2 = try dir.makeCache()
        let scheduler2 = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: healthyReader, faces: detector2),
            results: RegionSharpnessResultStore(capacity: 64, disk: cache2),
            parametersVersion: 1)

        let freshResult = await scheduler2.analyzeCurrent(
            makeRequest("race.ARW", session: "open-2"))
        #expect(freshResult?.acquisitionFailure == nil)
        if case .regions = freshResult?.faces {
        } else {
            Issue.record("Expected located face regions after healthy reopen")
        }
        #expect(healthyReader.totalCalls > 0)
        #expect(cache2.diskEntryCount == 1)
        await scheduler2.close()
    }

    @Test func schedulerRevisionChangeAndParametersBumpInvalidateDiskHits() async throws {
        let dir = try TempCacheDirectory()
        defer { dir.remove() }

        let reader1 = CountingReader()
        let detector1 = CountingFaceDetector()
        let cache1 = try dir.makeCache()
        let scheduler1 = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader1, faces: detector1),
            results: RegionSharpnessResultStore(capacity: 64, disk: cache1),
            parametersVersion: 1)

        _ = await scheduler1.analyzeCurrent(makeRequest("photo.ARW", session: "open-1"))
        await scheduler1.close()

        // Revision change in new session -> miss and re-analyze.
        let reader2 = CountingReader()
        let detector2 = CountingFaceDetector()
        let cache2 = try dir.makeCache()
        let scheduler2 = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader2, faces: detector2),
            results: RegionSharpnessResultStore(capacity: 64, disk: cache2),
            parametersVersion: 1)

        let updatedRev = ThumbnailRevision(
            size: Self.baseRevision.size + 1024,
            modificationTime: Self.baseRevision.modificationTime)
        _ = await scheduler2.analyzeCurrent(
            makeRequest("photo.ARW", session: "open-2", revision: updatedRev))
        #expect(reader2.totalCalls > 0)
        await scheduler2.close()

        // Parameters version bump in new session -> miss and re-analyze.
        let reader3 = CountingReader()
        let detector3 = CountingFaceDetector()
        let cache3 = try dir.makeCache()
        let scheduler3 = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader3, faces: detector3),
            results: RegionSharpnessResultStore(capacity: 64, disk: cache3),
            parametersVersion: 2)

        _ = await scheduler3.analyzeCurrent(makeRequest("photo.ARW", session: "open-3"))
        #expect(reader3.totalCalls > 0)
        await scheduler3.close()
    }
}
