import CloveCore
import Foundation
import Observation

/// The browsing state every screen reads and changes (PRD P0-13, P0-14).
///
/// The state belongs to this model, never to a view's `@State`, so the compact stack and the
/// split layout show the same folder, photo, filter, selection and group place when a fold, an
/// unfold or a resize changes the layout (PRD P0-14, G1 fold-state row). The model also keeps the
/// state in the shape CloveCore can validate and store, so a launch restores what it can and falls
/// back to entry for the rest.
///
/// The model is the only reader of the library's ``FolderLibrary/updates`` stream: entry's
/// Recents, the grid's photos and the save state all come from here, so no screen polls a
/// library or a write queue.
@MainActor
@Observable
final class BrowsingModel {
    /// The seam the screens read through: folder access, the scan, the order and writes.
    private let library: any FolderLibrary

    /// The scene's browsing state (PRD P0-14).
    private(set) var state: BrowsingState

    /// Why entry must ask for the saved folder again, or nil (PRD P0-02).
    ///
    /// This is the last open that is not tied to a Recents item, such as a pick or a launch
    /// restore; a failed reopen keeps its reason on the item instead (``recentFailure(for:)``).
    private(set) var folderFailure: FolderAccessFailure?

    /// Why one Recents item did not reopen, keyed by that record (PRD P0-02).
    ///
    /// PRD P0-02 requires an explicit answer on the item that failed rather than a silent
    /// failure, so the reason stays with the record until that record opens again.
    private var recentFailures: [RecentFolder.ID: FolderAccessFailure]

    /// The groups the open folder publishes, in grid order (PRD P0-11).
    private(set) var groups: [BrowsingGroup]

    /// The remembered folders entry lists, most recently opened first (PRD P0-02).
    private(set) var recents: [RecentFolder]

    /// Why the Recents list could not be read, or nil when it could (PRD P0-02).
    private(set) var recentsFailure: FolderAccessFailure?

    /// The library's photos with their marks, before this state's order and filter (PRD P0-03).
    private var storedPhotos: [GridPhoto]

    /// The latest change to each photo, with its save state (PRD P0-08).
    ///
    /// The model keeps the statuses rather than asking the library on every render, so an
    /// applied change repaints the screen through observation and a streamed transition shows
    /// "Writing…" without a refresh of its own.
    private var changes = PhotoChangeStates()

    /// Whether this scene has already read its saved state, so a later appearance never
    /// overwrites what the user has done since.
    private var hasRestored = false

    /// The saved scene waiting for its folder to hold the photos it names (PRD P0-14).
    ///
    /// It applies as soon as the scan delivered them, at the latest when the scan finishes, and
    /// is dropped if the user navigates or opens another folder first.
    private var pendingRestore: PendingBrowsingRestore?

    /// The task applying the library's updates on the main actor (PRD P0-03, P0-08).
    private var updateTask: Task<Void, Never>?

    /// Creates the model over one library, starting at entry unless a state is passed in.
    init(library: any FolderLibrary, state: BrowsingState = .entry) {
        self.library = library
        self.state = state
        self.groups = library.groups
        self.recents = library.recents
        self.thumbnails = library.thumbnails
        self.recentFailures = [:]
        self.storedPhotos = library.photos
        refresh()
        updateTask = Task { [weak self, updates = library.updates] in
            for await update in updates {
                guard let self else { return }
                await self.apply(update)
            }
        }
    }

    /// The photos the grid shows: this state's order and filter, applied to the folder's photos
    /// (PRD P0-03). Filtering never reorders, and neither choice changes a stored photo.
    var photos: [GridPhoto] {
        PhotoOrdering(photos: storedPhotos).photos(order: state.order, matching: state.filter)
    }

    /// Whether the open folder holds photos to browse (PRD P0-01).
    var hasFolderContents: Bool { !storedPhotos.isEmpty }

    /// The grid's thumbnail source for the open folder (PRD P0-03).
    ///
    /// The model keeps it rather than reading the library on every render, because the library is
    /// not observable: opening another folder replaces the source here, so no later change can
    /// leave the grid drawing from the previous folder's pipeline. It comes from the library, so
    /// the grid draws a real folder's previews through C11's session without reaching into the
    /// library itself.
    private(set) var thumbnails: any GridThumbnailSource

    /// Whether entry can return to a folder without the picker (PRD P0-01).
    ///
    /// A folder that is open stays open while entry is on screen, and the test library starts
    /// with its photos in place, so entry offers to continue in both cases. An empty folder still
    /// counts, because coming back from its grid must not claim no folder is open.
    var canContinueBrowsing: Bool { state.folder != nil || hasFolderContents }

    /// The photo the detail route shows, with its current marks (PRD Detail and marking).
    var currentPhoto: GridPhoto? {
        guard let id = state.currentPhoto else { return nil }
        return storedPhotos.first { $0.id == id }
    }

    /// The open group's photos with their marks, in the group's member order (PRD P0-12).
    var groupPhotos: [GridPhoto] {
        guard let position = state.groupPosition,
            let group = groups.first(where: { $0.id == position.group })
        else { return [] }
        var byIdentity: [PhotoIdentity: GridPhoto] = [:]
        for photo in storedPhotos { byIdentity[photo.id] = photo }
        return group.members.compactMap { byIdentity[$0] }
    }

    /// Why one Recents item did not open, or nil when it did (PRD P0-02).
    func recentFailure(for recent: RecentFolder.ID) -> FolderAccessFailure? {
        recentFailures[recent]
    }

    /// Opens the folder the library already holds and shows its grid (PRD Entry, P0-01).
    ///
    /// Entry offers this once a folder is open, which is what the test library starts with, so
    /// coming back from the grid does not need the picker again. A folder that opens answers
    /// whatever the last failed open left on entry, so the message goes with it (PRD P0-02).
    func openFolder() {
        pendingRestore = nil
        folderFailure = nil
        showOpenFolder()
    }

    /// Opens the folder the user chose in the system picker (PRD P0-01, P0-02).
    ///
    /// The library performs C11's validating read; a failure stays on the model so entry explains
    /// it and asks for the folder again, while a success shows the grid as the scan streams in.
    func openPickedFolder(_ url: URL) async {
        pendingRestore = nil
        folderFailure = await library.pick(url)
        guard folderFailure == nil else { return }
        showOpenFolder()
        await reloadRecents()
    }

    /// Reopens one remembered folder (PRD P0-02).
    ///
    /// A failed reopen keeps C11's reason on that item, so entry can explain it there and ask for
    /// the folder again instead of failing silently.
    func reopen(_ recent: RecentFolder) async {
        pendingRestore = nil
        if let failure = await library.reopen(recent) {
            recentFailures[recent.id] = failure
            return
        }
        recentFailures[recent.id] = nil
        folderFailure = nil
        showOpenFolder()
        await reloadRecents()
    }

    /// Re-reads the Recents list from C11's store (PRD P0-02).
    func reloadRecents() async {
        await library.reloadRecents()
        recents = library.recents
        recentsFailure = library.recentsFailure
    }

    /// Shows one photo's detail (PRD Detail and marking).
    func openPhoto(_ photo: PhotoIdentity) {
        state.currentPhoto = photo
        state.route = .detail
    }

    /// Opens a group's view on its first member (PRD In-group culling).
    func openGroup(_ group: BrowsingGroup) {
        guard let first = group.members.first else { return }
        state.groupPosition = BrowsingGroupPosition(group: group.id, photo: first)
        state.route = .group
    }

    /// Moves the open group view to another member (PRD P0-12).
    func showGroupPhoto(_ photo: PhotoIdentity) {
        guard let position = state.groupPosition else { return }
        state.groupPosition = BrowsingGroupPosition(group: position.group, photo: photo)
    }

    /// Shows Clove's settings (PRD Gesture-related settings).
    func showSettings() {
        state.route = .settings
    }

    /// Returns to the screen the current one came from (PRD P0-13).
    ///
    /// The grid's parent is entry, and detail and the group view return to the grid. Settings
    /// keeps the folder it was opened over, so closing them returns to the grid when a folder is
    /// open and to entry when none is.
    func back() {
        switch state.route {
        case .entry:
            break
        case .grid:
            state.route = .entry
        case .detail, .group, .settings:
            state.route = state.folder == nil ? .entry : .grid
        }
    }

    /// Changes the grid filter without touching the order or the current photo (PRD P0-03).
    func setFilter(_ filter: PhotoFilter) {
        state.filter = filter
    }

    /// Changes the grid order without touching the filter or the current photo (PRD P0-03).
    func setOrder(_ order: PhotoOrder) {
        state.order = order
    }

    /// Adds one photo to the multi-selection or removes it (PRD P0-09).
    func toggleSelection(_ photo: PhotoIdentity) {
        if state.selection.contains(photo) {
            state.selection.remove(photo)
        } else {
            state.selection.insert(photo)
        }
    }

    /// The last batch the bar applied, with each targeted photo's marks before it
    /// (PRD P0-09; C5's `MarkUndoHistory.recordBatch`).
    ///
    /// U8 records one undo entry per bar action from this value. A retry does not replace it, so
    /// retrying a failed item never records a second entry for the same action.
    private(set) var lastBatch: BatchMarkApplication?

    /// What the multi-select bar reports for the batch it applied, or nil when there is nothing
    /// to report or the bar dismissed it (PRD P0-09, PRD Failure and recovery).
    private(set) var batchReport: BatchMarkReport?

    /// The photos one batch marks: the selection narrowed to the photos the grid shows, in grid
    /// order (PRD P0-09). A photo the filter hides stays selected and is not marked.
    var batchTargets: [GridPhoto] {
        BatchSelection.targets(selection: state.selection, shown: photos)
    }

    /// Whether the grid is in multi-select (PRD P0-09).
    ///
    /// The mode is not stored separately: a non-empty selection is multi-select, and
    /// ``BrowsingState/selection`` is already saved per scene, so a fold, a resize and a relaunch
    /// keep the mode along with the photos it names (PRD P0-14).
    var isSelecting: Bool { !state.selection.isEmpty }

    /// The selection read against the folder's published groups (PRD P0-09, P0-11).
    private var batchSelection: BatchSelection {
        BatchSelection(groups: groups, selection: state.selection)
    }

    /// Whether a batch write or a retry is running, so the bar cannot start a second one
    /// (PRD P0-09).
    ///
    /// A batch is planned from the marks on screen, so two actions at once would both plan from
    /// the marks the first one is about to replace, and the later report could describe the
    /// action the earlier one superseded.
    private(set) var isApplyingBatch = false

    /// How many times multi-select ended, so a batch that finishes after Done reports nothing
    /// into a later session (PRD P0-09).
    private var selectionClearances = 0

    /// Enters multi-select on one cell's photos (PRD P0-09).
    ///
    /// A photo's cell adds that photo; a collapsed group's cover adds every photo in its group,
    /// because the cover stands for the group (PRD Grid, collapsed).
    func beginSelection(of cell: GridCellItem) {
        state.selection = batchSelection.selecting(cell)
    }

    /// Adds one cell's photos to the multi-selection or removes them (PRD P0-09).
    ///
    /// In multi-select a tap toggles instead of opening detail, and a partly selected cover
    /// completes its group rather than clearing the part already chosen.
    func toggleSelection(of cell: GridCellItem) {
        state.selection = batchSelection.toggling(cell)
    }

    /// Selects every photo the shown cells stand for (PRD P0-09's Select all visible).
    func selectAllVisible(_ cells: [GridCellItem]) {
        state.selection = batchSelection.selectingAll(cells)
    }

    /// Leaves multi-select, clears the selection and drops the batch's report (PRD P0-09).
    ///
    /// A failed photo keeps its failure in ``latestChange(for:)`` and shows no mark it did not
    /// save; U7's global save state reports the unfinished writes from there.
    func clearSelection() {
        state.selection = []
        batchReport = nil
        selectionClearances += 1
    }

    /// Applies one bar action to the selected photos the grid shows (PRD P0-09).
    ///
    /// One call is one batch: the library admits each change group's photos before awaiting that
    /// group's results, so a bar action over 50 photos writes them concurrently and reports one
    /// result with one retry handle. Each photo's save state still arrives through the library's
    /// stream, like any other change, so a failed photo never shows a mark it did not save
    /// (PRD P0-08). A second action is refused while one runs, so both plans cannot read the same
    /// pre-batch marks.
    func applyBatch(_ action: BatchMarkAction, settings: AppSettings) async {
        guard !isApplyingBatch else { return }
        let targets = batchTargets
        let plan = BatchMarkPlan(action: action, photos: targets, settings: settings)
        guard !plan.items.isEmpty else { return }
        var marksBefore: [PhotoIdentity: PhotoMarks] = [:]
        for photo in targets { marksBefore[photo.id] = photo.marks }
        let folder = state.folder
        let clearances = selectionClearances
        isApplyingBatch = true
        let result = await library.apply(plan.items)
        isApplyingBatch = false
        // The batch happened, but its report must not land in another folder's bar or reopen
        // after Done cleared the mode it belonged to.
        guard state.folder == folder else { return }
        lastBatch = BatchMarkApplication(result: result, marksBefore: marksBefore)
        guard clearances == selectionClearances else { return }
        batchReport = BatchMarkReport(result)
    }

    /// Retries only the photos the last batch could not save (PRD P0-09).
    ///
    /// The saved photos are left alone, and the retry's result merges with the action's, so the
    /// bar keeps counting the whole action instead of only the photos the retry resent. A library
    /// that can no longer retry, such as one whose folder closed, answers nil; the report then
    /// stays as it was, so the bar still names the photos that did not save (PRD P0-08).
    func retryFailedBatch() async {
        guard !isApplyingBatch, let report = batchReport, report.canRetry else { return }
        let folder = state.folder
        let clearances = selectionClearances
        isApplyingBatch = true
        defer { isApplyingBatch = false }
        guard let result = await library.retryFailed(in: report.batch),
            state.folder == folder, clearances == selectionClearances
        else { return }
        batchReport = report.merging(result)
    }

    /// Dismisses the batch's report without retrying (PRD Failure and recovery: Cancel).
    func dismissBatchReport() {
        batchReport = nil
    }

    /// The latest change to one photo with its save state, or nil when nothing was requested
    /// (PRD P0-08). U7 reads the same status for its retry.
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? {
        changes.latest(for: photo)
    }

    /// Applies one change to one photo through the library and shows its marks and save state
    /// (PRD P0-08).
    ///
    /// The await is C4's write queue. The change's states arrive only through the library's
    /// ordered stream, never from this call's return: a returned status can arrive after a newer
    /// change was admitted, which would let an older finished state paint over the newer one
    /// (``PhotoChangeStates``). A failed write therefore never shows a mark it did not confirm.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async {
        guard !change.isEmpty else { return }
        _ = await library.apply(change, to: photo)
    }

    /// Restores this scene's saved state through CloveCore's validation (PRD P0-14).
    ///
    /// A saved scene that shows photos reopens its folder through C11 and shows that folder's
    /// grid at once, because a large RAW folder's metadata read must not hold the launch on entry.
    /// The saved photo, filter, order, selection and group place stay pending and are validated by
    /// ``PendingBrowsingRestore``: they apply as soon as the folder holds every photo they name,
    /// at the latest when the scan finishes, and only while the scene still shows what the reopen
    /// produced. The user navigating, opening another folder or reopening a Recents item first
    /// drops the pending state instead of being overwritten later.
    ///
    /// A folder that does not open lands on entry with C11's reason on its Recents item
    /// (PRD P0-02), and a launch with nothing saved starts at entry. Restoring runs once per
    /// scene; later appearances keep whatever the user has done.
    func restore(from data: Data?, folderAvailability: FolderAvailability? = nil) async {
        guard !hasRestored else { return }
        hasRestored = true
        pendingRestore = nil
        let saved = BrowsingState.decoded(from: data)
        let launchState = state
        let availability: FolderAvailability?
        if let folderAvailability {
            availability = folderAvailability
        } else if let folder = saved.folder {
            availability = await library.openSavedFolder(folder)
        } else {
            availability = nil
        }
        // The user opened another folder while this one reopened; their choice wins.
        guard state == launchState else { return }

        switch availability {
        case .unavailable(let failure):
            state = .entry
            folderFailure = failure
            await reloadRecents()
            if let folder = saved.folder,
                let recent = recents.first(where: { $0.identity == folder })
            {
                recentFailures[recent.id] = failure
            }
        case .available?:
            folderFailure = nil
            await reloadRecents()
            if saved.showsPhotos {
                showOpenFolder()
                pendingRestore = PendingBrowsingRestore(saved: saved, shown: state)
                resolvePendingRestore(scanFinished: false)
            } else {
                thumbnails = library.thumbnails
                state = saved.restored(from: .available(library.contents)).state
            }
        case nil:
            let restored = saved.restored(from: .available(library.contents))
            state = restored.state
            folderFailure = restored.folderFailure
            await reloadRecents()
        }
        refresh()
    }

    /// Applies or drops a pending saved state as the folder's contents arrive (PRD P0-14).
    ///
    /// The finished scan is passed in so a photo that is gone by then takes U1's fallback instead
    /// of holding the restore forever; a partial scan counts as finished.
    private func resolvePendingRestore(scanFinished: Bool) {
        guard let pending = pendingRestore else { return }
        switch pending.decision(
            current: state, contents: library.contents, scanFinished: scanFinished)
        {
        case .apply(let restored):
            pendingRestore = nil
            state = restored.state
            folderFailure = restored.folderFailure
        case .drop:
            pendingRestore = nil
        case .wait:
            break
        }
    }

    /// Applies one library update on the main actor (PRD P0-03, P0-08).
    private func apply(_ update: FolderLibraryUpdate) async {
        switch update {
        case .photos, .reads:
            refresh()
            resolvePendingRestore(scanFinished: false)
        case .scanFinished:
            refresh()
            resolvePendingRestore(scanFinished: true)
            await reloadRecents()
        case .change(let status):
            // A streamed transition keeps "Writing…" and "Saved" current without re-reading
            // every photo, and the merge rule keeps a finished change from moving backwards.
            changes.insert(status)
        case .groups(let groups):
            self.groups = groups
        }
    }

    /// Shows the grid on the folder the library just opened (PRD Entry, P0-01).
    private func showOpenFolder() {
        state.folder = library.folder
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .grid
        // Another folder replaces every selected photo's identity, so the batch's report and
        // U8's undo snapshot go with the selection.
        lastBatch = nil
        batchReport = nil
        selectionClearances += 1
        // The library replaced its pipeline with the folder's, so the grid takes the new source
        // even when the route does not change.
        thumbnails = library.thumbnails
    }

    /// Takes the library's current photos, groups and save states.
    ///
    /// Scan batches, metadata reads, mark reads and confirmed writes all refresh through this
    /// path, so the screens keep reading the model while the library changes underneath it.
    private func refresh() {
        storedPhotos = library.photos
        groups = library.groups
        for photo in storedPhotos {
            if let change = library.latestChange(for: photo.id) { changes.insert(change) }
        }
    }
}

/// One batch the multi-select bar applied, with what U8's undo entry needs (PRD P0-09, C5).
///
/// The batch is already written when this value exists, so it holds what the action cannot be
/// re-derived from: C4's per-photo results, including the failed photos a retry resends, and the
/// marks each targeted photo had just before the batch. U8 passes both to
/// `MarkUndoHistory.recordBatch(_:marksBefore:)` from the one ``BrowsingModel/applyBatch(_:settings:)``
/// call, which is what keeps one bar action to one undo entry.
struct BatchMarkApplication: Sendable {
    /// C4's per-photo results, with the photos the batch could not save (PRD P0-09).
    let result: MarkBatchResult

    /// Each targeted photo's marks before the batch, keyed by C1's identity (PRD P0-05).
    let marksBefore: [PhotoIdentity: PhotoMarks]
}
