import Foundation

public enum AccessFill {
    /// Bounded allocation with real bytes, never a sparse truncate. Dedicated test media only.
    public static func add(at folder: URL, maximumBytes: Int = 256 * 1_024 * 1_024) -> [AccessEvent]
    {
        var events: [AccessEvent] = []
        let scope = folder.startAccessingSecurityScopedResource()
        defer { if scope { folder.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: folder, options: [], error: &coordinationError
        ) { url in
            let directory = url.appendingPathComponent("clove-lab-s1", isDirectory: true)
            let file = directory.appendingPathComponent("fill-s1-\(UUID().uuidString).bin")
            var written = 0
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                try Data().write(to: file, options: .withoutOverwriting)
                let handle = try FileHandle(forWritingTo: file)
                defer {
                    do { try handle.close() } catch {
                        events.append(AccessEvent(.write, "Fill close failed", error: error))
                    }
                }
                let block = Data(repeating: 0xA5, count: 1_024 * 1_024)
                while written < maximumBytes && !Task.isCancelled {
                    let count = min(block.count, maximumBytes - written)
                    try handle.write(contentsOf: block.prefix(count))
                    written += count
                }
                try handle.synchronize()
                events.append(
                    AccessEvent(
                        .write,
                        "Fill wrote and synchronized \(written) bytes to \(file.lastPathComponent); file retained until cleanup"
                    ))
            } catch {
                events.append(
                    AccessEvent(
                        .write,
                        "Fill failed after \(written) bytes; partial file retained: \(file.lastPathComponent)",
                        error: error))
            }
        }
        if let coordinationError {
            events.append(AccessEvent(.write, "Fill coordination failed", error: coordinationError))
        }
        return events
    }

    public static func isFillFile(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return url.pathExtension == "bin" && name.hasPrefix("fill-s1-")
            && UUID(uuidString: String(name.dropFirst("fill-s1-".count))) != nil
    }

    public static func clean(at folder: URL) -> [AccessEvent] {
        var events: [AccessEvent] = []
        let scope = folder.startAccessingSecurityScopedResource()
        defer { if scope { folder.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: folder, options: [], error: &coordinationError
        ) { url in
            let directory = url.appendingPathComponent("clove-lab-s1", isDirectory: true)
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)
                for file in files where isFillFile(file) {
                    do {
                        try FileManager.default.removeItem(at: file)
                        events.append(AccessEvent(.cleanup, "Removed \(file.lastPathComponent)"))
                    } catch {
                        events.append(
                            AccessEvent(
                                .cleanup, "Could not remove \(file.lastPathComponent)", error: error
                            ))
                    }
                }
                events.append(AccessEvent(.cleanup, "Fill cleanup finished; other files retained"))
            } catch {
                events.append(AccessEvent(.cleanup, "Could not list fill directory", error: error))
            }
        }
        if let coordinationError {
            events.append(
                AccessEvent(.cleanup, "Fill cleanup coordination failed", error: coordinationError))
        }
        return events
    }
}
