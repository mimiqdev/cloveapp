import CloveCore
import CoreGraphics

/// What one grid cell's thumbnail request produced (PRD Grid, P0-03).
enum GridThumbnailOutcome: Sendable {
    /// Decoded pixels with EXIF orientation already applied. A cell never transforms them again,
    /// matching I1's `Thumbnail` contract (G1 preview row).
    case image(CGImage)

    /// Nothing usable can be drawn for the photo, so the cell shows its unreadable state and
    /// never a blank image presented as loaded (PRD Scan scope).
    case unavailable

    /// The request could not run now: I1's queue was full, its pipeline closed, or the request
    /// was superseded (G1 scheduling row). The cell keeps its loading state and asks again,
    /// because the file itself may be perfectly readable.
    case deferred
}

/// How urgent one grid thumbnail request is (PRD P0-03, G1 scheduling row).
enum GridThumbnailPriority: Sendable {
    /// The cell is on screen now.
    case visible

    /// The collection view expects the cell soon. I1 lets visible work displace it (G1
    /// scheduling row), and the grid cancels it when the cell scrolls away.
    case prefetch
}

/// The reference companions a photo set carries, drawn as a cell badge (PRD Grid).
///
/// The badge names what the set holds beside its primary file, so a RAW photo with a JPEG or a
/// HIF companion is recognisable in the grid. The pixel source is the primary file either way
/// (G1 preview row), so this value only describes the set.
struct GridCompanions: Hashable, Sendable {
    /// Whether the set has a JPEG companion.
    var hasJPEG: Bool

    /// Whether the set has a HIF companion.
    var hasHEIF: Bool

    /// Collects one set's companions; none by default.
    init(hasJPEG: Bool = false, hasHEIF: Bool = false) {
        self.hasJPEG = hasJPEG
        self.hasHEIF = hasHEIF
    }

    /// The badge's text, or nil when the set has no companion to name (PRD Grid).
    var badgeText: String? {
        switch (hasJPEG, hasHEIF) {
        case (true, true): "JPEG+HIF"
        case (true, false): "JPEG"
        case (false, true): "HIF"
        case (false, false): nil
        }
    }
}

/// The grid's one window on the folder's files (PRD Grid, P0-03, G1 preview row).
///
/// A cell needs two facts the browsing model does not carry: the preview pixels for a photo and
/// the reference companions its badge names. This small main-actor seam supplies both by
/// ``PhotoIdentity``, so the grid never reaches into the folder library, the scan or a file
/// path, and a build with sample photos can draw generated tiles instead of decoding files.
///
/// A request cancelled by its caller may finish anyway: implementations only promise the
/// result, and the cell discards an outcome it no longer needs. The test library has one
/// implementation and the real folder another (``PipelineGridThumbnails``).
@MainActor
protocol GridThumbnailSource: AnyObject {
    /// Synchronously returns a memory-cached thumbnail outcome when available so warm cells build once.
    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome?

    /// Requests the photo's grid thumbnail at the G1 preview row's embedded-preview size.
    ///
    /// The request is safe to cancel. A cell cancels its request when it scrolls away, and the
    /// grid cancels prefetch requests the collection view no longer expects (PRD P0-03).
    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority)
        async -> GridThumbnailOutcome

    /// The companions the photo's set holds (PRD Grid).
    ///
    /// It answers synchronously from what the scan already found, so a cell draws its badge
    /// together with the photo's marks.
    func companions(for photo: PhotoIdentity) -> GridCompanions
}

extension GridThumbnailSource {
    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? { nil }
}
