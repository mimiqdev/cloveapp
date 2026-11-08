import Foundation
import SpikeSupport

public struct AccessSnapshot: Sendable {
    public var recents: [AccessRecent]
    public var selected: URL?
    public var report: LabReport
    public var events: [AccessEvent]
    public var watching: Bool
}

/// Serializes blocking file work away from SwiftUI. A watch owns one balanced security scope.
public actor AccessExperiment {
    private let storeURL: URL
    private var recents = AccessRecents()
    private var storageValid = true
    private var selected: URL?
    private var media: AccessMedia = .unknown
    private var events: [AccessEvent] = []
    private var context: [String: String] = [:]
    private var measurements: [LabMeasurement] = []
    private var presenter: AccessPresenter?
    private var watchScope = false
    private var watchURL: URL?
    private var watchVolumeURL: URL?
    private var watchStart: ContinuousClock.Instant?
    private var marker: ContinuousClock.Instant?
    private var lastSuccess: ContinuousClock.Instant?
    private var detected = false

    public init(storeURL: URL) { self.storeURL = storeURL }

    public func load() -> AccessSnapshot {
        do {
            recents = try AccessRecents.load(from: storeURL)
            events.append(AccessEvent(.storage, "Loaded \(recents.records.count) Lab-only Recents"))
        } catch {
            storageValid = false
            events.append(
                AccessEvent(
                    .storage, "Recents load failed; existing file will not be overwritten",
                    error: error))
        }
        return snapshot()
    }

    public func pick(_ url: URL, media: AccessMedia) -> AccessSnapshot {
        stopWatch()
        selected = url
        self.media = media
        context = ["path": url.path, "media": media.rawValue]
        events.append(AccessEvent(.bookmarkCreate, "Picked \(url.path), media=\(media.rawValue)"))
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        events.append(AccessEvent(.startAccess, "pick: scope=\(scope), no NSError API"))
        do {
            let data = try AccessBookmark.encode(url)
            let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey])
            let record = AccessRecent(
                bookmark: data, pathSummary: url.path, volumeName: values?.volumeName,
                volumeUUID: values?.volumeUUIDString, media: media)
            // Never deduplicate by volume name; two cards may share a label.
            recents.records.removeAll {
                record.volumeUUID != nil && $0.pathSummary == url.path
                    && $0.volumeUUID == record.volumeUUID
            }
            recents.records.insert(record, at: 0)
            events.append(
                AccessEvent(.bookmarkCreate, "Default bookmark created (\(data.count) bytes)"))
            do {
                try persist()
                events.append(AccessEvent(.storage, "Default bookmark saved to Lab Recents"))
            } catch {
                events.append(AccessEvent(.storage, "Save Lab Recents failed", error: error))
            }
            do {
                let minimal = try AccessBookmark.encode(url, minimal: true)
                let resolved = try AccessBookmark.resolve(minimal)
                events.append(
                    AccessEvent(
                        .bookmarkResolve,
                        "Comparison minimal bookmark: \(minimal.count) bytes, stale=\(resolved.stale), path=\(resolved.url.path)"
                    ))
            } catch {
                events.append(
                    AccessEvent(.bookmarkResolve, "Minimal comparison failed", error: error))
            }
        } catch {
            events.append(AccessEvent(.bookmarkCreate, "Create bookmark failed", error: error))
        }
        return snapshot()
    }

    public func reopen(_ id: UUID) -> AccessSnapshot {
        stopWatch()
        selected = nil
        guard let index = recents.records.firstIndex(where: { $0.id == id }) else {
            return snapshot()
        }
        let record = recents.records[index]
        media = record.media
        context = ["path": record.pathSummary, "media": media.rawValue]
        do {
            let resolved = try AccessBookmark.resolve(record.bookmark)
            events.append(
                AccessEvent(
                    .bookmarkResolve,
                    "Resolved \(record.pathSummary) → \(resolved.url.path), stale=\(resolved.stale)"
                ))
            selected = resolved.url
            context["path"] = resolved.url.path
            context["bookmarkStale"] = String(resolved.stale)
            let scope = resolved.url.startAccessingSecurityScopedResource()
            defer { if scope { resolved.url.stopAccessingSecurityScopedResource() } }
            events.append(AccessEvent(.startAccess, "reopen: scope=\(scope), no NSError API"))
            // A successful resolution alone does not establish accessibility or writability.
            do {
                let names = try AccessProbes.coordinatedRead(at: resolved.url)
                events.append(AccessEvent(.read, "Reopen read confirmed: \(names.count) entries"))
            } catch {
                events.append(AccessEvent(.read, "Reopen read failed", error: error))
                return snapshot()
            }
            do {
                if resolved.stale {
                    recents.records[index] = try AccessBookmark.refreshed(record, at: resolved.url)
                    events.append(
                        AccessEvent(.bookmarkCreate, "Re-created stale bookmark while scope held"))
                } else {
                    recents.records[index].lastOpened = Date()
                    recents.records[index].pathSummary = resolved.url.path
                }
                recents.records.sort { $0.lastOpened > $1.lastOpened }
                try persist()
            } catch {
                events.append(AccessEvent(.storage, "Refresh/save Recents failed", error: error))
            }
        } catch {
            events.append(
                AccessEvent(
                    .bookmarkResolve, "Reopen failed; select the folder again", error: error))
        }
        return snapshot()
    }

    private func persist() throws {
        guard storageValid else { throw CocoaError(.coderReadCorrupt) }
        try recents.save(to: storeURL)
    }

    public func probe(write: Bool, scenario: String) -> AccessSnapshot {
        guard let selected else { return snapshot() }
        events.append(
            AccessEvent(
                .read, "Scenario: \(scenario); path=\(selected.path); media=\(media.rawValue)"))
        let result = AccessProbes.run(at: selected, write: write)
        events += result.events
        context.merge(result.context) { _, new in new }
        context["scenario"] = scenario
        measurements += result.measurements.map { measurement in
            var tagged = measurement
            tagged.tags = ["scenario": scenario, "path": selected.path, "media": media.rawValue]
            return tagged
        }
        return snapshot()
    }

    public func startWatch() -> AccessSnapshot {
        stopWatch()
        guard let selected else { return snapshot() }
        watchURL = selected
        watchScope = selected.startAccessingSecurityScopedResource()
        watchVolumeURL = try? selected.resourceValues(forKeys: [.volumeURLKey]).volume
        watchStart = .now
        marker = nil
        lastSuccess = nil
        detected = false
        let item = AccessPresenter(url: selected)
        presenter = item
        NSFileCoordinator.addFilePresenter(item)
        events.append(
            AccessEvent(
                .watch,
                "Started 500 ms reachability polling and NSFilePresenter; scope=\(watchScope). No public UIKit volume-unmount notification; NSWorkspace is macOS-only."
            ))
        return poll()
    }

    public func markDisconnect() -> AccessSnapshot {
        guard watchStart != nil else { return snapshot() }
        marker = .now
        events.append(
            AccessEvent(
                .watch,
                "Operator marker: unplug now. This precedes the physical pull; marker latency includes human delay."
            ))
        return snapshot()
    }

    public func poll() -> AccessSnapshot {
        guard let watchURL, let watchStart else { return snapshot() }
        drainPresenter(since: watchStart)
        guard !detected else { return snapshot() }
        let pollStart = ContinuousClock.now
        do {
            if try AccessProbes.reachable(watchURL) {
                lastSuccess = .now
                context["watchLastReachableAt"] = Date().ISO8601Format()
            } else {
                detect(error: nil, detail: "checkResourceIsReachable=false (no NSError)")
            }
        } catch {
            detect(error: error, detail: "checkResourceIsReachable threw")
        }
        let duration = AccessProbes.milliseconds(since: pollStart)
        // Keep reports bounded during long waits; record slow calls and the failing call.
        if duration > 100 || detected {
            measurements.append(
                LabMeasurement(name: "reachability-call", value: duration, unit: "ms"))
        }
        return snapshot()
    }

    private func drainPresenter(since start: ContinuousClock.Instant) {
        for observation in presenter?.drain() ?? [] {
            events.append(observation.event)
            measurements.append(
                LabMeasurement(
                    name: "presenter-callback-since-watch-start",
                    value: AccessProbes.milliseconds(since: start, until: observation.instant),
                    unit: "ms",
                    tags: ["event": observation.event.detail]))
            if let marker, observation.instant >= marker {
                measurements.append(
                    LabMeasurement(
                        name: "presenter-callback-since-operator-marker",
                        value: AccessProbes.milliseconds(since: marker, until: observation.instant),
                        unit: "ms",
                        tags: [
                            "event": observation.event.detail,
                            "caveat": "callback may be unrelated to disconnect",
                        ]))
            }
        }
    }

    private func detect(error: Error?, detail: String) {
        detected = true
        let row =
            error.map {
                AccessError($0 as NSError).classify(
                    knownExternal: media.isExternal, previouslyReachable: lastSuccess != nil,
                    volumeUnavailable: volumeIsUnavailable()
                ).proposedCopyRow
            } ?? "Unavailable; cause unconfirmed"
        events.append(AccessEvent(.watch, "\(detail); proposed row: \(row)", error: error))
        if let marker {
            measurements.append(
                LabMeasurement(
                    name: "unreachable-since-operator-marker",
                    value: AccessProbes.milliseconds(since: marker), unit: "ms",
                    tags: ["caveat": "includes human delay before pull"]))
        }
        if let lastSuccess {
            measurements.append(
                LabMeasurement(
                    name: "unreachable-since-last-success",
                    value: AccessProbes.milliseconds(since: lastSuccess), unit: "ms",
                    tags: ["caveat": "observation interval, not exact physical disconnect time"]))
        }
    }

    private func volumeIsUnavailable() -> Bool {
        guard let watchVolumeURL else { return false }
        do {
            return try !AccessProbes.reachable(watchVolumeURL)
        } catch {
            return AccessError(error as NSError).classify() == .missingLocation
        }
    }

    public func stopWatch() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            if let watchStart { drainPresenter(since: watchStart) }
            events.append(AccessEvent(.watch, "Watch stopped; file presenter removed"))
        }
        if watchScope, let watchURL { watchURL.stopAccessingSecurityScopedResource() }
        presenter = nil
        watchURL = nil
        watchVolumeURL = nil
        watchScope = false
        watchStart = nil
    }

    public func fill() -> AccessSnapshot {
        guard let selected, watchStart == nil else { return snapshot() }
        events += AccessFill.add(at: selected)
        return snapshot()
    }

    public func cleanFill() -> AccessSnapshot {
        guard let selected, watchStart == nil else { return snapshot() }
        events += AccessFill.clean(at: selected)
        return snapshot()
    }

    public func record(_ event: AccessEvent) -> AccessSnapshot {
        events.append(event)
        return snapshot()
    }

    public func snapshot() -> AccessSnapshot {
        AccessSnapshot(
            recents: recents.records, selected: selected,
            report: LabReport(
                spike: "S1", context: context, measurements: measurements,
                notes: events.map(\.summary) + [
                    "Resource hints are not a successful write. Operator-marker latency includes human delay."
                ]),
            events: events, watching: watchStart != nil)
    }
}
