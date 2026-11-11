import CoreGraphics
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import CloveImaging

/// The only wait is bounded, even if the test fails before releasing it.
private final class DelayedDetailSizeReader: DetailNativeSizeReading, Sendable {
    private let started = Mutex(false)
    private let enabled: Mutex<Bool>
    init(enabled: Bool = true) { self.enabled = Mutex(enabled) }
    func pause() { enabled.withLock { $0 = true } }
    private let release = DispatchSemaphore(value: 0)
    var hasStarted: Bool { started.withLock { $0 } }
    func resume() { release.signal() }

    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
        if enabled.withLock({ $0 }) {
            started.withLock { $0 = true }
            _ = release.wait(timeout: .now() + 5)
        }
        return CGSize(width: 2768, height: 1848)
    }
}

@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailNavigationTests {
    @Test(arguments: [false, true])
    func cacheProbeRespectsSupersessionAndMemoryRelease(releaseImages: Bool) async throws {
        let sizes = DelayedDetailSizeReader(enabled: false)
        defer { sizes.resume() }
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: DetailRenderer(), sizes: sizes)
        let camera = DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            heif: try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC")),
            displayPixels: 1800, wantsNativeResolution: true,
            locationIdentity: "probe", mode: .cameraPreviewFirst)
        _ = try await pipeline.preview(for: camera)
        _ = try await pipeline.image(for: camera)
        sizes.pause()
        let consumer = UUID()
        let older = Task { try await pipeline.preview(for: camera, consumer: consumer) }
        defer { older.cancel() }
        try await eventually { sizes.hasStarted }
        if releaseImages {
            await pipeline.releaseCachedImages()
        } else {
            let newer = try availableDetail(
                try await pipeline.image(for: camera, consumer: consumer))
            #expect(newer.quality == .raster)
        }
        sizes.resume()
        await expectCancelled(older)
        if releaseImages { #expect(cache.imageCount == 0 && !cache.holdsNativeImage) }
        await pipeline.close()
    }

    @Test func failedNativeRenderKeepsTheCachedScreenRaw() async throws {
        let gate = DetailReadGate()
        let pipeline = DetailPipeline(cache: DetailCache(), reader: GatedDetailReader(gate: gate))
        let request = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)
        let screen = try availableDetail(try await pipeline.screen(for: request))
        await gate.configure(behaviour: .fail, holdNative: false, holdPreview: false)
        let fallback = try availableDetail(try await pipeline.image(for: request))
        #expect(fallback.quality == .screenRAW)
        #expect(fallback.width == screen.width && fallback.height == screen.height)
        #expect(fallback.source == screen.source)
        #expect(fallback.fullResolutionSize == screen.fullResolutionSize)
        #expect(fallback.limitation == .rawRenderFailed)
    }

    @Test func oldArrivalCannotReplaceNewWindowOrCancelItsRender() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let cache = DetailCache()
        let pipeline = DetailPipeline(cache: cache, reader: GatedDetailReader(gate: gate))
        let first = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), location: "old")
        let second = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), location: "new")
        await pipeline.beginNavigation(1)
        await pipeline.beginNavigation(2)
        await pipeline.navigate(to: second, generation: 2)
        let current = Task { try await pipeline.screen(for: second) }
        defer { Task { await gate.release() } }
        try await eventually { await gate.nativePaths.count == 1 }
        await pipeline.beginNavigation(1)
        await pipeline.navigate(to: first, generation: 1)
        try await letEntriesFinish(gate, natives: 1)
        let image = try availableDetail(try await current.value)
        #expect(image.quality == .screenRAW)
        #expect(cache.screen(for: second) != nil)
        #expect(cache.screen(for: first) == nil)
    }

    @Test func cancellationDuringSizeDiscoveryStartsNoRawOrFullCameraDecode() async throws {
        let heic = try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC"))
        for cameraMode in [false, true] {
            let gate = DetailReadGate()
            let sizes = DelayedDetailSizeReader()
            defer { sizes.resume() }
            let pipeline = DetailPipeline(
                cache: DetailCache(),
                reader: GatedDetailReader(gate: gate), sizes: sizes)
            let request = DetailRequest(
                raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
                heif: cameraMode ? heic : nil, displayPixels: 1800,
                wantsNativeResolution: true, locationIdentity: "cancel-size",
                mode: cameraMode ? .cameraPreviewFirst : .rawFirst)
            let task = Task { try await pipeline.image(for: request) }
            try await eventually { sizes.hasStarted }
            task.cancel()
            sizes.resume()
            await expectCancelled(task)
            try await eventually { await pipeline.activeCount == 0 }
            #expect(await gate.nativePaths.isEmpty)
            #expect(await gate.fullRasterPaths.isEmpty)
        }
    }

    @Test func cameraFullDecodeFailureKeepsRawOnLaterFitAndZoom() async throws {
        let heic = try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC"))
        let gate = DetailReadGate()
        let reader = GatedDetailReader(gate: gate, failedRasterFiles: [heic.url.lastPathComponent])
        let pipeline = DetailPipeline(cache: DetailCache(), reader: reader)
        let request = DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            heif: heic, displayPixels: 1800, wantsNativeResolution: true,
            locationIdentity: "failed-camera", mode: .cameraPreviewFirst)
        let native = try availableDetail(try await pipeline.image(for: request))
        #expect(native.quality == .nativeRAW)
        let fit = try availableDetail(try await pipeline.preview(for: request))
        #expect(fit.quality == .screenRAW)
        #expect(fit.source == request.raw)
        _ = try await pipeline.image(for: request)
        #expect(await gate.fullRasterPaths.count == 1)
        #expect(await gate.nativePaths.count == 2)
    }

    @Test func failedHeicTriesJpegWithoutRenderingRaw() async throws {
        let heic = try detailSource(DetailFixtures.file("sony-ilce-7s.HEIC"))
        let jpeg = try detailSource(DetailFixtures.file("canon-eos-6d.JPG"))
        let gate = DetailReadGate()
        let reader = GatedDetailReader(gate: gate, failedRasterFiles: [heic.url.lastPathComponent])
        let pipeline = DetailPipeline(cache: DetailCache(), reader: reader)
        let request = DetailRequest(
            raw: try detailSource(DetailFixtures.file("sony-ilce-7s.ARW")),
            jpeg: jpeg, heif: heic, displayPixels: 1800, wantsNativeResolution: true,
            locationIdentity: "camera-jpeg-fallback", mode: .cameraPreviewFirst)
        let full = try availableDetail(try await pipeline.image(for: request))
        #expect(full.source == jpeg)
        #expect(full.quality == .raster)
        #expect(full.width == 5472 && full.height == 3648)
        #expect(await gate.fullRasterPaths.count == 2)
        #expect(await gate.nativePaths.isEmpty)
    }
}
