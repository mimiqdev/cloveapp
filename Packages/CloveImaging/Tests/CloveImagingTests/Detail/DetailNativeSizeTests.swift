import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import CloveImaging

/// The native size a double-tap to 100% uses, read before a render lands (PRD P0-04; G1
/// "Preview, detail (I2)").
///
/// The fixture tests compare the size with the pixels the photo's own route produces, so the two
/// cannot drift apart: `nativeRAW` for a RAW-primary photo and `fullRaster` for a JPEG-primary one.
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
actor DetailNativeSizeFixtureTests {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.NativeSizeFixtures")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// The RAW extensions the fixture set holds; every one must answer the size its render uses.
    private static let rawExtensions: Set<String> = [
        "cr3", "nef", "arw", "raf", "orf", "rw2", "dng",
    ]

    /// The ProRAW DNG's render is compared in `portraitHeaderIsOrientedLikeTheNativeRender`.
    ///
    /// This file's decode takes seconds when another test decodes it at the same time, and the
    /// fixture timings decode it as well, so repeating it here stalls the whole test run. The
    /// assertion is the same one every other fixture makes below.
    private static let renderComparedWithThePortraitTest: Set<String> = [
        "apple-iphone-12-pro.DNG"
    ]

    @Test func everyRAWFixtureAnswersTheSizeItsRenderProduces() async throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: DetailFixtures.formats.path)
            .sorted()
            .filter { Self.rawExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        #expect(names.count >= 8, "The fixture set lost its RAW files")

        for name in names {
            let url = DetailFixtures.file(name)
            let source = try detailSource(url)
            // The decoder's own size, read without rendering: this is what the first preview
            // carries, so the double-tap target is the size the render then produces (#111).
            let decoded = try #require(DetailNativeSize.raw(source), "No decoder size for \(name)")
            let pipeline = DetailPipeline(cache: DetailCache())
            let preview = try availableDetail(
                try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
            await pipeline.close()

            let previewPixels = CGSize(width: preview.width, height: preview.height)
            #expect(preview.hasRAW, "\(name) lost its RAW")
            #expect(preview.fullResolutionSize == decoded, "\(name) preview size")
            // A RAW's preview never answers its own pixels as 100% (PRD P0-04; G1 "Preview,
            // detail (I2)").
            #expect(
                preview.fullResolutionPixels != previewPixels,
                "\(name) answered the preview's 100%")

            if !Self.renderComparedWithThePortraitTest.contains(name) {
                let rendered = try #require(
                    await DetailRenderer().nativeRAW(source), "No render for \(name)")
                #expect(
                    decoded == CGSize(width: rendered.width, height: rendered.height),
                    "\(name) decoded a size its render does not produce")
            }
        }
    }

    @Test func arwHeaderMatchesTheNativeRender() async throws {
        let source = try detailSource(DetailFixtures.file("sony-ilce-7s.ARW"))

        let header = try #require(DetailNativeSize.header(source))
        let rendered = try #require(await DetailRenderer().nativeRAW(source))

        #expect(header == CGSize(width: 2768, height: 1848))
        #expect(header == CGSize(width: rendered.width, height: rendered.height))
    }

    @Test func portraitHeaderIsOrientedLikeTheNativeRender() async throws {
        // The ProRAW fixture is 4032×3024 with EXIF orientation 6, so the photo is 3024×4032.
        let source = try detailSource(DetailFixtures.file("apple-iphone-12-pro.DNG"))

        let header = try #require(DetailNativeSize.header(source))
        let rendered = try #require(await DetailRenderer().nativeRAW(source))
        let decoded = try #require(DetailNativeSize.raw(source))

        #expect(header == CGSize(width: 3024, height: 4032))
        #expect(header == CGSize(width: rendered.width, height: rendered.height))
        // The decoder read the first preview carries is the size this render produces.
        #expect(decoded == CGSize(width: rendered.width, height: rendered.height))
    }

    @Test func jpegHeaderMatchesTheFullRaster() async throws {
        let source = try detailSource(DetailFixtures.file("canon-eos-6d.JPG"))

        let header = try #require(DetailNativeSize.header(source))
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
        let native = try #require(preview.fullResolutionPixels)
        #expect(preview.quality == .preview)
        #expect(preview.hasRAW)
        #expect(preview.longEdge < Int(native.width))
        #expect(preview.fullResolutionSize == CGSize(width: 2768, height: 1848))
        #expect(rendered.quality == .nativeRAW)
        #expect(rendered.fullResolutionSize == preview.fullResolutionSize)
        #expect(
            CGSize(width: rendered.width, height: rendered.height)
                == preview.fullResolutionSize)
    }

    @Test func aHeaderThatDescribesThePreviewIsNotTrustedForARAW() async throws {
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        // The shape of the device bug (#111): the read describes the embedded preview rather than
        // the sensor, which is what a camera without usable index-0 properties gives.
        let previewPixels = CGSize(width: 1616, height: 1080)
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: DetailRenderer(),
            sizes: StubDetailNativeSizeReader(size: previewPixels))

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        // A RAW is never smaller than its embedded preview, so this answer is not the RAW's: the
        // double tap has no target and must not zoom to the preview's pixels (PRD P0-04).
        #expect(preview.hasRAW)
        #expect(preview.fullResolutionSize == nil)
        #expect(preview.fullResolutionPixels == nil)

        // The render is the photo's own pixels, so its size is 100% from then on.
        let rendered = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))
        #expect(rendered.quality == .nativeRAW)
        #expect(rendered.fullResolutionPixels == CGSize(width: 2768, height: 1848))
        #expect(rendered.fullResolutionPixels != previewPixels)
    }

    @Test func aRAWWithNoSizeNeverAnswersThePreviews100Percent() async throws {
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: DetailRenderer(),
            sizes: StubDetailNativeSizeReader(size: nil))

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(preview.hasRAW)
        #expect(preview.fullResolutionSize == nil)
        #expect(preview.fullResolutionPixels == nil)

        let rendered = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))
        #expect(rendered.fullResolutionSize == CGSize(width: 2768, height: 1848))
    }

    @Test func aWrongNonNilSizeIsReplacedByTheRendersOwnSize() async throws {
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        // Larger than the preview, so the trust rule keeps it: a size that is plausible but
        // wrong, which is the state the view's one retarget corrects (#111).
        let wrong = CGSize(width: 4000, height: 3000)
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: DetailRenderer(),
            sizes: StubDetailNativeSizeReader(size: wrong))

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(preview.fullResolutionSize == wrong)

        let rendered = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))
        // The render reports its own size, so the view has a different size to correct to; its
        // rule is `DetailZoom.retargetedFullResolutionScale` (PRD P0-04).
        #expect(rendered.fullResolutionSize == CGSize(width: 2768, height: 1848))
        #expect(rendered.fullResolutionSize != preview.fullResolutionSize)
    }

    @Test func aRenderRemembersTheSizeTheReadCouldNotGive() async throws {
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: DetailRenderer(),
            sizes: StubDetailNativeSizeReader(size: nil))

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(preview.fullResolutionPixels == nil)

        let rendered = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))
        #expect(rendered.fullResolutionSize == CGSize(width: 2768, height: 1848))

        // The render is the photo's own pixels, so coming back to the photo knows its 100% without
        // another decoder read (PRD P0-04; G1 "Preview, detail (I2)").
        let again = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(again.fullResolutionSize == CGSize(width: 2768, height: 1848))
    }

    @Test func aRAWWithoutASizeWhoseRenderFailsStillLeavesNo100Percent() async throws {
        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        let gate = DetailReadGate()
        await gate.configure(behaviour: .fail, holdNative: false, holdPreview: false)
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: GatedDetailReader(gate: gate),
            sizes: StubDetailNativeSizeReader(size: nil))

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(preview.hasRAW)
        #expect(preview.fullResolutionPixels == nil)

        let failed = try availableDetail(
            try await pipeline.image(for: try rawRequest(url, displayPixels: 1200, native: true)))
        // The preview stays with the failure reported, and it still has no 100%: the view's rule
        // then inspects the preview instead of doing nothing (PRD P0-04; #111).
        #expect(failed.limitation == .rawRenderFailed)
        #expect(failed.fullResolutionSize == nil)
        #expect(failed.fullResolutionPixels == nil)
        #expect(await gate.nativePaths.count == 1)
    }

    @Test func aJpegPrimaryPreviewCarriesTheFullJpegSize() async throws {
        let pipeline = DetailPipeline(cache: DetailCache())
        let request = try rasterRequest(
            DetailFixtures.file("canon-eos-6d.JPG"), displayPixels: 1200)

        let preview = try availableDetail(try await pipeline.preview(for: request))

        // A JPEG-primary photo's 100% is the full JPEG, which `fullRaster` decodes.
        #expect(preview.quality == .raster)
        #expect(!preview.hasRAW)
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
        #expect(first.hasRAW)
        #expect(first.fullResolutionSize == CGSize(width: 2768, height: 1848))

        // The same cached HIF preview asked for a HIF-only photo has no larger size to report,
        // so it must not keep the RAW's 100% from the earlier request.
        let heifOnly = DetailRequest(
            heif: heifSource, displayPixels: 1200, locationIdentity: "folder")
        let second = try availableDetail(try await pipeline.preview(for: heifOnly))
        #expect(second.source.url.lastPathComponent == "camera.HIF")
        #expect(!second.hasRAW)
        #expect(second.fullResolutionSize == nil)
        #expect(second.fullResolutionPixels == CGSize(width: 1200, height: 800))
    }

    @Test func coldRAWPreviewUsesHeaderSizeWithoutNativeDecoderReadUntilRender() async throws {
        final class RecordingSizeReader: DetailNativeSizeReading, Sendable {
            private let nativeCount = Mutex(0)
            private let previewCount = Mutex(0)
            let previewAnswer: CGSize?
            let nativeAnswer: CGSize?
            init(previewAnswer: CGSize?, nativeAnswer: CGSize?) {
                self.previewAnswer = previewAnswer
                self.nativeAnswer = nativeAnswer
            }
            var nativeCalls: Int { nativeCount.withLock { $0 } }
            var previewCalls: Int { previewCount.withLock { $0 } }
            func previewSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
                previewCount.withLock { $0 += 1 }
                return previewAnswer
            }
            func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
                nativeCount.withLock { $0 += 1 }
                return nativeAnswer
            }
        }

        let url = DetailFixtures.file("sony-ilce-7s.ARW")
        let gate = DetailReadGate()
        let sizes = RecordingSizeReader(
            previewAnswer: CGSize(width: 2768, height: 1848),
            nativeAnswer: CGSize(width: 2768, height: 1848))
        let pipeline = DetailPipeline(
            cache: DetailCache(), reader: GatedDetailReader(gate: gate), sizes: sizes)

        let preview = try availableDetail(
            try await pipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(sizes.previewCalls == 1)
        #expect(sizes.nativeCalls == 0)
        #expect(preview.fullResolutionSize == CGSize(width: 2768, height: 1848))

        // When previewSize returns nil, preview does not cache .unknown so screen still calls nativeSize.
        let nilPreviewSizes = RecordingSizeReader(
            previewAnswer: nil, nativeAnswer: CGSize(width: 2768, height: 1848))
        let fallbackPipeline = DetailPipeline(
            cache: DetailCache(), reader: GatedDetailReader(gate: gate), sizes: nilPreviewSizes)
        let previewWithoutHeader = try availableDetail(
            try await fallbackPipeline.preview(for: try rawRequest(url, displayPixels: 1200)))
        #expect(nilPreviewSizes.previewCalls == 1)
        #expect(nilPreviewSizes.nativeCalls == 0)
        #expect(previewWithoutHeader.fullResolutionSize == nil)

        let screen = try availableDetail(
            try await fallbackPipeline.screen(for: try rawRequest(url, displayPixels: 1200)))
        #expect(nilPreviewSizes.nativeCalls == 1)
        #expect(screen.fullResolutionSize == CGSize(width: 2768, height: 1848))
    }
}

/// Size reads that need no fixture: the orientation rule, the RAW decoder's own read, and the
/// per-photo fallback that keeps a preview from answering 100% (PRD P0-04; G1 "Preview, detail
/// (I2)").
@Suite(.serialized)
actor DetailNativeSizeTests {
    private nonisolated let queue = DispatchSerialQueue(label: "CloveTests.NativeSize")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    @Test func aPortraitJpegHeaderIsOrientedLikeItsFullRaster() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(
            name: "portrait.JPG", orientation: 6, width: 2400, height: 1600)
        let source = try detailSource(file)

        let header = try #require(DetailNativeSize.header(source))
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

    @Test func aFileNoReaderCanOpenHasNoSize() throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.notAnImage(name: "broken.ARW")
        let source = try detailSource(file)

        #expect(DetailNativeSize.header(source) == nil)
        // No RAW decoder opens it either, which is why the header is the fallback and not the
        // other way round (PRD P0-04; G1 "Preview, detail (I2)").
        #expect(DetailNativeSize.raw(source) == nil)
    }

    @Test func theJPEGPrimaryReadsItsHeaderAndARAWItsDecoderSize() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let file = try directory.image(name: "primary.JPG", width: 2400, height: 1600)
        let source = try detailSource(file)
        let reader = DetailNativeSizeReader()

        #expect(reader.nativeSize(of: source, isRAW: false) == CGSize(width: 2400, height: 1600))
        // A raster file has no RAW decoder, so a RAW read falls back to the header the same way
        // an unsupported RAW would.
        #expect(reader.nativeSize(of: source, isRAW: true) == CGSize(width: 2400, height: 1600))
    }

    @Test func anImageAtItsBestNeverAsksForMorePixels() throws {
        let source = DetailSource(
            url: URL(fileURLWithPath: "/missing/photo.ARW"),
            revision: ThumbnailRevision(size: 0, modificationTime: .distantPast))
        let native = CGSize(width: 8640, height: 5760)
        func image(
            _ width: Int, _ height: Int, _ quality: DetailQuality, _ size: CGSize?,
            hasRAW: Bool = false
        ) throws -> DetailImage {
            DetailImage(
                image: try makeDetailImage(width: width, height: height), source: source,
                quality: quality, hasRAW: hasRAW, fullResolutionSize: size)
        }

        // A native RAW render is the photo's full resolution, and a full raster answers a JPEG's
        // 100%, so asking either for more would repeat the same pixels (G1 "Preview, detail").
        #expect(try image(8640, 5760, .nativeRAW, native, hasRAW: true).isBestAvailable)
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
        #expect(try !image(1616, 1080, .preview, native, hasRAW: true).isBestAvailable)
        // A raster or preview whose size is unknown may still find the render's size, so it asks
        // rather than treating its own size as the photo's.
        #expect(try !image(1616, 1080, .raster, nil).isBestAvailable)
        #expect(try !image(1616, 1080, .preview, nil).isBestAvailable)
    }

    @Test func aPreviewWithoutASizeFallsBackToItsOwnPixelsWithoutARAW() throws {
        let image = DetailImage(
            image: try makeDetailImage(width: 320, height: 240),
            source: DetailSource(
                url: URL(fileURLWithPath: "/missing/photo.HIF"),
                revision: ThumbnailRevision(size: 0, modificationTime: .distantPast)),
            quality: .preview, hasRAW: false)

        #expect(image.fullResolutionSize == nil)
        #expect(image.fullResolutionPixels == CGSize(width: 320, height: 240))
    }

    @Test func aRAWWithoutASizeHasNo100Percent() throws {
        let image = DetailImage(
            image: try makeDetailImage(width: 1616, height: 1080),
            source: DetailSource(
                url: URL(fileURLWithPath: "/missing/photo.ARW"),
                revision: ThumbnailRevision(size: 0, modificationTime: .distantPast)),
            quality: .preview, hasRAW: true)

        // The preview's pixels are not the RAW's 100%, so an unknown size has no target at all
        // (PRD P0-04; G1 "Preview, detail (I2)"; #111).
        #expect(image.hasRAW)
        #expect(image.fullResolutionSize == nil)
        #expect(image.fullResolutionPixels == nil)
    }
}
