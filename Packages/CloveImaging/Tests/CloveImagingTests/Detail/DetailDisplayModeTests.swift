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
        await pipeline.navigate(to: first)
        let preview = try availableDetail(try await pipeline.preview(for: first))
        #expect(preview.quality == .preview)
        let rendered = try availableDetail(try await pipeline.screen(for: first))
        #expect(rendered.quality == .screenRAW)
        #expect(abs(rendered.longEdge - 1800) <= 2)
        #expect(rendered.fullResolutionSize == CGSize(width: 2768, height: 1848))
        await pipeline.navigate(to: next)
        _ = try await pipeline.screen(for: next, priority: .prefetch)
        await pipeline.navigate(to: first)
        let returning = try availableDetail(try await pipeline.preview(for: first))
        #expect(returning.quality == .screenRAW)
        #expect(returning.width == rendered.width && returning.height == rendered.height)
        #expect(returning.source == rendered.source)
        #expect(await gate.nativePaths.count == 2)
        #expect(cache.screen(for: first) != nil && cache.screen(for: next) != nil)
    }

    @Test(arguments: [false, true])
    func revisitAfterTenOtherPhotosUsesCompressedPixels(screen: Bool) async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let first = try request()
        for index in 0...10 {
            let photo =
                index == 0 ? first : try request(position: index, location: "photo-\(index)")
            await pipeline.navigate(to: photo)
            if screen {
                _ = try await pipeline.screen(for: photo)
            } else {
                _ = try await pipeline.preview(for: photo)
            }
        }
        let entries = await gate.totalEntries
        await pipeline.navigate(to: first)
        let returning = try availableDetail(try await pipeline.preview(for: first))
        #expect(returning.quality == (screen ? .screenRAW : .preview))
        if screen { _ = try await pipeline.screen(for: first) }
        #expect(await gate.totalEntries == entries)
        #expect(cache.compressedCost < 64 * 1024 * 1024)
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
        await pipeline.leavePhoto(generation: 1)
        await expectCancelled(queued)
        await expectCancelled(active)
        try await letEntriesFinish(gate, natives: 1)
        try await eventually { await pipeline.activeCount == 0 }
        #expect(await gate.nativePaths.count == 1)
        #expect(cache.screen(for: first) == nil)
    }

    @Test func arrivalReusesRunningOneAheadEvenWhenItsCallerCancels() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let first = try request()
        let next = try request(position: 1, location: "next")
        await pipeline.beginNavigation(1)
        await pipeline.navigate(to: first, generation: 1)
        let ahead = Task { try await pipeline.screen(for: next, priority: .prefetch) }
        defer { Task { await gate.release() } }
        try await eventually { await gate.nativePaths.count == 1 }
        ahead.cancel()
        await pipeline.beginNavigation(2)
        await pipeline.navigate(to: next, generation: 2)
        let visible = Task { try await pipeline.screen(for: next) }
        try await eventually { await pipeline.queuedCount == 1 }
        try await letEntriesFinish(gate, natives: 1)
        await expectCancelled(ahead)
        let shown = try availableDetail(try await visible.value)
        #expect(shown.quality == .screenRAW)
        #expect(cache.screen(for: next)?.source == shown.source)
        #expect(await gate.nativePaths.count == 1)
        #expect(await gate.maximumNativeEntries == 1)
    }

    @Test func cameraModeUsesFullHeicAndReleasesOnLeaving() async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let heic = try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC"))
        let camera = try request(mode: .cameraPreviewFirst, camera: heic)
        await pipeline.navigate(to: camera)
        _ = try await pipeline.preview(for: camera)
        _ = try await pipeline.screen(for: camera)
        let full = try availableDetail(try await pipeline.image(for: camera))
        #expect(full.quality == .raster)
        #expect(full.source == heic)
        #expect(full.width == 2768 && full.height == 1848)
        #expect(await gate.nativePaths.isEmpty)
        #expect(cache.holdsNativeImage)
        #expect(cache.imageCount > 0)
        let next = try request(
            position: 1, mode: .cameraPreviewFirst, camera: heic, location: "next")
        await pipeline.navigate(to: next)
        #expect(!cache.holdsNativeImage)
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
