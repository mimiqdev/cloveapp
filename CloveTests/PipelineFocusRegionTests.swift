import CloveCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Clove
@testable import CloveImaging

@Suite(.serialized)
@MainActor
struct PipelineFocusRegionTests {
    @Test func openingTheCurrentPhotoDoesNotCancelItsAnalysis() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let environment = makeEnvironment(photos: [first])
        defer {
            Task { await environment.finish() }
        }
        let analysis = Task {
            await environment.source.analyzeRegions(for: first.id, group: [], nearby: []) { _ in }
        }
        try await pipelineEventually {
            await environment.reads.fullRasterPaths.count == 1
        }

        // This is the real prepare/beginNavigation/navigate sequence, after analysis has
        // entered the production pipeline but before its acquisition finishes.
        await environment.source.prepare(environment.window(for: first))
        await environment.reads.releaseFullRasters()
        let result = await analysis.value
        #expect(result != nil)
        #expect(result?.acquisitionFailure == nil)
    }

    @Test func navigationCancelsAnalysisForThePhotoLeftBehind() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let second = try fixture.photo("second.jpg")
        let environment = makeEnvironment(photos: [first, second])
        defer {
            Task { await environment.finish() }
        }
        let analysis = Task {
            await environment.source.analyzeRegions(for: first.id, group: [], nearby: []) { _ in }
        }
        try await pipelineEventually {
            await environment.reads.fullRasterPaths.count == 1
        }

        await environment.source.prepare(environment.window(for: second))
        await environment.reads.releaseFullRasters()
        let result = await analysis.value
        #expect(result?.acquisitionFailure == .closed)
    }

    @Test func previousCurrentPhotoLosesUrgencyWhenRetainedAsNearby() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let second = try fixture.photo("second.jpg")
        let environment = makeEnvironment(photos: [first, second])
        defer { Task { await environment.finish() } }
        await environment.scheduler.pause()
        let firstView = Task {
            await environment.source.analyzeRegions(for: first.id, group: [], nearby: []) { _ in }
        }
        try await pipelineEventually {
            await environment.scheduler.snapshot().queuedByPriority[.current] == 1
        }
        let nextView = Task {
            await environment.source.analyzeRegions(for: second.id, group: [], nearby: [first.id]) {
                _ in
            }
        }
        try await pipelineEventually {
            let queued = await environment.scheduler.snapshot().queuedByPriority
            return queued[.current] == 1 && queued[.nearby] == 1
        }
        await environment.scheduler.close()
        _ = await firstView.value
        _ = await nextView.value
    }

    @Test func changingCurrentPhotoCancelsObsoleteSchedulerWork() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let second = try fixture.photo("second.jpg")
        let environment = makeEnvironment(photos: [first, second])
        defer { Task { await environment.finish() } }
        let oldEarly = PipelineCallbackBox()
        let obsolete = Task {
            await environment.source.analyzeRegions(for: first.id, group: [], nearby: []) {
                oldEarly.record($0)
            }
        }
        try await pipelineEventually { await environment.reads.fullRasterPaths.count == 1 }
        await environment.source.prepare(environment.window(for: second))
        let current = Task {
            await environment.source.analyzeRegions(for: second.id, group: [], nearby: []) { _ in }
        }
        await environment.reads.releaseFullRasters()
        let oldResult = await obsolete.value
        #expect(oldResult == nil || oldResult?.acquisitionFailure == .closed)
        let result = await current.value
        #expect(result?.acquisitionFailure == nil)
    }

    @Test func queuedManualRenderingWinsOverAnalysis() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let second = try fixture.photo("second.jpg")
        let environment = makeEnvironment(photos: [first, second])
        defer {
            Task { await environment.finish() }
        }
        let request = environment.fullResolutionRequest()
        let initial = Task {
            await environment.source.image(for: second.id, request: request)
        }
        try await pipelineEventually {
            await environment.reads.fullRasterPaths.count == 1
        }
        let manual = Task {
            await environment.source.image(for: first.id, request: request)
        }
        try await pipelineEventually {
            await environment.pipeline.queuedCount == 1
        }
        let analysis = Task {
            await environment.source.analyzeRegions(for: first.id, group: [], nearby: []) { _ in }
        }
        try await pipelineEventually {
            await environment.scheduler.snapshot().stages[.pixelAcquisition]?.startedCount == 1
        }
        await environment.reads.releaseFullRasters()

        guard case .image = await manual.value else {
            Issue.record("Analysis cancelled the queued interactive render")
            return
        }
        _ = await initial.value
        _ = await analysis.value
    }

    @Test func cancelledViewerNeverReceivesAFWhenItsSharedAcquisitionFinishes() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let photo = try fixture.photo("first.jpg")
        let faces = PipelineFaceGate(holding: true)
        let environment = makeEnvironment(photos: [photo], faceGate: faces)
        defer { Task { await environment.finish() } }
        let staleEarly = PipelineCallbackBox()
        let oldViewer = Task {
            await environment.source.analyzeRegions(for: photo.id, group: [], nearby: []) {
                staleEarly.record($0)
            }
        }
        try await pipelineEventually { await environment.reads.fullRasterPaths.count == 1 }
        oldViewer.cancel()
        let currentEarly = PipelineCallbackBox()
        let currentViewer = Task {
            await environment.source.analyzeRegions(for: photo.id, group: [], nearby: []) {
                currentEarly.record($0)
            }
        }
        await environment.reads.releaseFullRasters()
        try await pipelineEventually { currentEarly.result != nil }
        #expect(staleEarly.result == nil)
        await faces.release()
        _ = await oldViewer.value
        _ = await currentViewer.value
    }

    @Test func openingAfterNearbyAnalysisDeliversEarlyAFAndCachedRevisits() async throws {
        let fixture = try PipelinePhotoFixture()
        defer { fixture.remove() }
        let first = try fixture.photo("first.jpg")
        let nearby = try fixture.photo("nearby.jpg")
        let faces = PipelineFaceGate(holding: true)
        let environment = makeEnvironment(photos: [first, nearby], faceGate: faces)
        defer {
            Task { await environment.finish() }
        }
        let opening = Task {
            await environment.source.analyzeRegions(
                for: first.id, group: [], nearby: [nearby.id]
            ) { _ in }
        }
        try await pipelineEventually {
            await environment.scheduler.snapshot().stages[.pixelAcquisition]?.startedCount == 1
        }
        await environment.reads.releaseFullRasters()
        try await pipelineEventually {
            await environment.reads.fullRasterPaths.count == 2
        }

        let early = PipelineCallbackBox()
        let joined = Task {
            await environment.source.analyzeRegions(for: nearby.id, group: [], nearby: []) {
                result in early.record(result)
            }
        }
        try await pipelineEventually {
            early.result != nil
        }
        guard case .regions(let regions) = early.result else {
            Issue.record("Expected scored AF from the shared production pipeline")
            return
        }
        #expect(regions.first?.score != nil)
        await faces.release()
        _ = await opening.value
        _ = await joined.value

        let revisitedEarly = PipelineCallbackBox()
        _ = await environment.source.analyzeRegions(for: nearby.id, group: [], nearby: []) {
            result in
            revisitedEarly.record(result)
        }
        #expect(revisitedEarly.result != nil)
    }

    private func makeEnvironment(
        photos: [PhotoSet],
        faceGate: PipelineFaceGate = PipelineFaceGate(holding: false)
    ) -> PipelineEnvironment {
        let reads = PipelineReadGate()
        let pipeline = DetailPipeline(
            cache: DetailCache(),
            reader: PipelineDetailReader(gate: reads),
            sizes: PipelineNativeSize())
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(
                reader: DetailRegionSharpnessReading(details: pipeline),
                faces: PipelineFaceDetector(gate: faceGate)))
        let byIdentity = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return PipelineEnvironment(
            source: PipelineDetailImages(
                pipeline: pipeline,
                set: { byIdentity[$0] },
                regionScheduler: scheduler),
            pipeline: pipeline, scheduler: scheduler, reads: reads, faces: faceGate)
    }

    private func fullResolutionRequest() -> DetailPixelRequest {
        DetailPixelRequest(displayPixels: 2400, need: .fullResolution, screenPixels: 1200)
    }
}

private final class PipelineCallbackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RegionSharpnessPathResult?
    var result: RegionSharpnessPathResult? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ result: RegionSharpnessPathResult) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

private struct PipelineEnvironment {
    let source: PipelineDetailImages
    let pipeline: DetailPipeline
    let scheduler: RegionSharpnessScheduler
    let reads: PipelineReadGate
    let faces: PipelineFaceGate

    func window(for photo: PhotoSet) -> DetailPhotoWindow {
        DetailPhotoWindow(
            id: UUID(), current: DetailNeighbour(photo: photo.id, position: 0),
            neighbours: [], direction: 1, mode: .rawFirst, screenPixels: 1200)
    }

    func fullResolutionRequest() -> DetailPixelRequest {
        DetailPixelRequest(displayPixels: 2400, need: .fullResolution, screenPixels: 1200)
    }

    func finish() async {
        await reads.releaseFullRasters()
        await faces.release()
        await source.closeRegionAnalysis()
        await pipeline.close()
    }
}

private actor PipelineReadGate {
    private(set) var fullRasterPaths: [String] = []
    private var holding = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fullRaster(_ source: DetailSource) async {
        fullRasterPaths.append(source.url.path)
        if holding {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func releaseFullRasters() {
        holding = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct PipelineDetailReader: DetailReading {
    let gate: PipelineReadGate

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        .image(pipelinePixels(width: 800, height: 600))
    }

    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
        await gate.fullRaster(source)
        return .image(pipelinePixels(width: 1200, height: 800))
    }

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        pipelinePixels(width: 1200, height: 800)
    }

    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage? {
        pipelinePixels(width: longEdge, height: max(1, longEdge * 2 / 3))
    }
}

private struct PipelineNativeSize: DetailNativeSizeReading {
    func nativeSize(of reference: DetailSource, isRAW: Bool) -> CGSize? {
        CGSize(width: 1200, height: 800)
    }
}

private actor PipelineFaceGate {
    private var holding: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(holding: Bool) {
        self.holding = holding
    }

    func detect() async -> FaceDetectionOutcome {
        if holding {
            await withCheckedContinuation { waiters.append($0) }
        }
        return .faces([])
    }

    func release() {
        holding = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct PipelineFaceDetector: FaceRegionDetecting {
    let gate: PipelineFaceGate

    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
        await gate.detect()
    }
}

private struct PipelinePhotoFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func photo(_ name: String) throws -> PhotoSet {
        let url = directory.appendingPathComponent(name)
        let pixels = pipelinePixels(width: 1200, height: 800)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, pixels,
            [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifPixelXDimension: 1200,
                    kCGImagePropertyExifPixelYDimension: 800,
                    kCGImagePropertyExifSubjectArea: [600, 400, 240, 160],
                ]
            ] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return try PhotoSet(
            folderID: FolderIdentity(rawValue: "pipeline-focus-tests"),
            relativeFolderPath: "", jpegURL: url)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func pipelinePixels(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@MainActor
private func pipelineEventually(
    _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(await condition())
}
