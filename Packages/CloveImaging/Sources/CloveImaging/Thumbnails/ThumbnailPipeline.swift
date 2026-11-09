import Foundation

/// Cancellation is signalled synchronously from onCancel, before its actor hop.
/// This closes the race between queued native entry/completion and cancellation.
private final class ThumbnailCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
    func deliver(_ body: (Bool) -> Void) { lock.withLock { body(cancelled) } }
}

public actor ThumbnailPipeline {
    private struct Job {
        let id: UUID
        let consumer: UUID
        let request: ThumbnailRequest
        let priority: ThumbnailPriority
        let cancellation: ThumbnailCancellation
        let continuation: CheckedContinuation<ThumbnailResult, any Error>
    }

    private let cache: ThumbnailCache
    private let decode: @Sendable (ThumbnailRequest) async -> ThumbnailResult
    private let queueLimit: Int
    private var workerCount: Int
    private var queue: [UUID] = []
    private var active: Set<UUID> = []
    private var jobs: [UUID: Job] = [:]
    private var latest: [UUID: UUID] = [:]
    private var closed = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    public init(cache: ThumbnailCache, workers: Int = 4, queueLimit: Int = 128) {
        precondition(workers > 0 && queueLimit > 0)
        self.cache = cache
        self.workerCount = workers
        self.queueLimit = queueLimit
        self.decode = { ThumbnailExtractor().extract($0) }
    }

    init(
        cache: ThumbnailCache, workers: Int, queueLimit: Int = 128,
        decode: @escaping @Sendable (ThumbnailRequest) async -> ThumbnailResult
    ) {
        precondition(workers > 0 && queueLimit > 0)
        self.cache = cache
        self.workerCount = workers
        self.queueLimit = queueLimit
        self.decode = decode
    }

    /// Reuse a consumer ID for a cell/view: its newer request supersedes its old
    /// request. Cancellation/supersession throws CancellationError, never pixels.
    /// A full queue throws queueFull; visible work may displace queued prefetch.
    public func thumbnail(
        for request: ThumbnailRequest, consumer: UUID = UUID(),
        priority: ThumbnailPriority = .visible
    ) async throws -> ThumbnailResult {
        let id = UUID()
        let cancellation = ThumbnailCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !closed else { throw ThumbnailPipelineError.closed }
            return try await withCheckedThrowingContinuation { continuation in
                if let old = latest[consumer] { cancel(old) }
                if queue.count >= queueLimit {
                    if priority == .visible,
                        let victim = queue.last(where: { jobs[$0]?.priority == .prefetch })
                    {
                        cancel(victim)
                    } else {
                        continuation.resume(throwing: ThumbnailPipelineError.queueFull)
                        return
                    }
                }
                let job = Job(
                    id: id, consumer: consumer, request: request, priority: priority,
                    cancellation: cancellation, continuation: continuation)
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

    /// Use two under contention/pressure. Running native calls retain their slots
    /// until completion, including after cancellation or reducing this limit.
    public func setWorkerCount(_ count: Int) {
        precondition(count > 0)
        workerCount = count
        drain()
    }

    public func cancelPrefetch() {
        for job in Array(jobs.values) where job.priority == .prefetch { cancel(job.id) }
    }

    /// Stop accepting work, cancel requests and wait for native calls to drain.
    /// After this returns, the caller can release the folder's security scope.
    public func close() async {
        closed = true
        for id in Array(jobs.keys) { cancel(id) }
        if !active.isEmpty {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
    }

    var queuedCount: Int { queue.count }
    var activeCount: Int { active.count }

    private func cancel(_ id: UUID) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.cancellation.cancel()
        queue.removeAll { $0 == id }
        if latest[job.consumer] == id { latest[job.consumer] = nil }
        job.continuation.resume(throwing: CancellationError())
        // An active slot is released only by complete(), after native work drains.
    }

    private func drain() {
        while active.count < workerCount, !queue.isEmpty {
            let index = queue.firstIndex { jobs[$0]?.priority == .visible } ?? 0
            let id = queue.remove(at: index)
            guard let job = jobs[id] else { continue }
            if job.cancellation.isCancelled {
                cancel(id)
                continue
            }
            active.insert(id)
            let cache = cache
            let decode = decode
            Task.detached(priority: job.priority == .visible ? .userInitiated : .utility) {
                let result: ThumbnailResult
                if job.cancellation.isCancelled {
                    result = .unavailable(.noUsablePreview)
                } else if (try? ThumbnailRevision.read(from: job.request.source))
                    != job.request.revision
                {
                    result = .unavailable(.sourceChanged)
                } else if let cached = cache.result(for: job.request) {
                    result = cached
                } else if job.cancellation.isCancelled {
                    result = .unavailable(.noUsablePreview)
                } else {
                    let extracted = await decode(job.request)
                    if (try? ThumbnailRevision.read(from: job.request.source))
                        != job.request.revision
                    {
                        result = .unavailable(.sourceChanged)
                    } else {
                        result = extracted
                        if !job.cancellation.isCancelled {
                            try? cache.store(result, for: job.request)
                        }
                    }
                }
                // Check cache hits too: the source may change during disk IO.
                let current =
                    (try? ThumbnailRevision.read(from: job.request.source)) == job.request.revision
                await self.complete(id, result: current ? result : .unavailable(.sourceChanged))
            }
        }
    }

    private func complete(_ id: UUID, result: ThumbnailResult) {
        active.remove(id)
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
}
