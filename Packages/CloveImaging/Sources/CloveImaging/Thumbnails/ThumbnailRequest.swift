import CoreGraphics
import CryptoKit
import Foundation

/// The caller supplies the primary file (the RAW for a RAW photo set) and keeps
/// its folder access alive until the request drains. No CloveCore dependency.
public struct ThumbnailRequest: Hashable, Sendable {
    public let source: URL
    public let revision: ThumbnailRevision
    public let targetPixels: Int
    /// Stable folder/bookmark identity; distinguishes media mounted at the same path.
    public let locationIdentity: String

    public init(
        source: URL, revision: ThumbnailRevision, targetPixels: Int = 400,
        locationIdentity: String
    ) {
        precondition((1...4096).contains(targetPixels))
        self.source = source.standardizedFileURL
        self.revision = revision
        self.targetPixels = targetPixels
        self.locationIdentity = locationIdentity
    }
}

public struct ThumbnailRevision: Hashable, Codable, Sendable {
    public let size: Int64
    public let modificationTime: Date

    public init(size: Int64, modificationTime: Date) {
        self.size = size
        self.modificationTime = modificationTime
    }

    public static func read(from source: URL) throws -> Self {
        var fresh = source
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let date = values.contentModificationDate else {
            throw CocoaError(.fileReadUnknown)
        }
        return Self(size: Int64(size), modificationTime: date)
    }

    public static func readOnImageWork(
        from source: URL, priority: ThumbnailPriority = .visible
    ) async throws -> Self {
        try await Task.detached(
            executorPreference: priority == .visible
                ? ImageWorkExecutor.userInitiated : ImageWorkExecutor.utility,
            priority: priority == .visible ? .userInitiated : .utility
        ) {
            try Self.read(from: source)
        }.value
    }
}

public enum ThumbnailRoute: String, Codable, Sendable {
    case embeddedOnly, ifAbsent, always
}

public struct Thumbnail: Sendable {
    /// Pixels already include EXIF orientation; consumers must not transform again.
    public let image: CGImage
    public let route: ThumbnailRoute
    public var width: Int { image.width }
    public var height: Int { image.height }
    public var decodedBytes: Int { image.bytesPerRow * image.height }

    public init(image: CGImage, route: ThumbnailRoute) {
        self.image = image
        self.route = route
    }
}

public enum ThumbnailUnavailable: String, Sendable {
    case cannotOpen, noUsablePreview, sourceChanged
}

public enum ThumbnailResult: Sendable {
    case available(Thumbnail)
    case unavailable(ThumbnailUnavailable)
}

public enum ThumbnailPriority: Sendable {
    case visible, prefetch
}

public enum ThumbnailPipelineError: Error, Sendable {
    case queueFull, closed
}

struct ThumbnailCacheKey: Encodable {
    let request: ThumbnailRequest
    let route: ThumbnailRoute
    let version: Int

    enum CodingKeys: String, CodingKey {
        case path, location, size, modificationTime, target, transform, route, version
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(request.source.path, forKey: .path)
        try values.encode(request.locationIdentity, forKey: .location)
        try values.encode(request.revision.size, forKey: .size)
        // Preserve the caller's full timestamp precision rather than rounding to seconds.
        try values.encode(
            request.revision.modificationTime.timeIntervalSince1970.bitPattern,
            forKey: .modificationTime)
        try values.encode(request.targetPixels, forKey: .target)
        try values.encode(true, forKey: .transform)
        try values.encode(route, forKey: .route)
        try values.encode(version, forKey: .version)
    }

    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // All encoded fields are finite scalar values.
        do {
            let data = try encoder.encode(self)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            preconditionFailure("Cannot encode thumbnail cache identity: \(error)")
        }
    }
}
