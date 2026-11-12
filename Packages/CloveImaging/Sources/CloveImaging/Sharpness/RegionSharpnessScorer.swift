import CoreGraphics
import Foundation

/// A lightweight local sharpness measure over one region's pixels: the Tenengrad mean of
/// squared Sobel gradients on luminance (#208).
///
/// The input is expected to be high-resolution, orientation-applied pixels of the region the
/// caller located; this type only measures what it is given. A region the Sobel kernel cannot
/// fit into reports nil rather than a meaningless number.
///
/// This is evidence, not a calibrated focus percentage: values are comparable only between
/// regions measured by the same scorer version.
public struct RegionSharpnessScorer: Sendable {
    /// The smallest interior a gradient kernel can average over.
    public static let minimumEdge = 3

    public init() {}

    /// Measures one region of an image, or nil when the region is too small to measure
    /// (fewer than 3×3 interior pixels).
    public func score(image: CGImage, region: NormalizedRegion) -> RegionSharpnessScore? {
        guard let rect = region.pixelRect(in: CGSize(width: image.width, height: image.height))
        else { return nil }
        guard rect.width >= CGFloat(Self.minimumEdge), rect.height >= CGFloat(Self.minimumEdge)
        else { return nil }
        guard
            let luminance = Self.luminance(
                of: image, in: rect, maximum: Self.maximumSampledPixels)
        else { return nil }
        guard luminance.width >= Self.minimumEdge, luminance.height >= Self.minimumEdge else {
            return nil
        }
        let value = luminance.value
        var total = 0.0
        var count = 0
        for y in 1..<(luminance.height - 1) {
            for x in 1..<(luminance.width - 1) {
                let gx =
                    -value(x - 1, y - 1) + value(x + 1, y - 1)
                    - 2 * value(x - 1, y) + 2 * value(x + 1, y)
                    - value(x - 1, y + 1) + value(x + 1, y + 1)
                let gy =
                    -value(x - 1, y - 1) - 2 * value(x, y - 1) - value(x + 1, y - 1)
                    + value(x - 1, y + 1) + 2 * value(x, y + 1) + value(x + 1, y + 1)
                total += gx * gx + gy * gy
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return RegionSharpnessScore(
            tenengradMeanSquare: total / Double(count), sampledPixels: count,
            sampledWidth: luminance.width, sampledHeight: luminance.height)
    }

    /// Downsamples a region's luminance before scoring so a large region stays bounded.
    static let maximumSampledPixels = 512 * 512

    /// Extracts the region's pixels as luminance, downsampling when the region is large.
    ///
    /// Downsampling is linear interpolation, which lowers gradient magnitudes of fine detail;
    /// regions that fit the budget are never resampled, and `RegionSharpnessScore`
    /// records the sampled size so a reader can see when two regions were not measured at the
    /// same scale.
    private static func luminance(
        of image: CGImage, in rect: CGRect, maximum: Int
    ) -> (width: Int, height: Int, value: (Int, Int) -> Double)? {
        let scale = min(1, sqrt(Double(maximum) / Double(rect.width * rect.height)))
        let width = max(1, Int((Double(rect.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(rect.height) * scale).rounded(.down)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            // CG draws with a bottom-left origin; the region's coordinates are top-left.
            context.draw(
                image,
                in: CGRect(
                    x: -Double(rect.minX) * scale,
                    y: -(Double(image.height) - Double(rect.maxY)) * scale,
                    width: Double(image.width) * scale, height: Double(image.height) * scale))
            return true
        }
        guard drawn else { return nil }
        return (
            width, height,
            { x, y in
                let red = Double(pixels[(y * width + x) * 4])
                let green = Double(pixels[(y * width + x) * 4 + 1])
                let blue = Double(pixels[(y * width + x) * 4 + 2])
                return 0.299 * red + 0.587 * green + 0.114 * blue
            }
        )
    }
}
