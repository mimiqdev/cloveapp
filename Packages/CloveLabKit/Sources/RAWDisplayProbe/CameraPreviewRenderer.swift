import CoreGraphics
import CoreImage
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
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        // The embedded preview applies orientation; a 100% source must too, or a
        // rotated camera HEIF would be compared and displayed sideways.
        let swapsEdges = orientation >= 5
        let native = CGSize(
            width: swapsEdges ? height : width, height: swapsEdges ? width : height)
        let image: CGImage?
        // A thumbnail requested with the transform flag is already oriented; the
        // other two routes leave orientation to the caller.
        var isOriented = false
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
            isOriented = true
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
        guard !isOriented else { return (image, native) }
        return (try oriented(image, orientation: orientation), native)
    }

    /// Applies EXIF orientation, which `CGImageSourceCreateImageAtIndex` leaves to the
    /// caller. An orientation-1 file is returned unchanged and pays no redraw.
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
