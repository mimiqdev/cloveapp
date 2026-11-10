import Foundation
import Testing

@testable import CloveImaging

/// The preview source order of G1 "Preview, detail (I2)", checked as a pure plan first.
struct DetailPreviewPlanTests {
    private func request(raw: Bool, jpeg: Bool, heif: Bool) throws -> DetailRequest {
        let file = URL(fileURLWithPath: "/photo/IMG_0001")
        let revision = ThumbnailRevision(size: 1, modificationTime: Date(timeIntervalSince1970: 1))
        func source(_ suffix: String) -> DetailSource {
            DetailSource(url: URL(fileURLWithPath: file.path + suffix), revision: revision)
        }
        return DetailRequest(
            raw: raw ? source(".ARW") : nil, jpeg: jpeg ? source(".JPG") : nil,
            heif: heif ? source(".HIF") : nil, displayPixels: 1200,
            locationIdentity: "folder")
    }

    @Test func hifLeadsThenRawThenJpeg() throws {
        let steps = DetailPreviewPlan.steps(for: try request(raw: true, jpeg: true, heif: true))
        #expect(
            steps == [
                .embedded(try #require(request(raw: true, jpeg: true, heif: true).heif)),
                .embedded(try #require(request(raw: true, jpeg: true, heif: true).raw)),
                .displayRaster(try #require(request(raw: true, jpeg: true, heif: true).jpeg)),
            ])
    }

    @Test func rawAndHeifSkipsTheJpegStep() throws {
        let steps = DetailPreviewPlan.steps(for: try request(raw: true, jpeg: false, heif: true))
        let request = try request(raw: true, jpeg: false, heif: true)
        #expect(
            steps == [
                .embedded(try #require(request.heif)), .embedded(try #require(request.raw)),
            ])
    }

    @Test func rawAloneUsesItsOwnPreview() throws {
        let request = try request(raw: true, jpeg: false, heif: false)
        #expect(
            DetailPreviewPlan.steps(for: request) == [
                .embedded(try #require(request.raw))
            ])
    }

    @Test func rawAndJpegFallsBackToTheRaster() throws {
        let request = try request(raw: true, jpeg: true, heif: false)
        #expect(
            DetailPreviewPlan.steps(for: request) == [
                .embedded(try #require(request.raw)), .displayRaster(try #require(request.jpeg)),
            ])
    }

    @Test func jpegAloneIsARasterAndHeifAloneAnEmbeddedPreview() throws {
        let jpeg = try request(raw: false, jpeg: true, heif: false)
        #expect(DetailPreviewPlan.steps(for: jpeg) == [.displayRaster(try #require(jpeg.jpeg))])
        let heif = try request(raw: false, jpeg: false, heif: true)
        #expect(DetailPreviewPlan.steps(for: heif) == [.embedded(try #require(heif.heif))])
    }

    @Test func jpegWithHeifAndNoRawStaysJpegFirst() throws {
        let request = try request(raw: false, jpeg: true, heif: true)
        #expect(
            DetailPreviewPlan.steps(for: request) == [
                .displayRaster(try #require(request.jpeg)), .embedded(try #require(request.heif)),
            ])
    }

    @Test func stepQualityNamesTheLevelItDelivers() {
        let revision = ThumbnailRevision(size: 1, modificationTime: Date(timeIntervalSince1970: 1))
        let source = DetailSource(url: URL(fileURLWithPath: "/photo/A.ARW"), revision: revision)
        #expect(DetailPreviewStep.embedded(source).quality == .preview)
        #expect(DetailPreviewStep.displayRaster(source).quality == .raster)
        #expect(DetailPreviewStep.embedded(source).purpose(displayPixels: 1200) == .embeddedPreview)
        #expect(
            DetailPreviewStep.displayRaster(source).purpose(displayPixels: 1200)
                == .displayRaster(1200))
    }

    @Test func aTinyEmbeddedPreviewIsNotUsableButARasterAlwaysIs() throws {
        let revision = ThumbnailRevision(size: 1, modificationTime: Date(timeIntervalSince1970: 1))
        let source = DetailSource(url: URL(fileURLWithPath: "/photo/A.ARW"), revision: revision)
        func image(_ pixels: Int, quality: DetailQuality = .preview) throws -> DetailImage {
            DetailImage(
                image: try makeDetailImage(width: pixels, height: 8), source: source,
                quality: quality, hasRAW: true)
        }
        #expect(DetailPreviewPlan.minimumUsablePreviewPixels == 1024)
        #expect(!DetailPreviewPlan.isUsable(try image(1023), from: .embedded(source)))
        #expect(DetailPreviewPlan.isUsable(try image(1024), from: .embedded(source)))
        // A display raster is decoded at the view's own size, so it never sends the plan on.
        #expect(DetailPreviewPlan.isUsable(try image(320), from: .displayRaster(source)))
    }
}

/// Preview sources, orientation and quality levels over the shared fixture sets (G1
/// "Preview, detail (I2)"; PRD P0-04) plus generated controls.
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailPreviewSourceTests {
    private func pipeline(_ cache: DetailCache = DetailCache()) -> DetailPipeline {
        DetailPipeline(cache: cache)
    }

    @Test func heifPreviewLeadsAndStopsThePlan() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "partner.HIF", type: .heic, embedded: true)
        let gate = DetailReadGate()
        // The generated HEIF thumbnail is 320 px, so a camera-sized HIF preview is
        // substituted here; the tiny 320 px case has its own test below.
        let pipeline = DetailPipeline(
            cache: DetailCache(),
            reader: GatedDetailReader(
                gate: gate,
                substitutions: [.init(file: "partner.HIF", width: 1616, height: 1080)]))
        let request = DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            heif: try detailSource(heif),
            // Larger than every embedded preview here: the pipeline must still stop at the
            // HIF and leave the extra pixels to image(for:).
            displayPixels: 2400, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.preview(for: request))
        // G1 "Preview, detail (I2)": the HIF's embedded preview is the first source, and a
        // bigger view never makes navigation read the RAW's preview as well.
        #expect(image.source.url == heif.standardizedFileURL)
        #expect(image.quality == .preview)
        #expect(image.longEdge == 1616)
        #expect(image.limitation == nil)
        #expect(await gate.previewPaths == [heif.standardizedFileURL.path])
    }

    @Test func heifWithoutPreviewFallsBackToTheRaw() async throws {
        // The generated HEIC fixture exposes no embedded preview, so this is the real
        // "HIF unreadable or with no preview" path from G1 "Preview, detail (I2)".
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let raw = DetailFixtures.file("sony-ilce-7s.ARW")
        let heif = DetailFixtures.file("sony-ilce-7s.HEIC")
        let request = DetailRequest(
            raw: try detailSource(raw), heif: try detailSource(heif),
            displayPixels: 1200, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.preview(for: request))
        #expect(image.source.url == raw.standardizedFileURL)
        #expect(image.quality == .preview)
        #expect(image.width == 1616 && image.height == 1080)
        // The HIF is tried first; only its missing preview makes the RAW read happen.
        #expect(
            await gate.previewPaths == [
                heif.standardizedFileURL.path, raw.standardizedFileURL.path,
            ])
    }

    @Test func tinyHeifPreviewFallsThroughToTheRaw() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "partner.HIF", type: .heic, embedded: true)
        let request = DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            heif: try detailSource(heif), displayPixels: 1200, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline().preview(for: request))
        #expect(image.source.url == DetailFixtures.file("sony-ilce-7s.ARW").standardizedFileURL)
        #expect(image.width == 1616)
    }

    @Test func rawAloneUsesItsEmbeddedPreview() async throws {
        let image = try availableDetail(
            try await pipeline().preview(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"))))
        #expect(image.quality == .preview)
        #expect(image.width == 1616 && image.height == 1080)
    }

    @Test(.enabled(if: DetailFixtures.hasCardBasic))
    func rawAndJpegUsesTheRawPreview() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let raw = DetailFixtures.cardFile("IMG_0001.CR3")
        let request = DetailRequest(
            raw: try detailSource(raw),
            jpeg: try detailSource(DetailFixtures.cardFile("IMG_0001.JPG")),
            displayPixels: 1200, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.preview(for: request))
        #expect(image.source.url.pathExtension == "CR3")
        #expect(image.quality == .preview)
        #expect(image.width == 2000 && image.height == 1333)
        // The JPEG is a fallback for a missing or tiny RAW preview, not a second read.
        #expect(await gate.previewPaths == [raw.standardizedFileURL.path])
    }

    @Test(.enabled(if: DetailFixtures.hasCardBasic))
    func aViewLargerThanThePreviewNeverReadsAnotherSource() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let raw = DetailFixtures.cardFile("IMG_0001.CR3")
        let request = DetailRequest(
            raw: try detailSource(raw),
            jpeg: try detailSource(DetailFixtures.cardFile("IMG_0001.JPG")),
            displayPixels: 2400, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.preview(for: request))
        // G1 "Preview, detail (I2)": the CR3 preview is a usable 2000 px one, so navigation
        // stops there. Extra pixels for a 2400 px view come from image(for:) only.
        #expect(image.source.url == raw.standardizedFileURL)
        #expect(image.quality == .preview)
        #expect(image.longEdge == 2000)
        #expect(await gate.previewPaths == [raw.standardizedFileURL.path])
    }

    @Test func tinyRawPreviewFallsBackToTheJpeg() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let jpeg = try directory.image(name: "partner.JPG", width: 3000, height: 2000)
        let gate = DetailReadGate()
        // No fixture has a RAW with an unusably small preview, so the ARW's embedded preview
        // is shrunk through the read seam.
        let pipeline = DetailPipeline(
            cache: DetailCache(),
            reader: GatedDetailReader(
                gate: gate,
                substitutions: [.init(file: "sony-ilce-7s.ARW", width: 640, height: 427)]))
        let raw = DetailFixtures.file("sony-ilce-7s.ARW")
        let request = DetailRequest(
            raw: try detailSource(raw), jpeg: try detailSource(jpeg), displayPixels: 1200,
            locationIdentity: "folder")
        let image = try availableDetail(try await pipeline.preview(for: request))
        // A 640 px preview is not a detail preview, so the JPEG answers at display size.
        #expect(image.source.url == jpeg.standardizedFileURL)
        #expect(image.quality == .raster)
        #expect(image.width == 1200)
        #expect(
            await gate.previewPaths == [
                raw.standardizedFileURL.path, jpeg.standardizedFileURL.path,
            ])
    }

    @Test func jpegAloneDecodesAtDisplaySize() async throws {
        let image = try availableDetail(
            try await pipeline().preview(
                for: try rasterRequest(DetailFixtures.file("canon-eos-6d.JPG"), displayPixels: 1200)
            ))
        #expect(image.quality == .raster)
        #expect(image.width == 1200 && image.height == 800)
    }

    @Test func jpegOrientationIsApplied() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let rotated = try directory.image(orientation: 6)
        let image = try availableDetail(
            try await pipeline().preview(for: try rasterRequest(rotated, displayPixels: 400)))
        #expect(image.width == 267 && image.height == 400)
    }

    @Test func rawPreviewOrientationIsApplied() async throws {
        // The ProRAW fixture is 4032×3024 with EXIF orientation 6.
        let image = try availableDetail(
            try await pipeline().preview(
                for: try rawRequest(DetailFixtures.file("apple-iphone-12-pro.DNG"))))
        #expect(image.quality == .preview)
        #expect(image.width == 1500 && image.height == 2000)
    }

    @Test func hifAloneStaysAtPreviewQuality() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        let request = DetailRequest(
            heif: try detailSource(heif), displayPixels: 1200, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline().preview(for: request))
        // G1 "Preview, detail (I2)": HIF alone is the embedded preview only, at preview
        // quality, even though it is smaller than the view's request.
        #expect(image.quality == .preview)
        #expect(image.width == 320)
    }

    @Test func unreadableJpegFallsBackToTheHeifPreview() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let heif = try directory.image(name: "camera.HIF", type: .heic, embedded: true)
        let request = DetailRequest(
            jpeg: try detailSource(directory.notAnImage(name: "broken.JPG")),
            heif: try detailSource(heif), displayPixels: 300, locationIdentity: "folder")
        let image = try availableDetail(try await pipeline().preview(for: request))
        #expect(image.source.url == heif.standardizedFileURL)
        #expect(image.quality == .preview)
    }

    @Test func cacheServesTheSecondRequestFromMemory() async throws {
        let cache = DetailCache()
        let pipeline = pipeline(cache)
        let request = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"))
        _ = try availableDetail(try await pipeline.preview(for: request))
        #expect(cache.previewCount >= 1)
        let start = ContinuousClock.now
        _ = try availableDetail(try await pipeline.preview(for: request))
        #expect(ContinuousClock.now - start < .milliseconds(200))
        #expect(cache.previewCount == 1)
    }
}
