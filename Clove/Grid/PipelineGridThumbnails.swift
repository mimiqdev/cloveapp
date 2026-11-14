import CloveCore
import CloveImaging
import Foundation

/// Grid thumbnails from I1's pipeline for a folder's scanned photo sets (G1 preview and
/// scheduling rows).
///
/// The folder owns the scan and the pipeline, so the caller supplies a lookup from a photo's
/// identity to its set. This type never reaches into the folder library, and a folder that
/// closes its pipeline simply stops answering requests. The request reads the set's primary
/// file, which is the RAW when there is one, so a RAW + HIF photo decodes once from the RAW's
/// embedded preview and never fully decodes a HIF (G1 preview row).
///
/// I1's revision guard is kept: a file that changed while its preview decoded answers
/// unavailable rather than showing stale pixels. A cancelled or superseded request also ends
/// here, and the cell ignores the outcome because it is no longer on screen.
@MainActor
final class PipelineGridThumbnails: GridThumbnailSource {
    /// The grid preview size from the G1 preview row's embedded preview at about 400 px.
    static let targetPixels = 400

    /// One request's file reads and decode, so a folder can admit them through C11's session
    /// (G1 folder access).
    typealias AdmittedWork = @Sendable () async -> GridThumbnailOutcome

    private let pipeline: ThumbnailPipeline
    private let set: @MainActor (PhotoIdentity) -> PhotoSet?
    private let scannedSet: (@MainActor (PhotoIdentity) -> ScannedPhotoSet?)?
    private let admitted: @Sendable (AdmittedWork) async -> GridThumbnailOutcome

    /// Uses one folder's pipeline and the folder's lookup from identity to scanned set.
    ///
    /// The folder library passes a closure that admits the request through its C11 session, so
    /// ending the folder waits for a decode instead of releasing the scope under it. A caller
    /// with no session passes the work straight through.
    init(
        pipeline: ThumbnailPipeline,
        set: @escaping @MainActor (PhotoIdentity) -> PhotoSet?,
        scannedSet: (@MainActor (PhotoIdentity) -> ScannedPhotoSet?)? = nil,
        admitted: @escaping @Sendable (AdmittedWork) async -> GridThumbnailOutcome = {
            await $0()
        }
    ) {
        self.pipeline = pipeline
        self.set = set
        self.scannedSet = scannedSet
        self.admitted = admitted
    }

    /// The companions the set holds beside its primary file (PRD Grid).
    func companions(for photo: PhotoIdentity) -> GridCompanions {
        guard let resolvedSet = scannedSet?(photo)?.photoSet ?? set(photo) else {
            return GridCompanions()
        }
        return GridCompanions(
            hasJPEG: resolvedSet.jpegCompanion != nil, hasHEIF: resolvedSet.heifCompanion != nil)
    }

    /// Synchronously returns an already-cached thumbnail from memory when the scan revision is known.
    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? {
        guard let source = primaryRequestSource(for: photo), let revision = source.revision else {
            return nil
        }
        let request = ThumbnailRequest(
            source: source.url, revision: revision, targetPixels: Self.targetPixels,
            locationIdentity: photo.folderID.rawValue)
        guard let cached = pipeline.cachedResult(for: request) else { return nil }
        switch cached {
        case .available(let thumbnail):
            return .image(thumbnail.image)
        case .unavailable:
            return .unavailable
        }
    }

    /// Asks I1 for the primary file's embedded preview (G1 preview row).
    ///
    /// When the scan already captured the primary file's size and modification date, the revision
    /// is reused directly; otherwise reading falls back onto `ImageWorkExecutor` off the main
    /// actor and cooperative pool.
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority)
        async -> GridThumbnailOutcome
    {
        guard let source = primaryRequestSource(for: photo) else { return .unavailable }
        let targetPixels = Self.targetPixels
        let pipelinePriority = priority.pipeline
        // G1 folder access holds the scope until the work that relies on it drains, so any
        // revision read and the decode both run inside the closure the folder supplies.
        return await admitted { [pipeline] in
            let revision: ThumbnailRevision
            if let prefetched = source.revision {
                revision = prefetched
            } else if let read = try? await ThumbnailRevision.readOnImageWork(
                from: source.url, priority: pipelinePriority)
            {
                revision = read
            } else {
                return .unavailable
            }
            let request = ThumbnailRequest(
                source: source.url, revision: revision, targetPixels: targetPixels,
                locationIdentity: photo.folderID.rawValue)
            do {
                switch try await pipeline.thumbnail(for: request, priority: pipelinePriority) {
                case .available(let thumbnail):
                    return .image(thumbnail.image)
                case .unavailable:
                    return .unavailable
                }
            } catch {
                return .deferred
            }
        }
    }

    private func primaryRequestSource(for photo: PhotoIdentity) -> (
        url: URL, revision: ThumbnailRevision?
    )? {
        if let scanned = scannedSet?(photo) {
            let primaryURL = scanned.photoSet.primary.url
            let primaryFile =
                scanned.imageFiles.first { $0.file.url == primaryURL }
                ?? (scanned.imageFiles.first?.file == scanned.photoSet.primary
                    ? scanned.imageFiles.first : nil)
            let revision: ThumbnailRevision? =
                if let size = primaryFile?.size,
                    let modificationDate = primaryFile?.modificationDate
                {
                    ThumbnailRevision(size: Int64(size), modificationTime: modificationDate)
                } else {
                    nil
                }
            return (primaryURL, revision)
        }
        guard let url = set(photo)?.primary.url else { return nil }
        return (url, nil)
    }
}

private extension GridThumbnailPriority {
    /// I1's priority for one grid request, mapped so the grid names its own urgency (G1
    /// scheduling row).
    var pipeline: ThumbnailPriority {
        switch self {
        case .visible: .visible
        case .prefetch: .prefetch
        }
    }
}
