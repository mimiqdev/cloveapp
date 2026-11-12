import Foundation
import Synchronization

/// One photo's settled feature work, as it arrives while a folder is being analysed.
///
/// PRD P0-11 refines groups as analysis finishes, so results stream one photo at a time rather
/// than returning as one array.
public struct ImageFeatureResult: Sendable {
    /// The photo this result belongs to, exactly as it was requested.
    public let request: ImageFeatureRequest
    public let outcome: ImageFeatureOutcome

    public init(request: ImageFeatureRequest, outcome: ImageFeatureOutcome) {
        self.request = request
        self.outcome = outcome
    }
}

/// What one photo's feature work settled on.
public enum ImageFeatureOutcome: Sendable {
    /// Features for this photo, computed now or read from the cache. A missing print means
    /// Vision could not run; ``ImageFeatures/visionFailure`` says why (PRD P0-11 fallback).
    case features(ImageFeatures)
    /// No usable preview, so neither kind could run and grouping splits (PRD P0-11).
    case unavailable(ThumbnailUnavailable)
}

/// Cancellation is signalled from the actor before its worker reaches Vision or the file
/// system, so a cancelled photo never starts the work it was queued for.
private final class FeatureJobCancellation: Sendable {
    private let cancelled = Mutex(false)
    var isCancelled: Bool { cancelled.withLock { $0 } }
    func cancel() { cancelled.withLock { $0 = true } }
}

/// Computes similar groups' features in the background, one photo at a time (PRD P0-11).
///
/// G1 "Grouping (C9/I3)" and "Scheduling and cache" set the rules this type keeps:
///
/// - Low priority: work runs on Dispatch-backed `.utility` tasks with at most two workers, so the grid
///   and detail pipelines keep the CPU. It never uses their workers; it only shares I1's preview
///   cache when the app passes one.
/// - ``pause()`` stops starting work for user interaction or memory pressure and ``resume()``
///   continues it; work that already entered a read finishes and is delivered.
/// - ``cancel(folder:)`` and ``cancel(photo:in:)`` drop queued and running work without
///   delivering a result.
/// - Results stream as each photo finishes, so C9 can refine groups while the rest is computed.
///
/// ```swift
/// let pipeline = ImageFeaturePipeline(cache: cache, sharedPreviewCache: thumbnailCache)
/// let stream = await pipeline.run(requests)
/// for await result in stream {
///     // per-photo features, or .unavailable for a photo without a preview
/// }
/// ```
///
/// One pipeline is one session: it also remembers whether Vision is usable, so a host where
/// Vision cannot run costs a bounded number of attempts instead of one per photo.
public actor ImageFeaturePipeline {
    private struct Batch {
        let continuation: AsyncStream<ImageFeatureResult>.Continuation
        var remaining: Int
    }

    private struct Job: Sendable {
        let id: UUID
        let batch: UUID
        let request: ImageFeatureRequest
        let cancellation: FeatureJobCancellation
    }

    private let cache: ImageFeatureCache
    private let previews: any ImageFeaturePreviewReading
    private let extractor: ImageFeatureExtractor
    private let visionRevision: Int
    private let workers: Int
    private var queue: [UUID] = []
    private var active: Set<UUID> = []
    private var jobs: [UUID: Job] = [:]
    private var batches: [UUID: Batch] = [:]
    private var paused = false
    private var closed = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    /// Builds the production pipeline: I1's extractor for previews, Vision for prints.
    ///
    /// Pass I1's thumbnail cache as `sharedPreviewCache` so a feature reuses the preview the grid
    /// already extracted and leaves its own read behind for the grid (G1 "Preview, grid (I1)").
    /// Two workers is the upper bound G1 allows; running Vision twice at once is still far below
    /// the grid's four thumbnail workers.
    public init(
        cache: ImageFeatureCache, sharedPreviewCache: ThumbnailCache? = nil, workers: Int = 2
    ) {
        self.init(
            cache: cache, previews: ThumbnailPreviewReader(sharedCache: sharedPreviewCache),
            prints: VisionFeaturePrintReader(), workers: workers,
            visionFailureLimit: FeaturePrintSession.defaultFailureLimit)
    }

    /// The seam the tests use to replace the preview read and the Vision attempt.
    init(
        cache: ImageFeatureCache, previews: any ImageFeaturePreviewReading,
        prints: any FeaturePrintReading, workers: Int = 2,
        visionFailureLimit: Int = FeaturePrintSession.defaultFailureLimit
    ) {
        precondition((1...2).contains(workers), "Feature work is bounded to one or two workers")
        self.cache = cache
        self.previews = previews
        self.visionRevision = prints.revision
        self.extractor = ImageFeatureExtractor(
            prints: prints, session: FeaturePrintSession(failureLimit: visionFailureLimit))
        self.workers = workers
    }

    /// Queues a folder's photos and streams each result as its work settles.
    ///
    /// Work starts in the order the requests arrive, and duplicate requests in one call are
    /// computed once. Photos whose features are already cached settle without reading
    /// anything. The stream finishes when every queued photo settled, was cancelled, or the
    /// pipeline closed; a cancelled photo delivers nothing, because C9 has already stopped
    /// caring about it.
    ///
    /// Stopping the iteration cancels that call's remaining work, like ``cancel(folder:)``.
    public func run(_ requests: [ImageFeatureRequest]) -> AsyncStream<ImageFeatureResult> {
        let (stream, continuation) = AsyncStream<ImageFeatureResult>.makeStream()
        guard !closed else {
            continuation.finish()
            return stream
        }
        var seen: Set<ImageFeatureRequest> = []
        let unique = requests.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else {
            continuation.finish()
            return stream
        }
        let batch = UUID()
        batches[batch] = Batch(continuation: continuation, remaining: unique.count)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.cancel(batch: batch) }
        }
        for request in unique {
            let id = UUID()
            jobs[id] = Job(
                id: id, batch: batch, request: request,
                cancellation: FeatureJobCancellation())
            queue.append(id)
        }
        drain()
        return stream
    }

    /// One photo's features, for a follow-up fill-in. Nil when its work was cancelled.
    public func features(for request: ImageFeatureRequest) async -> ImageFeatureResult? {
        for await result in run([request]) { return result }
        return nil
    }

    /// Stops starting new feature work; running reads finish and are delivered.
    ///
    /// PRD P0-11 shows the grid while grouping refines, and G1 "Grouping (C9/I3)" asks features to
    /// pause under interaction and memory pressure. Pair this with ``releaseMemory()`` when the
    /// system is short of memory, then ``resume()``.
    public func pause() {
        paused = true
    }

    /// Continues work that was stopped by ``pause()``.
    public func resume() {
        guard paused else { return }
        paused = false
        drain()
    }

    /// Drops every queued and running photo of one folder, for example when it closes.
    public func cancel(folder identity: String) {
        for job in Array(jobs.values) where job.request.folderIdentity == identity {
            cancel(job.id)
        }
    }

    /// Drops one photo's queued or running work.
    ///
    /// The path is standardised like a request's is, so a caller's own spelling still matches.
    public func cancel(photo source: URL, in folder: String) {
        let path = source.standardizedFileURL
        for job in Array(jobs.values)
        where job.request.folderIdentity == folder && job.request.source == path {
            cancel(job.id)
        }
    }

    /// Drops cached features from memory, keeping the disk entries (memory-pressure path).
    public func releaseMemory() {
        cache.releaseMemory()
    }

    /// Whether Vision can run in this session, with the failure that stopped it (PRD P0-11).
    public var featurePrintStatus: FeaturePrintStatus {
        extractor.session.status
    }

    /// Stops accepting work, cancels what is queued and waits for running reads to drain.
    ///
    /// After this returns the caller can release the folder's security scope. Preview reads and
    /// Vision calls cannot be interrupted, so work already running finishes and is discarded.
    public func close() async {
        closed = true
        for id in Array(jobs.keys) { cancel(id) }
        for batch in Array(batches.keys) {
            batches[batch]?.continuation.finish()
            batches[batch] = nil
        }
        if !active.isEmpty {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
    }

    var queuedCount: Int { queue.count }
    var activeCount: Int { active.count }
    var isPaused: Bool { paused }

    private func cancel(_ id: UUID) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.cancellation.cancel()
        queue.removeAll { $0 == id }
        settle(job)
        // A running job keeps its worker slot until its read drains.
    }

    private func cancel(batch: UUID) {
        guard let cancelled = batches.removeValue(forKey: batch) else { return }
        for job in Array(jobs.values) where job.batch == batch {
            job.cancellation.cancel()
            queue.removeAll { $0 == job.id }
            jobs[job.id] = nil
        }
        cancelled.continuation.finish()
    }

    /// Counts one photo's work as settled, whatever the reason, and finishes its batch.
    private func settle(_ job: Job) {
        guard var batch = batches[job.batch] else { return }
        batch.remaining -= 1
        if batch.remaining <= 0 {
            batch.continuation.finish()
            batches[job.batch] = nil
        } else {
            batches[job.batch] = batch
        }
    }

    private func drain() {
        while !paused, !closed, active.count < workers, !queue.isEmpty {
            start(queue.removeFirst())
        }
    }

    private func start(_ id: UUID) {
        guard let job = jobs[id] else { return }
        guard !job.cancellation.isCancelled else {
            cancel(id)
            return
        }
        active.insert(id)
        let cache = cache
        let previews = previews
        let extractor = extractor
        let visionRevision = visionRevision
        Task.detached(executorPreference: ImageWorkExecutor.utility, priority: .utility) {
            let outcome = await Self.perform(
                job, cache: cache, previews: previews, extractor: extractor,
                visionRevision: visionRevision)
            await self.complete(id, outcome: outcome)
        }
    }

    private func complete(_ id: UUID, outcome: ImageFeatureOutcome?) {
        active.remove(id)
        if let job = jobs.removeValue(forKey: id) {
            if let outcome, !job.cancellation.isCancelled, let batch = batches[job.batch] {
                batch.continuation.yield(
                    ImageFeatureResult(request: job.request, outcome: outcome))
            }
            settle(job)
        }
        drain()
        if closed && active.isEmpty {
            let waiters = closeWaiters
            closeWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    /// One photo, end to end, off the actor: cache, preview read, both features.
    private nonisolated static func perform(
        _ job: Job, cache: ImageFeatureCache, previews: any ImageFeaturePreviewReading,
        extractor: ImageFeatureExtractor, visionRevision: Int
    ) async -> ImageFeatureOutcome? {
        if job.cancellation.isCancelled { return nil }
        let request = job.request
        guard isCurrent(request.preview) else { return .unavailable(.sourceChanged) }
        for route in ThumbnailExtractor.routes(for: request.preview) {
            guard
                let cached = cache.features(
                    for: request, route: route, visionRevision: visionRevision)
            else { continue }
            guard isSettled(cached, session: extractor.session) else { continue }
            // A settled hash-only record means the session gave up on Vision; the caller still
            // needs the reason the photo has no print.
            if cached.print == nil, let failure = extractor.session.lastFailure {
                return .features(
                    ImageFeatures(
                        differenceHash: cached.differenceHash, visionFailure: failure))
            }
            return .features(cached)
        }
        let read = await previews.preview(for: request.preview)
        switch read {
        case .unavailable(let reason):
            return .unavailable(reason)
        case .preview(let preview):
            if job.cancellation.isCancelled { return nil }
            guard isCurrent(request.preview) else { return .unavailable(.sourceChanged) }
            let features = await extractor.features(from: preview.image)
            if job.cancellation.isCancelled { return nil }
            guard isCurrent(request.preview) else { return .unavailable(.sourceChanged) }
            try? cache.store(
                features, route: preview.route, visionRevision: visionRevision, for: request)
            return .features(features)
        }
    }

    /// Whether a cached record already answers everything this session can answer.
    ///
    /// A print is complete on its own. A hash alone is complete only when the session gave up on
    /// Vision, because P0-11's fallback is the degraded mode and not a verdict on the photo: the
    /// next analysis pass, or the next launch, asks Vision once more and keeps the hash either
    /// way. A route with an incomplete record is skipped rather than ending the search.
    private nonisolated static func isSettled(
        _ features: ImageFeatures, session: FeaturePrintSession
    ) -> Bool {
        features.print != nil || !session.permitsAttempt
    }

    private nonisolated static func isCurrent(_ request: ThumbnailRequest) -> Bool {
        (try? ThumbnailRevision.read(from: request.source)) == request.revision
    }
}
