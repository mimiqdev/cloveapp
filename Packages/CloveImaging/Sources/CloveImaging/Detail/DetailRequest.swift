import Foundation

/// Shared bound for requests, cache keys and raster decodes.
public enum DetailPixelLimit {
    public static let maximumEdge = 32_768
}

/// One file and its expected revision. Location identity on the request separately
/// distinguishes media mounted at the same path.
public struct DetailSource: Hashable, Sendable {
    public let url: URL
    public let revision: ThumbnailRevision

    public init(url: URL, revision: ThumbnailRevision) {
        self.url = url.standardizedFileURL
        self.revision = revision
    }

    public static func read(_ url: URL) throws -> DetailSource {
        DetailSource(url: url, revision: try ThumbnailRevision.read(from: url))
    }
}

/// Imaging has no dependency on the app's domain model or settings storage.
public enum DetailDisplayMode: Hashable, Sendable {
    case rawFirst
    case cameraPreviewFirst
}

/// The app maps a photo set's RAW primary and camera companions to these roles.
/// JPEG-only and HIF-only photos retain their existing raster/embedded routes.
public struct DetailRequest: Hashable, Sendable {
    public let raw: DetailSource?
    public let jpeg: DetailSource?
    public let heif: DetailSource?
    /// The image's on-screen long edge in pixels, including zoom.
    public let displayPixels: Int
    public let wantsNativeResolution: Bool
    public let locationIdentity: String
    public let mode: DetailDisplayMode
    /// Fixed screen edge, independent of zoom, for decode-time RAW scaling.
    public let screenPixels: Int
    /// Position in the visible order, for distance-based held-render eviction.
    public let position: Int

    public init(
        raw: DetailSource? = nil, jpeg: DetailSource? = nil, heif: DetailSource? = nil,
        displayPixels: Int, wantsNativeResolution: Bool = false, locationIdentity: String,
        mode: DetailDisplayMode = .rawFirst, screenPixels: Int? = nil, position: Int = 0
    ) {
        precondition(raw != nil || jpeg != nil || heif != nil, "A detail request needs a file")
        precondition((1...DetailPixelLimit.maximumEdge).contains(displayPixels))
        self.raw = raw
        self.jpeg = jpeg
        self.heif = heif
        self.displayPixels = displayPixels
        self.wantsNativeResolution = wantsNativeResolution
        self.locationIdentity = locationIdentity
        self.mode = mode
        self.screenPixels = min(max(screenPixels ?? displayPixels, 1), DetailPixelLimit.maximumEdge)
        self.position = position
    }
}
