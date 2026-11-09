import CoreGraphics

/// Where delivered pixels came from (G1 "Preview, detail (I2)").
public enum DetailQuality: String, CaseIterable, Sendable {
    /// A camera-rendered preview embedded in a RAW or HIF file.
    ///
    /// G1 "Preview, detail (I2)": the HIF's embedded preview is shown first for RAW + HIF,
    /// and a HIF is never fully decoded. On the owner's camera this stops at 1616 px, so
    /// preview quality alone never satisfies native focus inspection.
    case preview
    /// Pixels decoded from a JPEG file: at display size, or at the file's own size for 100%.
    ///
    /// G1 "Preview, detail (I2)": a JPEG-primary photo answers 100% with a bounded raster
    /// decode of the full JPEG, not a RAW render.
    case raster
    /// Native sensor pixels rendered by `CIRAWFilter` (G1 "Preview, detail (I2)").
    case nativeRAW
}

/// Why the delivered pixels fall short of what the request asked for.
///
/// PRD P0-04 requires a visible explanation instead of a blank image or a silent swap, so a
/// shortfall is always reported with the pixels that stand in for it.
public enum DetailLimitation: String, CaseIterable, Sendable {
    /// The full RAW render failed; the preview stays the best result (G1 "Preview, detail").
    case rawRenderFailed
    /// No route supplies more pixels: a HIF is never fully decoded (G1 "Preview, detail"),
    /// and a raster source cannot exceed its own resolution.
    case noHigherResolution
}

/// Why no pixels could be delivered at all.
///
/// These are explicit states, never a blank image (PRD Supported files: "a blank preview
/// must not be presented as loaded"). Cancellation is not a failure: a cancelled or
/// superseded request throws `CancellationError` instead.
public enum DetailFailure: String, CaseIterable, Sendable {
    /// The file could not be opened as an image, for example a truncated or foreign file.
    case cannotOpen
    /// The file opened but holds no preview the pipeline may show without an unbounded
    /// full decode: G1 "Preview, detail (I2)" forbids fully decoding a HIF, and a RAW is
    /// only rendered once a preview is available.
    case noUsablePreview
    /// A file no longer matches the revision the request carries, so its pixels must not be
    /// returned (G1 "Scheduling and cache"; I1's revision check).
    case sourceChanged
}

/// Pixels for one detail view, with the identity and quality of what is being shown.
///
/// ```swift
/// switch try await pipeline.image(for: request, consumer: viewID) {
/// case .available(let shown):
///     layer.contents = shown.image
///     if let limitation = shown.limitation { status.show(limitation) }
/// case .unavailable(let failure):
///     status.show(failure)
/// }
/// ```
public struct DetailImage: Sendable {
    /// Pixels with EXIF orientation already applied; consumers must not transform again.
    public let image: CGImage
    /// The file these pixels came from, with the revision they were read at.
    public let source: DetailSource
    /// Whether these are camera preview, raster, or native sensor pixels.
    public let quality: DetailQuality
    /// Set when these are the best pixels obtainable for the request (PRD P0-04).
    public let limitation: DetailLimitation?

    public init(
        image: CGImage, source: DetailSource, quality: DetailQuality,
        limitation: DetailLimitation? = nil
    ) {
        self.image = image
        self.source = source
        self.quality = quality
        self.limitation = limitation
    }

    public var width: Int { image.width }
    public var height: Int { image.height }
    /// Decoded size of this bitmap, the cost figure the detail cache budgets (S2 measured
    /// row bytes rather than assuming four bytes per pixel).
    public var decodedBytes: Int { image.bytesPerRow * image.height }

    /// Longest side in pixels, which is what a display-size request is compared against.
    var longEdge: Int { max(width, height) }

    func limited(by limitation: DetailLimitation) -> DetailImage {
        DetailImage(
            image: image, source: source, quality: quality,
            limitation: self.limitation ?? limitation)
    }
}

/// The outcome of one detail read: usable pixels or one explicit reason there are none.
public enum DetailResult: Sendable {
    case available(DetailImage)
    case unavailable(DetailFailure)
}

/// Ordering between the photo being inspected and speculative neighbour work.
public enum DetailPriority: Sendable, Hashable {
    /// The photo on screen; served before prefetch (G1 "Scheduling and cache").
    case visible
    /// A neighbour the view may open next; embedded previews only, dropped first.
    case prefetch
}
