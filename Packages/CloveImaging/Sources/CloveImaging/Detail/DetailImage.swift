import CoreGraphics

/// The colour source and resolution of delivered pixels.
public enum DetailQuality: String, Sendable {
    case preview
    case raster
    case screenRAW
    case nativeRAW
}

public enum DetailLimitation: String, Sendable {
    case rawRenderFailed
    case noHigherResolution
}

/// Cancellation throws CancellationError instead of reporting an image failure.
public enum DetailFailure: String, Sendable {
    case cannotOpen
    case noUsablePreview
    case sourceChanged
}

/// Oriented pixels, their source revision, and the size that native 100% means.
/// Screen RAW and camera previews report the full source size before zooming, so
/// replacing pixels sharpens the image without changing the zoom a second time.
public struct DetailImage: Sendable {
    public let image: CGImage
    public let source: DetailSource
    public let quality: DetailQuality
    public let hasRAW: Bool
    public let limitation: DetailLimitation?
    /// Nil when a reliable full size could not be read. A RAW's embedded bitmap
    /// must never stand in for its sensor's 100%.
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
    public var fullResolutionPixels: CGSize? {
        fullResolutionSize ?? (hasRAW ? nil : CGSize(width: width, height: height))
    }
    public var decodedBytes: Int { image.bytesPerRow * image.height }
    var longEdge: Int { max(width, height) }

    /// Whether asking this route for more pixels can help.
    public var isBestAvailable: Bool {
        switch quality {
        case .nativeRAW:
            return true
        case .raster:
            if longEdge >= DetailPixelLimit.maximumEdge { return true }
            guard let fullResolutionSize else { return false }
            return CGFloat(longEdge) + 1 >= max(fullResolutionSize.width, fullResolutionSize.height)
        case .preview, .screenRAW:
            return false
        }
    }

    func limited(by limitation: DetailLimitation) -> DetailImage {
        DetailImage(
            image: image, source: source, quality: quality, hasRAW: hasRAW,
            limitation: self.limitation ?? limitation, fullResolutionSize: fullResolutionSize)
    }

    /// A companion preview can serve more than one set. Its cached pixels must
    /// carry this request's full-size answer, including an unknown answer.
    func withFullResolution(_ size: CGSize?, hasRAW: Bool) -> DetailImage {
        DetailImage(
            image: image, source: source, quality: quality, hasRAW: hasRAW,
            limitation: limitation, fullResolutionSize: size)
    }
}

public enum DetailResult: Sendable {
    case available(DetailImage)
    case unavailable(DetailFailure)
}

public enum DetailPriority: Sendable, Hashable {
    case visible
    case prefetch
}
