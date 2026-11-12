import Foundation
import Testing

@testable import CloveImaging

private actor ThumbnailDecodeGate {
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var started: [Int] = []
    private(set) var maximum = 0
    private(set) var didClose = false
    func markClosed() { didClose = true }

    func decode(_ request: ThumbnailRequest) async -> ThumbnailResult {
        started.append(request.targetPixels)
        await withCheckedContinuation { continuation in
            waiters[request.targetPixels] = continuation
            maximum = max(maximum, waiters.count)
        }
        return .unavailable(.noUsablePreview)
    }

    func finish(_ pixels: Int) { waiters.removeValue(forKey: pixels)?.resume() }
}

struct ThumbnailSchedulingTests {
    private func request(_ base: ThumbnailRequest, _ pixels: Int) -> ThumbnailRequest {
        ThumbnailRequest(
            source: base.source, revision: base.revision, targetPixels: pixels,
            locationIdentity: base.locationIdentity)
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await condition())
        try #require(await condition())
    }

    private func cancelled(_ task: Task<ThumbnailResult, any Error>) async {
        do {
            _ = try await task.value
            Issue.record("Cancelled or superseded request delivered a result")
        } catch is CancellationError {} catch { Issue.record(error) }
    }

    @Test(arguments: [2, 4]) func workersStayBounded(workers: Int) async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: workers,
            decode: { await gate.decode($0) })
        let tasks = (1...(workers + 2)).map { index in
            Task { try await pipeline.thumbnail(for: request(base, index)) }
        }
        try await eventually {
            let active = await pipeline.activeCount
            let queued = await pipeline.queuedCount
            return active == workers && queued == 2
        }
        try await eventually { await gate.started.count == workers }
        #expect(await gate.maximum == workers)
        for task in tasks { task.cancel() }
        for task in tasks { await cancelled(task) }
        #expect(await pipeline.activeCount == workers)
        for pixels in await gate.started { await gate.finish(pixels) }
        try await eventually { await pipeline.activeCount == 0 }
        #expect(await gate.started.count == workers)
    }

    @Test func queuedCancellationNeverEntersDecoder() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: 1,
            decode: { await gate.decode($0) })
        let active = Task { try await pipeline.thumbnail(for: request(base, 1)) }
        try await eventually { await gate.started == [1] }
        let queued = Task { try await pipeline.thumbnail(for: request(base, 2)) }
        try await eventually { await pipeline.queuedCount == 1 }
        queued.cancel()
        await cancelled(queued)
        await gate.finish(1)
        _ = try await active.value
        #expect(await gate.started == [1])
        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.thumbnail(for: request(base, 3))
        }
        await cancelled(preCancelled)
        #expect(await gate.started == [1])
    }

    @Test func supersededNativeWorkDrainsBeforeNewRequestAndNeverDelivers() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: 1,
            decode: { await gate.decode($0) })
        let consumer = UUID()
        let old = Task { try await pipeline.thumbnail(for: request(base, 1), consumer: consumer) }
        try await eventually { await gate.started == [1] }
        let newer = Task { try await pipeline.thumbnail(for: request(base, 2), consumer: consumer) }
        try await eventually { await pipeline.queuedCount == 1 }
        await cancelled(old)
        #expect(await gate.started == [1])
        await gate.finish(1)
        try await eventually { await gate.started == [1, 2] }
        await gate.finish(2)
        _ = try await newer.value
        #expect(await gate.maximum == 1)
    }

    @Test func visibleWorkDisplacesPrefetchAndQueueHasHardLimit() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: 1,
            queueLimit: 2, decode: { await gate.decode($0) })
        let active = Task { try await pipeline.thumbnail(for: request(base, 1)) }
        try await eventually { await gate.started == [1] }
        let prefetch = Task {
            try await pipeline.thumbnail(for: request(base, 2), priority: .prefetch)
        }
        try await eventually { await pipeline.queuedCount == 1 }
        let displaced = Task {
            try await pipeline.thumbnail(for: request(base, 3), priority: .prefetch)
        }
        try await eventually { await pipeline.queuedCount == 2 }
        do {
            _ = try await pipeline.thumbnail(for: request(base, 4), priority: .prefetch)
            Issue.record("Full queue accepted more prefetch")
        } catch ThumbnailPipelineError.queueFull {}
        let visible = Task { try await pipeline.thumbnail(for: request(base, 5)) }
        await cancelled(displaced)
        #expect(await pipeline.queuedCount == 2)
        await gate.finish(1)
        _ = try await active.value
        try await eventually { await gate.started == [1, 5] }
        await gate.finish(5)
        _ = try await visible.value
        try await eventually { await gate.started == [1, 5, 2] }
        await gate.finish(2)
        _ = try await prefetch.value
    }

    @Test func reducedWorkerSettingWaitsForRunningWorkAndCancelsPrefetch() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: 4,
            decode: { await gate.decode($0) })
        let active = (1...4).map { index in
            Task { try await pipeline.thumbnail(for: request(base, index)) }
        }
        try await eventually { await gate.started.count == 4 }
        await pipeline.setWorkerCount(2)
        let queued = Task {
            try await pipeline.thumbnail(for: request(base, 5), priority: .prefetch)
        }
        try await eventually { await pipeline.queuedCount == 1 }
        await gate.finish(1)
        await gate.finish(2)
        try await eventually { await pipeline.activeCount == 2 }
        #expect(await gate.started.count == 4)
        await pipeline.cancelPrefetch()
        await cancelled(queued)
        await gate.finish(3)
        await gate.finish(4)
        for task in active { _ = try await task.value }
        #expect(await gate.started.count == 4)
    }

    @Test func closeWaitsForNativeDrainBeforeFolderAccessCanBeReleased() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let pipeline = ThumbnailPipeline(
            cache: try directory.cache(memory: 0, disk: 0), workers: 1,
            decode: { await gate.decode($0) })
        let active = Task { try await pipeline.thumbnail(for: request(base, 1)) }
        try await eventually { await gate.started == [1] }
        let closing = Task {
            await pipeline.close()
            await gate.markClosed()
        }
        await cancelled(active)
        #expect(await gate.didClose == false)
        #expect(await pipeline.activeCount == 1)
        do {
            _ = try await pipeline.thumbnail(for: base)
            Issue.record("Closed pipeline accepted a new request")
        } catch ThumbnailPipelineError.closed {}
        await gate.finish(1)
        await closing.value
        #expect(await gate.didClose)
        #expect(await pipeline.activeCount == 0)
        await pipeline.close()
    }

    @Test func cacheWriteFailureStillDeliversUsablePixels() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        struct InjectedFailure: Error {}
        let cache = try ThumbnailCache(
            directory: directory.url.appendingPathComponent("cache"),
            configuration: .init(), beforeCommit: { _ in throw InjectedFailure() })
        let pipeline = ThumbnailPipeline(cache: cache)
        let image = try availableThumbnail(await pipeline.thumbnail(for: base))
        #expect(max(image.width, image.height) == 400)
        await pipeline.close()
    }

    @Test func revisionChangedDuringDecodeIsUnavailableAndNotCached() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let base = try thumbnailRequest(directory.image())
        let gate = ThumbnailDecodeGate()
        let cache = try directory.cache()
        let pipeline = ThumbnailPipeline(
            cache: cache, workers: 1, decode: { await gate.decode($0) })
        let task = Task { try await pipeline.thumbnail(for: request(base, 1)) }
        try await eventually { await gate.started == [1] }
        try Data("changed".utf8).write(to: base.source)
        await gate.finish(1)
        guard case .unavailable(.sourceChanged) = try await task.value else {
            Issue.record("A changed source returned pixels")
            return
        }
        #expect(cache.result(for: request(base, 1)) == nil)
    }
}
