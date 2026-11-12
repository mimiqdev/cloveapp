import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// The production reading seam against the real detail pipeline: the analysis's preview and
/// high-resolution reads ride the pipeline's existing lanes, so one photo is decoded once per
/// stage and the analysis adds no route of its own (#208).
@Suite(.serialized)
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
