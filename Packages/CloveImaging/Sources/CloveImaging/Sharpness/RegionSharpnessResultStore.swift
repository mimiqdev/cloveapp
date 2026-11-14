import Foundation
import Synchronization

/// The identity one sharpness result belongs to: the folder session that computed it, the
/// photo's primary file and its revision, and the analysis-parameter version (#216).
///
/// A result is only ever served back under the exact key it was recorded with, so a record
/// can never stand in for another photo, another revision, another folder session, or
/// another version of the scorer.
public struct SharpnessResultKey: Hashable, Sendable {
    /// The folder session's identity string (the request's `locationIdentity`), so a record
    /// can never serve another session's view of the same path.
    public let folderSession: String
    public let photo: URL
    public let revision: ThumbnailRevision
    public let parametersVersion: Int

    public init(
        folderSession: String, photo: URL, revision: ThumbnailRevision, parametersVersion: Int
    ) {
        self.folderSession = folderSession
        self.photo = photo.standardizedFileURL
        self.revision = revision
        self.parametersVersion = parametersVersion
    }
}

/// One photo's finished sharpness analysis plus the identity it belongs to: located regions,
/// scores, explicit unavailability and timings — compact facts only, never pixels (#216).
public struct RegionSharpnessRecord: Sendable {
    public let key: SharpnessResultKey
    /// The request the analysis ran with, so invalidation can match every file of the set.
    public let request: RegionSharpnessRequest
    public let analysis: RegionSharpnessAnalysis

    public init(
        key: SharpnessResultKey, request: RegionSharpnessRequest, analysis: RegionSharpnessAnalysis
    ) {
        self.key = key
        self.request = request
        self.analysis = analysis
    }
}

/// The bounded store of finished sharpness records, one compact entry per analysed photo
/// (#216), optionally backed by an app-private ``RegionSharpnessCache`` disk tier (#239).
/// Memory stays authoritative under its full session-bound key, evicted least-recently-used first,
/// and holds no image buffers; the disk tier backs initial loads across folder sessions.
///
/// An analysis whose acquisition reported a transient or identity-breaking failure is never
/// stored: `staleSource` means the photo changed under the analysis, so the answer belongs to
/// no revision the caller can ask for again, and `queueFull`/`closed` mean the photo was
/// never analysed at all — asking for it again later should start real work, not replay the
/// contention. Every other explicit answer (missing metadata, no faces, unusable pixels,
/// unscorable regions) is a fact about the photo and is kept.
public final class RegionSharpnessResultStore: Sendable {
    private struct Entry {
        let record: RegionSharpnessRecord
        var access: UInt64
    }

    private struct State {
        var entries: [SharpnessResultKey: Entry] = [:]
        var tick: UInt64 = 0
    }

    private let capacity: Int
    private let disk: RegionSharpnessCache?
    private let state = Mutex(State())

    /// - Parameters:
    ///   - capacity: the maximum number of records kept in memory; the least recently used
    ///     entry is evicted first. Records are compact, so the count is the budget.
    ///   - disk: optional persistent disk tier shared across folder sessions.
    public init(capacity: Int, disk: RegionSharpnessCache? = nil) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.disk = disk
    }

    var hasDiskCache: Bool { disk != nil }

    /// Records one finished analysis under its key in memory and on disk, unless it settled for a
    /// transient or identity-breaking reason that later requests must not replay.
    public func store(_ record: RegionSharpnessRecord) {
        guard Self.shouldStore(record.analysis) else { return }
        storeInMemory(record)
        storeOnDisk(record)
    }

    /// The stored analysis for one exact identity, or nil when none was recorded.
    /// Memory answers first; a miss checks the disk tier and promotes hits into memory.
    public func result(for key: SharpnessResultKey) -> RegionSharpnessAnalysis? {
        if let memory = memoryResult(for: key) { return memory }
        guard let analysis = diskAnalysis(for: key) else { return nil }
        let promoted = RegionSharpnessRecord(
            key: key,
            request: RegionSharpnessRequest(
                raw: DetailSource(url: key.photo, revision: key.revision),
                locationIdentity: key.folderSession),
            analysis: analysis)
        storeInMemory(promoted)
        return analysis
    }

    /// Drops every record whose photo set touches any of the given files — the source-change
    /// and folder-close invalidation path (#216).
    public func invalidate(sources: [URL]) {
        let files = Set(sources.map { $0.standardizedFileURL })
        guard !files.isEmpty else { return }
        state.withLock { state in
            state.entries = state.entries.filter { entry in
                Set(entry.value.record.request.fileURLs).isDisjoint(with: files)
            }
        }
    }

    /// Drops memory entries, keeping disk entries (the app's memory-pressure path).
    public func releaseMemory() {
        state.withLock { $0.entries.removeAll() }
    }

    /// Drops every record in memory and on disk, whatever the identity.
    public func removeAll() {
        state.withLock { $0.entries.removeAll() }
        try? disk?.clear()
    }

    /// The number of records currently kept in memory.
    public var count: Int { state.withLock { $0.entries.count } }

    static func shouldStore(_ analysis: RegionSharpnessAnalysis) -> Bool {
        RegionSharpnessCache.isPersistable(analysis)
    }

    func memoryResult(for key: SharpnessResultKey) -> RegionSharpnessAnalysis? {
        state.withLock { state in
            guard state.entries[key] != nil else { return nil }
            state.tick &+= 1
            state.entries[key]?.access = state.tick
            return state.entries[key]?.record.analysis
        }
    }

    func diskAnalysis(for key: SharpnessResultKey) -> RegionSharpnessAnalysis? {
        disk?.analysis(for: key)
    }

    func storeInMemory(_ record: RegionSharpnessRecord) {
        guard Self.shouldStore(record.analysis) else { return }
        state.withLock { state in
            state.tick &+= 1
            // A repeated store replaces its own entry; a new key makes room by evicting
            // the least recently used entry first.
            _ = state.entries.removeValue(forKey: record.key)
            while state.entries.count >= capacity,
                let oldest = state.entries.min(by: { $0.value.access < $1.value.access })?.key
            {
                state.entries.removeValue(forKey: oldest)
            }
            state.entries[record.key] = Entry(record: record, access: state.tick)
        }
    }

    func storeOnDisk(_ record: RegionSharpnessRecord) {
        guard Self.shouldStore(record.analysis) else { return }
        try? disk?.store(record)
    }
}
