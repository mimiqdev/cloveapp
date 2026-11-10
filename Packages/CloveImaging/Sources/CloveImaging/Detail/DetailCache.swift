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

/// Decoded detail images, held in memory only (G1 "Scheduling and cache").
///
/// Preview and display-size bitmaps share a 32 MiB cost budget, counted in decoded row
/// bytes as S2 measured them. One native RAW image is held separately, outside that budget,
/// because a single 50 MP render is 189.84 MiB on the owner's camera. The mutex protects
/// bookkeeping only: decoding, file IO and eviction never run under it.
public final class DetailCache: Sendable {
    public struct Configuration: Sendable {
        /// G1 "Scheduling and cache": 32 MiB for detail images, about four 6.66 MiB bitmaps.
        public var previewBytes = 32 * 1024 * 1024
        public init() {}
    }

    private struct Entry {
        let image: DetailImage
        let cost: Int
        let access: UInt64
    }

    /// A photo's header size, or the answer that its header could not be read (PRD P0-04).
    ///
    /// The unknown answer is cached too, so a file that cannot supply a header is not opened
    /// again on every preview and render request.
    enum HeaderSize: Hashable, Sendable {
        case known(CGSize)
        case unreadable
    }

    private struct State {
        var previews: [DetailCacheKey: Entry] = [:]
        var previewCost = 0
        var native: (key: DetailCacheKey, image: DetailImage)?
        var headerSizes: [DetailSource: HeaderSize] = [:]
        var tick: UInt64 = 0
    }

    private let state: Mutex<State>
    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        precondition(configuration.previewBytes >= 0)
        self.configuration = configuration
        self.state = Mutex(State())
    }

    /// Drops every cached image, previews and the native render alike, and the header sizes.
    ///
    /// Call this from the app's memory-warning handler: nothing here observes UIKit, so the
    /// app decides when memory is short (G1 "Scheduling and cache"). Images the view is
    /// already displaying stay alive through their own references. Header sizes are tiny, but
    /// dropping them keeps this one "release everything" call and bounds the map to the photos
    /// in use (PRD P0-04).
    public func releaseAll() {
        state.withLock { state in
            state.previews.removeAll()
            state.previewCost = 0
            state.native = nil
            state.headerSizes.removeAll()
        }
    }

    /// Releases the single native render without touching previews.
    ///
    /// G1 "Scheduling and cache": release the old native image before rendering the next.
    func releaseNative() {
        state.withLock { $0.native = nil }
    }

    func preview(for key: DetailCacheKey) -> DetailImage? {
        state.withLock { state in
            guard var entry = state.previews[key] else { return nil }
            state.tick &+= 1
            entry = Entry(image: entry.image, cost: entry.cost, access: state.tick)
            state.previews[key] = entry
            return entry.image
        }
    }

    /// Stores preview or display-size pixels, evicting the least recently used entries.
    /// An image larger than the whole budget is simply not cached.
    func storePreview(_ image: DetailImage, for key: DetailCacheKey) {
        state.withLock { state in
            state.previewCost -= state.previews.removeValue(forKey: key)?.cost ?? 0
            guard image.decodedBytes <= configuration.previewBytes else { return }
            state.tick &+= 1
            state.previews[key] = Entry(image: image, cost: image.decodedBytes, access: state.tick)
            state.previewCost += image.decodedBytes
            while state.previewCost > configuration.previewBytes,
                let oldest = state.previews.min(by: { $0.value.access < $1.value.access })?.key
            {
                state.previewCost -= state.previews.removeValue(forKey: oldest)?.cost ?? 0
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

    /// The photo's header size if it was already read, including the answer that it could not be
    /// read (PRD P0-04).
    ///
    /// The source carries the file's revision, so a rewritten file reads its header again
    /// instead of inheriting an old size (G1 "Scheduling and cache").
    func headerSize(for source: DetailSource) -> HeaderSize? {
        state.withLock { $0.headerSizes[source] }
    }

    /// Remembers a header size, or that there is none, so one photo pays for the read once
    /// (PRD P0-04; G1 "Preview, detail (I2)").
    func store(headerSize: HeaderSize, for source: DetailSource) {
        state.withLock { $0.headerSizes[source] = headerSize }
    }

    /// Bytes currently held by preview and display-size entries, for budget tests.
    var previewCost: Int { state.withLock { $0.previewCost } }
    var previewCount: Int { state.withLock { $0.previews.count } }
    var holdsNativeImage: Bool { state.withLock { $0.native != nil } }
}
