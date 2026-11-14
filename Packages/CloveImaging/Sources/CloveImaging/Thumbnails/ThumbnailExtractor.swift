import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO embedded previews only for RAW and HEIF. This type never calls a RAW
/// renderer or CGImageSourceCreateImageAtIndex on an original.
public struct ThumbnailExtractor: Sendable {
    public init() {}

    static func routes(for request: ThumbnailRequest) -> [ThumbnailRoute] {
        let ext = request.source.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        if ["hif", "heif", "heic"].contains(ext)
            || type?.conforms(to: .rawImage) == true
            || ["arw", "cr2", "cr3", "nef", "nrw", "raf", "orf", "rw2", "dng", "raw", "pef", "srw"]
                .contains(ext)
        {
            return [.embeddedOnly]
        }
        // Prefer the improved raster variant when reading a previously cached result.
        return [.always, .ifAbsent, .embeddedOnly]
    }

    public func extract(_ request: ThumbnailRequest) -> ThumbnailResult {
        autoreleasepool {
            guard
                let source = CGImageSourceCreateWithURL(
                    request.source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return .unavailable(.cannotOpen) }
            // Inspect the actual container too: renaming HEIF/RAW must not enable fallback.
            let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
            let embeddedOnly =
                Self.routes(for: request) == [.embeddedOnly]
                || type?.conforms(to: .rawImage) == true
                || type?.conforms(to: .heif) == true || type?.conforms(to: .heic) == true
            let route: ThumbnailRoute = embeddedOnly ? .embeddedOnly : .ifAbsent
            let initial = image(source, request: request, route: route)
            if !embeddedOnly,
                (initial.map { max($0.width, $0.height) } ?? 0) < request.targetPixels,
                let fallback = image(source, request: request, route: .always)
            {
                return .available(Thumbnail(image: fallback, route: .always))
            }
            guard let initial else { return .unavailable(.noUsablePreview) }
            return .available(Thumbnail(image: initial, route: route))
        }
    }

    private func image(
        _ source: CGImageSource, request: ThumbnailRequest, route: ThumbnailRoute
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: request.targetPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: route == .ifAbsent,
            kCGImageSourceCreateThumbnailFromImageAlways: route == .always,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            image.width > 0, image.height > 0, image.bytesPerRow > 0
        else { return nil }
        return image
    }
}
