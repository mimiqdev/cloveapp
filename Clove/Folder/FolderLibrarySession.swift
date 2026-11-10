import CloveCore
import CloveImaging
import Foundation

/// The real ``FolderLibrary``: one open folder behind C11's access, C2's scan, I4's times,
/// C8's values and C4's writes (PRD P0-01, P0-02, P0-08).
///
/// The library is main-actor isolated because the screens read it there, and every file operation
/// leaves that actor: C11 holds the security scope, the scan walks and reads metadata in its own
/// task, and the write queue writes off the main actor. What crosses back to the main actor is a
/// value: a batch of grid photos, a read time, a mark, a finished scan or a write state, which
/// the model applies through ``FolderLibrary/updates``.
///
/// Opening another folder ends the one before it, so the scan is cancelled and C11's session
/// drains before its scope is released (G1 folder access). A scan that a newer open replaced
/// publishes nothing, because every publication checks the generation it started in.
@MainActor
final class FolderLibrarySession: FolderLibrary {
    /// The key a library answers with while no folder is open (PRD P0-02, P0-14).
    ///
    /// It is not a bookmark key, so a saved scene or a stored mark can never mistake it for a
    /// folder, and entry only shows a folder after a pick or a reopen returned one.
    static let noFolder = FolderIdentity(rawValue: "clove.folder.none")

    private let access: FolderAccess
    private let writes: MarkWriteQueue
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

    /// The open folder's photos, with their scanned sets (PRD P0-01, P0-08).
    private var store = FolderPhotos()

    /// The latest save state per photo, kept in step with C4's stream (PRD P0-08).
    private var changes = PhotoChangeStates()

    /// The session holding the open folder's scope, ended when another folder opens.
    private var openSession: FolderAccessSession?

    /// The running scan, cancelled when another folder opens.
    private var scanTask: Task<Void, Never>?

    /// The task keeping this library's save states in step with C4 (PRD P0-08).
    private var writeStatusTask: Task<Void, Never>?

    /// Which open a scan belongs to, so a replaced scan publishes nothing.
    private var scanGeneration = 0

    /// Creates the library over C11's Recents and C4's queue.
    ///
    /// The metadata reader and the settings are injectable so a preview or a test can keep the
    /// work small; production passes the ones ``FolderLibraryLaunch`` builds.
    init(
        access: FolderAccess,
        writes: MarkWriteQueue,
        metadata: MetadataReader = MetadataReader(),
        settings: AppSettings = AppSettings()
    ) {
        self.access = access
        self.writes = writes
        self.metadata = metadata
        self.settings = settings
        let (stream, continuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        updates = stream
        updatesContinuation = continuation
        writeStatusTask = Task { [weak self] in await self?.consumeWriteStates() }
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

    /// Applies one change to the photo's set through C4 (PRD P0-08).
    ///
    /// A photo the folder no longer holds is refused instead of being written somewhere else.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus {
        guard let set = store.scannedSet(for: photo) else {
            return MarkChangeStatus(
                id: MarkChangeID(), identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .locationUnavailable,
                        message: "The open folder no longer holds this photo.")))
        }
        let status = await writes.apply(change, to: set)
        record(status)
        return status
    }

    // MARK: - Entry

    /// Re-reads C11's Recents list (PRD P0-02).
    func reloadRecents() async {
        recents = (try? await access.recents()) ?? []
    }

    /// Opens a folder chosen in the system picker and scans it (PRD P0-01).
    func pick(_ url: URL) async -> FolderAccessFailure? {
        switch await access.pick(url) {
        case .opened(let opened):
            await open(opened)
            return nil
        case .failed(let failure):
            return failure
        }
    }

    /// Reopens one remembered folder and scans it (PRD P0-02).
    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        switch await access.reopen(recent.id) {
        case .opened(let opened):
            await open(opened)
            return nil
        case .failed(let failure):
            return failure
        }
    }

    /// Reopens the folder a saved scene names, for launch restore (PRD P0-02, P0-14).
    ///
    /// Restore validation asks what the folder holds now, so this waits for the launch scan
    /// before answering: the first batch alone cannot say whether the saved photo, selection and
    /// group view survived. The scan still streams into the model while entry is on screen, so
    /// the grid already has its photos when the restored route appears.
    func openSavedFolder(_ folder: FolderIdentity) async -> FolderAvailability {
        await reloadRecents()
        guard let recent = recents.first(where: { $0.identity == folder }) else {
            // The record is gone, so the saved location cannot be reopened; P0-02 asks for the
            // folder again rather than opening nothing.
            return .unavailable(Self.missingLocation)
        }
        if let failure = await reopen(recent) { return .unavailable(failure) }
        await scanTask?.value
        // Another open while the scan ran replaced the saved folder, so its contents no longer
        // answer for the saved scene.
        guard self.folder == folder else { return .unavailable(Self.missingLocation) }
        return .available(contents)
    }

    // MARK: - Opening

    /// Starts one opened folder: ends the previous one, then scans the new one (PRD P0-01).
    private func open(_ opened: OpenedFolder) async {
        await endOpenFolder()
        let session = opened.session
        let settings = settings
        scanGeneration += 1
        let generation = scanGeneration
        folder = session.folder.id
        openSession = session
        store = FolderPhotos()
        changes = PhotoChangeStates()
        publish(.photos([]))
        // PRD How marks reach disk, rule 1: Reject and standalone marks are read when the folder
        // opens. A damaged store is reported by U7's save state; the scan still shows the photos.
        let storedMarks = (try? await writes.storedMarks(for: session.folder.id)) ?? [:]
        let configuration = ScanConfiguration(
            rejectsFolderName: settings.rejectsFolderName.rawValue)
        scanTask = Task { [weak self] in
            await self?.scan(
                session: session, configuration: configuration, storedMarks: storedMarks,
                generation: generation)
        }
    }

    /// Ends the open folder: cancels its scan, drains writes and releases the scope.
    ///
    /// G1 folder access keeps the scope until the work that relies on it drains, so the queue is
    /// drained before the session ends. Ending waits for the scan's admitted work as well.
    private func endOpenFolder() async {
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        await writes.drain()
        guard let session = openSession else { return }
        openSession = nil
        await session.end()
    }

    // MARK: - Scan

    /// Walks the folder inside C11's admitted work and publishes what it finds.
    ///
    /// The whole walk, its metadata and sidecar reads run in the admitted closure, off the main
    /// actor, so ending the session waits for them before releasing the scope. Every publication
    /// checks its generation, so a scan a newer open replaced never lands in the new folder.
    private func scan(
        session: FolderAccessSession,
        configuration: ScanConfiguration,
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        generation: Int
    ) async {
        let rootURL = session.rootURL
        let folderID = session.folder.id
        let metadata = metadata
        let codec = codec
        do {
            try await session.withAdmittedWork { [weak self] in
                let scan = FolderScan(
                    folderURL: rootURL, folderID: folderID, configuration: configuration)
                for try await batch in scan {
                    try Task.checkCancellation()
                    guard let self else { return }
                    let sets = await self.admit(
                        batch.items, storedMarks: storedMarks, generation: generation)
                    guard !sets.isEmpty else { continue }
                    // I4 reads the primary file of each set off the main actor; a RAW set's
                    // capture time comes from the RAW (G1 decision 1, I4).
                    let reads = await metadata.read(urls: sets.map { $0.photoSet.primary.url })
                    let marks = Self.readMarks(for: sets, storedMarks: storedMarks, codec: codec)
                    await self.applyReads(
                        reads, marks: marks, sets: sets, generation: generation)
                }
                let summary = try await scan.summary()
                await self?.finishScan(summary, session: session, generation: generation)
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
        generation: Int
    ) async {
        guard generation == scanGeneration else { return }
        let recorded = FolderScanSummary(
            photoCount: summary.logicalPhotoCount,
            status: summary.status == .complete ? .complete : .partial)
        try? await access.recordScan(recorded, for: session)
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

    /// Reads each set's sidecar through C3 and combines it with Clove's stored marks
    /// (PRD P0-05, P0-07; G1 decisions 5–6).
    ///
    /// A packet C3 refuses contributes nothing and is not repaired, so the photo keeps whatever
    /// Clove stores and U7 can report the refusal with its own copy. A set with no sidecar reads
    /// no packet, which is why a standalone JPEG or HIF keeps its Clove-stored rating.
    private nonisolated static func readMarks(
        for sets: [ScannedPhotoSet],
        storedMarks: [PhotoIdentity: CloveStoredMarks],
        codec: XMPCodec
    ) -> [PhotoIdentity: PhotoMarks] {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for set in sets {
            var packet: XMPMarks?
            if let url = set.sidecar.resolvedURL, let data = try? Data(contentsOf: url) {
                packet = try? codec.read(data)
            }
            marks[set.id] = PhotoMarks(stored: storedMarks[set.id], xmp: packet)
        }
        return marks
    }

    // MARK: - Writes

    /// Keeps this library's save states in step with C4's stream (PRD P0-08).
    private func consumeWriteStates() async {
        let states = await writes.stateUpdates()
        for await status in states {
            guard !Task.isCancelled else { return }
            record(status)
        }
    }

    /// Records one change's state and shows a confirmed change on the photo (PRD P0-08).
    private func record(_ status: MarkChangeStatus) {
        changes.insert(status)
        if status.state.isConfirmed {
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

    /// The reason a saved folder that no longer has a record gives (PRD P0-02).
    private static let missingLocation = FolderAccessFailure.locationUnavailable(
        FolderErrorChain(CocoaError(.fileNoSuchFile)))

    deinit {
        // A dropped library must not leave its scan running or its consumer attached; C11's
        // session releases the scope itself when it is deallocated.
        scanTask?.cancel()
        writeStatusTask?.cancel()
        updatesContinuation.finish()
    }
}
