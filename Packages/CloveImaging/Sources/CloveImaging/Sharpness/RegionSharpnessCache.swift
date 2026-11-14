import CryptoKit
import Darwin
import Foundation
import Synchronization

/// Session-free disk identity for one cached sharpness record (#239).
///
/// Unlike ``SharpnessResultKey`` in the memory tier, this omits `folderSession` so reopening a
/// folder across sessions reuses prior analysis. Any change to the primary file's standardized
/// path, byte size, modification timestamp, `parametersVersion`, or `payloadVersion` produces a
/// distinct digest.
struct RegionSharpnessDiskKey: Hashable, Encodable {
    let path: String
    let size: Int64
    let modificationTimeBitPattern: UInt64
    let parametersVersion: Int
    let payloadVersion: Int

    init(
        photo: URL, revision: ThumbnailRevision, parametersVersion: Int,
        payloadVersion: Int
    ) {
        self.path = photo.standardizedFileURL.path
        self.size = revision.size
        // Preserve the caller's full timestamp precision rather than rounding to seconds.
        self.modificationTimeBitPattern = revision.modificationTime.timeIntervalSince1970.bitPattern
        self.parametersVersion = parametersVersion
        self.payloadVersion = payloadVersion
    }

    enum CodingKeys: String, CodingKey {
        case path, size, modificationTime, parametersVersion, payloadVersion
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(path, forKey: .path)
        try values.encode(size, forKey: .size)
        try values.encode(modificationTimeBitPattern, forKey: .modificationTime)
        try values.encode(parametersVersion, forKey: .parametersVersion)
        try values.encode(payloadVersion, forKey: .payloadVersion)
    }

    /// SHA-256 hex filename so the file system sees no long or nested paths.
    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let data = try encoder.encode(self)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            preconditionFailure("Cannot encode sharpness cache identity: \(error)")
        }
    }
}

/// On-disk JSON payload for one photo's sharpness analysis (#239).
///
/// The filename digest already encodes these identity fields; storing them inside the JSON catches
/// a file copied or renamed into the wrong slot and allows `payloadVersion` validation on decode.
struct RegionSharpnessPayload: Codable, Sendable {
    let payloadVersion: Int
    let photoPath: String
    let size: Int64
    let modificationTimeBitPattern: UInt64
    let parametersVersion: Int
    let analysis: RegionSharpnessAnalysis
}

/// App-private disk tier for ``RegionSharpnessRecord`` (#239), modeled on ``ImageFeatureCache``.
///
/// Stores one JSON file per `(photo, revision, parametersVersion)` under `Library/Caches` (so
/// reopening a folder across sessions serves prior results without re-running Vision/AF work).
/// Encoding, staging writes, atomic replacement, reads, and deletions all happen outside the
/// bookkeeping mutex. Cleanup uses LRU byte-budget eviction plus `payloadVersion` misses — no TTL
/// timers and no scheduled sweeps.
public final class RegionSharpnessCache: Sendable {
    public struct Configuration: Sendable {
        /// Disk budget for sharpness JSON files. Compact records are ~1–2 KiB each, so 16 MiB
        /// holds thousands of analysed photos.
        public var diskBytes = 16 * 1024 * 1024
        /// Bump when the on-disk payload layout changes; old entries become misses.
        public var payloadVersion = 1
        public init() {}
    }

    private struct DiskEntry {
        let generation = UUID()
        let size: Int
        var access: Date
        var evicting = false
    }

    private struct State {
        var disk: [String: DiskEntry] = [:]
        var diskCost = 0
    }

    private let state: Mutex<State>
    private let directory: URL
    private let configuration: Configuration

    /// One instance owns its directory, which is excluded from backup like ``ImageFeatureCache``.
    public init(directory: URL, configuration: Configuration = Configuration()) throws {
        precondition(configuration.diskBytes >= 0)
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
            guard url.pathExtension == "json" else { continue }
            guard
                let attributes = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
            else { continue }
            let entry = DiskEntry(
                size: attributes.fileSize ?? 0,
                access: attributes.contentModificationDate ?? .distantPast)
            initial.disk[url.deletingPathExtension().lastPathComponent] = entry
            initial.diskCost += entry.size
        }
        state = Mutex(initial)
        evict(state.withLock { selectEvictions(&$0) })
    }

    /// Reads the cached analysis matching `(key.photo, key.revision, key.parametersVersion)`,
    /// ignoring `key.folderSession`.
    public func analysis(for key: SharpnessResultKey) -> RegionSharpnessAnalysis? {
        analysis(
            photo: key.photo, revision: key.revision, parametersVersion: key.parametersVersion)
    }

    /// Reads the cached analysis for a standardized photo URL, revision, and parameters version.
    public func analysis(
        photo: URL, revision: ThumbnailRevision, parametersVersion: Int
    ) -> RegionSharpnessAnalysis? {
        let diskKey = diskKey(
            photo: photo, revision: revision, parametersVersion: parametersVersion)
        let digest = diskKey.digest
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
            let payload = try JSONDecoder().decode(RegionSharpnessPayload.self, from: data)
            guard payload.payloadVersion == configuration.payloadVersion,
                payload.photoPath == diskKey.path,
                payload.size == diskKey.size,
                payload.modificationTimeBitPattern == diskKey.modificationTimeBitPattern,
                payload.parametersVersion == diskKey.parametersVersion,
                Self.isPersistable(payload.analysis)
            else { throw CocoaError(.fileReadCorruptFile) }
            touch(digest)
            return payload.analysis
        } catch {
            removeFile(digest, entry)
            return nil
        }
    }

    /// Persists one finished sharpness record on disk under its session-free key, unless its
    /// acquisition or preview reported `staleSource`, `queueFull`, or `closed`.
    public func store(_ record: RegionSharpnessRecord) throws {
        try store(record.analysis, for: record.key)
    }

    /// Persists one finished analysis for `(key.photo, key.revision, key.parametersVersion)`,
    /// ignoring `key.folderSession`.
    public func store(_ analysis: RegionSharpnessAnalysis, for key: SharpnessResultKey) throws {
        guard Self.isPersistable(analysis) else { return }
        guard configuration.diskBytes > 0 else { return }
        let diskKey = diskKey(
            photo: key.photo, revision: key.revision, parametersVersion: key.parametersVersion)
        let digest = diskKey.digest
        let payload = RegionSharpnessPayload(
            payloadVersion: configuration.payloadVersion,
            photoPath: diskKey.path,
            size: diskKey.size,
            modificationTimeBitPattern: diskKey.modificationTimeBitPattern,
            parametersVersion: diskKey.parametersVersion,
            analysis: analysis)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        guard data.count <= configuration.diskBytes else { return }
        let staging = directory.appendingPathComponent(UUID().uuidString + ".staging")
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging)
        guard rename(staging.path, file(digest).path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let evictions = state.withLock { state -> [String] in
            if let previous = state.disk[digest], !previous.evicting {
                state.diskCost -= previous.size
            }
            state.disk[digest] = DiskEntry(size: data.count, access: Date())
            state.diskCost += data.count
            return selectEvictions(&state)
        }
        evict(evictions)
    }

    /// Removes every cached sharpness file on disk. Call with no work in flight so a concurrent
    /// store is not left half-published.
    public func clear() throws {
        state.withLock { state in
            state.disk.removeAll()
            state.diskCost = 0
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Whether an analysis represents a durable answer rather than a `staleSource` race or
    /// scheduler contention.
    static func isPersistable(_ analysis: RegionSharpnessAnalysis) -> Bool {
        switch analysis.acquisitionFailure {
        case .staleSource, .queueFull, .closed:
            return false
        case nil, .cannotOpen, .noUsablePreview:
            break
        }
        if case .unavailable(.previewFailed(let failure)) = analysis.faces {
            switch failure {
            case .staleSource, .queueFull, .closed:
                return false
            case .cannotOpen, .noUsablePreview:
                break
            }
        }
        return true
    }

    /// Bytes and entry counts currently tracked on disk, for diagnostics and budget tests.
    var diskByteCount: Int { state.withLock { $0.diskCost } }
    var diskEntryCount: Int { state.withLock { $0.disk.count } }

    private func diskKey(
        photo: URL, revision: ThumbnailRevision, parametersVersion: Int
    ) -> RegionSharpnessDiskKey {
        RegionSharpnessDiskKey(
            photo: photo, revision: revision, parametersVersion: parametersVersion,
            payloadVersion: configuration.payloadVersion)
    }

    private func file(_ digest: String) -> URL {
        directory.appendingPathComponent(digest + ".json")
    }

    /// Marks the least recently used entries until the budget fits. Bytes leave the index under
    /// the mutex; file deletion happens outside it in ``evict(_:)``.
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

    /// Updates LRU order in the in-memory disk index without writing file metadata.
    private func touch(_ digest: String) {
        let now = Date()
        state.withLock { $0.disk[digest]?.access = now }
    }

    private func forget(_ digest: String, _ entry: DiskEntry) {
        state.withLock { state in
            guard state.disk[digest]?.generation == entry.generation else { return }
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
