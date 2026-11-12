import CoreGraphics
import Foundation

/// Preview pixels one feature request is computed from, with the route that produced them.
///
/// G1 "Preview, grid (I1)" and "Grouping (C9/I3)" both start from the RAW's embedded preview at
/// roughly 400 px, so a feature reuses I1's request, revision and route instead of defining its
/// own preview read.
public struct ImageFeaturePreview: Sendable {
    /// Pixels already include EXIF orientation; features must not transform them again.
    public let image: CGImage
    /// The extraction route, which G1 makes part of the cache identity: an embedded preview and
    /// a generated raster of the same file can produce different distances.
    public let route: ThumbnailRoute

    public init(image: CGImage, route: ThumbnailRoute) {
        self.image = image
        self.route = route
    }

    /// Pixels on the long edge, reported by the timing test and by device checks.
    public var longEdge: Int { max(image.width, image.height) }
}

/// What one preview read delivered for a feature request.
public enum ImageFeaturePreviewRead: Sendable {
    case preview(ImageFeaturePreview)
    /// No usable preview, so neither kind can run and grouping splits the boundary (P0-11).
    case unavailable(ThumbnailUnavailable)
}

/// Supplies the preview a feature is computed from.
///
/// The seam exists for tests; production uses ``ThumbnailPreviewReader``, which reuses I1's
/// extraction and, when the app passes one, I1's cache as well.
public protocol ImageFeaturePreviewReading: Sendable {
    func preview(for request: ThumbnailRequest) async -> ImageFeaturePreviewRead
}

/// Reads features' previews through I1's extractor, and shares its cache when one is supplied.
///
/// PRD P0-11 refines groups in the background while the grid is already showing the same photos,
/// so a feature must not read its own preview when the grid has one: a hit in the shared
/// ``ThumbnailCache`` is used as-is, route included, and a miss is stored back for the grid. This
/// only calls I1's public API, so its behaviour is unchanged.
public struct ThumbnailPreviewReader: ImageFeaturePreviewReading {
    private let sharedCache: ThumbnailCache?

    /// Pass the grid pipeline's cache to share previews with it; nil reads the file every time.
    public init(sharedCache: ThumbnailCache? = nil) {
        self.sharedCache = sharedCache
    }

    public func preview(for request: ThumbnailRequest) async -> ImageFeaturePreviewRead {
        await withTaskExecutorPreference(ImageWorkExecutor.utility) {
            if let sharedCache {
                switch sharedCache.result(for: request) {
                case .available(let thumbnail):
                    return .preview(
                        ImageFeaturePreview(image: thumbnail.image, route: thumbnail.route))
                case .unavailable(let reason):
                    // I1 remembers a preview it could not use, so this photo is not read again.
                    return .unavailable(reason)
                case nil:
                    break
                }
            }
            let extracted = ThumbnailExtractor().extract(request)
            switch extracted {
            case .available(let thumbnail):
                if let sharedCache { try? sharedCache.store(extracted, for: request) }
                return .preview(ImageFeaturePreview(image: thumbnail.image, route: thumbnail.route))
            case .unavailable(let reason):
                return .unavailable(reason)
            }
        }
    }
}
