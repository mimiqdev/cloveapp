import CoreGraphics

/// Where delivered pixels came from (G1 "Preview, detail (I2)").
public enum DetailQuality: String, Sendable {
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
public enum DetailLimitation: String, Sendable {
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
public enum DetailFailure: String, Sendable {
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
    /// Whether the photo has a RAW, so 100% is its sensor pixels and never this bitmap's own
    /// (G1 decision 1; G1 "Preview, detail (I2)").
    ///
    /// A photo with a RAW is shown through an embedded preview that the detail route caps below the
    /// sensor's size, so the preview's own pixels are never what a double-tap to 100% means. A JPEG
    /// or HIF photo has no such larger source, so its pixels are its own 100%.
    public let hasRAW: Bool
    /// Set when these are the best pixels obtainable for the request (PRD P0-04).
    public let limitation: DetailLimitation?
    /// The photo's oriented full-resolution pixel size (PRD P0-04; G1 "Preview, detail (I2)"),
    /// or nil when it is not known.
    ///
    /// This is the size 100% means, so an embedded preview and the RAW render that replaces it
    /// answer the same scale and the view does not zoom a second time when the render lands. A
    /// render always carries its own size, because those pixels are native by definition. Nil
    /// means the size could not be read; ``fullResolutionPixels`` says what that leaves.
    public let fullResolutionSize: CGSize?

    public init(
        image: CGImage, source: DetailSource, quality: DetailQuality, hasRAW: Bool,
        limitation: DetailLimitation? = nil, fullResolutionSize: CGSize? = nil
    ) {
        self.image = image
        self.source = source
        self.quality = quality
        self.hasRAW = hasRAW
        self.limitation = limitation
        self.fullResolutionSize = fullResolutionSize
    }

    public var width: Int { image.width }
    public var height: Int { image.height }

    /// The size 100% means for this photo, or nil while it is unknown (PRD P0-04; G1 "Preview,
    /// detail (I2)").
    ///
    /// A photo without a RAW falls back to its shown bitmap's 100% when its size is unknown, which
    /// is the behaviour before the native size was known: a HIF is never fully decoded, so its
    /// preview is all there is, and a JPEG whose header cannot be read is its own full resolution.
    ///
    /// A photo with a RAW has no such fallback. Its 100% is the sensor's pixels, which are not the
    /// preview's: a RAW is never smaller than its embedded preview, and the detail preview is capped
    /// below the sensor's size. An unknown size therefore answers nil, and the view waits for the
    /// render's own size instead of zooming to the preview's pixels (#111).
    public var fullResolutionPixels: CGSize? {
        fullResolutionSize ?? (hasRAW ? nil : CGSize(width: width, height: height))
    }

    /// Decoded size of this bitmap, the cost figure the detail cache budgets (S2 measured
    /// row bytes rather than assuming four bytes per pixel).
    public var decodedBytes: Int { image.bytesPerRow * image.height }

    /// Longest side in pixels, which is what a display-size request is compared against.
    var longEdge: Int { max(width, height) }

    /// Whether these pixels are the best this photo's route can deliver (PRD P0-04; G1
    /// "Preview, detail (I2)").
    ///
    /// This answers whether asking for more pixels can help. A native RAW render is the photo's
    /// own pixels. A raster is final when it reaches the photo's size, allowing one pixel for
    /// rounding in the fit geometry, or when it reaches the raster decode limit, beyond which no
    /// display request can produce a larger bitmap. Below that limit, a raster whose native size
    /// is unknown is not final: it is a display raster, and the route behind it — a RAW render,
    /// for one — may still deliver more. A preview is never final when it could render; a preview
    /// whose native size is unknown still asks, because the render supplies the size the read
    /// could not.
    public var isBestAvailable: Bool {
        switch quality {
        case .nativeRAW:
            return true
        case .raster:
            if longEdge >= DetailPixelLimit.maximumEdge { return true }
            guard let fullResolutionSize else { return false }
            let nativeLongEdge = max(fullResolutionSize.width, fullResolutionSize.height)
            return CGFloat(longEdge) + 1 >= nativeLongEdge
        case .preview:
            return false
        }
    }

    func limited(by limitation: DetailLimitation) -> DetailImage {
        DetailImage(
            image: image, source: source, quality: quality, hasRAW: hasRAW,
            limitation: self.limitation ?? limitation, fullResolutionSize: fullResolutionSize)
    }

    /// The same pixels with the request's 100% answer attached (PRD P0-04; G1 "Preview, detail
    /// (I2)").
    ///
    /// A cached bitmap can outlive the request that stored it: a HIF companion has its own cache
    /// identity while the photo's size and its RAW come from the set. The current request's answer
    /// therefore replaces the stored one, including nil and no RAW for a request with no larger
    /// size to report.
    func withFullResolution(_ size: CGSize?, hasRAW: Bool) -> DetailImage {
        DetailImage(
            image: image, source: source, quality: quality, hasRAW: hasRAW,
            limitation: limitation, fullResolutionSize: size)
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
