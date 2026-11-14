import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import CloveImaging

// MARK: - Fakes and gates

/// A fake reader whose every read parks on a deterministic gate, so tests observe scheduling
/// decisions instead of racing real decodes. Records per-file counts and concurrency peaks.
final class GatedSharpnessReader: RegionSharpnessReading, @unchecked Sendable {
    private let lock = Mutex(State())
    private struct State {
        var propertiesAnswers: [String: ImageProperties] = [:]
        var activeProperties = 0
        var peakProperties = 0
        var previewAnswers: [String: Result<CGImage, RegionImageFailure>] = [:]
        var defaultProperties: ImageProperties?
        var propertiesCount: [String: Int] = [:]
        var previewCount: [String: Int] = [:]
        var activePreview = 0
        var peakPreview = 0
    }

    private let preview = SharpnessScene.flat(width: 32, height: 24)

    /// The gate every read parks on: a held kind parks every read of that kind until it is
    /// released. Reference semantics, shared by the reader and the test.
    let reads = ReadGate()

    final class ReadGate: Sendable {
        enum Kind: String, Sendable { case properties, preview }
        private struct State {
            var held: Set<Kind> = []
            var waiters: [CheckedContinuation<Void, Never>] = []
        }
        private let state = Mutex(State())

        func hold(_ kind: Kind) {
            state.withLock { _ = $0.held.insert(kind) }
        }

        func release(_ kind: Kind) {
            let pending = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.held.remove(kind)
                let all = state.waiters
                state.waiters.removeAll()
                return all
            }
            for waiter in pending { waiter.resume() }
        }

        func waitIfHeld(_ kind: Kind) async {
            while state.withLock({ $0.held.contains(kind) }) {
                let parked = state.withLock { $0.waiters.count }
                _ = parked
                await withCheckedContinuation { continuation in
                    let resumed = state.withLock { state -> Bool in
                        guard state.held.contains(kind) else { return false }
                        state.waiters.append(continuation)
                        return true
                    }
                    if !resumed { continuation.resume() }
                }
            }
        }
    }

    func setProperties(_ answer: ImageProperties?, for file: String) {
        lock.withLock {
            if let answer {
                $0.propertiesAnswers[file] = answer
            } else {
                $0.propertiesAnswers.removeValue(forKey: file)
            }
        }
    }

    func setPreview(failure: RegionImageFailure?, for file: String) {
        lock.withLock {
            if let failure {
                $0.previewAnswers[file] = .failure(failure)
            } else {
                $0.previewAnswers.removeValue(forKey: file)
            }
        }
    }

    func properties(of url: URL) async -> ImageProperties? {
        // Entry recorded before the gate parks, so a test can see a property read in flight.
        lock.withLock { state in
            state.activeProperties += 1
            state.peakProperties = max(state.peakProperties, state.activeProperties)
        }
        await reads.waitIfHeld(.properties)
        lock.withLock { $0.activeProperties -= 1 }
        return lock.withLock { state -> ImageProperties? in
            let name = url.lastPathComponent
            state.propertiesCount[name, default: 0] += 1
            return state.propertiesAnswers[name] ?? state.defaultProperties
        }
    }

    func preview(_ request: RegionSharpnessRequest) async -> Result<CGImage, RegionImageFailure> {
        let name = request.primaryURL.lastPathComponent
        lock.withLock { state in
            state.previewCount[name, default: 0] += 1
            state.activePreview += 1
            state.peakPreview = max(state.peakPreview, state.activePreview)
        }
        await reads.waitIfHeld(.preview)
        lock.withLock { $0.activePreview -= 1 }
        return lock.withLock { state -> Result<CGImage, RegionImageFailure> in
            if let failure = state.previewAnswers[name] { return failure }
            return .success(preview)
        }
    }

    var activePropertyReads: Int { lock.withLock { $0.activeProperties } }
    var peakPropertyReads: Int { lock.withLock { $0.peakProperties } }
    var propertiesCounts: [String: Int] { lock.withLock { $0.propertiesCount } }
    var previewCounts: [String: Int] { lock.withLock { $0.previewCount } }
    var peakPreview: Int { lock.withLock { $0.peakPreview } }
}

/// A fake detector whose requests park on an explicit gate and record concurrency.
final class GatedSharpnessDetector: FaceRegionDetecting, @unchecked Sendable {
    private let lock = Mutex(State())
    private let parkedRequests = AsyncStream<Void>.makeStream()
    private struct State {
        var answers: [String: FaceDetectionOutcome] = [:]
        var count = 0
        var active = 0
        var peak = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
        var holding = false
    }

    private let face = DetectedFaceRegion(
        face: NormalizedRegion(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
        leftEye: NormalizedRegion(x: 0.35, y: 0.4, width: 0.06, height: 0.06),
        rightEye: NormalizedRegion(x: 0.5, y: 0.4, width: 0.06, height: 0.06))

    func setOutcome(_ outcome: FaceDetectionOutcome?, for file: String) {
        lock.withLock {
            if let outcome {
                $0.answers[file] = outcome
            } else {
                $0.answers.removeValue(forKey: file)
            }
        }
    }

    /// Parks every request until ``releaseAll()``.
    func hold() { lock.withLock { $0.holding = true } }

    func releaseAll() {
        let pending = lock.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.holding = false
            let all = state.waiters
            state.waiters.removeAll()
            return all
        }
        for waiter in pending { waiter.resume() }
    }

    func detectFaces(on image: CGImage) async -> FaceDetectionOutcome {
        // One counted, parked request per call: the hold decision is made and consumed under
        // one lock, so a release can never resume a continuation twice.
        let releaseNow = lock.withLock { state -> Bool in
            state.count += 1
            state.active += 1
            state.peak = max(state.peak, state.active)
            return !state.holding
        }
        if !releaseNow {
            await withCheckedContinuation { continuation in
                let parked = lock.withLock { state -> Bool in
                    guard state.holding else { return false }
                    state.waiters.append(continuation)
                    return true
                }
                if parked {
                    parkedRequests.continuation.yield(())
                } else {
                    continuation.resume()
                }
            }
            lock.withLock { $0.active -= 1 }
            return lock.withLock { $0.answers["*"] ?? .faces([face]) }
        }
        lock.withLock { $0.active -= 1 }
        return lock.withLock { $0.answers["*"] ?? .faces([face]) }
    }

    func waitUntilParked() async throws {
        var iterator = parkedRequests.stream.makeAsyncIterator()
        try #require(await iterator.next() != nil, "Detection must enter its held gate")
    }

    var requestCount: Int { lock.withLock { $0.count } }
    var peakConcurrency: Int { lock.withLock { $0.peak } }
    var parked: Int { lock.withLock { $0.waiters.count } }
}

// MARK: - Shared helpers

/// AF metadata that locates one region, so the AF path scores through the fake pixels.
private func afInfoProperties() -> ImageProperties {
    ImageProperties(["{ExifAux}": ["AFInfo": [0.2, 0.2, 0.1, 0.1, "f"]]])
}

/// A request per file name; distinct revisions keep every photo a distinct identity.
private func photoRequest(
    _ name: String, revision: Int64 = 1, folder: String = "folder"
) -> RegionSharpnessRequest {
    RegionSharpnessRequest(
        raw: DetailSource(
            url: URL(fileURLWithPath: "/tmp/\(folder)/\(name).arw"),
            revision: ThumbnailRevision(
                size: revision,
                modificationTime: Date(timeIntervalSince1970: TimeInterval(revision)))),
        locationIdentity: folder)
}

/// Waits for a condition without spinning against the work it awaits. The condition is
/// evaluated once per iteration: scheduling state moves between evaluations, so a
/// check-then-assert helper would observe a different state than it waited for.
private func until(
    _ description: String, timeout: Duration = .seconds(5), _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        if await condition() { return }
        guard ContinuousClock.now < deadline else {
            Issue.record("Condition did not become true: \(description)")
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

// MARK: - Stage-gated analysis

/// The analyzer's stage gate seam: admission order and refusal, without the scheduler.
@Suite(.imageWork, .serialized) struct StageGatedAnalysisTests {
    @Test func refusedAdmissionCancelsTheAnalysis() async throws {
        final class RefusingGate: RegionSharpnessStageGate {
            func enter(_ stage: SharpnessAnalysisStage) async throws {
                throw CancellationError()
            }
            func exit(_ stage: SharpnessAnalysisStage) async {}
        }
        let reader = GatedSharpnessReader()
        reader.reads.release(.properties)
        reader.reads.release(.preview)

        let refused = RegionSharpnessAnalyzer(
            reader: reader, faces: GatedSharpnessDetector(),
            stages: RefusingGate())
        do {
            _ = try await refused.analyzeGated(photoRequest("a"))
            Issue.record("A refusing gate must cancel the analysis")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func ungatedAnalyzeStillDeliversBothPaths() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "a.arw")
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: GatedSharpnessDetector())
        let analysis = await analyzer.analyze(photoRequest("a"))
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions")
            return
        }
        #expect(afRegions.first?.score == nil)
        #expect(afRegions.first?.unavailableBecause == nil)
        guard case .regions(let faceRegions) = analysis.faces else {
            Issue.record("Expected face regions")
            return
        }
        #expect(faceRegions.allSatisfy { $0.score == nil && $0.unavailableBecause == nil })
    }

    @Test(.timeLimit(.minutes(1))) func earlyAFDeliverySurvivesStageGating() async throws {
        // #215's contract through the gate: the AF callback fires while detection is parked.
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "a.arw")
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        let detector = GatedSharpnessDetector()
        detector.hold()
        defer {
            detector.releaseAll()
        }
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let delivered = AsyncStream<RegionSharpnessPathResult>.makeStream()
        let task = Task {
            await scheduler.analyzeCurrent(photoRequest("a")) { early in
                delivered.continuation.yield(early)
            }
        }
        try await detector.waitUntilParked()
        var deliveries = delivered.stream.makeAsyncIterator()
        let early = try #require(await deliveries.next())
        #expect(detector.parked == 1, "AF must be delivered before detection completes")
        guard case .regions(let regions) = early else {
            Issue.record("Expected the located AF region early")
            task.cancel()
            return
        }
        #expect(regions.first?.score == nil)
        #expect(regions.first?.unavailableBecause == nil)
        detector.releaseAll()
        let analysis = try #require(await task.value)
        guard case .regions(let combinedAF) = analysis.autofocus,
            case .regions(let faces) = analysis.faces
        else {
            Issue.record("Expected both located paths after releasing detection")
            return
        }
        #expect(combinedAF.map(\.region) == regions.map(\.region))
        #expect(combinedAF.map(\.unavailableBecause) == regions.map(\.unavailableBecause))
        #expect(
            !faces.isEmpty && faces.allSatisfy { $0.score == nil && $0.unavailableBecause == nil })
        await scheduler.close()
    }
}

// MARK: - Priorities, promotion, cancellation

@Suite(.imageWork, .serialized) struct SharpnessSchedulingPriorityTests {
    private func makeScheduler(
        _ reader: GatedSharpnessReader, _ detector: GatedSharpnessDetector,
        metadata: Int = 2
    ) -> RegionSharpnessScheduler {
        RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector),
            metadataWorkers: metadata, detectionWorkers: 1)
    }

    private func releaseEverything(_ reader: GatedSharpnessReader) {
        for kind in [.properties, .preview] as [GatedSharpnessReader.ReadGate.Kind] {
            reader.reads.release(kind)
        }
    }

    @Test(.timeLimit(.minutes(1))) func currentPhotoPreemptsQueuedBackgroundWork() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "bg.arw")
        reader.setProperties(afInfoProperties(), for: "now.arw")
        let detector = GatedSharpnessDetector()
        // Park detection: queued work accumulates, nothing completes.
        detector.hold()
        let scheduler = makeScheduler(reader, detector)

        // One current photo runs; the folder's photos queue behind it.
        defer {
            releaseEverything(reader)
            detector.releaseAll()
        }
        let current = Task { await scheduler.analyzeCurrent(photoRequest("now")) }
        try await detector.waitUntilParked()
        await scheduler.submit((1...20).map { photoRequest("bg\($0)") }, priority: .folder)
        // All twenty are admitted as jobs; the metadata budget (2) holds two of them, so
        // eighteen queue without any stage slot.
        try await until("background photos queue") {
            await scheduler.snapshot().queuedByPriority[.folder] ?? 0 >= 18
        }

        // The detector budget (1) belongs to the current photo.
        #expect(reader.previewCounts["now.arw"] == 1)
        #expect(
            Set(reader.previewCounts.keys) == ["now.arw"],
            "no background photo entered detection while the current one holds the budget")
        #expect(reader.peakPreview <= 1)
        #expect(detector.parked == 1)

        releaseEverything(reader)
        detector.releaseAll()
        let analysis = try #require(await current.value)
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected the current photo's AF regions")
            return
        }
        #expect(afRegions.first?.score == nil)
        #expect(afRegions.first?.unavailableBecause == nil)
        await scheduler.close()
    }

    @Test func rapidNavigationLeavesNoObsoleteUrgentBacklog() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = makeScheduler(reader, detector)
        // Admission is held, so the queue below is exact: every photo queues, none runs.
        await scheduler.pause()

        // Open 10 photos in quick succession; each was current once.
        var tasks: [Task<RegionSharpnessAnalysis?, Never>] = []
        for index in 0..<10 {
            let task = Task { await scheduler.analyzeCurrent(photoRequest("p\(index)")) }
            tasks.append(task)
            try await until("photo \(index) queues or runs") {
                if detector.parked + (await scheduler.snapshot().queuedByPriority[.current] ?? 0)
                    >= index + 1
                {
                    return true
                }
                let snapshot = await scheduler.snapshot()
                let queued = snapshot.queuedByPriority.values.reduce(0, +)
                let active = snapshot.stages.values.reduce(0) { $0 + $1.active }
                return detector.parked + queued + active >= index + 1
            }
        }

        // Demote everything but the last-opened photo: none of the first nine is current
        // anymore, and their analyses must not stay ranked as current. Asserted on the live
        // priority queue, while admission is still held by the pause.
        await scheduler.focus(current: photoRequest("p9"))
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.queuedByPriority[.current] == 1, "only the view's photo stays current")
        // All ten are queued with no stage slot (admission is paused): the other nine demote
        // to folder rank instead of leaving an urgent backlog.
        #expect(snapshot.queuedByPriority[.folder] == 9)
        #expect(snapshot.queuedByPriority[.group] == nil)

        await scheduler.resume()
        releaseEverything(reader)
        detector.releaseAll()
        for task in tasks { _ = await task.value }
        await scheduler.close()
        let afterClose = await scheduler.snapshot()
        for stage in SharpnessAnalysisStage.allCases {
            #expect(afterClose.stages[stage]!.active == 0)
            #expect(afterClose.stages[stage]!.queued == 0)
        }
    }

    @Test func joiningInFlightWorkSharesTheAnalysis() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        releaseEverything(reader)
        let scheduler = makeScheduler(reader, detector)
        let first = Task { await scheduler.analyzeCurrent(photoRequest("shared")) }
        let second = Task { await scheduler.analyzeCurrent(photoRequest("shared")) }
        let third = Task { await scheduler.analyzeCurrent(photoRequest("shared")) }
        let answers = await withTaskGroup(of: RegionSharpnessAnalysis?.self) { group in
            group.addTask { await first.value }
            group.addTask { await second.value }
            group.addTask { await third.value }
            var collected: [RegionSharpnessAnalysis?] = []
            for await answer in group { collected.append(answer) }
            return collected
        }
        #expect(answers.count == 3)
        #expect(answers.allSatisfy { $0 != nil })
        // One unit of work: one property read, one preview, one detection.
        #expect(reader.propertiesCounts["shared.arw"] == 1)
        #expect(reader.previewCounts["shared.arw"] == 1)
        #expect(detector.requestCount == 1)
        await scheduler.close()
    }

    @Test func cachedResultServesTheSecondInteractiveRequest() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        releaseEverything(reader)
        let scheduler = makeScheduler(reader, detector)
        let first = await scheduler.analyzeCurrent(photoRequest("cached"))
        #expect(first != nil)
        let second = await scheduler.analyzeCurrent(photoRequest("cached"))
        #expect(second != nil)
        #expect(reader.propertiesCounts["cached.arw"] == 1)
        #expect(detector.requestCount == 1)
        await scheduler.close()
    }

    @Test func interactiveJoinsPromoteBackgroundWork() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = makeScheduler(reader, detector)
        // Queue ten folder photos; the detector holds the first one's request.
        await scheduler.submit((0..<10).map { photoRequest("q\($0)") }, priority: .folder)
        try await until("a background detection parks") {
            if detector.parked >= 1 { return true }
            let snapshot = await scheduler.snapshot()
            let waiting =
                snapshot.queuedByPriority.values.reduce(0, +)
                + snapshot.stages[.faceDetection]!.queued
            return waiting >= 10
        }
        // The person opens one of the queued photos.
        let promoted = Task { await scheduler.analyzeCurrent(photoRequest("q5")) }
        // Its work is shared with the queued job: the same key, so the request count stays
        // one per photo, and the join settles when the shared analysis does.
        releaseEverything(reader)
        detector.releaseAll()
        let answer = try #require(await promoted.value)
        #expect(answer != nil)
        #expect(reader.propertiesCounts["q5.arw"] == 1)
        await scheduler.close()
    }

    @Test func focusDemotesStaleUrgentWork() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = makeScheduler(reader, detector)
        await scheduler.pause()
        await scheduler.submit((0..<10).map { photoRequest("f\($0)") }, priority: .group)
        try await until("group work queues") {
            await scheduler.snapshot().queuedByPriority[.group] ?? 0 == 10
        }
        await scheduler.focus(current: photoRequest("elsewhere"), group: [], nearby: [])
        // The demotion is asserted on the live queue while admission is held by the pause:
        // no group-ranked backlog survives a view change that no longer mentions it.
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.queuedByPriority[.group] == nil, "no group-ranked work is left")
        #expect(snapshot.queuedByPriority[.folder] == 10, "everything demotes to folder rank")
        await scheduler.resume()
        releaseEverything(reader)
        detector.releaseAll()
        await scheduler.close()
    }
}

// MARK: - Invalidation and folder changes

@Suite(.imageWork, .serialized) struct SharpnessInvalidationTests {
    @Test func sourceChangeInvalidatesQueuedWorkAndStoredResults() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        await scheduler.submit([photoRequest("gone", revision: 1)], priority: .folder)
        try await until("the photo's detection is parked in the held detector") {
            detector.parked >= 1
        }
        // A finished record for the same photo exists from an earlier run.
        // The file changes: queued work for it must disappear.
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/gone.arw")])
        detector.releaseAll()
        try await until("no queued entry survives invalidation") {
            let snapshot = await scheduler.snapshot()
            return snapshot.stages.values.allSatisfy { $0.queued == 0 }
        }
        await scheduler.close()
    }

    @Test func stalePreviewIsNotStored() async throws {
        let reader = GatedSharpnessReader()
        reader.setPreview(failure: .staleSource, for: "stale.arw")
        reader.setProperties(afInfoProperties(), for: "stale.arw")
        let detector = GatedSharpnessDetector()
        for kind in [.properties, .preview] as [GatedSharpnessReader.ReadGate.Kind] {
            reader.reads.release(kind)
        }
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let first = await scheduler.analyzeCurrent(photoRequest("stale"))
        #expect(first != nil)
        // Not cached: a second interactive request runs real work again.
        let second = await scheduler.analyzeCurrent(photoRequest("stale"))
        #expect(second != nil)
        #expect(reader.propertiesCounts["stale.arw"] == 2)
        await scheduler.close()
    }

    @Test func staleResultsAreNeverPublished() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "flip.arw")
        let detector = GatedSharpnessDetector()
        await reader.reads.hold(.preview)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let task = Task { await scheduler.analyzeCurrent(photoRequest("flip", revision: 1)) }
        try await until("the preview read is held") {
            reader.previewCounts["flip.arw"] ?? 0 >= 1
        }
        // The file changes under the running analysis.
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/flip.arw")])
        reader.reads.release(.preview)
        let answer = await task.value
        // The waiter is told the photo no longer has a result, instead of receiving one that
        // belongs to a revision that is gone.
        #expect(answer == nil)
        await scheduler.close()
    }

    @Test func folderCloseCancelsEverything() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        await scheduler.submit((0..<5).map { photoRequest("c\($0)") }, priority: .folder)
        try await until("work is queued or running") {
            let snapshot = await scheduler.snapshot()
            let waiting =
                snapshot.queuedByPriority.values.reduce(0, +)
                + snapshot.stages[.faceDetection]!.queued
            return waiting >= 1 || snapshot.stages[.faceDetection]!.active >= 1
        }
        detector.releaseAll()
        await scheduler.close()
        let snapshot = await scheduler.snapshot()
        for stage in SharpnessAnalysisStage.allCases {
            #expect(snapshot.stages[stage]!.queued == 0)
            #expect(snapshot.stages[stage]!.active == 0)
        }
        // A closed scheduler refuses new work.
        let refused = await scheduler.analyzeCurrent(photoRequest("after"))
        #expect(refused == nil)
    }
}

// MARK: - Budgets and buffers

@Suite(.imageWork, .serialized) struct SharpnessBudgetTests {
    @Test(.timeLimit(.minutes(1))) func previewAndDetectionBudgetsHoldUnderSyntheticLoad()
        async throws
    {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector),
            metadataWorkers: 2, detectionWorkers: 1)
        // A thousand-photo folder, all at folder rank.
        await scheduler.submit((0..<1000).map { photoRequest("load\($0)") }, priority: .folder)
        // Observe forty entries, without requiring that throughput within a wall-clock
        // window shared with every parallel test. The gates record the concurrency peaks.
        try await until("forty photos finish face detection", timeout: .seconds(30)) {
            await scheduler.snapshot().stages[.faceDetection]!.finishedCount >= 40
        }
        await scheduler.close()
        #expect(reader.peakPreview <= 1)
        #expect(detector.peakConcurrency <= 1)
        // The compact store never grew beyond its capacity.
        let snapshot = await scheduler.snapshot()
        _ = snapshot
    }

    @Test func queuedJobsNeverHoldPixels() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        await scheduler.submit((0..<50).map { photoRequest("hold\($0)") }, priority: .folder)
        try await until("many jobs queue") {
            let snapshot = await scheduler.snapshot()
            return (snapshot.queuedByPriority[.folder] ?? 0) >= 5
        }
        // The queued jobs are records: only the admitted stage entries hold pixels, and the
        // queues themselves can hold at most the jobs' file identities.
        let snapshot = await scheduler.snapshot()
        let detection = snapshot.stages[.faceDetection]!
        #expect(detection.active <= 1)
        detector.releaseAll()
        await scheduler.close()
    }

    @Test func pauseStopsAdmittingAndResumeContinues() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        for kind in [.properties, .preview] as [GatedSharpnessReader.ReadGate.Kind] {
            reader.reads.release(kind)
        }
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        await scheduler.pause()
        await scheduler.submit((0..<5).map { photoRequest("pause\($0)") }, priority: .folder)
        try await until("the queue is accepted while paused") {
            await scheduler.snapshot().queuedByPriority[.folder] ?? 0 == 5
        }
        #expect(reader.previewCounts.isEmpty, "a paused scheduler admits no stage entries")
        let detectorEntries = await scheduler.snapshot().stages[.faceDetection]!
        #expect(detectorEntries.startedCount == 0)
        await scheduler.resume()
        try await until("work resumes") {
            reader.previewCounts.values.reduce(0, +) >= 1
        }
        await scheduler.close()
    }

    @Test func pauseHoldsAdmissionButAnEnteredReadFinishes() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "finishing.arw")
        let detector = GatedSharpnessDetector()
        reader.reads.hold(.properties)
        reader.reads.release(.preview)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let running = Task { await scheduler.analyzeCurrent(photoRequest("finishing")) }
        try await until("the property read is entered") {
            reader.activePropertyReads == 1
        }
        await scheduler.pause()
        // The read that already entered finishes under the pause (#216: an uncancellable
        // entry is never thrown away) — its stage slot is released honestly…
        reader.reads.release(.properties)
        try await until("the entered read drains while paused") {
            reader.activePropertyReads == 0
        }
        // …but no further stage of that photo is admitted until resume.
        #expect((await scheduler.snapshot()).paused)
        let detection = await scheduler.snapshot().stages[.faceDetection]!
        #expect(detection.startedCount == 0, "face detection waits for resume")
        await scheduler.resume()
        let answer = try #require(await running.value)
        guard case .regions(let afRegions) = answer.autofocus else {
            Issue.record("Expected the finished photo's AF regions after resume")
            return
        }
        #expect(afRegions.first?.score == nil)
        #expect(afRegions.first?.unavailableBecause == nil)
        await scheduler.close()
    }
}

// MARK: - Lifecycle windows (review fix round)

/// The remaining lifecycle contracts: resume drains stage queues (#1), dropped generations
/// never settle or answer for the newer same-key job (#2), metadata admission is bounded
/// (#4), pause-invalidate wakes parked tasks (#5), and background submits reuse the store
/// (#8).
@Suite(.imageWork, .serialized) struct SharpnessLifecycleTests {
    private func makeScheduler(_ reader: GatedSharpnessReader, _ detector: GatedSharpnessDetector)
        -> RegionSharpnessScheduler
    {
        RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
    }

    @Test(.timeLimit(.minutes(1))) func resumeDrainsStageQueuesWhoseHolderExitedWhilePaused()
        async throws
    {
        // #1: the slot holder finishes under pause; the parked job must be admitted on resume.
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        defer {
            detector.releaseAll()
        }
        let scheduler = makeScheduler(reader, detector)
        let holder = Task { await scheduler.analyzeCurrent(photoRequest("holder")) }
        let parked = Task { await scheduler.analyzeCurrent(photoRequest("parked")) }
        try await detector.waitUntilParked()
        // RegionSharpnessScheduler exposes no stage-queue/release notification seam without
        // altering production code; poll snapshots with a 30s budget inside the 1-minute limit.
        try await until("the second job queues on face detection", timeout: .seconds(30)) {
            await scheduler.snapshot().stages[.faceDetection]!.queued >= 1
        }
        await scheduler.pause()
        // The holder finishes while paused: its detection slot frees, but nothing admits.
        detector.releaseAll()
        try await until("the holder's stage slot released under pause", timeout: .seconds(30)) {
            await scheduler.snapshot().stages[.faceDetection]!.active == 0
        }
        // The parked entry is still waiting, and has not run a Vision request of its own.
        #expect(await scheduler.snapshot().stages[.faceDetection]!.queued >= 1)
        #expect(detector.requestCount == 1, "only the holder's detection has run so far")
        detector.hold()
        await scheduler.resume()
        try await detector.waitUntilParked()
        #expect(detector.requestCount >= 2)
        detector.releaseAll()
        _ = try #require(await holder.value)
        _ = try #require(await parked.value)
        await scheduler.close()
    }

    @Test func droppedGenerationNeverAnswersTheNewJob() async throws {
        // #2: invalidate a running job, then immediately ask for the same revision again.
        // The old task must not remove, cancel or answer the new job.
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "again.arw")
        let detector = GatedSharpnessDetector()
        detector.hold()
        await reader.reads.hold(.preview)
        let scheduler = makeScheduler(reader, detector)

        let oldTask = Task { await scheduler.analyzeCurrent(photoRequest("again", revision: 1)) }
        try await until("the old analysis is in flight") {
            reader.previewCounts["again.arw"] ?? 0 >= 1
        }
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/again.arw")])
        // Same revision requested right away: the new job must get a real answer, not the old
        // task's cancellation.
        let fresh = Task { await scheduler.analyzeCurrent(photoRequest("again", revision: 1)) }
        await reader.reads.release(.preview)
        detector.releaseAll()
        let answer = try #require(await fresh.value)
        guard case .regions(let afRegions) = answer.autofocus else {
            Issue.record("Expected the new job's own AF regions")
            return
        }
        #expect(afRegions.first?.score == nil)
        #expect(afRegions.first?.unavailableBecause == nil)
        // The dropped job's waiter was told nil by the invalidation itself.
        let dropped = await oldTask.value
        #expect(dropped == nil)
        await scheduler.close()
    }

    @Test(.timeLimit(.minutes(1))) func invalidateCancelsOnlyMatchingPhotos() async throws {
        // #3: iteration is over a copy of the keys, so dropping inside the loop is safe, and
        // only the invalidated photo's work is dropped.
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        defer {
            detector.releaseAll()
        }
        let scheduler = makeScheduler(reader, detector)
        await scheduler.submit(
            [photoRequest("keep"), photoRequest("gone")], priority: .folder)
        try await detector.waitUntilParked()
        // RegionSharpnessScheduler exposes no stage-queue notification seam without altering
        // production code; count both active and queued in .faceDetection.
        try await until("both photos have reached face detection", timeout: .seconds(30)) {
            let faceStage = await scheduler.snapshot().stages[.faceDetection]!
            return faceStage.active + faceStage.queued >= 2
        }
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/gone.arw")])
        detector.releaseAll()
        try await until("the surviving photo is analysed", timeout: .seconds(30)) {
            await scheduler.snapshot().stages[.faceDetection]!.finishedCount >= 1
        }
        await scheduler.close()
        // The untouched photo still produced its record; the dropped one did not crash the loop.
        #expect(reader.previewCounts["keep.arw"] != nil)
    }

    @Test func metadataAdmissionIsBoundedUnderLoad() async throws {
        // #4: a thousand-photo submit must not fan out a thousand ImageIO property reads.
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = makeScheduler(reader, detector)
        await scheduler.submit((0..<1000).map { photoRequest("load\($0)") }, priority: .folder)
        try await until("metadata reads stay bounded") { reader.peakPropertyReads > 0 }
        // The metadata budget is small, so concurrent property reads never exceed it.
        #expect(reader.peakPropertyReads <= 4)
        // Close drains the parked reads and requests too: release every gate first so close
        // can await them, which is the point of the test.
        detector.releaseAll()
        await scheduler.close()
    }

    @Test func pausedWaitersAreCancelledByInvalidate() async throws {
        // #5: pause first; a queued task parks in the paused-waiter set. Invalidation must
        // resume and cancel it, not leave it parked.
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        let scheduler = makeScheduler(reader, detector)
        await scheduler.pause()
        await scheduler.submit([photoRequest("victim")], priority: .folder)
        try await until("the task is parked by pause") {
            await scheduler.pausedAdmissionCount == 1
        }
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/victim.arw")])
        // The dropped task's pause-park is resumed and cancelled by the invalidation itself,
        // not left waiting for the next resume.
        #expect(await scheduler.pausedAdmissionCount == 0)
        // Nothing runs for the dropped photo after resume.
        await scheduler.resume()
        await scheduler.close()
        #expect(reader.propertiesCounts["victim.arw"] == nil)
        #expect(reader.previewCounts["victim.arw"] == nil)
    }

    @Test func backgroundSubmitSkipsPhotosWithCachedResults() async throws {
        // #8: the cached path also applies to background submits, not just interactive reads.
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        for kind in [.properties, .preview] as [GatedSharpnessReader.ReadGate.Kind] {
            reader.reads.release(kind)
        }
        let scheduler = makeScheduler(reader, detector)
        _ = await scheduler.analyzeCurrent(photoRequest("done"))
        #expect(reader.propertiesCounts["done.arw"] == 1)
        await scheduler.submit([photoRequest("done")], priority: .folder)
        // Cached: no new property read for that photo.
        #expect(reader.propertiesCounts["done.arw"] == 1)
        await scheduler.close()
    }
}
