import CloveCore
import CloveImaging
import CoreGraphics
import Foundation

/// The folder supplies session admission, so its security scope outlives every
/// read, including an uncancellable render draining after navigation.
struct DetailWorkAdmission: Sendable {
    let image: @Sendable (@Sendable () async -> DetailImageOutcome) async -> DetailImageOutcome
    let prefetch: @Sendable (@Sendable () async -> Void) async -> Void
}

extension DetailWorkAdmission {
    static let direct = DetailWorkAdmission(image: { await $0() }, prefetch: { await $0() })
}

@MainActor
final class PipelineDetailImages: DetailImageSource {
    private let pipeline: DetailPipeline
    private let thumbnails: ThumbnailCache?
    private let set: @MainActor (PhotoIdentity) -> PhotoSet?
    private let admitted: DetailWorkAdmission
    private let consumer = UUID()
    private var activeWindow: DetailPhotoWindow?
    private var navigationGeneration: UInt64 = 0

    init(
        pipeline: DetailPipeline,
        thumbnails: ThumbnailCache? = nil,
        set: @escaping @MainActor (PhotoIdentity) -> PhotoSet?,
        admitted: DetailWorkAdmission = .direct
    ) {
        self.pipeline = pipeline
        self.thumbnails = thumbnails
        self.set = set
        self.admitted = admitted
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
        navigationGeneration += 1
        let generation = navigationGeneration
        activeWindow = window
        await pipeline.beginNavigation(generation)
        guard !Task.isCancelled, activeWindow == window, generation == navigationGeneration,
            let current = sources(for: window.current.photo)
        else { return }
        _ = await admitted.image { [pipeline] in
            guard !Task.isCancelled,
                let request = current.request(for: window.request())
            else { return .deferred }
            await pipeline.navigate(to: request, generation: generation)
            return .deferred
        }
    }

    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        guard let sources = sources(for: photo) else { return .unavailable(.cannotOpen) }
        return await admitted.image { [pipeline, consumer] in
            guard let detailRequest = sources.request(for: request) else {
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

    /// Warm both embedded neighbours, then render exactly one ahead. The shared
    /// view calls this only after showing the current photo's screen result.
    func prefetch(_ window: DetailPhotoWindow, renderAhead: Bool) async {
        guard activeWindow == window else { return }
        let neighbours = window.neighbours.compactMap { neighbour -> (DetailRequest, Bool)? in
            guard let sources = sources(for: neighbour.photo),
                let request = sources.request(for: window.request())
            else { return nil }
            let ahead = neighbour.position == window.current.position + window.direction
            return (request, ahead)
        }
        await admitted.prefetch { [pipeline] in
            guard !Task.isCancelled else { return }
            await pipeline.prefetch(neighbours.map(\.0))
            guard renderAhead, !Task.isCancelled, let ahead = neighbours.first(where: \.1)?.0 else {
                return
            }
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
        let raw = raw.flatMap { try? DetailSource.read($0) }
        let jpeg = jpeg.flatMap { try? DetailSource.read($0) }
        let heif = heif.flatMap { try? DetailSource.read($0) }
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
