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
}

/// Reads system image capabilities with ImageIO and Core Image only.
///
/// No UIKit, so the module builds and tests on macOS (G1 "Scheduling and cache"), and no
/// stored Core Image context, so the type is `Sendable` without an unchecked conformance.
/// Every call opens a fresh source with caching disabled: a detail request measures and
/// shows current pixels rather than stale framework state (S2).
struct DetailRenderer: DetailReading {
    /// G1 "Preview, detail (I2)": the embedded preview is requested at about 2000 px.
    ///
    /// This is a cap, not a guarantee: the owner's A1 II exposes 1616 px and the ARW
    /// fixture 1616×1080, so the requested size is the largest the file offers.
    static let embeddedPreviewPixels = 2000
    /// Upper bound for a raster decode; protects the cache key range and the bitmap size.
    static let maximumRasterPixels = 32_768

    func read(_ step: DetailPreviewStep, displayPixels: Int) async -> DetailReadOutcome {
        switch step {
        case .embedded(let source):
            return embedded(source)
        case .displayRaster(let source):
            return raster(source, maxPixels: min(displayPixels, Self.maximumRasterPixels))
        }
    }

    /// G1 "Preview, detail (I2)": a JPEG-primary 100% request decodes the full JPEG, a
    /// bounded raster route rather than a RAW render.
    func fullRaster(_ source: DetailSource) async -> DetailReadOutcome {
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
            return raster(
                source, maxPixels: min(pixels, Self.maximumRasterPixels), imageSource: imageSource)
        }
    }

    /// Native sensor pixels (G1 "Preview, detail (I2)").
    ///
    /// Output is never scaled down: S2 measured a 2000 px RAW render at 592.8 ms against
    /// 529.1 ms at native size on the owner's device, so the smaller output is not cheaper.
    /// `CIRAWFilter` applies orientation, which is why the result can be trusted as oriented.
    func nativeRAW(_ source: DetailSource) async -> CGImage? {
        autoreleasepool {
            guard let filter = CIRAWFilter(imageURL: source.url) else { return nil }
            guard let output = filter.outputImage else { return nil }
            let context = CIContext(options: [.cacheIntermediates: false])
            guard
                let image = context.createCGImage(
                    output, from: output.extent, format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
                image.width > 0, image.height > 0
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
            image.width > 0, image.height > 0,
            let data = image.dataProvider?.data, CFDataGetLength(data) > 0
        else { return nil }
        return image
    }
}
