import CoreGraphics
import Foundation

/// Computes the 9×8 difference hash S5 measured at 0.225 ms per photo on an iPhone.
///
/// PRD P0-11 keeps grouping working when Vision is unavailable, and G1 "Grouping (C9/I3)" uses
/// this hash as that fallback. The preview is drawn into a 9×8 grayscale bitmap and adjacent
/// horizontal pixels are compared, exactly as the spike did, so a hash computed here means the
/// same thing as the one S5's fallback trials measured. It is sensitive to crop and rotation and
/// says nothing about focus or expression, which is why the Vision print is preferred.
struct DifferenceHashReader: Sendable {
    /// The bitmap size S5 used: nine columns give eight horizontal comparisons per row.
    static let columns = 9
    static let rows = 8

    /// Returns nil only when a 9×8 grayscale bitmap cannot be created, so a usable preview
    /// always yields one kind of feature even when Vision is unavailable.
    func hash(of image: CGImage) -> DifferenceHash? {
        let width = Self.columns
        let height = Self.rows
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        var bits: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                let left = pixels[row * width + column]
                let right = pixels[row * width + column + 1]
                if left > right {
                    bits |= UInt64(1) << (row * (width - 1) + column)
                }
            }
        }
        return DifferenceHash(bits: bits)
    }
}
