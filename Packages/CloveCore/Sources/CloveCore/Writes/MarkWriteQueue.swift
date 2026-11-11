import Foundation

/// Writes marks in admission order per photo. Results belong to the caller; none are retained.
public actor MarkWriteQueue {
    private let writer: SidecarMarkWriter
    private let store: CloveMarkStore

    private struct Request {
        let change: MarkChange
        let set: ScannedPhotoSet
        let completion: CheckedContinuation<MarkChangeStatus, Never>
    }

    private var pending: [PhotoIdentity: [Request]] = [:]
    private var writeTasks: [PhotoIdentity: Task<Void, Never>] = [:]
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: CloveMarkStore,
        fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        codec: XMPCodec = XMPCodec()
    ) {
        self.store = store
        self.writer = SidecarMarkWriter(fileSystem: fileSystem, codec: codec)
    }

    public init(
        storeDirectory: URL,
        fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        codec: XMPCodec = XMPCodec()
    ) {
        self.store = CloveMarkStore(directory: storeDirectory, fileSystem: fileSystem)
        self.writer = SidecarMarkWriter(fileSystem: fileSystem, codec: codec)
    }

    @discardableResult
    public func apply(_ change: MarkChange, to set: ScannedPhotoSet) async -> MarkChangeStatus {
        await withCheckedContinuation { continuation in
            pending[set.id, default: []].append(
                Request(change: change, set: set, completion: continuation))
            if writeTasks[set.id] == nil {
                writeTasks[set.id] = Task { await self.runWrites(for: set.id) }
            }
        }
    }

    @discardableResult
    public func apply(_ change: MarkChange, to sets: [ScannedPhotoSet]) async -> MarkBatchResult {
        let outcomes = await withTaskGroup(of: (Int, MarkChangeStatus).self) { group in
            for (index, set) in sets.enumerated() {
                group.addTask { (index, await self.apply(change, to: set)) }
            }
            var results: [(Int, MarkChangeStatus)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return MarkBatchResult(id: MarkBatchID(), change: change, outcomes: outcomes)
    }

    /// Drops waiting writes. An operation already touching a file finishes normally.
    public func discardChanges(in folder: FolderIdentity) {
        for photo in pending.keys where photo.folderID == folder {
            for request in pending.removeValue(forKey: photo) ?? [] {
                request.completion.resume(
                    returning: result(
                        request,
                        failure: MarkWriteFailure(
                            reason: .locationUnavailable, message: "The drive disconnected.")))
            }
        }
    }

    public func drain() async {
        guard !writeTasks.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    public func storedMarks(for folderID: FolderIdentity) async throws
        -> [PhotoIdentity: CloveStoredMarks]
    {
        try await store.marks(for: folderID)
    }

    public func storedMarks(for identity: PhotoIdentity) async throws -> CloveStoredMarks? {
        try await store.marks(for: identity)
    }

    @discardableResult
    public func clearReject(for identity: PhotoIdentity) async throws -> Bool {
        try await store.clearReject(for: identity)
    }

    private func runWrites(for photo: PhotoIdentity) async {
        while let request = pending[photo]?.first {
            pending[photo]?.removeFirst()
            if pending[photo]?.isEmpty == true { pending[photo] = nil }
            let failure = await perform(request.change, for: request.set)
            request.completion.resume(returning: result(request, failure: failure))
        }
        writeTasks[photo] = nil
        if writeTasks.isEmpty {
            let waiting = drainWaiters
            drainWaiters.removeAll()
            for continuation in waiting { continuation.resume() }
        }
    }

    private func result(_ request: Request, failure: MarkWriteFailure?) -> MarkChangeStatus {
        let destination =
            request.change.rating != nil
            ? request.set.photoSet.markPersistence.rating
            : request.set.photoSet.markPersistence.label
        let state: MarkChangeState
        if let failure {
            state = .failed(failure)
        } else {
            switch destination {
            case .xmpSidecar: state = .savedInSidecar
            case .cloveStorage: state = .savedInCloveOnly
            }
        }
        return MarkChangeStatus(
            id: MarkChangeID(), identity: request.set.id, requested: request.change, state: state)
    }

    private func perform(_ change: MarkChange, for set: ScannedPhotoSet) async -> MarkWriteFailure?
    {
        guard !change.isEmpty else {
            return MarkWriteFailure(reason: .unknown, message: "The change names no marks.")
        }
        let persistence = set.photoSet.markPersistence
        var edit = XMPEdit()
        var proposedSidecar: URL?
        var stored = CloveMarkChange()
        var usesSidecar = false
        var usesCloveStorage = false
        var failure: MarkWriteFailure?
        if let rating = change.rating {
            switch persistence.rating {
            case .xmpSidecar(let url):
                edit.rating = .set(rating)
                proposedSidecar = url
                usesSidecar = true
            case .cloveStorage:
                stored.rating = rating
                usesCloveStorage = true
            }
        }
        if let label = change.label {
            switch persistence.label {
            case .xmpSidecar(let url):
                edit.label = .set(label)
                proposedSidecar = proposedSidecar ?? url
                usesSidecar = true
            case .cloveStorage:
                stored.label = label
                usesCloveStorage = true
            }
        }
        if usesSidecar, let proposedSidecar {
            let destination = set.sidecar.resolvedURL ?? proposedSidecar
            if case .ambiguous = set.sidecar {
                failure = MarkWriteFailure(
                    reason: .ambiguousSidecar,
                    message: "The photo set has more than one candidate XMP packet.")
            } else {
                failure = await writer.write(edit, to: destination).failure
            }
        }
        if usesCloveStorage {
            do {
                try await store.apply(stored, to: set.id)
            } catch {
                if failure == nil { failure = MarkWriteFailure(classifying: error) }
            }
        }
        return failure
    }
}
