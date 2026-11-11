import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Decodes one camera HEIF variant: the 100% source the camera-preview mode needs.
///
/// A HIF is rendered camera HEIF, not RAW. S2 measured the CIRAWFilter control at
/// about 1.8 s and a large working set, so these variants use ImageIO, the route the
/// application uses for previews, and add no color management of their own.
///
/// Orientation is a display transform in production, so it is not part of the timed
/// decode. The reported size is still display-oriented: the edges are swapped for
/// orientations 5–8, which costs no pixel work, and every report row is tagged with
/// the source orientation.
public final class CameraPreviewRenderer: @unchecked Sendable {
    public init() {}

    /// One timed decode. Errors are recorded in `timing.error`, not thrown.
    public func render(url: URL, variant: CameraPreviewVariant) throws -> DisplayRenderTiming {
        var decodedOrientation = 1
        var swapsEdges = false
        var timing = try autoreleasepool {
            try measureDisplay {
                let decoded = try decode(url: url, variant: variant)
                decodedOrientation = decoded.orientation
                swapsEdges = decoded.needsOrientation && decoded.orientation >= 5
                return (decoded.image, decoded.native)
            }
        }
        timing.orientation = decodedOrientation
        if swapsEdges {
            swap(&timing.width, &timing.height)
        }
        return timing
    }

    /// The display-oriented bitmap for a colour comparison. Untimed; callers that need
    /// a measurement use ``render(url:variant:)``.
    public func image(url: URL, variant: CameraPreviewVariant) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let decoded = try decode(url: url, variant: variant)
            guard decoded.needsOrientation, decoded.orientation != 1 else {
                return decoded.image
            }
            return try oriented(decoded.image, orientation: decoded.orientation)
        }
    }

    private func decode(
        url: URL, variant: CameraPreviewVariant
    ) throws -> (
        image: CGImage, native: CGSize, orientation: Int, needsOrientation: Bool
    ) {
        try Task.checkCancellation()
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw RAWDisplayFailure.cannotRender }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        // A 100% source is displayed oriented, so report the oriented source size.
        let swapsEdges = orientation >= 5
        let native = CGSize(
            width: swapsEdges ? height : width, height: swapsEdges ? width : height)
        let image: CGImage?
        // A thumbnail requested with the transform flag is already oriented; the
        // other two routes leave orientation to the caller.
        var needsOrientation = true
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
            needsOrientation = false
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
        return (image, native, orientation, needsOrientation)
    }

    /// Applies EXIF orientation as a display transform. An orientation-1 file is
    /// returned unchanged and pays no redraw.
    private func oriented(_ image: CGImage, orientation: Int) throws -> CGImage {
        guard orientation != 1 else { return image }
        guard let value = CGImagePropertyOrientation(rawValue: UInt32(orientation)) else {
            throw RAWDisplayFailure.cannotRender
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        let input = CIImage(cgImage: image).oriented(value)
        guard
            let output = context.createCGImage(
                input, from: input.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { throw RAWDisplayFailure.cannotRender }
        return output
    }
}
