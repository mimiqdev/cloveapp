import Foundation
import Synchronization

/// Cancellation is signalled synchronously from onCancel, before its actor hop.
/// This closes the race between queued native entry/completion and cancellation.
private final class ThumbnailCancellation: Sendable {
    private let cancelled = Mutex(false)
    var isCancelled: Bool { cancelled.withLock { $0 } }
    func cancel() { cancelled.withLock { $0 = true } }
    func deliver(_ body: (Bool) -> Void) { cancelled.withLock { body($0) } }
}

public actor ThumbnailPipeline {
    private struct Waiter {
        let id: UUID
        let workID: UUID
        let consumer: UUID
        let priority: ThumbnailPriority
        let cancellation: ThumbnailCancellation
        let continuation: CheckedContinuation<ThumbnailResult, any Error>
    }

    private struct Work {
        let id: UUID
        let request: ThumbnailRequest
        var priority: ThumbnailPriority
        var waiterIDs: [UUID]
        let cancellation: ThumbnailCancellation
    }

    private let cache: ThumbnailCache
    private let decode: @Sendable (ThumbnailRequest) async -> ThumbnailResult
    private let queueLimit: Int
    private var workerCount: Int
    private var queue: [UUID] = []
    private var active: Set<UUID> = []
    private var works: [UUID: Work] = [:]
    private var workByRequest: [ThumbnailRequest: UUID] = [:]
    private var waiters: [UUID: Waiter] = [:]
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

    /// Synchronous memory-only lookup; never hops onto the actor or touches disk.
    public nonisolated func cachedResult(for request: ThumbnailRequest) -> ThumbnailResult? {
        cache.memoryResult(for: request)
    }

    /// Reuse a consumer ID for a cell/view: its newer request supersedes its old
    /// request. Equivalent in-flight requests coalesce and promote `.prefetch` to
    /// `.visible`. Cancellation/supersession throws CancellationError, never pixels.
    /// A full queue throws queueFull; visible work may displace queued prefetch.
    public func thumbnail(
        for request: ThumbnailRequest, consumer: UUID = UUID(),
        priority: ThumbnailPriority = .visible
    ) async throws -> ThumbnailResult {
        let waiterID = UUID()
        let waiterCancellation = ThumbnailCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !closed else { throw ThumbnailPipelineError.closed }
            return try await withCheckedThrowingContinuation { continuation in
                let oldWaiterID = latest[consumer]
                if let existingWorkID = workByRequest[request], var work = works[existingWorkID] {
                    let waiter = Waiter(
                        id: waiterID, workID: existingWorkID, consumer: consumer,
                        priority: priority, cancellation: waiterCancellation,
                        continuation: continuation)
                    waiters[waiterID] = waiter
                    latest[consumer] = waiterID
                    work.waiterIDs.append(waiterID)
                    if priority == .visible && work.priority == .prefetch {
                        work.priority = .visible
                    }
                    works[existingWorkID] = work
                    if let oldWaiterID { cancelWaiter(oldWaiterID) }
                    drain()
                    return
                }
                if let oldWaiterID { cancelWaiter(oldWaiterID) }
                if queue.count >= queueLimit {
                    if priority == .visible,
                        let victim = queue.last(where: { works[$0]?.priority == .prefetch })
                    {
                        cancelWork(victim)
                    } else {
                        continuation.resume(throwing: ThumbnailPipelineError.queueFull)
                        return
                    }
                }
                let workID = UUID()
                let work = Work(
                    id: workID, request: request, priority: priority, waiterIDs: [waiterID],
                    cancellation: ThumbnailCancellation())
                let waiter = Waiter(
                    id: waiterID, workID: workID, consumer: consumer, priority: priority,
                    cancellation: waiterCancellation, continuation: continuation)
                works[workID] = work
                workByRequest[request] = workID
                waiters[waiterID] = waiter
                latest[consumer] = waiterID
                queue.append(workID)
                drain()
            }
        } onCancel: {
            waiterCancellation.cancel()
            Task { await self.cancelWaiter(waiterID) }
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
        for waiter in Array(waiters.values) where waiter.priority == .prefetch {
            cancelWaiter(waiter.id)
        }
    }

    /// Stop accepting work, cancel requests and wait for native calls to drain.
    /// After this returns, the caller can release the folder's security scope.
    public func close() async {
        closed = true
        for workID in Array(works.keys) { cancelWork(workID) }
        if !active.isEmpty {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
    }

    var queuedCount: Int { queue.count }
    var activeCount: Int { active.count }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let waiter = waiters.removeValue(forKey: waiterID) else { return }
        waiter.cancellation.cancel()
        if latest[waiter.consumer] == waiterID { latest[waiter.consumer] = nil }
        waiter.continuation.resume(throwing: CancellationError())
        guard var work = works[waiter.workID] else { return }
        work.waiterIDs.removeAll { $0 == waiterID }
        if work.waiterIDs.isEmpty {
            cancelWork(work.id)
        } else {
            work.priority =
                work.waiterIDs.contains { waiters[$0]?.priority == .visible }
                ? .visible : .prefetch
            works[work.id] = work
        }
    }

    private func cancelWork(_ workID: UUID) {
        guard let work = works[workID] else { return }
        work.cancellation.cancel()
        if workByRequest[work.request] == workID { workByRequest[work.request] = nil }
        queue.removeAll { $0 == workID }
        for waiterID in work.waiterIDs {
            guard let waiter = waiters.removeValue(forKey: waiterID) else { continue }
            waiter.cancellation.cancel()
            if latest[waiter.consumer] == waiterID { latest[waiter.consumer] = nil }
            waiter.continuation.resume(throwing: CancellationError())
        }
        if active.contains(workID) {
            var draining = work
            draining.waiterIDs.removeAll()
            works[workID] = draining
        } else {
            works[workID] = nil
        }
        // An active slot is released only by complete(), after native work drains.
    }

    private func drain() {
        while active.count < workerCount, !queue.isEmpty {
            let index = queue.firstIndex { works[$0]?.priority == .visible } ?? 0
            let workID = queue.remove(at: index)
            guard let work = works[workID] else { continue }
            let hasLiveWaiter = work.waiterIDs.contains {
                waiters[$0]?.cancellation.isCancelled == false
            }
            if work.cancellation.isCancelled || !hasLiveWaiter {
                cancelWork(workID)
                continue
            }
            active.insert(workID)
            let cache = cache
            let decode = decode
            let request = work.request
            let workCancellation = work.cancellation
            let priority = work.priority
            Task.detached(
                executorPreference: priority == .visible
                    ? ImageWorkExecutor.userInitiated : ImageWorkExecutor.utility,
                priority: priority == .visible ? .userInitiated : .utility
            ) {
                let result: ThumbnailResult
                if workCancellation.isCancelled {
                    result = .unavailable(.noUsablePreview)
                } else if let cached = cache.result(for: request) {
                    result = cached
                } else if workCancellation.isCancelled {
                    result = .unavailable(.noUsablePreview)
                } else {
                    let extracted = await decode(request)
                    // Single post-decode revision check on misses catches external rewrites
                    // during decode without stating on cache hits.
                    if (try? ThumbnailRevision.read(from: request.source)) != request.revision {
                        result = .unavailable(.sourceChanged)
                    } else {
                        result = extracted
                        if !workCancellation.isCancelled {
                            try? cache.store(result, for: request)
                        }
                    }
                }
                await self.complete(workID, result: result)
            }
        }
    }

    private func complete(_ workID: UUID, result: ThumbnailResult) {
        active.remove(workID)
        if let work = works.removeValue(forKey: workID) {
            if workByRequest[work.request] == workID { workByRequest[work.request] = nil }
            for waiterID in work.waiterIDs {
                guard let waiter = waiters.removeValue(forKey: waiterID) else { continue }
                if latest[waiter.consumer] == waiterID { latest[waiter.consumer] = nil }
                waiter.cancellation.deliver { cancelled in
                    if cancelled {
                        waiter.continuation.resume(throwing: CancellationError())
                    } else {
                        waiter.continuation.resume(returning: result)
                    }
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
