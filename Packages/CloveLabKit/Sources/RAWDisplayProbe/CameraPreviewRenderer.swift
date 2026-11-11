import CoreGraphics
import Foundation
import ImageIO

/// Decodes one camera HEIF variant: the 100% source the camera-preview mode needs.
///
/// A HIF is rendered camera HEIF, not RAW. S2 measured the CIRAWFilter control at
/// about 1.8 s and a large working set, so these variants use ImageIO, the route the
/// application uses for previews, and add no color management of their own.
public final class CameraPreviewRenderer: @unchecked Sendable {
    public init() {}

    /// One timed decode. Errors are recorded in `timing.error`, not thrown.
    public func render(url: URL, variant: CameraPreviewVariant) throws -> DisplayRenderTiming {
        try measureDisplay {
            try decode(url: url, variant: variant)
        }
    }

    /// The decoded bitmap for a colour comparison. Untimed.
    public func image(url: URL, variant: CameraPreviewVariant) throws -> CGImage {
        try Task.checkCancellation()
        return try decode(url: url, variant: variant).image
    }

    private func decode(
        url: URL, variant: CameraPreviewVariant
    ) throws -> (image: CGImage, native: CGSize) {
        try Task.checkCancellation()
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw RAWDisplayFailure.cannotRender }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let native = CGSize(width: width, height: height)
        let image: CGImage?
        switch variant.kind {
        case .fullDecode:
            image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        case .subsample(let factor):
            image = CGImageSourceCreateImageAtIndex(
                source, 0,
                [
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceSubsampleFactor: max(1, factor),
                ] as CFDictionary)
        case .screenThumbnail(let longEdge):
            guard longEdge > 0 else { throw RAWDisplayFailure.cannotRender }
            // FromImageAlways decodes the full image instead of returning a built-in
            // thumbnail, which is what a chessboard-free 100% source needs.
            image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceThumbnailMaxPixelSize: longEdge,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                ] as CFDictionary)
        }
        guard let image else { throw RAWDisplayFailure.cannotRender }
        return (image, native)
    }
}
