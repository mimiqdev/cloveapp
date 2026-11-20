import CloveCore
import CloveImaging
import Foundation

enum FolderPreparationWaitingReason: Hashable, Sendable {
    case memoryPressure
    case folderUnavailable(FolderLocationLoss.Reason)
}

enum FolderPreparationPhase: Hashable, Sendable {
    case idle
    case enumeratingUnknown
    case preparing
    case waiting(FolderPreparationWaitingReason)
    case complete
    case completeWithIssues
}

enum FolderPreparationTaskKind: String, Hashable, Sendable {
    case analysis
    case previews
}

enum FolderPreparationClassification: Equatable, Sendable {
    case completed
    case retryableDeferral(String, staleRevision: Bool = false)
    case unsupported(String)
    case failed(String)

    static func classifyAnalysis(_ analysis: RegionSharpnessAnalysis?) -> Self {
        guard let analysis else {
            return .retryableDeferral("Analysis was interrupted before finishing.")
        }
        if let acquisition = analysis.acquisitionFailure {
            return classifyImageFailure(acquisition, context: "focus analysis")
        }
        if case .unavailable(let pathFailure) = analysis.faces,
            let classified = classifyPathUnavailable(pathFailure, isFacePath: true)
        {
            return classified
        }
        if case .unavailable(let pathFailure) = analysis.autofocus,
            let classified = classifyPathUnavailable(pathFailure, isFacePath: false)
        {
            return classified
        }
        return .completed
    }

    static func classifyPreviewOutcome(_ outcome: ThumbnailCachedOutcome) -> Self {
        switch outcome {
        case .available:
            return .completed
        case .unavailable(let reason):
            return classifyThumbnailUnavailable(reason)
        }
    }

    static func classifyPreviewResult(_ result: ThumbnailResult) -> Self {
        switch result {
        case .available:
            return .completed
        case .unavailable(let reason):
            return classifyThumbnailUnavailable(reason)
        }
    }

    static func classifyPreviewError(_ error: any Error) -> Self {
        if error is CancellationError {
            return .retryableDeferral("Preview request was cancelled before finishing.")
        }
        if let pipelineError = error as? ThumbnailPipelineError {
            switch pipelineError {
            case .queueFull:
                return .retryableDeferral("Preview queue is busy.")
            case .closed:
                return .retryableDeferral("Preview queue paused.")
            }
        }
        return .failed("Couldn't prepare preview.")
    }

    private static func classifyPathUnavailable(
        _ failure: RegionPathUnavailable, isFacePath: Bool
    ) -> Self? {
        switch failure {
        case .noAutofocusMetadata, .noFacesDetected:
            // A photo with no faces or no recorded autofocus data is still a valid analysis.
            return nil
        case .faceDetectionFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(trimmed.isEmpty ? "Face analysis failed." : trimmed)
        case .previewFailed(let imageFailure):
            return classifyImageFailure(
                imageFailure, context: isFacePath ? "face analysis" : "focus analysis")
        }
    }

    private static func classifyImageFailure(
        _ failure: RegionImageFailure, context: String
    ) -> Self {
        switch failure {
        case .closed:
            return .retryableDeferral("Analysis paused for active viewing.")
        case .queueFull:
            return .retryableDeferral("Analysis queue is busy.")
        case .staleSource:
            return .retryableDeferral("File changed during \(context).", staleRevision: true)
        case .cannotOpen:
            return .failed("Couldn't open photo for \(context).")
        case .noUsablePreview:
            return .failed("No usable preview for \(context).")
        }
    }

    private static func classifyThumbnailUnavailable(_ reason: ThumbnailUnavailable) -> Self {
        switch reason {
        case .sourceChanged:
            return .retryableDeferral(
                "File changed during preview preparation.", staleRevision: true)
        case .cannotOpen:
            return .failed("Couldn't open photo for preview.")
        case .noUsablePreview:
            return .failed("No usable embedded preview.")
        }
    }
}

enum FolderPreparationOutcome: Hashable, Sendable {
    case pending
    case completed
    case failed(String)
    case unsupported(String)
    case deferred(String)

    var isSettled: Bool {
        if case .pending = self { return false }
        return true
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var isRetryable: Bool {
        switch self {
        case .failed, .deferred: true
        case .pending, .completed, .unsupported: false
        }
    }

    var issueDescription: String? {
        switch self {
        case .pending, .completed: nil
        case .failed(let message), .unsupported(let message), .deferred(let message): message
        }
    }
}

struct FolderPreparationTaskCounts: Hashable, Sendable {
    var completed: Int = 0
    var failed: Int = 0
    var unsupported: Int = 0
    var deferred: Int = 0

    var retryableIssueCount: Int { failed + deferred }
    var issueCount: Int { failed + unsupported + deferred }
    var settledCount: Int { completed + issueCount }
}

struct FolderPreparationIssue: Hashable, Sendable, Identifiable {
    let photo: PhotoIdentity
    let fileName: String
    let task: FolderPreparationTaskKind
    let reason: String

    var id: String {
        "\(photo.folderID.rawValue)|\(photo.relativeFolderPath)|\(photo.stem)|\(task.rawValue)"
    }
}

struct FolderPreparationStatus: Hashable, Sendable {
    static let maxDisplayedIssues = 25

    static let idle = FolderPreparationStatus(
        folder: FolderIdentity(rawValue: ""),
        folderName: "",
        generation: 0,
        isEnumerating: false,
        isPartialScan: false,
        waitingReason: nil,
        totalPhotos: 0,
        analysis: FolderPreparationTaskCounts(),
        previews: FolderPreparationTaskCounts(),
        readyForBothCount: 0,
        bothSettledCount: 0,
        issues: [])

    var folder: FolderIdentity
    var folderName: String
    var generation: Int
    var isEnumerating: Bool
    var isPartialScan: Bool
    var waitingReason: FolderPreparationWaitingReason?
    var totalPhotos: Int
    var analysis: FolderPreparationTaskCounts
    var previews: FolderPreparationTaskCounts
    var readyForBothCount: Int
    var bothSettledCount: Int
    var issues: [FolderPreparationIssue]

    var hasMaterialIssues: Bool {
        analysis.issueCount > 0 || previews.issueCount > 0
    }

    var totalIssueCount: Int {
        analysis.issueCount + previews.issueCount
    }

    var retryableIssueCount: Int {
        analysis.retryableIssueCount + previews.retryableIssueCount
    }

    var hasRetryableIssues: Bool {
        retryableIssueCount > 0
    }

    var canRetryIssues: Bool {
        hasRetryableIssues && waitingReason == nil
    }

    var phase: FolderPreparationPhase {
        if totalPhotos == 0 {
            if let waitingReason {
                return .waiting(waitingReason)
            }
            if isEnumerating {
                return .enumeratingUnknown
            }
            return .idle
        }
        let allSettled = !isEnumerating && bothSettledCount >= totalPhotos
        if allSettled {
            return hasMaterialIssues ? .completeWithIssues : .complete
        }
        if let waitingReason {
            return .waiting(waitingReason)
        }
        return .preparing
    }

    var isVisibleInHeader: Bool {
        phase != .idle
    }

    var readyFraction: Double? {
        guard totalPhotos > 0 else { return nil }
        return min(max(Double(readyForBothCount) / Double(totalPhotos), 0), 1)
    }

    var analysisFraction: Double? {
        guard totalPhotos > 0 else { return nil }
        return min(max(Double(analysis.completed) / Double(totalPhotos), 0), 1)
    }

    var previewFraction: Double? {
        guard totalPhotos > 0 else { return nil }
        return min(max(Double(previews.completed) / Double(totalPhotos), 0), 1)
    }
}

struct FolderPreparationAccountant: Sendable {
    struct PendingWorkItem: Sendable {
        let photo: PhotoIdentity
        let set: ScannedPhotoSet
        let thumbnailRequest: ThumbnailRequest?
        let regionRequest: RegionSharpnessRequest?
    }

    struct RetryTargets: Sendable {
        let previewURLs: [URL]
        let analysisRequests: [RegionSharpnessRequest]
        let hasWork: Bool
    }

    private struct TrackedPhoto: Sendable {
        var set: ScannedPhotoSet
        var fileName: String
        var primaryURL: URL
        var fileURLs: [URL]
        var thumbnailRequest: ThumbnailRequest?
        var regionRequest: RegionSharpnessRequest?
        var analysis: FolderPreparationOutcome = .pending
        var preview: FolderPreparationOutcome = .pending
        var analysisRetryCount: Int = 0
        var previewRetryCount: Int = 0

        var isReadyForBoth: Bool { analysis.isCompleted && preview.isCompleted }
        var isBothSettled: Bool { analysis.isSettled && preview.isSettled }
    }

    let folder: FolderIdentity
    var folderName: String
    let generation: Int
    let parametersVersion: Int
    let maxTransientRetries: Int

    private var photos: [PhotoIdentity: TrackedPhoto] = [:]
    private var orderedIDs: [PhotoIdentity] = []
    private var thumbnailKeyIndex: [ThumbnailRequest: PhotoIdentity] = [:]
    private var urlIndex: [URL: Set<PhotoIdentity>] = [:]

    private var isEnumerating = true
    private var isPartialScan = false
    private var waitingReason: FolderPreparationWaitingReason?

    private var analysisCounts = FolderPreparationTaskCounts()
    private var previewCounts = FolderPreparationTaskCounts()
    private var readyForBothCount = 0
    private var bothSettledCount = 0

    init(
        folder: FolderIdentity,
        folderName: String,
        generation: Int,
        parametersVersion: Int = 2,
        maxTransientRetries: Int = 3
    ) {
        self.folder = folder
        self.folderName = folderName
        self.generation = generation
        self.parametersVersion = parametersVersion
        self.maxTransientRetries = max(0, maxTransientRetries)
    }

    var status: FolderPreparationStatus {
        let collectedIssues: [FolderPreparationIssue]
        if analysisCounts.issueCount > 0 || previewCounts.issueCount > 0 {
            var list: [FolderPreparationIssue] = []
            list.reserveCapacity(min(FolderPreparationStatus.maxDisplayedIssues, orderedIDs.count))
            for id in orderedIDs {
                guard let tracked = photos[id] else { continue }
                if let reason = tracked.analysis.issueDescription {
                    list.append(
                        FolderPreparationIssue(
                            photo: id, fileName: tracked.fileName, task: .analysis, reason: reason))
                    if list.count >= FolderPreparationStatus.maxDisplayedIssues { break }
                }
                if let reason = tracked.preview.issueDescription {
                    list.append(
                        FolderPreparationIssue(
                            photo: id, fileName: tracked.fileName, task: .previews, reason: reason))
                    if list.count >= FolderPreparationStatus.maxDisplayedIssues { break }
                }
            }
            collectedIssues = list
        } else {
            collectedIssues = []
        }
        return FolderPreparationStatus(
            folder: folder,
            folderName: folderName,
            generation: generation,
            isEnumerating: isEnumerating,
            isPartialScan: isPartialScan,
            waitingReason: waitingReason,
            totalPhotos: orderedIDs.count,
            analysis: analysisCounts,
            previews: previewCounts,
            readyForBothCount: readyForBothCount,
            bothSettledCount: bothSettledCount,
            issues: collectedIssues)
    }

    var hasPendingWork: Bool {
        orderedIDs.contains { id in
            guard let tracked = photos[id] else { return false }
            return !tracked.isBothSettled
        }
    }

    var hasRetryableIssues: Bool {
        analysisCounts.retryableIssueCount > 0 || previewCounts.retryableIssueCount > 0
    }

    func retryableTargets() -> RetryTargets {
        var previewURLs: [URL] = []
        var analysisRequests: [RegionSharpnessRequest] = []
        var hasWork = false
        for id in orderedIDs {
            guard let tracked = photos[id] else { continue }
            if tracked.preview.isRetryable {
                hasWork = true
                previewURLs.append(tracked.primaryURL)
            }
            if tracked.analysis.isRetryable {
                hasWork = true
                if let request = tracked.regionRequest {
                    analysisRequests.append(request)
                }
            }
        }
        return RetryTargets(
            previewURLs: previewURLs,
            analysisRequests: analysisRequests,
            hasWork: hasWork)
    }

    /// Resets only failed or deferred task outcomes back to `.pending`, preserving completed and
    /// unsupported outcomes intact and resetting retry counters for the retried task(s).
    @discardableResult
    mutating func retryIssues() -> [PhotoIdentity] {
        guard hasRetryableIssues else { return [] }
        var retried: [PhotoIdentity] = []
        for id in orderedIDs {
            guard var tracked = photos[id] else { continue }
            let retryPreview = tracked.preview.isRetryable
            let retryAnalysis = tracked.analysis.isRetryable
            guard retryPreview || retryAnalysis else { continue }

            let wasReady = tracked.isReadyForBoth
            let wasSettled = tracked.isBothSettled

            if retryPreview {
                if let oldKey = tracked.thumbnailRequest, thumbnailKeyIndex[oldKey] == id {
                    thumbnailKeyIndex.removeValue(forKey: oldKey)
                }
                tracked.thumbnailRequest = nil
                adjustTaskCount(&previewCounts, outcome: tracked.preview, delta: -1)
                tracked.preview = .pending
                tracked.previewRetryCount = 0
            }
            if retryAnalysis {
                tracked.regionRequest = nil
                adjustTaskCount(&analysisCounts, outcome: tracked.analysis, delta: -1)
                tracked.analysis = .pending
                tracked.analysisRetryCount = 0
            }

            if wasReady && !tracked.isReadyForBoth { readyForBothCount -= 1 }
            if wasSettled && !tracked.isBothSettled { bothSettledCount -= 1 }
            photos[id] = tracked
            retried.append(id)
        }
        return retried
    }

    mutating func registerDiscovered(_ sets: [ScannedPhotoSet]) {
        for set in sets {
            guard set.id.folderID == folder else { continue }
            guard photos[set.id] == nil else { continue }
            let primaryURL = set.photoSet.primary.url.standardizedFileURL
            let fileURLs = set.photoSet.imageFiles.map { $0.url.standardizedFileURL }
            let thumbnailRequest = Self.makeThumbnailRequest(for: set, folder: folder)
            let regionRequest = Self.makeRegionRequest(for: set, folder: folder)
            let tracked = TrackedPhoto(
                set: set,
                fileName: set.photoSet.primary.url.lastPathComponent,
                primaryURL: primaryURL,
                fileURLs: fileURLs,
                thumbnailRequest: thumbnailRequest,
                regionRequest: regionRequest)
            photos[set.id] = tracked
            orderedIDs.append(set.id)
            if let thumbnailRequest {
                thumbnailKeyIndex[thumbnailRequest] = set.id
            }
            for url in fileURLs {
                urlIndex[url, default: []].insert(set.id)
            }
        }
    }

    mutating func removePhotos(_ identities: Set<PhotoIdentity>) {
        guard !identities.isEmpty else { return }
        var removedAny = false
        for id in identities {
            guard let tracked = photos.removeValue(forKey: id) else { continue }
            removedAny = true
            adjustCounts(for: tracked, delta: -1)
            if let key = tracked.thumbnailRequest, thumbnailKeyIndex[key] == id {
                thumbnailKeyIndex.removeValue(forKey: key)
            }
            for url in tracked.fileURLs {
                urlIndex[url]?.remove(id)
                if urlIndex[url]?.isEmpty == true {
                    urlIndex.removeValue(forKey: url)
                }
            }
        }
        if removedAny {
            orderedIDs.removeAll { identities.contains($0) }
        }
    }

    mutating func finishScan(isPartial: Bool) {
        isEnumerating = false
        isPartialScan = isPartial
    }

    mutating func setWaitingReason(_ reason: FolderPreparationWaitingReason?) -> Bool {
        guard waitingReason != reason else { return false }
        waitingReason = reason
        return true
    }

    mutating func setResolvedRequests(
        for id: PhotoIdentity,
        thumbnailRequest: ThumbnailRequest?,
        regionRequest: RegionSharpnessRequest?
    ) {
        guard var tracked = photos[id] else { return }
        if let oldKey = tracked.thumbnailRequest, oldKey != thumbnailRequest,
            thumbnailKeyIndex[oldKey] == id
        {
            thumbnailKeyIndex.removeValue(forKey: oldKey)
        }
        tracked.thumbnailRequest = thumbnailRequest
        if let thumbnailRequest {
            thumbnailKeyIndex[thumbnailRequest] = id
        }
        tracked.regionRequest = regionRequest
        photos[id] = tracked
    }

    @discardableResult
    mutating func recordPreviewOutcome(
        _ classification: FolderPreparationClassification,
        for request: ThumbnailRequest
    ) -> Bool {
        guard request.locationIdentity == folder.rawValue,
            request.targetPixels == PipelineGridThumbnails.targetPixels
        else { return false }
        if let id = thumbnailKeyIndex[request], let tracked = photos[id] {
            guard tracked.thumbnailRequest == request else { return false }
            return applyPreviewClassification(classification, to: id)
        }
        let sourceURL = request.source.standardizedFileURL
        guard let candidateIDs = urlIndex[sourceURL] else { return false }
        var changed = false
        for id in candidateIDs {
            guard var tracked = photos[id], tracked.primaryURL == sourceURL else { continue }
            if let expected = tracked.thumbnailRequest {
                guard expected == request else { continue }
            } else {
                tracked.thumbnailRequest = request
                photos[id] = tracked
                thumbnailKeyIndex[request] = id
            }
            if applyPreviewClassification(classification, to: id) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    mutating func recordPreviewClassification(
        _ classification: FolderPreparationClassification,
        for id: PhotoIdentity
    ) -> Bool {
        applyPreviewClassification(classification, to: id)
    }

    @discardableResult
    mutating func recordAnalysisSettlement(
        key: SharpnessResultKey,
        request: RegionSharpnessRequest,
        analysis: RegionSharpnessAnalysis?
    ) -> Bool {
        guard key.folderSession == folder.rawValue,
            key.parametersVersion == parametersVersion
        else { return false }
        let primaryURL = request.primaryURL.standardizedFileURL
        guard let candidateIDs = urlIndex[primaryURL] else { return false }
        let classification = FolderPreparationClassification.classifyAnalysis(analysis)
        var changed = false
        for id in candidateIDs {
            guard var tracked = photos[id], tracked.primaryURL == primaryURL else { continue }
            if let expected = tracked.regionRequest {
                guard expected.primaryRevisionMatches(request) else { continue }
            } else {
                tracked.regionRequest = request
                photos[id] = tracked
            }
            if applyAnalysisClassification(classification, to: id) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    mutating func recordAnalysisClassification(
        _ classification: FolderPreparationClassification,
        for id: PhotoIdentity
    ) -> Bool {
        applyAnalysisClassification(classification, to: id)
    }

    @discardableResult
    mutating func invalidate(sources: [URL]) -> [PhotoIdentity] {
        let standardized = Set(sources.map { $0.standardizedFileURL })
        var affected: Set<PhotoIdentity> = []
        for url in standardized {
            if let ids = urlIndex[url] {
                affected.formUnion(ids)
            }
        }
        var changed: [PhotoIdentity] = []
        for id in affected {
            guard var tracked = photos[id] else { continue }
            var modified = false
            let wasReady = tracked.isReadyForBoth
            let wasSettled = tracked.isBothSettled

            let primaryTouched = standardized.contains(tracked.primaryURL)
            if primaryTouched {
                if let oldKey = tracked.thumbnailRequest, thumbnailKeyIndex[oldKey] == id {
                    thumbnailKeyIndex.removeValue(forKey: oldKey)
                }
                tracked.thumbnailRequest = nil
                if tracked.preview != .pending {
                    adjustTaskCount(&previewCounts, outcome: tracked.preview, delta: -1)
                    tracked.preview = .pending
                    modified = true
                }
                tracked.previewRetryCount = 0
            }
            tracked.regionRequest = nil
            if tracked.analysis != .pending {
                adjustTaskCount(&analysisCounts, outcome: tracked.analysis, delta: -1)
                tracked.analysis = .pending
                modified = true
            }
            tracked.analysisRetryCount = 0

            if wasReady && !tracked.isReadyForBoth { readyForBothCount -= 1 }
            if wasSettled && !tracked.isBothSettled { bothSettledCount -= 1 }
            photos[id] = tracked
            if modified || primaryTouched {
                changed.append(id)
            }
        }
        return changed
    }

    func thumbnailCheckRequests() -> [(PhotoIdentity, ThumbnailRequest)] {
        orderedIDs.compactMap { id in
            guard let tracked = photos[id],
                !tracked.preview.isSettled,
                let request = tracked.thumbnailRequest
            else { return nil }
            return (id, request)
        }
    }

    func analysisCheckRequests() -> [(PhotoIdentity, RegionSharpnessRequest)] {
        orderedIDs.compactMap { id in
            guard let tracked = photos[id],
                !tracked.analysis.isSettled,
                let request = tracked.regionRequest
            else { return nil }
            return (id, request)
        }
    }

    func nextPendingPreviewItems(
        limit: Int, excluding: Set<PhotoIdentity>
    ) -> [PendingWorkItem] {
        guard limit > 0 else { return [] }
        var items: [PendingWorkItem] = []
        items.reserveCapacity(limit)
        for id in orderedIDs where !excluding.contains(id) {
            guard let tracked = photos[id], tracked.preview == .pending else { continue }
            items.append(
                PendingWorkItem(
                    photo: id,
                    set: tracked.set,
                    thumbnailRequest: tracked.thumbnailRequest,
                    regionRequest: tracked.regionRequest))
            if items.count >= limit { break }
        }
        return items
    }

    func nextPendingAnalysisItems(
        limit: Int, excluding: Set<PhotoIdentity>
    ) -> [PendingWorkItem] {
        guard limit > 0 else { return [] }
        var items: [PendingWorkItem] = []
        items.reserveCapacity(limit)
        for id in orderedIDs where !excluding.contains(id) {
            guard let tracked = photos[id], tracked.analysis == .pending else { continue }
            items.append(
                PendingWorkItem(
                    photo: id,
                    set: tracked.set,
                    thumbnailRequest: tracked.thumbnailRequest,
                    regionRequest: tracked.regionRequest))
            if items.count >= limit { break }
        }
        return items
    }

    private mutating func applyPreviewClassification(
        _ classification: FolderPreparationClassification,
        to id: PhotoIdentity
    ) -> Bool {
        guard var tracked = photos[id] else { return false }
        let newOutcome: FolderPreparationOutcome
        switch classification {
        case .completed:
            newOutcome = .completed
        case .unsupported(let message):
            newOutcome = .unsupported(message)
        case .failed(let message):
            newOutcome = .failed(message)
        case .retryableDeferral(let message, let staleRevision):
            if staleRevision {
                if let oldKey = tracked.thumbnailRequest, thumbnailKeyIndex[oldKey] == id {
                    thumbnailKeyIndex.removeValue(forKey: oldKey)
                }
                tracked.thumbnailRequest = nil
            }
            if case .completed = tracked.preview {
                if staleRevision {
                    adjustTaskCount(&previewCounts, outcome: tracked.preview, delta: -1)
                    if tracked.isReadyForBoth { readyForBothCount -= 1 }
                    if tracked.isBothSettled { bothSettledCount -= 1 }
                    tracked.preview = .pending
                    tracked.previewRetryCount = 1
                    photos[id] = tracked
                    return true
                }
                return false
            }
            if tracked.preview.isSettled { return false }
            tracked.previewRetryCount += 1
            if tracked.previewRetryCount <= maxTransientRetries {
                photos[id] = tracked
                return false
            }
            newOutcome = .deferred(message)
        }

        guard shouldReplace(current: tracked.preview, with: newOutcome) else {
            return false
        }
        let wasReady = tracked.isReadyForBoth
        let wasSettled = tracked.isBothSettled
        adjustTaskCount(&previewCounts, outcome: tracked.preview, delta: -1)
        tracked.preview = newOutcome
        adjustTaskCount(&previewCounts, outcome: newOutcome, delta: 1)
        if !wasReady && tracked.isReadyForBoth { readyForBothCount += 1 }
        if wasReady && !tracked.isReadyForBoth { readyForBothCount -= 1 }
        if !wasSettled && tracked.isBothSettled { bothSettledCount += 1 }
        if wasSettled && !tracked.isBothSettled { bothSettledCount -= 1 }
        photos[id] = tracked
        return true
    }

    private mutating func applyAnalysisClassification(
        _ classification: FolderPreparationClassification,
        to id: PhotoIdentity
    ) -> Bool {
        guard var tracked = photos[id] else { return false }
        let newOutcome: FolderPreparationOutcome
        switch classification {
        case .completed:
            newOutcome = .completed
        case .unsupported(let message):
            newOutcome = .unsupported(message)
        case .failed(let message):
            newOutcome = .failed(message)
        case .retryableDeferral(let message, let staleRevision):
            if staleRevision {
                tracked.regionRequest = nil
            }
            if case .completed = tracked.analysis {
                if staleRevision {
                    adjustTaskCount(&analysisCounts, outcome: tracked.analysis, delta: -1)
                    if tracked.isReadyForBoth { readyForBothCount -= 1 }
                    if tracked.isBothSettled { bothSettledCount -= 1 }
                    tracked.analysis = .pending
                    tracked.analysisRetryCount = 1
                    photos[id] = tracked
                    return true
                }
                return false
            }
            if tracked.analysis.isSettled { return false }
            tracked.analysisRetryCount += 1
            if tracked.analysisRetryCount <= maxTransientRetries {
                photos[id] = tracked
                return false
            }
            newOutcome = .deferred(message)
        }

        guard shouldReplace(current: tracked.analysis, with: newOutcome) else {
            return false
        }
        let wasReady = tracked.isReadyForBoth
        let wasSettled = tracked.isBothSettled
        adjustTaskCount(&analysisCounts, outcome: tracked.analysis, delta: -1)
        tracked.analysis = newOutcome
        adjustTaskCount(&analysisCounts, outcome: newOutcome, delta: 1)
        if !wasReady && tracked.isReadyForBoth { readyForBothCount += 1 }
        if wasReady && !tracked.isReadyForBoth { readyForBothCount -= 1 }
        if !wasSettled && tracked.isBothSettled { bothSettledCount += 1 }
        if wasSettled && !tracked.isBothSettled { bothSettledCount -= 1 }
        photos[id] = tracked
        return true
    }

    private func shouldReplace(
        current: FolderPreparationOutcome, with next: FolderPreparationOutcome
    ) -> Bool {
        if current == next { return false }
        switch current {
        case .pending:
            return true
        case .deferred:
            // Later real completion or explicit failure supersedes a transient deferral.
            if case .pending = next { return false }
            return true
        case .completed, .failed, .unsupported:
            // Settled outcomes for the active revision are immutable unless invalidated.
            return false
        }
    }

    private mutating func adjustCounts(for tracked: TrackedPhoto, delta: Int) {
        adjustTaskCount(&analysisCounts, outcome: tracked.analysis, delta: delta)
        adjustTaskCount(&previewCounts, outcome: tracked.preview, delta: delta)
        if tracked.isReadyForBoth { readyForBothCount += delta }
        if tracked.isBothSettled { bothSettledCount += delta }
    }

    private func adjustTaskCount(
        _ counts: inout FolderPreparationTaskCounts,
        outcome: FolderPreparationOutcome,
        delta: Int
    ) {
        switch outcome {
        case .pending:
            break
        case .completed:
            counts.completed += delta
        case .failed:
            counts.failed += delta
        case .unsupported:
            counts.unsupported += delta
        case .deferred:
            counts.deferred += delta
        }
    }

    static func makeThumbnailRequest(
        for scanned: ScannedPhotoSet,
        folder: FolderIdentity
    ) -> ThumbnailRequest? {
        guard let source = detailSource(for: scanned.photoSet.primary, in: scanned) else {
            return nil
        }
        return ThumbnailRequest(
            source: source.url,
            revision: source.revision,
            targetPixels: PipelineGridThumbnails.targetPixels,
            locationIdentity: folder.rawValue)
    }

    static func makeRegionRequest(
        for scanned: ScannedPhotoSet,
        folder: FolderIdentity
    ) -> RegionSharpnessRequest? {
        guard let primary = detailSource(for: scanned.photoSet.primary, in: scanned) else {
            return nil
        }
        let jpeg = scanned.photoSet.jpegCompanion.flatMap {
            detailSource(for: $0, in: scanned)
        }
        let heif = scanned.photoSet.heifCompanion.flatMap {
            detailSource(for: $0, in: scanned)
        }
        switch scanned.photoSet.primary.format {
        case .raw:
            return RegionSharpnessRequest(
                raw: primary, jpeg: jpeg, heif: heif, locationIdentity: folder.rawValue)
        case .jpeg:
            return RegionSharpnessRequest(
                jpeg: primary, heif: heif, locationIdentity: folder.rawValue)
        case .heif:
            return RegionSharpnessRequest(
                heif: primary, locationIdentity: folder.rawValue)
        }
    }

    static func detailSource(
        for file: PhotoFile, in scanned: ScannedPhotoSet
    ) -> DetailSource? {
        let entry =
            scanned.imageFiles.first { $0.file.url == file.url }
            ?? scanned.imageFiles.first { $0.file == file }
        guard let size = entry?.size, let modificationDate = entry?.modificationDate else {
            return nil
        }
        return DetailSource(
            url: file.url,
            revision: ThumbnailRevision(size: Int64(size), modificationTime: modificationDate))
    }
}

private extension RegionSharpnessRequest {
    func primaryRevisionMatches(_ other: RegionSharpnessRequest) -> Bool {
        if let raw, let otherRaw = other.raw {
            return raw.url == otherRaw.url && raw.revision == otherRaw.revision
        }
        if raw == nil, other.raw == nil {
            if let jpeg, let otherJPEG = other.jpeg {
                return jpeg.url == otherJPEG.url && jpeg.revision == otherJPEG.revision
            }
            if jpeg == nil, other.jpeg == nil, let heif, let otherHEIF = other.heif {
                return heif.url == otherHEIF.url && heif.revision == otherHEIF.revision
            }
        }
        return false
    }
}
