import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

/// The native size a double-tap to 100% uses, read from the file header before a render lands
/// (PRD P0-04; G1 "Preview, detail (I2)").
///
/// The fixture tests compare the header size with the pixels the photo's own route produces, so
/// the two cannot drift apart: `nativeRAW` for a RAW-primary photo and `fullRaster` for a
/// JPEG-primary one.
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailNativeSizeFixtureTests {
    @Test func arwHeaderMatchesTheNativeRender() async throws {
        let source = try detailSource(DetailFixtures.file("sony-ilce-7s.ARW"))

        let header = try #require(DetailNativeSize.read(source))
        let rendered = try #require(await DetailRenderer().nativeRAW(source))

        #expect(header == CGSize(width: 2768, height: 1848))
        #expect(header == CGSize(width: rendered.width, height: rendered.height))
    }

    @Test func portraitHeaderIsOrientedLikeTheNativeRender() async throws {
        // The ProRAW fixture is 4032×3024 with EXIF orientation 6, so the photo is 3024×4032.
        let source = try detailSource(DetailFixtures.file("apple-iphone-12-pro.DNG"))

        let header = try #require(DetailNativeSize.read(source))
        let rendered = try #require(await DetailRenderer().nativeRAW(source))

        #expect(header == CGSize(width: 3024, height: 4032))
        #expect(header == CGSize(width: rendered.width, height: rendered.height))
    }

    @Test func jpegHeaderMatchesTheFullRaster() async throws {
        let source = try detailSource(DetailFixtures.file("canon-eos-6d.JPG"))

        let header = try #require(DetailNativeSize.read(source))
        guard case .image(let pixels) = await DetailRenderer().fullRaster(source) else {
            Issue.record("The JPEG fixture did not decode")
            return
        }

        #expect(header == CGSize(width: 5472, height: 3648))
        #expect(header == CGSize(width: pixels.width, height: pixels.height))
    }

    @Test func theFirstPreviewCarriesTheSizeTheRenderThenKeeps() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        // The explicit double-tap to 100% is the request that renders native pixels (PRD P0-04).
        let rendered = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))

        // The embedded preview is smaller than the RAW; the native size arrives with it, so the
        // double-tap target is the render's size and the render adds no second zoom.
        #expect(preview.quality == .preview)
        #expect(preview.longEdge < Int(preview.fullResolutionPixels.width))
        #expect(preview.fullResolutionSize == CGSize(width: 2768, height: 1848))
        #expect(rendered.quality == .nativeRAW)
        #expect(rendered.fullResolutionSize == preview.fullResolutionSize)
        #expect(
            CGSize(width: rendered.width, height: rendered.height)
                == preview.fullResolutionSize)
    }

    @Test func aJpegPrimaryPreviewCarriesTheFullJpegSize() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = try rasterRequest(
            DetailFixtures.file("canon-eos-6d.JPG"), displayPixels: 1200)

        let preview = try availableDetail(try await pipeline.preview(for: request))

        // A JPEG-primary photo's 100% is the full JPEG, which `fullRaster` decodes.
        #expect(preview.quality == .raster)
        #expect(preview.longEdge == 1200)
        #expect(preview.fullResolutionSize == CGSize(width: 5472, height: 3648))
    }

    @Test func aCachedCompanionPreviewTakesTheRequestsOwnSize() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        let gate = DetailReadGate()
        // The generated HEIF's own preview is tiny, so the plan would skip it; this substitution
        // gives it the camera-sized preview a RAW + HIF set shows first.
        let substitutions = [
            DetailPreviewSubstitution(file: "camera.HIF", width: 1200, height: 800)
        ]
        let pipeline = DetailPipeline(
            cache: DetailCache(),
            reader: GatedDetailReader(gate: gate, substitutions: substitutions))
        let raw = try detailSource(DetailFixtures.file("sony-ilce-7s.ARW"))
        let heifSource = try detailSource(heif)
        let withRaw = DetailRequest(
            raw: raw, heif: heifSource, displayPixels: 1200, locationIdentity: "folder")

        let first = try availableDetail(try await pipeline.preview(for: withRaw))
        // The preview comes from the HIF, while the photo's size comes from the RAW.
        #expect(first.source.url.lastPathComponent == "camera.HIF")
        #expect(first.fullResolutionSize == CGSize(width: 2768, height: 1848))

        // The same cached HIF preview asked for a HIF-only photo has no larger size to report,
        // so it must not keep the RAW's 100% from the earlier request.
        let heifOnly = DetailRequest(
            heif: heifSource, displayPixels: 1200, locationIdentity: "folder")
        let second = try availableDetail(try await pipeline.preview(for: heifOnly))
        #expect(second.source.url.lastPathComponent == "camera.HIF")
        #expect(second.fullResolutionSize == nil)
        #expect(second.fullResolutionPixels == CGSize(width: 1200, height: 800))
    }
}

/// Header reads that need no fixture: the orientation rule and the unreadable-file fallback.
@Suite(.serialized)
struct DetailNativeSizeTests {
    @Test func aPortraitJpegHeaderIsOrientedLikeItsFullRaster() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(
            name: "portrait.JPG", orientation: 6, width: 2400, height: 1600)
        let source = try detailSource(file)

        let header = try #require(DetailNativeSize.read(source))
        guard case .image(let pixels) = await DetailRenderer().fullRaster(source) else {
            Issue.record("The portrait JPEG did not decode")
            return
        }

        #expect(header == CGSize(width: 1600, height: 2400))
        #expect(header == CGSize(width: pixels.width, height: pixels.height))
    }

    @Test func everyQuarterTurnOrientationSwapsTheAxes() {
        for orientation in 5...8 {
            #expect(
                DetailNativeSize.oriented(width: 100, height: 200, orientation: orientation)
                    == CGSize(width: 200, height: 100))
        }
        for orientation in [1, 2, 3, 4] {
            #expect(
                DetailNativeSize.oriented(width: 100, height: 200, orientation: orientation)
                    == CGSize(width: 100, height: 200))
        }
        #expect(DetailNativeSize.oriented(width: 0, height: 200, orientation: 1) == nil)
    }

    @Test func anUnreadableFileHasNoHeaderSize() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.notAnImage(name: "broken.ARW")

        #expect(DetailNativeSize.read(try detailSource(file)) == nil)
    }

    @Test func aPreviewWithoutAHeaderSizeFallsBackToItsOwnPixels() throws {
        let image = DetailImage(
            image: try makeDetailImage(width: 320, height: 240),
            source: DetailSource(
                url: URL(fileURLWithPath: "/missing/photo.HIF"),
                revision: ThumbnailRevision(size: 0, modificationTime: .distantPast)),
            quality: .preview)

        #expect(image.fullResolutionSize == nil)
        #expect(image.fullResolutionPixels == CGSize(width: 320, height: 240))
    }
}
