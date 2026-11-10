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

    @Test func aCappedFullRasterReportsTheShortfall() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        // A JPEG wider than the raster cap: the full decode stops at the cap, so the route can
        // give no more and says so instead of being asked again (PRD P0-04; G1 "Preview, detail").
        let file = try directory.image(name: "huge.JPG", width: 40_000, height: 8)
        let pipeline = DetailPipeline(cache: DetailCache())

        let image = try availableDetail(
            try await pipeline.image(for: try rasterRequest(file, native: true)))

        #expect(image.quality == .raster)
        #expect(image.longEdge == DetailRenderer.maximumRasterPixels)
        #expect(image.limitation == .noHigherResolution)
        // The cap is final: no display request can produce a larger bitmap, so the view stops
        // asking even though the file's own size is larger.
        #expect(image.isBestAvailable)
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

    @Test func anImageAtItsBestNeverAsksForMorePixels() throws {
        let source = DetailSource(
            url: URL(fileURLWithPath: "/missing/photo.ARW"),
            revision: ThumbnailRevision(size: 0, modificationTime: .distantPast))
        let native = CGSize(width: 8640, height: 5760)
        func image(_ width: Int, _ height: Int, _ quality: DetailQuality, _ size: CGSize?)
            throws -> DetailImage
        {
            DetailImage(
                image: try makeDetailImage(width: width, height: height), source: source,
                quality: quality, fullResolutionSize: size)
        }

        // A native RAW render is the photo's full resolution, and a full raster answers a JPEG's
        // 100%, so asking either for more would repeat the same pixels (G1 "Preview, detail").
        #expect(try image(8640, 5760, .nativeRAW, native).isBestAvailable)
        #expect(try image(2900, 1933, .raster, CGSize(width: 2900, height: 1933)).isBestAvailable)
        // One pixel short counts as full: rounding in the fit geometry can lose that pixel.
        #expect(try image(2899, 1933, .raster, CGSize(width: 2900, height: 1933)).isBestAvailable)
        // The raster decode limit is final even when the file is larger: no display request can
        // produce more pixels than the cap.
        #expect(
            try image(
                DetailRenderer.maximumRasterPixels, 8, .raster,
                CGSize(width: 40_000, height: 8)
            ).isBestAvailable)
        // A display raster below the photo's size and any preview can still improve.
        #expect(try !image(1200, 800, .raster, native).isBestAvailable)
        #expect(try !image(1616, 1080, .preview, native).isBestAvailable)
        // A raster or preview whose header is unknown may still find the render's size, so it
        // asks rather than treating its own size as the photo's.
        #expect(try !image(1616, 1080, .raster, nil).isBestAvailable)
        #expect(try !image(1616, 1080, .preview, nil).isBestAvailable)
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
