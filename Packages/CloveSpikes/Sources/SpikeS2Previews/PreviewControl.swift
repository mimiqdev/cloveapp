import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synthetic control written only into a per-run temporary directory. Explicitly
/// omits an embedded thumbnail and supplies orientation 6 (90 degrees clockwise).
public enum PreviewControl {
    public static func writeNoThumbnailJPEG(
        in directory: URL, width: Int = 2_400, height: Int = 1_600
    ) throws -> URL {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw PreviewFailure.cannotRender }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw PreviewFailure.cannotRender }
        let url = directory.appendingPathComponent("control-no-thumbnail.jpg")
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw PreviewFailure.cannotRender
        }
        CGImageDestinationAddImage(
            destination, image,
            [
                kCGImagePropertyOrientation: 6, kCGImageDestinationEmbedThumbnail: false,
            ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PreviewFailure.cannotRender }
        return url
    }
}
