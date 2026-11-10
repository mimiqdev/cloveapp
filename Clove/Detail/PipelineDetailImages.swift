import CloveCore
import CloveImaging
import Foundation

/// Admits detail work through the folder's C11 session (G1 folder access).
///
/// The folder library supplies both closures, so ending the folder waits for a read instead of
/// releasing the scope under it. They are separate because a stored property cannot hold a
/// generic closure: one carries an image outcome and one is preview-only work.
struct DetailWorkAdmission: Sendable {
    /// Runs one image request inside the session, or answers unavailable after it closed.
    let image: @Sendable (@Sendable () async -> DetailImageOutcome) async -> DetailImageOutcome
    /// Runs preview-only work inside the same session.
    let prefetch: @Sendable (@Sendable () async -> Void) async -> Void
}

extension DetailWorkAdmission {
    /// Runs work straight through, for a caller that holds no folder session.
    static let direct = DetailWorkAdmission(
        image: { await $0() },
        prefetch: { await $0() })
}

/// Detail pixels from I2's pipeline for one folder's scanned photo sets
/// (G1 "Preview, detail (I2)" and "Scheduling and cache").
///
/// The folder owns the pipeline and C11's session, so the caller supplies a lookup from a
/// photo's identity to its scanned set. The source never reaches into the folder library: a
/// folder that closed its pipeline stops answering, and the library's admitted-work closure
/// answers unavailable for a photo from an earlier folder (G1 folder-access row).
///
/// Every request uses one consumer, because one detail view is on screen at a time. I2 uses that
/// to supersede an older request for the same view, so the preview a fast edge tap asked for can
/// never paint over the 100% render that replaced it. Prefetch and neighbour reads never render
/// (``DetailPipeline/prefetch(_:)``), so a swipe to the next photo stays cheap.
@MainActor
final class PipelineDetailImages: DetailImageSource {
    private let pipeline: DetailPipeline
    private let set: @MainActor (PhotoIdentity) -> PhotoSet?
    private let admitted: DetailWorkAdmission
    private let consumer = UUID()

    /// Uses one folder's pipeline and the folder's lookup from identity to scanned set.
    ///
    /// The folder library passes work admission through its C11 session, so ending the folder
    /// waits for a read instead of releasing the scope under it. A caller with no session passes
    /// ``DetailWorkAdmission/direct``.
    init(
        pipeline: DetailPipeline,
        set: @escaping @MainActor (PhotoIdentity) -> PhotoSet?,
        admitted: DetailWorkAdmission = .direct
    ) {
        self.pipeline = pipeline
        self.set = set
        self.admitted = admitted
    }

    /// Reads the photo's files and asks I2 for preview or render pixels (G1 detail row).
    ///
    /// The revisions are read inside the admitted closure, off the main actor, because both
    /// stats ask the file system and a card must never stall the detail screen. A file that
    /// disappeared between the scan and the request is dropped; a set with no readable file
    /// answers unavailable rather than a blank image (PRD Scan scope).
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
                case .morePixels, .fullResolution:
                    result = try await pipeline.image(for: detailRequest, consumer: consumer)
                }
                switch result {
                case .available(let image):
                    return .image(image)
                case .unavailable(let failure):
                    return .unavailable(failure)
                }
            } catch {
                // A superseded request or a closed pipeline may be perfectly readable later;
                // the screen keeps its preview and asks again only within its retry bound.
                return .deferred
            }
        }
    }

    /// Fills I2's cache with the neighbours' embedded previews (G1 "Scheduling and cache").
    ///
    /// The whole prefetch is admitted through C11's session, so ending the folder waits for the
    /// reads it started. The requests never render.
    func prefetch(_ photos: [PhotoIdentity], displayPixels: Int) async {
        let requests = photos.compactMap { photo -> DetailRequest? in
            guard let sources = sources(for: photo) else { return nil }
            return sources.request(
                for: DetailPixelRequest(displayPixels: displayPixels, need: .preview))
        }
        guard !requests.isEmpty else { return }
        await admitted.prefetch { [pipeline] in
            await pipeline.prefetch(requests)
        }
    }

    /// Drops queued prefetch so it never competes with the photo on screen (G1 scheduling).
    func cancelPrefetch() async {
        await pipeline.cancelPrefetch()
    }

    /// The photo's image files, resolved on the main actor because the lookup reads the folder's
    /// store. `CloveImaging` does not depend on `CloveCore`, so the URLs cross into the
    /// admitted work rather than the scanned set.
    private func sources(for photo: PhotoIdentity) -> PhotoSources? {
        guard let set = set(photo) else { return nil }
        return PhotoSources(set: set)
    }
}

/// One photo's role-tagged file URLs and the folder identity I2 keys its cache by
/// (``DetailRequest``).
private struct PhotoSources: Sendable {
    var raw: URL?
    var jpeg: URL?
    var heif: URL?
    var locationIdentity: String

    /// Takes the primary and companions in G1 decision 1's roles.
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

    /// Builds I2's request with the revision each readable file has now.
    ///
    /// A file whose revision cannot be read is left out, so a set with no readable file has no
    /// request rather than a request I2 would refuse at its precondition.
    func request(for request: DetailPixelRequest) -> DetailRequest? {
        let raw = raw.flatMap { try? DetailSource.read($0) }
        let jpeg = jpeg.flatMap { try? DetailSource.read($0) }
        let heif = heif.flatMap { try? DetailSource.read($0) }
        guard raw != nil || jpeg != nil || heif != nil else { return nil }
        return DetailRequest(
            raw: raw, jpeg: jpeg, heif: heif, displayPixels: request.displayPixels,
            wantsNativeResolution: request.need == .fullResolution,
            locationIdentity: locationIdentity)
    }
}
