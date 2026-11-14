import CoreGraphics
import Foundation

/// Generated pixel scenes for sharpness and preview tests: no camera binaries, so these
/// never depend on the shared fixture cache (#208).
enum SharpnessScene {
    /// A checkerboard with the given cell size.
    static func checkerboard(width: Int, height: Int, cell: Int) -> CGImage {
        image(width: width, height: height) { context in
            for y in 0..<height {
                for x in 0..<width {
                    let on = ((x / cell) + (y / cell)).isMultiple(of: 2)
                    context.setFillColor(
                        CGColor(gray: on ? 0.9 : 0.1, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    /// A flat image.
    static func flat(width: Int, height: Int) -> CGImage {
        image(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context else { fatalError("Cannot create a test bitmap") }
        draw(context)
        guard let image = context.makeImage() else { fatalError("Cannot render a test scene") }
        return image
    }
}
