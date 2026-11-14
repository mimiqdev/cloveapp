import Darwin
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// One instance owns its app-private directory. The state mutex protects only
/// bookkeeping. Per-key gates order publication, touch and deletion of one file;
/// JPEG work and IO for unrelated keys never hold the state mutex.
public final class ThumbnailCache: Sendable {
    private struct MemoryKey: Hashable {
        let path: String
        let locationIdentity: String
        let size: Int64
        let modificationTimeBits: UInt64
        let targetPixels: Int
        let route: ThumbnailRoute

        init(request: ThumbnailRequest, route: ThumbnailRoute) {
            self.path = request.source.path
            self.locationIdentity = request.locationIdentity
            self.size = request.revision.size
            self.modificationTimeBits =
                request.revision.modificationTime.timeIntervalSince1970.bitPattern
            self.targetPixels = request.targetPixels
            self.route = route
        }
    }
    private struct MemoryEntry {
        let result: ThumbnailResult
        let cost: Int
        let access: UInt64
    }
    private struct DiskEntry {
        let generation = UUID()
        let size: Int
        var access: Date
        var evicting = false
    }
    private final class FileAccess: Sendable {
        let gate = Mutex(())
    }
    private struct FileAccessEntry {
        let access: FileAccess
        var users: Int
    }
    private struct Eviction {
        let key: String
        let entry: DiskEntry
        let access: FileAccess
    }
    private struct State {
        var memory: [MemoryKey: MemoryEntry] = [:]
        var disk: [String: DiskEntry] = [:]
        var fileAccess: [String: FileAccessEntry] = [:]
        var memoryCost = 0
        var diskCost = 0
        var tick: UInt64 = 0
    }

    public struct Configuration: Sendable {
        public var memoryBytes = 64 * 1024 * 1024
        public var diskBytes = 256 * 1024 * 1024
        public var pipelineVersion = 1
        public init() {}
    }

    private let state: Mutex<State>
    private let directory: URL
    private let configuration: Configuration
    private let pressure: any DispatchSourceMemoryPressure
    /// Test seams run outside the bookkeeping mutex and per-key gates.
    private let beforeCommit: @Sendable (URL) throws -> Void
    private let afterDecode: @Sendable () -> Void

    public convenience init(directory: URL, configuration: Configuration = .init()) throws {
        try self.init(directory: directory, configuration: configuration, beforeCommit: { _ in })
    }

    init(
        directory: URL, configuration: Configuration,
        beforeCommit: @escaping @Sendable (URL) throws -> Void,
        afterDecode: @escaping @Sendable () -> Void = {}
    ) throws {
        precondition(configuration.memoryBytes >= 0 && configuration.diskBytes >= 0)
        self.directory = directory
        self.configuration = configuration
        self.beforeCommit = beforeCommit
        self.afterDecode = afterDecode
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
            } else if url.pathExtension == "jpg" {
                let attributes = try url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
                let entry = DiskEntry(
                    size: attributes.fileSize ?? 0,
                    access: attributes.contentModificationDate ?? .distantPast)
                initial.disk[url.deletingPathExtension().lastPathComponent] = entry
                initial.diskCost += entry.size
            }
        }
        state = Mutex(initial)
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
        pressure.resume()
        evict(state.withLock { selectEvictions(&$0) })
        pressure.setEventHandler { [weak self] in self?.releaseMemory() }
    }

    deinit { pressure.cancel() }

    /// Also available to an app's memory-warning handler; disk entries are retained.
    public func releaseMemory() {
        state.withLock {
            $0.memory.removeAll()
            $0.memoryCost = 0
        }
    }

    var memoryByteCount: Int { state.withLock { $0.memoryCost } }

    /// Synchronous memory-only lookup; never reads from disk.
    public func memoryResult(for request: ThumbnailRequest) -> ThumbnailResult? {
        let routes = ThumbnailExtractor.routes(for: request)
        return state.withLock { state in
            for route in routes {
                let memKey = MemoryKey(request: request, route: route)
                if let entry = state.memory[memKey] {
                    remember(entry.result, key: memKey, state: &state)
                    return entry.result
                }
            }
            return nil
        }
    }

    public func result(for request: ThumbnailRequest) -> ThumbnailResult? {
        for route in ThumbnailExtractor.routes(for: request) {
            let memKey = MemoryKey(request: request, route: route)
            let memoryOrHasDisk = state.withLock { state -> (ThumbnailResult?, Bool) in
                if let entry = state.memory[memKey] {
                    remember(entry.result, key: memKey, state: &state)
                    return (entry.result, false)
                }
                return (nil, !state.disk.isEmpty)
            }
            if let result = memoryOrHasDisk.0 { return result }
            guard memoryOrHasDisk.1 else { continue }
            let key = key(request, route: route)
            let lookup = state.withLock { state -> (ThumbnailResult?, DiskEntry?, FileAccess?) in
                if let entry = state.memory[memKey] {
                    remember(entry.result, key: memKey, state: &state)
                    return (entry.result, nil, nil)
                }
                guard let entry = state.disk[key], !entry.evicting else { return (nil, nil, nil) }
                return (nil, entry, retainFileAccess(key, state: &state))
            }
            if let result = lookup.0 { return result }
            guard let entry = lookup.1, let access = lookup.2 else { continue }
            defer { releaseFileAccess(key) }
            let url = file(key)
            let image = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(
                        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                    image.width > 0, image.height > 0, image.bytesPerRow > 0
                else { return nil as CGImage? }
                return image
            }
            afterDecode()
            let result = access.gate.withLock { _ -> ThumbnailResult? in
                guard let image else {
                    let removed = state.withLock { state -> Bool in
                        guard state.disk[key]?.generation == entry.generation,
                            state.disk[key]?.evicting == false
                        else { return false }
                        state.disk[key]?.evicting = true
                        state.diskCost -= entry.size
                        return true
                    }
                    if removed { deleteFile(key, entry: entry) }
                    return nil
                }
                let result = ThumbnailResult.available(Thumbnail(image: image, route: route))
                let now = Date()
                let valid = state.withLock { state -> Bool in
                    // Never promote pixels from a file evicted/replaced during decode.
                    guard state.disk[key]?.generation == entry.generation,
                        state.disk[key]?.evicting == false
                    else { return false }
                    state.disk[key]?.access = now
                    remember(result, key: memKey, state: &state)
                    return true
                }
                return valid ? result : nil
            }
            if let result { return result }
        }
        return nil
    }

    /// Cache failures never prevent the pipeline from returning usable source pixels.
    public func store(_ result: ThumbnailResult, for request: ThumbnailRequest) throws {
        let route: ThumbnailRoute
        if case .available(let thumbnail) = result {
            route = thumbnail.route
        } else {
            route = ThumbnailExtractor.routes(for: request)[0]
        }
        let memKey = MemoryKey(request: request, route: route)
        state.withLock { remember(result, key: memKey, state: &$0) }
        guard case .available(let thumbnail) = result, configuration.diskBytes > 0 else { return }
        let key = key(request, route: route)
        let data = try jpeg(thumbnail.image)
        guard data.count <= configuration.diskBytes else { return }
        let staging = directory.appendingPathComponent(UUID().uuidString + ".staging")
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging)
        try beforeCommit(staging)
        let access = state.withLock { retainFileAccess(key, state: &$0) }
        defer { releaseFileAccess(key) }
        let evictions = try access.gate.withLock { _ in
            guard rename(staging.path, file(key).path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return state.withLock { state in
                if let previous = state.disk[key], !previous.evicting {
                    state.diskCost -= previous.size
                }
                state.disk[key] = DiskEntry(size: data.count, access: Date())
                state.diskCost += data.count
                // Publication order determines the winner in both tiers, even if
                // another store began encoding first and finished staging later.
                remember(result, key: memKey, state: &state)
                return selectEvictions(&state)
            }
        }
        evict(evictions)
    }

    private func jpeg(_ image: CGImage) throws -> Data {
        try autoreleasepool {
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(
                destination, image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data as Data
        }
    }

    private func key(_ request: ThumbnailRequest, route: ThumbnailRoute) -> String {
        ThumbnailCacheKey(request: request, route: route, version: configuration.pipelineVersion)
            .digest
    }

    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }

    private func remember(_ result: ThumbnailResult, key: MemoryKey, state: inout State) {
        state.memoryCost -= state.memory.removeValue(forKey: key)?.cost ?? 0
        let cost: Int
        if case .available(let image) = result { cost = image.decodedBytes } else { cost = 256 }
        guard cost <= configuration.memoryBytes else { return }
        state.tick &+= 1
        state.memory[key] = MemoryEntry(result: result, cost: cost, access: state.tick)
        state.memoryCost += cost
        while state.memoryCost > configuration.memoryBytes,
            let oldest = state.memory.min(by: { $0.value.access < $1.value.access })?.key
        {
            state.memoryCost -= state.memory.removeValue(forKey: oldest)?.cost ?? 0
        }
    }

    private func retainFileAccess(_ key: String, state: inout State) -> FileAccess {
        if var entry = state.fileAccess[key] {
            entry.users += 1
            state.fileAccess[key] = entry
            return entry.access
        }
        let access = FileAccess()
        state.fileAccess[key] = FileAccessEntry(access: access, users: 1)
        return access
    }

    private func releaseFileAccess(_ key: String) {
        state.withLock { state in
            guard var entry = state.fileAccess[key] else { return }
            entry.users -= 1
            state.fileAccess[key] = entry.users == 0 ? nil : entry
        }
    }

    private func selectEvictions(_ state: inout State) -> [Eviction] {
        guard state.diskCost > configuration.diskBytes else { return [] }
        var evictions: [Eviction] = []
        for (key, entry) in state.disk.sorted(by: { $0.value.access < $1.value.access }) {
            guard state.diskCost > configuration.diskBytes else { break }
            guard !entry.evicting else { continue }
            state.disk[key]?.evicting = true
            state.diskCost -= entry.size
            evictions.append(
                Eviction(key: key, entry: entry, access: retainFileAccess(key, state: &state)))
        }
        return evictions
    }

    private func evict(_ evictions: [Eviction]) {
        for eviction in evictions {
            eviction.access.gate.withLock { _ in
                // A newer store may already have replaced this destination.
                if state.withLock({
                    $0.disk[eviction.key]?.generation == eviction.entry.generation
                        && $0.disk[eviction.key]?.evicting == true
                }) {
                    deleteFile(eviction.key, entry: eviction.entry)
                }
            }
            releaseFileAccess(eviction.key)
        }
    }

    /// Called with this key's gate held, never with the bookkeeping mutex held.
    private func deleteFile(_ key: String, entry: DiskEntry) {
        let url = file(key)
        let removed: Bool
        do {
            try FileManager.default.removeItem(at: url)
            removed = true
        } catch {
            removed = !FileManager.default.fileExists(atPath: url.path)
        }
        state.withLock {
            if removed {
                $0.disk[key] = nil
            } else {
                // Failed cleanup still occupies disk bytes and must stay accounted.
                $0.disk[key]?.evicting = false
                $0.diskCost += entry.size
            }
        }
    }
}
