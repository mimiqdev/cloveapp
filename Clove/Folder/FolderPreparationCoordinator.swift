import CloveCore
import CloveImaging
import Foundation

@MainActor
final class FolderPreparationCoordinator {
    private static let previewConcurrency = 2
    private static let analysisWindowSize = 4
    private static let cacheInspectionBatchSize = 64

    private let folder: FolderIdentity
    private let generation: Int
    private let session: FolderAccessSession
    private let thumbnailCache: ThumbnailCache?
    private let thumbnailPipeline: ThumbnailPipeline?
    private let regionScheduler: RegionSharpnessScheduler?
    private let publish: @MainActor (FolderPreparationStatus) -> Void

    private var accountant: FolderPreparationAccountant
    private var lastPublishedStatus: FolderPreparationStatus?
    private var publishDebounceTask: Task<Void, Never>?

    private var isClosed = false
    private var hasFinishedScan = false
    private var isPausedForMemoryPressure = false
    private var locationLossReason: FolderLocationLoss.Reason?

    private var thumbnailObserverToken: UUID?
    private var schedulerEventsTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?

    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var analysisSettlementWaiters: [CheckedContinuation<Void, Never>] = []
    private var inFlightAnalysisKeys: Set<SharpnessResultKey> = []
    private var pendingAnalysisRefresh = false

    init(
        folder: FolderIdentity,
        folderName: String,
        generation: Int,
        session: FolderAccessSession,
        thumbnailCache: ThumbnailCache?,
        thumbnailPipeline: ThumbnailPipeline?,
        regionScheduler: RegionSharpnessScheduler?,
        publish: @escaping @MainActor (FolderPreparationStatus) -> Void
    ) {
        self.folder = folder
        self.generation = generation
        self.session = session
        self.thumbnailCache = thumbnailCache
        self.thumbnailPipeline = thumbnailPipeline
        self.regionScheduler = regionScheduler
        self.publish = publish
        let parametersVersion = regionScheduler?.parametersVersion ?? 2
        self.accountant = FolderPreparationAccountant(
            folder: folder,
            folderName: folderName,
            generation: generation,
            parametersVersion: parametersVersion)
    }

    var currentStatus: FolderPreparationStatus {
        accountant.status
    }

    func start() {
        guard !isClosed else { return }
        attachObservers()
        emitStatus(immediate: true)
    }

    func registerDiscovered(_ sets: [ScannedPhotoSet], generation: Int) {
        guard !isClosed, generation == self.generation, !sets.isEmpty else { return }
        accountant.registerDiscovered(sets)
        checkSynchronousThumbnailHits(for: sets)
        emitStatus(immediate: true)
    }

    func finishScan(isPartial: Bool, generation: Int) {
        guard !isClosed, generation == self.generation else { return }
        hasFinishedScan = true
        accountant.finishScan(isPartial: isPartial)
        emitStatus(immediate: true)
        restartPreparationIfNeeded()
    }

    func removePhotos(_ identities: Set<PhotoIdentity>) {
        guard !isClosed, !identities.isEmpty else { return }
        accountant.removePhotos(identities)
        emitStatus(immediate: true)
    }

    func restorePhotos(_ sets: [ScannedPhotoSet]) {
        guard !isClosed, !sets.isEmpty else { return }
        accountant.registerDiscovered(sets)
        checkSynchronousThumbnailHits(for: sets)
        emitStatus(immediate: true)
        if hasFinishedScan {
            restartPreparationIfNeeded()
        }
    }

    func setMemoryPressurePaused(_ paused: Bool) {
        guard !isClosed else { return }
        guard isPausedForMemoryPressure != paused else { return }
        isPausedForMemoryPressure = paused
        updateWaitingReason()
        emitStatus(immediate: true)
        if !paused {
            resumePauseWaiters()
            if hasFinishedScan {
                restartPreparationIfNeeded()
            }
        }
    }

    func markLocationLost(_ reason: FolderLocationLoss.Reason) {
        guard !isClosed else { return }
        locationLossReason = reason
        updateWaitingReason()
        cancelBackgroundWork()
        inFlightAnalysisKeys.removeAll()
        resumeAllWaiters()
        emitStatus(immediate: true)
    }

    func retryIssues() async {
        guard !isClosed,
            locationLossReason == nil,
            !isPausedForMemoryPressure
        else { return }
        let targets = accountant.retryableTargets()
        guard targets.hasWork else { return }
        if !targets.previewURLs.isEmpty {
            thumbnailCache?.invalidateMemory(sources: targets.previewURLs)
        }
        if !targets.analysisRequests.isEmpty, let regionScheduler {
            for request in targets.analysisRequests {
                inFlightAnalysisKeys.remove(regionScheduler.resultKey(for: request))
            }
            await regionScheduler.discardResults(for: targets.analysisRequests)
        }
        guard !isClosed,
            locationLossReason == nil,
            !isPausedForMemoryPressure
        else { return }
        let retried = accountant.retryIssues()
        guard !retried.isEmpty else { return }
        emitStatus(immediate: true)
        resumeAnalysisSettlementWaiters()
        if hasFinishedScan {
            restartPreparationIfNeeded()
        }
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        publishDebounceTask?.cancel()
        publishDebounceTask = nil
        if let token = thumbnailObserverToken {
            thumbnailObserverToken = nil
            thumbnailCache?.removeStoreObserver(token)
        }
        schedulerEventsTask?.cancel()
        preparationTask?.cancel()
        inFlightAnalysisKeys.removeAll()
        resumeAllWaiters()
        await schedulerEventsTask?.value
        await preparationTask?.value
        schedulerEventsTask = nil
        preparationTask = nil
    }

    // MARK: - Observers

    private func attachObservers() {
        if let thumbnailCache {
            let folderID = folder
            let targetPixels = PipelineGridThumbnails.targetPixels
            thumbnailObserverToken = thumbnailCache.addStoreObserver {
                [weak self] request, outcome in
                guard request.locationIdentity == folderID.rawValue,
                    request.targetPixels == targetPixels
                else { return }
                Task { @MainActor [weak self] in
                    self?.handleThumbnailStored(request: request, outcome: outcome)
                }
            }
        }
        if let regionScheduler {
            schedulerEventsTask = Task { @MainActor [weak self] in
                let stream = await regionScheduler.events()
                for await event in stream {
                    guard let self, !self.isClosed, !Task.isCancelled else { return }
                    switch event {
                    case .settled(let key, let request, let analysis):
                        self.handleAnalysisSettled(key: key, request: request, analysis: analysis)
                    case .invalidated(let sources):
                        self.handleInvalidated(sources: sources)
                    }
                }
            }
        }
    }

    private func handleThumbnailStored(
        request: ThumbnailRequest, outcome: ThumbnailCachedOutcome
    ) {
        guard !isClosed else { return }
        let classification = FolderPreparationClassification.classifyPreviewOutcome(outcome)
        if accountant.recordPreviewOutcome(classification, for: request) {
            emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
        }
    }

    private func handleAnalysisSettled(
        key: SharpnessResultKey,
        request: RegionSharpnessRequest,
        analysis: RegionSharpnessAnalysis?
    ) {
        guard !isClosed else { return }
        inFlightAnalysisKeys.remove(key)
        let changed = accountant.recordAnalysisSettlement(
            key: key, request: request, analysis: analysis)
        if changed {
            emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
        }
        resumeAnalysisSettlementWaiters()
    }

    private func handleInvalidated(sources: [URL]) {
        guard !isClosed else { return }
        let invalidatedIDs = accountant.invalidate(sources: sources)
        guard !invalidatedIDs.isEmpty else { return }
        pendingAnalysisRefresh = true
        inFlightAnalysisKeys.removeAll()
        emitStatus(immediate: true)
        resumeAnalysisSettlementWaiters()
        if hasFinishedScan {
            restartPreparationIfNeeded()
        }
    }

    // MARK: - Cache inspection & background preparation

    private func restartPreparationIfNeeded() {
        guard !isClosed, locationLossReason == nil, hasFinishedScan else { return }
        guard preparationTask == nil else {
            resumeAnalysisSettlementWaiters()
            return
        }
        preparationTask = Task { @MainActor [weak self] in
            await self?.runPreparation()
        }
    }

    private func runPreparation() async {
        defer { preparationTask = nil }
        guard !isClosed, !Task.isCancelled, locationLossReason == nil else { return }

        await inspectInitialCaches()

        while !isClosed, !Task.isCancelled, locationLossReason == nil,
            accountant.hasPendingWork
        {
            if isPausedForMemoryPressure {
                await waitWhilePaused()
                continue
            }
            let canRunPreviews = thumbnailPipeline != nil
            let canRunAnalysis = regionScheduler != nil
            guard canRunPreviews || canRunAnalysis else { break }

            async let previewWork: Void = canRunPreviews ? runPreviewLoop() : ()
            async let analysisWork: Void = canRunAnalysis ? runAnalysisLoop() : ()
            _ = await (previewWork, analysisWork)
        }
        emitStatus(immediate: true)
    }

    private func inspectInitialCaches() async {
        // Check all known thumbnail requests synchronously without decoding or mutating LRU.
        if let thumbnailCache {
            for (photo, request) in accountant.thumbnailCheckRequests() {
                guard !isClosed, !Task.isCancelled else { return }
                if let cached = thumbnailCache.cachedOutcome(for: request) {
                    _ = accountant.recordPreviewClassification(
                        FolderPreparationClassification.classifyPreviewOutcome(cached), for: photo)
                }
            }
            emitStatus(immediate: false)
        }

        // Check revision-valid sharpness cache hits in bounded batches without promoting LRU.
        if let regionScheduler {
            let checks = accountant.analysisCheckRequests()
            var index = 0
            while index < checks.count {
                guard !isClosed, !Task.isCancelled, locationLossReason == nil else { return }
                let end = min(index + Self.cacheInspectionBatchSize, checks.count)
                let slice = Array(checks[index..<end])
                index = end
                let hits = await regionScheduler.cachedAnalyses(for: slice.map(\.1))
                guard !isClosed, !Task.isCancelled else { return }
                var anyChanged = false
                for (photo, request) in slice {
                    let key = regionScheduler.resultKey(for: request)
                    if let analysis = hits[key] {
                        let classified = FolderPreparationClassification.classifyAnalysis(analysis)
                        if accountant.recordAnalysisClassification(classified, for: photo) {
                            anyChanged = true
                        }
                    }
                }
                if anyChanged {
                    emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
                }
            }
        }
    }

    private func runPreviewLoop() async {
        guard let thumbnailPipeline else { return }
        var inFlight: Set<PhotoIdentity> = []
        var deferredCount = 0

        await withTaskGroup(of: (PhotoIdentity, FolderPreparationClassification).self) { group in
            while !isClosed, !Task.isCancelled, locationLossReason == nil {
                if isPausedForMemoryPressure {
                    await waitWhilePaused()
                    continue
                }

                while inFlight.count < Self.previewConcurrency {
                    let candidates = accountant.nextPendingPreviewItems(
                        limit: Self.previewConcurrency - inFlight.count,
                        excluding: inFlight)
                    guard !candidates.isEmpty else { break }
                    for item in candidates {
                        inFlight.insert(item.photo)
                        group.addTask { [weak self] in
                            await self?.preparePreview(
                                item: item, pipeline: thumbnailPipeline)
                                ?? (item.photo, .retryableDeferral("Folder closed."))
                        }
                    }
                }

                if let completed = await group.next() {
                    inFlight.remove(completed.0)
                    guard !isClosed, !Task.isCancelled else { break }
                    if case .retryableDeferral(_, let staleRevision) = completed.1 {
                        deferredCount += 1
                        if staleRevision {
                            accountant.setResolvedRequests(
                                for: completed.0, thumbnailRequest: nil, regionRequest: nil)
                        }
                    } else {
                        deferredCount = 0
                    }
                    if accountant.recordPreviewClassification(completed.1, for: completed.0) {
                        emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
                    }
                    if deferredCount > 0 {
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                } else {
                    break
                }
            }
            group.cancelAll()
        }
    }

    private func preparePreview(
        item: FolderPreparationAccountant.PendingWorkItem,
        pipeline: ThumbnailPipeline
    ) async -> (PhotoIdentity, FolderPreparationClassification) {
        guard !isClosed, !Task.isCancelled, locationLossReason == nil else {
            return (item.photo, .retryableDeferral("Folder closed."))
        }
        let folderID = folder
        let session = session
        let thumbnailCache = thumbnailCache
        let resolvedRequest: ThumbnailRequest?
        if let existing = item.thumbnailRequest {
            resolvedRequest = existing
        } else {
            let primaryURL = item.set.photoSet.primary.url
            guard
                let revision = try? await session.withAdmittedWork({
                    try await ThumbnailRevision.readOnImageWork(from: primaryURL, priority: .folder)
                })
            else {
                return (item.photo, .failed("Couldn't open photo for preview."))
            }
            let req = ThumbnailRequest(
                source: primaryURL,
                revision: revision,
                targetPixels: PipelineGridThumbnails.targetPixels,
                locationIdentity: folderID.rawValue)
            accountant.setResolvedRequests(
                for: item.photo, thumbnailRequest: req, regionRequest: item.regionRequest)
            resolvedRequest = req
        }
        guard let request = resolvedRequest else {
            return (item.photo, .failed("Couldn't open photo for preview."))
        }
        if let cached = thumbnailCache?.cachedOutcome(for: request) {
            return (item.photo, FolderPreparationClassification.classifyPreviewOutcome(cached))
        }
        do {
            let result = try await session.withAdmittedWork {
                try await pipeline.thumbnail(for: request, priority: .folder)
            }
            // Release returned CGImage reference immediately; the accountant stores status only.
            return (item.photo, FolderPreparationClassification.classifyPreviewResult(result))
        } catch {
            return (item.photo, FolderPreparationClassification.classifyPreviewError(error))
        }
    }

    private func runAnalysisLoop() async {
        guard let regionScheduler else { return }
        while !isClosed, !Task.isCancelled, locationLossReason == nil {
            if isPausedForMemoryPressure {
                await waitWhilePaused()
                continue
            }
            pendingAnalysisRefresh = false
            let batch = accountant.nextPendingAnalysisItems(
                limit: Self.analysisWindowSize, excluding: [])
            guard !batch.isEmpty else { break }

            var resolvedPairs: [(PhotoIdentity, RegionSharpnessRequest)] = []
            resolvedPairs.reserveCapacity(batch.count)
            for item in batch {
                guard !isClosed, !Task.isCancelled, locationLossReason == nil else { return }
                if let existing = item.regionRequest {
                    resolvedPairs.append((item.photo, existing))
                } else {
                    if let resolved = await resolveRegionRequest(for: item.set) {
                        accountant.setResolvedRequests(
                            for: item.photo,
                            thumbnailRequest: item.thumbnailRequest,
                            regionRequest: resolved)
                        resolvedPairs.append((item.photo, resolved))
                    } else {
                        _ = accountant.recordAnalysisClassification(
                            .failed("Couldn't open photo for focus analysis."),
                            for: item.photo)
                        emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
                    }
                }
            }
            guard !resolvedPairs.isEmpty, !isClosed, !Task.isCancelled, locationLossReason == nil
            else { continue }

            // Check cache hits first in case interactive navigation populated them since scan end.
            let requests = resolvedPairs.map(\.1)
            let preCached = await regionScheduler.cachedAnalyses(for: requests)
            var uncachedPairs: [(PhotoIdentity, RegionSharpnessRequest)] = []
            for (photo, request) in resolvedPairs {
                let key = regionScheduler.resultKey(for: request)
                if let analysis = preCached[key] {
                    _ = accountant.recordAnalysisClassification(
                        FolderPreparationClassification.classifyAnalysis(analysis), for: photo)
                } else {
                    uncachedPairs.append((photo, request))
                }
            }
            if uncachedPairs.count != resolvedPairs.count {
                emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
            }
            guard !uncachedPairs.isEmpty, !isClosed, !Task.isCancelled, locationLossReason == nil
            else { continue }

            let batchKeys = Set(uncachedPairs.map { regionScheduler.resultKey(for: $0.1) })
            inFlightAnalysisKeys = batchKeys

            let submittedRequests = uncachedPairs.map(\.1)
            do {
                try await session.withAdmittedWork {
                    await regionScheduler.submit(submittedRequests, priority: .folder)
                }
            } catch {
                inFlightAnalysisKeys.removeAll()
                for (photo, _) in uncachedPairs {
                    _ = accountant.recordAnalysisClassification(
                        .retryableDeferral("Folder access interrupted."), for: photo)
                }
                emitStatus(immediate: shouldPublishImmediately(after: accountant.status))
                break
            }
            guard !isClosed, !Task.isCancelled, locationLossReason == nil else {
                inFlightAnalysisKeys.removeAll()
                return
            }

            // Re-check cache once after submit, because disk-cached hits inside scheduler.submit
            // promote to memory without spawning a job or emitting `.settled`.
            let postCached = await regionScheduler.cachedAnalyses(for: submittedRequests)
            for (photo, request) in uncachedPairs {
                let key = regionScheduler.resultKey(for: request)
                if let analysis = postCached[key] {
                    inFlightAnalysisKeys.remove(key)
                    _ = accountant.recordAnalysisClassification(
                        FolderPreparationClassification.classifyAnalysis(analysis), for: photo)
                }
            }
            emitStatus(immediate: shouldPublishImmediately(after: accountant.status))

            // Wait until this bounded window emits `.settled` for every remaining item, or pauses/invalidates.
            while !inFlightAnalysisKeys.isEmpty, !isClosed, !Task.isCancelled,
                locationLossReason == nil
            {
                if isPausedForMemoryPressure || pendingAnalysisRefresh {
                    inFlightAnalysisKeys.removeAll()
                    break
                }
                await waitForAnalysisSettlement()
            }

            if pendingAnalysisRefresh { continue }
            if !isClosed, !Task.isCancelled {
                // Brief yield keeps interactive navigation responsive between background batches.
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    private func resolveRegionRequest(for scanned: ScannedPhotoSet) async -> RegionSharpnessRequest?
    {
        let folderID = folder
        let set = scanned.photoSet
        return try? await session.withAdmittedWork {
            await Task.detached(priority: .utility) {
                let primary = try? DetailSource.read(set.primary.url)
                guard let primary else { return nil }
                let jpeg = set.jpegCompanion.flatMap { try? DetailSource.read($0.url) }
                let heif = set.heifCompanion.flatMap { try? DetailSource.read($0.url) }
                switch set.primary.format {
                case .raw:
                    return RegionSharpnessRequest(
                        raw: primary, jpeg: jpeg, heif: heif, locationIdentity: folderID.rawValue)
                case .jpeg:
                    return RegionSharpnessRequest(
                        jpeg: primary, heif: heif, locationIdentity: folderID.rawValue)
                case .heif:
                    return RegionSharpnessRequest(
                        heif: primary, locationIdentity: folderID.rawValue)
                }
            }.value
        }
    }

    // MARK: - Helpers

    private func checkSynchronousThumbnailHits(for sets: [ScannedPhotoSet]) {
        guard let thumbnailCache else { return }
        for set in sets {
            guard
                let request = FolderPreparationAccountant.makeThumbnailRequest(
                    for: set, folder: folder)
            else { continue }
            if let outcome = thumbnailCache.cachedOutcome(for: request) {
                _ = accountant.recordPreviewOutcome(
                    FolderPreparationClassification.classifyPreviewOutcome(outcome),
                    for: request)
            }
        }
    }

    private func updateWaitingReason() {
        let nextReason: FolderPreparationWaitingReason?
        if let locationLossReason {
            nextReason = .folderUnavailable(locationLossReason)
        } else if isPausedForMemoryPressure {
            nextReason = .memoryPressure
        } else {
            nextReason = nil
        }
        _ = accountant.setWaitingReason(nextReason)
    }

    private func shouldPublishImmediately(after status: FolderPreparationStatus) -> Bool {
        guard let previous = lastPublishedStatus else { return true }
        return status.phase != previous.phase
            || status.totalPhotos != previous.totalPhotos
            || status.isEnumerating != previous.isEnumerating
            || status.waitingReason != previous.waitingReason
            || status.totalIssueCount != previous.totalIssueCount
    }

    private func emitStatus(immediate: Bool) {
        guard !isClosed else { return }
        let current = accountant.status
        guard current != lastPublishedStatus else { return }
        if immediate {
            publishDebounceTask?.cancel()
            publishDebounceTask = nil
            lastPublishedStatus = current
            publish(current)
            return
        }
        guard publishDebounceTask == nil else { return }
        publishDebounceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, !self.isClosed else { return }
            self.publishDebounceTask = nil
            let latest = self.accountant.status
            guard latest != self.lastPublishedStatus else { return }
            self.lastPublishedStatus = latest
            self.publish(latest)
        }
    }

    private func cancelBackgroundWork() {
        preparationTask?.cancel()
        preparationTask = nil
    }

    private func waitWhilePaused() async {
        guard isPausedForMemoryPressure, !isClosed, !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    private func waitForAnalysisSettlement() async {
        guard !isClosed, !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            analysisSettlementWaiters.append(continuation)
        }
    }

    private func resumePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func resumeAnalysisSettlementWaiters() {
        let waiters = analysisSettlementWaiters
        analysisSettlementWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func resumeAllWaiters() {
        resumePauseWaiters()
        resumeAnalysisSettlementWaiters()
    }
}
