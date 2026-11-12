import Foundation

/// Runs Move rejects: plans the sets, moves each one as a unit, and reports per-photo results.
///
/// G1 decision 5 and PRD P0-10 make the move the durable Reject result: after the user
/// confirms, every rejected photo set is renamed into `<root>/<rejects folder>/<relative
/// folder>` with its JPEG/HIF companions and its `.xmp`, and only a confirmed move counts.
/// The actor owns the whole run so its rules hold in one place:
///
/// - **Before moving.** A disabled setting or a read-only location refuses the whole request
///   (PRD Move rejects, Failure and recovery). Admitted writes drain first.
/// - **One unit per set.** Every file is renamed with an exclusive rename that refuses an
///   existing destination (PRD P0-10), and the set is confirmed file by file: source gone,
///   destination present with the source's size. If a later file fails, the earlier files move
///   back; if the move back also fails, the set is reported as split with every file's actual
///   location, so no file is ever lost track of.
/// - **After a confirmed move.** C4's stored Reject is removed; a removal that fails leaves the
///   set moved and reports the stale record as a diagnostic (PRD P0-08).
/// - **Results.** Moved sets leave the grid and failed sets stay in place.
///
/// The actor holds the runs Undo can restore and the progress streams. File work uses the
/// injected ``PhotoFileSystem``, which has no delete or copy operation at all.
public actor RejectMover {
    /// The injectable file operations every move goes through (PRD P0-10).
    ///
    /// Not `private` because the undo lane in `RejectMoveUndo.swift` adds its calls in an
    /// extension in another file; both directions use the same seam, so one injected failure
    /// covers the whole loop.
    let fileSystem: any PhotoFileSystem
    /// The confirmation-plan builder and the whole-request preconditions (PRD P0-10).
    private let planner: RejectMovePlanner
    /// C4's write queue: drain, the per-set mark-change check and the stored-Reject removal.
    ///
    /// Not `private` for the same reason as ``fileSystem``: undo stores Reject again through
    /// the queue, which stays the only writer of a stored mark (G1 decisions 2 and 6).
    let markQueue: MarkWriteQueue
    /// Progress streams handed to a UI or a test (PRD P0-10).
    private var observers: [UUID: AsyncStream<RejectMoveProgress>.Continuation] = [:]
    /// The completed runs ``undo(_:)`` can restore, by every batch ID they handed out.
    ///
    /// An undone run stays addressable so a second undo cannot move files twice.
    var undoableRuns: [RejectMoveBatchID: RejectMoveUndoRun] = [:]
    /// Undo progress streams handed to a UI or a test (PRD P0-10's Undo rule).
    var undoObservers: [UUID: AsyncStream<RejectMoveUndoProgress>.Continuation] = [:]

    /// Creates the mover over C4's queue and the production file system unless a test injects
    /// another.
    ///
    /// The queue is the only writer of a stored Reject, so the mover never touches app
    /// storage directly; tests inject a temporary store directory and a file-system double so
    /// nothing reaches real photos or the app's Application Support container.
    public init(
        markQueue: MarkWriteQueue,
        fileSystem: any PhotoFileSystem = FoundationPhotoFileSystem()
    ) {
        self.markQueue = markQueue
        self.fileSystem = fileSystem
        self.planner = RejectMovePlanner(fileSystem: fileSystem)
    }

    // MARK: - Planning

    /// Builds the confirmation plan without moving anything (PRD P0-10, U10).
    ///
    /// Throws when the settings or the location refuse the whole request; a set that cannot
    /// move is an entry with its reason, so the sheet can name the photos that will not go.
    public func plan(for request: RejectMoveRequest) throws(RejectMoveRefusal) -> RejectMovePlan {
        try planner.plan(for: request)
    }

    // MARK: - Moving

    /// Moves every ready set of a confirmed plan and reports one outcome per requested set.
    ///
    /// PRD P0-10 keeps the run deliberate: it starts only from a confirmed plan, waits for C4's
    /// admitted writes, and moves the sets as units. Failed sets stay in place.
    ///
    /// Throws only a whole-request refusal; every per-set problem is an outcome.
    public func move(_ preview: RejectMovePlan) async throws(RejectMoveRefusal) -> RejectMoveResult
    {
        try planner.preflight(rootURL: preview.rootURL, configuration: preview.configuration)
        // G1 decision 5: a mark write still in flight would target the old path, so the run
        // starts after C4 has nothing left to write (PRD P0-08, Failure and recovery).
        await markQueue.drain()
        let plan = try planner.plan(
            for: RejectMoveRequest(
                rootURL: preview.rootURL, sets: preview.sets, configuration: preview.configuration))
        let difference = RejectMovePlanDifference(preview: preview, actual: plan)

        let id = RejectMoveBatchID()
        var outcomes: [RejectMoveOutcome] = []
        outcomes.reserveCapacity(plan.entries.count)
        for entry in plan.entries {
            publish(.setStarted(entry.identity))
            let outcome = await perform(entry)
            outcomes.append(outcome)
            publish(.setFinished(outcome))
        }
        let result = RejectMoveResult(
            id: id, outcomes: outcomes, planDifference: difference.hasChanges ? difference : nil)
        rememberUndo(result, plan: plan)
        publish(.finished(result))
        return result
    }

    /// Every progress step, as a stream a UI can wrap into its own observation (PRD P0-10).
    ///
    /// PRD P0-10 asks for progress during a run. The stream yields each set as it starts and
    /// finishes, then the run's result, and finishes when the caller stops iterating; the mover
    /// keeps no reference to a finished stream.
    public func progressUpdates() -> AsyncStream<RejectMoveProgress> {
        let (stream, continuation) = AsyncStream<RejectMoveProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(64))
        let observerID = UUID()
        observers[observerID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return stream
    }

    // MARK: - One set

    /// Turns one plan entry into an outcome (PRD P0-10).
    private func perform(_ entry: RejectMovePlanEntry) async -> RejectMoveOutcome {
        switch entry {
        case .ready(let plan):
            return await move(plan)
        case .refused(let identity, let refusal):
            guard let failure = refusal.failure else {
                return skipped(identity, reason: .insideRejectsFolder)
            }
            return .failed(
                RejectMoveFailedSet(identity: identity, failure: failure, files: []))
        }
    }

    /// Moves through the shared exclusive move and per-set rollback implementation.
    private func move(_ plan: RejectMoveSetPlan) async -> RejectMoveOutcome {
        let files = plan.files.map { PhotoFileMove(source: $0.source, destination: $0.destination) }
        switch PhotoSetFileMover(fileSystem: fileSystem).move(files, to: plan.destinationFolder) {
        case .moved:
            return await confirmed(plan)
        case .failed(let error):
            return .failed(
                RejectMoveFailedSet(
                    identity: plan.identity, failure: RejectMoveFailure(classifying: error),
                    files: plan.files))
        case .split(let error, let rollbackFailures, let locations):
            let files = zip(plan.files, locations).map { file, location in
                let value: RejectMoveFileLocation.Location
                switch location.location {
                case .source: value = .source
                case .destination: value = .destination
                case .missing: value = .missing
                case .unknown: value = .unknown
                }
                return RejectMoveFileLocation(
                    role: file.role, source: file.source, destination: file.destination,
                    location: value)
            }
            return .split(
                RejectMoveSplitSet(
                    identity: plan.identity, failure: RejectMoveFailure(classifying: error),
                    rollbackFailures: rollbackFailures.map { RejectMoveFailure(classifying: $0) },
                    files: files))
        }
    }

    /// Drops a stored Reject after a confirmed move (PRD P0-08).
    ///
    /// A RAW set's Reject is in its sidecar and moves with it; a standalone JPEG/HIF keeps it in
    /// Clove storage, so that stored rating −1 is cleared only now. A removal that
    /// throws leaves the set counted as moved and the stale record as a diagnostic, because the
    /// files are already in the rejects folder and reporting the set as unmoved would be wrong.
    private func confirmed(_ plan: RejectMoveSetPlan) async -> RejectMoveOutcome {
        var removed = false
        var stale: RejectMoveFailure?
        do {
            removed = try await markQueue.clearReject(for: plan.identity)
        } catch {
            stale = RejectMoveFailure(classifying: error)
        }
        return .moved(
            RejectMoveMovedSet(
                identity: plan.identity, files: plan.files, removedStoredReject: removed,
                staleRejectRecord: stale))
    }

    // MARK: - State plumbing

    /// Builds a skip outcome with a short developer-facing explanation (PRD P0-10).
    private func skipped(_ identity: PhotoIdentity, reason: RejectMoveSkipReason)
        -> RejectMoveOutcome
    {
        RejectMoveOutcome.skipped(
            RejectMoveSkippedSet(identity: identity, reason: reason, message: reason.message))
    }

    /// Publishes one progress step to every stream a caller is reading (PRD P0-10).
    private func publish(_ progress: RejectMoveProgress) {
        for observer in observers.values { observer.yield(progress) }
    }

    /// Detaches a stream's continuation when its reader stops.
    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}

extension RejectMoveSkipReason {
    /// A short developer-facing explanation; product copy belongs to the result UI.
    var message: String {
        switch self {
        case .insideRejectsFolder: "The photo set is already inside the rejects folder."
        }
    }
}
