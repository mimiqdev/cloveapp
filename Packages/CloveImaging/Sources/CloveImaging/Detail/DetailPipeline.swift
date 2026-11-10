import Foundation
import Synchronization

/// Errors a detail request can be refused with, before any pixels are read.
public enum DetailPipelineError: Error, Sendable {
    /// The queue is full and this request is not more important than what it holds.
    case queueFull
    /// The pipeline was closed, for example after its folder was closed.
    case closed
}

/// Cancellation is signalled synchronously from `onCancel`, before its actor hop.
///
/// This closes the race between a queued native entry and its cancellation: a request that
/// was cancelled before the read starts still cannot deliver pixels.
private final class DetailCancellation: Sendable {
    private let cancelled = Mutex(false)
    var isCancelled: Bool { cancelled.withLock { $0 } }
    func cancel() { cancelled.withLock { $0 = true } }
    func deliver(_ body: (Bool) -> Void) { cancelled.withLock { body($0) } }
}

/// Shows one photo's detail pixels: a camera preview first, then native RAW only when the
/// view needs more (PRD P0-04; G1 "Preview, detail (I2)" and "Scheduling and cache").
///
/// Fit-view navigation (a swipe or an edge tap, PRD P0-04) uses
/// ``preview(for:consumer:priority:)``, which never renders. ``image(for:consumer:)`` is only
/// for a zoom past the preview's pixels or an explicit double-tap to 100%: it reuses the first
/// call's cached preview and then renders. Both take a consumer ID per view:
/// a newer request from the same consumer supersedes the older one, which is cancelled
/// before it enters a read or has its drained result discarded.
///
/// ```swift
/// let shown = try await pipeline.preview(for: request, consumer: viewID)
/// let detailed = try await pipeline.image(for: request, consumer: viewID)
/// ```
///
/// Scheduling follows G1 "Scheduling and cache": at most one RAW render at a time, the
/// photo on screen before neighbour prefetch, queued stale work cancelled before it starts,
/// and an in-flight render that cannot be interrupted is drained and discarded rather than
/// left to pile up.
public actor DetailPipeline {
    private enum Lane: Sendable, Hashable {
        /// Preview and display-size reads; a few run at once.
        case preview
        /// Native RAW and full-JPEG routes; exactly one runs at a time.
        case render
    }

    private enum Effort: Sendable, Hashable {
        /// Preview pixels only, never a render (`preview(for:)` and prefetch).
        case previewOnly
        /// Preview first, then a render when the view needs more (`image(for:)`).
        case best
    }

    private struct Job {
        let id: UUID
        let consumer: UUID
        let request: DetailRequest
        let effort: Effort
        let priority: DetailPriority
        let cancellation: DetailCancellation
        let continuation: CheckedContinuation<DetailResult, any Error>

        var lane: Lane { effort == .best ? .render : .preview }
    }

    private let cache: DetailCache
    private let reader: any DetailReading
    private let previewWorkers: Int
    private let queueLimit: Int
    private var queue: [UUID] = []
    private var active: [UUID: Lane] = [:]
    private var jobs: [UUID: Job] = [:]
    private var latest: [UUID: UUID] = [:]
    private var closed = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    /// Builds a pipeline over one cache. More than two preview readers buys little for the
    /// 6–13 ms first-preview work measured in S2, and the render lane is always single.
    public init(cache: DetailCache = DetailCache(), previewWorkers: Int = 2, queueLimit: Int = 16) {
        self.init(
            cache: cache, previewWorkers: previewWorkers, queueLimit: queueLimit,
            reader: DetailRenderer())
    }

    init(
        cache: DetailCache, previewWorkers: Int = 2, queueLimit: Int = 16,
        reader: any DetailReading
    ) {
        precondition(previewWorkers > 0 && queueLimit > 0)
        self.cache = cache
        self.previewWorkers = previewWorkers
        self.queueLimit = queueLimit
        self.reader = reader
    }

    /// Fit-view pixels for the photo on screen: fit-view navigation calls this and nothing
    /// else (PRD P0-04 full-width preview).
    ///
    /// The source order is G1 "Preview, detail (I2)" and it stops at the first usable
    /// preview: the HIF's embedded preview for RAW + HIF, the RAW's embedded preview when the
    /// HIF cannot be opened, has no preview or is tiny, the RAW's embedded preview for RAW
    /// alone or RAW + JPEG, a JPEG raster at display size when that preview is missing or
    /// tiny, the JPEG raster for JPEG alone, and the embedded preview only for HIF alone
    /// (reported as ``DetailQuality/preview``).
    ///
    /// This never renders a RAW, whatever ``DetailRequest/wantsNativeResolution`` says, so a
    /// swipe or edge tap can never start native work on a camera file. Swiping to the next
    /// photo stays cheap because pixels beyond the preview come from
    /// ``image(for:consumer:)`` only.
    ///
    /// Cancellation and supersession throw `CancellationError`; nothing else throws.
    public func preview(
        for request: DetailRequest, consumer: UUID = UUID(), priority: DetailPriority = .visible
    ) async throws -> DetailResult {
        try await enqueue(
            request, consumer: consumer, effort: .previewOnly, priority: priority)
    }

    /// More pixels for the photo on screen: zoom past what the preview holds, or the explicit
    /// double-tap to 100% (PRD P0-04 "pinch zoom and double-tap to 100% for focus inspection").
    ///
    /// Call this only for those two cases. Fit-view navigation calls
    /// ``preview(for:consumer:priority:)`` instead, because this call may render a RAW and G1
    /// "Preview, detail (I2)" allows that only when the needed pixel size is larger than the
    /// preview's or on an explicit 100% request — never for a swipe.
    ///
    /// G1 "Preview, detail (I2)": a RAW is rendered by `CIRAWFilter` at native size only when
    /// the needed pixel size is larger than the preview's, or on ``DetailRequest/wantsNativeResolution``.
    /// A plain fit-view request therefore never renders. A JPEG-primary photo answers 100% by
    /// decoding the full JPEG, and a HIF-only photo stays at preview quality and reports
    /// ``DetailLimitation/noHigherResolution``.
    ///
    /// A failed RAW render never hides the preview: the result stays ``DetailResult/available``
    /// with ``DetailLimitation/rawRenderFailed``. Cancellation and supersession throw
    /// `CancellationError`.
    ///
    /// There is no prefetch priority here: speculative work is limited to
    /// ``preview(for:consumer:priority:)``, so a neighbour can never queue a RAW render.
    public func image(
        for request: DetailRequest, consumer: UUID = UUID()
    ) async throws -> DetailResult {
        try await enqueue(request, consumer: consumer, effort: .best, priority: .visible)
    }

    /// Fills the cache with the neighbours' embedded previews.
    ///
    /// G1 "Scheduling and cache": prefetch covers embedded previews only, never a RAW render,
    /// and is the first work dropped when the queue is full or ``cancelPrefetch()`` is called.
    /// Results are discarded; this returns once every request has settled or been dropped.
    public func prefetch(_ requests: [DetailRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    _ = try? await self.preview(for: request, priority: .prefetch)
                }
            }
        }
    }

    /// Drops every queued prefetch. Running previews keep their slot until they finish, so a
    /// dropped request never delivers late pixels.
    public func cancelPrefetch() {
        for job in Array(jobs.values) where job.priority == .prefetch { cancel(job.id) }
    }

    /// Releases every cached image, previews and the native render, and drops queued
    /// prefetch.
    ///
    /// The app calls this from its memory-warning handler; nothing in this module observes
    /// UIKit, so it builds and tests on macOS (G1 "Scheduling and cache"). Neighbour
    /// prefetch is the first work dropped.
    public func releaseCachedImages() {
        cache.releaseAll()
        cancelPrefetch()
    }

    /// Stops accepting work, cancels requests and waits for running reads to drain.
    ///
    /// After this returns the caller can release the folder's security scope. An in-flight
    /// native render cannot be interrupted, so `close` waits for it and discards its result.
    public func close() async {
        closed = true
        for id in Array(jobs.keys) { cancel(id) }
        if !active.isEmpty {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
    }

    var queuedCount: Int { queue.count }
    var activeCount: Int { active.count }
    var activeRenderCount: Int { active.values.filter { $0 == .render }.count }

    private func enqueue(
        _ request: DetailRequest, consumer: UUID, effort: Effort, priority: DetailPriority
    ) async throws -> DetailResult {
        let id = UUID()
        let cancellation = DetailCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !closed else { throw DetailPipelineError.closed }
            return try await withCheckedThrowingContinuation { continuation in
                if let old = latest[consumer] { cancel(old) }
                if queue.count >= queueLimit {
                    if priority == .visible,
                        let victim = queue.last(where: { jobs[$0]?.priority == .prefetch })
                    {
                        cancel(victim)
                    } else {
                        continuation.resume(throwing: DetailPipelineError.queueFull)
                        return
                    }
                }
                if effort == .best {
                    // G1 "Scheduling and cache": obsolete RAW work never piles up. A queued
                    // render can only be stale once a newer one is requested, so drop it
                    // before it enters the native call and let the latest render next.
                    for queued in queue where jobs[queued]?.lane == .render { cancel(queued) }
                }
                let job = Job(
                    id: id, consumer: consumer, request: request, effort: effort,
                    priority: priority, cancellation: cancellation, continuation: continuation)
                jobs[id] = job
                latest[consumer] = id
                queue.append(id)
                drain()
            }
        } onCancel: {
            cancellation.cancel()
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.cancellation.cancel()
        queue.removeAll { $0 == id }
        if latest[job.consumer] == id { latest[job.consumer] = nil }
        job.continuation.resume(throwing: CancellationError())
        // An active slot is released only by complete(), after its read drains.
    }

    private func drain() {
        while active.values.filter({ $0 == .render }).count < 1,
            let index = nextIndex(lane: .render, priority: nil)
        {
            start(queue.remove(at: index))
        }
        while active.values.filter({ $0 == .preview }).count < previewWorkers,
            let index = nextIndex(lane: .preview, priority: nil)
        {
            start(queue.remove(at: index))
        }
    }

    /// The photo on screen comes before neighbour prefetch (G1 "Scheduling and cache").
    private func nextIndex(lane: Lane, priority: DetailPriority?) -> Int? {
        if let priority {
            queue.firstIndex { jobs[$0]?.lane == lane && jobs[$0]?.priority == priority }
        } else {
            queue.firstIndex { jobs[$0]?.lane == lane && jobs[$0]?.priority == .visible }
                ?? queue.firstIndex { jobs[$0]?.lane == lane }
        }
    }

    private func start(_ id: UUID) {
        guard let job = jobs[id] else { return }
        guard !job.cancellation.isCancelled else {
            cancel(id)
            return
        }
        active[id] = job.lane
        let cache = cache
        let reader = reader
        Task.detached(priority: job.priority == .visible ? .userInitiated : .utility) {
            let result = await Self.perform(job, cache: cache, reader: reader)
            await self.complete(id, result: result)
        }
    }

    private func complete(_ id: UUID, result: DetailResult) {
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

    /// One request, end to end, off the actor: previews, cache and at most one render.
    private nonisolated static func perform(
        _ job: Job, cache: DetailCache, reader: any DetailReading
    ) async -> DetailResult {
        if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
        let fullResolutionSize = fullResolutionSize(for: job.request, cache: cache)
        var best: DetailImage?
        var failures: [DetailFailure] = []
        for step in DetailPreviewPlan.steps(for: job.request) {
            let source = step.source
            // A file that changed since the request was built must not deliver pixels.
            guard isCurrent(source) else { return .unavailable(.sourceChanged) }
            let key = DetailCacheKey(
                source: source, locationIdentity: job.request.locationIdentity,
                purpose: step.purpose(displayPixels: job.request.displayPixels))
            var image = cache.preview(for: key)
            if image == nil {
                if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
                switch await reader.read(step, displayPixels: job.request.displayPixels) {
                case .image(let pixels):
                    let candidate = DetailImage(
                        image: pixels, source: source, quality: step.quality,
                        fullResolutionSize: fullResolutionSize)
                    cache.storePreview(candidate, for: key)
                    image = candidate
                case .cannotOpen:
                    failures.append(.cannotOpen)
                case .noUsablePreview:
                    failures.append(.noUsablePreview)
                }
            }
            guard let image else { continue }
            // G1 "Preview, detail (I2)": stop at the first source with a usable preview. A
            // later source is only tried when this one could not be opened, has no preview
            // or is tiny; a bigger view never reads more preview sources by itself, because
            // that is `image(for:)`'s render route, not navigation's.
            if DetailPreviewPlan.isUsable(image, from: step) {
                best = image
                break
            }
            // Every source is tiny: show the earliest preferred one rather than none.
            if best == nil { best = image }
        }

        guard let preview = best else {
            // "Cannot open" only when no route even opened a file, so a readable file with
            // no preview is never reported as unreadable.
            let failure =
                failures.allSatisfy { $0 == .cannotOpen } && !failures.isEmpty
                ? DetailFailure.cannotOpen : DetailFailure.noUsablePreview
            return .unavailable(failure)
        }
        guard job.effort == .best else { return verified(.available(preview)) }

        let needsMorePixels =
            job.request.wantsNativeResolution || preview.longEdge < job.request.displayPixels
        guard needsMorePixels else { return verified(.available(preview)) }

        if let raw = job.request.raw {
            guard isCurrent(raw) else { return .unavailable(.sourceChanged) }
            let key = DetailCacheKey(
                source: raw, locationIdentity: job.request.locationIdentity, purpose: .nativeRAW)
            // The revision is part of the key, so a hit is already this photo's render.
            if let cached = cache.native(for: key) { return verified(.available(cached)) }
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            // G1 "Scheduling and cache": release the old native image before rendering next.
            cache.releaseNative()
            guard let pixels = await reader.nativeRAW(raw) else {
                return verified(.available(preview.limited(by: .rawRenderFailed)))
            }
            guard isCurrent(raw) else { return .unavailable(.sourceChanged) }
            let rendered = DetailImage(
                image: pixels, source: raw, quality: .nativeRAW,
                fullResolutionSize: fullResolutionSize)
            cache.storeNative(rendered, for: key)
            return verified(.available(rendered))
        }

        if let jpeg = job.request.jpeg, job.request.wantsNativeResolution {
            // G1 "Preview, detail (I2)": JPEG-primary 100% is a bounded raster decode. A
            // zoomed display request was already answered at its own size by the raster
            // step above, and decoding the file again would produce the same pixels.
            guard isCurrent(jpeg) else { return .unavailable(.sourceChanged) }
            let key = DetailCacheKey(
                source: jpeg, locationIdentity: job.request.locationIdentity, purpose: .fullRaster)
            if let cached = cache.preview(for: key) { return verified(.available(cached)) }
            if job.cancellation.isCancelled { return .unavailable(.noUsablePreview) }
            if case .image(let pixels) = await reader.fullRaster(jpeg) {
                let decoded = DetailImage(
                    image: pixels, source: jpeg, quality: .raster,
                    fullResolutionSize: fullResolutionSize)
                cache.storePreview(decoded, for: key)
                return verified(.available(decoded))
            }
            return verified(.available(preview.limited(by: .noHigherResolution)))
        }

        // No RAW and no JPEG: a HIF is never fully decoded (G1 "Preview, detail (I2)"), so
        // the preview is the maximum and the shortfall is reported rather than hidden.
        return verified(.available(preview.limited(by: .noHigherResolution)))
    }

    /// Checks the delivered file's revision once more, after all IO, so no stale pixels leave.
    private nonisolated static func verified(_ result: DetailResult) -> DetailResult {
        guard case .available(let image) = result else { return result }
        return isCurrent(image.source) ? result : .unavailable(.sourceChanged)
    }

    /// The photo's oriented full-resolution pixel size, read from the file header once per photo
    /// (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// G1 decision 1: with a RAW, the RAW is the photo; without one, the JPEG is. A HIF is never
    /// fully decoded, so it has no larger size to report and the pixels' own size stands in. A
    /// file whose revision changed since the request was built answers nil, so no stale size
    /// reaches the view; the pixel steps report that change themselves.
    private nonisolated static func fullResolutionSize(
        for request: DetailRequest, cache: DetailCache
    ) -> CGSize? {
        guard let reference = request.raw ?? request.jpeg else { return nil }
        if let cached = cache.fullResolutionSize(for: reference) { return cached }
        guard isCurrent(reference), let size = DetailNativeSize.read(reference) else { return nil }
        cache.store(fullResolutionSize: size, for: reference)
        return size
    }

    private nonisolated static func isCurrent(_ source: DetailSource) -> Bool {
        (try? ThumbnailRevision.read(from: source.url)) == source.revision
    }
}
