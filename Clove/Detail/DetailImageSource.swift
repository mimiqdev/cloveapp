import CloveCore
import CloveImaging

/// What one detail image request produced (PRD P0-04, G1 "Preview, detail (I2)").
enum DetailImageOutcome: Sendable {
    /// Usable pixels, with their quality and any shortfall the view must explain (PRD P0-04).
    case image(DetailImage)

    /// Nothing usable can be drawn for the photo, so the view shows that state and never a
    /// blank image presented as loaded (PRD Scan scope).
    case unavailable(DetailFailure)

    /// The request could not run now: the pipeline was full or closed, or the request was
    /// superseded. The file may be perfectly readable, so the view keeps its loading state and
    /// asks again a bounded number of times (G1 "Scheduling and cache").
    case deferred
}

/// How many pixels the detail view needs, and why (PRD P0-04; G1 "Preview, detail (I2)").
///
/// The screen computes `displayPixels` from the image's on-screen long edge times the current
/// zoom scale, so a fit view never asks the pipeline to render a RAW just because the screen is
/// taller than the preview. ``Need`` keeps the one render decision explicit: only ``morePixels``
/// and ``fullResolution`` may reach I2's render lane.
struct DetailPixelRequest: Hashable, Sendable {
    /// Why the view needs these pixels.
    enum Need: Hashable, Sendable {
        /// Fit-view pixels only; I2 never renders a RAW for this (PRD P0-04 full-width preview).
        case preview

        /// A pinch needs more pixels than the preview holds (G1 "Preview, detail (I2)").
        case morePixels

        /// The explicit double-tap to 100%, the only request that asks for native resolution
        /// (PRD P0-04, G1 "Preview, detail (I2)").
        case fullResolution
    }

    /// The image's long edge in device pixels at the current zoom scale.
    let displayPixels: Int

    /// Why the view needs them.
    let need: Need

    /// Keeps the request inside I2's accepted range, because a view can report a zero size
    /// before its first layout.
    init(displayPixels: Int, need: Need) {
        self.displayPixels = min(max(displayPixels, 1), 32_768)
        self.need = need
    }
}

/// The detail screen's one window on a photo's pixels (PRD P0-04, G1 "Preview, detail (I2)").
///
/// A detail view needs pixels by ``PhotoIdentity`` and nothing else: not a file path, the scan
/// or the folder library. This small main-actor seam mirrors the grid's ``GridThumbnailSource``,
/// so the real folder can answer from I2's pipeline bound to C11's session while the test
/// library draws generated images and touches no file.
///
/// The request is safe to cancel: a screen that moves to another photo cancels the task waiting
/// on this call, and I2 drops the work it superseded. Implementations only promise an outcome;
/// a caller that no longer wants it discards the result.
@MainActor
protocol DetailImageSource: AnyObject {
    /// Asks for the photo's pixels at the requested size (PRD P0-04).
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome

    /// Fills the preview cache with the photos the view may open next (G1 "Scheduling and
    /// cache"). The work is embedded previews only, never a render, and is the first dropped.
    func prefetch(_ photos: [PhotoIdentity], displayPixels: Int) async

    /// Drops queued neighbour prefetch so it never competes with the photo on screen.
    func cancelPrefetch() async
}

extension DetailImageSource {
    func prefetch(_ photos: [PhotoIdentity], displayPixels: Int) async {}

    func cancelPrefetch() async {}
}

/// A library with no open folder has no detail pixels to show (PRD P0-04).
///
/// The empty test library and a real library before its first open answer with this source,
/// so a reachable detail view shows its unavailable state instead of decoding a file.
@MainActor
final class EmptyDetailImages: DetailImageSource {
    func image(for photo: PhotoIdentity, request: DetailPixelRequest) async -> DetailImageOutcome {
        .unavailable(.noUsablePreview)
    }
}
