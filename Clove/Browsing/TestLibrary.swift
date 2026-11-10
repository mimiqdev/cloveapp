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
        return sample(failingStemSuffix: environment[forcedFailureVariable])
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
    let groups: [BrowsingGroup]

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

    /// The stem suffix whose photos fail their first write, or nil when none does (PRD P0-09).
    private let failingStemSuffix: String?

    /// The photos whose forced failure already happened, so a retry saves them (PRD P0-09).
    private var alreadyFailed: Set<PhotoIdentity> = []

    /// The batches this library applied, so a retry touches only their failed photos
    /// (PRD P0-09).
    private var batches: [MarkBatchID: [BatchMarkItem]] = [:]

    /// The folder's photos with their marks, in the sample's capture order (PRD P0-03).
    var photos: [GridPhoto] { stored }

    /// An empty library: no folder holds anything until entry opens one.
    init() {
        folder = TestLibrary.emptyFolderKey
        stored = []
        groups = []
        changes = [:]
        failingStemSuffix = nil
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
        detailImages: (any DetailImageSource)? = nil
    ) {
        folder = TestLibrary.sampleFolderKey
        stored = photos
        self.groups = groups
        var byPhoto: [PhotoIdentity: MarkChangeStatus] = [:]
        for change in changes { byPhoto[change.identity] = change }
        self.changes = byPhoto
        self.failingStemSuffix = failingStemSuffix
        thumbnails = TestLibrary.sampleThumbnails
        self.detailImages = detailImages ?? SampleDetailImages()
        (updates, updateContinuation) = AsyncStream.makeStream(of: FolderLibraryUpdate.self)
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

    /// The latest change to one photo with its save state (PRD P0-08).
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? { changes[photo] }

    /// The sample: 36 photos across two capture folders, a few marks, two bursts, two sets with
    /// reference companions and one unreadable file (PRD P0-03, PRD Grid, PRD Scan scope).
    static var sample: TestLibrary { makeSample(failingStemSuffix: nil) }

    /// The sample with the launch's forced write failure (PRD P0-09).
    static func sample(failingStemSuffix suffix: String?) -> TestLibrary {
        makeSample(failingStemSuffix: suffix)
    }

    /// Builds the sample, keeping the forced failure when the launch asked for one.
    private static func makeSample(failingStemSuffix: String?) -> TestLibrary {
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
            failingStemSuffix: failingStemSuffix, detailImages: sampleDetailImages)
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
