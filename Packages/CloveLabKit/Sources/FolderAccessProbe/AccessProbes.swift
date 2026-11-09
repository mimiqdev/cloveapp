import Foundation
import LabSupport

public struct AccessProbeResult: Sendable {
    public var events: [AccessEvent] = []
    public var context: [String: String] = [:]
    public var measurements: [LabMeasurement] = []
    public init() {}
}

public enum AccessProbes {
    public static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeUUIDStringKey, .volumeLocalizedFormatDescriptionKey,
        .volumeIsReadOnlyKey, .isWritableKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityForOpportunisticUsageKey,
        .volumeTotalCapacityKey,
    ]

    /// A false scope result is recorded, not fabricated into an NSError: app-owned URLs can still work.
    public static func run(at url: URL, write: Bool) -> AccessProbeResult {
        var result = AccessProbeResult()
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        result.events.append(
            AccessEvent(
                .startAccess, "startAccessingSecurityScopedResource=\(scope) (no NSError API)"))
        for key in resourceKeys {
            do {
                var fresh = url
                fresh.removeAllCachedResourceValues()
                let values = try fresh.resourceValues(forKeys: [key])
                let text =
                    values.allValues[key].map { String(describing: $0) } ?? "unavailable (nil)"
                result.context[key.rawValue] = text
                result.events.append(AccessEvent(.resource, "\(key.rawValue)=\(text)"))
            } catch {
                result.context[key.rawValue] = "error"
                result.events.append(AccessEvent(.resource, key.rawValue, error: error))
            }
        }
        let start = ContinuousClock.now
        do {
            let names = try coordinatedRead(at: url)
            result.events.append(
                AccessEvent(.read, "Coordinated directory read: \(names.count) entries"))
        } catch {
            result.events.append(
                AccessEvent(.read, "Coordinated directory read failed", error: error))
        }
        result.measurements.append(
            LabMeasurement(name: "directory-read", value: milliseconds(since: start), unit: "ms"))
        if write { writeProbe(at: url, into: &result) }
        return result
    }

    public static func coordinatedRead(at url: URL) throws -> [URL] {
        var coordinationError: NSError?
        var outcome: Result<[URL], Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinated in
            outcome = Result {
                try FileManager.default.contentsOfDirectory(
                    at: coordinated, includingPropertiesForKeys: nil)
            }
        }
        if let coordinationError { throw coordinationError }
        return try outcome?.get() ?? []
    }

    private static func writeProbe(at url: URL, into result: inout AccessProbeResult) {
        let start = ContinuousClock.now
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) {
            coordinated in
            let directory = coordinated.appendingPathComponent(
                "clove-lab-folder-access", isDirectory: true)
            let probe = directory.appendingPathComponent("probe-\(UUID().uuidString).txt")
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let payload = Data("Clove Folder access write/read-back probe\n".utf8)
                try payload.write(to: probe, options: [.withoutOverwriting])
                let readback = try Data(contentsOf: probe)
                guard readback == payload else { throw CocoaError(.fileReadCorruptFile) }
                result.events.append(
                    AccessEvent(
                        .write, "Small file write and read-back confirmed (\(payload.count) bytes)")
                )
            } catch {
                result.events.append(
                    AccessEvent(.write, "Small file write/read-back failed", error: error))
            }
            if FileManager.default.fileExists(atPath: probe.path) {
                do {
                    try FileManager.default.removeItem(at: probe)
                    result.events.append(AccessEvent(.cleanup, "Removed own probe file"))
                } catch {
                    result.events.append(
                        AccessEvent(
                            .cleanup, "Remove own probe failed: \(probe.lastPathComponent)",
                            error: error))
                }
            }
        }
        if let coordinationError {
            result.events.append(
                AccessEvent(.write, "Write coordination failed", error: coordinationError))
        }
        result.measurements.append(
            LabMeasurement(
                name: "small-write-readback-cleanup", value: milliseconds(since: start), unit: "ms")
        )
    }

    /// Fresh URL each time; do not reuse resource-value caches when testing disconnects.
    public static func reachable(_ url: URL) throws -> Bool {
        var fresh = URL(fileURLWithPath: url.path, isDirectory: true)
        fresh.removeAllCachedResourceValues()
        return try fresh.checkResourceIsReachable()
    }

    public static func milliseconds(
        since instant: ContinuousClock.Instant, until end: ContinuousClock.Instant = .now
    ) -> Double {
        let parts = instant.duration(to: end).components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}

public struct AccessPresenterObservation: Sendable {
    public var event: AccessEvent
    public var instant: ContinuousClock.Instant
}

/// File presenter callbacks are advisory. The lock protects the URL and callback log across queues.
public final class AccessPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL
    private var events: [AccessPresenterObservation] = []
    public let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    public init(url: URL) { self.url = url }
    public var presentedItemURL: URL? { lock.withLock { url } }

    public func drain() -> [AccessPresenterObservation] {
        lock.withLock {
            defer { events.removeAll() }
            return events
        }
    }

    private func record(_ text: String) {
        lock.withLock {
            events.append(
                AccessPresenterObservation(
                    event: AccessEvent(.watch, "file-presenter: \(text)"), instant: .now))
        }
    }

    public func presentedItemDidChange() { record("item changed (not proof of disconnect)") }
    public func presentedSubitemDidChange(at url: URL) {
        record("subitem changed: \(url.lastPathComponent)")
    }
    public func presentedItemDidMove(to newURL: URL) {
        lock.withLock { url = newURL }
        record("item moved to \(newURL.path)")
    }
    public func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        record("item deletion requested")
        completionHandler(nil)
    }
    public func accommodatePresentedItemEviction(
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        record("item eviction requested")
        NSFileCoordinator.removeFilePresenter(self)
        completionHandler(nil)
    }
}
