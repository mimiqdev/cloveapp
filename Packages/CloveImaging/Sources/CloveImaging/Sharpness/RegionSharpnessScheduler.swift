import Foundation

/// Which pool a queued analysis belongs to (#216's priority order: current photo, then its
/// burst/similar group, then nearby/prefetch, then the remaining folder).
public enum SharpnessWorkPriority: Int, CaseIterable, Hashable, Sendable, Comparable {
    /// The photo the person is looking at.
    case current = 0
    /// Other members of the current burst/similar group.
    case group = 1
    /// Photos around the current one, and explicit prefetch.
    case nearby = 2
    /// Every remaining photo of the open folder.
    case folder = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Per-stage queue/active counts and entry timings, for later device measurement (#216).
/// Exposed as recorded facts; no performance claim is derived here.
public struct SharpnessSchedulerSnapshot: Sendable, Equatable {
    public struct Stage: Sendable, Equatable {
        /// Analyses waiting for this stage's budget.
        public let queued: Int
        /// Stage entries currently running.
        public let active: Int
        /// Stage entries admitted since the scheduler was created.
        public let startedCount: Int
        /// Stage entries finished since the scheduler was created.
        public let finishedCount: Int
        /// Wall-clock of the most recent finished entries, oldest first.
        public let durations: [ContinuousClock.Duration]
    }

    public let paused: Bool
    /// Jobs holding no stage slot right now, by priority: the queue a promotion or demotion
    /// reorders. A job that never started holds only its request (#216's "queued jobs hold
    /// identifiers/paths, not decoded images").
    public let queuedByPriority: [SharpnessWorkPriority: Int]
    public let stages: [SharpnessAnalysisStage: Stage]
}

/// The prioritized execution policy around ``RegionSharpnessAnalyzer`` (#216).
///
/// What this actor owns and what it deliberately does not:
///
/// - **Stage budgets.** Face/eye localization, the high-resolution acquisition and local
///   scoring each keep their own bound. Admission is asked per stage, so priorities are
///   reconsidered whenever a slot frees — the issue's "reconsider priorities between
///   stages".
/// - **No mid-stage displacement.** A running Vision request or decode is uncancellable at
///   this layer; it finishes and the newly prioritized work takes the next slot, exactly the
///   issue's fallback for pipelines without cancellation.
/// - **Queued jobs are records.** A job's analysis task parks at its first stage admission,
///   so a thousand queued jobs are a thousand parked tasks holding requests — files and
///   revisions — and nothing else. Completed results go to ``RegionSharpnessResultStore`` as
///   compact facts; no queued job or stored record ever holds pixels.
/// - **The engine's own rules are untouched.** One acquisition per photo, one detection
///   request per analysis, and #215's early-AF delivery all live in the analyzer; this type
///   only decides when each stage may run.
public actor RegionSharpnessScheduler {
    /// How many finished stage durations each stage keeps for measurement.
    private static let recordedDurations = 64

    public let parametersVersion: Int

    private let baseAnalyzer: RegionSharpnessAnalyzer
    private let results: RegionSharpnessResultStore

    private struct StageState {
        var limit: Int
        /// Jobs whose stage entry is running. Counted as a set so a dropped job still
        /// releases its slot through ``releaseStage``, never through the drop itself.
        var activeKeys: Set<SharpnessResultKey> = []
        var startedCount: Int = 0
        var finishedCount: Int = 0
        var durations: [ContinuousClock.Duration] = []
        var starts: [SharpnessResultKey: ContinuousClock.Instant] = [:]
        var waiters: [Waiter] = []

        var active: Int { activeKeys.count }
    }

    private struct Waiter {
        let key: SharpnessResultKey
        let sequence: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// One photo's unit of work. While queued this is only identifiers; the analysis task
    /// exists once `task` is set and parks at its first stage admission.
    private struct Job {
        let key: SharpnessResultKey
        let request: RegionSharpnessRequest
        var priority: SharpnessWorkPriority
        let sequence: Int
        var waiters: [CheckedContinuation<RegionSharpnessAnalysis?, Never>] = []
        var task: Task<Void, Never>?
        /// The interactive caller's early-AF callback, attached by the call that starts the
        /// job (#215's early delivery, passed through).
        var onAutofocus: (@Sendable (RegionSharpnessPathResult) -> Void)?
    }

    private var stages: [SharpnessAnalysisStage: StageState]
    private var jobs: [SharpnessResultKey: Job] = [:]
    private var nextSequence = 0
    private var waiterSequence = 0
    /// The job generation of one key: bumped on every drop, so a task that was already
    /// running for a dropped job can never settle or publish for the job that replaced it
    /// (#216: never publish a result for another photo or folder session).
    private var generations: [SharpnessResultKey: Int] = [:]
    private var paused = false
    /// Parked-on-pause continuations keyed by job, so a cancelled job's park is resumed on
    /// invalidate/drop instead of leaking until resume (#216).
    private var pausedWaiters: [SharpnessResultKey: [CheckedContinuation<Void, Never>]] = [:]
    private var closed = false

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - analyzer: the engine whose stages this scheduler admits. Its reader, detector and
    ///     scorer are shared; each job runs through a copy gated by this scheduler.
    ///   - detectionWorkers: the face/eye localization budget (the issue's starting value: 1).
    ///   - acquisitionWorkers: the high-resolution acquisition budget (the issue fixes 1,
    ///     shared with interactive viewing through the detail pipeline's own render lane).
    ///   - scoringWorkers: the local scoring budget (the issue allows 1–2).
    ///   - results: the compact result store shared by interactive and background requests.
    ///   - parametersVersion: the scorer/detector version baked into every result key.
    public init(
        analyzer: RegionSharpnessAnalyzer,
        detectionWorkers: Int = 1,
        acquisitionWorkers: Int = 1,
        scoringWorkers: Int = 2,
        results: RegionSharpnessResultStore = RegionSharpnessResultStore(capacity: 512),
        parametersVersion: Int = 1
    ) {
        precondition(detectionWorkers >= 1 && acquisitionWorkers >= 1 && scoringWorkers >= 1)
        self.baseAnalyzer = analyzer
        self.results = results
        self.parametersVersion = parametersVersion
        var configured: [SharpnessAnalysisStage: StageState] = [:]
        for stage in SharpnessAnalysisStage.allCases {
            let limit =
                stage == .faceDetection
                ? detectionWorkers
                : stage == .pixelAcquisition ? acquisitionWorkers : scoringWorkers
            configured[stage] = StageState(limit: limit)
        }
        self.stages = configured
    }

    // MARK: - Submitting work

    /// Queues photos for background analysis. Requests already running or already cached are
    /// not queued again; an interactive priority is never lowered by a background submit
    /// (#216: interactive and background work share valid cached results).
    public func submit(_ requests: [RegionSharpnessRequest], priority: SharpnessWorkPriority) {
        guard !closed else { return }
        for request in requests { submit(request, priority: priority) }
        pump()
    }

    /// One photo's analysis at interactive priority (#216): a valid cached result returns
    /// without new work, an in-flight analysis is joined (and promoted), and only a new photo
    /// starts work. Returns nil when the scheduler closed or the photo was invalidated.
    ///
    /// `onAutofocus`, when supplied and this call starts the photo's work, receives the AF
    /// path's result before face detection is waited on — the engine's early-AF delivery
    /// (#215) passed through the scheduler. A call that joins in-flight or cached work gets
    /// the same AF result in the returned analysis, without an early callback.
    public func analyzeCurrent(
        _ request: RegionSharpnessRequest,
        onAutofocus: (@Sendable (RegionSharpnessPathResult) -> Void)? = nil
    ) async -> RegionSharpnessAnalysis? {
        guard !closed else { return nil }
        let key = resultKey(for: request)
        if let cached = results.result(for: key) { return cached }
        if jobs[key] == nil {
            submit(request, priority: .current)
            jobs[key]?.onAutofocus = onAutofocus
            pump()
        }
        return await join(key: key, priority: .current)
    }

    /// Suspends until the job settles, promoting its priority when the joiner outranks it.
    private func join(key: SharpnessResultKey, priority: SharpnessWorkPriority) async
        -> RegionSharpnessAnalysis?
    {
        await withCheckedContinuation { continuation in
            guard var job = jobs[key] else {
                continuation.resume(returning: results.result(for: key))
                return
            }
            // Joining at a higher priority promotes the shared work (#216).
            if priority < job.priority { job.priority = priority }
            job.waiters.append(continuation)
            jobs[key] = job
            pump()
        }
    }

    private func submit(_ request: RegionSharpnessRequest, priority: SharpnessWorkPriority) {
        let key = resultKey(for: request)
        if results.result(for: key) != nil { return }
        if var existing = jobs[key] {
            if priority < existing.priority {
                existing.priority = priority
                jobs[key] = existing
            }
            return
        }
        nextSequence += 1
        // The job's generation is what lets an old dropped task be told apart from a newer
        // same-key job: every submit and every drop retires the previous generation (#216).
        generations[key] = (generations[key] ?? 0) + 1
        jobs[key] = Job(
            key: key, request: request, priority: priority, sequence: nextSequence)
    }

    // MARK: - Navigation priorities

    /// Applies #216's priority order for the folder view the person is in now: the current
    /// photo, its burst/similar group, and nearby/prefetch photos keep or gain their rank,
    /// and every queued or running analysis an earlier view promoted is demoted back to
    /// folder priority — rapid navigation leaves no obsolete urgent backlog.
    public func focus(
        current: RegionSharpnessRequest,
        group: [RegionSharpnessRequest] = [],
        nearby: [RegionSharpnessRequest] = []
    ) {
        guard !closed else { return }
        let ranked: [(RegionSharpnessRequest, SharpnessWorkPriority)] =
            [(current, .current)] + group.map { ($0, .group) } + nearby.map { ($0, .nearby) }
        let kept = Set(ranked.map { resultKey(for: $0.0) })
        for key in jobs.keys where !kept.contains(key) {
            // Not part of the view the person is in now: no urgency left.
            jobs[key]?.priority = .folder
        }
        for (request, priority) in ranked {
            let key = resultKey(for: request)
            if var job = jobs[key], priority < job.priority {
                job.priority = priority
                jobs[key] = job
            }
        }
        pump()
    }

    // MARK: - Pause and cancellation

    /// Stops admitting new stage entries; running entries finish. The memory-pressure and
    /// interaction handle (#216) — pair with ``resume()``.
    public func pause() { paused = true }

    /// Continues work stopped by ``pause()``: parked tasks resume, and every stage queue
    /// drains into its free slots, not just the jobs that were waiting on the pause itself.
    public func resume() {
        guard paused else { return }
        paused = false
        let resuming = pausedWaiters
        pausedWaiters.removeAll()
        for waiters in resuming.values {
            for waiter in waiters { waiter.resume() }
        }
        for stage in SharpnessAnalysisStage.allCases { drain(stage) }
        pump()
    }

    /// Drops queued and running work whose photo set touches any of the given files and
    /// invalidates their stored results — the source-change and folder-close path (#216).
    public func invalidate(sources: [URL]) {
        let files = Set(sources.map { $0.standardizedFileURL })
        guard !files.isEmpty else { return }
        results.invalidate(sources: sources)
        // Iterated over a copy: dropping mutates the same dictionary (#216).
        for (key, request) in jobs.mapValues(\.request)
        where !Set(request.fileURLs).isDisjoint(with: files) {
            drop(key: key)
        }
        pump()
    }

    /// Stops accepting work, cancels everything queued and running, and waits for running
    /// stage entries to drain.
    public func close() async {
        closed = true
        for key in Array(pausedWaiters.keys) { resumePausedWaiters(of: key) }
        let running = jobs.values.compactMap(\.task)
        for key in Array(jobs.keys) { drop(key: key) }
        // Admitted stage entries exit through their own path, cancelled or not; awaiting the
        // tasks is what makes the return safe for the folder's security scope.
        for task in running { _ = await task.value }
    }

    // MARK: - Measurement

    /// How many task admissions are parked on the pause itself. Exposed for tests to observe
    /// that invalidate/drop also ends these parks (#216).
    var pausedAdmissionCount: Int { pausedWaiters.values.reduce(0) { $0 + $1.count } }

    /// Per-stage queue/active counts and recent entry durations (#216).
    public func snapshot() -> SharpnessSchedulerSnapshot {
        var running = Set<SharpnessResultKey>()
        for stage in stages.values { running.formUnion(stage.activeKeys) }
        var queued: [SharpnessWorkPriority: Int] = [:]
        for (key, job) in jobs where !running.contains(key) {
            queued[job.priority, default: 0] += 1
        }
        return SharpnessSchedulerSnapshot(
            paused: paused,
            queuedByPriority: queued,
            stages: stages.mapValues { state in
                SharpnessSchedulerSnapshot.Stage(
                    queued: state.waiters.count, active: state.active,
                    startedCount: state.startedCount, finishedCount: state.finishedCount,
                    durations: state.durations)
            })
    }

    // MARK: - Stage admission (the analyzer's gate)

    /// Requests one stage slot for one job. Suspends while the scheduler is paused, the
    /// budget is full, or a higher-priority photo is waiting; throws when the job was
    /// cancelled, invalidated or closed while it waited.
    func requestStage(
        _ stage: SharpnessAnalysisStage, of key: SharpnessResultKey
    ) async throws {
        while paused, !closed, jobs[key] != nil {
            try Task.checkCancellation()
            // Parked under the job's key, so invalidate/drop can resume (and thereby cancel)
            // this park without waiting for resume (#216).
            await withCheckedContinuation { continuation in
                pausedWaiters[key, default: []].append(continuation)
            }
        }
        try Task.checkCancellation()
        guard !closed, jobs[key] != nil else { throw CancellationError() }
        guard var state = stages[stage] else { throw CancellationError() }
        guard state.activeKeys.count < state.limit, state.waiters.isEmpty else {
            waiterSequence += 1
            let sequence = waiterSequence
            try await withTaskCancellationHandler {
                try await self.park(
                    stage, of: key, sequence: sequence)
            } onCancel: {
                Task { await self.refuseStage(stage, of: key, sequence: sequence) }
            }
            return
        }
        admit(stage, key: key, into: &state)
        stages[stage] = state
    }

    /// Resumes (and thereby ends) every pause-park of one job.
    private func resumePausedWaiters(of key: SharpnessResultKey) {
        let waiters = pausedWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters { waiter.resume() }
    }

    /// Parks one job's stage request in the stage's queue until a slot admits it.
    private func park(
        _ stage: SharpnessAnalysisStage, of key: SharpnessResultKey, sequence: Int
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            stages[stage]?.waiters.append(
                Waiter(key: key, sequence: sequence, continuation: continuation))
        }
    }

    /// Resumes one cancelled waiter with a cancellation error and removes it from the queue.
    func refuseStage(
        _ stage: SharpnessAnalysisStage, of key: SharpnessResultKey, sequence: Int
    ) {
        guard var state = stages[stage] else { return }
        guard
            let index = state.waiters.firstIndex(where: { $0.sequence == sequence })
        else { return }
        let waiter = state.waiters.remove(at: index)
        stages[stage] = state
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// Releases one stage slot and admits the best waiting photo.
    func releaseStage(_ stage: SharpnessAnalysisStage, of key: SharpnessResultKey) async {
        guard var state = stages[stage], state.activeKeys.remove(key) != nil else { return }
        state.finishedCount += 1
        if let start = state.starts.removeValue(forKey: key) {
            state.durations.append(start.duration(to: .now))
            if state.durations.count > Self.recordedDurations {
                state.durations.removeFirst(state.durations.count - Self.recordedDurations)
            }
        }
        stages[stage] = state
        drain(stage)
        pump()
    }

    /// Admits waiting work into one stage's free slots, best photo first.
    private func drain(_ stage: SharpnessAnalysisStage) {
        guard !paused, !closed else { return }
        while var state = stages[stage], state.activeKeys.count < state.limit,
            let index = bestWaiterIndex(in: state.waiters)
        {
            let waiter = state.waiters.remove(at: index)
            guard jobs[waiter.key] != nil else {
                // The job was dropped while its stage entry waited; it never runs.
                stages[stage] = state
                waiter.continuation.resume(throwing: CancellationError())
                continue
            }
            admit(stage, key: waiter.key, into: &state)
            stages[stage] = state
            waiter.continuation.resume()
        }
    }

    private func bestWaiterIndex(in waiters: [Waiter]) -> Int? {
        guard !waiters.isEmpty else { return nil }
        var best = 0
        for index in waiters.indices {
            let current = waiters[index]
            let bestWaiter = waiters[best]
            let currentPriority = jobs[current.key]?.priority ?? .folder
            let bestPriority = jobs[bestWaiter.key]?.priority ?? .folder
            if currentPriority < bestPriority
                || (currentPriority == bestPriority
                    && (jobs[current.key]?.sequence ?? 0) < (jobs[bestWaiter.key]?.sequence ?? 0))
            {
                best = index
            }
        }
        return best
    }

    private func admit(
        _ stage: SharpnessAnalysisStage, key: SharpnessResultKey, into state: inout StageState
    ) {
        state.activeKeys.insert(key)
        state.startedCount += 1
        state.starts[key] = .now
    }

    // MARK: - Job execution

    /// Starts every job that has no task yet (#216). A started job is not running work: its
    /// task parks at its first stage admission until a slot and the top rank are its.
    private func pump() {
        guard !closed else { return }
        while let key = bestQueuedKey() { start(key) }
    }

    private func bestQueuedKey() -> SharpnessResultKey? {
        var best: (key: SharpnessResultKey, priority: SharpnessWorkPriority, sequence: Int)? = nil
        for (key, job) in jobs where job.task == nil {
            guard
                job.priority < best?.priority ?? .folder
                    || (job.priority == best?.priority ?? .folder
                        && job.sequence < best?.sequence ?? .max)
            else { continue }
            best = (key, job.priority, job.sequence)
        }
        return best?.key
    }

    private func start(_ key: SharpnessResultKey) {
        guard var job = jobs[key], job.task == nil else { return }
        let analyzer = baseAnalyzer
        let request = job.request
        let onAutofocus = job.onAutofocus
        let generation = generations[key] ?? 0
        let gate = SchedulerStageGate(key: key, scheduler: self)
        let owner = self
        let forwarder: (@Sendable (RegionSharpnessPathResult) -> Void)?
        if let onAutofocus {
            // Only the generation that started this job may deliver early AF: a dropped
            // job's in-flight callback must not reach a newer job's caller (#216).
            forwarder = { result in
                Task {
                    await owner.deliverEarlyAutofocus(
                        result, for: key, generation: generation, to: onAutofocus)
                }
            }
        } else {
            forwarder = nil
        }
        let task = Task.detached(priority: .utility) {
            await Self.run(
                analyzer: analyzer, gatedBy: gate, request: request, owner: self, key: key,
                generation: generation, onAutofocus: forwarder)
        }
        job.task = task
        jobs[key] = job
    }

    /// Forwards an early-AF callback only while its job's generation is still current.
    private func deliverEarlyAutofocus(
        _ result: RegionSharpnessPathResult, for key: SharpnessResultKey, generation: Int,
        to callback: @Sendable (RegionSharpnessPathResult) -> Void
    ) {
        guard generations[key] == generation, jobs[key] != nil else { return }
        callback(result)
    }

    /// One job's analysis, off the actor. Stage admission and settling hop back on, each
    /// with the generation the analysis belongs to.
    private static func run(
        analyzer: RegionSharpnessAnalyzer, gatedBy gate: SchedulerStageGate,
        request: RegionSharpnessRequest, owner: RegionSharpnessScheduler,
        key: SharpnessResultKey, generation: Int,
        onAutofocus: (@Sendable (RegionSharpnessPathResult) -> Void)?
    ) async {
        let analysis = try? await analyzer.gated(by: gate).analyzeGated(
            request, onAutofocus: onAutofocus)
        await owner.settle(key: key, generation: generation, analysis: analysis)
    }

    /// Publishes one finished analysis to waiters and the store, or clears a cancelled one.
    /// An old generation settles into nothing: its job was dropped and possibly replaced, so
    /// the newer job owns the key's answer (#216).
    private func settle(
        key: SharpnessResultKey, generation: Int, analysis: RegionSharpnessAnalysis?
    ) {
        guard generations[key] == generation else { return }
        guard let job = jobs.removeValue(forKey: key) else {
            return  // dropped while running: nothing to publish
        }
        generations.removeValue(forKey: key)
        if let analysis {
            results.store(
                RegionSharpnessRecord(key: key, request: job.request, analysis: analysis))
        }
        for waiter in job.waiters { waiter.resume(returning: analysis) }
        pump()
    }

    /// Cancels one job: parked stage entries are refused, its task is cancelled, waiters get
    /// nil.
    private func drop(key: SharpnessResultKey) {
        guard let job = jobs.removeValue(forKey: key) else { return }
        // Any later same-key job is a new generation; this drop retires the old one.
        generations[key] = (generations[key] ?? 0) + 1
        resumePausedWaiters(of: key)
        job.task?.cancel()
        for waiter in job.waiters { waiter.resume(returning: nil) }
        for stage in SharpnessAnalysisStage.allCases {
            // A parked stage entry never started, so it is refused outright — resumed, never
            // silently dropped, or its task would leak. A running entry keeps its slot until
            // it exits: the budget bounds real work, and the uncancellable request
            // underneath is still occupying it.
            guard var state = stages[stage] else { continue }
            let parked = state.waiters.filter { $0.key == key }
            guard !parked.isEmpty else { continue }
            state.waiters.removeAll { $0.key == key }
            stages[stage] = state
            for waiter in parked { waiter.continuation.resume(throwing: CancellationError()) }
        }
    }

    private func resultKey(for request: RegionSharpnessRequest) -> SharpnessResultKey {
        SharpnessResultKey(
            folderSession: request.locationIdentity, photo: request.primaryURL,
            revision: request.primaryRevision, parametersVersion: parametersVersion)
    }
}

/// The per-job ``RegionSharpnessStageGate``: a token carrying the job's key into the
/// scheduler's stage admission.
private struct SchedulerStageGate: RegionSharpnessStageGate {
    let key: SharpnessResultKey
    let scheduler: RegionSharpnessScheduler

    func enter(_ stage: SharpnessAnalysisStage) async throws {
        try await scheduler.requestStage(stage, of: key)
    }

    func exit(_ stage: SharpnessAnalysisStage) async {
        await scheduler.releaseStage(stage, of: key)
    }
}

extension RegionSharpnessRequest {
    /// The revision a result key uses: the primary file's revision (G1 decision 1's file).
    /// The request's precondition guarantees at least one file exists.
    fileprivate var primaryRevision: ThumbnailRevision {
        if let raw { return raw.revision }
        if let jpeg { return jpeg.revision }
        if let heif { return heif.revision }
        preconditionFailure("An analysis request needs a file")
    }
}
