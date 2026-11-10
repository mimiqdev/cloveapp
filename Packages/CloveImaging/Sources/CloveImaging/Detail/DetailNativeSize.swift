import CoreGraphics
import Foundation
import ImageIO

/// The photo's full-resolution pixel size, read from a file header (PRD P0-04; G1 "Preview,
/// detail (I2)").
///
/// PRD P0-04's double-tap to 100% needs the size one image pixel fills one screen pixel at, and
/// G1 "Preview, detail (I2)" shows an embedded preview before a RAW render arrives. Reading the
/// size from the header lets the view compute the native 100% target with the first preview, so
/// the render only sharpens the picture instead of zooming again.
///
/// The size is the file's primary image with its EXIF orientation applied: width and height are
/// swapped for the four orientations that rotate a quarter turn (5 through 8), which is what a
/// renderer such as `CIRAWFilter` produces. `CGImageSourceCopyPropertiesAtIndex` reads metadata
/// only, so no image pixel is decoded; the first RAW header of a process can still load the
/// system's RAW decoder, which the embedded-preview read pays for as well.
enum DetailNativeSize {
    /// The file's oriented full-resolution size, or nil when its header cannot be read.
    static func read(_ source: DetailSource) -> CGSize? {
        autoreleasepool {
            guard
                let imageSource = CGImageSourceCreateWithURL(
                    source.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            return read(imageSource)
        }
    }

    /// The same read for an ImageIO source a caller already opened.
    static func read(_ imageSource: CGImageSource) -> CGSize? {
        guard
            let properties =
                CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return oriented(width: width, height: height, orientation: orientation)
    }

    /// The size after EXIF orientation, which is the size the pixels are displayed at.
    static func oriented(width: Int, height: Int, orientation: Int) -> CGSize? {
        guard width > 0, height > 0 else { return nil }
        // EXIF 5–8 rotate by a quarter turn, so the displayed width and height are swapped.
        let swapsAxes = (5...8).contains(orientation)
        return swapsAxes
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
