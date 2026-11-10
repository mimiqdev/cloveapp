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
        return sample(
            failingStems: stems,
            failureReason: forcedFailureReason(named: environment[forcedFailureReasonVariable]),
            locationLoss: locationLoss(named: environment[locationLossVariable]),
            drainDelay: Duration.milliseconds(
                Int(environment[drainDelayVariable] ?? "") ?? 0))
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
    private let allGroups: [BrowsingGroup]

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

    /// The stem suffixes whose photos fail their first write (PRD P0-08).
    private let failingStems: [String]

    /// The reason a forced failure reports, so a test can show any PRD row (PRD P0-08).
    private let failureReason: MarkWriteFailureReason

    /// The photos whose forced failure already happened, so a retry saves them (PRD P0-08).
    private var alreadyFailed: Set<PhotoIdentity> = []

    /// How long the sample's write drain takes, so a UI test can see the waiting state
    /// (PRD P0-08).
    private let drainDelay: Duration

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
        changes = [:]
        failingStems = []
        failureReason = .notConfirmed
        drainDelay = .zero
        thumbnails = SampleGridThumbnails()
        detailImages = EmptyDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
    }

    /// A fixed library, for the sample below and the previews.
    init(
        photos: [GridPhoto],
        groups: [BrowsingGroup],
        changes: [MarkChangeStatus] = [],
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
        var byPhoto: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in changes { byPhoto[change.identity] = change }
        self.changes = byPhoto
        self.failingStems = failingStems.map { $0.lowercased() }
        self.failureReason = failureReason
        self.drainDelay = drainDelay
        thumbnails = TestLibrary.sampleThumbnails
        self.detailImages = detailImages ?? SampleDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
        // The stream buffers these until the model starts reading it, so the sample opens with
        // the save states and the loss it was built with (PRD P0-08, P0-02).
        for change in changes { updateContinuation.yield(.change(change)) }
        if let locationLoss {
            updateContinuation.yield(
                .locationLost(
                    folder: folder, loss: FolderLocationLoss(reason: locationLoss, date: Date()),
                    generation: openGeneration))
        }
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
        if shouldFailFirstWrite(to: photo) {
            // PRD How marks reach disk, rule 8: the requested marks stay for a retry and are not
            // painted onto the photo, so nothing unconfirmed appears as saved.
            let status = MarkChangeStatus(
                id: MarkChangeID(), identity: photo, requested: change,
                state: .failed(
                    MarkWriteFailure(
                        reason: failureReason,
                        message: "The sample library's forced failure.")))
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

    /// The latest change to one photo with its save state (PRD P0-08).
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { changes[photo] }

    /// Resends the photo's latest failed change, which the sample then saves (PRD P0-08).
    ///
    /// A forced failure happens once per photo, so Retry confirms the change the way C4's queue
    /// does after the condition that broke the write is gone; a change that did not fail is left
    /// alone, and a superseded one is never resurrected (PRD How marks reach disk, rule 8).
    func retryLatestChange(for photo: PhotoIdentity) async -> MarkChangeStatus? {
        guard let status = changes[photo], status.state.failure != nil else {
            return changes[photo]
        }
        // C4's retry re-admits the same change, so the sample publishes the same identity moving
        // back to pending before the write lands; the merge rule accepts that one backward move.
        let pending = MarkChangeStatus(
            id: status.id, identity: photo, requested: status.requested, state: .pending)
        changes[photo] = pending
        updateContinuation.yield(.change(pending))
        return await apply(status.requested, to: photo)
    }

    /// Reports the sample folder's location gone, as C11's watch does (PRD P0-02).
    func reportLocationLoss(_ reason: FolderLocationLoss.Reason) {
        updateContinuation.yield(
            .locationLost(
                folder: folder, loss: FolderLocationLoss(reason: reason, date: Date()),
                generation: openGeneration))
    }

    /// Waits for the sample's writes; a launch can make this take long enough to see
    /// (PRD Failure and recovery).
    func drainWrites() async {
        guard drainDelay > .zero else { return }
        try? await Task.sleep(for: drainDelay)
    }

    /// Whether a change is still unfinished, so Wait for writes keeps the question
    /// (PRD P0-08).
    func hasUnfinishedWrites() async -> Bool {
        changes.values.contains { $0.state.isUnfinished }
    }

    /// Closes the sample folder, so leaving with unfinished writes really drops its photos
    /// (PRD P0-08).
    func closeFolder() async {
        stored = []
        groups = []
        changes = [:]
        openGeneration += 1
        updateContinuation.yield(.photos([]))
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
    static var sample: TestLibrary { sample() }

    /// The sample, optionally with forced write failures and a lost location (PRD P0-08, P0-02).
    static func sample(
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
            photos: photos, groups: sampleGroups, changes: sampleChanges,
            detailImages: sampleDetailImages, failingStems: failingStems,
            failureReason: failureReason, locationLoss: locationLoss, drainDelay: drainDelay)
    }

    /// Two bursts from the sample, so the grid offers a group view (PRD P0-11).
    private static var sampleGroups: [BrowsingGroup] {
        [
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2678"),
                members: samplePhotos(2678...2680)),
            BrowsingGroup(
                id: GroupID(rawValue: "burst-2696"),
                members: samplePhotos(2696...2698)),
        ]
    }

    /// The save states the sample starts with (PRD P0-08).
    ///
    /// One photo starts saved, so the indicator's normal reading is **All saved** and a launch
    /// that forces a failure can watch it come back to that. The requested marks are kept on the
    /// status so a failure made in the sample has something to retry (PRD How marks reach disk,
    /// rule 8).
    private static var sampleChanges: [MarkChangeStatus] {
        [
            MarkChangeStatus(
                id: MarkChangeID(),
                identity: samplePhoto(2679),
                requested: .rating(stars(3)),
                state: .savedInSidecar)
        ]
    }

    /// Whether this photo's first write should fail, and records that it did (PRD P0-08).
    private func shouldFailFirstWrite(to photo: PhotoIdentity) -> Bool {
        guard !alreadyFailed.contains(photo),
            failingStems.contains(where: { photo.stem.hasSuffix($0) })
        else { return false }
        alreadyFailed.insert(photo)
        return true
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
