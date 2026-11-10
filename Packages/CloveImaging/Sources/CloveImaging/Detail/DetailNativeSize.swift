import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// The size a photo's 100% means, read before its pixels are (PRD P0-04; G1 "Preview, detail
/// (I2)").
///
/// PRD P0-04's double-tap to 100% needs the size one image pixel fills one screen pixel at, and
/// G1 "Preview, detail (I2)" shows an embedded preview before a RAW render arrives. Reading the
/// size up front lets the view compute the native 100% target with the first preview, so the
/// render only sharpens the picture instead of zooming again.
///
/// A RAW's size comes from the decoder its render uses: `CIRAWFilter` reports the extent of the
/// image it will produce, which is what ``DetailRenderer/nativeRAW(_:)`` renders, so the target
/// and the pixels cannot disagree. The file's index-0 ImageIO properties are not enough on every
/// camera: a Sony A1 II ARW either has none or describes its embedded preview, and a preview-sized
/// header made the first double-tap land at the preview's 100% (#111). The ImageIO header stays
/// for a JPEG primary, which has no RAW decoder, and as the fallback when `CIRAWFilter` cannot open
/// a RAW.
enum DetailNativeSize {
    /// The oriented size `CIRAWFilter` will render at, or nil when the filter cannot open the file
    /// (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// This reads the filter's output extent and nothing else: no context, no bitmap, no
    /// demosaicing, so no image pixel is decoded. `CIRAWFilter` applies the RAW's own orientation
    /// to its output, which is why the extent is already the size the pixels are displayed at.
    static func raw(_ source: DetailSource) -> CGSize? {
        autoreleasepool {
            guard let filter = CIRAWFilter(imageURL: source.url),
                let extent = filter.outputImage?.extent
            else { return nil }
            return oriented(
                width: Int(extent.width.rounded()), height: Int(extent.height.rounded()),
                orientation: 1)
        }
    }

    /// The file's oriented header size, or nil when its header cannot be read (PRD P0-04).
    ///
    /// The size is the file's primary image with its EXIF orientation applied: width and height
    /// are swapped for the four orientations that rotate a quarter turn (5 through 8), which is
    /// what a renderer such as `CIRAWFilter` produces. `CGImageSourceCopyPropertiesAtIndex` reads
    /// metadata only, so no image pixel is decoded; the first RAW header of a process can still
    /// load the system's RAW decoder, which the embedded-preview read pays for as well.
    static func header(_ source: DetailSource) -> CGSize? {
        autoreleasepool {
            guard
                let imageSource = CGImageSourceCreateWithURL(
                    source.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                let properties =
                    CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            else { return nil }
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            return oriented(width: width, height: height, orientation: orientation)
        }
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
