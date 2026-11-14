import Foundation
import Testing

@testable import CloveImaging

/// G1 "Scheduling and cache": one RAW render at a time, the photo on screen before
/// neighbour prefetch, and stale work cancelled before it starts or discarded after it drains.
@Suite(.serialized, .enabled(if: DetailFixtures.hasFormats))
struct DetailSchedulingTests {
    /// Distinct locations keep each request out of the others' cache entries, so the gate
    /// sees every entry instead of a cache hit.
    private func previewRequest(_ name: String, index: Int) throws -> DetailRequest {
        try rawRequest(
            DetailFixtures.file(name), displayPixels: 1200, location: "folder-\(index)")
    }

    /// Admission tests need file revisions, but not camera decoding or RAW-size discovery.
    /// Keep those operations synthetic too, so render-entry deadlines measure scheduling.
    private func makePipeline(
        _ gate: DetailReadGate, previewWorkers: Int = 2, queueLimit: Int = 16
    ) -> DetailPipeline {
        let previews = [
            "sony-ilce-7s.ARW", "canon-eos-r6.CR3", "nikon-d500.NEF", "fujifilm-x-s10.RAF",
        ].map { DetailPreviewSubstitution(file: $0, width: 1200, height: 800) }
        return DetailPipeline(
            cache: DetailCache(), previewWorkers: previewWorkers, queueLimit: queueLimit,
            reader: GatedDetailReader(gate: gate, substitutions: previews),
            sizes: StubDetailNativeSizeReader(size: nil))
    }

    @Test func rawRendersStaySerial() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate)
        let first = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true),
                consumer: UUID())
        }
        try await eventually("First RAW render enters the gate") {
            await gate.nativePaths.count == 1
        }
        let second = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("canon-eos-r6.CR3"), native: true),
                consumer: UUID())
        }
        try await eventually("Second RAW render queues") { await pipeline.queuedCount == 1 }
        // The second render waits for the first slot: one RAW render at a time.
        #expect(await gate.nativePaths.count == 1)
        #expect(await pipeline.activeRenderCount == 1)
        #expect(await pipeline.nativeRAWRenderCount == 1)
        await gate.release()
        try await eventually("Second RAW render enters after release") {
            await gate.nativePaths.count == 2
        }
        #expect(await gate.maximumNativeEntries == 1)
        #expect(await pipeline.nativeRAWRenderCount == 2)
        try await letEntriesFinish(gate, natives: 2)
        _ = try await first.value
        _ = try await second.value
        #expect(await gate.maximumNativeEntries == 1)
    }

    @Test func queuedRenderIsDroppedWhenANewerOneArrives() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate)
        let active = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("canon-eos-r6.CR3"), native: true),
                consumer: UUID())
        }
        try await eventually { await gate.nativePaths.count == 1 }
        let queued = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true),
                consumer: UUID())
        }
        try await eventually { await pipeline.queuedCount == 1 }
        let latest = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("nikon-d500.NEF"), native: true),
                consumer: UUID())
        }
        // G1: a queued render is obsolete once a newer one arrives, so it never enters.
        await expectCancelled(queued)
        await gate.release()
        try await eventually { await gate.nativePaths.count == 2 }
        #expect(await gate.nativePaths.last?.hasSuffix("nikon-d500.NEF") == true)
        try await letEntriesFinish(gate, natives: 2)
        _ = try await active.value
        _ = try await latest.value
    }

    @Test func supersededRenderDrainsItsResultIntoNothing() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate)
        let consumer = UUID()
        let old = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true),
                consumer: consumer)
        }
        try await eventually { await gate.nativePaths.count == 1 }
        let newer = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("nikon-d500.NEF"), native: true),
                consumer: consumer)
        }
        // The drained render cannot be interrupted, but its result must never be delivered.
        await expectCancelled(old)
        #expect(await pipeline.activeRenderCount == 1)
        await gate.release()
        try await eventually { await gate.nativePaths.count == 2 }
        try await letEntriesFinish(gate, natives: 2)
        let image = try availableDetail(try await newer.value)
        #expect(image.source.url.lastPathComponent == "nikon-d500.NEF")
        #expect(image.quality == .nativeRAW)
    }

    @Test func visiblePreviewWorkGoesBeforeQueuedPrefetch() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: false, holdPreview: true)
        let pipeline = makePipeline(gate, previewWorkers: 1)
        let active = Task {
            try await pipeline.preview(for: try previewRequest("sony-ilce-7s.ARW", index: 1))
        }
        try await eventually { await gate.previewPaths.count == 1 }
        let neighbour = Task {
            try await pipeline.prefetchPreview(for: try previewRequest("nikon-d500.NEF", index: 2))
        }
        try await eventually { await pipeline.queuedCount == 1 }
        let visible = Task {
            try await pipeline.preview(for: try previewRequest("canon-eos-r6.CR3", index: 3))
        }
        try await eventually { await pipeline.queuedCount == 2 }
        await gate.release()
        try await eventually { await gate.previewPaths.count == 2 }
        // G1: the photo on screen comes before neighbour prefetch.
        #expect(await gate.previewPaths.last?.hasSuffix("canon-eos-r6.CR3") == true)
        try await letEntriesFinish(gate, previews: 3)
        _ = try await active.value
        _ = try await visible.value
        _ = try await neighbour.value
    }

    @Test func previewWorkersStayBounded() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: false, holdPreview: true)
        let pipeline = makePipeline(gate, previewWorkers: 2)
        let names = [
            "sony-ilce-7s.ARW", "nikon-d500.NEF", "canon-eos-r6.CR3", "fujifilm-x-s10.RAF",
        ]
        let tasks = try names.enumerated().map { index, name in
            let request = try previewRequest(name, index: index)
            return Task { try await pipeline.preview(for: request) }
        }
        // Both readers hold an entry and the other two wait: the bound is two at a time.
        try await eventually { await gate.previewPaths.count == 2 }
        try await eventually { await pipeline.queuedCount == 2 }
        #expect(await pipeline.activeCount == 2)
        #expect(await gate.maximumPreviewEntries == 2)
        try await letEntriesFinish(gate, previews: 4)
        for task in tasks { _ = try await task.value }
        #expect(await gate.maximumPreviewEntries == 2)
    }

    @Test func visibleRequestDisplacesQueuedPrefetchAndQueueHasAHardLimit() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: false, holdPreview: true)
        let pipeline = makePipeline(gate, previewWorkers: 1, queueLimit: 2)
        let active = Task {
            try await pipeline.preview(for: try previewRequest("sony-ilce-7s.ARW", index: 1))
        }
        try await eventually { await gate.previewPaths.count == 1 }
        let neighbour = Task {
            try await pipeline.prefetchPreview(for: try previewRequest("nikon-d500.NEF", index: 2))
        }
        try await eventually { await pipeline.queuedCount == 1 }
        let displaced = Task {
            try await pipeline.prefetchPreview(
                for: try previewRequest("fujifilm-x-s10.RAF", index: 3))
        }
        try await eventually { await pipeline.queuedCount == 2 }
        do {
            _ = try await pipeline.prefetchPreview(
                for: try previewRequest("canon-eos-r6.CR3", index: 4))
            Issue.record("A full queue accepted more prefetch")
        } catch DetailPipelineError.queueFull {}
        let visible = Task {
            try await pipeline.preview(for: try previewRequest("sony-ilce-7s.ARW", index: 5))
        }
        await expectCancelled(displaced)
        #expect(await pipeline.queuedCount == 2)
        try await letEntriesFinish(gate, previews: 3)
        _ = try await active.value
        _ = try await visible.value
        _ = try await neighbour.value
        // G1: prefetch is the first thing dropped, and a dropped request never delivers.
        #expect(await gate.previewPaths.count == 3)
    }

    @Test func prefetchFillsPreviewsAndNeverRenders() async throws {
        let gate = DetailReadGate()
        let pipeline = makePipeline(gate)
        await pipeline.prefetch([
            try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true),
            try rawRequest(DetailFixtures.file("nikon-d500.NEF"), displayPixels: 4000),
        ])
        #expect(await gate.previewPaths.count == 2)
        // G1: prefetch covers embedded previews only, never a RAW render.
        #expect(await gate.nativePaths.isEmpty)
    }

    @Test func cancelPrefetchDropsQueuedNeighbours() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: false, holdPreview: true)
        let pipeline = makePipeline(gate, previewWorkers: 1)
        let active = Task {
            try await pipeline.preview(for: try previewRequest("sony-ilce-7s.ARW", index: 1))
        }
        try await eventually { await gate.previewPaths.count == 1 }
        let neighbour = Task {
            try await pipeline.prefetchPreview(for: try previewRequest("nikon-d500.NEF", index: 2))
        }
        try await eventually { await pipeline.queuedCount == 1 }
        await pipeline.cancelPrefetch()
        await expectCancelled(neighbour)
        try await letEntriesFinish(gate, previews: 1)
        _ = try await active.value
        #expect(await gate.previewPaths.count == 1)
    }

    @Test func closeWaitsForTheRunningRenderBeforeFolderAccessEnds() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate)
        let active = Task {
            try await pipeline.image(
                for: try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true),
                consumer: UUID())
        }
        try await eventually { await gate.nativePaths.count == 1 }
        let closing = Task {
            await pipeline.close()
            await gate.markClosed()
        }
        await expectCancelled(active)
        #expect(await gate.didClose == false)
        #expect(await pipeline.activeRenderCount == 1)
        do {
            _ = try await pipeline.preview(for: try previewRequest("sony-ilce-7s.ARW", index: 1))
            Issue.record("A closed pipeline accepted a new request")
        } catch DetailPipelineError.closed {}
        try await letEntriesFinish(gate, natives: 1)
        await closing.value
        #expect(await gate.didClose)
        #expect(await pipeline.activeCount == 0)
        await pipeline.close()
    }

    @Test func aNewerRequestFromTheSameConsumerSupersedesTheQueuedOne() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: false, holdPreview: true)
        let pipeline = makePipeline(gate, previewWorkers: 1)
        let consumer = UUID()
        let old = Task {
            try await pipeline.preview(
                for: try previewRequest("sony-ilce-7s.ARW", index: 1), consumer: consumer)
        }
        try await eventually { await gate.previewPaths.count == 1 }
        let queued = Task {
            try await pipeline.preview(
                for: try previewRequest("nikon-d500.NEF", index: 2), consumer: consumer)
        }
        try await eventually { await pipeline.queuedCount == 1 }
        let newest = Task {
            try await pipeline.preview(
                for: try previewRequest("canon-eos-r6.CR3", index: 3), consumer: consumer)
        }
        // The superseded queued request never enters, and the drained active one is discarded.
        await expectCancelled(queued)
        await expectCancelled(old)
        try await letEntriesFinish(gate, previews: 2)
        let image = try availableDetail(try await newest.value)
        #expect(image.source.url.lastPathComponent == "canon-eos-r6.CR3")
        #expect(await gate.previewPaths.count == 2)
    }

    @Test func beginNavigationCancelsNonMatchingQueuedAnalysisJobs() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate, previewWorkers: 1)
        let current = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)
        let next = try rawRequest(DetailFixtures.file("nikon-d500.NEF"), native: true)
        let active = Task { try await pipeline.image(for: current) }
        try await eventually { await gate.nativePaths.count == 1 }
        let staleAnalysis = Task { try await pipeline.analysisImage(for: current) }
        try await eventually { await pipeline.queuedCount == 1 }
        // Navigating to `next` cancels queued `.analysis` for `current` immediately in beginNavigation.
        await pipeline.beginNavigation(1, keepingAnalysisFor: [next.raw!.url])
        await expectCancelled(staleAnalysis)
        await expectCancelled(active)
        // Keeping `next` preserves an analysis queued for the destination itself.
        let keptAnalysis = Task { try await pipeline.analysisImage(for: next) }
        try await eventually { await pipeline.queuedCount == 1 }
        await pipeline.beginNavigation(2, keepingAnalysisFor: [next.raw!.url])
        #expect(await pipeline.queuedCount == 1)
        try await letEntriesFinish(gate, natives: 2)
        _ = try await keptAnalysis.value
        await pipeline.close()
    }

    @Test func queuedPrefetchBeatsQueuedAnalysisOnRenderLane() async throws {
        let gate = DetailReadGate()
        await gate.configure(behaviour: .synthetic, holdNative: true, holdPreview: false)
        let pipeline = makePipeline(gate, previewWorkers: 1)
        let holder = try rawRequest(DetailFixtures.file("sony-ilce-7s.ARW"), native: true)
        let analysisTarget = try rawRequest(DetailFixtures.file("nikon-d500.NEF"), native: true)
        let prefetchTarget = try rawRequest(DetailFixtures.file("canon-eos-r6.CR3"))
        let running = Task { try await pipeline.image(for: holder) }
        try await eventually { await gate.nativePaths.count == 1 }
        let analysis = Task { try await pipeline.analysisImage(for: analysisTarget) }
        try await eventually { await pipeline.queuedCount == 1 }
        let prefetch = Task { try await pipeline.prefetchScreen(for: prefetchTarget) }
        try await eventually { await pipeline.queuedCount == 2 }
        // Release the holder, then allow the next render entry to finish: `.prefetch` must claim the lane first.
        try await letEntriesFinish(gate, natives: 2)
        _ = try await running.value
        _ = try await prefetch.value
        #expect(
            await gate.nativePaths.dropFirst().first
                == DetailFixtures.file("canon-eos-r6.CR3").standardizedFileURL.path)
        try await letEntriesFinish(gate, natives: 3)
        _ = try await analysis.value
        await pipeline.close()
    }
}
