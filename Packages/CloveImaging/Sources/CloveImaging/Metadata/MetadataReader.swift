import Foundation
import ImageIO

/// Reads the caller-selected primary file. For a RAW set, pass the RAW URL.
/// Reads one ImageIO property dictionary per file, with caching disabled; never decodes
/// pixels or enumerates XMP packets. Serial preference is EXIF body, ExifAux, then makers.
public struct MetadataReader: Sendable {
    public let maximumConcurrentReads: Int
    private let readFile: @Sendable (URL) -> MetadataReadOutcome

    public init(maximumConcurrentReads: Int = 4) {
        self.init(maximumConcurrentReads: maximumConcurrentReads) { Self.load($0) }
    }

    init(
        maximumConcurrentReads: Int,
        readFile: @escaping @Sendable (URL) -> MetadataReadOutcome
    ) {
        precondition(maximumConcurrentReads > 0, "Metadata concurrency must be positive")
        self.maximumConcurrentReads = maximumConcurrentReads
        self.readFile = readFile
    }

    /// Synchronous property I/O; call from a background task. Cancellation is checked before
    /// and after ImageIO, whose current property read cannot itself be interrupted.
    public func read(url: URL) -> MetadataFileResult {
        guard !Task.isCancelled else { return .init(url: url, outcome: .failure(.cancelled)) }
        let outcome = autoreleasepool { readFile(url) }
        return .init(url: url, outcome: Task.isCancelled ? .failure(.cancelled) : outcome)
    }

    /// Bounded rolling admission. Results preserve input order and duplicates. A failed file
    /// never fails the batch. Cancellation drains in-flight reads and marks all remaining
    /// entries cancelled, without admitting further I/O.
    public func read(urls: [URL]) async -> [MetadataFileResult] {
        await withTaskGroup(of: (Int, MetadataFileResult).self) { group in
            var results = urls.map { MetadataFileResult(url: $0, outcome: .failure(.cancelled)) }
            var next = 0
            func admit() {
                let index = next
                let url = urls[index]
                group.addTask {
                    guard !Task.isCancelled else {
                        return (index, MetadataFileResult(url: url, outcome: .failure(.cancelled)))
                    }
                    let outcome = await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            continuation.resume(returning: autoreleasepool { readFile(url) })
                        }
                    }
                    return (
                        index,
                        MetadataFileResult(
                            url: url, outcome: Task.isCancelled ? .failure(.cancelled) : outcome)
                    )
                }
                next += 1
            }
            if !Task.isCancelled {
                for _ in 0..<min(maximumConcurrentReads, urls.count) { admit() }
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if Task.isCancelled {
                    group.cancelAll()
                } else if next < urls.count {
                    admit()
                }
            }
            return results
        }
    }

    static func load(
        _ url: URL,
        fileDates: (URL) throws -> (creation: Date?, modification: Date?) = { url in
            let values = try url.resourceValues(forKeys: [
                .creationDateKey, .contentModificationDateKey,
            ])
            return (values.creationDate, values.contentModificationDate)
        }
    ) -> MetadataReadOutcome {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure(.unreadableFile)
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                as? [String: Any]
        else { return .failure(.propertiesUnavailable) }
        // Capture metadata is still useful if the provider cannot supply resource dates.
        let dates = try? fileDates(url)
        return .success(
            MetadataParser.parse(
                properties: properties, creationDate: dates?.creation,
                modificationDate: dates?.modification))
    }
}
