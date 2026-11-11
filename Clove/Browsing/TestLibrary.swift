import CloveCore
import CloveImaging
import Foundation

/// The in-memory library the UI test and previews browse (PRD P0-08, P0-13).
///
/// It stands in for folder access, the scan, the order and the atomic C4 write until U2 and U3
/// replace the ``FolderLibrary`` seam. It holds one fake folder with a few dozen photos, some
/// marks, two groups and the save state of each change it receives, and writes nothing anywhere.
///
/// The sample is selected with the launch environment value ``launchVariable``; without it the
/// app browses an empty library and entry says no folder is open. Launch values can also force a
/// write failure on chosen photos with a chosen reason, slow the write drain, and report the
/// folder's location gone, so the UI test drives the PRD's failure and recovery copy without a
/// file, a fixture or a permission.
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

    /// The launch environment value that makes the first write to named photos fail (PRD P0-08).
    ///
    /// Its value is a comma-separated list of stem suffixes. A photo whose stem ends with one of
    /// them reports one failed change and keeps the marks it had, and the next write saves it, so
    /// a UI test drives PRD Failure and recovery's single-photo row without a file or a
    /// permission.
    static let forcedFailureStemsVariable = "CLOVE_TEST_LIBRARY_FAIL_STEMS"

    /// The launch environment value that chooses the forced failure's reason (PRD P0-08).
    ///
    /// Values are `permission`, `location`, `readOnly`, `space` and `write`. A write that cannot
    /// be confirmed is the default, so the PRD's single-photo row appears without a hardware
    /// fault.
    static let forcedFailureReasonVariable = "CLOVE_TEST_LIBRARY_FAIL_REASON"

    /// The launch environment value that slows the sample's write drain, in milliseconds
    /// (PRD P0-08).
    ///
    /// A UI test can then see the leaving question's waiting state instead of a drain that
    /// finishes within one frame.
    static let drainDelayVariable = "CLOVE_TEST_LIBRARY_DRAIN_DELAY_MS"

    /// The launch environment value that makes the sample report its folder's location gone
    /// (PRD P0-02).
    ///
    /// Values are `drive` for an external volume that disconnected and `location` for a folder
    /// that cannot be found. The sample publishes C11's loss on its update stream, so the grid
    /// shows the PRD's copy and recovery action without a drive or a permission.
    static let locationLossVariable = "CLOVE_TEST_LIBRARY_LOCATION_LOSS"

    /// The library this launch browses: the sample when the launch value asks for it (PRD P0-13).
    static func forLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any FolderLibrary {
        guard environment[launchVariable] == "1" else { return TestLibrary() }
        let stems = (environment[forcedFailureStemsVariable] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let library = sample(
            failingMoveStemSuffix: environment[forcedMoveFailureVariable],
            readOnly: environment[readOnlyVariable] == "1",
            failingStems: stems,
            failureReason: forcedFailureReason(named: environment[forcedFailureReasonVariable]),
            locationLoss: locationLoss(named: environment[locationLossVariable]),
            drainDelay: Duration.milliseconds(
                Int(environment[drainDelayVariable] ?? "") ?? 0))
        library.writeDelay = .milliseconds(
            min(10_000, max(0, Int(environment["CLOVE_TEST_LIBRARY_WRITE_DELAY_MS"] ?? "") ?? 0)))
        library.disconnectsOnWrite = environment["CLOVE_TEST_LIBRARY_DISCONNECT_ON_WRITE"] == "1"
        library.installPresentationSamples(environment: environment)
        return library
    }

    /// A fixed synthetic Recents UUID so sample scenes and photo identities share one folder.
    static let sampleFolderKey = FolderIdentity(rawValue: sampleRecentID(1).uuidString)

    private static func sampleRecentID(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }

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

    /// Made-up Recents exercise the resume, Done and Reconnect layouts (handoff Entry).
    var recents: [RecentFolder] {
        guard folder == Self.sampleFolderKey else { return [] }
        let date = Date().addingTimeInterval(-86_400)
        return [
            RecentFolder(
                id: Self.sampleRecentID(1), bookmark: Data(),
                pathSummary: "/Shoots/Coastal light", volumeName: "Field Drive",
                mediaType: .externalDrive,
                photoCount: stored.count, scanStatus: .complete, lastOpened: date,
                progress: FolderProgress(
                    confirmedMarks: stored.map(\.marks), isComplete: true,
                    lastViewedPhoto: stored.first?.id,
                    previewPhotos: Array(stored.prefix(3).map(\.id)))),
            RecentFolder(
                id: Self.sampleRecentID(2), bookmark: Data(),
                pathSummary: "/Documents/Studio", mediaType: .internalVolume, photoCount: 96,
                scanStatus: .complete, lastOpened: date.addingTimeInterval(-86_400),
                progress: FolderProgress(
                    marked: 80, rejected: 16, total: 96,
                    previewPhotos: Array(stored.suffix(3).map(\.id)))),
            RecentFolder(
                id: Self.sampleRecentID(3), bookmark: Data(),
                pathSummary: "/Shoots/Backup card", volumeName: "Travel Card",
                mediaType: .externalDrive,
                lastOpened: date.addingTimeInterval(-172_800), needsReconnect: true),
        ]
    }

    func entryThumbnail(for photo: PhotoIdentity) async -> GridThumbnailOutcome {
        await thumbnails.thumbnail(for: photo, priority: .visible)
    }

    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? {
        guard recent.identity == folder else { return .unknownRecent(recent.id) }
        if let sampleLocationLoss { reportLocationLoss(sampleLocationLoss) }
        return nil
    }

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

    /// The stem suffix U4's launch value names, whose photos fail their first write (PRD P0-09).
    /// The sample's finishing-action records, so a group it finishes counts as complete like the
    /// real session's (PRD In-group culling, group completion; PRD P0-12).

    /// The stem suffixes whose photos fail their first write (PRD P0-08).
    private let failingStems: [String]

    /// The reason a forced failure reports, so a test can show any PRD row (PRD P0-08).
    private let failureReason: MarkWriteFailureReason

    /// The photos whose forced failure already happened, so a retry saves them (PRD P0-08, P0-09).
    private var alreadyFailed: Set<PhotoIdentity> = []

    /// The photos whose forced move failure already happened, so a retry moves them (P0-10).
    private var alreadyFailedMoves: Set<PhotoIdentity> = []

    /// The stem suffix whose rejected photos fail their first move, or nil when none does
    /// (PRD P0-10).
    private let failingMoveStemSuffix: String?

    /// Whether this sample refuses Move rejects as a read-only location (PRD P0-10).
    private let readOnly: Bool

    private var movedPhotoRecords: [RejectMoveBatchID: [GridPhoto]] = [:]

    /// The progress stream the move sheet reads while a sample move runs (PRD P0-10).
    ///
    /// Each run gets its own stream, so a retry never reads the earlier run's finished step.
    private var rejectMoveContinuation: AsyncStream<RejectMoveProgress>.Continuation?

    /// How long the sample's write drain takes, so a UI test can see the waiting state
    /// (PRD P0-08).
    private let drainDelay: Duration
    private var writeDelay: Duration = .zero
    private var disconnectsOnWrite = false
    private let sampleLocationLoss: FolderLocationLoss.Reason?

    /// The open this sample library installed last, which ``closeFolder()`` changes (PRD P0-02).
    private(set) var openGeneration = 0

    /// The folder's photos with their marks, in the sample's capture order (PRD P0-03).
    var photos: [GridPhoto] { stored }

    /// An empty library: no folder holds anything until entry opens one.
    init() {
        folder = TestLibrary.emptyFolderKey
        stored = []
        groups = []
        allGroups = []
        failingMoveStemSuffix = nil
        readOnly = false
        failingStems = []
        failureReason = .notConfirmed
        drainDelay = .zero
        sampleLocationLoss = nil
        thumbnails = SampleGridThumbnails()
        detailImages = EmptyDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
    }

    /// A fixed library, for the sample below and the previews.
    init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        failingMoveStemSuffix: String? = nil,
        readOnly: Bool = false,
        detailImages: (any DetailImageSource)? = nil,
        failingStems: [String] = [],
        failureReason: MarkWriteFailureReason = .notConfirmed,
        locationLoss: FolderLocationLoss.Reason? = nil,
        drainDelay: Duration = .zero
    ) {
        folder = TestLibrary.sampleFolderKey
        stored = photos
        self.groups = groups
        allGroups = groups
        self.failingMoveStemSuffix = failingMoveStemSuffix
        self.readOnly = readOnly
        self.failingStems = failingStems.map { $0.lowercased() }
        self.failureReason = failureReason
        self.drainDelay = drainDelay
        self.sampleLocationLoss = locationLoss
        thumbnails = TestLibrary.sampleThumbnails
        self.detailImages = detailImages ?? SampleDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        if let locationLoss {
            updateContinuation.yield(
                .locationLost(
                    folder: folder, loss: FolderLocationLoss(reason: locationLoss, date: Date()),
                    generation: openGeneration))
        }
        // The sample is fully scanned when it opens, so the grid can show the actions the
        // handoff hides during opening (design handoff, PRD P0-01).
        updateContinuation.yield(.scanStarted)
        updateContinuation.yield(
            .scanFinished(
                FolderScanSummary(photoCount: stored.count, status: .complete)))
    }

    /// Applies one bar action's per-photo changes as one batch (PRD P0-09).
    ///
    /// Each photo is written on its own, the way C4's batch admits each set: a photo the launch
    /// forced to fail keeps its marks and reports a failure, while the others take the change.
    /// Per-photo states go through the same stream as a single change, and the batch's handle
    /// retries only the photos that did not save.
    func apply(_ items: [BatchMarkItem]) async -> MarkBatchResult {
        let ids = items.map { _ in MarkChangeID() }
        if writeDelay > .zero { try? await Task.sleep(for: writeDelay) }
        if disconnectsOnWrite {
            reportLocationLoss(.externalVolumeDisconnected)
            return MarkBatchResult(
                id: MarkBatchID(), change: items.first?.change ?? MarkChange(),
                outcomes: zip(items, ids).map { item, id in
                    MarkChangeStatus(
                        id: id, identity: item.photo, requested: item.change,
                        state: .failed(
                            MarkWriteFailure(
                                reason: .locationUnavailable, message: "The drive disconnected.")))
                })
        }
        var outcomes: [MarkChangeStatus] = []
        for (item, id) in zip(items, ids) {
            let status = perform(item.change, for: item.photo, id: id)
            outcomes.append(status)
        }
        let batch = MarkBatchID()
        return MarkBatchResult(
            id: batch, change: items.first?.change ?? MarkChange(), outcomes: outcomes)
    }

    /// Applies one change to one photo and reports the state C4 would (PRD P0-08).
    ///
    /// A forced failure leaves the sample's stored marks untouched. Nothing is written to disk.
    private func perform(
        _ change: MarkChange, for photo: PhotoIdentity, id: MarkChangeID
    ) -> MarkChangeStatus {
        guard !change.isEmpty else {
            // C4's queue refuses a request that names no marks and records nothing.
            return MarkChangeStatus(
                id: id, identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .unknown,
                        message: "The change names no marks, so nothing was written.")))
        }
        guard let index = stored.firstIndex(where: { $0.id == photo }) else {
            return MarkChangeStatus(
                id: id, identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: .locationUnavailable,
                        message: "The sample library does not hold this photo.")))
        }
        if shouldFailFirstWrite(to: photo) {
            // The model reads the sample's unchanged marks after this failure.
            let status = MarkChangeStatus(
                id: id, identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: forcedFailureReason(for: photo),
                        message: "The sample library's forced failure.")))
            return status
        }
        let marks = stored[index].marks.applying(change)
        stored[index].marks = marks

        let state: MarkChangeState = .savedInSidecar
        let status = MarkChangeStatus(
            id: id, identity: photo, requested: change, state: state)
        // The sample publishes through the same stream as the real library, so every verify
        // exercises the model's update path (PRD P0-08, P0-13).
        updateContinuation.yield(.reads(times: [:], marks: [photo: marks]))
        return status
    }

    // MARK: - Move rejects

    /// Plans Move rejects from the sample's rejected photos (PRD P0-10).
    ///
    /// The plan is built in memory from the sample's marks, so the sheet shows the same counts,
    /// companions, XMP files and folder name the real plan would, without checking or touching a
    /// file. A read-only sample refuses the whole request, as PRD P0-10 requires.
    func planRejectMove(
        configuration: RejectMoveConfiguration, rejected: [PhotoIdentity]
    ) async throws -> RejectMovePlan {
        try checkMoveRejects(configuration)
        return makeRejectMovePlan(configuration, rejected: Set(rejected))
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

    func undoRejectMove(
        _ entry: RejectMoveUndoEntry, currentMarks: [PhotoIdentity: PhotoMarks],
        restoring edits: [DesiredMarkEdit]
    ) async throws -> RejectMoveUndoResult {
        guard let moved = movedPhotoRecords.removeValue(forKey: entry.batch) else {
            throw RejectMoveUndoRefusal.unknownBatch(entry.batch)
        }
        var outcomes: [RejectMoveUndoOutcome] = []
        for photo in moved {
            guard let set = scannedSet(for: photo) else { continue }
            stored.append(photo)
            let status = perform(.rating(.rejected), for: photo.id, id: MarkChangeID())
            outcomes.append(
                .restored(
                    RejectMoveUndoRestoredPhoto(
                        identity: photo.id, set: set, files: [], keptInConfirmation: false,
                        rejectStoreFailure: status.state.failure.map {
                            RejectMoveFailure(classifying: $0)
                        })))
        }
        for kept in entry.keptPhotos {
            var target = kept.marksAfter
            target.rating = .rejected
            guard let current = currentMarks[kept.set.id],
                DesiredMarkRestore.change(
                    photo: kept.set.id, current: current, expected: kept.marksAfter,
                    target: target, fields: .rating(kept.marksAfter.rating)) != nil
            else {
                outcomes.append(.changedSince(kept.set.id))
                continue
            }
            let status = perform(.rating(.rejected), for: kept.set.id, id: MarkChangeID())
            outcomes.append(
                .restored(
                    RejectMoveUndoRestoredPhoto(
                        identity: kept.set.id, set: kept.set, files: [], keptInConfirmation: true,
                        rejectStoreFailure: status.state.failure.map {
                            RejectMoveFailure(classifying: $0)
                        })))
        }
        let restored = Set(
            outcomes.compactMap { outcome -> PhotoIdentity? in
                guard case .restored(let photo) = outcome, photo.isRejectStored else { return nil }
                return photo.identity
            })
        for edit in edits where restored.contains(edit.photo) {
            if let index = stored.firstIndex(where: { $0.id == edit.photo }) {
                stored[index].marks = edit.after
            }
        }
        updateContinuation.yield(.photos([]))
        return RejectMoveUndoResult(id: RejectMoveUndoBatchID(), outcomes: outcomes)
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
    private func makeRejectMovePlan(
        _ configuration: RejectMoveConfiguration, rejected: Set<PhotoIdentity>
    ) -> RejectMovePlan {
        let root = URL(fileURLWithPath: "/clove-test-library", isDirectory: true)
        let destination = root.appendingPathComponent(
            configuration.rejectsFolderName.rawValue, isDirectory: true)
        var sets: [ScannedPhotoSet] = []
        var entries: [RejectMovePlanEntry] = []
        for photo in stored where rejected.contains(photo.id) {
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

    /// Move undo resolves kept sample photos through the same identity-based seam as production.
    func scannedSet(for identity: PhotoIdentity) -> ScannedPhotoSet? {
        stored.first(where: { $0.id == identity }).flatMap { scannedSet(for: $0) }
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
    private func simulateMove(
        _ entries: [RejectMovePlanEntry], batchID: RejectMoveBatchID? = nil
    ) -> RejectMoveResult {
        var outcomes: [RejectMoveOutcome] = []
        var moved: Set<PhotoIdentity> = []
        for entry in entries {
            rejectMoveContinuation?.yield(.setStarted(entry.identity))
            let outcome = simulateMove(entry)
            outcomes.append(outcome)
            if case .moved(let set) = outcome { moved.insert(set.identity) }
            rejectMoveContinuation?.yield(.setFinished(outcome))
        }
        let id = batchID ?? RejectMoveBatchID()
        movedPhotoRecords[id, default: []].append(
            contentsOf: stored.filter { moved.contains($0.id) })
        if !moved.isEmpty {
            stored.removeAll { moved.contains($0.id) }
            updateGroupsAfterMove(moved)
            updateContinuation.yield(.photos([]))
        }
        let result = RejectMoveResult(id: id, outcomes: outcomes)
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

    /// Reports the sample folder's location gone, as C11's watch does (PRD P0-02).
    func reportLocationLoss(_ reason: FolderLocationLoss.Reason) {
        updateContinuation.yield(
            .locationLost(
                folder: folder, loss: FolderLocationLoss(reason: reason, date: Date()),
                generation: openGeneration))
    }

    func discardPendingChanges() async {}

    /// Waits for the sample's writes; a launch can make this take long enough to see
    /// (PRD Failure and recovery).
    func drainWrites() async {
        guard drainDelay > .zero else { return }
        try? await Task.sleep(for: drainDelay)
    }

    /// Closing a presentation leaves the sample's simulated files available to Reopen.
    func closeFolder() async {
        openGeneration += 1
    }

    /// Deterministic Info without a file or device path (handoff Detail).
    func information(for photo: PhotoIdentity) async -> PhotoInformation? {
        guard stored.contains(where: { $0.id == photo }) else { return nil }
        return PhotoInformation(
            image: ImageInformation(
                captureWallTime: Date(timeIntervalSince1970: 1_793_975_525.42),
                subseconds: "42", camera: "Sample camera", bodySerial: "0123",
                lens: "24–70 mm", exposureSeconds: 1.0 / 250, aperture: 2.8, iso: 400,
                focalLengthMillimetres: 35, fileSizeBytes: 45_100_000,
                pixelWidth: 8192, pixelHeight: 5464),
            relativeFolder: photo.relativeFolderPath,
            companions: Self.sampleCompanions[photo].map {
                [$0.hasJPEG ? "JPG" : nil, $0.hasHEIF ? "HIF" : nil].compactMap { $0 }
            } ?? [], usesSidecar: true)
    }

    /// Held presentation states for screenshots and short UI tests. Normal sample launches
    /// remain fully opened and saved. Values are read only when the test library is selected.
    private func installPresentationSamples(environment: [String: String]) {
        if let state = environment["CLOVE_TEST_LIBRARY_GROUP_STATE"],
            let group = groups.first, state == "unmarked" || state == "done"
        {
            for index in stored.indices where group.members.contains(stored[index].id) {
                stored[index].marks =
                    state == "done"
                    ? PhotoMarks(
                        rating: stored[index].id == group.members.first ? Self.stars(3) : .rejected)
                    : PhotoMarks()
            }
        }
        if let opening = environment["CLOVE_TEST_LIBRARY_OPENING"] {
            if opening == "reading" || opening == "empty" {
                updateContinuation.yield(.scanStarted)
                let firstPending = opening == "empty" ? 0 : 12
                for index in stored.indices where index >= firstPending {
                    stored[index].time = .pending
                }
                updateContinuation.yield(.photos(stored))
            } else if opening == "grouping" {
                updateContinuation.yield(.groupingActivity(true))
            }
        }
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

    /// Whether this photo's first write should fail, and records that it did (PRD P0-08, P0-09).
    private func shouldFailFirstWrite(to photo: PhotoIdentity) -> Bool {
        guard !alreadyFailed.contains(photo) else { return false }
        guard failingStems.contains(where: { photo.stem.hasSuffix($0) }) else { return false }
        alreadyFailed.insert(photo)
        return true
    }

    /// The forced failure's reason, which the named list can choose (PRD P0-08).
    private func forcedFailureReason(for photo: PhotoIdentity) -> MarkWriteFailureReason {
        failingStems.contains { photo.stem.hasSuffix($0) } ? failureReason : .notConfirmed
    }

    /// The forced failure's reason, by its launch value (PRD P0-08).
    private static func forcedFailureReason(named name: String?) -> MarkWriteFailureReason {
        switch name {
        case "permission": .permissionLost
        case "location": .locationUnavailable
        case "readOnly": .readOnlyStorage
        case "space": .insufficientSpace
        default: .notConfirmed
        }
    }

    /// The location loss the sample reports at launch, by its launch value (PRD P0-02).
    private static func locationLoss(named name: String?) -> FolderLocationLoss.Reason? {
        switch name {
        case "drive": .externalVolumeDisconnected
        case "location": .locationUnavailable
        default: nil
        }
    }

    /// The sample: 36 photos across two capture folders, a few marks, two bursts, two sets with
    /// reference companions and one unreadable file (PRD P0-03, PRD Grid, PRD Scan scope).
    static var sample: TestLibrary { sample() }

    /// The sample, with the launch's forced write and move failures, lost location and drain.
    ///
    /// The forced values keep the UI tests from needing files; the move failures and read-only
    /// switch cover PRD P0-10, while the write failures, loss and drain cover PRD P0-08 and P0-02.
    static func sample(
        failingMoveStemSuffix: String? = nil,
        readOnly: Bool = false,
        failingStems: [String] = [],
        failureReason: MarkWriteFailureReason = .notConfirmed,
        locationLoss: FolderLocationLoss.Reason? = nil,
        drainDelay: Duration = .zero
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
            photos: photos, groups: sampleGroups,
            failingMoveStemSuffix: failingMoveStemSuffix, readOnly: readOnly,
            detailImages: sampleDetailImages, failingStems: failingStems,
            failureReason: failureReason, locationLoss: locationLoss,
            drainDelay: drainDelay)
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
        marks[1] = PhotoMarks(rating: .rejected)
        marks[4] = PhotoMarks(label: ColourLabel(colour: .green))
        marks[7] = PhotoMarks(rating: .rejected)
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
