import Foundation

/// One photo's feature request: which file, which revision, which preview size and which folder.
///
/// `CloveImaging` does not depend on `CloveCore`, so this carries the primary file (the RAW for
/// a RAW set, as I1 does), its revision, the folder identity and the preview size rather than a
/// C1 `PhotoSet` (PRD P0-11).
public struct ImageFeatureRequest: Hashable, Sendable {
    /// The 400 px grid preview I1 extracts, reused here so a feature never reads its own copy.
    public let preview: ThumbnailRequest

    /// Wraps an existing grid request, so a feature and its thumbnail share one identity.
    public init(preview: ThumbnailRequest) {
        self.preview = preview
    }

    /// The grid's default: 400 px long edge, the size G1 "Grouping (C9/I3)" compares at.
    public init(
        source: URL, revision: ThumbnailRevision, locationIdentity: String,
        previewPixels: Int = 400
    ) {
        self.init(
            preview: ThumbnailRequest(
                source: source, revision: revision, targetPixels: previewPixels,
                locationIdentity: locationIdentity))
    }

    /// The primary file: a RAW for a RAW set, one read per photo (G1 decision 1).
    public var source: URL { preview.source }

    /// Stable folder identity, used to cancel a folder's work when it closes (PRD P0-11).
    public var folderIdentity: String { preview.locationIdentity }
}
