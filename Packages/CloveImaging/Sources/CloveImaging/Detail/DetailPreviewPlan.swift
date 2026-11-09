/// One way to obtain preview pixels, in the order G1 "Preview, detail (I2)" prescribes.
enum DetailPreviewStep: Hashable, Sendable {
    /// The file's embedded, camera-rendered preview, capped at about 2000 px.
    ///
    /// ImageIO runs with both thumbnail-creation flags off, so this never decodes an
    /// original: a HIF is never fully decoded (G1 "Preview, detail (I2)").
    case embedded(DetailSource)
    /// Pixels decoded from a JPEG raster at the view's display size.
    ///
    /// This is the JPEG route, not a RAW route: it answers display-size and 100% requests
    /// for a JPEG-primary photo (G1 "Preview, detail (I2)").
    case displayRaster(DetailSource)

    var source: DetailSource {
        switch self {
        case .embedded(let source), .displayRaster(let source): source
        }
    }

    var quality: DetailQuality {
        switch self {
        case .embedded: .preview
        case .displayRaster: .raster
        }
    }

    /// The cache purpose keeps one preview route's pixels from answering another's, and
    /// keeps one display size's raster from being reused at a different size.
    func purpose(displayPixels: Int) -> DetailCachePurpose {
        switch self {
        case .embedded: .embeddedPreview
        case .displayRaster: .displayRaster(displayPixels)
        }
    }
}

/// The preview source order from G1 "Preview, detail (I2)", for one request.
///
/// The pipeline takes the first step that yields a usable image and stops there. It tries a
/// later source only when an earlier one cannot be opened, has no preview, or holds a preview
/// below ``minimumUsablePreviewPixels``. Pixel size never sends the plan onwards by itself:
/// more pixels for a zoomed or 100% view come from the RAW or full-JPEG route in
/// ``DetailPipeline/image(for:consumer:)``. A RAW render never happens here.
enum DetailPreviewPlan {
    /// Below this long edge an embedded preview is not a camera detail preview.
    ///
    /// The owner's A1 II and the ARW fixture expose 1616 px, S2's camera previews ranged from
    /// 1616 to 5472 px, and a generated HEIF thumbnail is 320 px. 1024 px sits under every
    /// camera preview measured so far, so a smaller one means "look at the next source"
    /// rather than "show this at full display width".
    static let minimumUsablePreviewPixels = 1024

    /// - RAW + HIF: the HIF's embedded preview.
    /// - RAW + HIF whose HIF cannot be opened, has no preview or is tiny: the RAW's.
    /// - RAW alone or RAW + JPEG: the RAW's embedded preview, then the JPEG at display size
    ///   when that preview is missing or tiny.
    /// - JPEG alone: the JPEG at display size.
    /// - HIF alone: the embedded preview only, at preview quality.
    static func steps(for request: DetailRequest) -> [DetailPreviewStep] {
        var steps: [DetailPreviewStep] = []
        if let raw = request.raw {
            if let heif = request.heif { steps.append(.embedded(heif)) }
            steps.append(.embedded(raw))
            if let jpeg = request.jpeg { steps.append(.displayRaster(jpeg)) }
        } else if let jpeg = request.jpeg {
            steps.append(.displayRaster(jpeg))
            // G1 §1: JPEG + HIF without a RAW is unsupported, so no special handling. The
            // generic rule is JPEG primary; a HIF's embedded preview is the fallback.
            if let heif = request.heif { steps.append(.embedded(heif)) }
        } else if let heif = request.heif {
            steps.append(.embedded(heif))
        }
        return steps
    }

    /// Whether a step's pixels are good enough to show and stop at.
    ///
    /// A display raster is decoded at the view's own size on purpose, so its size never sends
    /// the plan on to another source even when the file itself is small.
    static func isUsable(_ image: DetailImage, from step: DetailPreviewStep) -> Bool {
        switch step {
        case .embedded: image.longEdge >= minimumUsablePreviewPixels
        case .displayRaster: true
        }
    }
}
