import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import Synchronization

/// The folder supplies session admission, so its security scope outlives every
/// read, including an uncancellable render draining after navigation.
struct DetailWorkAdmission: Sendable {
    let image: @Sendable (@Sendable () async -> DetailImageOutcome) async -> DetailImageOutcome
    let prefetch: @Sendable (@Sendable () async -> Void) async -> Void
    let sharpness:
        @Sendable (@Sendable () async -> RegionSharpnessAnalysis?) async
            -> RegionSharpnessAnalysis?
}

extension DetailWorkAdmission {
    static let direct = DetailWorkAdmission(
        image: { await $0() }, prefetch: { await $0() }, sharpness: { await $0() })
}

@MainActor
final class PipelineDetailImages: DetailImageSource {
    private let pipeline: DetailPipeline
    private let thumbnails: ThumbnailCache?
    private let set: @MainActor (PhotoIdentity) -> PhotoSet?
    private let admitted: DetailWorkAdmission
    private let consumer = UUID()
    private let regionScheduler: RegionSharpnessScheduler
    private let onUserActivity: (@MainActor () async -> Void)?
    private let regionRequestTracker = KnownRegionRequestTracker()
    private let knownSources = KnownDetailSourceCache()
    private var activeWindow: DetailPhotoWindow?
    private var navigationGeneration: UInt64 = 0

    init(
        pipeline: DetailPipeline,
        thumbnails: ThumbnailCache? = nil,
        set: @escaping @MainActor (PhotoIdentity) -> PhotoSet?,
        admitted: DetailWorkAdmission = .direct,
        regionScheduler: RegionSharpnessScheduler? = nil,
        sharpnessCache: RegionSharpnessCache? = nil,
        onUserActivity: (@MainActor () async -> Void)? = nil
    ) {
        self.pipeline = pipeline
        self.thumbnails = thumbnails
        self.set = set
        self.admitted = admitted
        self.regionScheduler =
            regionScheduler
            ?? RegionSharpnessScheduler(
                analyzer: RegionSharpnessAnalyzer(
                    reader: DetailRegionSharpnessReading(details: pipeline)),
                results: RegionSharpnessResultStore(
                    capacity: 512, disk: sharpnessCache))
        self.onUserActivity = onUserActivity
    }

    func warmImage(for photo: PhotoIdentity, request: DetailPixelRequest) -> DetailImage? {
        guard let current = sources(for: photo) else { return nil }
        guard
            let detailRequest = knownSources.request(
                for: photo, matching: current, request: request)
        else { return nil }
        return pipeline.warmCachedImage(for: detailRequest)
    }

    /// Reads the shared grid cache directly, without entering the grid work queue.
    func placeholder(for photo: PhotoIdentity, gridThumbnails: any GridThumbnailSource) async
        -> CGImage?
    {
        guard let thumbnails, let sources = sources(for: photo) else { return nil }
        let outcome = await admitted.image {
            guard
                let request = sources.request(
                    for: DetailPixelRequest(displayPixels: 400, need: .preview)),
                let source = request.raw ?? request.jpeg ?? request.heif
            else { return .deferred }
            let key = ThumbnailRequest(
                source: source.url, revision: source.revision, targetPixels: 400,
                locationIdentity: request.locationIdentity)
            guard case .available(let thumbnail) = thumbnails.result(for: key) else {
                return .deferred
            }
            return .image(
                DetailImage(
                    image: thumbnail.image, source: source, quality: .preview,
                    hasRAW: request.raw != nil))
        }
        if case .image(let image) = outcome { return image.image }
        return nil
    }

    func prepare(_ window: DetailPhotoWindow) async {
        await onUserActivity?()
        navigationGeneration += 1
        let generation = navigationGeneration
        activeWindow = window
        let current = sources(for: window.current.photo)
        let keptURLs = Set(
            [current?.raw, current?.jpeg, current?.heif].compactMap { $0?.standardizedFileURL })
        await pipeline.beginNavigation(generation, keepingAnalysisFor: keptURLs)
        guard !Task.isCancelled, activeWindow == window, generation == navigationGeneration,
            let current
        else { return }
        _ = await admitted.image { [pipeline, knownSources] in
            guard !Task.isCancelled,
                let request = Self.resolveRequest(
                    for: window.current.photo, sources: current,
                    request: window.request(), knownSources: knownSources)
            else { return .deferred }
            await pipeline.navigate(to: request, generation: generation)
            return .deferred
        }
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        await onUserActivity?()
        guard let sources = sources(for: photo) else { return .unavailable(.cannotOpen) }
        return await admitted.image { [pipeline, consumer, knownSources] in
            guard
                let detailRequest = Self.resolveRequest(
                    for: photo, sources: sources, request: request, knownSources: knownSources)
            else {
                return .unavailable(.cannotOpen)
            }
            do {
                let result: DetailResult
                switch request.need {
                case .preview:
                    result = try await pipeline.preview(for: detailRequest, consumer: consumer)
                case .screenRender:
                    result = try await pipeline.screen(for: detailRequest, consumer: consumer)
                case .morePixels, .fullResolution:
                    result = try await pipeline.image(for: detailRequest, consumer: consumer)
                }
                switch result {
                case .available(let image): return .image(image)
                case .unavailable(let failure): return .unavailable(failure)
                }
            } catch { return .deferred }
        }
    }

    /// Warm +/-2 embedded previews immediately on arrival on the preview lane.
    func prefetchPreviews(_ window: DetailPhotoWindow) async {
        guard activeWindow == window else { return }
        let pixelRequest = window.request()
        let targets = window.previewNeighbours.compactMap {
            neighbour -> (PhotoIdentity, PhotoSources)? in
            guard let sources = sources(for: neighbour.photo) else { return nil }
            return (neighbour.photo, sources)
        }
        guard !targets.isEmpty else { return }
        await admitted.prefetch { [pipeline, knownSources] in
            guard !Task.isCancelled else { return }
            let resolved = targets.compactMap { photo, sources in
                Self.resolveRequest(
                    for: photo, sources: sources, request: pixelRequest, knownSources: knownSources
                )
            }
            guard !Task.isCancelled, !resolved.isEmpty else { return }
            await pipeline.prefetch(resolved)
        }
    }

    /// Warm +/-2 embedded neighbours, then render exactly one ahead.
    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        guard activeWindow == window else { return }
        let pixelRequest = window.request()
        let previewTargets = window.previewNeighbours.compactMap {
            neighbour -> (PhotoIdentity, PhotoSources)? in
            guard let sources = sources(for: neighbour.photo) else { return nil }
            return (neighbour.photo, sources)
        }
        let neighbours = window.neighbours.compactMap {
            neighbour -> (PhotoIdentity, PhotoSources, Bool)? in
            guard let sources = sources(for: neighbour.photo) else { return nil }
            let ahead = neighbour.position == window.current.position + window.direction
            return (neighbour.photo, sources, ahead)
        }
        await admitted.prefetch { [pipeline, knownSources] in
            guard !Task.isCancelled else { return }
            let resolvedPreviews = previewTargets.compactMap { photo, sources in
                Self.resolveRequest(
                    for: photo, sources: sources, request: pixelRequest, knownSources: knownSources
                )
            }
            guard !Task.isCancelled else { return }
            await pipeline.prefetch(resolvedPreviews)
            guard renderAhead, !Task.isCancelled,
                let aheadTarget = neighbours.first(where: \.2),
                let ahead = Self.resolveRequest(
                    for: aheadTarget.0, sources: aheadTarget.1, request: pixelRequest,
                    knownSources: knownSources)
            else { return }
            try? await pipeline.prefetchScreen(for: ahead)
        }
    }

    func leave(window: UUID) async {
        guard activeWindow?.id == window else { return }
        activeWindow = nil
        navigationGeneration += 1
        await pipeline.leavePhoto(generation: navigationGeneration)
    }

    private func sources(for photo: PhotoIdentity) -> PhotoSources? {
        set(photo).map(PhotoSources.init)
    }

    private nonisolated static func resolveRequest(
        for photo: PhotoIdentity,
        sources: PhotoSources,
        request: DetailPixelRequest,
        knownSources: KnownDetailSourceCache
    ) -> DetailRequest? {
        let resolved = sources.readResolvedSources()
        let entry = KnownDetailSources(
            locationIdentity: sources.locationIdentity,
            rawURL: sources.raw, jpegURL: sources.jpeg, heifURL: sources.heif,
            raw: resolved.raw, jpeg: resolved.jpeg, heif: resolved.heif)
        knownSources.store(entry, for: photo)
        return entry.detailRequest(for: request)
    }
}

private final class KnownDetailSourceCache: Sendable {
    private let entries = Mutex<[PhotoIdentity: KnownDetailSources]>([:])

    func store(_ entry: KnownDetailSources, for photo: PhotoIdentity) {
        entries.withLock { map in
            if map.count >= 256, map[photo] == nil {
                map.removeAll(keepingCapacity: true)
            }
            map[photo] = entry
        }
    }

    func request(
        for photo: PhotoIdentity, matching sources: PhotoSources, request: DetailPixelRequest
    ) -> DetailRequest? {
        let entry = entries.withLock { $0[photo] }
        guard let entry, entry.matches(sources) else { return nil }
        return entry.detailRequest(for: request)
    }
}

private struct KnownDetailSources: Sendable {
    let locationIdentity: String
    let rawURL: URL?
    let jpegURL: URL?
    let heifURL: URL?
    let raw: DetailSource?
    let jpeg: DetailSource?
    let heif: DetailSource?

    func matches(_ sources: PhotoSources) -> Bool {
        locationIdentity == sources.locationIdentity
            && rawURL == sources.raw
            && jpegURL == sources.jpeg
            && heifURL == sources.heif
    }

    func detailRequest(for request: DetailPixelRequest) -> DetailRequest? {
        guard raw != nil || jpeg != nil || heif != nil else { return nil }
        return DetailRequest(
            raw: raw, jpeg: jpeg, heif: heif,
            displayPixels: request.displayPixels,
            wantsNativeResolution: request.need == .fullResolution,
            locationIdentity: locationIdentity,
            mode: request.mode == .rawFirst ? .rawFirst : .cameraPreviewFirst,
            screenPixels: request.screenPixels)
    }
}

/// Role-tagged URLs cross the session boundary instead of the scanned domain set.
private struct PhotoSources: Sendable {
    var raw: URL?
    var jpeg: URL?
    var heif: URL?
    var locationIdentity: String

    init(set: PhotoSet) {
        locationIdentity = set.id.folderID.rawValue
        switch set.primary.format {
        case .raw:
            raw = set.primary.url
            jpeg = set.jpegCompanion?.url
            heif = set.heifCompanion?.url
        case .jpeg:
            jpeg = set.primary.url
            heif = set.heifCompanion?.url
        case .heif:
            heif = set.primary.url
        }
    }

    func request(for request: DetailPixelRequest) -> DetailRequest? {
        let sources = readResolvedSources()
        guard sources.raw != nil || sources.jpeg != nil || sources.heif != nil else { return nil }
        return DetailRequest(
            raw: sources.raw, jpeg: sources.jpeg, heif: sources.heif,
            displayPixels: request.displayPixels,
            wantsNativeResolution: request.need == .fullResolution,
            locationIdentity: locationIdentity,
            mode: request.mode == .rawFirst ? .rawFirst : .cameraPreviewFirst,
            screenPixels: request.screenPixels)
    }

    func regionRequest() -> RegionSharpnessRequest? {
        let sources = readResolvedSources()
        guard sources.raw != nil || sources.jpeg != nil || sources.heif != nil else { return nil }
        return RegionSharpnessRequest(
            raw: sources.raw, jpeg: sources.jpeg, heif: sources.heif,
            locationIdentity: locationIdentity)
    }

    func readResolvedSources() -> (raw: DetailSource?, jpeg: DetailSource?, heif: DetailSource?) {
        (
            raw.flatMap { try? DetailSource.read($0) },
            jpeg.flatMap { try? DetailSource.read($0) },
            heif.flatMap { try? DetailSource.read($0) }
        )
    }
}

extension PipelineDetailImages: DetailRegionSharpnessSource {
    func analyzeRegions(
        for photo: PhotoIdentity,
        group: [PhotoIdentity],
        nearby: [PhotoIdentity],
        onAutofocus: @escaping @Sendable (RegionSharpnessPathResult) -> Void
    ) async -> RegionSharpnessAnalysis? {
        await onUserActivity?()
        guard let currentSources = sources(for: photo) else { return nil }
        let groupSources = group.compactMap { identity in
            sources(for: identity).map { (identity, $0) }
        }
        let nearbySources = nearby.compactMap { identity in
            sources(for: identity).map { (identity, $0) }
        }
        return await admitted.sharpness { [regionScheduler, regionRequestTracker] in
            guard !Task.isCancelled, let current = currentSources.regionRequest() else {
                return nil
            }
            let groupPairs = groupSources.compactMap { identity, sources in
                sources.regionRequest().map { (identity, $0) }
            }
            let nearbyPairs = nearbySources.compactMap { identity, sources in
                sources.regionRequest().map { (identity, $0) }
            }
            let invalidated = await regionRequestTracker.update(
                with: [(photo, current)] + groupPairs + nearbyPairs)
            for urls in invalidated {
                await regionScheduler.invalidate(sources: urls)
            }
            guard !Task.isCancelled else { return nil }
            let groupRequests = groupPairs.map(\.1)
            let nearbyRequests = nearbyPairs.map(\.1)
            // Cancel analyses outside this detail window before admitting more work. A nearby
            // job that becomes current stays shared, including its stored early-AF answer.
            await regionScheduler.focus(
                current: current, group: groupRequests, nearby: nearbyRequests,
                cancellingObsolete: true)
            guard !Task.isCancelled else { return nil }
            async let analysis = regionScheduler.analyzeCurrent(
                current, onAutofocus: onAutofocus)
            await regionScheduler.submit(groupRequests, priority: .group)
            await regionScheduler.submit(nearbyRequests, priority: .nearby)
            return await analysis
        }
    }

    func beginInteractiveRender() -> UUID? {
        regionScheduler.beginInteractiveAcquisitionPause()
    }

    func endInteractiveRender(_ token: UUID?) {
        guard let token else { return }
        regionScheduler.endInteractiveAcquisitionPause(token)
    }

    func closeRegionAnalysis() async {
        await regionScheduler.close()
    }
}

private actor KnownRegionRequestTracker {
    private var known: [PhotoIdentity: RegionSharpnessRequest] = [:]

    func update(with entries: [(PhotoIdentity, RegionSharpnessRequest)]) -> [[URL]] {
        var invalidated: [[URL]] = []
        for (identity, request) in entries {
            if let previous = known[identity], previous != request {
                invalidated.append(previous.fileURLs)
            }
            known[identity] = request
        }
        return invalidated
    }
}
