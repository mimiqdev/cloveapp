import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// The production reading seam against the real detail pipeline: the analysis's preview and
/// high-resolution reads ride the pipeline's existing lanes, so one photo is decoded once per
/// stage and the analysis adds no route of its own (#208).
@Suite(.serialized, .imageWork)
struct DetailRegionSharpnessReadingTests {
    @Test func readingDeliversOrientationAppliedPixelsForARaster() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        // Orientation 6, so delivered pixels are axis-swapped from the stored raster.
        let file = try directory.image(name: "photo.jpg", orientation: 6, width: 1200, height: 800)
        let request = RegionSharpnessRequest(
            jpeg: try detailSource(file), locationIdentity: "test")
        let details = DetailPipeline(cache: directory.cache())
        defer { Task { await details.close() } }
        let reading = DetailRegionSharpnessReading(details: details)

        let properties = await reading.properties(of: file)
        #expect(properties != nil)

        let preview = await reading.preview(request)
        guard case .success(let previewImage) = preview else {
            Issue.record("Expected preview pixels")
            return
        }
        #expect(
            max(previewImage.width, previewImage.height) <= RegionSharpnessAnalyzer.previewPixels)

        let highResolution = await reading.highResolution(request)
        guard case .success(let fullImage) = highResolution else {
            Issue.record("Expected full pixels")
            return
        }
        // Orientation 6 swaps the stored 1200×800 to 800×1200 display pixels.
        #expect(fullImage.width == 800 && fullImage.height == 1200)
    }

    @Test(.enabled(if: DetailFixtures.hasFormats))
    func facePreviewUsesOnlyTheBoundedPreviewLane() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(
            cache: directory.cache(), reader: GatedDetailReader(gate: gate),
            sizes: StubDetailNativeSizeReader(size: CGSize(width: 4000, height: 3000)))
        defer { Task { await pipeline.close() } }
        let reading = DetailRegionSharpnessReading(details: pipeline)
        let request = RegionSharpnessRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            locationIdentity: "test")

        let preview = await reading.preview(request)
        guard case .success(let pixels) = preview else {
            Issue.record("Expected bounded preview pixels")
            return
        }
        #expect(max(pixels.width, pixels.height) <= RegionSharpnessAnalyzer.previewPixels)
        #expect(await gate.previewPaths.count == 1)
        #expect(await gate.nativePaths.isEmpty)

        _ = await reading.highResolution(request)
        // The native analysis shares the preview already acquired for detection rather than
        // decoding it again; only this explicit high-resolution path enters native RAW.
        #expect(await gate.previewPaths.count == 1)
        #expect(await gate.nativePaths.count == 1)
    }

    @Test func unreadableFilesReportExplicitFailures() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.notAnImage()
        let request = RegionSharpnessRequest(
            jpeg: try detailSource(file), locationIdentity: "test")
        let details = DetailPipeline(cache: directory.cache())
        defer { Task { await details.close() } }
        let reading = DetailRegionSharpnessReading(details: details)

        let preview = await reading.preview(request)
        guard case .failure(let failure) = preview else {
            Issue.record("Expected an explicit failure")
            return
        }
        #expect(failure == .cannotOpen || failure == .noUsablePreview)
    }
}
