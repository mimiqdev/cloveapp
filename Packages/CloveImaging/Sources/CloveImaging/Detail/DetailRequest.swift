import Foundation

/// One image file of a photo set: where it lives and which revision of its bytes the
/// caller expects.
///
/// PRD P0-04 needs the photo's own pixels, and G1 "Scheduling and cache" requires a source
/// identity plus revision in every cache entry, so no result can come from another photo or
/// from a file rewritten after the request was built. This is the same source identity idea
/// I1 uses for the grid, without a dependency on the grid pipeline.
public struct DetailSource: Hashable, Sendable {
    /// The file's location. Detail only ever reads folders, never writes them (PRD P0-01).
    public let url: URL
    /// The size and modification time the caller saw when it built the request.
    public let revision: ThumbnailRevision

    /// Standardises the URL so equivalent spellings share one identity and one cache entry.
    public init(url: URL, revision: ThumbnailRevision) {
        self.url = url.standardizedFileURL
        self.revision = revision
    }

    /// Reads the current revision, bypassing cached URL resource values (as I1 does).
    public static func read(_ url: URL) throws -> DetailSource {
        DetailSource(url: url, revision: try ThumbnailRevision.read(from: url))
    }
}

/// Everything the detail pipeline needs about one photo (PRD P0-04).
///
/// `CloveImaging` does not depend on `CloveCore`, so a request carries file URLs and
/// revisions rather than domain types. The integration maps a C1 `PhotoSet` like this:
///
/// - `raw` — `set.primary` when its format is RAW, otherwise nil.
/// - `jpeg` — `set.jpegCompanion`, which is present only when RAW is primary.
/// - `heif` — `set.heifCompanion`; for a HIF-only set, the HIF primary itself.
/// - `displayPixels` — the detail view's current on-screen long edge in pixels, multiplied
///   by the current zoom scale (PRD P0-04 pinch zoom and 100%).
/// - `wantsNativeResolution` — true only for the explicit double-tap to 100% (PRD P0-04),
///   never for plain fit-view navigation.
/// - `locationIdentity` — the opened folder's stable identity, so the same path on another
///   card is a different source (G1 "Scheduling and cache").
///
/// A stale request is harmless: every read re-checks the revision and reports
/// ``DetailFailure/sourceChanged`` rather than showing pixels from a rewritten file.
public struct DetailRequest: Hashable, Sendable {
    /// The RAW file, the source of truth for native focus inspection (G1 decision 1).
    public let raw: DetailSource?
    /// The JPEG reference or primary, decoded as a raster only (never a RAW render).
    public let jpeg: DetailSource?
    /// The HIF/HEIF reference or primary; only its embedded preview is ever shown.
    public let heif: DetailSource?
    /// Long-edge pixels the view can show right now, including the zoom scale (PRD P0-04).
    public let displayPixels: Int
    /// The explicit double-tap to 100% (PRD P0-04), which may render native sensor pixels.
    public let wantsNativeResolution: Bool
    /// Stable folder/bookmark identity; distinguishes media mounted at the same path.
    public let locationIdentity: String

    /// Requires at least one file and a plausible display size; a set always has a primary.
    public init(
        raw: DetailSource? = nil, jpeg: DetailSource? = nil, heif: DetailSource? = nil,
        displayPixels: Int, wantsNativeResolution: Bool = false, locationIdentity: String
    ) {
        precondition(raw != nil || jpeg != nil || heif != nil, "A detail request needs a file")
        precondition((1...32_768).contains(displayPixels))
        self.raw = raw
        self.jpeg = jpeg
        self.heif = heif
        self.displayPixels = displayPixels
        self.wantsNativeResolution = wantsNativeResolution
        self.locationIdentity = locationIdentity
    }
}
