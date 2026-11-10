import CloveCore
import CloveImaging
import Foundation

/// The real ``FolderLibrary``: one open folder behind C11's access, C2's scan, I4's times,
/// C8's values and C4's writes (PRD P0-01, P0-02, P0-08).
///
/// The library is main-actor isolated because the screens read it there, and every file operation
/// leaves that actor: C11 holds the security scope, the scan walks and reads metadata in its own
/// task, and the write queue writes off the main actor. What crosses back to the main actor is a
/// value: a batch of grid photos, a batch of read results, a finished scan or a write state, which
/// the model applies through ``FolderLibrary/updates``.
///
/// Opening another folder ends the one before it, so the scan is cancelled and C11's session
/// drains before its scope is released (G1 folder access). A scan that a newer open replaced
/// publishes nothing, because every publication checks the generation it started in.
@MainActor
final class FolderLibrarySession: FolderLibrary {
    /// The app-private stores the library works through: C11's Recents and C4's write queue.
    struct Stores: Sendable {
        let access: FolderAccess
        let writes: MarkWriteQueue

        /// C9's per-folder group cache in Clove's own storage (PRD Similar groups rules).
        let groups: SimilarGroupsCache

        /// Prepares the stores below Application Support (PRD P0-02, P0-08, P0-11).
        ///
        /// Resolving those paths touches the file system, so ``FolderLibraryLaunch`` runs this off
        /// the main actor instead of during the scene's first body evaluation.
        static func applicationSupport() throws -> Stores {
            let store = try RecentFolderStore.applicationSupport()
            let marksDirectory = try CloveMarkStore.applicationSupportDirectory()
            let groupsDirectory = try SimilarGroupsCache.applicationSupportDirectory()
            return Stores(
                access: FolderAccess(store: store),
                writes: MarkWriteQueue(storeDirectory: marksDirectory),
                groups: SimilarGroupsCache(directory: groupsDirectory))
        }
    }

    /// The open folder's I1 preview cache and I3 feature cache (G1 preview and scheduling rows).
    ///
    /// Grouping's features share the grid's preview cache, so a photo the grid already decoded is
    /// never read twice, and both caches live in the app's Caches directory because both can be
    /// rebuilt from the files.
    struct Caches: Sendable {
        let thumbnails: ThumbnailCache
        let features: ImageFeatureCache
    }

    /// The key a library answers with while no folder is open (PRD P0-02, P0-14).
    ///
    /// It is not a bookmark key, so a saved scene or a stored mark can never mistake it for a
    /// folder, and entry only shows a folder after a pick or a reopen returned one.
    static let noFolder = FolderIdentity(rawValue: "clove.folder.none")

    /// The stores, prepared off the main actor so the first scene never waits on disk.
    private let stores: Task<Stores, any Error>
    private let metadata: MetadataReader
    private let codec = XMPCodec()

    /// The rejects folder name the scan skips, read each time a folder opens (PRD Move rejects).
    ///
    /// A closure rather than a value, because the user can rename the folder while a folder is
    /// open; the scan reads it when the folder opens, so a new name applies to the next open. The
    /// PRD does not apply a rename to a folder that is already scanned.
    private let rejectsFolderName: @MainActor () -> RejectsFolderName

    /// Whether similar groups are offered, read each time grouping runs (PRD P0-11).
    ///
    /// It is a closure rather than a value for the same reason as the rejects folder name: the
    /// settings screen can change it while nothing is open, and the next folder must group by
    /// what the store says then, not by what this library was created with.
    private let similarGroupsEnabled: @MainActor () -> Bool

    /// The one stream this library publishes, consumed by ``BrowsingModel``.
    let updates: AsyncStream<FolderLibraryUpdate>
    private let updatesContinuation: AsyncStream<FolderLibraryUpdate>.Continuation

    /// The open folder's durable key, or ``noFolder`` before one opens (PRD P0-02).
    private(set) var folder: FolderIdentity = FolderLibrarySession.noFolder

    /// Every remembered folder, most recently opened first (PRD P0-02).
    private(set) var recents: [RecentFolder] = []

    /// Why the Recents list could not be read, or nil when it could (PRD P0-02).
    private(set) var recentsFailure: FolderAccessFailure?

    /// The open folder's photos, with their scanned sets (PRD P0-01, P0-08).
    private var store = FolderPhotos()

    /// The latest save state per photo, kept in step with C4's ordered stream (PRD P0-08).
    private var changes = PhotoChangeStates()

    /// The open folder's finishing-action records, which complete a group even when a write
    /// failed (PRD In-group culling, group completion; PRD P0-12).
    ///
    /// One tracker per opened folder: the records do not persist across launches, so reopening
    /// the folder follows the marks again (``GroupCompletionTracker``).
    private var groupCompletionTracker = GroupCompletionTracker()

    /// The batches this library applied, so a retry resends only their failed photos
    /// (PRD P0-09). It is replaced with every folder, because another folder's identities and
    /// sidecars cannot be retried through this one.
    private var batches: [MarkBatchID: AppliedBatch] = [:]

    /// The open folder's undo and redo history (PRD P0-05; DEV-PLAN C5).
    ///
    /// It is created with the folder and cleared when the folder closes, because PRD P0-05 does
    /// not ask for a history across launches (``MarkUndoHistory``). It writes through this
    /// library's C4 queue, so an undo shows the same save state, failure copy and retry as the
    /// change it reverts, and it keeps the folder's own completion records, so undoing a
    /// finishing action makes its group incomplete again (PRD P0-12).
    private var undoHistory: MarkUndoHistory?

    /// What ``undoHistory`` offers, mirrored for the screens (PRD P0-05).
    ///
    /// The history is an actor, so the screens cannot read it synchronously; the library keeps
    /// this answer in step after every record, undo and redo, and the browsing model copies it
    /// for the toolbar's enabled state.
    private var undoState: UndoAvailability = .none

    /// The session holding the open folder's scope, ended when another folder opens.
    private var openSession: FolderAccessSession?

    /// Whether the open folder is closing, set before its drain (PRD P0-01, P0-08).
    ///
    /// C4 starts a change's write at admission, so an admission after the drain but before the
    /// scope is released would write under a scope the folder no longer holds. The flag closes
    /// that window: an admission that starts after the close begins is refused, and every write
    /// admitted before it is drained.
    private var isClosingFolder = false

    /// The running scan, cancelled when another folder opens.
    private var scanTask: Task<Void, Never>?

    /// The walk behind ``scanTask``, so ending the folder stops its enumeration.
    private var openScan: FolderScan?

    /// The folder's thumbnail pipeline, closed before its scope is released (PRD P0-03).
    private var thumbnailPipeline: ThumbnailPipeline?

    /// The grid's source for the open folder, bound to that folder's session and pipeline.
    private var thumbnailSource: (any GridThumbnailSource)?

    /// The open folder's grouping, which publishes its groups (PRD P0-11).
    private var grouping: FolderGrouping?

    /// The groups grouping last published for the open folder (PRD P0-11).
    private var publishedGroups: [BrowsingGroup] = []

    /// Whether grouping published at all for the open folder, even with no groups, so a saved
    /// group view knows the wait is over (PRD P0-14).
    private var hasPublishedGroups = false

    /// The folder's detail pipeline, closed before its scope is released (PRD P0-04).
    private var detailPipeline: DetailPipeline?

    /// The detail view's source for the open folder, bound to that folder's session and pipeline.
    private var detailSource: (any DetailImageSource)?

    /// The task keeping this library's save states in step with C4 (PRD P0-08).
    private var writeStatusTask: Task<Void, Never>?

    /// C6's mover for the open folder, with the batches a retry of failed sets needs (P0-10).
    ///
    /// It is replaced with every folder, because another folder's identities, settings and open
    /// session cannot be retried through this one.
    private var rejectMover: RejectMover?

    /// The photos a confirmed move took out of the folder (PRD P0-10).
    ///
    /// A scan still enumerating when the move runs can deliver a set after its files moved, so
    /// these identities are dropped from later scan batches instead of reappearing in the grid.
    private var movedRejectIdentities: Set<PhotoIdentity> = []

    /// The watch that reports the open folder's location going away (PRD P0-02, G1 folder access).
    ///
    /// G1 uses presenters plus a 500 ms foreground poll; the watch reports one loss and stops, and
    /// ``endOpenFolder()`` removes it so nothing arrives after the folder closes.
    private var locationMonitor: FolderLocationMonitor?

    /// Which open a scan belongs to, so a replaced scan publishes nothing.
    private var scanGeneration = 0

    /// The last queued open transition, so two opens can never install out of order.
    private var openTransition: Task<Void, Never>?

    /// Creates the library over a task that prepares its app-private stores.
    ///
    /// The metadata reader and the rejects folder name are injectable so a test can keep the work
    /// small; production passes what ``FolderLibraryLaunch`` builds.
    init(
        stores: Task<Stores, any Error>,
        metadata: MetadataReader = MetadataReader(),
        rejectsFolderName: @escaping @MainActor () -> RejectsFolderName = {
            .defaultFolderName
        },
        similarGroupsEnabled: @escaping @MainActor () -> Bool = { true }
    ) {
        self.stores = stores
        self.metadata = metadata
        self.rejectsFolderName = rejectsFolderName
        self.similarGroupsEnabled = similarGroupsEnabled
        let (stream, continuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        updates = stream
        updatesContinuation = continuation
        // The observer holds the queue and the stream, never the library: a closed scene must be
        // able to release the library and, with it, the folder's scope.
        writeStatusTask = Task { [weak self, stores] in
            guard let queue = try? await stores.value.writes else { return }
            let states = await queue.stateUpdates()
            for await status in states {
                guard !Task.isCancelled, let self else { return }
                self.record(status)
            }
        }
    }

    /// The folder's photos with their marks, in scan order (PRD P0-03).
    var photos: [GridPhoto] { store.photos }

    /// Grouping's groups for the folder, in grid order and by grouping's stable keys
    /// (PRD P0-11). They arrive through ``FolderLibraryUpdate/groups(_:)``; before grouping's
    /// first publication this is empty.
    var groups: [BrowsingGroup] { publishedGroups }

    /// The grid's source for the open folder's previews and companion badges (PRD P0-03).
    ///
    /// It is bound to the folder that was open when it was made, so a request for an earlier
    /// folder's photo answers unavailable instead of decoding under another folder's scope.
    var thumbnails: any GridThumbnailSource { thumbnailSource ?? Self.emptyThumbnails }

    /// The source a grid reads while no folder is open: no tiles and no companions.
    private static let emptyThumbnails = SampleGridThumbnails()

    /// The detail view's source for the open folder's pixels (PRD P0-04, G1 detail row).
    ///
    /// It is bound to the folder that was open when it was made and to that folder's I2 pipeline,
    /// so a request for an earlier folder's photo answers unavailable instead of reading under
    /// another folder's scope. Closing the folder closes the pipeline after its reads drain.
    var detailImages: any DetailImageSource { detailSource ?? Self.emptyDetailImages }

    /// The source detail reads while no folder is open: nothing to show.
    private static let emptyDetailImages = EmptyDetailImages()

    /// The latest change to one photo with its save state (PRD P0-08).
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { changes.latest(for: photo) }

    /// What the open folder's undo history offers now (PRD P0-05).
    var undoAvailability: UndoAvailability { undoState }

    /// Records one confirmed change on the open folder's undo history (PRD P0-05, P0-09, P0-12).
    ///
    /// PRD P0-05's Undo row restores the previous mark, so each request carries what its change
    /// replaced. A mark and a bar action are recorded from their requests, in the state C4 admits
    /// a change in, so the history holds the action from the moment it starts and the Undo control
    /// is live while its write runs. The browsing model waits for its own writes before it runs a
    /// step, so a step never reads the marks between this record and C4 admitting the write. A
    /// finishing action is recorded once, from C10's own record of what it changed; a change that
    /// names no field records nothing, and a retry never records a second step.
    func recordUndoStep(_ request: UndoRecordRequest) async -> Bool {
        guard let history = undoHistory else { return false }
        let recorded: MarkUndoEntryID?
        switch request {
        case .mark(let entry):
            // C4 reported the marks this change replaces at admission, so the record takes them
            // from there instead of guessing while other writers run (PRD P0-05).
            let status = MarkChangeStatus(
                id: entry.id, identity: entry.photo, requested: entry.change, state: .pending)
            recorded = await history.record(status, marksBefore: entry.marksBefore)
        case .batch(let entry):
            let outcomes = entry.admissions.map { admission in
                MarkChangeStatus(
                    id: admission.id, identity: admission.photo, requested: admission.change,
                    state: .pending)
            }
            var marksBefore: [PhotoIdentity: PhotoMarks] = [:]
            for admission in entry.admissions {
                marksBefore[admission.photo] = admission.marksBefore
            }
            let batch = MarkBatchResult(
                id: entry.libraryBatch, change: entry.change, outcomes: outcomes)
            recorded = await history.recordBatch(batch, marksBefore: marksBefore)
        case .groupFinishing(let undo):
            recorded = await history.recordGroupFinishing(undo)
        }
        // A folder can close or be replaced while the history call waits: the step landed in the
        // history that is gone, so it does not count and the new session's mirror is untouched
        // (PRD P0-05, P0-14).
        guard undoHistory === history else { return false }
        await refreshUndoAvailability(from: history)
        return recorded != nil
    }

    /// Admits one change and reports the marks C4 says it replaces (PRD P0-05).
    func admitMarkChange(_ change: MarkChange, to photo: PhotoIdentity) async
        -> MarkChangeAdmission?
    {
        func refuse(_ reason: MarkWriteFailureReason, _ message: String) -> MarkChangeAdmission? {
            let status = Self.refused(change, for: photo, reason: reason, message: message)
            publish(.change(status))
            return nil
        }
        guard !change.isEmpty else { return nil }
        guard !isClosingFolder, let set = store.scannedSet(for: photo), openSession != nil else {
            return refuse(.locationUnavailable, "The open folder no longer holds this photo.")
        }
        guard case .success(let stores) = await resolvedStores() else {
            return refuse(.unknown, "Clove's stored marks are unavailable.")
        }
        // The folder can close while the stores resolve.
        guard !isClosingFolder, openSession != nil else {
            return refuse(
                .locationUnavailable, "The folder closed before the change could be admitted.")
        }
        let confirmed = store.photo(for: photo)?.marks ?? PhotoMarks()
        return await stores.writes.admit(change, to: set, confirmed: confirmed)
    }

    /// Awaits one admitted change's write inside C11's session (PRD P0-08).
    ///
    /// The write is admitted through the folder's session, so ending the folder waits for it
    /// before releasing the scope; a folder that closed refuses the change instead of writing
    /// under a scope it no longer holds.
    func write(_ admission: MarkChangeAdmission) async -> MarkChangeStatus {
        func refuse(_ reason: MarkWriteFailureReason, _ message: String) -> MarkChangeStatus {
            let status = Self.refused(
                admission.change, for: admission.photo, reason: reason, message: message)
            publish(.change(status))
            return status
        }
        guard let session = openSession else {
            return refuse(.locationUnavailable, "The open folder no longer holds this photo.")
        }
        switch await resolvedStores() {
        case .failure(let error):
            return refuse(.unknown, "Clove's stored marks are unavailable: \(error)")
        case .success(let stores):
            do {
                return try await session.withAdmittedWork {
                    await stores.writes.waitFor(admission)
                }
            } catch {
                return refuse(
                    .locationUnavailable, "The folder closed before the change could be written.")
            }
        }
    }

    /// Admits one bar action's per-photo changes (PRD P0-09).
    ///
    /// Items can name different changes because C13 resolves the action per photo, so the queue
    /// admits one batch per distinct change and the action's own handle keeps them for a retry.
    func admitBatch(_ items: [BatchMarkItem]) async -> BatchWriteAdmission? {
        guard !items.isEmpty, !isClosingFolder, openSession != nil else { return nil }
        let scanned = store
        var order: [PhotoIdentity: Int] = [:]
        var byChange: [MarkChange: [ScannedPhotoSet]] = [:]
        var unavailable: [BatchMarkItem] = []
        for (index, item) in items.enumerated() {
            order[item.photo] = index
            guard let set = scanned.scannedSet(for: item.photo) else {
                unavailable.append(item)
                let status = Self.refused(
                    item.change, for: item.photo, reason: .locationUnavailable,
                    message: "The open folder no longer holds this photo.")
                publish(.change(status))
                continue
            }
            byChange[item.change, default: []].append(set)
        }
        guard case .success(let stores) = await resolvedStores() else { return nil }
        guard !isClosingFolder, openSession != nil else { return nil }
        var queueBatches: [MarkBatchAdmission] = []
        var admissions: [MarkChangeAdmission] = []
        for (change, sets) in byChange {
            var confirmed: [PhotoIdentity: PhotoMarks] = [:]
            for set in sets {
                confirmed[set.id] = scanned.photo(for: set.id)?.marks ?? PhotoMarks()
            }
            let admission = await stores.writes.admit(change, to: sets, confirmed: confirmed)
            queueBatches.append(admission)
            admissions.append(contentsOf: admission.admissions)
        }
        admissions.sort { (order[$0.photo] ?? .max) < (order[$1.photo] ?? .max) }
        let change = items.first?.change ?? MarkChange()
        let libraryBatch = MarkBatchID()
        // The action is kept even when nothing reached the queue, so a retry reports the photos
        // the folder no longer holds instead of dropping them (PRD P0-09).
        batches[libraryBatch] = AppliedBatch(
            change: change, queueBatches: queueBatches.map(\.batchID), unavailable: unavailable)
        return BatchWriteAdmission(
            change: change, batches: queueBatches, admissions: admissions,
            unavailable: unavailable, libraryBatch: libraryBatch, order: order)
    }

    /// Awaits one admitted bar action's writes inside C11's session (PRD P0-09).
    func write(_ admission: BatchWriteAdmission) async -> MarkBatchResult {
        var outcomes: [MarkChangeStatus] = []
        if let session = openSession, case .success(let stores) = await resolvedStores() {
            for group in admission.batches {
                let result: MarkBatchResult? = try? await session.withAdmittedWork {
                    await stores.writes.waitFor(group)
                }
                if let result {
                    outcomes.append(contentsOf: result.outcomes)
                } else {
                    for entry in group.admissions {
                        let status = Self.refused(
                            entry.change, for: entry.photo, reason: .locationUnavailable,
                            message: "The folder closed before the batch could be written.")
                        publish(.change(status))
                        outcomes.append(status)
                    }
                }
            }
        } else {
            for entry in admission.admissions {
                let status = Self.refused(
                    entry.change, for: entry.photo, reason: .locationUnavailable,
                    message: "The open folder no longer holds this photo.")
                publish(.change(status))
                outcomes.append(status)
            }
        }
        for item in admission.unavailable {
            let status = Self.refused(
                item.change, for: item.photo, reason: .locationUnavailable,
                message: "The open folder no longer holds this photo.")
            publish(.change(status))
            outcomes.append(status)
        }
        outcomes.sort {
            (admission.order[$0.identity] ?? .max) < (admission.order[$1.identity] ?? .max)
        }
        return MarkBatchResult(
            id: admission.libraryBatch, change: admission.change, outcomes: outcomes)
    }

    /// Undoes the history's next action through C4's write queue (PRD P0-05).
    ///
    /// The step is admitted through C11's session like any other write, so the folder waits for
    /// it before releasing the scope, and the queue is the only writer, so PRD P0-08's save
    /// state, failure copy and retry describe an undo exactly as they describe a mark.
    func undoMarkChange() async -> UndoStepResult? {
        await restoreMarkChange { history, stores in
            await history.undo(
                photoSet: { [weak self] photo in await self?.finishingSet(for: photo) },
                latestMarks: { [weak self] photo in
                    await self?.finishingMarks(for: photo, in: stores.writes) ?? PhotoMarks()
                })
        }
    }

    /// Redoes the history's next undone action through C4's write queue (PRD P0-05).
    func redoMarkChange() async -> UndoStepResult? {
        await restoreMarkChange { history, stores in
            await history.redo(
                photoSet: { [weak self] photo in await self?.finishingSet(for: photo) },
                latestMarks: { [weak self] photo in
                    await self?.finishingMarks(for: photo, in: stores.writes) ?? PhotoMarks()
                })
        }
    }

    /// Runs one undo or redo step inside the open folder's session (PRD P0-05).
    ///
    /// The photo-set lookup and the marks read are the ones a finishing action uses: the folder's
    /// current set, and the marks the queue has now, including a requested change C4 has not
    /// confirmed yet. C5 therefore never overwrites a newer mark with the one it restores, and a
    /// photo the folder no longer holds is reported instead of written somewhere else.
    private func restoreMarkChange(
        _ step: @Sendable (MarkUndoHistory, Stores) async -> MarkUndoResult?
    ) async -> UndoStepResult? {
        guard let history = undoHistory, let session = openSession else { return nil }
        guard case .success(let stores) = await resolvedStores() else { return nil }
        let result: MarkUndoResult?
        do {
            result = try await session.withAdmittedWork { await step(history, stores) }
        } catch {
            result = nil
        }
        // The folder can close or be replaced while the step waits; the open folder's mirror is
        // the only one this session may refresh (PRD P0-05, P0-14).
        if undoHistory === history {
            await refreshUndoAvailability(from: history)
        }
        return result.map(UndoStepResult.init)
    }

    /// Copies the history's state for the toolbar and the system menu (PRD P0-05).
    private func refreshUndoAvailability(from history: MarkUndoHistory) async {
        let canUndo = await history.canUndo
        let canRedo = await history.canRedo
        let undoDepth = await history.undoCount
        let undoName = await history.nextUndoActionName
        let redoName = await history.nextRedoActionName
        undoState = UndoAvailability(
            canUndo: canUndo, canRedo: canRedo, undoDepth: undoDepth, undoName: undoName,
            redoName: redoName)
    }

    /// The open this library installed last, which changes on every install and close
    /// (PRD P0-02).
    var openGeneration: Int { scanGeneration }

    /// Whether C4 still holds an unfinished change for the open folder (PRD P0-08).
    ///
    /// The queue keeps a failed change for the session, including one from a folder the user
    /// left, so the answer is narrowed to the folder that is open now; otherwise an earlier
    /// folder's failure would keep this folder's leaving question up forever.
    func hasUnfinishedWrites() async -> Bool {
        guard case .success(let stores) = await resolvedStores() else { return false }
        let current = folder
        return await stores.writes.unfinishedChanges().contains {
            $0.identity.folderID == current
        }
    }

    /// The scanned set behind one photo, for writes and U3's thumbnail lookup (PRD P0-08).
    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? { store.scannedSet(for: photo) }

    /// Applies one change to the photo's set through C4, inside the session that holds its scope.
    ///
    /// A photo the folder no longer holds, or a folder that closed while the change waited, is
    /// refused instead of being written somewhere else. The write is admitted through C11's
    /// session so `end()` cannot release the scope while it runs (G1 folder access, PRD P0-08).
    /// A refusal never reaches the queue, so it is published on ``updates`` itself; otherwise the
    /// screen would never learn that the latest attempt failed (PRD P0-08 never fails silently).
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus {
        func refuse(_ reason: MarkWriteFailureReason, _ message: String) -> MarkChangeStatus {
            let status = Self.refused(change, for: photo, reason: reason, message: message)
            publish(.change(status))
            return status
        }
        guard let set = store.scannedSet(for: photo), let session = openSession else {
            return refuse(.locationUnavailable, "The open folder no longer holds this photo.")
        }
        switch await resolvedStores() {
        case .failure(let error):
            return refuse(.unknown, "Clove's stored marks are unavailable: \(error)")
        case .success(let stores):
            do {
                return try await session.withAdmittedWork {
                    await stores.writes.apply(change, to: set)
                }
            } catch {
                return refuse(
                    .locationUnavailable, "The folder closed before the change could be written.")
            }
        }
    }

    /// Resends one photo's latest failed change through C4, inside the session holding its scope.
    ///
    /// PRD Failure and recovery offers Retry for a single-photo write failure, and PRD How marks
    /// reach disk, rule 8, never retries a change a newer one superseded. The library therefore
    /// retries only the photo's latest change and only while it still holds a failure; anything
    /// else answers with what it already has, so a retry can neither resurrect stale marks nor
    /// report an unconfirmed change as saved. The write is admitted through C11's session for the
    /// same reason ``apply(_:to:)`` is (G1 folder access, PRD P0-08).
    func retryLatestChange(for photo: PhotoIdentity) async -> MarkChangeStatus? {
        guard case .success(let stores) = await resolvedStores() else {
            return changes.latest(for: photo)
        }
        // C4's own record is the authority: a session copy can lag a transition, and a change
        // this open already forgot must not be retried (PRD Failure and recovery).
        guard let status = await stores.writes.latestChange(for: photo) else { return nil }
        guard status.state.failure != nil, let session = openSession else { return status }
        do {
            return try await session.withAdmittedWork {
                await stores.writes.retry(status.id)
            }
        } catch {
            return status
        }
    }

    /// Waits until C4 has finished every admitted write (PRD Failure and recovery).
    ///
    /// The leaving question's "Wait for writes" uses this; a failed change is finished for this
    /// purpose and is retried explicitly instead of holding the folder open.
    func drainWrites() async {
        guard case .success(let stores) = await resolvedStores() else { return }
        await stores.writes.drain()
    }

    /// Checks the open folder's location now, for a scene that came back to the foreground
    /// (PRD P0-02, G1 folder access). Nothing is watched while no folder is open.
    func checkFolderLocationNow() async {
        await locationMonitor?.checkNow()
    }

    /// Closes the open folder and releases its scope (PRD P0-08, PRD P0-02).
    ///
    /// PRD Failure and recovery's "Leave anyway" closes the folder without reporting the
    /// unconfirmed changes as saved: they keep their failed or unfinished state in C4, and the
    /// next open reads the actual XMP and Clove-stored marks. The library drops the folder's
    /// photos, groups and save states and answers with ``noFolder`` until another open.
    ///
    /// The close takes the same turn as an open, so a close queued before an open never tears
    /// down the folder that open installed. The departure itself does not wait for this: the
    /// screen shows entry first, and ending the folder here waits for C4's work only to keep
    /// G1's scope release safe.
    func closeFolder() async {
        let earlier = openTransition
        let transition = Task { [weak self] in
            await earlier?.value
            await self?.uninstallFolder()
        }
        openTransition = transition
        await transition.value
    }

    /// Ends the open folder and forgets its contents, once every earlier open finished.
    private func uninstallFolder() async {
        await endOpenFolder()
        folder = Self.noFolder
        store = FolderPhotos()
        changes = PhotoChangeStates()
        publishedGroups = []
        hasPublishedGroups = false
        thumbnailSource = nil
        detailSource = nil
        publish(.photos([]))
    }

    /// Applies one bar action to the open folder's photos in one batch and reports each photo's
    /// result (PRD P0-09).
    ///
    /// C13 resolves the action per photo, so items can name different changes: a rating clears
    /// Reject on the rejected photos only. The library groups the items by change and admits each
    /// group through C4's batch write inside the session that holds the folder's scope, then
    /// reports one result in the caller's order under one handle a retry can use (PRD P0-09). A
    /// photo the folder no longer holds is refused and published on ``updates``, so the bar
    /// counts it as a failure and the photo keeps the marks it had (PRD P0-08).
    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        let change = items.first?.change ?? MarkChange()
        guard let session = openSession, !items.isEmpty else {
            return Self.refusedBatch(
                items, change: change, reason: .locationUnavailable,
                message: "The open folder no longer holds these photos.")
        }
        let scanned = store
        var order: [PhotoIdentity: Int] = [:]
        var byChange: [MarkChange: [ScannedPhotoSet]] = [:]
        var itemsByIdentity: [PhotoIdentity: BatchMarkItem] = [:]
        var refused: [MarkChangeStatus] = []
        var unavailable: [BatchMarkItem] = []
        for (index, item) in items.enumerated() {
            order[item.photo] = index
            itemsByIdentity[item.photo] = item
            guard let set = scanned.scannedSet(for: item.photo) else {
                unavailable.append(item)
                let status = Self.refused(
                    item.change, for: item.photo, reason: .locationUnavailable,
                    message: "The open folder no longer holds this photo.")
                publish(.change(status))
                refused.append(status)
                continue
            }
            byChange[item.change, default: []].append(set)
        }
        guard case .success(let stores) = await resolvedStores() else {
            return Self.refusedBatch(
                items, change: change, reason: .unknown,
                message: "Clove's stored marks are unavailable.")
        }
        var queueBatches: [MarkBatchID] = []
        var outcomes = refused
        for (change, sets) in byChange {
            let admitted: MarkBatchResult? = try? await session.withAdmittedWork {
                await stores.writes.apply(change, to: sets)
            }
            guard let result = admitted else {
                for set in sets {
                    guard let item = itemsByIdentity[set.photoSet.id] else { continue }
                    unavailable.append(item)
                    let status = Self.refused(
                        change, for: item.photo, reason: .locationUnavailable,
                        message: "The folder closed before the batch could be written.")
                    publish(.change(status))
                    outcomes.append(status)
                }
                continue
            }
            queueBatches.append(result.id)
            outcomes.append(contentsOf: result.outcomes)
        }
        outcomes.sort { (order[$0.identity] ?? .max) < (order[$1.identity] ?? .max) }
        let batch = MarkBatchID()
        // The batch is kept even when nothing reached the queue, so a retry reports the photos
        // the folder no longer holds instead of dropping them (PRD P0-09).
        batches[batch] = AppliedBatch(
            change: change, queueBatches: queueBatches, unavailable: unavailable)
        return MarkBatchResult(id: batch, change: change, outcomes: outcomes)
    }

    /// Retries only the photos one batch could not save (PRD P0-09).
    ///
    /// Each C4 batch the bar action admitted is retried through the same session, so a retry
    /// writes under the folder's scope like the first attempt. A photo the folder no longer holds
    /// is reported as failed again instead of disappearing from the counts. A folder that closed,
    /// or a batch this session never applied, cannot be retried and answers nil.
    func retryFailed(in batch: MarkBatchID) async -> MarkBatchResult? {
        guard let applied = batches[batch], let session = openSession else { return nil }
        switch await resolvedStores() {
        case .failure:
            return nil
        case .success(let stores):
            var outcomes: [MarkChangeStatus] = []
            for queueBatch in applied.queueBatches {
                let retried: MarkBatchResult? = try? await session.withAdmittedWork {
                    await stores.writes.retryFailed(in: queueBatch)
                }
                if let retried { outcomes.append(contentsOf: retried.outcomes) }
            }
            for item in applied.unavailable {
                let status = Self.refused(
                    item.change, for: item.photo, reason: .locationUnavailable,
                    message: "The open folder no longer holds this photo.")
                publish(.change(status))
                outcomes.append(status)
            }
            // The retry's own handle stays usable, so a second attempt touches the same photos
            // as the first and never repeats a write that already confirmed.
            let retryBatch = MarkBatchID()
            batches[retryBatch] = applied
            return MarkBatchResult(id: retryBatch, change: applied.change, outcomes: outcomes)
        }
    }

    // MARK: - Move rejects

    /// Plans Move rejects for the open folder's rejected photos (PRD P0-10).
    ///
    /// C6's planner reads existence only, so the sheet can show its counts before the user
    /// commits. The request is built from the marks the folder holds now and from the settings
    /// the caller read at move time (PRD Move rejects, C12); a disabled setting or a read-only
    /// volume refuses the whole request before any file is touched.
    func planRejectMove(configuration: RejectMoveConfiguration) async throws -> RejectMovePlan {
        guard let mover = rejectMover, let session = openSession else {
            throw FolderSessionError.ended
        }
        let rejected = store.photos.filter(\.marks.isRejected)
        let sets = rejected.compactMap { store.scannedSet(for: $0.id) }
        return try await mover.plan(
            for: RejectMoveRequest(
                rootURL: session.rootURL, sets: sets, configuration: configuration))
    }

    /// Runs a confirmed plan under the folder's session and drops the moved photos (PRD P0-10).
    ///
    /// The whole move is admitted work, so ending the folder waits for it before releasing the
    /// scope (G1 folder access). Moved sets leave the folder's photos and grouping runs again over
    /// the remaining ones, the same way it does after a scan finishes; failed and skipped sets
    /// stay in place, still rejected, so a retry addresses only the failures.
    func runRejectMove(_ plan: RejectMovePlan) async throws -> RejectMoveResult {
        guard let mover = rejectMover, let session = openSession else {
            throw FolderSessionError.ended
        }
        let generation = scanGeneration
        let result = try await session.withAdmittedWork {
            try await mover.move(plan)
        }
        guard generation == scanGeneration, openSession === session else { return result }
        let moved = result.movedIdentities
        guard !moved.isEmpty else { return result }
        movedRejectIdentities.formUnion(moved)
        store.remove(moved)
        publish(.photos([]))
        await startGrouping(generation: scanGeneration)
        return result
    }

    /// Retries only the sets an earlier run could not move (PRD P0-10).
    ///
    /// The retry is admitted like the first run and drops whatever it moves, so a retry's moved
    /// sets leave the grid as the first run's did. A folder that closed, or a run this session
    /// never started, cannot be retried and answers nil.
    func retryFailedRejects(
        in batch: RejectMoveBatchID, excluding identities: Set<PhotoIdentity>
    ) async throws -> RejectMoveResult? {
        guard let mover = rejectMover, let session = openSession else { return nil }
        let generation = scanGeneration
        let retried = try await session.withAdmittedWork {
            try await mover.retryFailed(in: batch, excluding: identities)
        }
        guard let result = retried else { return nil }
        guard generation == scanGeneration, openSession === session else { return result }
        let moved = result.movedIdentities
        guard !moved.isEmpty else { return result }
        movedRejectIdentities.formUnion(moved)
        store.remove(moved)
        publish(.photos([]))
        await startGrouping(generation: scanGeneration)
        return result
    }

    /// The progress steps of the next or running Move rejects (PRD P0-10).
    func rejectMoveProgress() async -> AsyncStream<RejectMoveProgress> {
        guard let mover = rejectMover else { return AsyncStream { $0.finish() } }
        return await mover.progressUpdates()
    }

    // MARK: - In-group culling

    /// Runs one finishing action's plan through C10's executor and C4's write queue
    /// (PRD In-group culling, finishing actions; PRD P0-12).
    ///
    /// The executor records the group's completion first, because the action ran even when a
    /// write later fails, then re-reads each photo's marks so a rating or label applied after the
    /// plan was built is never rejected (PRD P0-12). The writes are admitted through C11's
    /// session, so ending the folder waits for them before releasing its scope (G1 folder access).
    /// A folder that closed, or whose stored marks are unavailable, reports the refused changes
    /// instead of claiming they were saved (PRD P0-08).
    func runGroupFinishing(_ plan: GroupFinishingPlan) async -> GroupFinishingResult {
        // The session is read before anything is awaited, so the action can only run inside the
        // folder that was open when it started (G1 folder access).
        guard let session = openSession else {
            return finishingResult(plan, refused: "No folder is open.")
        }
        switch await resolvedStores() {
        case .failure(let error):
            return finishingResult(
                plan, refused: "Clove's stored marks are unavailable: \(error)")
        case .success(let stores):
            let executor = GroupFinishingExecutor(
                queue: stores.writes, completion: groupCompletionTracker)
            do {
                return try await session.withAdmittedWork {
                    await executor.execute(
                        plan,
                        photoSet: { [weak self] photo in await self?.finishingSet(for: photo) },
                        latestMarks: { [weak self, writes = stores.writes] photo in
                            await self?.finishingMarks(for: photo, in: writes) ?? PhotoMarks()
                        })
                }
            } catch {
                return finishingResult(
                    plan, refused: "The folder closed before the action could run.")
            }
        }
    }

    /// Retries only the changes of one finishing action that still need it (PRD P0-09).
    ///
    /// A failure C4 admitted has a handle, so the queue retries exactly those changes. A refusal
    /// that never reached the queue has none, so the plan runs again under the checks the executor
    /// always applies, which drops whatever no longer needs writing (``rerun(_:executor:)``).
    func retryGroupFinishing(_ result: GroupFinishingResult) async -> GroupFinishingResult {
        guard let session = openSession else { return result }
        guard case .success(let stores) = await resolvedStores() else { return result }
        let executor = GroupFinishingExecutor(
            queue: stores.writes, completion: groupCompletionTracker)
        do {
            return try await session.withAdmittedWork {
                guard result.keptChangeID != nil || result.rejectedBatchID != nil else {
                    return await self.rerun(
                        result, executor: executor, writes: stores.writes)
                }
                return await executor.retryFailed(in: result)
            }
        } catch {
            return result
        }
    }

    /// Runs a finishing action again after a refusal that never reached C4's queue (PRD P0-09).
    ///
    /// A handle-less result is one the folder refused before writing, so none of its changes is
    /// stored and running the plan again is the retry. The executor re-reads every photo's marks,
    /// so a change that gained a rating or label meanwhile is dropped instead of written. The undo
    /// record is built from the changes both runs actually confirmed, so a photo the retry skipped
    /// cannot be undone back over a newer mark (PRD P0-12; DEV-PLAN C5).
    private func rerun(
        _ result: GroupFinishingResult, executor: GroupFinishingExecutor, writes: MarkWriteQueue
    ) async -> GroupFinishingResult {
        let rerun = await executor.execute(
            result.plan,
            photoSet: { [weak self] photo in await self?.finishingSet(for: photo) },
            latestMarks: { [weak self] photo in
                await self?.finishingMarks(for: photo, in: writes) ?? PhotoMarks()
            })
        var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
        for outcome in result.outcomes where outcome.status.state.isConfirmed {
            statuses[outcome.photo] = outcome.status
        }
        for outcome in rerun.outcomes { statuses[outcome.photo] = outcome.status }
        let confirmed = result.outcomes.filter(\.status.state.isConfirmed).map(\.change)
        let changed = rerun.outcomes.map(\.change)
        return GroupFinishingResult.applied(
            result.plan, changes: confirmed + changed, statuses: statuses)
    }

    /// Whether the group is complete, and where the group view goes next (PRD P0-12).
    ///
    /// The marks are the folder's marks read now, so a group completed by its marks and one a
    /// finishing action ran on answer the same question (PRD In-group culling, group completion).
    func groupCompletion(
        for groupID: GroupID, behaviour: GroupCompletionBehaviour
    ) async -> GroupViewCompletion {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for photo in store.photos { marks[photo.id] = photo.marks }
        return await groupCompletionTracker.viewCompletion(
            after: groupID, in: publishedGroups, behaviour: behaviour, marks: marks)
    }

    /// The scanned set behind one photo for a finishing action's write (PRD P0-12; G1 Safe
    /// writes).
    private func finishingSet(for photo: PhotoIdentity) -> ScannedPhotoSet? {
        store.scannedSet(for: photo)
    }

    /// The marks one finishing action re-checks against (PRD P0-12).
    ///
    /// A photo whose rating or label is still being written counts as marked: auto-advance can
    /// bring the next photo onto the screen within the write's time, and rejecting such a photo
    /// would leave one photo both rated and rejected. C4 keeps the request until a newer change
    /// replaces it (PRD How marks reach disk, rule 8), so the requested fields are applied to the
    /// confirmed marks here, exactly as the plan's input does
    /// (``BrowsingModel/cullingMarks(for:)``).
    private func finishingMarks(
        for photo: PhotoIdentity, in writes: MarkWriteQueue
    ) async -> PhotoMarks {
        let confirmed = store.photo(for: photo)?.marks ?? PhotoMarks()
        return await writes.marksShown(for: photo, confirmed: confirmed)
    }

    /// A finishing action the folder could not run: every planned change reports the refusal, so
    /// the group view shows what still needs saving and offers a retry (PRD P0-08, P0-09).
    private func finishingResult(
        _ plan: GroupFinishingPlan, refused message: String
    ) -> GroupFinishingResult {
        var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in plan.changes {
            statuses[change.photo] = MarkChangeStatus(
                id: MarkChangeID(), identity: change.photo, requested: change.change,
                state: .failed(
                    MarkWriteFailure(reason: .locationUnavailable, message: message)))
        }
        return GroupFinishingResult.applied(plan, statuses: statuses)
    }
    // MARK: - Entry

    /// Re-reads C11's Recents list (PRD P0-02).
    ///
    /// A store that cannot be read keeps its file untouched and is reported, so entry explains it
    /// instead of showing an empty list as if nothing had ever opened (PRD P0-02).
    func reloadRecents() async {
        switch await resolvedStores() {
        case .success(let stores):
            do {
                recents = try await stores.access.recents()
                recentsFailure = nil
            } catch {
                recentsFailure = Self.recentsFailure(for: error)
            }
        case .failure(let error):
            recentsFailure = Self.storageFailure(for: error)
        }
    }

    /// Opens a folder chosen in the system picker and scans it (PRD P0-01).
    func pick(_ url: URL) async -> FolderAccessFailure? {
        switch await resolvedStores() {
        case .failure(let error):
            return Self.storageFailure(for: error)
        case .success(let stores):
            switch await stores.access.pick(url) {
            case .opened(let opened):
                await open(opened)
                return nil
            case .failed(let failure):
                return failure
            }
        }
    }

    /// Reopens one remembered folder and scans it (PRD P0-02).
    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        switch await resolvedStores() {
        case .failure(let error):
            return Self.storageFailure(for: error)
        case .success(let stores):
            switch await stores.access.reopen(recent.id) {
            case .opened(let opened):
                await open(opened)
                return nil
            case .failed(let failure):
                return failure
            }
        }
    }

    /// Reopens the folder a saved scene names, for launch restore (PRD P0-02, P0-14).
    ///
    /// It answers as soon as C11 reopened and validated the folder, so entry shows the saved
    /// folder's grid at once instead of waiting for a large RAW folder's metadata. The scan keeps
    /// streaming, and its `scanFinished` update tells the model when the folder's contents are
    /// known and the saved scene can be validated. A folder that did not open answers with C11's
    /// reason, which entry explains on the matching Recents item.
    func openSavedFolder(_ folder: FolderIdentity) async -> FolderAvailability {
        await reloadRecents()
        if let failure = recentsFailure { return .unavailable(failure) }
        guard let recent = recents.first(where: { $0.identity == folder }) else {
            // The record is gone, so the saved location cannot be reopened; P0-02 asks for the
            // folder again rather than opening nothing.
            return .unavailable(Self.missingLocation)
        }
        if let failure = await reopen(recent) { return .unavailable(failure) }
        return .available(contents)
    }

    // MARK: - Opening

    /// Opens one folder after every open queued before it finished (PRD P0-01).
    ///
    /// A launch restore and a tap on a Recents item can overlap, as can two quick taps. Each
    /// transition runs after the previous one, so a later open is never replaced by an earlier
    /// one that resumed late, and every replaced session is ended.
    private func open(_ opened: OpenedFolder) async {
        let earlier = openTransition
        let transition = Task { [weak self] in
            await earlier?.value
            await self?.install(opened)
        }
        openTransition = transition
        await transition.value
    }

    /// Installs one opened folder: ends the previous one, then scans the new one.
    private func install(_ opened: OpenedFolder) async {
        await endOpenFolder()
        guard case .success(let stores) = await resolvedStores() else {
            // Without the app-private stores the folder can be neither scanned nor written, so
            // its grant is released instead of being held by a folder nothing can use.
            await opened.session.end()
            return
        }
        let session = opened.session
        isClosingFolder = false
        scanGeneration += 1
        let generation = scanGeneration
        folder = session.folder.id
        openSession = session
        store = FolderPhotos()
        changes = PhotoChangeStates()
        groupCompletionTracker = GroupCompletionTracker()

        batches = [:]
        // PRD P0-05's history belongs to the folder that opens, so a new folder never offers an
        // older folder's actions, and it keeps this folder's own completion records (PRD P0-12).
        undoHistory = MarkUndoHistory(
            queue: stores.writes, completion: groupCompletionTracker)
        undoState = .none
        // The queue outlives the folder, so this open seeds its shown marks from the scan again
        // (PRD P0-05).
        await stores.writes.forgetShownMarks(in: session.folder.id)
        movedRejectIdentities = []
        rejectMover = RejectMover(markQueue: stores.writes)
        publishedGroups = []
        hasPublishedGroups = false
        publish(.scanStarted)
        publish(.photos([]))
        // PRD How marks reach disk, rule 1: Reject and standalone marks are read when the folder
        // opens. A damaged store is reported by U7's save state; the scan still shows the photos.
        let storedMarks = (try? await stores.writes.storedMarks(for: session.folder.id)) ?? [:]
        let configuration = ScanConfiguration(
            rejectsFolderName: rejectsFolderName().rawValue)
        let caches = await Self.makeCaches()
        thumbnailSource = makeThumbnailSource(for: session, caches: caches)
        detailSource = makeDetailSource(for: session)
        // The loss is reported for the folder this open installed, never for a later one.
        let monitor = makeLocationMonitor(for: session, mediaType: opened.recent.mediaType)
        locationMonitor = monitor
        let installedFolder = session.folder.id
        await monitor.start { [weak self] loss in
            Task { @MainActor [weak self] in
                self?.locationLost(loss, folder: installedFolder, generation: generation)
            }
        }
        grouping = makeGrouping(
            for: session, stores: stores, caches: caches, generation: generation)
        let scan = FolderScan(
            folderURL: session.rootURL, folderID: session.folder.id,
            configuration: configuration)
        openScan = scan
        scanTask = Task { [weak self] in
            await self?.scan(
                scan, session: session, storedMarks: storedMarks, stores: stores,
                generation: generation)
        }
    }

    /// Ends the open folder: cancels its scan, drains writes and releases the scope.
    ///
    /// G1 folder access keeps the scope until the work that relies on it drains, so the queue is
    /// drained before the session ends. Ending waits for the scan's admitted work as well.
    private func endOpenFolder() async {
        isClosingFolder = true
        scanGeneration += 1
        if let monitor = locationMonitor {
            locationMonitor = nil
            await monitor.stop()
        }
        openScan?.cancel()
        openScan = nil
        scanTask?.cancel()
        scanTask = nil
        thumbnailSource = nil
        rejectMover = nil
        movedRejectIdentities = []
        publishedGroups = []
        hasPublishedGroups = false
        if let grouping {
            self.grouping = nil
            // Grouping's 400 px preview reads run under the folder's scope too, so the folder
            // waits for them exactly as it waits for a grid decode (G1 folder access).
            await grouping.close()
        }
        if let pipeline = thumbnailPipeline {
            thumbnailPipeline = nil
            // I1's close cancels queued work and waits for a decode in flight, so the scope is
            // never released under one (G1 preview and folder-access rows).
            await pipeline.close()
        }
        detailSource = nil
        if let pipeline = detailPipeline {
            detailPipeline = nil
            // I2's close cancels queued work and waits for a render in flight, so the scope is
            // never released under one (G1 preview and folder-access rows).
            await pipeline.close()
        }
        if case .success(let stores) = await resolvedStores() {
            await stores.writes.drain()
            // PRD Failure and recovery: a folder that closes takes its unconfirmed changes with
            // it, so the next open reads the actual XMP and no later leaving question counts
            // marks the user abandoned.
            if folder != Self.noFolder {
                await stores.writes.forgetUnfinishedChanges(in: folder)
            }
        }
        // PRD P0-05 does not keep a history across folders, so a closed folder forgets every
        // action it could undo; a step still running finishes its writes but cannot repopulate it.
        if let history = undoHistory {
            undoHistory = nil
            undoState = .none
            await history.clear()
        }
        guard let session = openSession else { return }
        openSession = nil
        await session.end()
    }

    // MARK: - Scan

    /// Walks the folder inside C11's admitted work and publishes what it finds.
    ///
    /// The whole walk, its metadata and sidecar reads run in the admitted closure, off the main
    /// actor, so ending the session waits for them before releasing the scope. The scan's own
    /// producer is awaited on every exit too, so a cancelled consumer cannot leave the walk
    /// enumerating files after the admitted work returned. Every publication checks its
    /// generation, so a scan a newer open replaced never lands in the new folder.
    private func scan(
        _ scan: FolderScan,
        session: FolderAccessSession,
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        stores: Stores,
        generation: Int
    ) async {
        let metadata = metadata
        let codec = codec
        do {
            try await session.withAdmittedWork { [weak self] in
                do {
                    for try await batch in scan {
                        try Task.checkCancellation()
                        guard let self else { return }
                        let sets = await self.admit(
                            batch.items, storedMarks: storedMarks, generation: generation)
                        guard !sets.isEmpty else { continue }
                        // I4 reads the primary file of each set off the main actor; a RAW set's
                        // capture time comes from the RAW (G1 decision 1, I4).
                        let reads = await metadata.read(urls: sets.map { $0.photoSet.primary.url })
                        let marks = Self.readMarks(
                            for: sets, storedMarks: storedMarks, codec: codec)
                        await self.applyReads(
                            reads, marks: marks, sets: sets, generation: generation)
                    }
                    let summary = try await scan.summary()
                    await self?.finishScan(
                        summary, session: session, stores: stores, generation: generation)
                } catch {
                    // The consumer stopped early, but the walk may still be enumerating files.
                    // Awaiting the producer keeps the admitted work, and the scope behind it,
                    // until the walk has actually ended.
                    _ = try? await scan.summary()
                    throw error
                }
            }
        } catch is CancellationError {
            // A newer open or a closed folder cancelled this scan; it publishes nothing.
        } catch {
            await failedScan(generation: generation)
        }
    }

    /// Adds one batch's photos, publishing the ones that are new (PRD P0-01, P0-03).
    ///
    /// The photos enter with a `.pending` time, so the grid withholds them until their metadata
    /// read lands instead of showing a filename order first (G1 decision 3).
    private func admit(
        _ items: [ScanItem],
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        generation: Int
    ) -> [ScannedPhotoSet] {
        guard generation == scanGeneration else { return [] }
        let items = items.filter { item in
            guard case .photo(let set) = item else { return true }
            return !movedRejectIdentities.contains(set.id)
        }
        let added = store.insert(items, storedMarks: storedMarks)
        guard !added.isEmpty else { return [] }
        publish(.photos(added))
        return added.compactMap { store.scannedSet(for: $0.id) }
    }

    /// Applies one batch's metadata and mark reads (PRD P0-03, P0-07, P0-11).
    private func applyReads(
        _ reads: [MetadataFileResult],
        marks: [PhotoIdentity: PhotoMarks],
        sets: [ScannedPhotoSet],
        generation: Int
    ) {
        guard generation == scanGeneration else { return }
        let timeZone = TimeZone.current
        var times: [PhotoIdentity: PhotoTimeState] = [:]
        for read in reads {
            guard let set = sets.first(where: { $0.photoSet.primary.url == read.url }) else {
                continue
            }
            let time = Self.timeState(for: read.outcome, in: timeZone)
            times[set.id] = time
            store.setTime(time, for: set.id)
            // G1's Grouping row separates photos by camera model plus the serial when the file
            // carries one, so the read's values are kept beside the time for grouping.
            if case .success(let metadata) = read.outcome {
                store.setCameraBody(
                    CameraBody(
                        model: metadata.model.value, serial: metadata.bodySerial.value),
                    for: set.id)
            }
        }
        for (id, marks) in marks {
            store.setMarks(marks, for: id)
        }
        publish(.reads(times: times, marks: marks))
    }

    /// Records the finished scan's count for Recents and publishes its outcome (PRD P0-02).
    ///
    /// A partial walk is recorded as partial, because PRD P0-01 never reports a shorter folder as
    /// a complete scan. A store error leaves the previous record in place.
    private func finishScan(
        _ summary: ScanSummary,
        session: FolderAccessSession,
        stores: Stores,
        generation: Int
    ) async {
        guard generation == scanGeneration else { return }
        let recorded = FolderScanSummary(
            photoCount: summary.logicalPhotoCount,
            status: summary.status == .complete ? .complete : .partial)
        try? await stores.access.recordScan(recorded, for: session)
        await reloadRecents()
        await startGrouping(generation: generation)
        // The folder can be replaced while grouping runs above, so the report is re-checked
        // against the generation it belongs to before it reaches the model.
        guard generation == scanGeneration else { return }
        publish(.scanFinished(recorded))
    }

    /// Reports a scan that could not run as partial, without recording a count (PRD P0-01).
    private func failedScan(generation: Int) async {
        guard generation == scanGeneration else { return }
        await startGrouping(generation: generation)
        guard generation == scanGeneration else { return }
        publish(
            .scanFinished(
                FolderScanSummary(photoCount: store.count, status: .partial)))
    }

    // MARK: - Reads

    /// I4's read as C8's ordering state (PRD P0-03, G1 decision 3).
    ///
    /// A file the metadata reader could not read has no usable time, so it sorts with the other
    /// untimed photos instead of being hidden.
    private nonisolated static func timeState(
        for outcome: MetadataReadOutcome,
        in timeZone: TimeZone
    ) -> PhotoTimeState {
        guard case .success(let metadata) = outcome else { return .unavailable }
        switch metadata.time {
        case .captureMetadata(let capture):
            return .known(
                PhotoTime(
                    captureWallTime: capture.wallTime,
                    utcOffsetSeconds: capture.utcOffsetSeconds, in: timeZone))
        case .fileCreation(let date):
            return .known(PhotoTime(fileCreation: date))
        case .fileModification(let date):
            return .known(PhotoTime(fileModification: date))
        case .unavailable:
            return .unavailable
        }
    }

    /// Reads each RAW set's sidecar through C3 and combines it with Clove's stored marks
    /// (PRD P0-05, P0-07; G1 decisions 2, 5–6).
    ///
    /// Only a RAW set reads a packet: a standalone JPEG or HIF is never given a sidecar, so a
    /// stray packet beside it cannot override the marks Clove stores for it. A packet C3 refuses
    /// contributes nothing and is not repaired, so the photo keeps whatever Clove stores and U7
    /// can report the refusal with its own copy.
    private nonisolated static func readMarks(
        for sets: [ScannedPhotoSet],
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        codec: XMPCodec
    ) -> [PhotoIdentity: PhotoMarks] {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for set in sets {
            var packet: XMPMarks?
            if set.photoSet.primary.format == .raw, let url = set.sidecar.resolvedURL,
                let data = try? Data(contentsOf: url)
            {
                packet = try? codec.read(data)
            }
            marks[set.id] = PhotoMarks(
                stored: storedMarks[set.id], xmp: packet,
                persistence: set.photoSet.markPersistence)
        }
        return marks
    }

    // MARK: - Thumbnails

    /// Builds the open folder's grid source over a pipeline bound to its session (PRD P0-03).
    ///
    /// The pipeline's requests are admitted through the folder's C11 session, so ending the
    /// folder drains a decode before releasing the scope (G1 preview and folder-access rows). A
    /// cache that cannot be created leaves the grid without previews rather than failing the open.
    private func makeThumbnailSource(for session: FolderAccessSession, caches: Caches?)
        -> (any GridThumbnailSource)?
    {
        guard let caches else { return nil }
        let pipeline = ThumbnailPipeline(cache: caches.thumbnails)
        thumbnailPipeline = pipeline
        let folder = session.folder.id
        return PipelineGridThumbnails(
            pipeline: pipeline,
            set: { [weak self] photo in self?.store.scannedSet(for: photo)?.photoSet },
            admitted: { [weak self] work in
                guard let self else { return .unavailable }
                return await self.admittedThumbnail(work, session: session, folder: folder)
            })
    }

    /// Builds the open folder's grouping over C9 and I3 (PRD P0-11, G1's Grouping row).
    ///
    /// One grouper and one feature pipeline live as long as the folder; ``endOpenFolder()``
    /// closes them before the scope is released. The group cache is app-private, so a reopened
    /// folder shows its finished groups at once, and the feature pipeline shares the grid's
    /// preview cache so grouping never decodes a preview the grid already has (G1 preview row).
    /// A folder whose caches could not be created groups nothing rather than failing the open.
    private func makeGrouping(
        for session: FolderAccessSession, stores: Stores, caches: Caches?, generation: Int
    ) -> FolderGrouping? {
        guard let caches else { return nil }
        let folder = session.folder.id
        return FolderGrouping(
            folder: folder,
            session: session,
            cache: stores.groups,
            featureCache: caches.features,
            previewCache: caches.thumbnails,
            sets: { [weak self] photo in self?.store.scannedSet(for: photo)?.photoSet },
            publish: { [weak self] groups in
                // A replaced folder publishes nothing: the open that owns this grouping is gone.
                guard let self, generation == self.scanGeneration else { return }
                self.publishGroups(groups)
            })
    }

    /// Runs grouping's time stage for the open folder and publishes its result (PRD P0-11).
    ///
    /// The first publication always lands, even with no groups, before the scan reports itself
    /// finished: a saved group view waits for it instead of dropping its place on every launch
    /// (PRD P0-14). A folder that could not build grouping publishes an empty result here too.
    /// The pass suspends, so the generation is re-checked before anything reaches the model: a
    /// folder replaced meanwhile must publish neither its groups nor its empty result.
    private func startGrouping(generation: Int) async {
        let photos = store.groupingPhotos
        let revision = groupingRevision()
        if let grouping {
            await grouping.begin(
                photos: photos, revision: revision, enabled: similarGroupsEnabled())
        }
        guard generation == scanGeneration else { return }
        if !hasPublishedGroups { publishGroups([]) }
    }

    /// The group cache's token for the folder as the scan found it (PRD Similar groups rules).
    ///
    /// C9's fingerprint covers each photo's identity, name, capture time and body; the scan's
    /// primary-file revisions cover a file replaced in place, so neither a changed file nor a
    /// changed feature pipeline can restore older groups (PRD P0-11).
    private func groupingRevision() -> GroupingInputRevision {
        let sets = store.photos.compactMap { store.scannedSet(for: $0.id) }
        return .scanned(sets, feature: FolderGrouping.featureRevision)
    }

    /// Publishes grouping's groups for the open folder (PRD P0-11).
    ///
    /// The first publication of a folder always lands, because a saved group view waits for it
    /// (PRD P0-14); a later publication only lands when it changed something, so refinement and
    /// Run again do not repaint an unchanged grid.
    private func publishGroups(_ groups: [BrowsingGroup]) {
        guard groups != publishedGroups || !hasPublishedGroups else { return }
        publishedGroups = groups
        hasPublishedGroups = true
        publish(.groups(groups))
    }

    /// Runs one grid request inside the session that holds the folder's scope.
    ///
    /// A request that arrives after the folder ended, or for another folder's photo, answers
    /// unavailable instead of decoding under a scope the folder no longer holds (G1 folder access).
    private func admittedThumbnail(
        _ work: @Sendable () async -> GridThumbnailOutcome,
        session: FolderAccessSession,
        folder: FolderIdentity
    ) async -> GridThumbnailOutcome {
        guard self.folder == folder else { return .unavailable }
        do {
            return try await session.withAdmittedWork { await work() }
        } catch {
            return .unavailable
        }
    }

    // MARK: - Detail pixels

    /// Builds the open folder's detail source over I2's pipeline bound to its session
    /// (PRD P0-04, G1 "Preview, detail (I2)").
    ///
    /// G1 keeps the detail cache in memory (32 MiB plus one native render), so the pipeline needs
    /// no directory, unlike the grid's disk cache. Its reads are admitted through the folder's
    /// C11 session, so ending the folder waits for a read before releasing the scope.
    private func makeDetailSource(for session: FolderAccessSession) -> any DetailImageSource {
        let pipeline = DetailPipeline()
        detailPipeline = pipeline
        let folder = session.folder.id
        return PipelineDetailImages(
            pipeline: pipeline,
            set: { [weak self] photo in self?.store.scannedSet(for: photo)?.photoSet },
            admitted: DetailWorkAdmission(
                image: { [weak self] work in
                    guard let self else { return .unavailable(.noUsablePreview) }
                    return await self.admittedDetail(work, session: session, folder: folder)
                },
                prefetch: { [weak self] work in
                    guard let self else { return }
                    await self.admittedDetailPrefetch(work, session: session, folder: folder)
                }))
    }

    /// Runs one detail request inside the session that holds the folder's scope.
    ///
    /// A request that arrives after the folder ended, or for another folder's photo, answers
    /// unavailable instead of reading under a scope the folder no longer holds (G1 folder access).
    private func admittedDetail(
        _ work: @Sendable () async -> DetailImageOutcome,
        session: FolderAccessSession,
        folder: FolderIdentity
    ) async -> DetailImageOutcome {
        guard self.folder == folder else { return .unavailable(.noUsablePreview) }
        do {
            return try await session.withAdmittedWork { await work() }
        } catch {
            return .unavailable(.noUsablePreview)
        }
    }

    /// Runs neighbour prefetch inside the same session, so its reads are scoped too.
    private func admittedDetailPrefetch(
        _ work: @Sendable () async -> Void,
        session: FolderAccessSession,
        folder: FolderIdentity
    ) async {
        guard self.folder == folder else { return }
        _ = try? await session.withAdmittedWork { await work() }
    }

    /// Builds the folder's caches over the app's Caches directory, off the main actor.
    ///
    /// Creating either cache makes its directory and reads what it already holds, so this runs in
    /// a detached task; the folder waits for it while opening, and nothing touches the disk during
    /// the scene's first body evaluation.
    private nonisolated static func makeCaches() async -> Caches? {
        await Task.detached(priority: .userInitiated) {
            do {
                let caches = try FileManager.default.url(
                    for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let thumbnails = try ThumbnailCache(
                    directory: caches.appendingPathComponent(
                        "Clove/GridThumbnails", isDirectory: true))
                let features = try ImageFeatureCache(
                    directory: caches.appendingPathComponent(
                        "Clove/ImageFeatures", isDirectory: true))
                return Caches(thumbnails: thumbnails, features: features)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Location

    /// Starts the watch that reports the open folder's location going away (G1 folder access).
    ///
    /// G1 uses presenters plus a 500 ms poll while the app is in the foreground; the monitor holds
    /// the folder's URL, its media type and the volume root it reads at start, so a folder on an
    /// external drive can tell a disconnect from a missing folder. The library keeps the monitor
    /// so a return to the foreground can check at once and ``endOpenFolder()`` can stop it.
    private func makeLocationMonitor(for session: FolderAccessSession, mediaType: FolderMediaType)
        -> FolderLocationMonitor
    {
        FolderLocationMonitor(rootURL: session.rootURL, mediaType: mediaType)
    }

    /// Publishes a loss the watch reported for the folder this open installed (PRD P0-02).
    ///
    /// A loss that arrives after another open replaced the folder is dropped here, and the update
    /// carries the folder's identity and the open so a reader that had already suspended cannot
    /// apply it to a newer folder or to a later open of the same folder either.
    private func locationLost(_ loss: FolderLocationLoss, folder: FolderIdentity, generation: Int) {
        guard generation == scanGeneration else { return }
        publish(.locationLost(folder: folder, loss: loss, generation: generation))
    }

    // MARK: - Writes

    /// Records one change's state from C4's ordered stream (PRD P0-08).
    ///
    /// Only a status the merge accepts may change the photo's marks: a refused status belongs to
    /// an older change a newer one replaced, and painting its fields would show an older rating
    /// again. The same rule keeps ``latestChange(for:)`` equal to the queue's newest change.
    private func record(_ status: MarkChangeStatus) {
        if changes.insert(status), status.state.isConfirmed {
            store.apply(status.requested, to: status.identity)
            if let photo = store.photo(for: status.identity) {
                publish(.reads(times: [:], marks: [status.identity: photo.marks]))
            }
        }
        publish(.change(status))
    }

    // MARK: - Grouping

    /// Runs similar groups again for the open folder without the group cache (PRD P0-11).
    ///
    /// P0-11 keeps Run again available beside the published groups. The current photos are the
    /// inputs, the cache's finished result is not reused, and the refinement follows in the
    /// background as it does on open; the group keys stay put through C9's ancestry, so the grid
    /// does not move the photo the user is looking at.
    func runGroupingAgain() async {
        guard let grouping, hasPublishedGroups else { return }
        await grouping.runAgain(photos: store.groupingPhotos)
    }

    /// Applies C12's similar-groups setting to the open folder (PRD P0-11).
    ///
    /// Off publishes no groups and stops feature work; on publishes the cached or time-only
    /// result at once and refines again. The settings store keeps and persists the value; this
    /// only applies it to the folder that is open, and ``similarGroupsEnabled`` reads the store
    /// again when the next folder opens. Grouping that has not started yet needs nothing: its
    /// time stage reads the store when the scan finishes, so a change during the scan is covered.
    func setSimilarGroupsEnabled(_ enabled: Bool) async {
        guard hasPublishedGroups else { return }
        await grouping?.setEnabled(enabled, photos: store.groupingPhotos)
    }

    // MARK: - Publishing

    /// Sends one update to the model's stream (PRD P0-03, P0-08).
    private func publish(_ update: FolderLibraryUpdate) {
        updatesContinuation.yield(update)
    }

    /// The stores, or why they could not be prepared (PRD P0-02).
    private func resolvedStores() async -> Result<Stores, any Error> {
        do {
            return .success(try await stores.value)
        } catch {
            return .failure(error)
        }
    }

    /// C11's reason for a Recents read that failed (PRD P0-02).
    private static func recentsFailure(for error: any Error) -> FolderAccessFailure {
        if let storeError = error as? RecentFolderStoreError {
            return .storageUnavailable(storeError)
        }
        return .storageUnavailable(.unreadable(FolderErrorChain(error)))
    }

    /// The reason a store that could not be prepared gives, kept as storage so entry explains it
    /// rather than failing silently (PRD P0-02).
    private static func storageFailure(for error: any Error) -> FolderAccessFailure {
        .storageUnavailable(.unreadable(FolderErrorChain(error)))
    }

    /// The failure of a change the library cannot write (PRD P0-08).
    private static func refused(
        _ change: MarkChange,
        for photo: PhotoIdentity,
        reason: MarkWriteFailureReason,
        message: String
    ) -> MarkChangeStatus {
        MarkChangeStatus(
            id: MarkChangeID(), identity: photo, requested: change,
            state: .failed(MarkWriteFailure(reason: reason, message: message)))
    }

    /// A batch every photo of which this library cannot write (PRD P0-09, P0-08).
    private static func refusedBatch(
        _ items: [BatchMarkItem],
        change: MarkChange,
        reason: MarkWriteFailureReason,
        message: String
    ) -> MarkBatchResult {
        MarkBatchResult(
            id: MarkBatchID(), change: change,
            outcomes: items.map { item in
                refused(item.change, for: item.photo, reason: reason, message: message)
            })
    }

    /// The reason a saved folder that no longer has a record gives (PRD P0-02).
    private static let missingLocation = FolderAccessFailure.locationUnavailable(
        FolderErrorChain(CocoaError(.fileNoSuchFile)))

    /// One bar action as this session admitted it (PRD P0-09).
    private struct AppliedBatch {
        /// The change the action asked for, named on the retry's results (PRD P0-09).
        let change: MarkChange

        /// The C4 batches the action admitted, one per distinct per-photo change.
        let queueBatches: [MarkBatchID]

        /// The photos the folder no longer held, which a retry reports as failed again
        /// (PRD P0-08).
        let unavailable: [BatchMarkItem]
    }

    deinit {
        // A dropped library must not leave its scan running or its consumer attached; C11's
        // session releases the scope itself when it is deallocated.
        openScan?.cancel()
        scanTask?.cancel()
        writeStatusTask?.cancel()
        if let grouping {
            // Closing drains a preview read in flight, which cannot happen here, so it runs in
            // its own task; the grouping keeps the session alive until that read ends, and the
            // session's own deinit releases the scope if the library outlives it.
            Task { await grouping.close() }
        }
        updatesContinuation.finish()
    }
}
