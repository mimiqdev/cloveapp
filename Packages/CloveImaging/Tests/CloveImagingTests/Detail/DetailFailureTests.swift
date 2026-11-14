import Foundation
import Testing

@testable import CloveImaging

/// Every failure is an explicit state, never a blank image or a silent swap (PRD P0-04,
/// PRD Supported files, G1 "Preview, detail (I2)").
@Suite(.serialized)
struct DetailFailureTests {
    @Test func unreadableFileReportsCannotOpen() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let pipeline = DetailPipeline(cache: DetailCache())
        let result = try await pipeline.preview(
            for: try rasterRequest(directory.notAnImage(name: "broken.JPG")))
        #expect(try detailFailure(result) == .cannotOpen)
    }

    @Test func truncatedJPEGReportsFailureInsteadOfEmptyBitmap() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let valid = try directory.image(name: "valid.JPG")
        let validBytes = try Data(contentsOf: valid)
        let truncated = directory.path("truncated.JPG")
        try validBytes.prefix(min(validBytes.count / 4, 64)).write(to: truncated)
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = try rasterRequest(truncated)
        let previewFailure = try detailFailure(try await pipeline.preview(for: request))
        #expect(previewFailure == .cannotOpen || previewFailure == .noUsablePreview)
        let fullFailure = try detailFailure(
            try await pipeline.image(
                for: DetailRequest(
                    jpeg: try detailSource(truncated), displayPixels: 1200,
                    wantsNativeResolution: true, locationIdentity: "folder")))
        #expect(fullFailure == .cannotOpen || fullFailure == .noUsablePreview)
    }

    @Test func readableFileWithoutPreviewReportsNoUsablePreview() async throws {
        // A HEIF without an embedded thumbnail is the no-preview control I1 also uses.
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "no-preview.HIF", type: .heic)
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = DetailRequest(
            heif: try detailSource(heif), displayPixels: 1200, locationIdentity: "folder")
        #expect(try detailFailure(try await pipeline.preview(for: request)) == .noUsablePreview)
        #expect(try detailFailure(try await pipeline.image(for: request)) == .noUsablePreview)
    }

    @Test func rawOrHifInTheJpegSlotIsNeverFullyDecoded() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let pipeline = DetailPipeline(cache: DetailCache())
        // G1 "Preview, detail (I2)": a HIF is never fully decoded, and a RAW belongs to the
        // render route, so a mis-slotted file is reported instead of decoded.
        let heif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        #expect(
            try detailFailure(try await pipeline.preview(for: try rasterRequest(heif)))
                == .noUsablePreview)
        let raw = directory.path("renamed.JPG")
        try Data(contentsOf: DetailFixtures.file("sony-ilce-7s.ARW")).write(to: raw)
        #expect(
            try detailFailure(try await pipeline.preview(for: try rasterRequest(raw)))
                == .noUsablePreview)
    }

    @Test(.enabled(if: DetailFixtures.hasFormats))
    func changedFileNeverReturnsTheCachedImage() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let copy = try directory.copy(of: DetailFixtures.file("sony-ilce-7s.ARW"), as: "IMG_1.ARW")
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = DetailRequest(
            raw: try detailSource(copy), displayPixels: 1200, locationIdentity: "folder")
        let first = try availableDetail(try await pipeline.preview(for: request))
        #expect(first.width == 1616)
        let handle = try FileHandle(forWritingTo: copy)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()
        // The revision the request carries is stale, so the cached image must not come back.
        let stale = try await pipeline.preview(for: request)
        #expect(try detailFailure(stale) == .sourceChanged)
        // A fresh revision reads the new bytes instead of the old entry.
        let refreshed = DetailRequest(
            raw: try detailSource(copy), displayPixels: 1200, locationIdentity: "folder")
        #expect(try availableDetail(try await pipeline.preview(for: refreshed)).quality == .preview)
    }

    @Test(.enabled(if: DetailFixtures.hasFormats))
    func staleNativeRequestNeverRendersAChangedFile() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let copy = try directory.copy(of: DetailFixtures.file("sony-ilce-7s.ARW"), as: "IMG_2.ARW")
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = DetailRequest(
            raw: try detailSource(copy), displayPixels: 1200, wantsNativeResolution: true,
            locationIdentity: "folder")
        let handle = try FileHandle(forWritingTo: copy)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()
        // The preview is unreadable under the stale revision, so nothing is rendered or shown.
        #expect(try detailFailure(try await pipeline.image(for: request)) == .sourceChanged)
    }
}
