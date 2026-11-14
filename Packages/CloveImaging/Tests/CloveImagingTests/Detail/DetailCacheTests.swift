import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// Reads through the real renderer but records whether a native image was held at entry.
private struct NativeHeldProbe: DetailReading {
    let cache: DetailCache
    let gate: DetailReadGate

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        await DetailRenderer().read(step, displayPixels: displayPixels)
    }

    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
        await DetailRenderer().fullRaster(source)
    }

    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage? {
        await DetailRenderer().screenRAW(source, longEdge: longEdge)
    }

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        await gate.recordNativeHeld(cache.holdsNativeImage)
        return try? makeDetailImage(width: 64, height: 48)
    }
}

/// Compressed detail images share a budget; one native image is held separately.
@Suite(.serialized)
actor DetailCacheTests {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.DetailCache")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private func image(_ source: URL, width: Int, height: Int) throws -> DetailImage {
        DetailImage(
            image: try makeDetailImage(width: width, height: height),
            source: try detailSource(source),
            quality: .preview, hasRAW: false)
    }

    private func key(_ source: DetailSource, purpose: DetailCachePurpose = .embeddedPreview)
        -> DetailCacheKey
    {
        DetailCacheKey(source: source, locationIdentity: "folder", purpose: purpose)
    }

    @Test func defaultBudgetIsSixtyFourMebibytes() {
        #expect(DetailCache.Configuration().compressedBytes == 64 * 1024 * 1024)
    }

    @Test func budgetEvictsTheLeastRecentlyUsedPreview() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let sample = try image(file, width: 512, height: 512)
        let compressed = try #require(DetailCompressedImage(sample))
        var configuration = DetailCache.Configuration()
        configuration.compressedBytes = compressed.data.count * 2
        let cache = DetailCache(configuration: configuration)
        let source = try detailSource(file)
        let keys = (0..<3).map { index in
            DetailCacheKey(
                source: source, locationIdentity: "folder-\(index)", purpose: .embeddedPreview)
        }
        // Only two JPEGs fit, even though their decoded bitmaps exceed the budget.
        #expect(sample.decodedBytes > configuration.compressedBytes)
        func store(_ index: Int) {
            cache.store(compressed, for: keys[index])
            #expect(cache.compressedCost <= configuration.compressedBytes)
        }
        store(0)
        store(1)
        #expect(cache.image(for: keys[0]) != nil)
        // The touch above leaves the middle entry as the least recently used one.
        store(2)
        #expect(cache.imageCount == 2)
        #expect(cache.compressedCost == configuration.compressedBytes)
        #expect(cache.image(for: keys[0]) != nil)
        #expect(cache.image(for: keys[1]) == nil)
        #expect(cache.image(for: keys[2]) != nil)
    }

    @Test func imageLargerThanTheBudgetIsNotCached() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "big.JPG")
        let cache = directory.cache(megabytes: 0)
        let source = try detailSource(file)
        cache.store(
            try #require(DetailCompressedImage(image(file, width: 1024, height: 512))),
            for: key(source))
        #expect(cache.imageCount == 0)
        #expect(cache.compressedCost == 0)
        #expect(cache.image(for: key(source)) == nil)
    }

    @Test func atMostOneNativeImageIsHeld() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        let first = try image(file, width: 64, height: 48)
        let second = DetailImage(
            image: try makeDetailImage(width: 32, height: 32), source: source, quality: .nativeRAW,
            hasRAW: true)
        cache.storeNative(first, for: key(source, purpose: .nativeRAW))
        cache.storeNative(second, for: key(source, purpose: .displayRaster(1200)))
        #expect(cache.holdsNativeImage)
        #expect(cache.native(for: key(source, purpose: .nativeRAW)) == nil)
        #expect(cache.native(for: key(source, purpose: .displayRaster(1200))) != nil)
        // The native slot is outside the preview budget.
        #expect(cache.imageCount == 0)
        cache.releaseNative()
        #expect(cache.holdsNativeImage == false)
    }

    @Test func releaseAllClearsPreviewsAndTheNativeImage() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        cache.store(
            try #require(DetailCompressedImage(image(file, width: 64, height: 48))),
            for: key(source))
        cache.storeNative(
            try image(file, width: 64, height: 48), for: key(source, purpose: .nativeRAW))
        #expect(cache.imageCount == 1 && cache.holdsNativeImage)
        // The memory-warning release drops both tiers (G1 "Scheduling and cache").
        cache.releaseAll()
        #expect(cache.imageCount == 0)
        #expect(cache.compressedCost == 0)
        #expect(cache.holdsNativeImage == false)
    }

    @Test func aNativeSizeIsKeptPerSourceRevision() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        #expect(cache.nativeSize(for: source) == nil)

        cache.store(nativeSize: .known(CGSize(width: 8640, height: 5760)), for: source)

        // PRD P0-04: the size is paid for once per photo and answers the native 100%.
        #expect(cache.nativeSize(for: source) == .known(CGSize(width: 8640, height: 5760)))
        // A rewritten file is a different revision, so it never inherits the old size.
        let newer = DetailSource(
            url: source.url,
            revision: ThumbnailRevision(size: 2, modificationTime: source.revision.modificationTime)
        )
        #expect(cache.nativeSize(for: newer) == nil)
        // A memory warning drops every cached value, so the map stays bounded.
        cache.releaseAll()
        #expect(cache.nativeSize(for: source) == nil)
    }

    @Test func anUnknownSizeIsCachedPerSource() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)

        cache.store(nativeSize: .unknown, for: source)

        // A size that cannot be read is not read again on every request.
        #expect(cache.nativeSize(for: source) == .unknown)
    }

    @Test func identityCoversLocationRevisionAndRoute() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        cache.store(
            try #require(DetailCompressedImage(image(file, width: 64, height: 48))),
            for: key(source))
        // A different mount at the same path is a different source.
        #expect(
            cache.image(
                for: DetailCacheKey(
                    source: source, locationIdentity: "other-folder", purpose: .embeddedPreview))
                == nil)
        // A different display size is a different raster.
        #expect(cache.image(for: key(source, purpose: .displayRaster(1200))) == nil)
        // A rewritten file is a different revision.
        let newer = DetailSource(
            url: source.url,
            revision: ThumbnailRevision(size: 2, modificationTime: source.revision.modificationTime)
        )
        #expect(cache.image(for: key(newer)) == nil)
    }

    @Test(.enabled(if: DetailFixtures.hasFormats))
    func pipelineReleasesTheOldNativeImageBeforeRenderingTheNext() async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(
            cache: cache, reader: NativeHeldProbe(cache: cache, gate: gate))
        _ = try await pipeline.image(
            for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true))
        #expect(cache.holdsNativeImage)
        _ = try await pipeline.image(
            for: try rawRequest(DetailFixtures.file("canon-eos-r6.CR3"), native: true))
        // G1: release the old native image before allocating the next.
        #expect(await gate.nativeHeldAtEntry == [false, false])
        #expect(cache.holdsNativeImage)
        await pipeline.releaseCachedImages()
        #expect(cache.holdsNativeImage == false)
        #expect(cache.imageCount == 0)
    }

    @Test func truncatedCompressedDataFailsToDecode() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let sample = try image(file, width: 128, height: 128)
        let compressed = try #require(DetailCompressedImage(sample))
        let corrupted = DetailCompressedImage(
            corruptingData: Data(compressed.data.prefix(64)),
            copying: compressed)
        #expect(corrupted.decoded() == nil)
    }

    @Test func stagedWarmImageServesImmediatelyAndReleaseAllInvalidatesInFlightEncode() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        let entryKey = key(source)
        let sample = try image(file, width: 128, height: 128)
        let token = try #require(cache.stageForEncoding(sample, for: entryKey))

        // Synchronously available before compressed encoding finishes.
        #expect(cache.warmImage(for: entryKey)?.image === sample.image)
        #expect(cache.image(for: entryKey)?.image === sample.image)
        #expect(cache.pendingCount == 1)
        #expect(cache.imageCount == 1)
        #expect(cache.contains(entryKey, minimumLongEdge: 128))

        // releaseAll bumps encodingEpoch so a late finishEncoding never pollutes the cleared cache.
        cache.releaseAll()
        #expect(cache.pendingCount == 0)
        #expect(cache.warmCost == 0)
        #expect(cache.warmImage(for: entryKey) == nil)
        cache.finishEncoding(
            try #require(DetailCompressedImage(sample)), for: entryKey,
            epoch: token.epoch, token: token.token)
        #expect(cache.imageCount == 0)
        #expect(cache.compressedCost == 0)

        // Fresh stage + commit transitions pending -> compressed cleanly.
        let freshToken = try #require(cache.stageForEncoding(sample, for: entryKey))
        cache.finishEncoding(
            try #require(DetailCompressedImage(sample)), for: entryKey,
            epoch: freshToken.epoch, token: freshToken.token)
        #expect(cache.pendingCount == 0)
        #expect(cache.imageCount == 1)
        #expect(cache.compressedCost > 0)
    }

    @Test func warmBudgetEvictsLeastRecentlyUsedBitmapWhileKeepingCompressedEntry() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let sample = try image(file, width: 128, height: 128)
        let compressed = try #require(DetailCompressedImage(sample))
        var configuration = DetailCache.Configuration()
        configuration.compressedBytes = compressed.data.count * 8
        configuration.warmBytes = sample.decodedBytes * 2
        let cache = DetailCache(configuration: configuration)
        let source = try detailSource(file)
        let keys = (0..<3).map { index in
            DetailCacheKey(
                source: source, locationIdentity: "warm-\(index)", purpose: .embeddedPreview)
        }

        for index in 0..<2 {
            let staged = try #require(cache.stageForEncoding(sample, for: keys[index]))
            cache.finishEncoding(
                compressed, for: keys[index], epoch: staged.epoch, token: staged.token)
        }
        // Touch key 0 so key 1 is oldest when key 2 arrives.
        #expect(cache.warmImage(for: keys[0]) != nil)
        let third = try #require(cache.stageForEncoding(sample, for: keys[2]))
        cache.finishEncoding(compressed, for: keys[2], epoch: third.epoch, token: third.token)

        #expect(cache.warmCost == sample.decodedBytes * 2)
        #expect(cache.warmImage(for: keys[0]) != nil)
        #expect(cache.warmImage(for: keys[1]) == nil)
        #expect(cache.warmImage(for: keys[2]) != nil)
        // Evicted from warm tier, still recoverable from compressed JPEG tier.
        #expect(cache.image(for: keys[1]) != nil)
    }

    @Test func deviceAwareBudgetScalesAcrossMemoryTiers() {
        let mib = 1024 * 1024
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 4 * 1024 * 1024 * 1024)
                .compressedBytes == 64 * mib)
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 6 * 1024 * 1024 * 1024)
                .compressedBytes == 64 * mib)
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 7_500_000_000).compressedBytes
                == 96 * mib)
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 8 * 1024 * 1024 * 1024)
                .compressedBytes == 96 * mib)
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 12 * 1024 * 1024 * 1024)
                .compressedBytes == 128 * mib)
        #expect(
            DetailCache.Configuration.deviceAware(physicalMemory: 16 * 1024 * 1024 * 1024)
                .compressedBytes == 128 * mib)
    }
}
