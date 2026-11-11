import Foundation
import Synchronization
import Testing

@testable import CloveImaging

@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailCompressedSchedulingTests {
    @Test(arguments: [false, true])
    func cachedAnswerBypassesBusyWorkersAndFullQueue(screen: Bool) async throws {
        let gate = DetailReadGate()
        let cache = DetailCache()
        let pipeline = DetailPipeline(
            cache: cache, previewWorkers: 1, queueLimit: 1, reader: GatedDetailReader(gate: gate))
        let raw = DetailFixtures.file("sony-ilce-7s.ARW")
        let cached = try rawRequest(raw, location: "cached")
        if screen {
            _ = try await pipeline.screen(for: cached)
        } else {
            _ = try await pipeline.preview(for: cached)
        }
        let renderRequest = try rawRequest(raw, location: "rendering")
        _ = try await pipeline.preview(for: renderRequest)
        let warmedEntries = await gate.totalEntries
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: true)
        let rendering = Task {
            try await pipeline.screen(for: renderRequest)
        }
        let reading = Task {
            try await pipeline.preview(for: rawRequest(raw, location: "reading"))
        }
        defer {
            rendering.cancel()
            reading.cancel()
            Task { await gate.release() }
        }
        try await eventually { await gate.totalEntries == warmedEntries + 2 }
        try await eventually { await pipeline.activeRenderCount == 1 }
        let queued = Task {
            try await pipeline.preview(for: rawRequest(raw, location: "queued"))
        }
        defer { queued.cancel() }
        try await eventually { await pipeline.queuedCount == 1 }
        if screen {
            try await pipeline.prefetchScreen(for: cached)
        } else {
            try await pipeline.prefetchPreview(for: cached)
        }
        #expect(await pipeline.queuedCount == 1)
        let completed = Mutex(false)
        let hit = Task {
            defer { completed.withLock { $0 = true } }
            if screen { return try await pipeline.screen(for: cached) }
            return try await pipeline.preview(for: cached)
        }
        defer { hit.cancel() }
        // Bounded observation: a hit finishes without releasing either lane.
        try await eventually { completed.withLock { $0 } }
        let result = try availableDetail(try await hit.value)
        #expect(result.quality == (screen ? .screenRAW : .preview))
        #expect(await pipeline.queuedCount == 1)
        #expect(await pipeline.activeRenderCount == 1)
        await pipeline.releaseCachedImages()
        await gate.release()
        await expectCancelled(rendering)
        // A preview released above may already have completed.
        _ = try? await reading.value
        await expectCancelled(queued)
        await pipeline.close()
    }
}
