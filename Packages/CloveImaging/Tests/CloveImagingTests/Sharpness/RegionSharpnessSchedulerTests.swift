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
        var previewAnswers: [String: Result<CGImage, RegionImageFailure>] = [:]
        var highResolutionAnswers: [String: Result<CGImage, RegionImageFailure>] = [:]
        var defaultProperties: ImageProperties?
        var propertiesCount: [String: Int] = [:]
        var previewCount: [String: Int] = [:]
        var highResolutionCount: [String: Int] = [:]
        var activeHighResolution = 0
        var peakHighResolution = 0
        var activePreview = 0
        var peakPreview = 0
    }

    private let preview = SharpnessScene.flat(width: 32, height: 24)
    private let highResolution = SharpnessScene.checkerboard(width: 256, height: 256, cell: 4)

    /// The gate every read parks on: a held kind parks every read of that kind until it is
    /// released. Reference semantics, shared by the reader and the test.
    let reads = ReadGate()

    final class ReadGate: Sendable {
        enum Kind: String, Sendable { case properties, preview, highResolution }
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

    func setHighResolution(failure: RegionImageFailure?, for file: String) {
        lock.withLock {
            if let failure {
                $0.highResolutionAnswers[file] = .failure(failure)
            } else {
                $0.highResolutionAnswers.removeValue(forKey: file)
            }
        }
    }

    func properties(of url: URL) async -> ImageProperties? {
        await reads.waitIfHeld(.properties)
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

    func highResolution(
        _ request: RegionSharpnessRequest
    ) async -> Result<CGImage, RegionImageFailure> {
        // The entry is recorded on arrival, before parking, so a test can see a read is
        // in flight while the gate still holds it.
        let name = request.primaryURL.lastPathComponent
        lock.withLock { state in
            state.highResolutionCount[name, default: 0] += 1
            state.activeHighResolution += 1
            state.peakHighResolution = max(state.peakHighResolution, state.activeHighResolution)
        }
        await reads.waitIfHeld(.highResolution)
        lock.withLock { $0.activeHighResolution -= 1 }
        return lock.withLock { state -> Result<CGImage, RegionImageFailure> in
            if let failure = state.highResolutionAnswers[name] { return failure }
            return .success(highResolution)
        }
    }

    var activeHighResolutionReads: Int { lock.withLock { $0.activeHighResolution } }
    var propertiesCounts: [String: Int] { lock.withLock { $0.propertiesCount } }
    var previewCounts: [String: Int] { lock.withLock { $0.previewCount } }
    var highResolutionCounts: [String: Int] { lock.withLock { $0.highResolutionCount } }
    var peakHighResolution: Int { lock.withLock { $0.peakHighResolution } }
    var peakPreview: Int { lock.withLock { $0.peakPreview } }
}

/// A fake detector whose requests park on an explicit gate and record concurrency.
final class GatedSharpnessDetector: FaceRegionDetecting, @unchecked Sendable {
    private let lock = Mutex(State())
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
                if !parked { continuation.resume() }
            }
            lock.withLock { $0.active -= 1 }
            return lock.withLock { $0.answers["*"] ?? .faces([face]) }
        }
        lock.withLock { $0.active -= 1 }
        return lock.withLock { $0.answers["*"] ?? .faces([face]) }
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
@Suite(.serialized) struct StageGatedAnalysisTests {
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
        reader.reads.release(.highResolution)

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
        reader.reads.release(.highResolution)
        let analyzer = RegionSharpnessAnalyzer(
            reader: reader, faces: GatedSharpnessDetector())
        let analysis = await analyzer.analyze(photoRequest("a"))
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected AF regions")
            return
        }
        #expect(afRegions.first?.score != nil)
        guard case .regions(let faceRegions) = analysis.faces else {
            Issue.record("Expected face regions")
            return
        }
        #expect(faceRegions.allSatisfy { $0.score != nil })
    }

    @Test func earlyAFDeliverySurvivesStageGating() async throws {
        // #215's contract through the gate: the AF callback fires while detection is parked.
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "a.arw")
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        reader.reads.release(.highResolution)
        let detector = GatedSharpnessDetector()
        detector.hold()
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let delivered = Mutex<RegionSharpnessPathResult?>(nil)
        let task = Task {
            await scheduler.analyzeCurrent(photoRequest("a")) { early in
                delivered.withLock { $0 = early }
            }
        }
        // The AF result must arrive while detection is still parked (#215 through the
        // scheduler): wait for the delivery itself, then prove the detector never finished.
        try await until("the AF result is delivered") { delivered.withLock { $0 } != nil }
        let stillParked = detector.parked
        #expect(stillParked >= 1, "AF must be delivered before detection completes")
        let early = delivered.withLock { $0 }
        guard case .regions(let regions) = early else {
            Issue.record("Expected the scored AF region early")
            detector.releaseAll()
            task.cancel()
            return
        }
        #expect(regions.first?.score != nil)
        detector.releaseAll()
        let analysis = try #require(await task.value)
        #expect(analysis.autofocus != nil || analysis.faces != nil)
        await scheduler.close()
    }
}

// MARK: - Priorities, promotion, cancellation

@Suite(.serialized) struct SharpnessSchedulingPriorityTests {
    private func makeScheduler(
        _ reader: GatedSharpnessReader, _ detector: GatedSharpnessDetector,
        scoring: Int = 2
    ) -> RegionSharpnessScheduler {
        RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector),
            detectionWorkers: 1, acquisitionWorkers: 1, scoringWorkers: scoring)
    }

    private func releaseEverything(_ reader: GatedSharpnessReader) {
        for kind in [.properties, .preview, .highResolution] as [GatedSharpnessReader.ReadGate.Kind]
        {
            reader.reads.release(kind)
        }
    }

    @Test func currentPhotoPreemptsQueuedBackgroundWork() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "bg.arw")
        reader.setProperties(afInfoProperties(), for: "now.arw")
        let detector = GatedSharpnessDetector()
        // Park both heavy stages: queued work accumulates, nothing starts.
        detector.hold()
        await reader.reads.hold(.highResolution)
        let scheduler = makeScheduler(reader, detector)

        // One current photo runs; the folder's photos queue behind it.
        let current = Task { await scheduler.analyzeCurrent(photoRequest("now")) }
        try await until("detection parks") { detector.parked >= 1 }
        await scheduler.submit((1...20).map { photoRequest("bg\($0)") }, priority: .folder)
        try await until("background photos queue") {
            await scheduler.snapshot().queuedByPriority[.folder] ?? 0 >= 19
        }

        // The current photo's acquisition runs while twenty folder photos wait: the
        // acquisition budget (1) is held by the current photo, not by background work.
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.stages[.pixelAcquisition]!.active == 1)
        #expect(snapshot.stages[.pixelAcquisition]!.queued == 0)
        // And the detector budget (1) likewise belongs to the current photo.
        #expect(detector.parked == 1)

        releaseEverything(reader)
        detector.releaseAll()
        let analysis = try #require(await current.value)
        guard case .regions(let afRegions) = analysis.autofocus else {
            Issue.record("Expected the current photo's AF regions")
            return
        }
        #expect(afRegions.first?.score != nil)
        await scheduler.close()
    }

    @Test func rapidNavigationLeavesNoObsoleteUrgentBacklog() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        await reader.reads.hold(.highResolution)
        let scheduler = makeScheduler(reader, detector)

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
        // anymore, and their analyses must not stay ranked as current.
        await scheduler.focus(current: photoRequest("p9"))
        let snapshot = await scheduler.snapshot()
        let detection = snapshot.stages[.faceDetection]!
        // One running detection (whoever got the slot) plus queued entries that are no
        // longer urgent — nothing beyond the one slot is running.
        #expect(detection.active <= 1)

        releaseEverything(reader)
        detector.releaseAll()
        for task in tasks { _ = await task.value }
        await scheduler.close()
        // Every rapid-navigation waiter settled; no backlog of active stage entries remains.
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
        // One unit of work: one property read, one preview, one acquisition, one detection.
        #expect(reader.propertiesCounts["shared.arw"] == 1)
        #expect(reader.previewCounts["shared.arw"] == 1)
        #expect(reader.highResolutionCounts["shared.arw"] == 1)
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
        await reader.reads.hold(.highResolution)
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
        await reader.reads.hold(.highResolution)
        let scheduler = makeScheduler(reader, detector)
        await scheduler.submit((0..<10).map { photoRequest("f\($0)") }, priority: .group)
        try await until("group work queues or runs") {
            let snapshot = await scheduler.snapshot()
            return (snapshot.queuedByPriority[.group] ?? 0) >= 1
                || snapshot.stages[.faceDetection]!.active >= 1
        }
        await scheduler.focus(current: photoRequest("elsewhere"), group: [], nearby: [])
        // Everything queued is now folder rank: no group-ranked backlog survives a view
        // change that no longer mentions it.
        try await until("group entry is taken or demoted") {
            let detection = await scheduler.snapshot().stages[.faceDetection]!
            return detection.active <= 1
        }
        releaseEverything(reader)
        detector.releaseAll()
        await scheduler.close()
    }
}

// MARK: - Invalidation and folder changes

@Suite(.serialized) struct SharpnessInvalidationTests {
    @Test func sourceChangeInvalidatesQueuedWorkAndStoredResults() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        await reader.reads.hold(.highResolution)
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
        reader.reads.release(.highResolution)
        try await until("no queued entry survives invalidation") {
            let snapshot = await scheduler.snapshot()
            return snapshot.stages.values.allSatisfy { $0.queued == 0 }
        }
        await scheduler.close()
    }

    @Test func staleAcquisitionIsNotStored() async throws {
        let reader = GatedSharpnessReader()
        reader.setHighResolution(failure: .staleSource, for: "stale.arw")
        reader.setProperties(afInfoProperties(), for: "stale.arw")
        let detector = GatedSharpnessDetector()
        for kind in [.properties, .preview, .highResolution] as [GatedSharpnessReader.ReadGate.Kind]
        {
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
        await reader.reads.hold(.highResolution)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let task = Task { await scheduler.analyzeCurrent(photoRequest("flip", revision: 1)) }
        try await until("the acquisition is held") {
            reader.highResolutionCounts["flip.arw"] ?? 0 >= 1
        }
        // The file changes under the running analysis.
        await scheduler.invalidate(sources: [URL(fileURLWithPath: "/tmp/folder/flip.arw")])
        reader.reads.release(.highResolution)
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

@Suite(.serialized) struct SharpnessBudgetTests {
    @Test func acquisitionAndDetectionBudgetsHoldUnderSyntheticLoad() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        reader.reads.release(.highResolution)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector),
            detectionWorkers: 1, acquisitionWorkers: 1, scoringWorkers: 2)
        // A thousand-photo folder, all at folder rank.
        await scheduler.submit((0..<1000).map { photoRequest("load\($0)") }, priority: .folder)
        // Let a healthy amount of work run; the gates record the concurrency peaks.
        try await until("many photos complete") {
            reader.highResolutionCounts.values.reduce(0, +) >= 40
        }
        await scheduler.close()
        #expect(reader.peakHighResolution <= 1)
        #expect(detector.peakConcurrency <= 1)
        // The compact store never grew beyond its capacity.
        let snapshot = await scheduler.snapshot()
        _ = snapshot
    }

    @Test func queuedJobsNeverHoldPixels() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        detector.hold()
        await reader.reads.hold(.highResolution)
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
        #expect(reader.peakHighResolution <= 1)
        detector.releaseAll()
        reader.reads.release(.highResolution)
        await scheduler.close()
    }

    @Test func pauseStopsAdmittingAndResumeContinues() async throws {
        let reader = GatedSharpnessReader()
        let detector = GatedSharpnessDetector()
        for kind in [.properties, .preview, .highResolution] as [GatedSharpnessReader.ReadGate.Kind]
        {
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
            reader.highResolutionCounts.values.reduce(0, +) >= 1
        }
        await scheduler.close()
    }

    @Test func pauseHoldsAdmissionButAnEnteredReadFinishes() async throws {
        let reader = GatedSharpnessReader()
        reader.setProperties(afInfoProperties(), for: "finishing.arw")
        let detector = GatedSharpnessDetector()
        reader.reads.release(.properties)
        reader.reads.release(.preview)
        await reader.reads.hold(.highResolution)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(reader: reader, faces: detector))
        let running = Task { await scheduler.analyzeCurrent(photoRequest("finishing")) }
        try await until("the acquisition is entered") {
            reader.highResolutionCounts["finishing.arw"] ?? 0 >= 1
        }
        await scheduler.pause()
        // The read that already entered finishes under the pause (#216: an uncancellable
        // entry is never thrown away) — its stage slot is released honestly…
        reader.reads.release(.highResolution)
        try await until("the entered read drains while paused") {
            reader.activeHighResolutionReads == 0
        }
        // …but no further stage of that photo is admitted until resume.
        #expect((await scheduler.snapshot()).paused)
        let scoring = await scheduler.snapshot().stages[.regionScoring]!
        #expect(scoring.startedCount == 0, "scoring waits for resume")
        await scheduler.resume()
        let answer = try #require(await running.value)
        guard case .regions(let afRegions) = answer.autofocus else {
            Issue.record("Expected the finished photo's AF regions after resume")
            return
        }
        #expect(afRegions.first?.score != nil)
        await scheduler.close()
    }
}
