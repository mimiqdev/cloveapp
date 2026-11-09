import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One instance owns its app-private directory. The lock protects both tiers and
/// the disk index; all IO is performed from the pipeline's bounded worker slots.
public final class ThumbnailCache: @unchecked Sendable {
    private struct MemoryEntry {
        let result: ThumbnailResult
        let cost: Int
        let access: UInt64
    }
    private struct DiskEntry {
        let size: Int
        var access: Date
    }

    public struct Configuration: Sendable {
        public var memoryBytes = 64 * 1024 * 1024
        public var diskBytes = 256 * 1024 * 1024
        public var pipelineVersion = 1
        public init() {}
    }

    private let lock = NSLock()
    private let directory: URL
    private let configuration: Configuration
    private var memory: [String: MemoryEntry] = [:]
    private var disk: [String: DiskEntry] = [:]
    private var memoryCost = 0
    private var diskCost = 0
    private var tick: UInt64 = 0
    private let pressure: any DispatchSourceMemoryPressure
    /// Test seam: fail after the complete staging write, before atomic rename.
    private let beforeCommit: @Sendable (URL) throws -> Void

    public convenience init(directory: URL, configuration: Configuration = .init()) throws {
        try self.init(directory: directory, configuration: configuration, beforeCommit: { _ in })
    }

    init(
        directory: URL, configuration: Configuration,
        beforeCommit: @escaping @Sendable (URL) throws -> Void
    ) throws {
        precondition(configuration.memoryBytes >= 0 && configuration.diskBytes >= 0)
        self.directory = directory
        self.configuration = configuration
        self.beforeCommit = beforeCommit
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
        // A resumed source can also be safely destroyed if directory setup throws.
        pressure.resume()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var privateDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateDirectory.setResourceValues(values)
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
                disk[url.deletingPathExtension().lastPathComponent] = entry
                diskCost += entry.size
            }
        }
        evictDisk()
        pressure.setEventHandler { [weak self] in self?.releaseMemory() }
    }

    deinit { pressure.cancel() }

    /// Also available to an app's memory-warning handler; disk entries are retained.
    public func releaseMemory() {
        lock.withLock {
            memory.removeAll()
            memoryCost = 0
        }
    }

    public func result(for request: ThumbnailRequest) -> ThumbnailResult? {
        lock.withLock {
            for route in ThumbnailExtractor.routes(for: request) {
                let key = key(request, route: route)
                if let entry = memory[key] {
                    remember(entry.result, key: key)
                    return entry.result
                }
                guard var entry = disk[key] else { continue }
                let url = file(key)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(
                        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                    image.dataProvider?.data != nil
                else {
                    removeDisk(key)
                    continue
                }
                entry.access = Date()
                disk[key] = entry
                try? FileManager.default.setAttributes(
                    [.modificationDate: entry.access], ofItemAtPath: url.path)
                let result = ThumbnailResult.available(Thumbnail(image: image, route: route))
                remember(result, key: key)
                return result
            }
            return nil
        }
    }

    /// Cache failures never prevent the pipeline from returning usable source pixels.
    public func store(_ result: ThumbnailResult, for request: ThumbnailRequest) throws {
        try lock.withLock {
            let route: ThumbnailRoute
            if case .available(let thumbnail) = result {
                route = thumbnail.route
            } else {
                route = ThumbnailExtractor.routes(for: request)[0]
            }
            let key = key(request, route: route)
            remember(result, key: key)
            guard case .available(let thumbnail) = result, configuration.diskBytes > 0 else {
                return
            }
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(
                destination, thumbnail.image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard data.length <= configuration.diskBytes else { return }
            let staging = directory.appendingPathComponent(UUID().uuidString + ".staging")
            defer { try? FileManager.default.removeItem(at: staging) }
            try (data as Data).write(to: staging)
            try beforeCommit(staging)
            guard rename(staging.path, file(key).path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            diskCost -= disk[key]?.size ?? 0
            disk[key] = DiskEntry(size: data.length, access: Date())
            diskCost += data.length
            evictDisk()
        }
    }

    private func key(_ request: ThumbnailRequest, route: ThumbnailRoute) -> String {
        ThumbnailCacheKey(request: request, route: route, version: configuration.pipelineVersion)
            .digest
    }

    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }

    private func remember(_ result: ThumbnailResult, key: String) {
        memoryCost -= memory.removeValue(forKey: key)?.cost ?? 0
        let cost: Int
        if case .available(let image) = result { cost = image.decodedBytes } else { cost = 256 }
        guard cost <= configuration.memoryBytes else { return }
        tick &+= 1
        memory[key] = MemoryEntry(result: result, cost: cost, access: tick)
        memoryCost += cost
        while memoryCost > configuration.memoryBytes,
            let oldest = memory.min(by: { $0.value.access < $1.value.access })?.key
        {
            memoryCost -= memory.removeValue(forKey: oldest)?.cost ?? 0
        }
    }

    private func evictDisk() {
        for (key, _) in disk.sorted(by: { $0.value.access < $1.value.access }) {
            guard diskCost > configuration.diskBytes else { break }
            removeDisk(key)
        }
    }

    private func removeDisk(_ key: String) {
        let url = file(key)
        do { try FileManager.default.removeItem(at: url) } catch {
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
        }
        diskCost -= disk.removeValue(forKey: key)?.size ?? 0
    }
}
