import CoreGraphics
import Foundation
import Testing

@testable import CloveImaging

@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailDisplayModeTests {
    private func request(
        position: Int = 0, mode: DetailDisplayMode = .rawFirst,
        camera: DetailSource? = nil, location: String = "display-tests"
    ) throws -> DetailRequest {
        DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            heif: camera, displayPixels: 1800, wantsNativeResolution: false,
            locationIdentity: location, mode: mode, screenPixels: 1800, position: position)
    }

    @Test func scaledRawLongEdgeAndHeldReturn() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .real, holdNative: false, holdPreview: false)
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let first = try request()
        let next = try request(position: 1, location: "next")
        await pipeline.navigate(to: first, neighbours: [next])
        let preview = try availableDetail(try await pipeline.preview(for: first))
        #expect(preview.quality == .preview)
        let rendered = try availableDetail(try await pipeline.screen(for: first))
        #expect(rendered.quality == .screenRAW)
        #expect(abs(rendered.longEdge - 1800) <= 2)
        #expect(rendered.fullResolutionSize == CGSize(width: 2768, height: 1848))
        await pipeline.navigate(to: next, neighbours: [first])
        _ = try await pipeline.screen(for: next, priority: .prefetch)
        await pipeline.navigate(to: first, neighbours: [next])
        let returning = try availableDetail(try await pipeline.preview(for: first))
        #expect(returning.quality == .screenRAW)
        #expect(returning.image === rendered.image)
        #expect(await gate.nativePaths.count == 2)
        #expect(cache.screenCount == 2)
        let durations = await pipeline.takeScreenRenderDurations()
        #expect(durations.count == 2)
        print(
            "DISPLAY screen RAW fixture n=\(durations.count) ms=\(durations.map { String(format: "%.1f", $0) }.joined(separator: ",")); macOS debug, shared host, informational only"
        )
        #expect(await pipeline.takeScreenRenderDurations().isEmpty)
    }

    @Test func heldRenderLimitEvictsFarthestAndWindowDropsDistantPhotos() async throws {
        let cache = DetailCache()
        let pixels = try makeDetailImage(width: 64, height: 48)
        let requests = try (0..<5).map { try request(position: $0, location: "photo-\($0)") }
        for request in requests {
            let image = DetailImage(
                image: pixels, source: request.raw!, quality: .screenRAW, hasRAW: true)
            cache.storeScreen(image, for: request)
            #expect(cache.screenCount <= 3)
        }
        #expect(cache.screen(for: requests[0]) != nil)
        #expect(cache.screen(for: requests[1]) != nil)
        #expect(cache.screen(for: requests[2]) != nil)
        #expect(cache.screen(for: requests[3]) == nil)
        #expect(cache.screen(for: requests[4]) == nil)
        cache.navigate(to: requests[2], neighbours: [requests[1], requests[3]])
        #expect(cache.screen(for: requests[0]) == nil)
        #expect(cache.screenCount == 2)
    }

    @Test func leavingDropsQueuedScreenAndDrainedPixels() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let first = try request()
        let second = try request(position: 1, location: "next")
        let active = Task { try await pipeline.screen(for: first) }
        defer { Task { await gate.release() } }
        try await eventually { await gate.nativePaths.count == 1 }
        let queued = Task { try await pipeline.screen(for: second, priority: .prefetch) }
        try await eventually { await pipeline.queuedCount == 1 }
        await pipeline.navigate(to: first, neighbours: [second])
        await expectCancelled(queued)
        await expectCancelled(active)
        try await letEntriesFinish(gate, natives: 1)
        try await eventually { await pipeline.activeCount == 0 }
        #expect(await gate.nativePaths.count == 1)
        #expect(cache.screenCount == 0)
        #expect(await pipeline.takeScreenRenderDurations().isEmpty)
    }

    @Test func cameraModeUsesFullHeicAndReleasesOnLeaving() async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let heic = try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC"))
        let camera = try request(mode: .cameraPreviewFirst, camera: heic)
        await pipeline.navigate(to: camera, neighbours: [])
        _ = try await pipeline.preview(for: camera)
        _ = try await pipeline.screen(for: camera)
        let full = try availableDetail(try await pipeline.image(for: camera))
        #expect(full.quality == .raster)
        #expect(full.source == heic)
        #expect(full.width == 2768 && full.height == 1848)
        #expect(await gate.nativePaths.isEmpty)
        #expect(cache.holdsNativeImage)
        #expect(cache.previewCount > 0)
        let next = try request(
            position: 1, mode: .cameraPreviewFirst, camera: heic, location: "next")
        await pipeline.navigate(to: next, neighbours: [])
        #expect(!cache.holdsNativeImage)
        #expect(await pipeline.takeScreenRenderDurations().isEmpty)
    }

    @Test func cameraModeRawOnlyAndUnreadableCameraUseRawAtFitAndZoom() async throws {
        let directory = try DetailTestDirectory()
        defer { directory.remove() }
        let broken = try detailSource(directory.notAnImage(name: "bad.HIF"))
        for camera in [nil, broken] {
            let pipeline = DetailPipeline()
            let photo = try request(mode: .cameraPreviewFirst, camera: camera)
            let fit = try availableDetail(try await pipeline.screen(for: photo))
            #expect(fit.quality == .screenRAW)
            let full = try availableDetail(try await pipeline.image(for: photo))
            #expect(full.quality == .nativeRAW)
            let returning = try availableDetail(try await pipeline.preview(for: photo))
            #expect(returning.quality == .screenRAW)
        }
    }

    @Test func rawJpegSetUsesSelectedColourSource() async throws {
        let raw = try detailSource(DetailFixtures.file("sony-ilce-7s.ARW"))
        let jpeg = try detailSource(DetailFixtures.file("canon-eos-6d.JPG"))
        let pipeline = DetailPipeline()
        let request = DetailRequest(
            raw: raw, jpeg: jpeg, displayPixels: 1800,
            wantsNativeResolution: true, locationIdentity: "raw-jpeg", mode: .cameraPreviewFirst)
        let full = try availableDetail(try await pipeline.image(for: request))
        #expect(full.quality == .raster)
        #expect(full.source == jpeg)
        #expect(full.width == 5472 && full.height == 3648)
    }
}
