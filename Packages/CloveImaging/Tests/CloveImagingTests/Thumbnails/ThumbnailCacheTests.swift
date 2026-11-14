import Foundation
import Testing

@testable import CloveImaging

actor ThumbnailCacheTests {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.ThumbnailCacheStorage")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    @Test func memoryAndPersistentDiskHitsPreserveRouteAndDimensions() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image(orientation: 6))
        let result = ThumbnailExtractor().extract(request)
        let cache = try directory.cache()
        try cache.store(result, for: request)
        let memory = try availableThumbnail(#require(cache.result(for: request)))
        #expect(memory.height == 400 && memory.width == 267)
        cache.releaseMemory()
        let disk = try availableThumbnail(#require(cache.result(for: request)))
        #expect(
            disk.route == memory.route && disk.width == memory.width && disk.height == memory.height
        )
        let reopened = try directory.cache()
        #expect(reopened.result(for: request) != nil)
    }

    @Test func revisionRouteVersionAndLocationInvalidate() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let cache = try directory.cache()
        try cache.store(ThumbnailExtractor().extract(request), for: request)
        func changed(
            size: Int64? = nil, date: Date? = nil, location: String? = nil,
            pixels: Int = 400
        ) -> ThumbnailRequest {
            ThumbnailRequest(
                source: request.source,
                revision: .init(
                    size: size ?? request.revision.size,
                    modificationTime: date ?? request.revision.modificationTime),
                targetPixels: pixels, locationIdentity: location ?? request.locationIdentity)
        }
        #expect(cache.result(for: changed(size: request.revision.size + 1)) == nil)
        #expect(
            cache.result(
                for: changed(date: request.revision.modificationTime.addingTimeInterval(0.001)))
                == nil)
        #expect(cache.result(for: changed(location: "another-card")) == nil)
        #expect(cache.result(for: changed(pixels: 200)) == nil)
        let newer = try directory.cache(version: 2)
        #expect(newer.result(for: request) == nil)
        let base = ThumbnailCacheKey(request: request, route: .embeddedOnly, version: 1).digest
        #expect(base != ThumbnailCacheKey(request: request, route: .always, version: 1).digest)
        #expect(base != ThumbnailCacheKey(request: request, route: .ifAbsent, version: 1).digest)
        let other = ThumbnailRequest(
            source: directory.url.appendingPathComponent("other.jpg"),
            revision: request.revision, locationIdentity: request.locationIdentity)
        #expect(cache.result(for: other) == nil)
    }

    @Test func memoryCostEvictionAndPressureRelease() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let first = try thumbnailRequest(directory.image(name: "first.jpg"))
        let second = try thumbnailRequest(directory.image(name: "second.jpg"))
        let third = try thumbnailRequest(directory.image(name: "third.jpg"))
        let result = ThumbnailExtractor().extract(first)
        let cost = try availableThumbnail(result).decodedBytes
        let cache = try directory.cache(memory: cost * 2, disk: 0)
        try cache.store(result, for: first)
        try cache.store(result, for: second)
        #expect(cache.result(for: first) != nil)  // first is now most recently used
        try cache.store(result, for: third)
        #expect(cache.result(for: second) == nil)
        #expect(cache.result(for: first) != nil)
        #expect(cache.result(for: third) != nil)
        cache.releaseMemory()
        #expect(cache.result(for: first) == nil)
        #expect(cache.result(for: third) == nil)
    }

    @Test func diskLRUEvictsByBytesAndSurvivesReopen() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let first = try thumbnailRequest(directory.image(name: "first.jpg"))
        let second = try thumbnailRequest(directory.image(name: "second.jpg"))
        let third = try thumbnailRequest(directory.image(name: "third.jpg"))
        let result = ThumbnailExtractor().extract(first)
        let calibration = try directory.cache(memory: 0)
        try calibration.store(result, for: first)
        let cacheURL = directory.url.appendingPathComponent("cache")
        let files = try FileManager.default.contentsOfDirectory(
            at: cacheURL, includingPropertiesForKeys: [.fileSizeKey])
        let size = try #require(files.first?.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let cache = try directory.cache(memory: 0, disk: size * 2)
        try cache.store(result, for: second)
        #expect(cache.result(for: first) != nil)
        try cache.store(result, for: third)
        let reopened = try directory.cache(memory: 0, disk: size * 2)
        #expect(reopened.result(for: second) == nil)
        #expect(reopened.result(for: first) != nil)
        #expect(reopened.result(for: third) != nil)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: cacheURL, includingPropertiesForKeys: [.fileSizeKey])
        let total = try remaining.reduce(0) {
            try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        #expect(total <= size * 2)
    }

    @Test func failedAtomicReplacementKeepsCompleteOldJPEGAndRemovesStaging() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let result = ThumbnailExtractor().extract(request)
        let cache = try directory.cache(memory: 0)
        try cache.store(result, for: request)
        let cacheURL = directory.url.appendingPathComponent("cache")
        let destination = try #require(
            FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
                .first)
        let before = try Data(contentsOf: destination)
        struct InjectedFailure: Error {}
        let failing = try ThumbnailCache(
            directory: cacheURL, configuration: .init(),
            beforeCommit: { stage in
                #expect((try? Data(contentsOf: stage).count) == before.count)
                throw InjectedFailure()
            })
        #expect(throws: InjectedFailure.self) { try failing.store(result, for: request) }
        #expect(try Data(contentsOf: destination) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cacheURL.path).count == 1)
        #expect(try directory.cache(memory: 0).result(for: request) != nil)
        let newRequest = ThumbnailRequest(
            source: request.source, revision: request.revision,
            targetPixels: 200, locationIdentity: request.locationIdentity)
        #expect(throws: InjectedFailure.self) { try failing.store(result, for: newRequest) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: cacheURL.path).count == 1)
    }

    @Test func corruptDiskEntryIsRemovedAndUnavailableIsMemoryBounded() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let cache = try directory.cache(memory: 256)
        try cache.store(.unavailable(.noUsablePreview), for: request)
        guard case .unavailable(.noUsablePreview) = cache.result(for: request) else {
            Issue.record("Failure state should be cached")
            return
        }
        cache.releaseMemory()
        try cache.store(ThumbnailExtractor().extract(request), for: request)
        cache.releaseMemory()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory.url.appendingPathComponent("cache"), includingPropertiesForKeys: nil)
        try Data("truncated".utf8).write(to: #require(files.first))
        #expect(cache.result(for: request) == nil)
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
    }

    @Test func memoryResultIsSynchronousAndNeverReadsDisk() throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let result = ThumbnailExtractor().extract(request)
        let cache = try directory.cache()
        #expect(cache.memoryResult(for: request) == nil)
        try cache.store(result, for: request)
        let memory = try availableThumbnail(#require(cache.memoryResult(for: request)))
        #expect(max(memory.width, memory.height) == 400)
        cache.releaseMemory()
        // Disk entry still exists, yet memory-only lookup must miss without touching disk.
        #expect(cache.memoryResult(for: request) == nil)
        #expect(cache.result(for: request) != nil)
        #expect(cache.memoryResult(for: request) != nil)
    }

    @Test func deviceAwareMemoryBudgetScalesAboveEightGibibytes() {
        let mib = 1024 * 1024
        #expect(ThumbnailCache.Configuration().memoryBytes == 64 * mib)
        #expect(
            ThumbnailCache.Configuration.deviceAware(physicalMemory: 4 * 1024 * 1024 * 1024)
                .memoryBytes == 64 * mib)
        #expect(
            ThumbnailCache.Configuration.deviceAware(physicalMemory: 6 * 1024 * 1024 * 1024)
                .memoryBytes == 64 * mib)
        // iOS reports 8 GiB devices slightly below 8 * 1024^3 bytes.
        #expect(
            ThumbnailCache.Configuration.deviceAware(physicalMemory: 7_500_000_000).memoryBytes
                == 128 * mib)
        #expect(
            ThumbnailCache.Configuration.deviceAware(physicalMemory: 16 * 1024 * 1024 * 1024)
                .memoryBytes == 128 * mib)
    }
}
