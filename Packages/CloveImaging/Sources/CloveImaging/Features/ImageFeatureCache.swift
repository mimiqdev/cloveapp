import CryptoKit
import Darwin
import Foundation
import Synchronization

/// Identity of one cached feature entry.
///
/// G1 "Grouping (C9/I3)" keys a feature by its source and revision (the "Scheduling and cache"
/// rule), plus everything that changes what the numbers mean: the preview size, the extraction
/// route, the feature kind and the Vision revision. Anything that does not match is a miss, so a
/// rewritten file or a new Vision revision never reuses an older feature.
struct ImageFeatureCacheKey: Hashable, Encodable {
    let path: String
    let locationIdentity: String
    let size: Int64
    let modificationTime: Date
    let previewPixels: Int
    let route: ThumbnailRoute
    /// nil for the whole-record memory key; a kind for the on-disk entries.
    let kind: ImageFeatureKind?
    let visionRevision: Int
    let version: Int

    init(
        request: ImageFeatureRequest, route: ThumbnailRoute, kind: ImageFeatureKind?,
        visionRevision: Int, version: Int
    ) {
        self.path = request.preview.source.path
        self.locationIdentity = request.preview.locationIdentity
        self.size = request.preview.revision.size
        self.modificationTime = request.preview.revision.modificationTime
        self.previewPixels = request.preview.targetPixels
        self.route = route
        self.kind = kind
        self.visionRevision = visionRevision
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case path, location, size, modificationTime, previewPixels, route, kind
        case visionRevision, version
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(path, forKey: .path)
        try values.encode(locationIdentity, forKey: .location)
        try values.encode(size, forKey: .size)
        // Preserve the caller's full timestamp precision rather than rounding to seconds.
        try values.encode(
            modificationTime.timeIntervalSince1970.bitPattern, forKey: .modificationTime)
        try values.encode(previewPixels, forKey: .previewPixels)
        try values.encode(route, forKey: .route)
        try values.encode(kind, forKey: .kind)
        try values.encode(visionRevision, forKey: .visionRevision)
        try values.encode(version, forKey: .version)
    }

    /// The file name and memory index key: a digest so the file system sees no long paths.
    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // All encoded fields are finite scalar values.
        do {
            let data = try encoder.encode(self)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            preconditionFailure("Cannot encode feature cache identity: \(error)")
        }
    }
}

/// What one on-disk entry holds. The key already names the kind and revision, and the copy here
/// catches a file that was copied or renamed into the wrong place.
struct ImageFeaturePayload: Codable, Sendable {
    let kind: ImageFeatureKind
    let visionRevision: Int
    let print: VisionFeaturePrint?
    let hash: DifferenceHash?

    init(
        kind: ImageFeatureKind, visionRevision: Int, print: VisionFeaturePrint? = nil,
        hash: DifferenceHash? = nil
    ) {
        self.kind = kind
        self.visionRevision = visionRevision
        self.print = print
        self.hash = hash
    }

    /// The one value this kind carries, or nil when the payload does not match its key.
    var value: ImageFeaturePayload? {
        switch kind {
        case .visionPrint: print == nil ? nil : self
        case .differenceHash: hash == nil ? nil : self
        }
    }
}

/// Feature entries in memory and on disk, in the app's own cache directory (PRD P0-11).
///
/// G1 "Scheduling and cache" asks every cache to be memory-first with an app-private disk tier.
/// Feature records are tiny next to thumbnails (a 768-element print is 3 KiB and a hash is 8
/// bytes), so the budgets below hold thousands of photos. The bookkeeping mutex never covers
/// Vision, preview decoding or file IO: encoding, staging writes, reads and deletion all happen
/// outside it.
public final class ImageFeatureCache: Sendable {
    public struct Configuration: Sendable {
        /// Memory budget for joined records; S5's prints are 3 KiB each.
        public var memoryBytes = 4 * 1024 * 1024
        /// Disk budget for feature files, about 2,700 prints at 3 KiB each.
        public var diskBytes = 8 * 1024 * 1024
        /// Bump when the on-disk payload layout changes; old entries become misses.
        public var payloadVersion = 1
        public init() {}
    }

    private struct MemoryEntry {
        let features: ImageFeatures
        let cost: Int
        let access: UInt64
    }

    private struct DiskEntry {
        let size: Int
        var access: Date
        var evicting = false
    }

    private struct State {
        var memory: [ImageFeatureCacheKey: MemoryEntry] = [:]
        var memoryCost = 0
        var disk: [String: DiskEntry] = [:]
        var diskCost = 0
        var tick: UInt64 = 0
    }

    private let state: Mutex<State>
    private let directory: URL
    private let configuration: Configuration

    /// One instance owns its directory, which is excluded from backup like I1's thumbnail cache.
    public init(directory: URL, configuration: Configuration = Configuration()) throws {
        precondition(configuration.memoryBytes >= 0 && configuration.diskBytes >= 0)
        self.directory = directory
        self.configuration = configuration
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var privateDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateDirectory.setResourceValues(values)
        var initial = State()
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        {
            if url.pathExtension == "staging" {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard url.pathExtension == "feature" else { continue }
            let attributes = try url.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey,
            ])
            let entry = DiskEntry(
                size: attributes.fileSize ?? 0,
                access: attributes.contentModificationDate ?? .distantPast)
            initial.disk[url.deletingPathExtension().lastPathComponent] = entry
            initial.diskCost += entry.size
        }
        state = Mutex(initial)
        evict(state.withLock { selectEvictions(&$0) })
    }

    /// Everything the cache knows for this photo's preview route, joined from both kinds.
    ///
    /// G1 "Grouping (C9/I3)" pairs a print and a hash only when one preview read produced both,
    /// so this answers the first route that has any entry and never mixes two routes. A missing
    /// print with no recorded failure means the caller should read the preview again.
    public func features(
        for request: ImageFeatureRequest, route: ThumbnailRoute, visionRevision: Int
    ) -> ImageFeatures? {
        let recordKey = recordKey(request, route: route, visionRevision: visionRevision)
        if let entry = state.withLock({ state -> MemoryEntry? in
            guard var entry = state.memory[recordKey] else { return nil }
            state.tick &+= 1
            entry = MemoryEntry(features: entry.features, cost: entry.cost, access: state.tick)
            state.memory[recordKey] = entry
            return entry
        }) {
            return entry.features
        }
        var print: VisionFeaturePrint?
        var hash: DifferenceHash?
        var found = false
        for kind in [ImageFeatureKind.visionPrint, .differenceHash] {
            guard
                let payload = payload(
                    for: request, route: route, kind: kind, visionRevision: visionRevision)
            else { continue }
            found = true
            if let value = payload.print { print = value }
            if let value = payload.hash { hash = value }
        }
        guard found else { return nil }
        let features = ImageFeatures(print: print, differenceHash: hash)
        remember(features, key: recordKey)
        return features
    }

    /// Publishes what one preview read produced. Kind entries that are absent stay absent, so a
    /// Vision failure is not written to disk and the next launch tries Vision again.
    public func store(
        _ features: ImageFeatures, route: ThumbnailRoute, visionRevision: Int,
        for request: ImageFeatureRequest
    ) throws {
        remember(
            features, key: recordKey(request, route: route, visionRevision: visionRevision))
        guard configuration.diskBytes > 0 else { return }
        var evictions: [String] = []
        if let print = features.print {
            evictions += try store(
                ImageFeaturePayload(
                    kind: .visionPrint, visionRevision: visionRevision, print: print),
                kind: .visionPrint, request: request, route: route, visionRevision: visionRevision)
        }
        if let hash = features.differenceHash {
            evictions += try store(
                ImageFeaturePayload(
                    kind: .differenceHash, visionRevision: visionRevision, hash: hash),
                kind: .differenceHash, request: request, route: route,
                visionRevision: visionRevision)
        }
        evict(evictions)
    }

    /// Drops memory entries, keeping disk entries (the app's memory-pressure path).
    public func releaseMemory() {
        state.withLock {
            $0.memory.removeAll()
            $0.memoryCost = 0
        }
    }

    /// Removes every feature, in memory and on disk: "clear all features" for the user or a
    /// folder that no longer exists. Call it with no work in flight, for example after pausing a
    /// pipeline, so a concurrent store is not left half-published.
    public func clear() throws {
        state.withLock { state in
            state.memory.removeAll()
            state.memoryCost = 0
            state.disk.removeAll()
            state.diskCost = 0
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Bytes of feature files currently on disk, for the timing report and budget tests.
    var diskByteCount: Int { state.withLock { $0.diskCost } }
    var memoryByteCount: Int { state.withLock { $0.memoryCost } }
    var diskEntryCount: Int { state.withLock { $0.disk.count } }

    private func recordKey(
        _ request: ImageFeatureRequest, route: ThumbnailRoute, visionRevision: Int
    ) -> ImageFeatureCacheKey {
        ImageFeatureCacheKey(
            request: request, route: route, kind: nil, visionRevision: visionRevision,
            version: configuration.payloadVersion)
    }

    private func kindKey(
        _ request: ImageFeatureRequest, route: ThumbnailRoute, kind: ImageFeatureKind,
        visionRevision: Int
    ) -> ImageFeatureCacheKey {
        ImageFeatureCacheKey(
            request: request, route: route, kind: kind, visionRevision: visionRevision,
            version: configuration.payloadVersion)
    }

    private func file(_ digest: String) -> URL {
        directory.appendingPathComponent(digest + ".feature")
    }

    /// Reads one kind's entry. A missing, undecodable or mismatched file is a miss, and a bad
    /// file is removed so the caller's fresh value can replace it.
    private func payload(
        for request: ImageFeatureRequest, route: ThumbnailRoute, kind: ImageFeatureKind,
        visionRevision: Int
    ) -> ImageFeaturePayload? {
        let digest = kindKey(request, route: route, kind: kind, visionRevision: visionRevision)
            .digest
        guard let entry = state.withLock({ $0.disk[digest] }), !entry.evicting else { return nil }
        let url = file(digest)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            forget(digest, entry)
            return nil
        }
        do {
            let payload = try PropertyListDecoder().decode(ImageFeaturePayload.self, from: data)
            guard payload.kind == kind, payload.visionRevision == visionRevision,
                let value = payload.value
            else { throw CocoaError(.fileReadCorruptFile) }
            touch(digest)
            return value
        } catch {
            removeFile(digest, entry)
            return nil
        }
    }

    /// Writes one kind's payload beside the destination, then renames it into place.
    private func store(
        _ payload: ImageFeaturePayload, kind: ImageFeatureKind, request: ImageFeatureRequest,
        route: ThumbnailRoute, visionRevision: Int
    ) throws -> [String] {
        let digest = kindKey(request, route: route, kind: kind, visionRevision: visionRevision)
            .digest
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(payload)
        guard data.count <= configuration.diskBytes else { return [] }
        let staging = directory.appendingPathComponent(UUID().uuidString + ".staging")
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging)
        guard rename(staging.path, file(digest).path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return state.withLock { state in
            // The payload for one key is a pure function of what the key names, so a concurrent
            // store of the same key publishes identical bytes and publication order is harmless.
            if let previous = state.disk[digest], !previous.evicting {
                state.diskCost -= previous.size
            }
            state.disk[digest] = DiskEntry(size: data.count, access: Date())
            state.diskCost += data.count
            return selectEvictions(&state)
        }
    }

    private func remember(_ features: ImageFeatures, key: ImageFeatureCacheKey) {
        state.withLock { state in
            state.memoryCost -= state.memory.removeValue(forKey: key)?.cost ?? 0
            let cost = max(features.approximateBytes, 1)
            guard cost <= configuration.memoryBytes else { return }
            state.tick &+= 1
            state.memory[key] = MemoryEntry(features: features, cost: cost, access: state.tick)
            state.memoryCost += cost
            while state.memoryCost > configuration.memoryBytes,
                let oldest = state.memory.min(by: { $0.value.access < $1.value.access })?.key
            {
                state.memoryCost -= state.memory.removeValue(forKey: oldest)?.cost ?? 0
            }
        }
    }

    /// Marks the least recently used entries until the budget fits. The bytes leave the index
    /// here; the files are deleted outside the mutex by ``evict(_:)``.
    private func selectEvictions(_ state: inout State) -> [String] {
        guard state.diskCost > configuration.diskBytes else { return [] }
        var evictions: [String] = []
        for (digest, entry) in state.disk.sorted(by: { $0.value.access < $1.value.access }) {
            guard state.diskCost > configuration.diskBytes else { break }
            guard !entry.evicting else { continue }
            state.disk[digest] = nil
            state.diskCost -= entry.size
            evictions.append(digest)
        }
        return evictions
    }

    private func evict(_ digests: [String]) {
        for digest in digests { try? FileManager.default.removeItem(at: file(digest)) }
    }

    /// A hit keeps LRU order in the index and in the file's date, as I1's cache does.
    private func touch(_ digest: String) {
        let now = Date()
        state.withLock { $0.disk[digest]?.access = now }
        try? FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: file(digest).path)
    }

    private func forget(_ digest: String, _ entry: DiskEntry) {
        state.withLock { state in
            guard state.disk[digest]?.size == entry.size else { return }
            state.disk[digest] = nil
            state.diskCost -= entry.size
        }
    }

    private func removeFile(_ digest: String, _ entry: DiskEntry) {
        do {
            try FileManager.default.removeItem(at: file(digest))
        } catch {
            guard !FileManager.default.fileExists(atPath: file(digest).path) else { return }
        }
        forget(digest, entry)
    }
}
