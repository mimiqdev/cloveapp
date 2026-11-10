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

    private let pipeline: ThumbnailPipeline
    private let set: @MainActor (PhotoIdentity) -> PhotoSet?

    /// Uses one folder's pipeline and the folder's lookup from identity to scanned set.
    init(pipeline: ThumbnailPipeline, set: @escaping @MainActor (PhotoIdentity) -> PhotoSet?) {
        self.pipeline = pipeline
        self.set = set
    }

    /// The companions the set holds beside its primary file (PRD Grid).
    func companions(for photo: PhotoIdentity) -> GridCompanions {
        guard let set = set(photo) else { return GridCompanions() }
        return GridCompanions(
            hasJPEG: set.jpegCompanion != nil, hasHEIF: set.heifCompanion != nil)
    }

    /// Asks I1 for the primary file's embedded preview (G1 preview row).
    ///
    /// Reading the file's size and modification time is what I1's revision check needs, and it
    /// runs off the main actor: both calls ask the file system, and PRD P0-03 puts smooth
    /// scrolling before decoding, so a slow card must never stall the grid. A file that is
    /// already gone then reports unavailable, without taking a queue slot (PRD Scan scope).
    /// I1's queue pressure, a closed pipeline and a superseded request are deferred instead:
    /// the file may be readable and the cell asks again (G1 scheduling row).
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority)
        async -> GridThumbnailOutcome
    {
        guard let set = set(photo) else { return .unavailable }
        let source = set.primary.url
        guard
            let revision = await Task.detached(
                priority: .userInitiated,
                operation: {
                    try? ThumbnailRevision.read(from: source)
                }
            ).value
        else {
            return .unavailable
        }
        let request = ThumbnailRequest(
            source: source, revision: revision, targetPixels: Self.targetPixels,
            locationIdentity: photo.folderID.rawValue)
        do {
            switch try await pipeline.thumbnail(for: request, priority: priority.pipeline) {
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
