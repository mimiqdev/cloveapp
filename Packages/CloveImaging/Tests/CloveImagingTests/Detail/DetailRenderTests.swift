import Foundation
import Testing

@testable import CloveImaging

/// When the RAW route is allowed to run (G1 "Preview, detail (I2)"; PRD P0-04).
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailRenderTests {
    @Test func rawFitUpgradeRendersAtScreenSize() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let image = try availableDetail(
            try await pipeline.screen(
                for: try rawRequest(DetailFixtures.file("canon-eos-r6.CR3"), displayPixels: 1200)))
        #expect(await gate.nativePaths.count == 1)
        #expect(image.quality == .screenRAW)
        #expect(image.longEdge == 1200)
        #expect(image.limitation == nil)
    }

    @Test func viewBeyondThePreviewRendersNativePixels() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        let image = try availableDetail(
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), displayPixels: 1800)))
        // The ARW exposes 1616 px, so a 1800 px need is answered by CIRAWFilter at native size.
        #expect(image.quality == .nativeRAW)
        #expect(image.width == 2768 && image.height == 1848)
        #expect(image.source.url.pathExtension == "ARW")
        #expect(image.limitation == nil)
    }

    @Test func nativeRequestRendersNativePixels() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)
        let image = try availableDetail(try await pipeline.image(for: request))
        #expect(image.quality == .nativeRAW)
        #expect(image.width == 2768 && image.height == 1848)
    }

    @Test func nativeRenderAppliesOrientation() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        // The ProRAW fixture is 4032×3024 with EXIF orientation 6.
        let image = try availableDetail(
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("apple-iphone-12-pro.DNG"), native: true)))
        #expect(image.quality == .nativeRAW)
        #expect(image.width == 3024 && image.height == 4032)
    }

    @Test func jpegPrimaryNativeDecodesTheFullJpegWithoutRenderingRaw() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let image = try availableDetail(
            try await pipeline.image(
                for: try rasterRequest(DetailFixtures.file("canon-eos-6d.JPG"), native: true)))
        // G1 "Preview, detail (I2)": JPEG primary answers 100% with a bounded raster decode.
        #expect(image.quality == .raster)
        #expect(image.width == 5472 && image.height == 3648)
        #expect(await gate.nativePaths.isEmpty)
    }

    @Test func hifOnlyNativeStaysAtPreviewQualityAndReportsIt() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = DetailRequest(
            heif: try detailSource(heif), displayPixels: 1200, wantsNativeResolution: true,
            locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.image(for: request))
        // G1: a HIF is never fully decoded, so the preview is the maximum and says so.
        #expect(image.quality == .preview)
        #expect(image.width == 320)
        #expect(image.limitation == .noHigherResolution)
    }

    @Test func failedRawRenderKeepsThePreview() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .fail, holdNative: false, holdPreview: false)
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let image = try availableDetail(
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)))
        // PRD P0-04: the preview stays the best result, reported as such, never a blank image.
        #expect(image.quality == .preview)
        #expect(image.width == 1616)
        #expect(image.limitation == .rawRenderFailed)
        #expect(await gate.nativePaths.count == 1)
    }

    @Test func nativeRenderIsReusedForTheSameSource() async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let request = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)
        _ = try availableDetail(try await pipeline.image(for: request))
        _ = try availableDetail(try await pipeline.image(for: request))
        #expect(await gate.nativePaths.count == 1)
        #expect(cache.holdsNativeImage)
    }

    @Test func previewOnlyRequestNeverRenders() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        _ = try availableDetail(
            try await pipeline.preview(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)))
        // `preview(for:)` is the immediate fit-view image: it never renders, even when the
        // request carries the 100% flag.
        #expect(await gate.nativePaths.isEmpty)
    }
}
