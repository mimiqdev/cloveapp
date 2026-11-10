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

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        await gate.recordNativeHeld(cache.holdsNativeImage)
        return try? makeDetailImage(width: 64, height: 48)
    }
}

/// G1 "Scheduling and cache": a 32 MiB detail budget and at most one native RAW image.
@Suite(.serialized)
struct DetailCacheTests {
    private func image(_ source: URL, width: Int, height: Int) throws -> DetailImage {
        DetailImage(
            image: try makeDetailImage(width: width, height: height),
            source: try detailSource(source),
            quality: .preview)
    }

    private func key(_ source: DetailSource, purpose: DetailCachePurpose = .embeddedPreview)
        -> DetailCacheKey
    {
        DetailCacheKey(source: source, locationIdentity: "folder", purpose: purpose)
    }

    @Test func defaultBudgetIsThirtyTwoMebibytes() {
        #expect(DetailCache.Configuration().previewBytes == 32 * 1024 * 1024)
    }

    @Test func budgetEvictsTheLeastRecentlyUsedPreview() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache(megabytes: 2)
        let source = try detailSource(file)
        let keys = (0..<3).map { index in
            DetailCacheKey(
                source: source, locationIdentity: "folder-\(index)", purpose: .embeddedPreview)
        }
        // Each bitmap is exactly 1 MiB of row bytes, so two fit the 2 MiB budget.
        func store(_ index: Int) throws {
            cache.storePreview(try image(file, width: 512, height: 512), for: keys[index])
            #expect(cache.previewCost <= 2 * 1024 * 1024)
        }
        try store(0)
        try store(1)
        #expect(cache.preview(for: keys[0]) != nil)
        // The touch above leaves the middle entry as the least recently used one.
        try store(2)
        #expect(cache.previewCount == 2)
        #expect(cache.preview(for: keys[0]) != nil)
        #expect(cache.preview(for: keys[1]) == nil)
        #expect(cache.preview(for: keys[2]) != nil)
    }

    @Test func imageLargerThanTheBudgetIsNotCached() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "big.JPG")
        let cache = directory.cache(megabytes: 1)
        let source = try detailSource(file)
        cache.storePreview(try image(file, width: 1024, height: 512), for: key(source))
        #expect(cache.previewCount == 0)
        #expect(cache.previewCost == 0)
        #expect(cache.preview(for: key(source)) == nil)
    }

    @Test func atMostOneNativeImageIsHeld() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        let first = try image(file, width: 64, height: 48)
        let second = DetailImage(
            image: try makeDetailImage(width: 32, height: 32), source: source, quality: .nativeRAW)
        cache.storeNative(first, for: key(source, purpose: .nativeRAW))
        cache.storeNative(second, for: key(source, purpose: .displayRaster(1200)))
        #expect(cache.holdsNativeImage)
        #expect(cache.native(for: key(source, purpose: .nativeRAW)) == nil)
        #expect(cache.native(for: key(source, purpose: .displayRaster(1200))) != nil)
        // The native slot is outside the preview budget.
        #expect(cache.previewCount == 0)
        cache.releaseNative()
        #expect(cache.holdsNativeImage == false)
    }

    @Test func releaseAllClearsPreviewsAndTheNativeImage() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        cache.storePreview(try image(file, width: 64, height: 48), for: key(source))
        cache.storeNative(
            try image(file, width: 64, height: 48), for: key(source, purpose: .nativeRAW))
        #expect(cache.previewCount == 1 && cache.holdsNativeImage)
        // The memory-warning release drops both tiers (G1 "Scheduling and cache").
        cache.releaseAll()
        #expect(cache.previewCount == 0)
        #expect(cache.previewCost == 0)
        #expect(cache.holdsNativeImage == false)
    }

    @Test func aFullResolutionSizeIsKeptPerSourceRevision() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        #expect(cache.fullResolutionSize(for: source) == nil)

        cache.store(fullResolutionSize: CGSize(width: 8640, height: 5760), for: source)

        // PRD P0-04: the header size is paid for once per photo and answers the native 100%.
        #expect(cache.fullResolutionSize(for: source) == CGSize(width: 8640, height: 5760))
        // A rewritten file is a different revision, so it never inherits the old size.
        let newer = DetailSource(
            url: source.url,
            revision: ThumbnailRevision(size: 2, modificationTime: source.revision.modificationTime)
        )
        #expect(cache.fullResolutionSize(for: newer) == nil)
        // The size is metadata rather than decoded pixels, so a memory warning keeps it.
        cache.releaseAll()
        #expect(cache.fullResolutionSize(for: source) == CGSize(width: 8640, height: 5760))
    }

    @Test func identityCoversLocationRevisionAndRoute() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "bytes.JPG")
        let cache = directory.cache()
        let source = try detailSource(file)
        cache.storePreview(try image(file, width: 64, height: 48), for: key(source))
        // A different mount at the same path is a different source.
        #expect(
            cache.preview(
                for: DetailCacheKey(
                    source: source, locationIdentity: "other-folder", purpose: .embeddedPreview))
                == nil)
        // A different display size is a different raster.
        #expect(cache.preview(for: key(source, purpose: .displayRaster(1200))) == nil)
        // A rewritten file is a different revision.
        let newer = DetailSource(
            url: source.url,
            revision: ThumbnailRevision(size: 2, modificationTime: source.revision.modificationTime)
        )
        #expect(cache.preview(for: key(newer)) == nil)
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
        #expect(cache.previewCount == 0)
    }
}
