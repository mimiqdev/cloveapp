import CloveCore
import CloveImaging
import Foundation
import UIKit

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
        var renamer: BatchRenamer? = nil

        /// Prepares the stores below Application Support (PRD P0-02, P0-08, P0-11).
        ///
        /// Resolving those paths touches the file system, so ``FolderLibraryLaunch`` runs this off
        /// the main actor instead of during the scene's first body evaluation.
        static func applicationSupport() throws -> Stores {
            let store = try RecentFolderStore.applicationSupport()
            let marksDirectory = try CloveMarkStore.applicationSupportDirectory()
            let groupsDirectory = try SimilarGroupsCache.applicationSupportDirectory()
            let marks = CloveMarkStore(directory: marksDirectory)
            return Stores(
                access: FolderAccess(store: store),
                writes: MarkWriteQueue(store: marks),
                groups: SimilarGroupsCache(directory: groupsDirectory),
                renamer: BatchRenamer(store: marks))
        }
    }

    /// The library's I1 preview cache, I3 feature cache, and sharpness disk cache.
    ///
    /// All three live in the app's Caches directory because all three can be rebuilt from the
    /// source files, and are shared across folder opens for the library's lifetime.
    struct Caches: Sendable {
        let thumbnails: ThumbnailCache
        let features: ImageFeatureCache
        let sharpness: RegionSharpnessCache?
    }

    /// The key a library answers with while no folder is open (PRD P0-02, P0-14).
    ///
    /// It is not a bookmark key, so a saved scene or a stored mark can never mistake it for a
    /// folder, and entry only shows a folder after a pick or a reopen returned one.
    static let noFolder = FolderIdentity(rawValue: "clove.folder.none")

    /// The stores, prepared off the main actor so the first scene never waits on disk.
    private let stores: Task<Stores, any Error>
    /// Shared preview, feature, and sharpness caches indexed once for the library's lifetime.
    private let caches: Task<Caches?, Never>
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

    /// The session holding the open folder's scope, ended when another folder opens.
    private var openSession: FolderAccessSession?

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

    /// The folder's detail pipeline, closed before its scope is released (PRD P0-04).
    private var detailPipeline: DetailPipeline?

    /// The open folder's in-memory sharpness result store, purged on memory pressure.
    private var sharpnessResults: RegionSharpnessResultStore?

    /// The open folder's sharpness scheduler, paused on critical memory pressure.
    private var sharpnessScheduler: RegionSharpnessScheduler?

    /// Whether background grouping/sharpness workers are paused due to critical memory pressure.
    private(set) var isPausedForMemoryPressure = false

    /// System memory-pressure source and UIKit warning observer active for the library's lifetime.
    private let memoryPressureSource: any DispatchSourceMemoryPressure
    private var memoryWarningTask: Task<Void, Never>?

    /// The detail view's source for the open folder, bound to that folder's session and pipeline.
    private var detailSource: (any DetailImageSource)?

    /// The mover and its undo records belong to this open folder.
    private var rejectMover: RejectMover?

    /// The photos a confirmed move took out of the folder (PRD P0-10).
    ///
    /// A scan still enumerating when the move runs can deliver a set after its files moved, so
    /// these identities are dropped from later scan batches instead of reappearing in the grid.
    private var movedRejectIdentities: Set<PhotoIdentity> = []
    private var movedPhotoRecords: [PhotoIdentity: GridPhoto] = [:]

    /// The watch that reports the open folder's location going away (PRD P0-02, G1 folder access).
    ///
    /// G1 uses presenters plus a 500 ms foreground poll; the watch reports one loss and stops, and
    /// ``endOpenFolder()`` removes it so nothing arrives after the folder closes.
    private var locationMonitor: FolderLocationMonitor?

    /// Which open a scan belongs to, so a replaced scan publishes nothing.
    private var scanGeneration = 0

    /// Entry snapshots use only a finished scan's confirmed marks (handoff Entry).
    private var completedScanStatus: FolderScanStatus?
    private var lastViewedPhoto: PhotoIdentity?
    private var entryPreviewTask: Task<Void, Never>?
    private var progressPersistence: Task<Void, Never>?
    private var progressDebounceTask: Task<Void, Never>?
    private var entryProgress: FolderProgress?
    private var openingProgress: FolderProgress?
    private var confirmedProgressChanges: [PhotoIdentity: FolderProgress.ConfirmedChange] = [:]

    /// The last queued open transition, so two opens can never install out of order.
    private var openTransition: Task<Void, Never>?

    /// Creates the library over a task that prepares its app-private stores.
    ///
    /// The metadata reader, caches and rejects folder name are injectable so a test can isolate
    /// storage and keep work small; production passes what ``FolderLibraryLaunch`` builds.
    init(
        stores: Task<Stores, any Error>,
        caches: Task<Caches?, Never>? = nil,
        metadata: MetadataReader = MetadataReader(),
        rejectsFolderName: @escaping @MainActor () -> RejectsFolderName = {
            .defaultFolderName
        },
        similarGroupsEnabled: @escaping @MainActor () -> Bool = { true }
    ) {
        self.stores = stores
        self.caches = caches ?? Task.detached(priority: .userInitiated) { await Self.makeCaches() }
        self.metadata = metadata
        self.rejectsFolderName = rejectsFolderName
        self.similarGroupsEnabled = similarGroupsEnabled
        let (stream, continuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        updates = stream
        updatesContinuation = continuation

        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        memoryPressureSource = pressure
        pressure.setEventHandler { [weak self, weak pressure] in
            guard let event = pressure?.data else { return }
            Task { @MainActor [weak self] in
                await self?.handleMemoryPressure(event)
            }
        }
        pressure.resume()
        memoryWarningTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification)
            {
                guard !Task.isCancelled else { return }
                await self?.handleMemoryPressure(.warning)
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

    /// The open this library installed last, which changes on every install and close
    /// (PRD P0-02).
    var openGeneration: Int { scanGeneration }

    /// The scanned set behind one photo, for writes and U3's thumbnail lookup (PRD P0-08).
    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? { store.scannedSet(for: photo) }

    /// Waits until C4 has finished every admitted write (PRD Failure and recovery).
    ///
    /// Moving files and releasing folder access wait for admitted writes.
    func drainWrites() async {
        guard case .success(let stores) = await resolvedStores() else { return }
        await stores.writes.drain()
    }

    func discardPendingChanges() async {
        guard case .success(let stores) = await resolvedStores() else { return }
        await stores.writes.discardChanges(in: folder)
    }

    /// Checks the open folder's location now, for a scene that came back to the foreground
    /// (PRD P0-02, G1 folder access). Nothing is watched while no folder is open.
    func checkFolderLocationNow() async {
        await locationMonitor?.checkNow()
    }

    /// Closes the open folder and releases its scope (PRD P0-08, PRD P0-02).
    ///
    /// The next open reads the files again. Closing drops this folder's photos and groups.
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
        publishedGroups = []
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
    /// reports one result in the caller's order. A
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
        for (index, item) in items.enumerated() {
            order[item.photo] = index
            itemsByIdentity[item.photo] = item
            guard let set = scanned.scannedSet(for: item.photo) else {
                let status = Self.refused(
                    item.change, for: item.photo, reason: .locationUnavailable,
                    message: "The open folder no longer holds this photo.")
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
        var outcomes = refused
        for (change, sets) in byChange {
            let admitted: MarkBatchResult? = try? await session.withAdmittedWork {
                await stores.writes.apply(change, to: sets)
            }
            guard let result = admitted else {
                for set in sets {
                    guard let item = itemsByIdentity[set.photoSet.id] else { continue }
                    let status = Self.refused(
                        change, for: item.photo, reason: .locationUnavailable,
                        message: "The folder closed before the batch could be written.")
                    outcomes.append(status)
                }
                continue
            }
            outcomes.append(contentsOf: result.outcomes)
        }
        outcomes.sort { (order[$0.identity] ?? .max) < (order[$1.identity] ?? .max) }
        // Fold confirmations before returning; the status observer may still be catching up.
        for status in outcomes { record(status) }
        return MarkBatchResult(id: MarkBatchID(), change: change, outcomes: outcomes)
    }

    /// A failed write leaves no desired state behind: read the files under this folder's scope.
    func rereadMarks(for photos: [PhotoIdentity]) async throws {
        guard let session = openSession,
            case .success(let stores) = await resolvedStores()
        else { return }
        let sets = photos.compactMap { store.scannedSet(for: $0) }
        let codec = codec
        let marks = try await session.withAdmittedWork {
            let stored = try await stores.writes.storedMarks(for: session.folder.id)
            return try await Task.detached {
                try Self.readMarks(for: sets, storedMarks: stored, codec: codec)
            }.value
        }
        for (photo, marks) in marks { store.setMarks(marks, for: photo) }
        publish(.reads(times: [:], marks: marks))
    }

    // MARK: - Move rejects

    /// Plans Move rejects for the open folder's rejected photos (PRD P0-10).
    ///
    /// C6's planner reads existence only, so the sheet can show its counts before the user
    /// commits. The request is built from the marks the folder holds now and from the settings
    /// the caller read at move time (PRD Move rejects, C12); a disabled setting or a read-only
    /// volume refuses the whole request before any file is touched.
    func planRejectMove(
        configuration: RejectMoveConfiguration, rejected: [PhotoIdentity]
    ) async throws -> RejectMovePlan {
        guard let mover = rejectMover, let session = openSession else {
            throw FolderSessionError.ended
        }
        let sets = rejected.compactMap { store.scannedSet(for: $0) }
        return try await mover.plan(
            for: RejectMoveRequest(
                rootURL: session.rootURL, sets: sets, configuration: configuration))
    }

    /// Runs a confirmed plan under the folder's session and drops the moved photos (PRD P0-10).
    ///
    /// The whole move is admitted work, so ending the folder waits for it before releasing the
    /// scope (G1 folder access). Moved sets leave the folder's photos and grouping runs again over
    /// the remaining ones, the same way it does after a scan finishes; failed and skipped sets
    /// stay in place, still rejected.
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
        for photo in store.photos where moved.contains(photo.id) {
            movedPhotoRecords[photo.id] = photo
        }
        store.remove(moved)
        publish(.photos([]))
        await startGrouping()
        return result
    }

    func undoRejectMove(
        _ entry: RejectMoveUndoEntry, currentMarks: [PhotoIdentity: PhotoMarks],
        restoring edits: [DesiredMarkEdit]
    ) async throws -> RejectMoveUndoResult {
        guard let mover = rejectMover, let session = openSession else {
            throw FolderSessionError.ended
        }
        let result = try await session.withAdmittedWork {
            try await mover.undo(entry, currentMarks: { currentMarks[$0] })
        }
        for restored in result.restored where !restored.keptInConfirmation {
            store.insert([.photo(restored.set)])
            if let photo = movedPhotoRecords.removeValue(forKey: restored.identity) {
                store.setTime(photo.time, for: restored.identity)
                store.setMarks(photo.marks, for: restored.identity)
            }
            movedRejectIdentities.remove(restored.identity)
        }
        // The files are already back, so a failed reread must not turn the Undo into a failure.
        try? await rereadMarks(for: result.restored.map(\.identity))
        publish(.photos([]))
        await startGrouping()
        return result
    }

    /// The progress steps of the next or running Move rejects (PRD P0-10).
    func rejectMoveProgress() async -> AsyncStream<RejectMoveProgress> {
        guard let mover = rejectMover else { return AsyncStream { $0.finish() } }
        return await mover.progressUpdates()
    }

    // MARK: - Batch rename

    func planBatchRename(
        order: [PhotoIdentity], template: RenameTemplate, destination: RenameDestination,
        rejectsFolderName: RejectsFolderName
    ) async throws -> BatchRenamePlan {
        guard let session = openSession,
            case .success(let stores) = await resolvedStores(), let renamer = stores.renamer
        else { throw RenameFlowError.unavailable }
        let sets = try order.map { identity in
            guard let set = store.scannedSet(for: identity) else {
                throw RenameFlowError.photoMissing
            }
            return set
        }
        return try await session.withAdmittedWork {
            var items: [RenameItem] = []
            for set in sets {
                try Task.checkCancellation()
                let wallTime =
                    template.includesCaptureDate
                    ? ImageInformationReader().read(url: set.photoSet.primary.url)?
                        .captureWallTime
                    : nil
                items.append(RenameItem(set: set, captureWallTime: wallTime))
            }
            try Task.checkCancellation()
            return await renamer.plan(
                for: BatchRenameRequest(
                    rootURL: session.rootURL, items: items, template: template,
                    destination: destination, rejectsFolderName: rejectsFolderName))
        }
    }

    func runBatchRename(
        _ plan: BatchRenamePlan,
        progress: @escaping @MainActor @Sendable (BatchRenameProgress) -> Void
    ) async throws -> BatchRenameResult {
        guard let session = openSession,
            case .success(let stores) = await resolvedStores(), let renamer = stores.renamer,
            plan.request.rootURL == session.rootURL
        else { throw RenameFlowError.unavailable }
        return try await session.withAdmittedWork {
            let updates = await renamer.progressUpdates()
            let observer = Task { @MainActor in
                for await update in updates {
                    progress(update)
                    if case .finished = update { return }
                }
            }
            do {
                let result = try await renamer.rename(plan)
                await observer.value
                return result
            } catch {
                observer.cancel()
                throw error
            }
        }
    }

    func rescanAfterRename() async throws {
        await reloadRecents()
        guard let recent = recents.first(where: { $0.identity == folder }),
            await reopen(recent) == nil
        else { throw RenameFlowError.rescanFailed }
        await scanTask?.value
        guard completedScanStatus == .complete else { throw RenameFlowError.rescanFailed }
    }

    // MARK: - Entry

    /// Remembers navigation immediately; preview work never holds a departure (handoff Entry).
    func setEntryResumePhoto(_ photo: PhotoIdentity) {
        guard photo.folderID == folder else { return }
        lastViewedPhoto = photo
        prepareEntryPreviews()
    }

    /// Persists progress without reading the folder; incomplete scans keep the prior counts.
    func recordEntryProgress(lastViewed: PhotoIdentity?) async {
        if let lastViewed, lastViewed.folderID == folder { lastViewedPhoto = lastViewed }
        guard folder != Self.noFolder, openSession != nil else { return }
        progressDebounceTask?.cancel()
        progressDebounceTask = nil
        persistEntryProgress()
        await progressPersistence?.value
        await reloadRecents()
    }

    /// Flushes the resume preview immediately; no debounce can drop a quick swipe then Back.
    func flushEntryState(lastViewed: PhotoIdentity?) async {
        let generation = scanGeneration
        entryPreviewTask?.cancel()
        entryPreviewTask = nil
        await recordEntryProgress(lastViewed: lastViewed)
        guard generation == scanGeneration else { return }
        await cacheEntryPreviews(generation: generation, immediate: true)
    }

    /// Chains snapshots in capture order so an older write cannot overwrite the close snapshot.
    private func persistEntryProgress() {
        let photos = store.photos
        let identity = folder
        let complete = completedScanStatus == .complete
        let progress = FolderProgress.snapshot(
            confirmedMarks: complete ? photos.map(\.marks) : [], scanIsComplete: complete,
            previous: openingProgress, lastViewedPhoto: lastViewedPhoto ?? photos.first?.id,
            previewPhotos: Array(photos.prefix(3).map(\.id)),
            confirmedChanges: confirmedProgressChanges)
        entryProgress = progress
        let previous = progressPersistence
        progressPersistence = Task { [stores] in
            await previous?.value
            guard let access = try? await stores.value.access else { return }
            try? await access.recordProgress(progress, for: identity)
        }
    }

    /// Coalesces a batch into one recount and Recents write after marking settles (PRD P0-08).
    private func scheduleEntryProgress() {
        progressDebounceTask?.cancel()
        let generation = scanGeneration
        progressDebounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, generation == self.scanGeneration else { return }
            self.progressDebounceTask = nil
            await self.recordEntryProgress(lastViewed: self.lastViewedPhoto)
        }
    }

    /// Prepares at most four previews after navigation settles, under the pipeline's scope.
    private func prepareEntryPreviews() {
        entryPreviewTask?.cancel()
        let generation = scanGeneration
        entryPreviewTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, generation == self.scanGeneration else { return }
            await self.cacheEntryPreviews(generation: generation, immediate: false)
        }
    }

    private func cacheEntryPreviews(generation: Int, immediate: Bool) async {
        guard generation == scanGeneration, let session = openSession,
            let source = thumbnailSource
        else { return }
        let identity = folder
        let previews =
            completedScanStatus == .complete
            ? Array(store.photos.prefix(3).map(\.id))
            : entryProgress?.previewPhotos ?? Array(store.photos.prefix(3).map(\.id))
        var seen: Set<PhotoIdentity> = []
        let identities = ([lastViewedPhoto].compactMap { $0 } + previews).filter {
            seen.insert($0).inserted
        }
        for photo in identities {
            guard !Task.isCancelled, generation == scanGeneration else { return }
            guard let url = store.scannedSet(for: photo)?.photoSet.primary.url,
                let revision = await Self.entryRevision(for: url, session: session)
            else { continue }
            if await EntryThumbnailStore.shared.contains(photo, revision: revision) { continue }
            let priority: GridThumbnailPriority =
                immediate && photo == lastViewedPhoto ? .visible : .prefetch
            if case .image(let image) = await source.thumbnail(for: photo, priority: priority),
                !Task.isCancelled, generation == scanGeneration,
                await Self.entryRevision(for: url, session: session) == revision
            {
                await EntryThumbnailStore.shared.store(image, for: photo, revision: revision)
            }
        }
        guard !Task.isCancelled, generation == scanGeneration else { return }
        await EntryThumbnailStore.shared.retain(identities, in: identity)
    }

    private nonisolated static func entryRevision(for url: URL, session: FolderAccessSession)
        async -> EntryThumbnailStore.SourceRevision?
    {
        guard
            let revision = try? await session.withAdmittedWork({
                try await Task.detached { try ThumbnailRevision.read(from: url) }.value
            })
        else { return nil }
        return EntryThumbnailStore.SourceRevision(sourceName: url.lastPathComponent, file: revision)
    }

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
        completedScanStatus = nil
        entryProgress =
            recents.first(where: { $0.id == opened.recent.id })?.progress
            ?? opened.recent.progress
        lastViewedPhoto = entryProgress?.lastViewedPhoto
        openingProgress = entryProgress
        confirmedProgressChanges = [:]
        guard case .success(let stores) = await resolvedStores() else {
            // Without the app-private stores the folder can be neither scanned nor written, so
            // its grant is released instead of being held by a folder nothing can use.
            await opened.session.end()
            return
        }
        let session = opened.session
        scanGeneration += 1
        let generation = scanGeneration
        folder = session.folder.id
        openSession = session
        store = FolderPhotos()

        movedRejectIdentities = []
        movedPhotoRecords = [:]
        rejectMover = RejectMover(markQueue: stores.writes)
        publishedGroups = []
        publish(.scanStarted)
        publish(.photos([]))
        // PRD How marks reach disk, rule 1: Reject and standalone marks are read when the folder
        // opens. A damaged store is reported by U7's save state; the scan still shows the photos.
        let storedMarks = (try? await stores.writes.storedMarks(for: session.folder.id)) ?? [:]
        isPausedForMemoryPressure = false
        let configuration = ScanConfiguration(
            rejectsFolderName: rejectsFolderName().rawValue)
        let caches = await resolvedCaches()
        thumbnailSource = makeThumbnailSource(for: session, caches: caches)
        detailSource = makeDetailSource(
            for: session, thumbnails: caches?.thumbnails, sharpness: caches?.sharpness)
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
        isPausedForMemoryPressure = false
        entryPreviewTask?.cancel()
        entryPreviewTask = nil
        progressDebounceTask?.cancel()
        progressDebounceTask = nil
        scanGeneration += 1
        openScan?.cancel()
        openScan = nil
        scanTask?.cancel()
        scanTask = nil
        if let monitor = locationMonitor {
            locationMonitor = nil
            await monitor.stop()
        }
        await cacheEntryPreviews(generation: scanGeneration, immediate: true)
        thumbnailSource = nil
        rejectMover = nil
        movedRejectIdentities = []
        movedPhotoRecords = [:]
        publishedGroups = []
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
        if let analysis = detailSource as? DetailRegionSharpnessSource {
            // Analysis shares this folder's pipeline and admitted session. Close and drain it
            // before either the pipeline or the security scope can end.
            await analysis.closeRegionAnalysis()
        }
        sharpnessScheduler = nil
        sharpnessResults = nil
        detailSource = nil
        if let pipeline = detailPipeline {
            detailPipeline = nil
            // I2's close cancels queued work and waits for a render in flight, so the scope is
            // never released under one (G1 preview and folder-access rows).
            await pipeline.close()
        }
        if case .success(let stores) = await resolvedStores() {
            await stores.writes.drain()
            await recordEntryProgress(lastViewed: lastViewedPhoto)
            completedScanStatus = nil
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
                        var marks: [PhotoIdentity: PhotoMarks] = [:]
                        for set in sets {
                            if let read = try? Self.readMarks(
                                for: [set], storedMarks: storedMarks, codec: codec,
                                trustAbsentSidecar: true)
                            {
                                marks.merge(read) { _, new in new }
                            }
                        }
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
        let setsByURL = Dictionary(
            sets.map { ($0.photoSet.primary.url, $0) },
            uniquingKeysWith: { first, _ in first })
        var times: [PhotoIdentity: PhotoTimeState] = [:]
        for read in reads {
            guard let set = setsByURL[read.url] else {
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
        if marks.count < sets.count { publish(.markReadFailed) }
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
        completedScanStatus = recorded.status
        prepareEntryPreviews()
        await recordEntryProgress(lastViewed: lastViewedPhoto)
        await reloadRecents()
        await startGrouping()
        // The folder can be replaced while grouping runs above, so the report is re-checked
        // against the generation it belongs to before it reaches the model.
        guard generation == scanGeneration else { return }
        publish(.scanFinished(recorded))
    }

    /// Reports a scan that could not run as partial, without recording a count (PRD P0-01).
    private func failedScan(generation: Int) async {
        guard generation == scanGeneration else { return }
        await startGrouping()
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
    nonisolated static func readMarks(
        for sets: [ScannedPhotoSet],
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        codec: XMPCodec,
        trustAbsentSidecar: Bool = false
    ) throws -> [PhotoIdentity: PhotoMarks] {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for set in sets {
            var packet: XMPMarks?
            let sidecar: URL?
            switch set.sidecar {
            case .resolved(let url): sidecar = url
            case .absent:
                if trustAbsentSidecar {
                    sidecar = nil
                } else {
                    switch set.photoSet.markPersistence.rating {
                    case .xmpSidecar(let url): sidecar = url
                    case .cloveStorage: sidecar = nil
                    }
                }
            case .ambiguous: sidecar = nil
            }
            if set.photoSet.primary.format == .raw, let sidecar {
                do {
                    let data = try Data(contentsOf: sidecar)
                    packet = try? codec.read(data)
                } catch CocoaError.fileReadNoSuchFile {
                    // A missing sidecar has no marks; other read failures must not erase them.
                }
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
            },
            analysisChanged: { [weak self] isRunning in
                guard let self, generation == self.scanGeneration else { return }
                self.publish(.groupingActivity(isRunning))
            })
    }

    /// Runs grouping's time stage for the open folder (PRD P0-11).
    ///
    /// The result arrives through grouping's own publication, which re-checks the open it
    /// belongs to before anything reaches the model.
    private func startGrouping() async {
        guard let grouping else { return }
        await grouping.begin(
            photos: store.groupingPhotos, revision: groupingRevision(),
            enabled: similarGroupsEnabled())
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
    /// A publication only lands when it changed something, so refinement and Run again do not
    /// repaint an unchanged grid.
    private func publishGroups(_ groups: [BrowsingGroup]) {
        guard groups != publishedGroups else { return }
        publishedGroups = groups
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

    /// Info reads hold the same security scope as previews and run off the main actor (G1).
    /// A result from a replaced open is discarded even if its folder identity is unchanged.
    func information(for photo: PhotoIdentity) async -> PhotoInformation? {
        guard let session = openSession, photo.folderID == folder,
            let set = store.scannedSet(for: photo)?.photoSet
        else { return nil }
        let generation = scanGeneration
        let result = try? await session.withAdmittedWork {
            ImageInformationReader().read(url: set.primary.url)
        }
        guard generation == scanGeneration, !Task.isCancelled else { return nil }
        return PhotoInformation(
            image: result, relativeFolder: photo.relativeFolderPath,
            companions: [set.jpegCompanion, set.heifCompanion].compactMap {
                $0?.url.lastPathComponent
            },
            usesSidecar: set.primary.format == .raw)
    }

    // MARK: - Detail pixels

    /// Builds the open folder's detail source over I2's pipeline bound to its session
    /// (PRD P0-04, G1 "Preview, detail (I2)").
    ///
    /// G1 keeps detail images in memory (64 MiB compressed plus one native render), so the pipeline needs
    /// no directory, unlike the grid's disk cache. Its reads are admitted through the folder's
    /// C11 session, so ending the folder waits for a read before releasing the scope.
    private func makeDetailSource(
        for session: FolderAccessSession,
        thumbnails: ThumbnailCache?,
        sharpness: RegionSharpnessCache?
    ) -> any DetailImageSource {
        let pipeline = DetailPipeline()
        detailPipeline = pipeline
        let sharpnessResults = RegionSharpnessResultStore(capacity: 512, disk: sharpness)
        let scheduler = RegionSharpnessScheduler(
            analyzer: RegionSharpnessAnalyzer(
                reader: DetailRegionSharpnessReading(details: pipeline)),
            results: sharpnessResults)
        self.sharpnessResults = sharpnessResults
        self.sharpnessScheduler = scheduler
        let folder = session.folder.id
        return PipelineDetailImages(
            pipeline: pipeline, thumbnails: thumbnails,
            set: { [weak self] photo in self?.store.scannedSet(for: photo)?.photoSet },
            admitted: DetailWorkAdmission(
                image: { [weak self] work in
                    guard let self else { return .unavailable(.noUsablePreview) }
                    return await self.admittedDetail(work, session: session, folder: folder)
                },
                prefetch: { [weak self] work in
                    guard let self else { return }
                    await self.admittedDetailPrefetch(work, session: session, folder: folder)
                },
                sharpness: { [weak self] work in
                    guard let self else { return nil }
                    return await self.admittedDetailSharpness(
                        work, session: session, folder: folder)
                }),
            regionScheduler: scheduler,
            sharpnessCache: sharpness,
            onUserActivity: { [weak self] in await self?.resumeAfterMemoryPressure() })
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

    /// Runs the scheduler's shared analysis under the same folder admission as interactive reads.
    private func admittedDetailSharpness(
        _ work: @Sendable () async -> RegionSharpnessAnalysis?,
        session: FolderAccessSession,
        folder: FolderIdentity
    ) async -> RegionSharpnessAnalysis? {
        guard self.folder == folder else { return nil }
        return try? await session.withAdmittedWork { await work() }
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

    /// Builds the library's shared caches over the app's Caches directory, off the main actor.
    ///
    /// Creating any cache makes its directory and indexes what it already holds, so this runs once
    /// per library in a detached task; the first open waits for it if still indexing, and later
    /// folder opens reuse the same instances with warm memory tiers.
    nonisolated static func makeCaches(in rootDirectory: URL? = nil) async -> Caches? {
        await Task.detached(priority: .userInitiated) {
            do {
                let caches: URL
                if let rootDirectory {
                    caches = rootDirectory
                } else {
                    caches = try FileManager.default.url(
                        for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil,
                        create: true)
                }
                let thumbnails = try ThumbnailCache(
                    directory: caches.appendingPathComponent(
                        "Clove/GridThumbnails", isDirectory: true))
                let features = try ImageFeatureCache(
                    directory: caches.appendingPathComponent(
                        "Clove/ImageFeatures", isDirectory: true))
                let sharpness = try? RegionSharpnessCache(
                    directory: caches.appendingPathComponent(
                        "Clove/RegionSharpness", isDirectory: true))
                return Caches(thumbnails: thumbnails, features: features, sharpness: sharpness)
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
        Task { [stores] in
            guard let access = try? await stores.value.access else { return }
            try? await access.recordLocationLoss(for: folder)
        }
    }

    // MARK: - Writes

    /// Records one change's state from C4's ordered stream (PRD P0-08).
    ///
    /// The ordered caller returns completed writes, so their changes apply in the same order.
    private func record(_ status: MarkChangeStatus) {
        guard status.identity.folderID == folder else { return }
        if status.state.failure?.reason == .locationUnavailable {
            locationLost(
                FolderLocationLoss(reason: .externalVolumeDisconnected, date: Date()),
                folder: folder, generation: scanGeneration)
            return
        }
        if status.state.isConfirmed {
            applyConfirmedProgressChange(status)
            if let photo = store.photo(for: status.identity) {
                publish(.reads(times: [:], marks: [status.identity: photo.marks]))
                scheduleEntryProgress()
            }
        }
    }

    /// Tracks net changes against the session's first confirmed marks, independent of debounce flushes.
    private func applyConfirmedProgressChange(_ status: MarkChangeStatus) {
        guard let before = store.photo(for: status.identity)?.marks else { return }
        store.apply(status.requested, to: status.identity)
        guard let after = store.photo(for: status.identity)?.marks else { return }
        confirmedProgressChanges[status.identity] =
            confirmedProgressChanges[status.identity]?
            .updating(to: after) ?? FolderProgress.ConfirmedChange(before: before, after: after)
    }

    // MARK: - Grouping

    /// Runs similar groups again for the open folder without the group cache (PRD P0-11).
    ///
    /// P0-11 keeps Run again available beside the published groups. The current photos are the
    /// inputs, the cache's finished result is not reused, and the refinement follows in the
    /// background as it does on open; the group keys stay put through C9's ancestry, so the grid
    /// does not move the photo the user is looking at.
    func runGroupingAgain() async {
        await resumeAfterMemoryPressure()
        await grouping?.runAgain(photos: store.groupingPhotos)
    }

    /// Applies C12's similar-groups setting to the open folder (PRD P0-11).
    ///
    /// Off publishes no groups and stops feature work; on publishes the cached or time-only
    /// result at once and refines again. The settings store keeps and persists the value; this
    /// only applies it to the folder that is open, and ``similarGroupsEnabled`` reads the store
    /// again when the next folder opens. A change during the scan changes nothing: grouping
    /// reads the store when it starts after the scan finishes.
    func setSimilarGroupsEnabled(_ enabled: Bool) async {
        if enabled {
            await resumeAfterMemoryPressure()
        }
        await grouping?.setEnabled(enabled, photos: store.groupingPhotos)
    }

    // MARK: - Memory pressure

    /// Releases memory tiers across all active caches/pipelines on `.warning`/`.critical`, and
    /// pauses background grouping/sharpness workers on `.critical`.
    func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) async {
        if event.contains(.warning) || event.contains(.critical) {
            if let caches = await resolvedCaches() {
                caches.thumbnails.releaseMemory()
                caches.features.releaseMemory()
            }
            sharpnessResults?.releaseMemory()
            await detailPipeline?.releaseCachedImages()
        }
        if event.contains(.critical) {
            isPausedForMemoryPressure = true
            await grouping?.pauseAnalysis()
            await sharpnessScheduler?.pause()
        } else if event.contains(.normal), isPausedForMemoryPressure {
            await resumeAfterMemoryPressure()
        }
    }

    /// Resumes background grouping and sharpness work that `.critical` pressure paused.
    func resumeAfterMemoryPressure() async {
        guard isPausedForMemoryPressure else { return }
        isPausedForMemoryPressure = false
        await grouping?.resumeAnalysis()
        await sharpnessScheduler?.resume()
    }

    // MARK: - Publishing

    /// Sends one update to the model's stream (PRD P0-03, P0-08).
    private func publish(_ update: FolderLibraryUpdate) {
        updatesContinuation.yield(update)
    }

    /// The shared caches indexed for the library's lifetime.
    func resolvedCaches() async -> Caches? {
        await caches.value
    }

    var activeGrouping: FolderGrouping? { grouping }
    var activeDetailPipeline: DetailPipeline? { detailPipeline }
    var activeSharpnessResults: RegionSharpnessResultStore? { sharpnessResults }
    var activeSharpnessScheduler: RegionSharpnessScheduler? { sharpnessScheduler }

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

    deinit {
        memoryPressureSource.cancel()
        memoryWarningTask?.cancel()
        // A dropped library must not leave its scan running or its consumer attached; C11's
        // session releases the scope itself when it is deallocated.
        openScan?.cancel()
        scanTask?.cancel()
        if let grouping {
            // Closing drains a preview read in flight, which cannot happen here, so it runs in
            // its own task; the grouping keeps the session alive until that read ends, and the
            // session's own deinit releases the scope if the library outlives it.
            Task { await grouping.close() }
        }
        updatesContinuation.finish()
    }
}
