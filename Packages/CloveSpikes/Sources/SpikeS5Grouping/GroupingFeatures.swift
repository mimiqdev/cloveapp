import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum GroupingFeatureError: Error { case noPreview, noFeature, noBitmap }

/// Synchronous, serial, per-image work; callers keep observations inside their
/// worker task. Only scalar results and bounded JPEG thumbnails reach the UI.
public enum GroupingFeatures {
    public static func preview(url: URL, maxPixel: Int) throws -> CGImage {
        let raster = ["jpg", "jpeg", "heic", "heif", "png"].contains(url.pathExtension.lowercased())
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: raster,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw GroupingFeatureError.noPreview }
        return image
    }

    public static func feature(_ image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let result = request.results?.first else { throw GroupingFeatureError.noFeature }
        return result
    }

    /// 64-bit horizontal difference hash. Lower distance means more similar.
    /// Cheap but sensitive to crop/rotation and blind to fine focus/expression.
    public static func differenceHash(_ image: CGImage) throws -> UInt64 {
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: 9, height: 8, bitsPerComponent: 8,
                    bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        guard rendered else { throw GroupingFeatureError.noBitmap }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                if pixels[row * 9 + column] > pixels[row * 9 + column + 1] {
                    hash |= UInt64(1) << (row * 8 + column)
                }
            }
        }
        return hash
    }

    public static func thumbnail(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
