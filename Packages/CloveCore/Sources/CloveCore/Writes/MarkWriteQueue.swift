import Foundation

/// The write queue: admits mark changes, routes each to its storage, and reports save state.
///
/// G1's Safe writes row and decisions 2 and 6 route a change by mark: ratings (Reject included)
/// and labels on a RAW set go to the resolved `.xmp` sidecar, while the same marks on a
/// standalone JPEG/HIF go to Clove's own storage. A RAW set therefore has one storage for all
/// its marks, and Reject no longer has a route of its own (decision record
/// `reject-as-rating.md`). PRD How marks reach disk, rule 7, requires each change to be
/// confirmed in the storage it uses, and PRD P0-08 forbids showing any unconfirmed change as
/// saved. The queue is the one place that decides a change's destination, performs it, and
/// keeps the per-change state:
///
/// - **Admission.** A request becomes a ``MarkChangeStatus`` and is written immediately.
///   Requests for one photo that arrive while an earlier write is still running merge into
///   the next write of the latest requested marks (coalescing), and each request still ends
///   with a final state. A request that changes a field another waiting request asked for
///   supersedes it (PRD How marks reach disk, rule 8).
/// - **Confirmation.** A RAW set's rating or label change is saved only when the sidecar reads
///   back with the requested marks (PRD P0-08); a standalone mark only when Clove storage reads
///   back. A failure keeps the requested marks for retry (PRD disk rule 8).
/// - **Batches.** One change applied to many photo sets reports per-photo results and the
///   confirmed and failed counts P0-09 needs, and retries only the failed items.
///
/// The queue is an actor, so its state needs no other lock. Writes for different photos may
/// run at the same time; writes to one sidecar are serialized by ``SidecarMarkWriter``.
/// Ordinary caller cancellation does not interrupt admitted work. A disconnect explicitly
/// discards the folder's requests and cancels its writers before another replacement starts.
public actor MarkWriteQueue {
    /// The sidecar writer shared by every change (G1 Safe writes serialization).
    private let writer: SidecarMarkWriter
    /// Clove's own storage for standalone marks (G1 decision 6).
    private let store: CloveMarkStore

    /// Every change's latest state, by handle (PRD P0-08).
    private var changes: [MarkChangeID: MarkChangeStatus] = [:]
    /// Admission order, so unfinished-change queries are stable for U7.
    private var order: [MarkChangeID] = []
    /// The photo set each change was admitted for, so a retry reuses its destinations.
    private var sets: [MarkChangeID: ScannedPhotoSet] = [:]
    /// The latest change per photo, for "the current state of a photo's latest change".
    private var latestByPhoto: [PhotoIdentity: MarkChangeID] = [:]
    /// Requests waiting for the next write of one photo, with the cumulative requested marks.
    private var pending: [PhotoIdentity: PendingWrite] = [:]
    /// The last failed write per photo, kept for retry and supersession (PRD disk rule 8).
    private var failed: [PhotoIdentity: FailedWrite] = [:]
    /// The write loop currently running per photo.
    private var writeTasks: [PhotoIdentity: Task<Void, Never>] = [:]
    /// Callers waiting for one change to reach its final state.
    private var waiters: [MarkChangeID: [CheckedContinuation<Void, Never>]] = [:]
    /// Callers waiting for every admitted write to finish (C11's access session).
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    /// State-change streams handed to a UI or a test.
    private var observers: [UUID: AsyncStream<MarkChangeStatus>.Continuation] = [:]
    /// Applied batches, for P0-09's retry of failed items only.
    private var batches: [MarkBatchID: AppliedBatch] = [:]

    /// Creates the queue over an existing Clove store and an injectable file seam.
    ///
    /// Production passes ``CloveMarkStore/applicationSupportDirectory()``; tests inject a
    /// temporary directory and a file-system double, so no write touches real photos or the
    /// app's Application Support container.
    public init(
        store: CloveMarkStore,
        fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        codec: XMPCodec = XMPCodec()
    ) {
        self.store = store
        self.writer = SidecarMarkWriter(fileSystem: fileSystem, codec: codec)
    }

    /// Creates the queue with Clove storage rooted at `storeDirectory`.
    ///
    /// The sidecar writer and the store share the same file seam, so one injected failure
    /// covers both storages (G1 Safe writes; G1 decision 6).
    public init(
        storeDirectory: URL,
        fileSystem: any MarkWriteFileSystem = FoundationMarkWriteFileSystem(),
        codec: XMPCodec = XMPCodec()
    ) {
        self.store = CloveMarkStore(directory: storeDirectory, fileSystem: fileSystem)
        self.writer = SidecarMarkWriter(fileSystem: fileSystem, codec: codec)
    }

    // MARK: - Changes

    /// Applies one change to one photo set and returns its final state.
    ///
    /// The destination comes from C1's ``MarkPersistence``: ratings (Reject included) and
    /// labels on a RAW set go to its sidecar (G1 decision 2), and a standalone JPEG/HIF keeps
    /// them in Clove (G1 decision 6). A set whose C2 sidecar state is ambiguous is refused with
    /// ``MarkWriteFailureReason/ambiguousSidecar`` and no second packet is created.
    ///
    /// The call returns only after the change reaches a final state, so a caller that renders
    /// PRD P0-08's status can trust the result. A change naming no marks writes nothing and
    /// returns a failure instead of claiming success.
    ///
    /// - Parameters:
    ///   - change: The rating and/or label request (PRD P0-07, P0-09).
    ///   - set: The scanned photo set, with C1's set and C2's sidecar state.
    /// - Returns: The change's final status, with the requested marks kept on failure.
    @discardableResult
    public func apply(_ change: MarkChange, to set: ScannedPhotoSet) async -> MarkChangeStatus {
        guard !Task.isCancelled else {
            return Self.disconnected(id: MarkChangeID(), photo: set.id, change: change)
        }
        guard !change.isEmpty else {
            return MarkChangeStatus(
                id: MarkChangeID(), identity: set.photoSet.id, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .unknown,
                        message: "The change names no marks, so nothing was written.")))
        }
        let id = admit(change, for: set)
        await waitFor(id)
        return changes[id]
            ?? Self.disconnected(id: id, photo: set.id, change: change)
    }

    /// Applies one change to many photo sets and returns the per-photo results (PRD P0-09).
    ///
    /// Every set is admitted before any result is awaited, so the writes run concurrently and
    /// a batch of 50 does not serialize on one sidecar. Each result carries its own state, and
    /// ``MarkBatchResult/confirmedCount`` and ``MarkBatchResult/failedCount`` give P0-09's
    /// "Saved N photos. M photos couldn't be saved." counts. The batch stays available for
    /// ``retryFailed(in:)``.
    @discardableResult
    public func apply(_ change: MarkChange, to sets: [ScannedPhotoSet]) async -> MarkBatchResult {
        let batchID = MarkBatchID()
        guard !Task.isCancelled else {
            return MarkBatchResult(
                id: batchID, change: change,
                outcomes: sets.map {
                    Self.disconnected(id: MarkChangeID(), photo: $0.id, change: change)
                })
        }
        var ids: [MarkChangeID] = []
        var outcomes: [MarkChangeStatus] = []
        for set in sets {
            guard !change.isEmpty else {
                outcomes.append(
                    MarkChangeStatus(
                        id: MarkChangeID(), identity: set.photoSet.id, requested: change,
                        state: .failed(
                            MarkWriteFailure(
                                reason: .unknown,
                                message: "The change names no marks, so nothing was written."))))
                continue
            }
            ids.append(admit(change, for: set))
        }
        for (index, id) in ids.enumerated() {
            await waitFor(id)
            outcomes.append(
                changes[id] ?? Self.disconnected(id: id, photo: sets[index].id, change: change))
        }
        let remaining = ids.filter { changes[$0] != nil }
        if !remaining.isEmpty { batches[batchID] = AppliedBatch(change: change, ids: remaining) }
        return MarkBatchResult(id: batchID, change: change, outcomes: outcomes)
    }

    /// Retries a failed change, or reports why it cannot be retried.
    ///
    /// PRD How marks reach disk, rule 8, keeps a failed change's requested marks; this call
    /// sends them again. A change a newer change superseded does nothing and returns the
    /// superseded state, so U7's single-photo retry can never resurrect stale marks. A change
    /// that is still pending or writing is awaited instead of written twice.
    @discardableResult
    public func retry(_ id: MarkChangeID) async -> MarkChangeStatus? {
        guard let status = changes[id] else { return nil }
        switch status.state {
        case .pending, .writing:
            await waitFor(id)
            return changes[id]
        case .failed:
            guard sets[id] != nil, let record = failed[status.identity],
                record.ids.contains(id)
            else {
                return changes[id]
            }
            failed[status.identity] = nil
            let failedIDs = record.ids.filter { changes[$0]?.state.failure != nil }
            let retryIDs = failedIDs.isEmpty ? [id] : failedIDs
            for retryID in retryIDs {
                guard let existing = changes[retryID], existing.state.failure != nil else {
                    continue
                }
                let pendingStatus = existing.withState(.pending)
                changes[retryID] = pendingStatus
                notify(pendingStatus)
            }
            if var existing = pending[status.identity] {
                existing.fields = existing.fields.merged(with: record.fields)
                for retryID in retryIDs where !existing.waiting.contains(retryID) {
                    existing.waiting.append(retryID)
                }
                pending[status.identity] = existing
            } else {
                pending[status.identity] = PendingWrite(fields: record.fields, waiting: retryIDs)
            }
            latestByPhoto[status.identity] = id
            startWriting(for: status.identity)
            await waitFor(id)
            return changes[id]
        default:
            return changes[id]
        }
    }

    /// Retries only the failed items of an applied batch (PRD P0-09).
    ///
    /// Saved and superseded items are left untouched, and the returned batch holds one result
    /// per retried photo, so U4's "Retry failed items" cannot repeat a successful write. A
    /// batch handle from another queue, or an unknown one, returns `nil`.
    @discardableResult
    public func retryFailed(in batchID: MarkBatchID) async -> MarkBatchResult? {
        guard let batch = batches[batchID] else { return nil }
        var outcomes: [MarkChangeStatus] = []
        var handled: Set<PhotoIdentity> = []
        for id in batch.ids {
            guard let status = changes[id], status.state.isUnfinished,
                handled.insert(status.identity).inserted
            else { continue }
            if let retried = await retry(id) { outcomes.append(retried) }
        }
        let result = MarkBatchResult(id: MarkBatchID(), change: batch.change, outcomes: outcomes)
        batches[result.id] = AppliedBatch(change: batch.change, ids: outcomes.map(\.id))
        return result
    }

    // MARK: - Queries

    /// The latest state of one change (PRD P0-08).
    public func status(of id: MarkChangeID) -> MarkChangeStatus? {
        changes[id]
    }

    /// The current state of a photo's latest change, or `nil` before its first change.
    ///
    /// The queue never mixes a newer change with an older failure: once a newer change is
    /// admitted, the older one reports ``MarkChangeState/superseded(by:)`` and this query
    /// returns the newer one (PRD disk rule 8).
    public func latestChange(for identity: PhotoIdentity) -> MarkChangeStatus? {
        latestByPhoto[identity].flatMap { changes[$0] }
    }

    /// Every change that has not finished saving: pending, writing or failed.
    ///
    /// U7's "Some marks haven't finished saving" and C11's leaving check both use this. A
    /// saved or superseded change is excluded, and the order is admission order.
    public func unfinishedChanges() -> [MarkChangeStatus] {
        order.compactMap { changes[$0] }.filter { $0.state.isUnfinished }
    }

    /// Every state change, as a stream a UI can wrap into its own observation.
    ///
    /// PRD P0-08's visible status needs a push, not a poll. The stream yields each admitted
    /// change's transitions and finishes when the caller stops iterating; the queue keeps no
    /// reference to a finished stream.
    public func stateUpdates() -> AsyncStream<MarkChangeStatus> {
        let (stream, continuation) = AsyncStream<MarkChangeStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(64))
        let observerID = UUID()
        observers[observerID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return stream
    }

    /// Stops a disconnected folder's writers and drops all of its requests and status.
    /// Canceled writers remove their own staging files; no request remains available to retry.
    public func discardChanges(in folder: FolderIdentity) {
        let photos = Set(latestByPhoto.keys.filter { $0.folderID == folder })
            .union(writeTasks.keys.filter { $0.folderID == folder })
        for photo in photos {
            writeTasks[photo]?.cancel()
            pending[photo] = nil
            failed[photo] = nil
            latestByPhoto[photo] = nil
        }
        let discarded = order.filter { changes[$0]?.identity.folderID == folder }
        for id in discarded {
            changes[id] = nil
            sets[id] = nil
            resumeWaiters(for: id)
        }
        order.removeAll { changes[$0] == nil }
        for (id, var batch) in batches {
            batch.ids.removeAll { changes[$0] == nil }
            batches[id] = batch.ids.isEmpty ? nil : batch
        }
        finishDrainingIfIdle()
    }

    private static func disconnected(
        id: MarkChangeID, photo: PhotoIdentity, change: MarkChange
    ) -> MarkChangeStatus {
        MarkChangeStatus(
            id: id, identity: photo, requested: change,
            state: .failed(
                MarkWriteFailure(reason: .locationUnavailable, message: "The drive disconnected.")))
    }

    /// Forgets a folder's unfinished and failed changes once its work has drained
    /// (PRD Failure and recovery).
    ///
    /// "Failure and recovery" is explicit: if users leave before writes finish, the unconfirmed
    /// changes are not saved, and the next open reads the actual XMP. C4 therefore forgets the
    /// folder's unfinished changes when it closes, so a later mark on the same file can never
    /// carry fields the user abandoned (PRD disk rule 8), and a leaving question in a later
    /// folder cannot count them.
    ///
    /// A confirmed change is untouched, because its storage already holds it. A change whose
    /// write is still running is left alone too: it owns its result, and callers drain first
    /// (``drain()``), so after a normal close only failed changes remain.
    ///
    /// The queue publishes nothing here. The reader that owned the folder drops its own copy of
    /// the states, and a change that no longer exists has nothing left to report.
    ///
    /// - Parameter folder: the closed folder whose changes are forgotten.
    /// - Returns: how many changes were forgotten.
    @discardableResult
    public func forgetUnfinishedChanges(in folder: FolderIdentity) -> Int {
        var forgotten: [MarkChangeID] = []
        for id in order {
            guard let status = changes[id], status.identity.folderID == folder,
                status.state.isUnfinished, writeTasks[status.identity] == nil
            else { continue }
            forgotten.append(id)
        }
        guard !forgotten.isEmpty else { return 0 }
        for id in forgotten {
            guard let status = changes[id] else { continue }
            changes[id] = nil
            sets[id] = nil
            if latestByPhoto[status.identity] == id { latestByPhoto[status.identity] = nil }
            failed[status.identity] = nil
            if var record = pending[status.identity] {
                record.waiting.removeAll { $0 == id }
                pending[status.identity] = record.waiting.isEmpty ? nil : record
            }
        }
        order.removeAll { changes[$0] == nil }
        // A forgotten change is finished, so it has no waiter; resuming any that a caller left
        // keeps nobody suspended on a change that no longer exists.
        for id in forgotten { resumeWaiters(for: id) }
        return forgotten.count
    }

    /// Waits until every admitted write has finished, for C11's access session to end.
    ///
    /// G1's Folder access row holds security-scoped access until work drains, and PRD Failure
    /// and recovery forbids treating unconfirmed changes as saved after leaving. A failed
    /// change is finished for this purpose: it keeps its requested marks and is retried
    /// explicitly, so it does not hold the folder open forever.
    public func drain() async {
        guard !isIdle else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    // MARK: - Stored marks

    /// The marks Clove stores for every photo of a folder, for opening it.
    ///
    /// PRD How marks reach disk, rule 1, reads standalone marks when the folder opens. A damaged
    /// file throws ``CloveMarkStoreError/corruptStorage(_:reason:)`` and is never overwritten
    /// silently (G1 decision 6).
    public func storedMarks(for folderID: FolderIdentity) async throws
        -> [PhotoIdentity: CloveStoredMarks]
    {
        try await store.marks(for: folderID)
    }

    /// The marks Clove stores for one photo, or `nil` when it stores none (G1 decision 6).
    public func storedMarks(for identity: PhotoIdentity) async throws -> CloveStoredMarks? {
        try await store.marks(for: identity)
    }

    /// Drops a photo's stored Reject after C6 confirms its move to the rejects folder.
    ///
    /// The move is the durable Reject result, so the stored rating −1 is cleared only once C6
    /// reports the confirmed move. The removal is confirmed by read-back; a photo that is not
    /// stored as rejected returns `false` without writing.
    @discardableResult
    public func clearReject(for identity: PhotoIdentity) async throws -> Bool {
        try await store.clearReject(for: identity)
    }

    // MARK: - Admission and merging

    /// A request waiting for its photo's next write, with the cumulative requested marks.
    private struct PendingWrite {
        /// Every field still waiting for a write; a newer request wins per field.
        var fields: MarkChange
        /// Requests whose fields are still covered by ``fields`` and await the same write.
        var waiting: [MarkChangeID]
    }

    /// The last failed write for one photo, kept so a retry or a newer change can carry it.
    private struct FailedWrite {
        /// The fields the failed write did not confirm (PRD disk rule 8).
        var fields: MarkChange
        /// The requests that failed together and share those fields.
        var ids: [MarkChangeID]
    }

    /// One applied batch, so its failed items can be retried without the saved ones.
    private struct AppliedBatch {
        /// The change every photo set received (PRD P0-09).
        var change: MarkChange
        /// The change handles the batch admitted, in caller order.
        var ids: [MarkChangeID]
    }

    /// Registers a request, merges it with what is waiting, and starts its write.
    private func admit(_ change: MarkChange, for set: ScannedPhotoSet) -> MarkChangeID {
        let id = MarkChangeID()
        let identity = set.photoSet.id
        let status = MarkChangeStatus(
            id: id, identity: identity, requested: change, state: .pending)
        changes[id] = status
        order.append(id)
        sets[id] = set
        latestByPhoto[identity] = id
        notify(status)

        var fields = change
        if let failedWrite = failed[identity] {
            // PRD disk rule 8: a newer change supersedes an older failed one, and the failed
            // fields it did not replace stay with the newer change so none are dropped.
            for oldID in failedWrite.ids { finish(oldID, .superseded(by: id)) }
            failed[identity] = nil
            fields = failedWrite.fields.merged(with: change)
        }

        if var existing = pending[identity] {
            let merged = existing.fields.merged(with: change)
            for waitingID in existing.waiting {
                guard let waiting = changes[waitingID] else { continue }
                guard !merged.covers(waiting.requested) else { continue }
                finish(waitingID, .superseded(by: id))
                existing.waiting.removeAll { $0 == waitingID }
            }
            existing.fields = merged
            existing.waiting.append(id)
            pending[identity] = existing
        } else {
            pending[identity] = PendingWrite(fields: fields, waiting: [id])
        }
        startWriting(for: identity)
        return id
    }

    /// Starts the photo's write loop when it is not already running.
    private func startWriting(for identity: PhotoIdentity) {
        guard writeTasks[identity] == nil, pending[identity] != nil else { return }
        writeTasks[identity] = Task { await self.runWrites(for: identity) }
    }

    /// The photo set of the newest admitted change for an identity.
    ///
    /// A rescan can resolve a sidecar's spelling or report it ambiguous after an earlier
    /// change was admitted, and C2's sidecar state is the authority for the next write
    /// (G1 Sidecar naming). Each write iteration therefore reads the latest set instead of
    /// the one captured when the write loop started.
    private func latestSet(for identity: PhotoIdentity) -> ScannedPhotoSet? {
        guard let id = latestByPhoto[identity] else { return nil }
        return sets[id]
    }

    /// Runs one write at a time for a photo until nothing is waiting, coalescing as it goes.
    ///
    /// G1's Safe writes row makes each write a full read-modify-write, so a request admitted
    /// during a write is not lost: it stays in ``pending`` and the next iteration writes the
    /// latest cumulative marks with the newest set's destinations. The attempted requests
    /// finish with this write's outcome; a request whose fields a newer one overwrote was
    /// already superseded at admission.
    private func runWrites(for identity: PhotoIdentity) async {
        while !Task.isCancelled, let current = pending[identity], !current.waiting.isEmpty {
            guard let set = latestSet(for: identity) else { break }
            let attempted = current.waiting
            for id in attempted { transition(id, to: .writing) }
            let failure = await perform(current.fields, for: set)
            guard !Task.isCancelled else { break }
            if let failure, failure.reason == .locationUnavailable {
                // Publish the location loss once, then retain none of this folder's status.
                for id in attempted {
                    if let status = changes[id] { notify(status.withState(.failed(failure))) }
                }
                discardChanges(in: identity.folderID)
                break
            }

            if var record = pending[identity] {
                record.waiting.removeAll { attempted.contains($0) }
                pending[identity] = record.waiting.isEmpty ? nil : record
            }
            let newer = pending[identity]?.waiting.first
            for id in attempted {
                guard let status = changes[id], status.state.isInProgress else { continue }
                if failure != nil, let newer {
                    // The newer change carries this request's fields, so retrying this one
                    // would duplicate work (PRD disk rule 8).
                    finish(id, .superseded(by: newer))
                } else {
                    finish(
                        id,
                        state(
                            for: status.requested, persistence: set.photoSet.markPersistence,
                            failure: failure))
                }
            }
            if failure != nil, pending[identity] == nil {
                failed[identity] = FailedWrite(fields: current.fields, ids: attempted)
            }
        }
        writeTasks[identity] = nil
        finishDrainingIfIdle()
    }

    // MARK: - Destinations

    /// Performs one cumulative request against the storage its marks use.
    ///
    /// G1 decisions 2 and 6 route a RAW set's rating (Reject included) and label to its sidecar
    /// and a standalone JPEG/HIF's to Clove storage, so one photo never needs two writes for one
    /// mark. A failure is reported after both parts were attempted, and a retry repeats only what
    /// is still unconfirmed.
    private func perform(_ change: MarkChange, for set: ScannedPhotoSet) async -> MarkWriteFailure?
    {
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
                proposedSidecar = proposedSidecar ?? url
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
            // C2's resolved packet wins over C1's proposed name, so an existing `.XMP`
            // spelling is reused and no second packet is created (G1 Sidecar naming).
            let destination = set.sidecar.resolvedURL ?? proposedSidecar
            if case .ambiguous(let candidates) = set.sidecar {
                failure = MarkWriteFailure(
                    reason: .ambiguousSidecar,
                    message:
                        "The photo set has more than one candidate XMP packet: "
                        + candidates.map(\.lastPathComponent).joined(separator: ", "))
            } else {
                let result = await writer.write(edit, to: destination)
                if let writeFailure = result.failure { failure = writeFailure }
            }
        }

        if usesCloveStorage {
            do {
                try Task.checkCancellation()
                try await store.apply(stored, to: set.photoSet.id)
            } catch {
                if failure == nil { failure = MarkWriteFailure(classifying: error) }
            }
        }
        return failure
    }

    /// The state one request shows once its write has a result.
    ///
    /// PRD P0-08 names the storage: XMP read-back is **Saved**, and a standalone mark confirmed
    /// in Clove is **Saved in Clove only**. Reject is a rating, so it reports the state its own
    /// storage gave it (decision record `reject-as-rating.md`).
    private func state(
        for request: MarkChange,
        persistence: MarkPersistence,
        failure: MarkWriteFailure?
    ) -> MarkChangeState {
        if let failure { return .failed(failure) }
        let destination: MarkDestination =
            request.rating != nil ? persistence.rating : persistence.label
        switch destination {
        case .xmpSidecar: return .savedInSidecar
        case .cloveStorage: return .savedInCloveOnly
        }
    }

    // MARK: - State plumbing

    /// Whether no write is running or waiting.
    private var isIdle: Bool { writeTasks.isEmpty && pending.isEmpty }

    /// Stores a transition that is not final, such as `.writing`.
    private func transition(_ id: MarkChangeID, to state: MarkChangeState) {
        guard let status = changes[id] else { return }
        let updated = status.withState(state)
        changes[id] = updated
        notify(updated)
    }

    /// Stores a final state, resumes the change's waiters and tells observers.
    private func finish(_ id: MarkChangeID, _ state: MarkChangeState) {
        guard let status = changes[id] else { return }
        guard status.state.isInProgress || status.state.failure != nil else { return }
        let updated = status.withState(state)
        changes[id] = updated
        notify(updated)
        resumeWaiters(for: id)
        finishDrainingIfIdle()
    }

    /// Resumes callers waiting for one change, at most once per state.
    private func resumeWaiters(for id: MarkChangeID) {
        for continuation in waiters.removeValue(forKey: id) ?? [] { continuation.resume() }
    }

    /// Publishes a state to every stream a caller is reading.
    private func notify(_ status: MarkChangeStatus) {
        for observer in observers.values { observer.yield(status) }
    }

    /// Waits for one change to leave `.pending` or `.writing`.
    private func waitFor(_ id: MarkChangeID) async {
        guard let status = changes[id], status.state.isInProgress else { return }
        await withCheckedContinuation { continuation in
            waiters[id, default: []].append(continuation)
        }
    }

    /// Resumes drain callers once no write is running or waiting (C11's access session).
    private func finishDrainingIfIdle() {
        guard isIdle else { return }
        let waiting = drainWaiters
        drainWaiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    /// Detaches a stream's continuation when its reader stops.
    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
