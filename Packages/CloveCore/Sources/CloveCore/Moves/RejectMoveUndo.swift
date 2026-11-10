import Foundation

/// One photo an undo step puts back, with everything the reverse of the move needs.
///
/// PRD P0-10's Undo rule restores a completed move's files and Reject; PRD Move rejects'
/// "Keeping before the move" adds the photos the confirmation kept, which never moved and only
/// need their Reject back.
struct RejectMoveUndoJob: Sendable {
    /// C1's stable identity, which Clove's stored Reject is keyed by (G1 decision 5).
    let identity: PhotoIdentity
    /// C1's set as the scan built it, so C4 stores Reject for the same photo (G1 decision 5).
    let set: ScannedPhotoSet
    /// Every file with its original path and its rejects-folder path (PRD P0-10).
    ///
    /// Empty for a kept photo: the move never renamed anything of it (PRD Move rejects).
    let files: [RejectMoveFilePlan]
    /// Whether the confirmation kept the photo, so only its Reject comes back (PRD Move rejects).
    let keptInConfirmation: Bool
}

/// The completed run one undo step restores, shared by its first attempt and every retry.
///
/// PRD P0-10's Undo rule makes a completed move one step, and PRD "Failure and recovery" lets a
/// retry move more of the same run. Both therefore share one record: the step covers every set
/// the run moved, and the run can be undone once.
final class RejectMoveUndoRun {
    /// The opened folder, for the whole-request read-only check (PRD "Failure and recovery").
    let rootURL: URL
    /// The sets this run has moved so far, in move order (PRD P0-10).
    var moved: [RejectMoveUndoJob]
    /// Whether an undo step already restored this run (PRD P0-10's Undo applies once).
    var isUndone: Bool

    /// Describes one completed run's moved sets (PRD P0-10).
    init(rootURL: URL, moved: [RejectMoveUndoJob]) {
        self.rootURL = rootURL
        self.moved = moved
        self.isUndone = false
    }

    /// Adds a retry's moved sets to this run, so one step still covers the whole run.
    ///
    /// PRD P0-10 retries only the failed items, and those move under a handle of their own; the
    /// first attempt's record adopts them so a single undo restores everything. PRD P0-10's Undo
    /// rule undoes a run once, so a retry that moves more sets after the run was undone does not
    /// reopen the step; it keeps its own record instead, and those sets are their own step.
    func adopt(_ retry: RejectMoveUndoRun) {
        guard retry !== self, !retry.moved.isEmpty, !isUndone else { return }
        moved.append(contentsOf: retry.moved)
    }
}

/// One undo attempt's failed photos, kept so a retry can send exactly those (PRD P0-10).
struct RejectMoveUndoRetry: Sendable {
    /// The opened folder, for the retry's read-only check (PRD "Failure and recovery").
    let rootURL: URL
    /// The photos a retry may address again, never a conflict or a split one (PRD P0-10).
    let jobs: [RejectMoveUndoJob]
}

/// Restores one photo's files and Reject: the move in reverse.
///
/// PRD P0-10's Undo rule puts a completed move back, so the runner reuses the move's rules
/// rather than inventing weaker ones: the same injected file seam, the same exclusive rename
/// that never overwrites, the same per-file confirmation by size, and the same rollback that
/// keeps a photo set a unit. A move back that cannot finish returns the set's files to the
/// rejects folder; a rollback that also fails reports every file's actual location instead of a
/// guess. The production seam has no delete and no copy, so undo can neither lose a file nor
/// duplicate one across volumes (PRD P0-10).
struct RejectMoveUndoRunner: Sendable {
    /// The seam the move used, shared so one injected failure covers both directions.
    private let fileSystem: any RejectMoveFileSystem
    /// C4's queue, the only writer of Clove's stored Reject (G1 decision 5).
    private let markQueue: MarkWriteQueue

    /// Creates the runner over the mover's seam and queue (PRD P0-10).
    init(fileSystem: any RejectMoveFileSystem, markQueue: MarkWriteQueue) {
        self.fileSystem = fileSystem
        self.markQueue = markQueue
    }

    /// Puts one photo back and stores its Reject again (PRD P0-10's Undo rule).
    ///
    /// - Parameter job: The photo, its files and its scanned set.
    /// - Returns: The photo's outcome; never throws, so one photo cannot stop the step.
    func restore(_ job: RejectMoveUndoJob) async -> RejectMoveUndoOutcome {
        // PRD Move rejects: a kept photo never moved, so the move cleared only its Reject.
        guard !job.files.isEmpty else { return await restored(job, files: []) }
        var sizes: [URL: Int] = [:]
        for file in job.files {
            do {
                guard let size = try fileSystem.fileSize(at: file.destination) else {
                    return .failed(
                        failed(
                            job,
                            RejectMoveFailure(
                                reason: .locationUnavailable,
                                message:
                                    "\(file.destination.lastPathComponent) is no longer under "
                                    + "the rejects folder.")))
                }
                // G1 decision 5's confirmation compares sizes, so the rejects-folder copy's
                // size is the evidence that the file that comes back is the one that left.
                sizes[file.source] = size
            } catch {
                return .failed(failed(job, RejectMoveFailure(classifying: error)))
            }
        }
        var taken: [URL] = []
        for file in job.files {
            do {
                if try fileSystem.exists(at: file.source) { taken.append(file.source) }
            } catch {
                return .failed(failed(job, RejectMoveFailure(classifying: error)))
            }
        }
        guard taken.isEmpty else {
            return .conflict(
                RejectMoveUndoConflict(
                    identity: job.identity, files: job.files, takenPaths: taken,
                    failure: RejectMoveFailure(
                        reason: .conflict,
                        message: "\(taken[0].lastPathComponent)'s original path is now taken.")))
        }
        for folder in Set(job.files.map({ $0.source.deletingLastPathComponent() })) {
            do {
                // PRD P0-10 preserves the subfolder structure, so the original folder exists
                // unless the user removed it; creating it is a no-op when it does.
                try fileSystem.createDirectory(folder)
            } catch {
                return .failed(failed(job, RejectMoveFailure(classifying: error)))
            }
        }
        var movedBack: [RejectMoveFilePlan] = []
        var failure: RejectMoveFailure?
        var blockedPath: URL?
        for file in job.files {
            do {
                try fileSystem.moveExclusively(from: file.destination, to: file.source)
                movedBack.append(file)
            } catch {
                failure = RejectMoveFailure(classifying: error)
                blockedPath = file.source
                break
            }
        }
        if failure == nil {
            failure = confirm(job, sizes: sizes)
        }
        guard let failure else { return await restored(job, files: job.files) }
        return rollBack(job, movedBack: movedBack, failure: failure, blockedPath: blockedPath)
    }

    /// Checks the confirmed state of every file: rejects-folder copy gone, original path present
    /// with the recorded size.
    ///
    /// PRD P0-08 confirms the storage that changed, so undo confirms the move back itself rather
    /// than the rename's return code. A mismatch rolls the set back and is never reported as
    /// restored.
    private func confirm(_ job: RejectMoveUndoJob, sizes: [URL: Int]) -> RejectMoveFailure? {
        for file in job.files {
            do {
                if try fileSystem.exists(at: file.destination) {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message:
                            "\(file.destination.lastPathComponent) is still under the rejects "
                            + "folder.")
                }
                guard let size = try fileSystem.fileSize(at: file.source) else {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message:
                            "\(file.source.lastPathComponent) is not back at its original path.")
                }
                if let expected = sizes[file.source], size != expected {
                    return RejectMoveFailure(
                        reason: .notConfirmed,
                        message: "\(file.source.lastPathComponent) changed size during the undo.")
                }
            } catch {
                return RejectMoveFailure(classifying: error)
            }
        }
        return nil
    }

    /// Returns the files that already came back to the rejects folder, then reports the set.
    ///
    /// PRD P0-10 keeps a photo set a unit, so a failure after some files moved back restores
    /// those files. Each move back is itself an exclusive rename, so a file that appeared at the
    /// rejects-folder path in the meantime is not overwritten. If any rollback or its check
    /// fails, the set is split and every file's actual location is reported.
    private func rollBack(
        _ job: RejectMoveUndoJob, movedBack: [RejectMoveFilePlan], failure: RejectMoveFailure,
        blockedPath: URL?
    ) -> RejectMoveUndoOutcome {
        var rollbackFailures: [RejectMoveFailure] = []
        var rolledBack: Set<RejectMoveFilePlan> = []
        for file in movedBack.reversed() {
            do {
                try fileSystem.moveExclusively(from: file.source, to: file.destination)
                rolledBack.insert(file)
            } catch {
                rollbackFailures.append(RejectMoveFailure(classifying: error))
            }
        }
        for file in job.files {
            let atDestination: Bool
            do {
                atDestination = try fileSystem.exists(at: file.destination)
            } catch {
                // A check that could not run is not proof the file went back, so the set cannot
                // be reported as failed with every file under the rejects folder (PRD P0-10).
                rollbackFailures.append(RejectMoveFailure(classifying: error))
                continue
            }
            guard atDestination else {
                rollbackFailures.append(
                    RejectMoveFailure(
                        reason: .notConfirmed,
                        message:
                            "\(file.destination.lastPathComponent) is not back under the rejects "
                            + "folder."))
                continue
            }
            guard movedBack.contains(file) else { continue }
            do {
                if try fileSystem.exists(at: file.source) {
                    rollbackFailures.append(
                        RejectMoveFailure(
                            reason: .notConfirmed,
                            message:
                                "\(file.source.lastPathComponent) is still at its original path."))
                }
            } catch {
                rollbackFailures.append(RejectMoveFailure(classifying: error))
            }
        }
        guard rollbackFailures.isEmpty else {
            return .split(
                RejectMoveUndoSplitPhoto(
                    identity: job.identity, failure: failure,
                    rollbackFailures: rollbackFailures,
                    files: locations(
                        of: job.files, movedBack: Set(movedBack), rolledBack: rolledBack)))
        }
        // PRD P0-10's Undo rule reports a set whose original path is taken as a conflict, so the
        // copy the UI shows names the situation the pre-check also reports.
        if failure.reason == .conflict, let blockedPath {
            return .conflict(
                RejectMoveUndoConflict(
                    identity: job.identity, files: job.files, takenPaths: [blockedPath],
                    failure: failure))
        }
        return .failed(failed(job, failure))
    }

    /// Reports every file's actual location after a failed rollback (PRD P0-10).
    ///
    /// The last rename that succeeded is what placed a file, so the reporter starts from it: a
    /// file the rollback returned is under the rejects folder even when something else now uses
    /// its original path, and a file the rollback could not return is at its original path. Disk
    /// is read only to notice a file that is no longer where the rename put it. Nothing is
    /// guessed: a check that cannot run is ``RejectMoveFileLocation/Location/unknown``, a path
    /// that answers "nothing here" is never reported as holding the file, and a file found at
    /// neither path is ``RejectMoveFileLocation/Location/missing``.
    private func locations(
        of files: [RejectMoveFilePlan], movedBack: Set<RejectMoveFilePlan>,
        rolledBack: Set<RejectMoveFilePlan>
    ) -> [RejectMoveFileLocation] {
        files.map { file in
            let placedAtSource = movedBack.contains(file) && !rolledBack.contains(file)
            let known: RejectMoveFileLocation.Location = placedAtSource ? .source : .destination
            return RejectMoveFileLocation(
                role: file.role, source: file.source, destination: file.destination,
                location: location(known: known, of: file))
        }
    }

    /// Confirms the path the last rename placed the file at, or reports what the checks say.
    ///
    /// A path that answers "nothing here" cannot be the file's location, but the other path is
    /// not the answer either: nothing proves the file that occupies it is this one, so the
    /// location stays unknown. Only two definite absences make the file missing (PRD P0-10).
    private func location(
        known: RejectMoveFileLocation.Location, of file: RejectMoveFilePlan
    ) -> RejectMoveFileLocation.Location {
        let other: RejectMoveFileLocation.Location = known == .source ? .destination : .source
        guard let atKnown = try? fileSystem.exists(at: url(of: known, in: file)) else {
            return .unknown
        }
        if atKnown { return known }
        guard let atOther = try? fileSystem.exists(at: url(of: other, in: file)) else {
            return .unknown
        }
        return atOther ? .unknown : .missing
    }

    /// The URL one location names for a file (PRD P0-10).
    private func url(of location: RejectMoveFileLocation.Location, in file: RejectMoveFilePlan)
        -> URL
    {
        switch location {
        case .source: file.source
        case .destination: file.destination
        case .missing, .unknown: file.source
        }
    }

    /// Stores Reject again and reports the photo as restored (PRD P0-10's Undo rule).
    ///
    /// G1 decision 5 keeps Reject in Clove and PRD P0-08 confirms it in the storage that holds
    /// it, so the mark goes through C4's queue like every other mark. A mark that could not be
    /// stored stays a diagnostic: the files are back, so the photo is restored and the stale
    /// record is reported for a retry of the mark.
    private func restored(_ job: RejectMoveUndoJob, files: [RejectMoveFilePlan]) async
        -> RejectMoveUndoOutcome
    {
        let status = await markQueue.apply(.reject(true), to: job.set)
        return .restored(
            RejectMoveUndoRestoredPhoto(
                identity: job.identity, set: job.set, files: files,
                keptInConfirmation: job.keptInConfirmation,
                rejectStoreFailure: rejectStoreFailure(of: status.state)))
    }

    /// C4's reason when the restored Reject was not confirmed (PRD P0-08).
    private func rejectStoreFailure(of state: MarkChangeState) -> RejectMoveFailure? {
        if state.isConfirmed { return nil }
        if let failure = state.failure {
            return RejectMoveFailure(
                reason: RejectMoveFailureReason(failure.reason), message: failure.message,
                errorChain: failure.errorChain)
        }
        return RejectMoveFailure(
            reason: .unknown,
            message: "A newer change replaced the restored Reject before it was stored.")
    }

    /// The failed outcome for a photo whose files stayed under the rejects folder (PRD P0-10).
    private func failed(_ job: RejectMoveUndoJob, _ failure: RejectMoveFailure)
        -> RejectMoveUndoFailedPhoto
    {
        RejectMoveUndoFailedPhoto(
            identity: job.identity, failure: failure, files: job.files)
    }
}

// MARK: - The mover's undo calls

/// Undoing a completed run, in the mover that owns its files and its mark queue.
///
/// PRD P0-10's Undo rule and the PRD's Undo row make a completed move one step: every set the
/// run moved comes back to its original path, and Reject returns on those photos and on the
/// photos the confirmation kept. The mover keeps each run's moved sets, so the caller holds only
/// a ``RejectMoveUndoEntry`` and the run can be undone once, even after a retry moved more of it.
extension RejectMover {
    /// Undoes a completed run as one step (PRD P0-10's Undo rule, PRD's Undo row).
    ///
    /// Every moved set is renamed back with the move's own rules: same volume only, never
    /// overwrite, and confirmed per file. A set whose original path is taken stays untouched
    /// under the rejects folder and is reported as a conflict; a set that cannot finish rolls
    /// back into the rejects folder; a set whose Reject cannot be stored after a confirmed move
    /// back is restored with the stale record as a diagnostic. The kept photos only get Reject
    /// back, because they never moved. Folders the move created stay in place: undo deletes
    /// nothing (PRD P0-10).
    ///
    /// A run is undone once: a second call is refused, and so is every handle that resolves to
    /// that step. A retry that moves more sets *after* the undo does not reopen it; those sets
    /// keep their own handle and are restored once, separately.
    ///
    /// - Parameter entry: The step, as the move or its retry produced it.
    /// - Returns: One outcome per restored photo, with the counts and the failed photos a retry
    ///   can send again.
    /// - Throws: A refusal that touched nothing: the run is unknown or already undone, or the
    ///   location reports itself read-only.
    public func undo(_ entry: RejectMoveUndoEntry) async throws(RejectMoveUndoRefusal)
        -> RejectMoveUndoResult
    {
        guard let run = undoableRuns[entry.batch] else { throw .unknownBatch(entry.batch) }
        guard !run.isUndone else { throw .alreadyUndone(entry.batch) }
        try preflightUndo(run.rootURL)
        // PRD P0-10's Undo applies once, so a second call is refused even while this one runs.
        run.isUndone = true
        return await performUndo(
            jobs(for: run, keeping: entry.keptPhotos), rootURL: run.rootURL)
    }

    /// Retries the photos an earlier undo attempt could not restore (PRD P0-10).
    ///
    /// PRD "Failure and recovery" retries only the failed items, so restored photos are left
    /// alone and a conflict or a split set is never resent: their files are in a place a blind
    /// retry could overwrite or duplicate. The returned attempt has its own handle, and the
    /// earlier one is dropped so it cannot be retried twice.
    ///
    /// - Parameter batch: The undo attempt whose failed photos should be retried.
    /// - Returns: The retry's outcomes, or `nil` when the attempt is unknown or had no failures
    ///   left to retry.
    /// - Throws: ``RejectMoveUndoRefusal/readOnlyLocation(_:)`` when the location is read-only.
    public func retryFailedUndo(in batch: RejectMoveUndoBatchID) async throws(RejectMoveUndoRefusal)
        -> RejectMoveUndoResult?
    {
        guard let retry = undoRetries[batch] else { return nil }
        try preflightUndo(retry.rootURL)
        undoRetries[batch] = nil
        return await performUndo(retry.jobs, rootURL: retry.rootURL)
    }

    /// Every undo progress step, as a stream a UI can wrap into its own observation.
    ///
    /// PRD P0-10 asks for progress during a move, and an undo renames the same files and stores
    /// a Reject for each photo. The stream yields each photo as it starts and finishes, then the
    /// attempt's result. It buffers at most 64 steps and drops its subscription once the stream
    /// ends, so a caller that deallocates the stream leaves nothing behind; a caller that keeps
    /// an abandoned stream retains that one buffered subscription. A retry of failed photos
    /// publishes its own sequence.
    public func undoProgressUpdates() -> AsyncStream<RejectMoveUndoProgress> {
        let (stream, continuation) = AsyncStream<RejectMoveUndoProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(64))
        let observerID = UUID()
        undoObservers[observerID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeUndoObserver(observerID) }
        }
        return stream
    }

    /// Refuses an undo that cannot touch any file (PRD P0-10, "Failure and recovery").
    ///
    /// PRD "Failure and recovery" gives a read-only location its own message, so undo refuses
    /// the whole request instead of reporting every photo as failed. Only the volume's own
    /// read-only value refuses; a failed read is not evidence, and a generic rename failure is
    /// classified per photo.
    private func preflightUndo(_ rootURL: URL) throws(RejectMoveUndoRefusal) {
        guard (try? fileSystem.isReadOnlyVolume(at: rootURL)) == true else { return }
        let name =
            rootURL.lastPathComponent.isEmpty
            ? rootURL.path(percentEncoded: false) : rootURL.lastPathComponent
        throw .readOnlyLocation(
            RejectMoveFailure(
                reason: .readOnlyStorage,
                message: "The volume holding \(name) reports itself read-only."))
    }

    /// Runs every photo's restore and keeps the failures for a retry (PRD P0-10).
    ///
    /// A photo's outcome never stops the step, so one taken path or one failed rename does not
    /// hide the photos that did come back. A run with no photo to restore still returns a result,
    /// so the caller's one step always ends.
    private func performUndo(_ jobs: [RejectMoveUndoJob], rootURL: URL) async
        -> RejectMoveUndoResult
    {
        let runner = RejectMoveUndoRunner(fileSystem: fileSystem, markQueue: markQueue)
        var outcomes: [RejectMoveUndoOutcome] = []
        outcomes.reserveCapacity(jobs.count)
        var failedJobs: [RejectMoveUndoJob] = []
        for job in jobs {
            publishUndo(.photoStarted(job.identity))
            let outcome = await runner.restore(job)
            outcomes.append(outcome)
            publishUndo(.photoFinished(outcome))
            if case .failed = outcome { failedJobs.append(job) }
        }
        let result = RejectMoveUndoResult(id: RejectMoveUndoBatchID(), outcomes: outcomes)
        if !failedJobs.isEmpty {
            undoRetries[result.id] = RejectMoveUndoRetry(rootURL: rootURL, jobs: failedJobs)
        }
        publishUndo(.finished(result))
        return result
    }

    /// Publishes one undo progress step to every stream a caller is reading (PRD P0-10).
    ///
    /// A subscription whose stream has already ended is dropped here, so a finished reader never
    /// keeps a buffered step alive.
    private func publishUndo(_ progress: RejectMoveUndoProgress) {
        for (id, observer) in undoObservers {
            switch observer.yield(progress) {
            case .terminated: undoObservers[id] = nil
            @unknown default: break
            }
        }
    }

    /// Detaches a stream's continuation when its reader stops (PRD P0-10).
    private func removeUndoObserver(_ id: UUID) {
        undoObservers[id] = nil
    }

    /// The run's moved sets plus the photos the confirmation kept, each photographed once.
    ///
    /// PRD P0-10's Undo rule restores the moved sets and the kept photos; a photo that somehow
    /// appears in both is restored once, from the run's own record.
    private func jobs(for run: RejectMoveUndoRun, keeping kept: [ScannedPhotoSet])
        -> [RejectMoveUndoJob]
    {
        var jobs = run.moved
        var seen = Set(jobs.map(\.identity))
        for photo in kept where seen.insert(photo.id).inserted {
            jobs.append(
                RejectMoveUndoJob(
                    identity: photo.id, set: photo, files: [], keptInConfirmation: true))
        }
        return jobs
    }

    /// Keeps a completed run's moved sets so an undo can restore them (PRD P0-10).
    ///
    /// The record pairs each set's confirmed files with the scanned set C4 stores Reject for,
    /// and it is addressable by the run's handle. A run that moved nothing keeps an empty record:
    /// the confirmation may still have kept photos for the same step.
    func rememberUndo(_ result: RejectMoveResult, plan: RejectMovePlan) {
        let sets = Dictionary(
            plan.sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var moved: [RejectMoveUndoJob] = []
        moved.reserveCapacity(result.moved.count)
        for set in result.moved {
            guard let scanned = sets[set.identity] else { continue }
            moved.append(
                RejectMoveUndoJob(
                    identity: set.identity, set: scanned, files: set.files,
                    keptInConfirmation: false))
        }
        undoableRuns[result.id] = RejectMoveUndoRun(rootURL: plan.rootURL, moved: moved)
    }

    /// Makes a retry's moved sets part of the run the caller first held (PRD P0-10).
    ///
    /// PRD "Failure and recovery" retries the unmoved items of one run, so the retry is not a
    /// second undo step: its sets join the first attempt's record, and both handles resolve to
    /// that one step. A run that was already undone keeps its step spent, so a retry that
    /// finishes afterwards keeps its own handle instead: its sets moved after the undo, and the
    /// only alternative would leave them with no way back.
    func adoptUndoRetry(_ result: RejectMoveResult, of batch: RejectMoveBatchID) {
        guard let root = undoableRuns[batch], let retried = undoableRuns[result.id] else {
            return
        }
        guard root !== retried, !root.isUndone else { return }
        root.adopt(retried)
        undoableRuns[result.id] = root
    }
}
