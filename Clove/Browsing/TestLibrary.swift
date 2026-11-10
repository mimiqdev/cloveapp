import CloveCore
import Foundation

/// The in-memory library the UI test and previews browse (PRD P0-08, P0-13).
///
/// It stands in for folder access, the scan, the order and the atomic C4 write until U2 and U3
/// replace the ``FolderLibrary`` seam. It holds one fake folder with a few dozen photos, some
/// marks, two groups and the save state of each change it receives, and writes nothing anywhere.
///
/// The sample is selected with the launch environment value ``launchVariable``; without it the
/// app browses an empty library and entry says no folder is open.
@MainActor
final class TestLibrary: FolderLibrary {
    /// The launch environment value that selects the sample library: set it to `1`.
    static let launchVariable = "CLOVE_TEST_LIBRARY"

    /// The launch environment value that makes one sample set fail its first move (PRD P0-10).
    ///
    /// Its value is a stem suffix: a rejected photo whose stem ends with it reports a failed move
    /// once, stays in the grid and keeps its Reject, and the next retry moves it. The UI smoke
    /// test therefore forces a partial Move rejects failure without files.
    static let forcedMoveFailureVariable = "CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX"

    /// The launch environment value that makes the sample location read-only (PRD P0-10).
    ///
    /// Set it to `1` and the sample refuses every Move rejects request with the read-only
    /// location the sheet explains, still without touching a file.
    static let readOnlyVariable = "CLOVE_TEST_LIBRARY_READ_ONLY"

    /// The launch environment value that keeps a sample move toast from auto-dismissing.
    ///
    /// The UI smoke test reads Details and the grid after a move; this holds the toast for that
    /// check without lengthening the timer users get.
    static let keepToastVariable = "CLOVE_TEST_LIBRARY_KEEP_TOAST"

    /// Whether this launch keeps the sample move toast visible (PRD P0-10).
    static var keepsMoveToast: Bool {
        ProcessInfo.processInfo.environment[keepToastVariable] == "1"
    }

    /// The launch environment value that makes sample photos fail their first write (PRD P0-09).
    ///
    /// Its value is a stem suffix: a photo whose stem ends with it reports a failed change once
    /// and keeps the marks it had, and the next write saves it. The UI test therefore forces a
    /// partial batch failure without files, sees the PRD's "Saved N photos. M photos couldn't be
    /// saved." copy, and sees a retry of only the failed photo succeed.
    static let forcedFailureVariable = "CLOVE_TEST_LIBRARY_FAIL_STEM_SUFFIX"

    /// The library this launch browses: the sample when the launch value asks for it (PRD P0-13).
    static func forLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any FolderLibrary {
        guard environment[launchVariable] == "1" else { return TestLibrary() }
        return sample(
            failingStemSuffix: environment[forcedFailureVariable],
            failingMoveStemSuffix: environment[forcedMoveFailureVariable],
            readOnly: environment[readOnlyVariable] == "1")
    }

    /// The sample folder's durable key, spelled so a saved scene never looks like a real folder.
    static let sampleFolderKey = FolderIdentity(rawValue: "clove.test-library")

    /// The empty library's key: nothing is open, so a scene saved by the sample never applies
    /// here (PRD P0-14).
    static let emptyFolderKey = FolderIdentity(rawValue: "clove.empty-library")

    /// The sample photo whose file produces no preview, so the grid has an unreadable state to
    /// show and never a blank image presented as loaded (PRD Scan scope).
    static let unreadablePhoto = samplePhoto(2700)

    /// The generated tiles the sample grid draws: no file is read and every photo is a tile
    /// (PRD P0-03). The unreadable photo reports that state instead.
    static var sampleThumbnails: any GridThumbnailSource {
        SampleGridThumbnails(companions: sampleCompanions, unavailable: [unreadablePhoto])
    }

    /// The sample photo whose detail answers with its preview only, so the screen has a
    /// "preview only" note to show (PRD P0-04, G1 detail row).
    static let previewOnlyPhoto = samplePhoto(2706)

    /// The generated detail images the sample shows: the unreadable file answers unavailable and
    /// one photo cannot go past its preview (PRD P0-04, PRD Scan scope).
    static var sampleDetailImages: any DetailImageSource {
        SampleDetailImages(unavailable: [unreadablePhoto], previewOnly: [previewOnlyPhoto])
    }

    let folder: FolderIdentity

    /// The groups the sample publishes; turning similar groups off publishes none (PRD P0-11).
    private(set) var groups: [BrowsingGroup]

    /// The groups the sample publishes again when similar groups are turned back on.
    private var allGroups: [BrowsingGroup]

    /// The one update stream the browsing model consumes, so the sample browses through the same
    /// path as the real library (PRD P0-08, P0-13).
    let updates: AsyncStream<FolderLibraryUpdate>

    /// The generated tiles this library's grid draws (PRD P0-03).
    let thumbnails: any GridThumbnailSource

    /// The generated detail images this library's detail view draws (PRD P0-04).
    let detailImages: any DetailImageSource

    private let updateContinuation: AsyncStream<FolderLibraryUpdate>.Continuation
    private var stored: [GridPhoto]
    private var changes: [PhotoIdentity: MarkChangeStatus]

    /// The sample's finishing-action records, so a group it finishes counts as complete like the
    /// real session's (PRD In-group culling, group completion; PRD P0-12).
    private let groupCompletion = GroupCompletionTracker()

    /// The stem suffix whose photos fail their first write, or nil when none does (PRD P0-09).
    private let failingStemSuffix: String?

    /// The photos whose forced failure already happened, so a retry saves them (PRD P0-09).
    private var alreadyFailed: Set<PhotoIdentity> = []

    /// The photos whose forced move failure already happened, so a retry moves them (P0-10).
    private var alreadyFailedMoves: Set<PhotoIdentity> = []

    /// The batches this library applied, so a retry touches only their failed photos
    /// (PRD P0-09).
    private var batches: [MarkBatchID: [BatchMarkItem]] = [:]

    /// The stem suffix whose rejected photos fail their first move, or nil when none does
    /// (PRD P0-10).
    private let failingMoveStemSuffix: String?

    /// Whether this sample refuses Move rejects as a read-only location (PRD P0-10).
    private let readOnly: Bool

    /// The entries a retry may resend, one batch per run that had a failure (PRD P0-10).
    private var rejectMoveBatches: [RejectMoveBatchID: [RejectMovePlanEntry]] = [:]

    /// The progress stream the move sheet reads while a sample move runs (PRD P0-10).
    ///
    /// Each run gets its own stream, so a retry never reads the earlier run's finished step.
    private var rejectMoveContinuation: AsyncStream<RejectMoveProgress>.Continuation?

    /// The folder's photos with their marks, in the sample's capture order (PRD P0-03).
    var photos: [GridPhoto] { stored }

    /// An empty library: no folder holds anything until entry opens one.
    init() {
        folder = TestLibrary.emptyFolderKey
        stored = []
        groups = []
        allGroups = []
        changes = [:]
        failingStemSuffix = nil
        failingMoveStemSuffix = nil
        readOnly = false
        thumbnails = SampleGridThumbnails()
        detailImages = EmptyDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
    }

    /// A fixed library, for the sample below and the previews.
    init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        changes: [MarkChangeStatus] = [],
        failingStemSuffix: String? = nil,
        failingMoveStemSuffix: String? = nil,
        readOnly: Bool = false,
        detailImages: (any DetailImageSource)? = nil
    ) {
        folder = TestLibrary.sampleFolderKey
        stored = photos
        self.groups = groups
        allGroups = groups
        var byPhoto: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in changes { byPhoto[change.identity] = change }
        self.changes = byPhoto
        self.failingStemSuffix = failingStemSuffix
        self.failingMoveStemSuffix = failingMoveStemSuffix
        self.readOnly = readOnly
        thumbnails = TestLibrary.sampleThumbnails
        self.detailImages = detailImages ?? SampleDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        // The sample is fully scanned when it opens, so the grid can show the actions the
        // handoff hides during opening (design handoff, PRD P0-01).
        updateContinuation.yield(.scanStarted)
        updateContinuation.yield(
            .scanFinished(
                FolderScanSummary(photoCount: stored.count, status: .complete)))
    }

    /// Applies only the fields the change names and reports the state C4 would (PRD P0-08).
    ///
    /// Every sample photo is a RAW set, whose rating and label belong to its sidecar, so a change
    /// that names either reports ``MarkChangeState/savedInSidecar``. A Reject-only change reports
    /// ``MarkChangeState/storedInClove``, which is confirmed but never shown as Saved (G1
    /// decision 5). ``MarkChangeState/savedInCloveOnly`` would belong to a standalone JPEG/HIF
    /// (G1 decision 6); the sample has none. A newer change replaces the photo's status the way the
    /// queue supersedes an older request, and a photo with nothing requested has no status at all.
    /// Nothing is written anywhere.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus {
        perform(change, for: photo)
    }

    /// Applies one bar action's per-photo changes as one batch (PRD P0-09).
    ///
    /// Each photo is written on its own, the way C4's batch admits each set: a photo the launch
    /// forced to fail keeps its marks and reports a failure, while the others take the change.
    /// Per-photo states go through the same stream as a single change, and the batch's handle
    /// retries only the photos that did not save.
    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        let outcomes = items.map { perform($0.change, for: $0.photo) }
        let batch = MarkBatchID()
        batches[batch] = items
        return MarkBatchResult(
            id: batch, change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }

    /// Retries only the photos one batch could not save (PRD P0-09).
    func retryFailed(in batch: MarkBatchID) async -> MarkBatchResult? {
        guard let items = batches[batch] else { return nil }
        let failed = items.filter { changes[$0.photo]?.state.isUnfinished == true }
        let outcomes = failed.map { perform($0.change, for: $0.photo) }
        let retry = MarkBatchID()
        batches[retry] = items
        return MarkBatchResult(
            id: retry, change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }

    /// Applies one change to one photo and reports the state C4 would (PRD P0-08).
    ///
    /// Every sample photo is a RAW set, whose rating and label belong to its sidecar, so a change
    /// that names either reports ``MarkChangeState/savedInSidecar``. A Reject-only change reports
    /// ``MarkChangeState/storedInClove``, which is confirmed but never shown as Saved (G1
    /// decision 5). ``MarkChangeState/savedInCloveOnly`` would belong to a standalone JPEG/HIF
    /// (G1 decision 6); the sample has none. A newer change replaces the photo's status the way the
    /// queue supersedes an older request, and a photo with nothing requested has no status at all.
    /// A forced failure leaves the photo's marks untouched and fails only that photo's first
    /// write, so a retry shows what retrying does (PRD P0-08, P0-09). Nothing is written
    /// anywhere.
    private func perform(_ change: MarkChange, for photo: PhotoIdentity) -> MarkChangeStatus {
        guard !change.isEmpty else {
            // C4's queue refuses a request that names no marks and records nothing.
            return MarkChangeStatus(
                id: MarkChangeID(), identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .unknown,
                        message: "The change names no marks, so nothing was written.")))
        }
        guard let index = stored.firstIndex(where: { $0.id == photo }) else {
            return MarkChangeStatus(
                id: MarkChangeID(), identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .locationUnavailable,
                        message: "The sample library does not hold this photo.")))
        }
        if let failingStemSuffix, photo.stem.hasSuffix(failingStemSuffix),
            alreadyFailed.insert(photo).inserted
        {
            let status = MarkChangeStatus(
                id: MarkChangeID(), identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .notConfirmed,
                        message: "The sample library was told to fail this photo.")))
            changes[photo] = status
            updateContinuation.yield(.change(status))
            return status
        }
        var marks = stored[index].marks
        if let rating = change.rating { marks.rating = rating }
        if let label = change.label { marks.label = label }
        if let reject = change.reject { marks.isRejected = reject }
        stored[index].marks = marks

        let state: MarkChangeState =
            change.rating == nil && change.label == nil ? .storedInClove : .savedInSidecar
        let status = MarkChangeStatus(
            id: MarkChangeID(), identity: photo, requested: change, state: state)
        changes[photo] = status
        // The sample publishes through the same stream as the real library, so every verify
        // exercises the model's update path (PRD P0-08, P0-13).
        updateContinuation.yield(.reads(times: [:], marks: [photo: marks]))
        updateContinuation.yield(.change(status))
        return status
    }

    // MARK: - Move rejects

    /// Plans Move rejects from the sample's rejected photos (PRD P0-10).
    ///
    /// The plan is built in memory from the sample's marks, so the sheet shows the same counts,
    /// companions, XMP files and folder name the real plan would, without checking or touching a
    /// file. A read-only sample refuses the whole request, as PRD P0-10 requires.
    func planRejectMove(configuration: RejectMoveConfiguration) async throws -> RejectMovePlan {
        try checkMoveRejects(configuration)
        return makeRejectMovePlan(configuration)
    }

    /// Moves the sample's rejected photos and reports their outcomes (PRD P0-10).
    ///
    /// A photo whose stem matches the forced move failure stays in place once, with its Reject,
    /// so the sheet shows PRD "Partial move failure" and its retry. Every other ready set leaves
    /// the sample's photos and groups through the same update stream the real library publishes.
    func runRejectMove(_ plan: RejectMovePlan) async throws -> RejectMoveResult {
        try checkMoveRejects(plan.configuration)
        return simulateMove(plan.entries)
    }

    /// Retries only the sample sets an earlier move could not move (PRD P0-10).
    func retryFailedRejects(
        in batch: RejectMoveBatchID, excluding identities: Set<PhotoIdentity>
    ) async throws -> RejectMoveResult? {
        guard let entries = rejectMoveBatches[batch], !readOnly else { return nil }
        rejectMoveBatches[batch] = nil
        return simulateMove(entries.filter { !identities.contains($0.identity) })
    }

    /// The sample's progress steps for one run (PRD P0-10).
    ///
    /// A fresh stream per call keeps a retry from ending on the previous run's finished step.
    func rejectMoveProgress() async -> AsyncStream<RejectMoveProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: RejectMoveProgress.self)
        rejectMoveContinuation = continuation
        return stream
    }

    /// Refuses a disabled or read-only sample request before anything changes (PRD P0-10).
    private func checkMoveRejects(_ configuration: RejectMoveConfiguration) throws {
        guard configuration.isEnabled else { throw RejectMoveRefusal.disabled }
        guard !readOnly else {
            throw RejectMoveRefusal.readOnlyLocation(
                RejectMoveFailure(
                    reason: .readOnlyStorage,
                    message: "The sample library reports a read-only location."))
        }
    }

    /// Builds the sample plan with one ready set per rejected photo (PRD P0-10).
    private func makeRejectMovePlan(_ configuration: RejectMoveConfiguration) -> RejectMovePlan {
        let root = URL(fileURLWithPath: "/clove-test-library", isDirectory: true)
        let destination = root.appendingPathComponent(
            configuration.rejectsFolderName.rawValue, isDirectory: true)
        var sets: [ScannedPhotoSet] = []
        var entries: [RejectMovePlanEntry] = []
        for photo in stored where photo.marks.isRejected {
            guard let set = scannedSet(for: photo) else { continue }
            sets.append(set)
            let folder =
                set.id.relativeFolderPath.isEmpty
                ? destination
                : destination.appendingPathComponent(
                    set.id.relativeFolderPath, isDirectory: true)
            var files: [RejectMoveFilePlan] = []
            for file in set.photoSet.imageFiles {
                guard let role = set.photoSet.role(of: file) else { continue }
                let moveRole: RejectMoveFileRole =
                    switch role {
                    case .primary: .primary
                    case .jpegCompanion: .jpegCompanion
                    case .heifCompanion: .heifCompanion
                    }
                files.append(
                    RejectMoveFilePlan(
                        role: moveRole, source: file.url,
                        destination: folder.appendingPathComponent(file.url.lastPathComponent)))
            }
            if let sidecar = set.sidecar.resolvedURL ?? set.photoSet.sidecarURL {
                files.append(
                    RejectMoveFilePlan(
                        role: .sidecar, source: sidecar,
                        destination: folder.appendingPathComponent(sidecar.lastPathComponent)))
            }
            entries.append(
                .ready(
                    RejectMoveSetPlan(
                        identity: set.id, relativeFolderPath: set.id.relativeFolderPath,
                        destinationFolder: folder, files: files)))
        }
        return RejectMovePlan(
            rootURL: root, configuration: configuration, sets: sets, entries: entries,
            destinationURL: destination)
    }

    /// The sample's in-memory set behind one photo, with its companions and packet (P0-10).
    private func scannedSet(for photo: GridPhoto) -> ScannedPhotoSet? {
        let root = URL(fileURLWithPath: "/clove-test-library", isDirectory: true)
        let folder =
            photo.id.relativeFolderPath.isEmpty
            ? root
            : root.appendingPathComponent(photo.id.relativeFolderPath, isDirectory: true)
        let stem = (photo.fileName as NSString).deletingPathExtension
        let companions = TestLibrary.sampleCompanions[photo.id]
        let sidecar = folder.appendingPathComponent("\(stem).xmp")
        guard
            let set = try? PhotoSet(
                folderID: photo.id.folderID, relativeFolderPath: photo.id.relativeFolderPath,
                rawURL: folder.appendingPathComponent("\(stem).ARW"),
                jpegURL: companions?.hasJPEG == true
                    ? folder.appendingPathComponent("\(stem).JPG") : nil,
                heifURL: companions?.hasHEIF == true
                    ? folder.appendingPathComponent("\(stem).HIF") : nil,
                sidecarURL: sidecar)
        else { return nil }
        let images = set.imageFiles.map { file in
            ScannedImageFile(file: file, size: nil, modificationDate: nil)
        }
        return ScannedPhotoSet(photoSet: set, sidecar: .resolved(sidecar), imageFiles: images)
    }

    /// Simulates one run, publishing progress and the photos that left the sample (P0-10).
    private func simulateMove(_ entries: [RejectMovePlanEntry]) -> RejectMoveResult {
        var outcomes: [RejectMoveOutcome] = []
        var moved: Set<PhotoIdentity> = []
        for entry in entries {
            rejectMoveContinuation?.yield(.setStarted(entry.identity))
            let outcome = simulateMove(entry)
            outcomes.append(outcome)
            if case .moved(let set) = outcome { moved.insert(set.identity) }
            rejectMoveContinuation?.yield(.setFinished(outcome))
        }
        if !moved.isEmpty {
            stored.removeAll { moved.contains($0.id) }
            changes = changes.filter { !moved.contains($0.key) }
            updateGroupsAfterMove(moved)
            updateContinuation.yield(.photos([]))
        }
        let result = RejectMoveResult(id: RejectMoveBatchID(), outcomes: outcomes)
        let failed = Set(result.failed.map(\.identity))
        let retryable = entries.filter { failed.contains($0.identity) }
        if !retryable.isEmpty { rejectMoveBatches[result.id] = retryable }
        rejectMoveContinuation?.yield(.finished(result))
        rejectMoveContinuation = nil
        return result
    }

    /// Simulates one entry, failing the requested stem's first attempt (PRD P0-10).
    private func simulateMove(_ entry: RejectMovePlanEntry) -> RejectMoveOutcome {
        switch entry {
        case .ready(let plan):
            if let failingMoveStemSuffix,
                plan.identity.stem.hasSuffix(failingMoveStemSuffix),
                alreadyFailedMoves.insert(plan.identity).inserted
            {
                return .failed(
                    RejectMoveFailedSet(
                        identity: plan.identity,
                        failure: RejectMoveFailure(
                            reason: .notConfirmed,
                            message: "The sample library was told to fail this move."),
                        files: plan.files))
            }
            return .moved(
                RejectMoveMovedSet(
                    identity: plan.identity, files: plan.files, removedStoredReject: true,
                    staleRejectRecord: nil))
        case .refused(let identity, let refusal):
            guard let failure = refusal.failure else {
                return .skipped(
                    RejectMoveSkippedSet(
                        identity: identity, reason: .insideRejectsFolder,
                        message: "The photo set is already inside the rejects folder."))
            }
            return .failed(
                RejectMoveFailedSet(identity: identity, failure: failure, files: []))
        }
    }

    /// Drops moved photos from the sample's groups, keeping grouping's two-photo minimum.
    private func updateGroupsAfterMove(_ moved: Set<PhotoIdentity>) {
        func remaining(_ groups: [BrowsingGroup]) -> [BrowsingGroup] {
            groups.compactMap { group in
                let members = group.members.filter { !moved.contains($0) }
                return members.count >= 2 ? BrowsingGroup(id: group.id, members: members) : nil
            }
        }
        let next = remaining(groups)
        allGroups = remaining(allGroups)
        guard next != groups else { return }
        groups = next
        updateContinuation.yield(.groups(next))
    }

    /// The latest change to one photo with its save state (PRD P0-08).
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { changes[photo] }

    // MARK: - In-group culling

    /// Runs one finishing action's plan through the sample's own mark call (PRD P0-12).
    ///
    /// The sample has no write queue, so it applies the plan's still-allowed changes itself and
    /// reports the same result shape the real library returns
    /// (``GroupFinishingResult/applied(_:changes:statuses:undo:)``). The changes are re-checked
    /// against the marks the sample holds now through C10's own rule, so a photo rated or labelled
    /// after the screen built its plan is never rejected and its rating is never overwritten
    /// (PRD P0-12; ``GroupFinishingPlan/changesAllowed(currentMarks:)``). An unavailable plan
    /// writes nothing and records no completion, exactly like the executor (PRD In-group culling,
    /// finishing actions).
    func runGroupFinishing(_ plan: GroupFinishingPlan) async -> GroupFinishingResult {
        let changes = plan.changesAllowed { self.marks(for: $0) }
        guard plan.availability.isAvailable else {
            return GroupFinishingResult.applied(plan, changes: changes, statuses: [:])
        }
        await groupCompletion.recordFinishingAction(on: plan.groupID)
        var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in changes {
            statuses[change.photo] = await apply(change.change, to: change.photo)
        }
        return GroupFinishingResult.applied(plan, changes: changes, statuses: statuses)
    }

    /// Sends the finishing action's failed changes again, and only those (PRD P0-09).
    func retryGroupFinishing(_ result: GroupFinishingResult) async -> GroupFinishingResult {
        var statuses: [PhotoIdentity: MarkChangeStatus] = [:]
        for outcome in result.outcomes { statuses[outcome.photo] = outcome.status }
        for outcome in result.outcomes where outcome.status.state.isUnfinished {
            // A retry applies the same requested marks; the sample's marks still allow them or the
            // change would have been dropped when the action ran (PRD P0-12).
            statuses[outcome.photo] = await apply(outcome.change.change, to: outcome.photo)
        }
        return GroupFinishingResult.applied(
            result.plan, changes: result.undo.entries, statuses: statuses, undo: result.undo)
    }

    /// The marks the sample holds for one photo right now, for a finishing action's re-check
    /// (PRD P0-12).
    private func marks(for photo: PhotoIdentity) -> PhotoMarks {
        stored.first { $0.id == photo }?.marks ?? PhotoMarks()
    }

    /// Whether the sample's group is complete, and where the group view goes next (PRD P0-12).
    func groupCompletion(
        for groupID: GroupID, behaviour: GroupCompletionBehaviour
    ) async -> GroupViewCompletion {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for photo in stored { marks[photo.id] = photo.marks }
        return await groupCompletion.viewCompletion(
            after: groupID, in: groups, behaviour: behaviour, marks: marks)
    }

    /// Turns the sample's groups on or off through the same call the settings screen makes
    /// (PRD P0-11).
    ///
    /// The sample publishes the change through its stream, so the UI test exercises the whole
    /// path — store, model, library and grid — without a folder, a fixture or a permission.
    func setSimilarGroupsEnabled(_ enabled: Bool) async {
        let published = enabled ? allGroups : []
        guard published != groups else { return }
        groups = published
        updateContinuation.yield(.groups(published))
    }

    /// The sample: 36 photos across two capture folders, a few marks, two bursts, two sets with
    /// reference companions and one unreadable file (PRD P0-03, PRD Grid, PRD Scan scope).
    static var sample: TestLibrary { makeSample(failingStemSuffix: nil) }

    /// The sample with the launch's forced write and move failures (PRD P0-09, P0-10).
    static func sample(
        failingStemSuffix suffix: String?,
        failingMoveStemSuffix moveSuffix: String? = nil,
        readOnly: Bool = false
    ) -> TestLibrary {
        makeSample(
            failingStemSuffix: suffix, failingMoveStemSuffix: moveSuffix, readOnly: readOnly)
    }

    /// Builds the sample, keeping the forced failures and read-only location when asked.
    private static func makeSample(
        failingStemSuffix: String?, failingMoveStemSuffix: String? = nil,
        readOnly: Bool = false
    ) -> TestLibrary {
        let captureBase = Date(timeIntervalSince1970: 1_760_000_000)
        let photos = (0..<36).map { index -> GridPhoto in
            let number = 2678 + index
            let stem = String(format: "MMQ%05d", number)
            return GridPhoto(
                id: samplePhoto(number),
                fileName: "\(stem).ARW",
                time: .known(
                    PhotoTime(
                        captureTime: captureBase.addingTimeInterval(Double(index) * 4),
                        hasUTCOffset: true)),
                marks: sampleMarks[index])
        }
        return TestLibrary(
            photos: photos, groups: sampleGroups, changes: sampleChanges,
            failingStemSuffix: failingStemSuffix,
            failingMoveStemSuffix: failingMoveStemSuffix, readOnly: readOnly,
            detailImages: sampleDetailImages)
    }

    /// Two bursts from the sample, so the grid offers a group view (PRD P0-11).
    ///
    /// The first burst skips 2680: the UI test's group flow and its batch flow run in one launch
    /// and the batch flow forces one stem-0 photo to fail its first write, so the two flows must
    /// not write the same photo (PRD P0-09).
    private static var sampleGroups: [BrowsingGroup] {
        [
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2678"),
                members: [samplePhoto(2678), samplePhoto(2679), samplePhoto(2681)]),
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2696"),
                members: samplePhotos(2696...2698)),
        ]
    }

    /// The save states the sample starts with (PRD P0-08).
    ///
    /// One photo starts failed, with the requested change kept, so the save state has a failure to
    /// show and U7 has a change to retry.
    private static var sampleChanges: [MarkChangeStatus] {
        [
            MarkChangeStatus(
                id: MarkChangeID(),
                identity: samplePhoto(2679),
                requested: .rating(stars(4)),
                state: .failed(
                    MarkWriteFailure(
                        reason: .notConfirmed,
                        message: "The sample sidecar did not read back.")))
        ]
    }

    /// Identities of the sample photos for the given stems, in ascending order.
    private static func samplePhotos(_ numbers: ClosedRange<Int>) -> [PhotoIdentity] {
        numbers.map(samplePhoto)
    }

    /// The sample photo with one number, in its capture folder.
    private static func samplePhoto(_ number: Int) -> PhotoIdentity {
        PhotoIdentity(
            folderID: sampleFolderKey,
            relativeFolderPath: number < 2696 ? "DCIM/100CAM" : "DCIM/101CAM",
            stem: String(format: "MMQ%05d", number))
    }

    /// A few saved marks, so the flow has something to show (PRD P0-05).
    private static let sampleMarks: [PhotoMarks] = {
        var marks = Array(repeating: PhotoMarks(), count: 36)
        marks[0] = PhotoMarks(rating: stars(5), label: ColourLabel(colour: .red))
        marks[1] = PhotoMarks(rating: stars(3), isRejected: true)
        marks[4] = PhotoMarks(label: ColourLabel(colour: .green))
        marks[7] = PhotoMarks(isRejected: true)
        marks[21] = PhotoMarks(rating: stars(2), label: ColourLabel(colour: .purple))
        return marks
    }()

    /// The reference companions two sample RAW sets carry, so the grid's badge shows both its
    /// shapes: JPEG alone and JPEG with HIF (PRD Grid).
    private static var sampleCompanions: [PhotoIdentity: GridCompanions] {
        [
            samplePhoto(2680): GridCompanions(hasJPEG: true),
            samplePhoto(2695): GridCompanions(hasJPEG: true, hasHEIF: true),
        ]
    }

    /// A rating for the sample, which only uses values the camera's 0–5 range holds (PRD P0-05).
    private static func stars(_ count: Int) -> Rating {
        guard let rating = Rating(rawValue: count) else {
            preconditionFailure("a sample rating must be within 0–5")
        }
        return rating
    }
}
