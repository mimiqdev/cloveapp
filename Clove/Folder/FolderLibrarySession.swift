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

        /// Prepares the stores below Application Support (PRD P0-02, P0-08).
        ///
        /// Resolving those paths touches the file system, so ``FolderLibraryLaunch`` runs this off
        /// the main actor instead of during the scene's first body evaluation.
        static func applicationSupport() throws -> Stores {
            let store = try RecentFolderStore.applicationSupport()
            let marksDirectory = try CloveMarkStore.applicationSupportDirectory()
            return Stores(
                access: FolderAccess(store: store),
                writes: MarkWriteQueue(storeDirectory: marksDirectory))
        }
    }

    /// The key a library answers with while no folder is open (PRD P0-02, P0-14).
    ///
    /// It is not a bookmark key, so a saved scene or a stored mark can never mistake it for a
    /// folder, and entry only shows a folder after a pick or a reopen returned one.
    static let noFolder = FolderIdentity(rawValue: "clove.folder.none")

    /// The stores, prepared off the main actor so the first scene never waits on disk.
    private let stores: Task<Stores, any Error>
    private let metadata: MetadataReader
    private let settings: AppSettings
    private let codec = XMPCodec()

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

    /// The session holding the open folder's scope, ended when another folder opens.
    private var openSession: FolderAccessSession?

    /// The running scan, cancelled when another folder opens.
    private var scanTask: Task<Void, Never>?

    /// The walk behind ``scanTask``, so ending the folder stops its enumeration.
    private var openScan: FolderScan?

    /// The task keeping this library's save states in step with C4 (PRD P0-08).
    private var writeStatusTask: Task<Void, Never>?

    /// Which open a scan belongs to, so a replaced scan publishes nothing.
    private var scanGeneration = 0

    /// The last queued open transition, so two opens can never install out of order.
    private var openTransition: Task<Void, Never>?

    /// Creates the library over a task that prepares its app-private stores.
    ///
    /// The metadata reader and the settings are injectable so a test can keep the work small;
    /// production passes what ``FolderLibraryLaunch`` builds.
    init(
        stores: Task<Stores, any Error>,
        metadata: MetadataReader = MetadataReader(),
        settings: AppSettings = AppSettings()
    ) {
        self.stores = stores
        self.metadata = metadata
        self.settings = settings
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

    /// Grouping's groups for the folder. The grouping follow-up publishes them through
    /// ``FolderLibraryUpdate/groups(_:)``; U2 runs no grouping (PRD P0-11).
    var groups: [BrowsingGroup] { [] }

    /// The latest change to one photo with its save state (PRD P0-08).
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { changes.latest(for: photo) }

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
        scanGeneration += 1
        let generation = scanGeneration
        folder = session.folder.id
        openSession = session
        store = FolderPhotos()
        changes = PhotoChangeStates()
        publish(.photos([]))
        // PRD How marks reach disk, rule 1: Reject and standalone marks are read when the folder
        // opens. A damaged store is reported by U7's save state; the scan still shows the photos.
        let storedMarks = (try? await stores.writes.storedMarks(for: session.folder.id)) ?? [:]
        let configuration = ScanConfiguration(
            rejectsFolderName: settings.rejectsFolderName.rawValue)
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
        scanGeneration += 1
        openScan?.cancel()
        openScan = nil
        scanTask?.cancel()
        scanTask = nil
        if case .success(let stores) = await resolvedStores() {
            await stores.writes.drain()
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
            failedScan(generation: generation)
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
        let added = store.insert(items, storedMarks: storedMarks)
        guard !added.isEmpty else { return [] }
        publish(.photos(added))
        return added.compactMap { store.scannedSet(for: $0.id) }
    }

    /// Applies one batch's metadata and mark reads (PRD P0-03, P0-07).
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
        publish(.scanFinished(recorded))
    }

    /// Reports a scan that could not run as partial, without recording a count (PRD P0-01).
    private func failedScan(generation: Int) {
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

    /// The reason a saved folder that no longer has a record gives (PRD P0-02).
    private static let missingLocation = FolderAccessFailure.locationUnavailable(
        FolderErrorChain(CocoaError(.fileNoSuchFile)))

    deinit {
        // A dropped library must not leave its scan running or its consumer attached; C11's
        // session releases the scope itself when it is deallocated.
        openScan?.cancel()
        scanTask?.cancel()
        writeStatusTask?.cancel()
        updatesContinuation.finish()
    }
}
