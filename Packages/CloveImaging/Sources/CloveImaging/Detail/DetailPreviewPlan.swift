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
/// The steps are tried in order and the pipeline keeps the first result that covers the
/// view's pixel size, otherwise the largest one it saw. This keeps a camera preview ahead
/// of a generated raster even when both would fit, and never renders a RAW here.
enum DetailPreviewPlan {
    /// - RAW + HIF: the HIF's embedded preview.
    /// - RAW + HIF whose HIF has no usable preview: the RAW's embedded preview.
    /// - RAW alone or RAW + JPEG: the RAW's embedded preview, then the JPEG at display size
    ///   when that preview is missing or too small for the view.
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
}
