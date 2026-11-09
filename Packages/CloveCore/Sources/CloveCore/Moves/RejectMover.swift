import Foundation

/// Runs Move rejects: plans the sets, moves each one as a unit, and reports per-photo results.
///
/// G1 decision 5 and PRD P0-10 make the move the durable Reject result: after the user
/// confirms, every rejected photo set is renamed into `<root>/<rejects folder>/<relative
/// folder>` with its JPEG/HIF companions and its `.xmp`, and only a confirmed move counts.
/// The actor owns the whole run so its rules hold in one place:
///
/// - **Before moving.** A disabled setting or a read-only location refuses the whole request
///   (PRD Move rejects, Failure and recovery). C4's admitted writes drain first, and a set
///   whose latest mark change is unfinished or failed is skipped, because a later retry of that
///   change would address the old path (G1 decision 5, PRD P0-08).
/// - **One unit per set.** Every file is renamed with an exclusive rename that refuses an
///   existing destination (PRD P0-10), and the set is confirmed file by file: source gone,
///   destination present with the source's size. If a later file fails, the earlier files move
///   back; if the move back also fails, the set is reported as split with every file's actual
///   location, so no file is ever lost track of.
/// - **After a confirmed move.** C4's stored Reject is removed; a removal that fails leaves the
///   set moved and reports the stale record as a diagnostic (PRD P0-08).
/// - **Results.** Moved sets keep their new URLs so the grid can drop them, failed sets stay in
///   place for a retry of failed items only, and cancellation stops the run between sets, never
///   inside one (PRD P0-10, Failure and recovery).
///
/// The actor holds only in-flight and post-run state: the batches kept for ``retryFailed(in:)``
/// and the progress streams. All file work goes through the injected ``RejectMoveFileSystem``,
/// which has no delete or copy operation at all.
public actor RejectMover {
    /// The injectable file operations every move goes through (PRD P0-10).
    private let fileSystem: any RejectMoveFileSystem
    /// The confirmation-plan builder and the whole-request preconditions (PRD P0-10).
    private let planner: RejectMovePlanner
    /// C4's write queue: drain, the per-set mark-change check and the stored-Reject removal.
    private let markQueue: MarkWriteQueue
    /// One entry per run that still has failed items to retry (PRD P0-10).
    private var batches: [RejectMoveBatchID: AppliedBatch] = [:]
    /// Progress streams handed to a UI or a test (PRD P0-10).
    private var observers: [UUID: AsyncStream<RejectMoveProgress>.Continuation] = [:]

    /// Creates the mover over C4's queue and the production file system unless a test injects
    /// another.
    ///
    /// The queue is the only writer of Clove's stored Reject, so the mover never touches app
    /// storage directly; tests inject a temporary store directory and a file-system double so
    /// nothing reaches real photos or the app's Application Support container.
    public init(
        markQueue: MarkWriteQueue,
        fileSystem: any RejectMoveFileSystem = FoundationRejectMoveFileSystem()
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
    /// admitted writes, and checks each set's latest mark change again right before it starts.
    /// Moved sets keep their new URLs, failed sets are untouched and retryable, and cancellation
    /// is honoured between sets only, so a set is never half-attempted.
    ///
    /// Throws only a whole-request refusal; every per-set problem is an outcome.
    public func move(_ plan: RejectMovePlan) async throws(RejectMoveRefusal) -> RejectMoveResult {
        try planner.preflight(rootURL: plan.rootURL, configuration: plan.configuration)
        // G1 decision 5: a mark write still in flight would target the old path, so the run
        // starts after C4 has nothing left to write (PRD P0-08, Failure and recovery).
        await markQueue.drain()

        let id = RejectMoveBatchID()
        var outcomes: [RejectMoveOutcome] = []
        outcomes.reserveCapacity(plan.entries.count)
        for (index, entry) in plan.entries.enumerated() {
            if Task.isCancelled {
                // PRD P0-10: cancellation takes effect between sets, never in the middle of
                // one. The remaining sets are reported as skipped and stay untouched.
                for remaining in plan.entries[index...] {
                    outcomes.append(skipped(remaining.identity, reason: .cancelled))
                }
                break
            }
            publish(.setStarted(entry.identity))
            let outcome = await perform(entry)
            outcomes.append(outcome)
            publish(.setFinished(outcome))
        }
        let result = RejectMoveResult(id: id, outcomes: outcomes)
        remember(result, plan: plan)
        publish(.finished(result))
        return result
    }

    /// Retries only the failed sets of an earlier run (PRD P0-10, Failure and recovery).
    ///
    /// Moved sets stay moved and split sets are never resent, because their files are in two
    /// places and a retry could not restore them blindly. A set that was skipped is not part of
    /// the retry either: resolving its mark change is what makes it movable. The returned run
    /// has its own handle, and the earlier one is dropped so a second retry cannot resend it.
    public func retryFailed(in batch: RejectMoveBatchID) async throws(RejectMoveRefusal)
        -> RejectMoveResult?
    {
        guard let applied = batches[batch], !applied.sets.isEmpty else { return nil }
        let request = RejectMoveRequest(
            rootURL: applied.rootURL, sets: applied.sets,
            configuration: applied.configuration)
        let plan = try planner.plan(for: request)
        let result = try await move(plan)
        batches[batch] = nil
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

    /// Moves one set as a unit and confirms every file (G1 decision 5, PRD P0-10).
    private func move(_ plan: RejectMoveSetPlan) async -> RejectMoveOutcome {
        if let skip = await markSkip(for: plan.identity) { return skip }
        var sizes: [URL: Int] = [:]
        do {
            for file in plan.files {
                guard let size = try fileSystem.fileSize(at: file.source) else {
                    return .failed(
                        RejectMoveFailedSet(
                            identity: plan.identity,
                            failure: RejectMoveFailure(
                                reason: .locationUnavailable,
                                message: "\(file.source.lastPathComponent) is no longer there."),
                            files: plan.files))
                }
                sizes[file.source] = size
            }
        } catch {
            return .failed(
                RejectMoveFailedSet(
                    identity: plan.identity, failure: RejectMoveFailure(classifying: error),
                    files: plan.files))
        }
        // PRD P0-10: same volume only, compared before any folder is created. A volume that
        // reports no identifier cannot be compared, so the exclusive rename's EXDEV remains
        // the authority rather than a guess.
        let volumes = volumeIdentifiers(of: plan)
        if let source = volumes.source, let destination = volumes.destination,
            source != destination
        {
            return .failed(
                RejectMoveFailedSet(
                    identity: plan.identity,
                    failure: RejectMoveFailure(
                        reason: .differentVolume,
                        message: "The rejects folder is on a different volume."),
                    files: plan.files))
        }
        do {
            try fileSystem.createDirectory(plan.destinationFolder)
        } catch {
            return .failed(
                RejectMoveFailedSet(
                    identity: plan.identity, failure: RejectMoveFailure(classifying: error),
                    files: plan.files))
        }

        var moved: [RejectMoveFilePlan] = []
        var failure: RejectMoveFailure?
        for file in plan.files {
            do {
                try fileSystem.moveExclusively(from: file.source, to: file.destination)
                moved.append(file)
            } catch {
                failure = RejectMoveFailure(classifying: error)
                break
            }
        }
        if failure == nil {
            failure = confirm(plan, sizes: sizes)
        }
        guard let failure else {
            return await confirmed(plan)
        }
        return rollBack(plan, moved: moved, failure: failure)
    }

    /// Reads both volumes for the same-volume check (PRD P0-10).
    private func volumeIdentifiers(of plan: RejectMoveSetPlan) -> (
        source: String?, destination: String?
    ) {
        guard let primary = plan.files.first?.source else { return (nil, nil) }
        let source = try? fileSystem.volumeIdentifier(of: primary.deletingLastPathComponent())
        let destination = try? fileSystem.volumeIdentifier(of: plan.destinationFolder)
        return (source, destination)
    }

    /// Checks the confirmed state of every file: source gone, destination present, same size.
    ///
    /// G1 decision 5 and PRD P0-08 confirm the move itself, not the rename's return code. A
    /// mismatch is ``RejectMoveFailureReason/notConfirmed`` and rolls the set back, so an
    /// unconfirmed move is never reported as moved.
    private func confirm(_ plan: RejectMoveSetPlan, sizes: [URL: Int]) -> RejectMoveFailure? {
        for file in plan.files {
            do {
                if try fileSystem.exists(at: file.source) {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message: "\(file.source.lastPathComponent) is still at its source.")
                }
                guard let size = try fileSystem.fileSize(at: file.destination) else {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message: "\(file.destination.lastPathComponent) is not at its destination.")
                }
                if let expected = sizes[file.source], size != expected {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message:
                            "\(file.destination.lastPathComponent) changed size during the move.")
                }
            } catch {
                return RejectMoveFailure(classifying: error)
            }
        }
        return nil
    }

    /// Moves every earlier file back, then reports the set as failed or split (PRD P0-10).
    ///
    /// PRD P0-10 keeps a set a unit: a failure after some files moved restores those files. Each
    /// move back is itself an exclusive rename, so a file that appeared at the source in the
    /// meantime is not overwritten. If any move back or its check fails, the set is split and
    /// every file's actual location is reported instead of a guessed one.
    private func rollBack(
        _ plan: RejectMoveSetPlan, moved: [RejectMoveFilePlan], failure: RejectMoveFailure
    ) -> RejectMoveOutcome {
        var rollbackFailures: [RejectMoveFailure] = []
        for file in moved.reversed() {
            do {
                try fileSystem.moveExclusively(from: file.destination, to: file.source)
            } catch {
                rollbackFailures.append(RejectMoveFailure(classifying: error))
            }
        }
        let restored = moved.reduce(into: Set<URL>()) { $0.insert($1.source) }
        for file in plan.files {
            let atSource: Bool
            do {
                atSource = try fileSystem.exists(at: file.source)
            } catch {
                // A check that could not run is not proof the file moved back, so it counts as
                // a rollback this set cannot confirm (PRD P0-10).
                rollbackFailures.append(RejectMoveFailure(classifying: error))
                continue
            }
            guard atSource else {
                rollbackFailures.append(
                    RejectMoveFailure(
                        reason: .notConfirmed,
                        message: "\(file.source.lastPathComponent) is not back at its source."))
                continue
            }
            guard restored.contains(file.source) else { continue }
            do {
                if try fileSystem.exists(at: file.destination) {
                    rollbackFailures.append(
                        RejectMoveFailure(
                            reason: .notConfirmed,
                            message:
                                "\(file.destination.lastPathComponent) is still at its destination."
                        ))
                }
            } catch {
                rollbackFailures.append(RejectMoveFailure(classifying: error))
            }
        }
        guard rollbackFailures.isEmpty else {
            return .split(
                RejectMoveSplitSet(
                    identity: plan.identity, failure: failure,
                    rollbackFailures: rollbackFailures,
                    files: locations(of: plan.files, moved: Set(moved))))
        }
        return .failed(
            RejectMoveFailedSet(identity: plan.identity, failure: failure, files: plan.files))
    }

    /// Reports every file's actual location after a failed move back (PRD P0-10).
    ///
    /// A moved file is looked for at the destination first and a file that never moved at its
    /// source first, so a stale copy can never be mistaken for the file. A check that throws is
    /// reported as ``RejectMoveFileLocation/Location/unknown`` rather than as a lost file.
    private func locations(
        of files: [RejectMoveFilePlan], moved: Set<RejectMoveFilePlan>
    ) -> [RejectMoveFileLocation] {
        files.map { file in
            let atDestination = try? fileSystem.exists(at: file.destination)
            let atSource = try? fileSystem.exists(at: file.source)
            let location = location(
                source: atSource, destination: atDestination,
                prefersDestination: moved.contains(file))
            return RejectMoveFileLocation(
                role: file.role, source: file.source, destination: file.destination,
                location: location)
        }
    }

    /// Chooses one file's location from the two checks, or ``RejectMoveFileLocation``'s
    /// unknown and missing cases when neither answers (PRD P0-10).
    private func location(
        source: Bool?, destination: Bool?, prefersDestination: Bool
    ) -> RejectMoveFileLocation.Location {
        let first = prefersDestination ? destination : source
        let second = prefersDestination ? source : destination
        let firstLocation: RejectMoveFileLocation.Location =
            prefersDestination ? .destination : .source
        let secondLocation: RejectMoveFileLocation.Location =
            prefersDestination ? .source : .destination
        switch (first, second) {
        case (true, _): return firstLocation
        case (false, true), (nil, true): return secondLocation
        case (false, false): return .missing
        case (false, nil), (nil, false), (nil, nil): return .unknown
        }
    }

    /// Drops the stored Reject after a confirmed move (G1 decision 5, PRD P0-08).
    ///
    /// The move is the durable Reject result, so the record is removed only now. A removal that
    /// throws leaves the set counted as moved and the stale record as a diagnostic, because the
    /// files are already in the rejects folder and reporting the set as unmoved would be wrong.
    private func confirmed(_ plan: RejectMoveSetPlan) async -> RejectMoveOutcome {
        var removed = false
        var stale: RejectMoveFailure?
        do {
            removed = try await markQueue.removeReject(for: plan.identity)
        } catch {
            stale = RejectMoveFailure(classifying: error)
        }
        return .moved(
            RejectMoveMovedSet(
                identity: plan.identity, files: plan.files, removedStoredReject: removed,
                staleRejectRecord: stale))
    }

    /// The skip a set's latest mark change forces, or `nil` when it may move (PRD P0-08).
    private func markSkip(for identity: PhotoIdentity) async -> RejectMoveOutcome? {
        guard let change = await markQueue.latestChange(for: identity) else { return nil }
        switch change.state {
        case .pending, .writing:
            return skipped(identity, reason: .unfinishedMarkChange)
        case .failed:
            return skipped(identity, reason: .failedMarkChange)
        case .savedInSidecar, .savedInCloveOnly, .storedInClove, .superseded:
            return nil
        }
    }

    // MARK: - Batch bookkeeping

    /// One run's inputs, kept so ``retryFailed(in:)`` can rebuild its plan (PRD P0-10).
    private struct AppliedBatch {
        /// The opened folder the rejects folder lives under.
        let rootURL: URL
        /// The settings the run used; a retry keeps the same destination name.
        let configuration: RejectMoveConfiguration
        /// The failed sets, which are the only ones a retry resends (PRD P0-10).
        let sets: [ScannedPhotoSet]
    }

    /// Keeps the failed sets of a run for a retry of failed items only (PRD P0-10).
    private func remember(_ result: RejectMoveResult, plan: RejectMovePlan) {
        let failedIdentities = Set(result.failed.map(\.identity))
        guard !failedIdentities.isEmpty else {
            batches[result.id] = nil
            return
        }
        let sets = plan.sets.filter { failedIdentities.contains($0.photoSet.id) }
        batches[result.id] = AppliedBatch(
            rootURL: plan.rootURL, configuration: plan.configuration, sets: sets)
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
        case .unfinishedMarkChange: "A mark change for this photo hasn't finished saving."
        case .failedMarkChange: "A mark change for this photo failed and needs its retry first."
        case .insideRejectsFolder: "The photo set is already inside the rejects folder."
        case .cancelled: "The move was cancelled before this photo set started."
        }
    }
}
