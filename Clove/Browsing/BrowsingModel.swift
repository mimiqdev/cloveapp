import CloveCore
import Foundation
import Observation
import UIKit

/// The browsing state every screen reads and changes (PRD P0-13, P0-14).
///
/// The state belongs to this model, never to a view's `@State`, so the compact stack and the
/// split layout show the same folder, photo, filter and selection when a fold, an
/// unfold or a resize changes the layout (PRD P0-14, G1 fold-state row). The model also keeps the
/// state in the shape CloveCore can validate and store, so a launch restores what it can and falls
/// back to entry for the rest.
///
/// The model is the only reader of the library's ``FolderLibrary/updates`` stream: entry's
/// Recents, the grid's photos and their marks all come from here, so no screen polls a
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

    /// The folder whose scan reported itself finished (PRD P0-01).
    ///
    /// Restore reads this when reopening catches up with an already finished scan.
    private var finishedScanFor: FolderIdentity?

    /// Whether the open folder's scan reported itself finished (PRD P0-01).
    private var hasFinishedScan: Bool { finishedScanFor == library.folder }

    /// Whether the open folder is still opening, so the grid hides actions the handoff hides
    /// until the scan finishes (design handoff, PRD P0-01).
    var isFolderOpening: Bool { !hasFinishedScan || isFindingSimilarShots }

    /// Display-only activity forwarded by the folder's visual grouping pass.
    private(set) var isFindingSimilarShots = false

    /// Progress from discovered photos, including photos still waiting for metadata.
    var readingProgress: (read: Int, total: Int)? {
        guard !hasFinishedScan else { return nil }
        return (storedPhotos.filter { !$0.time.isPending }.count, storedPhotos.count)
    }

    /// The opened folder's display name, without its device path.
    var folderTitle: String {
        recents.first(where: { $0.identity == state.folder }).map {
            RecentFolderSummary.name(for: $0)
        }
            ?? "Photos"
    }

    /// Label filtering is a presentation filter over the same ordered photos.
    var labelFilter: LabelColour?

    /// All placed photos, used for the filter menu's counts.
    var allPlacedPhotos: [GridPhoto] {
        PhotoOrdering(photos: storedPhotos).photos(order: state.order, matching: .all)
    }

    /// One admitted Info read, requested only when the sheet opens.
    func information(for photo: PhotoIdentity) async -> PhotoInformation? {
        await library.information(for: photo)
    }

    /// The library's current open generation, which changes when the same folder is reopened
    /// (PRD P0-02). A move that finishes across a change must not record against the new open.
    var openGeneration: Int { library.openGeneration }

    /// The remembered folders entry lists, most recently opened first (PRD P0-02).
    private(set) var recents: [RecentFolder]

    /// Entry waits for the small app-private Recents read before showing first launch (P0-02).
    private(set) var hasLoadedRecents = false

    /// Why the Recents list could not be read, or nil when it could (PRD P0-02).
    private(set) var recentsFailure: FolderAccessFailure?

    /// The library's photos with their marks, before this state's order and filter (PRD P0-03).
    private var confirmedPhotos: [GridPhoto]

    /// Shown marks are updated at submission and confirmation, rather than mapped on every read.
    private var storedPhotos: [GridPhoto]
    private var photoIndices: [PhotoIdentity: Int] = [:]

    /// A pending mark is shown until its ordered write finishes.
    private var desiredMarks = DesiredPhotoMarks()
    private var actionPipeline = PhotoActionPipeline()
    private var actionConsumer: Task<Void, Never>?
    private var shownGeneration: Int
    private var moveCompletions: [UInt64: (Result<RejectMoveResult, any Error>) -> Void] = [:]
    private var keptEditsByMove: [RejectMoveBatchID: [DesiredMarkEdit]] = [:]

    /// The latest detail action's return photo and before/after snapshots form one undo step.
    private var markUndo: (photo: PhotoIdentity, edits: [DesiredMarkEdit])?
    private(set) var lastMoveUndo: Result<RejectMoveUndoResult, any Error>?

    static let saveFailureToastMessage = "Couldn't save the mark."
    private(set) var isSaveFailureToastVisible = false
    private(set) var saveFailureToastBurst = 0

    func dismissSaveFailureToast() { isSaveFailureToastVisible = false }

    /// Whether this scene has already read its saved state, so a later appearance never
    /// overwrites what the user has done since.
    private var hasRestored = false

    /// The open folder's location loss, as C11's watch reported it (PRD P0-02, P0-08).
    ///
    /// A loss explains the folder with the disconnected-drive or missing-location copy and
    /// stops new marking actions. It is cleared when another folder opens.
    private(set) var folderLocationLoss: FolderLocationLoss?

    /// Whether this scene left its folder and is ignoring that folder's updates until a real open
    /// shows another one.
    ///
    /// The library keeps the departed folder's photos until its session drains, so without this
    /// a confirmed write could refresh them back onto entry and bring Continue browsing with it.
    private var hasLeftFolder = false

    /// How many opens this scene started, so a leaving destination never replaces a folder the
    /// user opened while it waited (PRD P0-08).
    private var openRequests = 0
    private var folderClose: Task<Void, Never>?

    private var folderReplacements = 0

    /// Refuse new actions while a pick or reopen drains and replaces the folder's generation.
    var isChangingFolder: Bool { folderReplacements > 0 }

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
        self.shownGeneration = library.openGeneration
        self.state = state
        self.groups = library.groups
        self.recents = library.recents
        self.thumbnails = library.thumbnails
        self.detailImages = library.detailImages
        self.recentFailures = [:]
        self.confirmedPhotos = library.photos
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
        let ordered = PhotoOrdering(photos: storedPhotos).photos(
            order: state.order, matching: state.filter)
        guard let labelFilter else { return ordered }
        return ordered.filter { $0.marks.label.colour == labelFilter }
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

    /// The detail view's source for the open folder (PRD P0-04).
    ///
    /// It is kept beside ``thumbnails`` for the same reason: the source is bound to one folder's
    /// I2 pipeline and C11 session, so detail must read the source that belongs to the folder
    /// that is open now, never a pipeline whose folder ended.
    private(set) var detailImages: any DetailImageSource

    /// The photo the detail route shows, with its current marks (PRD Detail and marking).
    var currentPhoto: GridPhoto? {
        guard let id = state.currentPhoto, let index = photoIndices[id] else { return nil }
        return storedPhotos[index]
    }

    /// The open group's photos with their marks, in the group's member order (PRD P0-12).
    var groupPhotos: [GridPhoto] {
        guard let group = currentGroup else { return [] }
        return group.members.compactMap { photo in
            photoIndices[photo].map { storedPhotos[$0] }
        }
    }

    /// The current photo's group, derived from the folder's published membership.
    var currentGroup: BrowsingGroup? {
        guard let photo = state.currentPhoto else { return nil }
        return groups.first { $0.members.contains(photo) }
    }

    /// Loads an Entry preview from app-private storage only (handoff Entry).
    func entryThumbnail(for photo: PhotoIdentity) async -> GridThumbnailOutcome {
        await library.entryThumbnail(for: photo)
    }

    /// Changes after a flush so an Entry placeholder can reload a newly written hero preview.
    private(set) var entryPreviewGeneration = 0

    /// Flushes the open folder's confirmed progress and current preview (handoff Entry).
    func recordEntryProgress() async {
        await library.flushEntryState(lastViewed: state.currentPhoto)
        await reloadRecents()
        entryPreviewGeneration += 1
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
        guard !hasLeftFolder else { return }
        openRequests += 1
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
        await openPickedFolderNow(url)
    }

    /// Opens a folder the user chose after the old folder's writes drain.
    private func openPickedFolderNow(_ url: URL) async {
        folderReplacements += 1
        defer { folderReplacements -= 1 }
        openRequests += 1
        // Clearing before the await keeps a loss the new open reports. A failed pick has not
        // reconnected the old folder, so its disconnected gate must remain in effect.
        let previousLoss = folderLocationLoss
        folderLocationLoss = nil
        await folderClose?.value
        await drainActions()
        folderFailure = await library.pick(url)
        guard folderFailure == nil else {
            if folderLocationLoss == nil { folderLocationLoss = previousLoss }
            return
        }
        showOpenFolder()
        await reloadRecents()
        clearRecentFailureForOpenFolder()
    }

    /// Clears only the recovered folder; failures on other remembered folders stay visible.
    private func clearRecentFailureForOpenFolder() {
        guard let folder = state.folder else { return }
        for recent in recents where recent.identity == folder { recentFailures[recent.id] = nil }
    }

    /// Reopens one remembered folder (PRD P0-02).
    ///
    /// A failed reopen keeps C11's reason on that item, so entry can explain it there and ask for
    /// the folder again instead of failing silently.
    func reopen(_ recent: RecentFolder) async {
        pendingRestore = nil
        if !hasLeftFolder, state.folder == recent.identity, folderLocationLoss == nil {
            openRequests += 1
            recentFailures[recent.id] = nil
            folderFailure = nil
            state.route = .grid
            return
        }
        await reopenNow(recent)
    }

    /// Reopens the hero at its saved photo through the scene's existing restore validation.
    func resume(_ recent: RecentFolder) async {
        let resumePhoto =
            state.folder == recent.identity
            ? state.currentPhoto ?? recent.progress?.lastViewedPhoto
            : recent.progress?.lastViewedPhoto
        await reopen(recent)
        guard recentFailures[recent.id] == nil, state.folder == recent.identity,
            let photo = resumePhoto
        else { return }
        var saved = state
        saved.currentPhoto = photo
        saved.route = .detail
        pendingRestore = PendingBrowsingRestore(saved: saved, shown: state)
        resolvePendingRestore(scanFinished: hasFinishedScan)
    }

    /// Reopens one remembered folder after the old folder's writes drain.
    private func reopenNow(_ recent: RecentFolder) async {
        folderReplacements += 1
        defer { folderReplacements -= 1 }
        openRequests += 1
        // Keep a new open's own loss, and retain the old gate if reopening fails.
        let previousLoss = folderLocationLoss
        folderLocationLoss = nil
        await folderClose?.value
        await drainActions()
        if let failure = await library.reopen(recent) {
            recentFailures[recent.id] = failure
            if folderLocationLoss == nil { folderLocationLoss = previousLoss }
            return
        }
        recentFailures[recent.id] = nil
        folderFailure = nil
        showOpenFolder()
        await reloadRecents()
        clearRecentFailureForOpenFolder()
    }

    /// Re-reads the Recents list from C11's store (PRD P0-02).
    func reloadRecents() async {
        await library.reloadRecents()
        recents = library.recents
        recentsFailure = library.recentsFailure
        hasLoadedRecents = true
    }

    /// Shows one photo's detail (PRD Detail and marking).
    func openPhoto(_ photo: PhotoIdentity) {
        state.currentPhoto = photo
        library.setEntryResumePhoto(photo)
        state.route = .detail
    }

    /// Runs similar groups again for the open folder, without the group cache (PRD P0-11).
    ///
    /// Run again is the grid's own action (PRD Similar groups rules), so the model passes it to
    /// the library and takes the result from the update stream like any other grouping result.
    func runGroupingAgain() async {
        await library.runGroupingAgain()
    }

    /// Applies C12's similar-groups setting to the open folder (PRD P0-11).
    ///
    /// The settings screen calls this when the user changes the choice: the open folder drops or
    /// restores its groups at once, and every later open in this launch reads the same value.
    /// Saving the choice stays with the settings store.
    func setSimilarGroupsEnabled(_ enabled: Bool) async {
        await library.setSimilarGroupsEnabled(enabled)
    }

    // MARK: - In-group culling

    /// Snapshots the allowed changes from shown marks and submits one finishing action.
    func runGroupFinishing(_ plan: GroupFinishingPlan) {
        guard canMark, plan.availability.isAvailable else { return }
        let edits = plan.changesAllowed { photo in self.shownMarks(for: photo) }.map {
            request($0.change, for: $0.photo)
        }
        submit(.finishing(plan, edits))
    }

    private var settingsReturnRoute: BrowserRoute = .entry

    /// Shows Clove's settings (PRD Gesture-related settings).
    func showSettings() {
        settingsReturnRoute = state.route == .entry ? .entry : .grid
        state.route = .settings
    }

    /// Returns to the screen the current one came from (PRD P0-13).
    ///
    /// The grid's parent is entry, and detail returns to the grid. Settings
    /// keeps the folder it was opened over, so closing them returns to the grid when a folder is
    /// open and to entry when none is. Going back from the grid leaves immediately.
    func back() {
        switch state.route {
        case .entry:
            break
        case .grid:
            leaveFolder()
        case .settings:
            state.route = settingsReturnRoute
        case .detail:
            state.route = state.folder == nil ? .entry : .grid
        }
    }

    /// Changes the grid filter without touching the order or the current photo (PRD P0-03).
    func setFilter(_ filter: PhotoFilter) {
        labelFilter = nil
        state.filter = filter
    }

    /// Applies a label-only display filter in grid order (handoff Filter menu).
    func setLabelFilter(_ label: LabelColour) {
        state.filter = .all
        labelFilter = label
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

    /// Leaves multi-select and clears the selection (PRD P0-09).
    func clearSelection() {
        state.selection = []
    }

    /// Updates the selected photos immediately and queues one batch with their before and after marks.
    func applyBatch(_ action: BatchMarkAction, settings: AppSettings) {
        guard canMark else { return }
        let plan = BatchMarkPlan(action: action, photos: batchTargets, settings: settings)
        guard !plan.items.isEmpty else { return }
        let edits = plan.items.map { request($0.change, for: $0.photo) }
        submit(.batch(edits))
    }

    // MARK: - Move rejects

    /// How many photos the open folder holds with Reject set (PRD P0-10).
    ///
    /// The grid offers Move rejects only while this is non-zero, the scan has finished and
    /// C12's setting is on; the plan still decides which sets can actually move.
    var rejectedPhotoCount: Int { storedPhotos.filter(\.marks.isRejected).count }

    /// The latest completed Move rejects run, which C14's undo will use (PRD P0-10).
    ///
    /// It holds the run's result and the identities the person kept in the confirmation, plus the
    /// folder name that run used. It stays after the toast goes, so a later undo has the whole
    /// move; nothing in this task moves files back.
    private(set) var lastRejectMove: CompletedRejectMove?

    /// Whether the grid shows the latest move's toast (design handoff, PRD P0-10).
    ///
    /// Dismissing the toast keeps ``lastRejectMove``; only the presentation goes away.
    private(set) var isRejectMoveToastVisible = false

    /// Each completed move restarts the toast timer.
    private(set) var rejectMoveToastAttempt = 0

    /// Blocks new marks while the consumer executes a move or move undo.
    private(set) var isMovingRejects = false
    private(set) var rejectMoveFinishedCount = 0

    /// Plans Move rejects for the open folder's rejected photos (PRD P0-10).
    ///
    /// The plan is the confirmation sheet's input; nothing moves until ``runRejectMove(_:)``.
    /// The configuration is read from settings by the caller at move time, so a renamed folder
    /// applies without reopening the folder (PRD Move rejects, C12).
    func planRejectMove(configuration: RejectMoveConfiguration) async throws -> RejectMovePlan {
        try await library.planRejectMove(
            configuration: configuration,
            rejected: storedPhotos.filter(\.marks.isRejected).map(\.id))
    }

    /// Commits staged keeps and queues the move behind them and every earlier user action.
    func runRejectMove(
        _ plan: RejectMovePlan, kept: [PhotoIdentity],
        completion: @escaping (Result<RejectMoveResult, any Error>) -> Void
    ) {
        guard canMark else {
            completion(.failure(RejectMoveRefusal.disabled))
            return
        }
        let edits = kept.map { request(.rating(.unrated), for: $0) }
        submit(.keep(edits))
        let id = submit(.move(plan, kept: edits))
        moveCompletions[id] = completion
    }

    /// Records one completed move, so the toast can show it and C14 can undo it (PRD P0-10).
    func recordRejectMove(
        _ result: RejectMoveResult, keptIdentities: [PhotoIdentity],
        rejectsFolderName: RejectsFolderName, folder: FolderIdentity?, openGeneration: Int
    ) {
        lastRejectMove = CompletedRejectMove(
            result: result, keptIdentities: keptIdentities, rejectsFolderName: rejectsFolderName,
            folder: folder, openGeneration: openGeneration)
        isSaveFailureToastVisible = false
        isRejectMoveToastVisible = true
        rejectMoveToastAttempt += 1
    }

    /// The toast restores the completed move and the exact marks its staged keeps left behind.
    func undoRejectMove(_ completed: CompletedRejectMove) {
        guard canMark,
            completed.folder == state.folder, completed.openGeneration == openGeneration,
            let photo = completed.keptIdentities.first ?? completed.result.movedIdentities.first
        else { return }
        let kept = (keptEditsByMove[completed.id] ?? []).compactMap {
            edit -> RejectMoveKeptPhoto? in
            guard let set = library.scannedSet(for: edit.photo) else { return nil }
            return RejectMoveKeptPhoto(set: set, marksAfter: edit.after)
        }
        submitMoveUndo(
            RejectMoveUndoEntry(batch: completed.id, keptPhotos: kept, photoToReturnTo: photo))
        dismissRejectMoveToast()
    }

    /// Submits a move undo to the existing ordered pipeline.
    func submitMoveUndo(_ entry: RejectMoveUndoEntry) {
        guard canMark else { return }
        let edits = entry.keptPhotos.compactMap { kept -> DesiredMarkEdit? in
            var target = kept.marksAfter
            target.rating = .rejected
            guard
                let change = DesiredMarkRestore.change(
                    photo: kept.set.id, current: shownMarks(for: kept.set.id),
                    expected: kept.marksAfter, target: target,
                    fields: .rating(kept.marksAfter.rating))
            else { return nil }
            return request(change, for: kept.set.id)
        }
        submit(.moveUndo(entry, edits))
    }

    /// Hides the move toast while keeping the completed move for a later undo (PRD P0-10).
    func dismissRejectMoveToast() {
        isRejectMoveToastVisible = false
    }

    /// Every screen and marking rule reads desired marks while they await confirmation.
    func shownMarks(for photo: PhotoIdentity) -> PhotoMarks {
        guard let index = photoIndices[photo] else { return PhotoMarks() }
        return storedPhotos[index].marks
    }

    /// Inputs check admission before planning auto-advance as well as before submitting a mark.
    var canMark: Bool {
        !isMovingRejects && !isChangingFolder && !hasLeftFolder && folderLocationLoss == nil
    }

    /// Shows the requested mark and submits its write before returning to the input handler.
    func apply(_ change: MarkChange, to photo: PhotoIdentity) {
        guard canMark, !change.isEmpty else { return }
        let edit = request(change, for: photo)
        submit(.mark(edit))
    }

    var canUndoMark: Bool { canMark && markUndo != nil }

    /// Restore the latest detail action together, including a whole Reject unmarked action.
    func undoLastMark() {
        guard canUndoMark, let undo = markUndo else { return }
        let edits = undo.edits.compactMap { edit -> DesiredMarkEdit? in
            guard
                let change = DesiredMarkRestore.change(
                    photo: edit.photo, current: shownMarks(for: edit.photo), expected: edit.after,
                    target: edit.before, fields: edit.change)
            else { return nil }
            return request(change, for: edit.photo)
        }
        submit(.batch(edits))
        openPhoto(undo.photo)
    }

    // MARK: - Ordered actions

    private func request(_ change: MarkChange, for photo: PhotoIdentity) -> DesiredMarkEdit {
        let confirmed = photoIndices[photo].map { confirmedPhotos[$0].marks } ?? PhotoMarks()
        let edit = desiredMarks.apply(change, to: photo, confirmed: confirmed)
        updateShownPhoto(photo)
        return edit
    }

    private func updateShownPhoto(_ photo: PhotoIdentity) {
        guard let index = photoIndices[photo] else { return }
        storedPhotos[index].marks = desiredMarks.shown(
            for: photo, confirmed: confirmedPhotos[index].marks)
    }

    /// Only detail marks and finishing actions create a marking undo step. Other actions and
    /// ending the folder's session clear the whole value, so no separate navigation record lingers.
    private func recordUndo(for action: PhotoAction?) {
        switch action {
        case .mark(let edit)? where state.route == .detail:
            markUndo = (edit.photo, [edit])
        case .finishing(let plan, let edits)? where state.route == .detail && !edits.isEmpty:
            markUndo = (plan.currentPhoto, edits)
        default:
            markUndo = nil
        }
    }

    @discardableResult
    private func submit(_ action: PhotoAction) -> UInt64 {
        recordUndo(for: action)
        let id = actionPipeline.submit(action)
        if actionConsumer == nil {
            actionConsumer = Task { [weak self] in
                await self?.consumeActions()
            }
        }
        return id
    }

    func drainActions() async { await actionConsumer?.value }

    private func consumeActions() async {
        var keptStatuses: [MarkChangeStatus] = []
        while let entry = actionPipeline.beginNext() {
            switch entry.action {
            case .mark(let edit):
                _ = await persist([edit])
            case .batch(let edits):
                _ = await persist(edits)
            case .finishing(_, let edits):
                _ = await persist(edits)
            case .keep(let edits):
                keptStatuses = await persist(edits).outcomes
            case .move(let preview, let kept):
                await performMove(
                    preview, kept: kept, keptStatuses: keptStatuses, actionID: entry.id)
                keptStatuses = []
            case .moveUndo(let move, let edits):
                await performMoveUndo(move, edits: edits)
            }
            actionPipeline.finish(entry.id)
        }
        actionConsumer = nil
    }

    private func performMove(
        _ preview: RejectMovePlan, kept: [DesiredMarkEdit], keptStatuses: [MarkChangeStatus],
        actionID: UInt64
    ) async {
        isMovingRejects = true
        defer { isMovingRejects = false }
        let context = (folder: state.folder, generation: openGeneration)
        let progress = await observeMoveProgress()
        defer { progress.cancel() }
        do {
            let excluded = Set(kept.map(\.photo))
            let candidates = Set(preview.sets.map(\.id))
            let rejected = confirmedPhotos.filter {
                $0.marks.isRejected && candidates.contains($0.id) && !excluded.contains($0.id)
                    && !desiredMarks.hasPending(for: $0.id)
            }.map(\.id)
            await library.drainWrites()
            let plan = try await library.planRejectMove(
                configuration: preview.configuration, rejected: rejected)
            let moved = try await library.runRejectMove(plan)
            let clearFailures = keptStatuses.compactMap { status -> RejectMoveOutcome? in
                guard let failure = status.state.failure else { return nil }
                return .failed(
                    RejectMoveFailedSet(
                        identity: status.identity, failure: RejectMoveFailure(classifying: failure),
                        files: preview.readyEntries.first { $0.identity == status.identity }?.files
                            ?? []
                    ))
            }
            let difference = RejectMovePlanDifference(
                preview: preview.removing(kept: excluded), actual: plan)
            let result = RejectMoveResult(
                id: moved.id, outcomes: moved.outcomes + clearFailures,
                planDifference: difference.hasChanges ? difference : moved.planDifference)
            if let difference = result.planDifference {
                UIAccessibility.post(notification: .announcement, argument: difference.announcement)
            }
            keptEditsByMove[result.id] = kept
            recordRejectMove(
                result, keptIdentities: kept.map(\.photo),
                rejectsFolderName: plan.configuration.rejectsFolderName,
                folder: context.folder, openGeneration: context.generation)
            refresh()
            moveCompletions.removeValue(forKey: actionID)?(.success(result))
        } catch {
            // A whole-request refusal restores only keeps the user has not changed since.
            let restores = kept.compactMap { edit -> DesiredMarkEdit? in
                guard
                    let change = DesiredMarkRestore.change(
                        photo: edit.photo, current: shownMarks(for: edit.photo),
                        expected: edit.after, target: edit.before, fields: edit.change)
                else { return nil }
                return request(change, for: edit.photo)
            }
            _ = await persist(restores)
            moveCompletions.removeValue(forKey: actionID)?(.failure(error))
        }
    }

    private func observeMoveProgress() async -> Task<Void, Never> {
        rejectMoveFinishedCount = 0
        let updates = await library.rejectMoveProgress()
        return Task { [weak self] in
            for await update in updates {
                guard let self, !Task.isCancelled else { return }
                switch update {
                case .setStarted: break
                case .setFinished: self.rejectMoveFinishedCount += 1
                case .finished: return
                }
            }
        }
    }

    private func performMoveUndo(_ entry: RejectMoveUndoEntry, edits: [DesiredMarkEdit]) async {
        isMovingRejects = true
        defer { isMovingRejects = false }
        var current = Dictionary(uniqueKeysWithValues: storedPhotos.map { ($0.id, $0.marks) })
        for edit in edits { current[edit.photo] = edit.before }
        do {
            let result = try await library.undoRejectMove(
                entry, currentMarks: current, restoring: edits)
            finishPendingMarks(edits)
            refresh()
            if result.restored.contains(where: { !$0.isRejectStored }) { showSaveFailureToast() }
            lastMoveUndo = .success(result)
        } catch {
            finishPendingMarks(edits)
            refresh()
            showSaveFailureToast()
            lastMoveUndo = .failure(error)
        }
    }

    private func finishPendingMarks(_ edits: [DesiredMarkEdit]) {
        for edit in edits where !actionPipeline.hasPendingMark(for: edit.photo) {
            desiredMarks.finish(for: edit.photo)
        }
    }

    private func persist(_ edits: [DesiredMarkEdit]) async -> MarkBatchResult {
        guard folderLocationLoss == nil else {
            return MarkBatchResult(id: MarkBatchID(), change: MarkChange(), outcomes: [])
        }
        let result = await library.apply(
            edits.map { BatchMarkItem(photo: $0.photo, change: $0.change) })
        guard folderLocationLoss == nil else { return result }
        if result.outcomes.contains(where: { $0.state.failure?.reason == .locationUnavailable }) {
            await discardDisconnectedChanges(
                FolderLocationLoss(reason: .externalVolumeDisconnected, date: Date()))
            return result
        }
        let failed = result.outcomes.filter { $0.state.failure != nil }.map(\.identity)
        if !failed.isEmpty { try? await library.rereadMarks(for: failed) }
        finishPendingMarks(edits)
        refresh()
        if !failed.isEmpty { showSaveFailureToast() }
        return result
    }

    private func showSaveFailureToast() {
        guard folderLocationLoss == nil, !isSaveFailureToastVisible else { return }
        saveFailureToastBurst += 1
        isSaveFailureToastVisible = true
        isRejectMoveToastVisible = false
        UIAccessibility.post(notification: .announcement, argument: Self.saveFailureToastMessage)
    }

    /// The situation the open folder's own loss explains, or nil while it is reachable
    /// (PRD Failure and recovery, rows 3 and 6).
    var folderSituation: SaveSituation? {
        folderLocationLoss.map { SaveStatus.situation(for: $0) }
    }

    /// Drive loss drops queued work and pending marks; Reopen reads the files.
    private func discardDisconnectedChanges(_ loss: FolderLocationLoss) async {
        guard folderLocationLoss == nil else { return }
        folderLocationLoss = loss
        let dropped = actionPipeline.removePending()
        recordUndo(for: nil)
        desiredMarks.removeAll()
        storedPhotos = confirmedPhotos
        dismissSaveFailureToast()
        for entry in dropped {
            moveCompletions.removeValue(forKey: entry.id)?(.failure(RejectMoveRefusal.disabled))
        }
        await library.discardPendingChanges()
    }

    /// Checks the open folder's location now, as a return to the foreground asks (PRD P0-02).
    func checkFolderLocation() async {
        await library.checkFolderLocationNow()
    }

    /// Reopens the open folder through its Recents record (PRD P0-02).
    ///
    /// The disconnected-drive and lost-permission rows offer Reconnect/reopen, and C11 validates
    /// the location with a real read before anything is scanned again. Reopening the folder that
    /// is already open is not leaving it, so no question comes first. A folder that no longer
    /// opens lands on entry with its own reason on the matching Recents item, which is what
    /// PRD P0-02 asks for instead of a silent failure.
    func reopenOpenFolder() async {
        guard let folder = state.folder,
            let recent = recents.first(where: { $0.identity == folder })
        else {
            state.route = .entry
            return
        }
        await reopenNow(recent)
        if let failure = recentFailures[recent.id] {
            folderFailure = failure
            state.route = .entry
        }
    }

    /// Entry appears immediately; admitted writes finish before the folder releases its scope.
    private func leaveFolder() {
        let token = openRequests
        // The screen leaves the folder before anything that waits for its writes, so no
        // destination keeps the user on the old folder while C4 drains (G1 keeps the scope until
        // the work ends, but that is not something the user has to watch).
        if let lastViewed = state.currentPhoto { library.setEntryResumePhoto(lastViewed) }
        state.route = .entry
        hasLeftFolder = true
        state.folder = nil
        let generation = library.openGeneration
        let close = Task {
            await drainActions()
            // Every later open waits for this close, so it can only end this generation.
            guard library.openGeneration == generation, hasLeftFolder, state.folder == nil else {
                return
            }
            showEntryAfterLeaving()
            await library.closeFolder()
        }
        folderClose = close
        Task {
            await close.value
            guard token == openRequests else { return }
            await reloadRecents()
            entryPreviewGeneration += 1
        }
    }

    /// Shows entry and drops the closed folder's state at once (PRD Failure and recovery).
    ///
    /// The library ends the folder's session after admitted actions finish. The next open reads
    /// the actual XMP and Clove-stored marks. The filter and order survive, because they describe
    /// the grid rather than the folder that closed.
    private func showEntryAfterLeaving() {
        state.folder = nil
        state.currentPhoto = nil
        state.selection = []
        state.route = .entry
        folderLocationLoss = nil
        finishedScanFor = nil
        isFindingSimilarShots = false
        labelFilter = nil
        pendingRestore = nil
        hasLeftFolder = true
        // The closed folder's completed move cannot be undone through its ended session.
        lastRejectMove = nil
        isRejectMoveToastVisible = false
        confirmedPhotos = []
        storedPhotos = []
        photoIndices = [:]
        desiredMarks.removeAll()
        recordUndo(for: nil)
        dismissSaveFailureToast()
        groups = []
        thumbnails = library.thumbnails
        detailImages = library.detailImages
    }

    /// Restores this scene's saved state through CloveCore's validation (PRD P0-14).
    ///
    /// A saved scene that shows photos reopens its folder through C11 and shows that folder's
    /// grid at once, because a large RAW folder's metadata read must not hold the launch on entry.
    /// The saved photo, filter, order and selection stay pending and are validated by
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
        await reloadRecents()
        guard state == launchState else { return }
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
            // C11 reopened and validated the folder, so a loss buffered before this scene caught
            // up belongs to whatever was open then, not to what it shows now (PRD P0-02). The
            // open it just installed is the one this scene shows, even when the saved route is
            // entry or settings and the grid does not appear yet.
            folderLocationLoss = nil
            hasLeftFolder = false
            await reloadRecents()
            if saved.showsPhotos {
                showOpenFolder()
                pendingRestore = PendingBrowsingRestore(saved: saved, shown: state)
                // The scan can finish before this scene catches up.
                resolvePendingRestore(scanFinished: hasFinishedScan)
            } else {
                thumbnails = library.thumbnails
                detailImages = library.detailImages
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
        // A folder this scene left may still be closing; nothing it publishes may bring it back
        // (PRD P0-08's Leave anyway).
        guard !hasLeftFolder else { return }
        switch update {
        case .groupingActivity(let isRunning):
            isFindingSimilarShots = isRunning
        case .scanStarted:
            isFindingSimilarShots = false
            // A reopen of the same folder starts a new scan, so the old finished marker cannot
            // make the folder look ready before its new scan ends (PRD P0-01, P0-10).
            finishedScanFor = nil
            refresh()
        case .photos, .reads:
            refresh()
            resolvePendingRestore(scanFinished: false)
        case .markReadFailed:
            showSaveFailureToast()
        case .scanFinished:
            finishedScanFor = library.folder
            refresh()
            resolvePendingRestore(scanFinished: true)
            await reloadRecents()
        case .locationLost(let folder, let loss, let generation):
            // A buffered loss can arrive after another folder opened, or after the same folder
            // opened again, so it only applies to the folder and the open this scene shows.
            guard folder == library.folder, generation == library.openGeneration else { return }
            await discardDisconnectedChanges(loss)
            if let index = recents.firstIndex(where: { $0.identity == folder }) {
                recents[index].needsReconnect = true
            }
        case .groups(let groups):
            self.groups = groups
        }
    }

    /// Shows the grid on the folder the library just opened (PRD Entry, P0-01).
    ///
    /// A loss the last folder reported is not cleared here: opening the folder that is already
    /// open (entry's Continue browsing) never validated it again, so its warning stays until a
    /// real open or reopen reads it (PRD P0-02). A real open clears the loss itself.
    private func showOpenFolder() {
        hasLeftFolder = false
        state.folder = library.folder
        clearRecentFailureForOpenFolder()
        state.currentPhoto = nil
        state.selection = []
        state.route = .grid
        // The previous folder's completed move cannot be undone through this folder's session.
        lastRejectMove = nil
        isRejectMoveToastVisible = false
        // Whatever the folder published before this screen caught up (a scan batch that landed
        // while the old folder closed, or grouping's first result) is read here, so the grid
        // never waits for one more update (PRD P0-11).
        refresh()
        // The library replaced its pipeline with the folder's, so the grid takes the new source
        // even when the route does not change. Detail takes the source bound to the same folder.
        thumbnails = library.thumbnails
        detailImages = library.detailImages
    }

    /// Takes the library's current photos and groups.
    ///
    /// Scan batches, metadata reads and confirmed writes all refresh through this path, so the
    /// screens keep reading the model while the library changes underneath it.
    private func refresh() {
        if shownGeneration != library.openGeneration {
            shownGeneration = library.openGeneration
            desiredMarks.removeAll()
            recordUndo(for: nil)
            dismissSaveFailureToast()
        }
        confirmedPhotos = library.photos
        photoIndices = Dictionary(
            uniqueKeysWithValues: confirmedPhotos.enumerated().map { ($0.element.id, $0.offset) })
        storedPhotos = confirmedPhotos.map { photo in
            var shown = photo
            shown.marks = desiredMarks.shown(for: photo.id, confirmed: photo.marks)
            return shown
        }
        groups = library.groups
        reconcileRemovedPhotos()
    }

    /// Drops scene state that names a photo the folder no longer holds (PRD P0-10, P0-14).
    ///
    /// A confirmed move removes photos, so the selection and current photo must not point at
    /// one. The scan only adds photos, so this changes nothing during a normal scan; a detail
    /// route whose photo is gone returns to the grid, the same fallback a restore uses.
    private func reconcileRemovedPhotos() {
        let present = Set(photoIndices.keys)
        if !state.selection.isSubset(of: present) {
            state.selection.formIntersection(present)
        }
        if let current = state.currentPhoto, !present.contains(current) {
            state.currentPhoto = nil
            if state.route == .detail { state.route = .grid }
        }
    }
}

/// The latest completed Move rejects run, kept for the toast and C14's undo (PRD P0-10).
///
/// The result names every set the run moved, failed or skipped, and the kept identities are the
/// photos the person kept in the confirmation. C14's undo will move the files back and restore
/// Reject on both lists as one step; this task only keeps the value.
struct CompletedRejectMove: Sendable, Identifiable {
    /// The run's outcomes and its undo handle.
    let result: RejectMoveResult
    /// The ready sets the person kept, in the plan's order (PRD P0-10).
    let keptIdentities: [PhotoIdentity]
    /// The rejects folder name that run used, for the toast (PRD Move rejects).
    let rejectsFolderName: RejectsFolderName
    /// The folder open the run belonged to (PRD P0-02).
    let folder: FolderIdentity?
    /// The open generation the run belonged to, so a reopen invalidates it (PRD P0-02).
    let openGeneration: Int

    /// The run's id, so the grid can key the toast on it (PRD P0-10).
    var id: RejectMoveBatchID { result.id }

    var canUndo: Bool { !keptIdentities.isEmpty || !result.movedIdentities.isEmpty }
}
