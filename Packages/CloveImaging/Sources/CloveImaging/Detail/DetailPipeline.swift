import CoreGraphics
import Foundation
import Synchronization
import os

public enum DetailPipelineError: Error, Sendable {
    case queueFull
    case closed
}

private final class NativeRAWRenderCounter: Sendable {
    private let count = Mutex<UInt64>(0)
    var value: UInt64 { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

/// Cancellation closes admission synchronously, before the cancellation actor hop.
private final class DetailCancellation: Sendable {
    private struct State {
        var callerCancelled = false
        var discarded = false
        var retainsRunningScreen = false
    }
    private let state = Mutex(State())
    var isCancelled: Bool { state.withLock { $0.discarded } }

    func start(retainingScreen: Bool) -> Bool {
        state.withLock {
            guard !$0.discarded else { return false }
            $0.retainsRunningScreen = retainingScreen
            return true
        }
    }

    func cancelCaller() {
        state.withLock {
            $0.callerCancelled = true
            if !$0.retainsRunningScreen { $0.discarded = true }
        }
    }

    func discard() { state.withLock { $0.discarded = true } }
    func deliver(_ body: (Bool) -> Void) {
        state.withLock { body($0.callerCancelled || $0.discarded) }
    }
    func storeIfActive(_ body: () -> Void) {
        state.withLock { if !$0.discarded { body() } }
    }
}

/// Detail and group review's shared image scheduler. Embedded previews have their
/// own bounded lane. Screen RAW, native RAW and full camera decodes share one lane.
/// Obsolete full-size calls drain without publishing. Running screen renders can
/// survive caller cancellation and populate the compressed cache.
public actor DetailPipeline {
    private enum Lane: Sendable { case preview, render }
    private enum Effort: Sendable { case previewOnly, screen, best }

    private struct Job {
        let id: UUID
        let consumer: UUID
        let request: DetailRequest
        let effort: Effort
        let priority: DetailPriority
        let cancellation: DetailCancellation
        let continuation: CheckedContinuation<DetailResult?, any Error>
        var lane: Lane { effort == .previewOnly ? .preview : .render }
    }

    private static let signposter = OSSignposter(
        subsystem: "com.mimiqdev.clove", category: "DetailPipeline")

    private let cache: DetailCache
    private let reader: any DetailReading
    private let sizes: any DetailNativeSizeReading
    private let previewWorkers: Int
    private let queueLimit: Int
    private var queue: [UUID] = []
    private var active: [UUID: Lane] = [:]
    private var jobs: [UUID: Job] = [:]
    private var latest: [UUID: UUID] = [:]
    private var renderLaneSignposts: [UUID: OSSignpostIntervalState] = [:]
    private var closed = false
    private var navigationGeneration: UInt64 = 0
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    public init(cache: DetailCache = DetailCache(), previewWorkers: Int = 2, queueLimit: Int = 16) {
        self.init(
            cache: cache, previewWorkers: previewWorkers, queueLimit: queueLimit,
            reader: DetailRenderer(), sizes: DetailNativeSizeReader())
    }

    init(
        cache: DetailCache, previewWorkers: Int = 2, queueLimit: Int = 16,
        reader: any DetailReading, sizes: any DetailNativeSizeReading = DetailNativeSizeReader()
    ) {
        precondition(previewWorkers > 0 && queueLimit > 0)
        self.cache = cache
        self.previewWorkers = previewWorkers
        self.queueLimit = queueLimit
        self.reader = reader
        self.sizes = sizes
    }

    /// Called before arrival reads. Releases the full image on photo/mode change
    /// and cancels queued work. Running screen renders can finish into the cache.
    public func navigate(
        to current: DetailRequest,
        generation: UInt64? = nil
    ) {
        guard !closed, !Task.isCancelled else { return }
        if let generation, generation != navigationGeneration { return }
        cache.navigate(to: current)
        for job in Array(jobs.values) where !isRunningScreen(job) {
            // Analysis for the newly opened photo and revision belongs to this arrival. Only
            // obsolete analysis is cancelled; interactive reads keep the existing navigation
            // cancellation rule.
            if job.priority == .analysis && Self.samePhoto(job.request, current) { continue }
            cancel(job.id)
        }
        latest = latest.filter { jobs[$0.value] != nil }
    }

    /// The app reserves arrival ownership before any file-system work. An older
    /// arrival cannot reclaim ownership after a slow revision read or actor hop.
    public func beginNavigation(_ generation: UInt64, keepingAnalysisFor urls: Set<URL> = []) {
        guard !closed, generation > navigationGeneration else { return }
        navigationGeneration = generation
        let kept = Set(urls.map(\.standardizedFileURL))
        for job in Array(jobs.values) where !isRunningScreen(job) {
            if job.priority == .analysis,
                let primary = (job.request.raw ?? job.request.jpeg ?? job.request.heif)?.url
                    .standardizedFileURL,
                kept.contains(primary)
            {
                continue
            }
            cancel(job.id)
        }
        latest = latest.filter { jobs[$0.value] != nil }
    }

    /// Immediate fit pixels: held screen RAW in RAW mode, otherwise the camera preview.
    /// This method never starts a render.
    public func preview(
        for request: DetailRequest, consumer: UUID = UUID()
    ) async throws -> DetailResult {
        guard
            let result = try await enqueue(
                request, consumer: consumer, effort: .previewOnly, priority: .visible)
        else { preconditionFailure("A visible detail request must return a result") }
        return result
    }

    /// The fit upgrade. RAW mode renders at screen size with draft off; camera mode
    /// keeps its preview. A RAW set without a usable full camera source takes RAW mode.
    public func screen(
        for request: DetailRequest, consumer: UUID = UUID()
    ) async throws -> DetailResult {
        guard
            let result = try await enqueue(
                request, consumer: consumer, effort: .screen, priority: .visible)
        else { preconditionFailure("A visible detail request must return a result") }
        return result
    }

    /// Zoom beyond the shown pixels, or an explicit 100% request.
    public func image(for request: DetailRequest, consumer: UUID = UUID()) async throws
        -> DetailResult
    {
        guard
            let result = try await enqueue(
                request, consumer: consumer, effort: .best, priority: .visible)
        else { preconditionFailure("A visible detail request must return a result") }
        return result
    }

    /// Bounded preview pixels for face/eye analysis. Analysis never uses the native render
    /// route for detection, and its background admission cannot displace interactive reads.
    public func analysisPreview(
        for request: DetailRequest, consumer: UUID = UUID()
    ) async throws -> DetailResult {
        guard
            let result = try await enqueue(
                request, consumer: consumer, effort: .previewOnly, priority: .analysis)
        else { preconditionFailure("An admitted analysis request must return a result") }
        return result
    }

    /// The one native acquisition shared by a photo's analysis regions. Queued visible
    /// fit/zoom work takes precedence over this background route.
    public func analysisImage(
        for request: DetailRequest, consumer: UUID = UUID()
    ) async throws -> DetailResult {
        guard
            let result = try await enqueue(
                request, consumer: consumer, effort: .best, priority: .analysis)
        else { preconditionFailure("An admitted analysis request must return a result") }
        return result
    }

    /// Embedded previews only. One-ahead RAW work is explicitly requested through screen().
    public func prefetch(_ requests: [DetailRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for request in requests.prefix(2) {
                group.addTask { try? await self.prefetchPreview(for: request) }
            }
        }
    }

    public func prefetchPreview(for request: DetailRequest) async throws {
        _ = try await enqueue(request, consumer: UUID(), effort: .previewOnly, priority: .prefetch)
    }

    public func prefetchScreen(for request: DetailRequest) async throws {
        _ = try await enqueue(request, consumer: UUID(), effort: .screen, priority: .prefetch)
    }

    public func cancelPrefetch() {
        for job in Array(jobs.values) where job.priority == .prefetch {
            cancel(job.id, preservingRunningScreen: true)
        }
    }

    /// Leaving the detail stage keeps compressed images, but never a
    /// full camera decode or native RAW allocation.
    public func leavePhoto(generation: UInt64) {
        guard generation > navigationGeneration else { return }
        beginNavigation(generation)
        for job in Array(jobs.values) { cancel(job.id) }
        cache.releaseNative()
    }

    public func releaseCachedImages() {
        for job in Array(jobs.values) { cancel(job.id) }
        latest.removeAll()
        cache.releaseAll()
    }

    var cachedImageCount: Int { cache.imageCount }

    /// Waits for uncancellable reads before the folder's security scope can end.
    public func close() async {
        closed = true
        for id in Array(jobs.keys) { cancel(id) }
        cache.releaseAll()
        if !active.isEmpty { await withCheckedContinuation { closeWaiters.append($0) } }
    }

    var queuedCount: Int { queue.count }
    var activeCount: Int { active.count }
    var activeRenderCount: Int { active.values.filter { $0 == .render }.count }

    private let nativeRAWCounter = NativeRAWRenderCounter()

    /// Native RAW renders started in this pipeline session. The lock-protected counter
    /// advances synchronously immediately before the renderer call, without an actor hop
    /// that could admit a render after cancellation.
    public var nativeRAWRenderCount: UInt64 { nativeRAWCounter.value }

    private func enqueue(
        _ request: DetailRequest, consumer: UUID, effort: Effort,
        priority: DetailPriority
    ) async throws -> DetailResult? {
        let id = UUID()
        let cancellation = DetailCancellation()
        defer { if latest[consumer] == id { latest[consumer] = nil } }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !closed else { throw DetailPipelineError.closed }
            if let old = latest[consumer] { cancel(old, preservingRunningScreen: true) }
            latest[consumer] = id
            let cache = cache
            let sizes = sizes
            let hit = await Task.detached(
                executorPreference: ImageWorkExecutor.userInitiated, priority: .userInitiated
            ) {
                if priority == .prefetch {
                    return (
                        Self.hasCached(request, effort: effort, cache: cache), nil as DetailResult?
                    )
                }
                let result = await Self.cached(request, effort: effort, cache: cache, sizes: sizes)
                return (result != nil, result)
            }.value
            try Task.checkCancellation()
            guard !closed else { throw DetailPipelineError.closed }
            guard latest[consumer] == id else { throw CancellationError() }
            if hit.0 { return hit.1 }
            return try await withCheckedThrowingContinuation { continuation in
                if queue.count >= queueLimit {
                    if priority == .visible,
                        let victim = queue.last(where: { jobs[$0]?.priority == .analysis })
                            ?? queue.last(where: { jobs[$0]?.priority == .prefetch })
                    {
                        cancel(victim)
                    } else {
                        continuation.resume(throwing: DetailPipelineError.queueFull)
                        return
                    }
                }
                if effort != .previewOnly && priority == .visible {
                    for queued in queue
                    where jobs[queued]?.lane == .render && jobs[queued]?.priority != .analysis {
                        cancel(queued)
                    }
                }
                jobs[id] = Job(
                    id: id, consumer: consumer, request: request, effort: effort,
                    priority: priority, cancellation: cancellation, continuation: continuation)
                latest[consumer] = id
                queue.append(id)
                drain()
            }
        } onCancel: {
            cancellation.cancelCaller()
            Task { await self.cancel(id, preservingRunningScreen: true) }
        }
    }

    private func isRunningScreen(_ job: Job) -> Bool {
        active[job.id] == .render && job.effort == .screen && job.request.raw != nil
    }

    private nonisolated static func samePhoto(
        _ first: DetailRequest, _ second: DetailRequest
    ) -> Bool {
        let firstSource = first.raw ?? first.jpeg ?? first.heif
        let secondSource = second.raw ?? second.jpeg ?? second.heif
        return firstSource == secondSource
    }

    private func cancel(_ id: UUID, preservingRunningScreen: Bool = false) {
        guard let job = jobs[id] else { return }
        if preservingRunningScreen && isRunningScreen(job) { return }
        jobs[id] = nil
        job.cancellation.discard()
        queue.removeAll { $0 == id }
        if latest[job.consumer] == id { latest[job.consumer] = nil }
        job.continuation.resume(throwing: CancellationError())
    }

    private func drain() {
        while activeRenderCount < 1, let index = nextIndex(lane: .render) {
            start(queue.remove(at: index))
        }
        while active.values.filter({ $0 == .preview }).count < previewWorkers,
            let index = nextIndex(lane: .preview)
        { start(queue.remove(at: index)) }
    }

    private func nextIndex(lane: Lane) -> Int? {
        queue.firstIndex { jobs[$0]?.lane == lane && jobs[$0]?.priority == .visible }
            ?? queue.firstIndex { jobs[$0]?.lane == lane && jobs[$0]?.priority == .prefetch }
            ?? queue.firstIndex { jobs[$0]?.lane == lane }
    }

    private func start(_ id: UUID) {
        guard let job = jobs[id] else { return }
        guard
            job.cancellation.start(retainingScreen: job.effort == .screen && job.request.raw != nil)
        else { cancel(id); return }
        active[id] = job.lane
        if job.lane == .render {
            let signpostID = Self.signposter.makeSignpostID()
            renderLaneSignposts[id] = Self.signposter.beginInterval(
                "DetailRenderLane", id: signpostID,
                "effort=\(String(describing: job.effort), privacy: .public) priority=\(String(describing: job.priority), privacy: .public)"
            )
        }
        let cache = cache
        let reader = reader
        let sizes = sizes
        let nativeRAWCounter = nativeRAWCounter
        Task.detached(
            executorPreference: job.priority == .visible
                ? ImageWorkExecutor.userInitiated : ImageWorkExecutor.utility,
            priority: job.priority == .visible ? .userInitiated : .utility
        ) {
            let result = await Self.perform(
                job, cache: cache, reader: reader, sizes: sizes,
                nativeRAWStarted: nativeRAWCounter.increment)
            await self.complete(id, result: result)
        }
    }

    private func complete(_ id: UUID, result: DetailResult?) {
        if let interval = renderLaneSignposts.removeValue(forKey: id) {
            Self.signposter.endInterval("DetailRenderLane", interval)
        }
        active.removeValue(forKey: id)
        if let job = jobs.removeValue(forKey: id) {
            if latest[job.consumer] == id { latest[job.consumer] = nil }
            job.cancellation.deliver { cancelled in
                if cancelled {
                    job.continuation.resume(throwing: CancellationError())
                } else {
                    job.continuation.resume(returning: result)
                }
            }
        }
        drain()
        if closed && active.isEmpty {
            let waiters = closeWaiters
            closeWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    private nonisolated static func cameraSource(_ request: DetailRequest, cache: DetailCache)
        -> DetailSource?
    {
        guard request.raw != nil, request.mode == .cameraPreviewFirst else { return nil }
        for source in [request.heif, request.jpeg].compactMap({ $0 }) {
            if !cache.cameraFailed(source), isCurrent(source),
                DetailNativeSize.header(source) != nil
            {
                return source
            }
        }
        return nil
    }

    /// Prefetch touches usable entries without decoding an image it would discard.
    private nonisolated static func hasCached(
        _ request: DetailRequest, effort: Effort, cache: DetailCache
    ) -> Bool {
        if let raw = request.raw, !isCurrent(raw) { return false }
        let usesRAW = request.raw != nil && cameraSource(request, cache: cache) == nil
        if usesRAW {
            if let key = DetailCache.screenKey(request), cache.contains(key) { return true }
            if effort == .screen { return false }
        }
        for step in DetailPreviewPlan.steps(for: request) {
            guard isCurrent(step.source) else { return false }
            let key = DetailCacheKey(
                source: step.source, locationIdentity: request.locationIdentity,
                purpose: step.purpose(displayPixels: request.displayPixels))
            let minimum: Int
            switch step {
            case .embedded: minimum = DetailPreviewPlan.minimumUsablePreviewPixels
            case .displayRaster: minimum = 0
            }
            if cache.contains(key, minimumLongEdge: minimum) { return true }
        }
        return false
    }

    /// Cache reads decode on a worker before admission, so hits never wait for a lane.
    private nonisolated static func cached(
        _ request: DetailRequest, effort: Effort, cache: DetailCache,
        sizes: any DetailNativeSizeReading
    ) async -> DetailResult? {
        if let raw = request.raw, !isCurrent(raw) { return .unavailable(.sourceChanged) }
        let camera = cameraSource(request, cache: cache)
        let usesRAW = request.raw != nil && camera == nil
        if effort == .best {
            let source =
                camera ?? request.raw ?? (request.wantsNativeResolution ? request.jpeg : nil)
            if let source {
                let key = DetailCacheKey(
                    source: source, locationIdentity: request.locationIdentity,
                    purpose: usesRAW ? .nativeRAW : .fullRaster)
                return cache.native(for: key).map { verified(.available($0)) }
            }
        }
        if usesRAW {
            if effort == .best { return nil }
            if let screen = cache.screen(for: request) { return verified(.available(screen)) }
            if effort == .screen { return nil }
        }
        var best: DetailImage?
        for step in DetailPreviewPlan.steps(for: request) {
            guard isCurrent(step.source) else { return .unavailable(.sourceChanged) }
            let key = DetailCacheKey(
                source: step.source, locationIdentity: request.locationIdentity,
                purpose: step.purpose(displayPixels: request.displayPixels))
            guard let image = cache.image(for: key) else { continue }
            if DetailPreviewPlan.isUsable(image, from: step) { best = image; break }
        }
        guard let best else { return nil }
        let size: CGSize?
        if let camera {
            size = await sizes.readNativeSize(of: camera, isRAW: false)
        } else if let reference = request.raw ?? request.jpeg,
            case .known(let known) = cache.nativeSize(for: reference)
        {
            size = known
        } else {
            size = nil
        }
        let shown = best.withFullResolution(size, hasRAW: request.raw != nil)
        if effort == .best, request.jpeg == nil {
            return verified(.available(shown.limited(by: .noHigherResolution)))
        }
        return verified(.available(shown))
    }

    private nonisolated static func perform(
        _ job: Job, cache: DetailCache,
        reader: any DetailReading, sizes: any DetailNativeSizeReading,
        nativeRAWStarted: @Sendable () -> Void
    ) async -> DetailResult? {
        let request = job.request
        if job.priority == .prefetch, hasCached(request, effort: job.effort, cache: cache) {
            return nil
        }
        if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        if let raw = request.raw, !isCurrent(raw) { return .unavailable(.sourceChanged) }
        var camera = cameraSource(request, cache: cache)
        let usesRAW = request.raw != nil && camera == nil
        if usesRAW, let held = cache.screen(for: request), job.effort != .best {
            return verified(.available(held))
        }

        var best: DetailImage? = usesRAW ? cache.screen(for: request) : nil
        var failures: [DetailFailure] = []
        for step in best == nil ? DetailPreviewPlan.steps(for: request) : [] {
            guard isCurrent(step.source) else { return .unavailable(.sourceChanged) }
            let key = DetailCacheKey(
                source: step.source, locationIdentity: request.locationIdentity,
                purpose: step.purpose(displayPixels: request.displayPixels))
            var image = cache.image(for: key)
            if image == nil {
                if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
                switch await reader.read(step, displayPixels: request.displayPixels) {
                case .image(let pixels):
                    let candidate = DetailImage(
                        image: pixels, source: step.source,
                        quality: step.quality, hasRAW: false)
                    if let compressed = DetailCompressedImage(candidate) {
                        job.cancellation.storeIfActive { cache.store(compressed, for: key) }
                    }
                    image = candidate
                case .cannotOpen: failures.append(.cannotOpen)
                case .noUsablePreview: failures.append(.noUsablePreview)
                }
            }
            guard let image else { continue }
            if DetailPreviewPlan.isUsable(image, from: step) { best = image; break }
            if best == nil { best = image }
        }
        if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        var fullSize: CGSize?
        if let camera {
            fullSize = await sizes.readNativeSize(of: camera, isRAW: false)
        } else {
            fullSize = await fullResolutionSize(
                for: request, previewLongEdge: best?.longEdge ?? 0,
                cache: cache, sizes: sizes)
        }
        var shown = best?.withFullResolution(fullSize, hasRAW: request.raw != nil)
        if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        if job.effort == .previewOnly {
            if let shown { return verified(.available(shown)) }
            return missing(failures)
        }
        if job.effort == .screen, camera != nil || request.raw == nil {
            return shown.map { verified(.available($0)) } ?? missing(failures)
        }

        if job.effort == .best, let fullCamera = camera {
            let key = DetailCacheKey(
                source: fullCamera, locationIdentity: request.locationIdentity,
                purpose: .fullRaster)
            if let held = cache.native(for: key) { return verified(.available(held)) }
            cache.releaseNative()
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            let rasterInterval = Self.signposter.beginInterval(
                "DetailFullRaster", id: Self.signposter.makeSignpostID())
            let rasterOutcome = await reader.fullRaster(fullCamera)
            Self.signposter.endInterval("DetailFullRaster", rasterInterval)
            if case .image(let pixels) = rasterOutcome {
                let decoded = DetailImage(
                    image: pixels, source: fullCamera, quality: .raster,
                    hasRAW: true, fullResolutionSize: pixelSize(pixels))
                return publish(decoded, job: job) { cache.storeNative(decoded, for: key) }
            }
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            cache.recordCameraFailure(fullCamera)
            // A failed HIF may still have a JPEG companion. Otherwise this entire photo
            // uses RAW, including subsequent fit requests and held-render returns.
            camera = cameraSource(request, cache: cache)
            if camera != nil {
                return await perform(
                    job, cache: cache, reader: reader, sizes: sizes,
                    nativeRAWStarted: nativeRAWStarted)
            }
            fullSize = await fullResolutionSize(
                for: request, previewLongEdge: best?.longEdge ?? 0,
                cache: cache, sizes: sizes)
            if let raw = request.raw {
                // Keep a screen RAW before attempting native RAW. Returning to a
                // camera-decode failure must not go back to camera colours.
                let fallback = await renderScreen(
                    job, raw: raw, fullSize: fullSize,
                    shown: shown, failures: failures, cache: cache, reader: reader)
                if case .available(let image) = fallback { shown = image }
            }
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        }

        if let raw = request.raw {
            if job.effort == .screen {
                return await renderScreen(
                    job, raw: raw, fullSize: fullSize,
                    shown: shown, failures: failures, cache: cache, reader: reader)
            }
            let key = DetailCacheKey(
                source: raw, locationIdentity: request.locationIdentity,
                purpose: .nativeRAW)
            if let held = cache.native(for: key) { return verified(.available(held)) }
            cache.releaseNative()
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            nativeRAWStarted()
            let nativeInterval = Self.signposter.beginInterval(
                "DetailNativeRAW", id: Self.signposter.makeSignpostID())
            let renderedPixels = await reader.nativeRAW(raw)
            Self.signposter.endInterval("DetailNativeRAW", nativeInterval)
            guard let pixels = renderedPixels else {
                return shown.map { verified(.available($0.limited(by: .rawRenderFailed))) }
                    ?? missing(failures)
            }
            let rendered = DetailImage(
                image: pixels, source: raw, quality: .nativeRAW,
                hasRAW: true, fullResolutionSize: renderedSize(pixels, known: fullSize, source: raw)
            )
            return publish(rendered, job: job) {
                cache.storeNative(rendered, for: key)
                cache.store(nativeSize: .known(pixelSize(pixels)), for: raw)
            }
        }

        if request.raw == nil, request.jpeg != nil, !request.wantsNativeResolution {
            return shown.map { verified(.available($0)) } ?? missing(failures)
        }
        if let jpeg = request.jpeg, request.wantsNativeResolution {
            let key = DetailCacheKey(
                source: jpeg, locationIdentity: request.locationIdentity,
                purpose: .fullRaster)
            if let held = cache.native(for: key) { return verified(.available(held)) }
            cache.releaseNative()
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            let rasterInterval = Self.signposter.beginInterval(
                "DetailFullRaster", id: Self.signposter.makeSignpostID())
            let rasterOutcome = await reader.fullRaster(jpeg)
            Self.signposter.endInterval("DetailFullRaster", rasterInterval)
            if case .image(let pixels) = rasterOutcome {
                var decoded = DetailImage(
                    image: pixels, source: jpeg, quality: .raster,
                    hasRAW: false, fullResolutionSize: fullSize ?? pixelSize(pixels))
                if let fullSize, max(fullSize.width, fullSize.height) > CGFloat(decoded.longEdge) {
                    decoded = decoded.limited(by: .noHigherResolution)
                }
                return publish(decoded, job: job) { cache.storeNative(decoded, for: key) }
            }
        }
        return shown.map { verified(.available($0.limited(by: .noHigherResolution))) }
            ?? missing(failures)
    }

    private nonisolated static func renderScreen(
        _ job: Job, raw: DetailSource,
        fullSize: CGSize?, shown: DetailImage?, failures: [DetailFailure],
        cache: DetailCache, reader: any DetailReading
    ) async -> DetailResult {
        if let held = cache.screen(for: job.request) { return verified(.available(held)) }
        if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        let screenInterval = Self.signposter.beginInterval(
            "DetailScreenRAW", id: Self.signposter.makeSignpostID(),
            "edge=\(job.request.screenPixels)")
        let screenPixels = await reader.screenRAW(raw, longEdge: job.request.screenPixels)
        Self.signposter.endInterval("DetailScreenRAW", screenInterval)
        guard let pixels = screenPixels else {
            return shown.map { verified(.available($0.limited(by: .rawRenderFailed))) }
                ?? missing(failures)
        }
        let rendered = DetailImage(
            image: pixels, source: raw, quality: .screenRAW,
            hasRAW: true, fullResolutionSize: fullSize)
        let compressed = DetailCompressedImage(rendered)
        return publish(rendered, job: job) {
            if let compressed, let key = DetailCache.screenKey(job.request) {
                cache.store(compressed, for: key)
            }
        }
    }

    /// Cache insertion and explicit discard share the same lock. Caller cancellation
    /// can leave a useful running screen render alive for the compressed cache.
    private nonisolated static func publish(
        _ image: DetailImage, job: Job,
        store: () -> Void
    ) -> DetailResult {
        guard isCurrent(image.source) else { return .unavailable(.sourceChanged) }
        job.cancellation.storeIfActive(store)
        return .available(image)
    }

    private nonisolated static func missing(_ failures: [DetailFailure]) -> DetailResult {
        .unavailable(
            !failures.isEmpty && failures.allSatisfy { $0 == .cannotOpen }
                ? .cannotOpen : .noUsablePreview)
    }

    private nonisolated static func verified(_ result: DetailResult) -> DetailResult {
        guard case .available(let image) = result else { return result }
        return isCurrent(image.source) ? result : .unavailable(.sourceChanged)
    }

    private nonisolated static func fullResolutionSize(
        for request: DetailRequest,
        previewLongEdge: Int, cache: DetailCache, sizes: any DetailNativeSizeReading
    ) async -> CGSize? {
        guard let reference = request.raw ?? request.jpeg, isCurrent(reference) else { return nil }
        if let cached = cache.nativeSize(for: reference) {
            switch cached {
            case .known(let size): return size;
            case .unknown: return nil
            }
        }
        var size = await sizes.readNativeSize(of: reference, isRAW: request.raw != nil)
        if let read = size, request.raw != nil,
            max(read.width, read.height) <= CGFloat(previewLongEdge)
        {
            size = nil
        }
        cache.store(nativeSize: size.map(DetailCache.NativeSize.known) ?? .unknown, for: reference)
        return size
    }

    private nonisolated static func renderedSize(
        _ pixels: CGImage, known: CGSize?,
        source: DetailSource
    ) -> CGSize {
        let size = pixelSize(pixels)
        if let known, known != size {
            print(
                "DETAIL native-size-mismatch known=\(Int(known.width))x\(Int(known.height))"
                    + " render=\(pixels.width)x\(pixels.height) file=\(source.url.lastPathComponent)"
            )
        }
        return size
    }

    private nonisolated static func isCurrent(_ source: DetailSource) -> Bool {
        (try? ThumbnailRevision.read(from: source.url)) == source.revision
    }

    private nonisolated static func pixelSize(_ pixels: CGImage) -> CGSize {
        CGSize(width: pixels.width, height: pixels.height)
    }
}
