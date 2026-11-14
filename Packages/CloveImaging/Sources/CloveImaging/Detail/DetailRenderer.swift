import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The result of one read attempt, before any cache or revision decision.
enum DetailReadOutcome: Sendable {
    case image(CGImage)
    /// The file could not be opened as an image at all.
    case cannotOpen
    /// The file opened but this route has no pixels it may show.
    case noUsablePreview
}

/// The read routes the pipeline calls. Tests replace this to count and gate entries;
/// production always uses ``DetailRenderer``.
protocol DetailReading: Sendable {
    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome
    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome
    func nativeRAW(_ source: DetailSource) async -> CGImage?
    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage?
}

/// Reads system image capabilities with ImageIO and Core Image only.
///
/// Each read opens a fresh source. CIContext supports concurrent use and stores no
/// per-request state; the pipeline serializes all full-image and RAW work.
final class DetailRenderer: DetailReading, @unchecked Sendable {
    // Lazily initialized by the first rendering job on the Dispatch executor.
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// G1 "Preview, detail (I2)": the embedded preview is requested at about 2000 px.
    ///
    /// This is a cap, not a guarantee: the owner's A1 II exposes 1616 px and the ARW
    /// fixture 1616×1080, so the requested size is the largest the file offers.
    static let embeddedPreviewPixels = 2000
    /// Upper bound for a raster decode; protects the cache key range and the bitmap size.
    static let maximumRasterPixels = DetailPixelLimit.maximumEdge

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        await withTaskExecutorPreference(ImageWorkExecutor.current) {
            switch step {
            case .embedded(let source):
                return embedded(source)
            case .displayRaster(let source):
                return raster(source, maxPixels: min(displayPixels, Self.maximumRasterPixels))
            }
        }
    }

    /// Full camera pixels for a JPEG or HIF. RAW files never enter this route.
    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
        await withTaskExecutorPreference(ImageWorkExecutor.current) {
            autoreleasepool {
                guard
                    let imageSource = CGImageSourceCreateWithURL(
                        source.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                else { return .cannotOpen }
                guard Self.containerType(imageSource) != nil else { return .cannotOpen }
                let properties =
                    CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
                let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
                let pixels = max(width, height)
                guard pixels > 0 else { return .noUsablePreview }
                guard let type = Self.containerType(imageSource), !type.conforms(to: .rawImage)
                else {
                    return .noUsablePreview
                }
                if pixels > Self.maximumRasterPixels {
                    return raster(
                        source, maxPixels: Self.maximumRasterPixels, imageSource: imageSource)
                }
                guard
                    let image = CGImageSourceCreateImageAtIndex(
                        imageSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                    ),
                    image.width > 0, image.height > 0, image.bytesPerRow > 0
                else { return .noUsablePreview }
                let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
                guard orientation != 1 else { return .image(image) }
                let oriented = CIImage(cgImage: image).oriented(
                    forExifOrientation: Int32(orientation))
                guard let transformed = Self.context.createCGImage(oriented, from: oriented.extent)
                else {
                    return .noUsablePreview
                }
                return .image(transformed)
            }
        }
    }

    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        await withTaskExecutorPreference(ImageWorkExecutor.current) {
            raw(source, longEdge: nil)
        }
    }

    func screenRAW(_ source: DetailSource, longEdge: Int) async -> CGImage? {
        await withTaskExecutorPreference(ImageWorkExecutor.current) {
            raw(source, longEdge: longEdge)
        }
    }

    /// Decode-time scaling, with draft explicitly off. CIRAWFilter applies orientation.
    private func raw(_ source: DetailSource, longEdge: Int?) -> CGImage? {
        autoreleasepool {
            guard let filter = CIRAWFilter(imageURL: source.url) else { return nil }
            if let longEdge {
                let nativeEdge = max(filter.nativeSize.width, filter.nativeSize.height)
                guard nativeEdge > 0 else { return nil }
                filter.scaleFactor = min(1, Float(longEdge) / Float(nativeEdge))
            }
            filter.isDraftModeEnabled = false
            guard let output = filter.outputImage else { return nil }
            guard
                let image = Self.context.createCGImage(
                    output, from: output.extent, format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
                image.width > 0, image.height > 0, image.bytesPerRow > 0
            else { return nil }
            // S2: a filter that initialises can still fail at rendering, so pixels are the
            // only evidence of support.
            return image
        }
    }

    private func embedded(_ source: DetailSource) -> DetailReadOutcome {
        autoreleasepool {
            guard
                let imageSource = CGImageSourceCreateWithURL(
                    source.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return .cannotOpen }
            guard Self.containerType(imageSource) != nil else { return .cannotOpen }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: Self.embeddedPreviewPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailFromImageAlways: false,
            ]
            guard let image = materialized(imageSource, options) else { return .noUsablePreview }
            return .image(image)
        }
    }

    private func raster(_ source: DetailSource, maxPixels: Int) -> DetailReadOutcome {
        autoreleasepool {
            guard
                let imageSource = CGImageSourceCreateWithURL(
                    source.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return .cannotOpen }
            return raster(source, maxPixels: maxPixels, imageSource: imageSource)
        }
    }

    private func raster(
        _ source: DetailSource, maxPixels: Int, imageSource: CGImageSource
    ) -> DetailReadOutcome {
        // G1 "Preview, detail (I2)": a HIF is never fully decoded, and a RAW belongs to the
        // render route. A container that is not a raster image is reported, not decoded.
        guard let type = Self.containerType(imageSource) else { return .cannotOpen }
        guard Self.allowsRasterDecode(type) else { return .noUsablePreview }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
        ]
        guard let image = materialized(imageSource, options) else { return .noUsablePreview }
        return .image(image)
    }

    /// ImageIO opens a source for any readable byte stream, so an unknown container is only
    /// identifiable by its missing type: that is an unreadable file, not a missing preview.
    static func containerType(_ source: CGImageSource) -> UTType? {
        CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    }

    /// Only raster formats are decoded from an original; everything else has a preview route.
    static func allowsRasterDecode(_ type: UTType) -> Bool {
        if type.conforms(to: .rawImage) || type.conforms(to: .heif) || type.conforms(to: .heic) {
            return false
        }
        return type.conforms(to: .image)
    }

    /// Forces the bitmap provider so callers never hold a lazily decoded image.
    private func materialized(
        _ source: CGImageSource, _ options: [CFString: Any]
    ) -> CGImage? {
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            image.width > 0, image.height > 0, image.bytesPerRow > 0
        else { return nil }
        return image
    }
}
