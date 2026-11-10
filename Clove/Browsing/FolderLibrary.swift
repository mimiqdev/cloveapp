import CloveCore
import Foundation

/// One change a library publishes while a folder is open (PRD P0-02, P0-03, P0-08).
///
/// The screens never poll the library: ``BrowsingModel`` consumes the one stream a library
/// publishes and keeps its own values current. A case that carries values lets a reader apply it
/// without reading the library again; a case that carries none only asks for a refresh.
enum FolderLibraryUpdate: Hashable, Sendable {
    /// The scan delivered photos, with their C8 values; their time is `.pending` until its read
    /// finishes, so the grid withholds them instead of showing a filename order (G1 decision 3).
    case photos([GridPhoto])

    /// What one batch's metadata and mark reads found (PRD P0-03, P0-05, P0-07).
    ///
    /// A photo's state can be ``PhotoTimeState/unavailable`` when its metadata read failed, and
    /// its marks combine its sidecar packet with Clove's stored marks. Sending one batch per scan
    /// batch keeps a reader from re-reading every photo once per file.
    case reads(times: [PhotoIdentity: PhotoTimeState], marks: [PhotoIdentity: PhotoMarks])

    /// The folder's scan finished with the count and completeness Recents shows (PRD P0-01,
    /// P0-02). A scan that could not read everything finishes as `.partial`.
    case scanFinished(FolderScanSummary)

    /// A change's save state moved (PRD P0-08).
    case change(MarkChangeStatus)

    /// Grouping published the folder's groups (PRD P0-11).
    ///
    /// The folder's first publication always arrives, even with no groups and with similar groups
    /// turned off, so a saved group view knows the wait is over (PRD P0-14); later publications
    /// carry a refinement or a Run again and only arrive when they changed something.
    case groups([BrowsingGroup])
}

/// What the browsing screens read and change, behind one seam (PRD P0-08, P0-13, P0-14).
///
/// Folder access (C11), the scan (C2), the order (C8), writes (C4) and grouping (C9) arrive with
/// U2 and U3. U2's library opens real folders and publishes its scan, metadata reads and write
/// transitions as one ``updates`` stream, which ``BrowsingModel`` consumes on the main actor;
/// the seam still speaks C4's `MarkChange` and `MarkChangeStatus`, so those tasks replace the
/// implementation without changing a screen or the shape of these calls.
@MainActor
protocol FolderLibrary: AnyObject {
    /// The open folder's durable key, never a path or a name (G1 folder access, PRD P0-01).
    ///
    /// A library with no folder open answers with its own placeholder key, which no saved state
    /// and no photo identity ever uses.
    var folder: FolderIdentity { get }

    /// The folder's photos with their marks, in any order: the browsing state orders and filters
    /// them through its C8 order and C1 marks (PRD P0-03).
    var photos: [GridPhoto] { get }

    /// The groups grouping published for the folder, empty when grouping is off (PRD P0-11).
    ///
    /// They arrive on ``updates`` as ``FolderLibraryUpdate/groups(_:)``; the first publication
    /// always lands, even when it is empty, so a saved group view knows the wait is over
    /// (PRD P0-14).
    var groups: [BrowsingGroup] { get }

    /// Runs similar groups again for the open folder without the group cache (PRD P0-11).
    ///
    /// PRD P0-11 keeps Run again beside the published groups: the current photos are grouped
    /// again and the result arrives on ``updates``. A library that cannot group does nothing.
    func runGroupingAgain() async

    /// Applies C12's similar-groups setting to the open folder (PRD P0-11).
    ///
    /// Off means no groups and no feature work; on publishes the cached or time-only result and
    /// refines again. The settings screen calls this one method; persistence stays with the
    /// settings store. A library that cannot group ignores it.
    func setSimilarGroupsEnabled(_ enabled: Bool) async

    /// The grid's window on the folder's files: preview pixels and companion badges by identity
    /// (PRD P0-03, G1 preview row).
    ///
    /// The grid reads this source, never the folder library, the scan or a file path. The real
    /// library answers with a source bound to the open folder's pipeline and C11 session; the
    /// test library answers with its generated tiles. A library that supplies none draws no tiles.
    var thumbnails: any GridThumbnailSource { get }

    /// The detail view's window on the folder's pixels (PRD P0-04, G1 "Preview, detail (I2)").
    ///
    /// One pipeline serves the open folder and is closed when the folder ends, so a quality
    /// change and the neighbours' prefetch share its cache without outliving C11's scope. The
    /// real library admits every read through that scope and answers unavailable for a photo
    /// from an earlier folder; the test library answers with its generated images.
    var detailImages: any DetailImageSource { get }

    /// The one stream of updates this library publishes while it is open (PRD P0-03, P0-08).
    ///
    /// It carries the scan's batches, the metadata reads that finish each photo's time, the mark
    /// reads and confirmed writes, the finished scan and every write-status transition, in the
    /// order they happen. ``BrowsingModel`` reads it on the main actor; the library keeps no
    /// second consumer.
    var updates: AsyncStream<FolderLibraryUpdate> { get }

    /// Applies one change and returns its status (PRD P0-08).
    ///
    /// The call is asynchronous because C4's `MarkWriteQueue.apply(_:to:)` is: the library
    /// resolves the identity to its scanned set and awaits the queue without changing this
    /// signature. A failed or unconfirmed write is reported by the returned status, never by
    /// throwing.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus

    /// The latest change to one photo with its save state (PRD P0-08).
    ///
    /// It answers from the library's current records, synchronously, so a screen can render it.
    /// C4's `MarkWriteQueue.latestChange(for:)` is actor-isolated, so the library keeps this
    /// answer in step with the statuses the queue streams; U7 reads the same status for its
    /// retry. Nil means nothing has been requested for the photo, not that everything is saved.
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus?

    /// Runs one finishing action's plan in the open folder session (PRD In-group culling,
    /// finishing actions; PRD P0-12).
    ///
    /// The plan is C10's, and C4's write queue is the only writer, so per-photo results, the
    /// partial-failure counts and a retry of only the failed items come from one place
    /// (PRD P0-09). A library whose folder cannot write reports the refused changes instead of
    /// claiming they were saved (PRD P0-08).
    func runGroupFinishing(_ plan: GroupFinishingPlan) async -> GroupFinishingResult

    /// Retries only the changes of one finishing action that still need it (PRD P0-09).
    ///
    /// Confirmed changes are left alone, so a retry can never repeat a successful write; the
    /// plan, the dropped photos and C5's undo record stay as they were (PRD P0-12).
    func retryGroupFinishing(_ result: GroupFinishingResult) async -> GroupFinishingResult

    /// Whether the group is complete, and where the group view goes next, following C12's
    /// setting (PRD In-group culling, group completion; PRD P0-12).
    ///
    /// The library owns the folder's completion records, so the view never derives a second
    /// rule; a folder that ended answers ``GroupViewCompletion/inProgress``.
    func groupCompletion(
        for groupID: GroupID, behaviour: GroupCompletionBehaviour
    ) async -> GroupViewCompletion

    /// The scanned set behind one photo, for writes, thumbnails and the grouping follow-up
    /// (PRD P0-08, P0-11).
    ///
    /// U3's grid resolves each cell's identity to the files I1 reads its preview from; C6's move
    /// and the grouping follow-up need the same answer. Nil means the folder no longer holds the
    /// photo.
    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet?

    /// Every remembered folder, most recently opened first (PRD P0-02).
    ///
    /// The list is a value the entry screen reads; ``reloadRecents()`` refreshes it from C11's
    /// store, so reading it never performs I/O on the main actor.
    var recents: [RecentFolder] { get }

    /// Why the Recents list could not be read, or nil when it could (PRD P0-02).
    ///
    /// PRD P0-02 asks for the problem to be explained instead of showing an empty list as if
    /// nothing had ever opened, so entry reports this next to the Recents list.
    var recentsFailure: FolderAccessFailure? { get }

    /// Re-reads C11's Recents list, keeping what the store holds (PRD P0-02).
    func reloadRecents() async

    /// Opens a folder chosen in the system picker and scans it (PRD P0-01).
    ///
    /// - Returns: nil when the folder opened, or C11's reason when it did not, which entry shows
    ///   inline and answers by asking for the folder again (PRD P0-02).
    func pick(_ url: URL) async -> FolderAccessFailure?

    /// Reopens one remembered folder and scans it (PRD P0-02).
    ///
    /// - Returns: nil when the folder opened, or C11's reason when it did not; the reason belongs
    ///   to that Recents item and is never reported as a silent failure.
    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure?

    /// Reopens the folder a saved scene names, for launch restore (PRD P0-02, P0-14).
    ///
    /// C11 validates a real read and the folder's identity keys before anything is scanned, so a
    /// remembered location that is gone, revoked or replaced comes back as
    /// ``FolderAvailability/unavailable(_:)`` with the reason entry explains.
    func openSavedFolder(_ folder: FolderIdentity) async -> FolderAvailability
}

extension FolderLibrary {
    /// What restore validation checks a saved state against (PRD P0-14).
    var contents: FolderContents {
        FolderContents(folder: folder, photos: photos.map(\.id), groups: groups)
    }

    /// A library with no folder access cannot open a picked or remembered folder; the reason
    /// asks for the folder again (PRD P0-02). The real library and the test library override
    /// the calls they support.
    var updates: AsyncStream<FolderLibraryUpdate> {
        AsyncStream { $0.finish() }
    }

    var thumbnails: any GridThumbnailSource { SampleGridThumbnails() }

    var detailImages: any DetailImageSource { EmptyDetailImages() }

    var recents: [RecentFolder] { [] }

    var recentsFailure: FolderAccessFailure? { nil }

    func reloadRecents() async {}

    func pick(_ url: URL) async -> FolderAccessFailure? { Self.noFolderAccess }

    func reopen(_ recent: RecentFolder) async -> FolderAccessFailure? { Self.noFolderAccess }

    /// A saved folder only reopens when it is the one this library already holds.
    func openSavedFolder(_ folder: FolderIdentity) async -> FolderAvailability {
        folder == self.folder ? .available(contents) : .unavailable(Self.noFolderAccess)
    }

    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? { nil }

    /// A library with no folder to write records no finishing action and completes no group
    /// (PRD In-group culling).
    func runGroupFinishing(_ plan: GroupFinishingPlan) async -> GroupFinishingResult {
        GroupFinishingResult.applied(plan, statuses: [:], undo: nil)
    }

    func retryGroupFinishing(_ result: GroupFinishingResult) async -> GroupFinishingResult {
        result
    }

    func groupCompletion(
        for groupID: GroupID, behaviour: GroupCompletionBehaviour
    ) async -> GroupViewCompletion {
        .inProgress
    }

    func runGroupingAgain() async {}

    func setSimilarGroupsEnabled(_ enabled: Bool) async {}

    /// The reason a library with no folder access gives, which asks for the folder again
    /// (PRD P0-02).
    private static var noFolderAccess: FolderAccessFailure {
        .locationUnavailable(FolderErrorChain(CocoaError(.fileNoSuchFile)))
    }
}
