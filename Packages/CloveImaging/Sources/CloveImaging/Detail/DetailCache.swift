import CoreGraphics
import Foundation
import Synchronization

/// What one cache entry answers, so a preview never stands in for a native render and one
/// display size's raster is never reused at another.
enum DetailCachePurpose: Hashable, Sendable {
    case embeddedPreview
    case displayRaster(Int)
    case fullRaster
    case nativeRAW
    case screenRAW(Int)
}

/// Identity of one detail image (G1 "Scheduling and cache": source identity and revision).
///
/// The location identity distinguishes media mounted at the same path, and the revision
/// distinguishes a rewritten file, so a changed source can never hit an old entry.
struct DetailCacheKey: Hashable, Sendable {
    init(
        source: DetailSource, locationIdentity: String, purpose: DetailCachePurpose
    ) {
        self.path = source.url.path
        self.locationIdentity = locationIdentity
        self.size = source.revision.size
        self.modificationTime = source.revision.modificationTime
        self.purpose = purpose
    }

    private let path: String
    private let locationIdentity: String
    private let size: Int64
    private let modificationTime: Date
    private let purpose: DetailCachePurpose
}

/// Detail previews and screen renders share a compressed JPEG LRU in memory.
/// One native render is held separately. Encoding and decoding run outside the mutex.
public final class DetailCache: Sendable {
    public struct Configuration: Sendable {
        /// Compressed bytes shared by previews and RAW screen renders, encoded as JPEG 0.9.
        public var compressedBytes = 64 * 1024 * 1024
        public init() {}
    }

    private struct Entry {
        let image: DetailCompressedImage
        let access: UInt64
    }

    /// A photo's 100% size, or the answer that it could not be read (PRD P0-04; G1 "Preview,
    /// detail (I2)").
    ///
    /// The unknown answer is cached too, so a file whose size cannot be read is not opened
    /// again on every preview and render request.
    enum NativeSize: Hashable, Sendable {
        case known(CGSize)
        case unknown
    }

    private struct State {
        var images: [DetailCacheKey: Entry] = [:]
        var compressedCost = 0
        var native: (key: DetailCacheKey, image: DetailImage)?
        var nativeSizes: [DetailSource: NativeSize] = [:]
        var currentPhoto: DetailCacheKey?
        var cameraFailures: Set<DetailSource> = []
        var tick: UInt64 = 0
    }

    private let state: Mutex<State>
    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        precondition(configuration.compressedBytes >= 0)
        self.configuration = configuration
        self.state = Mutex(State())
    }

    /// Drops every cached image, previews and the native render alike, and the native sizes.
    ///
    /// Call this from the app's memory-warning handler: nothing here observes UIKit, so the
    /// app decides when memory is short (G1 "Scheduling and cache"). Images the view is
    /// already displaying stay alive through their own references. Native sizes are tiny, but
    /// dropping them keeps this one "release everything" call and bounds the map to the photos
    /// in use (PRD P0-04).
    public func releaseAll() {
        state.withLock { state in
            state.images.removeAll()
            state.compressedCost = 0
            state.native = nil
            state.nativeSizes.removeAll()
            state.cameraFailures.removeAll()
        }
    }

    /// Changing photo releases the sole full decode before the next allocation.
    func navigate(to request: DetailRequest) {
        state.withLock { state in
            let photo = Self.fullKey(request)
            if state.currentPhoto != photo { state.native = nil }
            state.currentPhoto = photo
        }
    }

    static func screenKey(_ request: DetailRequest) -> DetailCacheKey? {
        request.raw.map {
            DetailCacheKey(
                source: $0, locationIdentity: request.locationIdentity,
                purpose: .screenRAW(request.screenPixels))
        }
    }

    static func fullKey(_ request: DetailRequest) -> DetailCacheKey {
        guard let source = request.raw ?? request.jpeg ?? request.heif else {
            preconditionFailure("A detail request needs a file")
        }
        return DetailCacheKey(
            source: source,
            locationIdentity: request.locationIdentity,
            purpose: request.mode == .rawFirst ? .nativeRAW : .fullRaster)
    }

    func screen(for request: DetailRequest) -> DetailImage? {
        guard let key = Self.screenKey(request) else { return nil }
        return image(for: key)
    }

    func cameraFailed(_ source: DetailSource) -> Bool {
        state.withLock { $0.cameraFailures.contains(source) }
    }

    func recordCameraFailure(_ source: DetailSource) {
        state.withLock { _ = $0.cameraFailures.insert(source) }
    }

    /// Releases the single native render without touching previews.
    ///
    /// G1 "Scheduling and cache": release the old native image before rendering the next.
    func releaseNative() {
        state.withLock { $0.native = nil }
    }

    func image(for key: DetailCacheKey) -> DetailImage? {
        let compressed = state.withLock { state -> DetailCompressedImage? in
            guard let entry = state.images[key] else { return nil }
            state.tick &+= 1
            state.images[key] = Entry(image: entry.image, access: state.tick)
            return entry.image
        }
        return compressed?.decoded()
    }

    /// Inserts encoded bytes under the caller's cancellation guard, without doing pixel work.
    func store(_ compressed: DetailCompressedImage, for key: DetailCacheKey) {
        state.withLock { state in
            state.compressedCost -= state.images.removeValue(forKey: key)?.image.data.count ?? 0
            guard compressed.data.count <= configuration.compressedBytes else { return }
            state.tick &+= 1
            state.images[key] = Entry(image: compressed, access: state.tick)
            state.compressedCost += compressed.data.count
            while state.compressedCost > configuration.compressedBytes,
                let oldest = state.images.min(by: { $0.value.access < $1.value.access })?.key
            {
                state.compressedCost -=
                    state.images.removeValue(forKey: oldest)?.image.data.count ?? 0
            }
        }
    }

    func native(for key: DetailCacheKey) -> DetailImage? {
        state.withLock { $0.native?.key == key ? $0.native?.image : nil }
    }

    /// Holds at most one native render: a newer one replaces the older (G1 "Scheduling").
    func storeNative(_ image: DetailImage, for key: DetailCacheKey) {
        state.withLock { $0.native = (key, image) }
    }

    /// The photo's native 100% size if it was already read, including the answer that it could
    /// not be read (PRD P0-04; G1 "Preview, detail (I2)").
    ///
    /// The source carries the file's revision, so a rewritten file reads its size again
    /// instead of inheriting an old answer (G1 "Scheduling and cache").
    func nativeSize(for source: DetailSource) -> NativeSize? {
        state.withLock { $0.nativeSizes[source] }
    }

    /// Remembers a photo's native 100% size, or that there is none, so one photo pays for the
    /// read once (PRD P0-04; G1 "Preview, detail (I2)").
    func store(nativeSize: NativeSize, for source: DetailSource) {
        state.withLock { $0.nativeSizes[source] = nativeSize }
    }

    /// Compressed bytes and entries currently held, for budget tests.
    var compressedCost: Int { state.withLock { $0.compressedCost } }
    var imageCount: Int { state.withLock { $0.images.count } }
    var holdsNativeImage: Bool { state.withLock { $0.native != nil } }
}
