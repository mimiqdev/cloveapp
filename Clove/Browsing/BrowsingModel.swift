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
final class BrowsingModel: UndoHistoryHost {
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

    /// The folder whose grouping has published a result (PRD P0-11).
    ///
    /// A saved group view names a group key, and grouping publishes keys only after the scan, so
    /// the pending restore waits for that first publication instead of dropping the place on
    /// every launch (PRD P0-14). The folder key keeps the answer with the folder that produced
    /// it, so a reopen that the scan answered before this scene caught up is not lost.
    private var groupsPublishedFor: FolderIdentity?

    /// The folder whose scan reported itself finished (PRD P0-01).
    ///
    /// The pending restore reads it when groups arrive, because the two can land in either order
    /// and the decision has to see the same scan state both times.
    private var finishedScanFor: FolderIdentity?

    /// Whether the open folder's grouping has published, even with no groups (PRD P0-11).
    private var groupsPublished: Bool { groupsPublishedFor == library.folder }

    /// Whether the open folder's scan reported itself finished (PRD P0-01).
    private var hasFinishedScan: Bool { finishedScanFor == library.folder }

    /// Whether the open folder is still opening, so the grid hides actions the handoff hides
    /// until the scan finishes (design handoff, PRD P0-01).
    var isFolderOpening: Bool { !hasFinishedScan }

    /// The library's current open generation, which changes when the same folder is reopened
    /// (PRD P0-02). A move that finishes across a change must not record against the new open.
    var openGeneration: Int { library.openGeneration }

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

    /// The open folder's location loss, as C11's watch reported it (PRD P0-02, P0-08).
    ///
    /// A loss explains the folder with the PRD's disconnected-drive or missing-location copy and
    /// keeps its unfinished changes from reading **Writing…** or **Saved**. It is cleared when
    /// another folder opens.
    private(set) var folderLocationLoss: FolderLocationLoss?

    /// The question standing before a destination that leaves the open folder, or nil
    /// (PRD Failure and recovery, last row).
    private(set) var leavePrompt: LeaveFolderPrompt?

    /// Whether **Wait for writes** is draining C4 before the question is answered again.
    private(set) var isWaitingForWrites = false

    /// Whether this scene left its folder and is ignoring that folder's updates until a real open
    /// shows another one (PRD P0-08's Leave anyway).
    ///
    /// The library keeps the departed folder's photos until its session drains, so without this
    /// a confirmed write could refresh them back onto entry and bring Continue browsing with it.
    private var hasLeftFolder = false

    /// How many opens this scene started, so a leaving destination never replaces a folder the
    /// user opened while it waited (PRD P0-08).
    private var openRequests = 0

    /// The saved scene waiting for its folder to hold the photos it names (PRD P0-14).
    ///
    /// It applies as soon as the scan delivered them, at the latest when the scan finishes, and
    /// is dropped if the user navigates or opens another folder first.
    private var pendingRestore: PendingBrowsingRestore?

    /// This scene's bridge to the system undo manager (PRD P0-05).
    ///
    /// It is created with the model and attached to the window's `UndoManager` by whichever
    /// screen offers Undo, so the toolbar button, ⌘Z and the three-finger gestures all reach this
    /// one history (``UndoHistoryBridge``).
    private let undoBridge = UndoHistoryBridge()

    /// What the open folder's undo history offers the toolbar (PRD P0-05).
    ///
    /// The library keeps the history and is not observable, so the model copies its answer here
    /// after every record, undo and redo; that is what redraws a screen's Undo button.
    private(set) var undoAvailability: UndoAvailability = .none

    /// The last undo or redo step's partial failure, or nil (PRD P0-09).
    ///
    /// PRD P0-08's failure row and the folder indicator show the per-photo states themselves; this
    /// keeps C5's counts and the Retry that belongs to them, because a failed restore keeps its
    /// entry and the Undo button is then its retry.
    private(set) var undoFailure: UndoFailure?

    /// How many times a step returned the view to a photo (PRD P0-05's Undo row).
    ///
    /// A screen holding a pending auto-advance drops it when this changes, so the advance the
    /// undone mark started cannot move the view off the photo the undo restored
    /// (PRD Auto-advance).
    private(set) var undoReturnCount = 0

    /// The last finishing action's result for each group, so a redo can bring the group view's own
    /// completion state back with C10's record (PRD P0-12).
    private var finishingResults: [GroupID: GroupFinishingResult] = [:]

    /// The groups whose finishing record an undo cleared, so the group view stops treating them as
    /// finished until a redo restores them (PRD P0-12).
    private var clearedFinishingGroups: Set<GroupID> = []

    /// How many actions this folder's history recorded, so a failure row knows whether its step is
    /// still the newest action (PRD P0-08).
    private var recordedActions = 0

    /// How many writes this scene started and has not seen finish (PRD P0-05).
    ///
    /// A step waits for them before it reads the marks, so it never runs between recording an
    /// action and C4 admitting that action's writes.
    private var writesInFlight = 0

    /// Callers waiting for ``writesInFlight`` to reach zero.
    private var writeIdleWaiters: [CheckedContinuation<Void, Never>] = []

    /// The photo the grid must bring into view after an undo, with a token per request
    /// (PRD P0-05's Undo row).
    private(set) var gridReveal: GridRevealRequest?

    /// How many grid reveals this scene asked for, so a repeated photo is a new request.
    private var gridReveals = 0

    /// The task applying the library's updates on the main actor (PRD P0-03, P0-08).
    private var updateTask: Task<Void, Never>?

    /// Creates the model over one library, starting at entry unless a state is passed in.
    init(library: any FolderLibrary, state: BrowsingState = .entry) {
        self.library = library
        self.state = state
        self.groups = library.groups
        self.recents = library.recents
        self.thumbnails = library.thumbnails
        self.detailImages = library.detailImages
        self.recentFailures = [:]
        self.storedPhotos = library.photos
        // The bridge asks this model for every step, so both entry points share one path to the
        // open folder's history and the system undo manager.
        undoBridge.host = self
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

    /// The detail view's source for the open folder (PRD P0-04).
    ///
    /// It is kept beside ``thumbnails`` for the same reason: the source is bound to one folder's
    /// I2 pipeline and C11 session, so detail must read the source that belongs to the folder
    /// that is open now, never a pipeline whose folder ended.
    private(set) var detailImages: any DetailImageSource

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

    /// The group the group view shows, from grouping's published groups (PRD P0-11, P0-12).
    ///
    /// The view keeps only the group's key and the photo it is on in ``state``, so a fold or a
    /// relaunch reads the group back from the folder's publication rather than from a copy
    /// (PRD P0-14).
    var currentGroup: BrowsingGroup? {
        guard let position = state.groupPosition else { return nil }
        return groups.first { $0.id == position.group }
    }

    /// The photo the group view shows, with its current marks (PRD P0-12).
    var groupPhoto: GridPhoto? {
        guard let id = state.groupPosition?.photo else { return nil }
        return groupPhotos.first { $0.id == id }
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
        openRequests += 1
        pendingRestore = nil
        folderFailure = nil
        showOpenFolder()
    }

    /// Opens the folder the user chose in the system picker (PRD P0-01, P0-02).
    ///
    /// The library performs C11's validating read; a failure stays on the model so entry explains
    /// it and asks for the folder again, while a success shows the grid as the scan streams in.
    /// With unfinished writes in the open folder, the question comes first (PRD P0-08).
    func openPickedFolder(_ url: URL) async {
        pendingRestore = nil
        guard askBeforeLeaving(.picked(url)) else { return }
        await openPickedFolderNow(url)
    }

    /// Opens a folder the user chose, once any leaving question is answered (PRD P0-01).
    private func openPickedFolderNow(_ url: URL) async {
        openRequests += 1
        // An earlier folder's loss and save states do not apply to whatever this open installs.
        // Clearing the loss before the await keeps a loss the new open reports (PRD P0-02).
        folderLocationLoss = nil
        folderFailure = await library.pick(url)
        guard folderFailure == nil else { return }
        // PRD Failure and recovery: a real open reads the actual XMP, so what is on screen starts
        // from this open's changes and never from a failure the closed folder left behind.
        changes = PhotoChangeStates()
        showOpenFolder()
        await reloadRecents()
    }

    /// Reopens one remembered folder (PRD P0-02).
    ///
    /// A failed reopen keeps C11's reason on that item, so entry can explain it there and ask for
    /// the folder again instead of failing silently. With unfinished writes in the open folder,
    /// the question comes first; reopening the folder that is already open is not leaving it.
    func reopen(_ recent: RecentFolder) async {
        pendingRestore = nil
        guard askBeforeLeaving(.recent(recent)) else { return }
        await reopenNow(recent)
    }

    /// Reopens one remembered folder, once any leaving question is answered (PRD P0-02).
    private func reopenNow(_ recent: RecentFolder) async {
        openRequests += 1
        // The reopen reads the folder again, so the loss the watch reported is no longer current,
        // and a loss the new open reports after the await still applies (PRD P0-02).
        folderLocationLoss = nil
        if let failure = await library.reopen(recent) {
            recentFailures[recent.id] = failure
            return
        }
        recentFailures[recent.id] = nil
        folderFailure = nil
        // The reopened folder reads its XMP and Clove-stored marks again, so the states from the
        // previous open are gone (PRD Failure and recovery).
        changes = PhotoChangeStates()
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

    /// Moves the open group view to another member (PRD P0-12).
    func showGroupPhoto(_ photo: PhotoIdentity) {
        guard let position = state.groupPosition else { return }
        state.groupPosition = BrowsingGroupPosition(group: position.group, photo: photo)
    }

    // MARK: - In-group culling

    /// The last finishing action the group view ran, with its result and C5's undo record
    /// (PRD P0-12: finishing actions can be undone).
    ///
    /// The result carries ``GroupFinishingResult/undo``, so one property holds both what the
    /// group view shows and what U8 records as one undo entry. A later action or a retry replaces
    /// the group's result, and an undo hides it until a redo restores it, so the group view reads
    /// the record that belongs to the group it is showing.
    var lastGroupFinishing: GroupFinishingResult? {
        guard let group = state.groupPosition?.group, let result = finishingResults[group],
            !clearedFinishingGroups.contains(group)
        else { return nil }
        return result
    }

    /// Whether a finishing action is running, so the group view holds its completion until the
    /// action's per-photo result arrives (PRD P0-12; PRD P0-09).
    ///
    /// A finishing action's marks stream in one photo at a time, so the group can look complete
    /// before the action returns and its failures are known; advancing meanwhile would hide the
    /// retry (PRD Failure and recovery).
    private(set) var isRunningGroupFinishing = false

    /// Counts the finishing actions and retries this scene has run (PRD P0-12).
    ///
    /// Two finishing actions can produce equal results — Keep rated on a group that is already
    /// fully decided changes nothing — so the group view needs an identity for the event itself,
    /// not only for the value it produced.
    private(set) var groupFinishingRuns = 0

    /// The finishing action the user already dismissed, so its bar does not return on the next
    /// redraw (PRD Failure and recovery: Cancel hides it without retrying).
    private var dismissedGroupFailure: GroupFinishingResult?

    /// The finishing action's result while it still has changes to retry, or nil
    /// (PRD P0-09; PRD Failure and recovery).
    ///
    /// U4's batch bar and this one report the same counts, and a confirmed change is never part
    /// of a retry. Dismissing hides the bar without retrying, which leaves the failed changes
    /// unsaved (PRD P0-08).
    var groupFinishingFailure: GroupFinishingResult? {
        guard let result = lastGroupFinishing, result != dismissedGroupFailure,
            result.failedCount > 0
        else { return nil }
        return result
    }

    /// Runs one finishing action's plan in the open folder session and keeps its result
    /// (PRD In-group culling, finishing actions; PRD P0-12).
    ///
    /// The library applies C10's plan through C4's write queue, so per-photo results, the
    /// partial-failure counts and a retry of only the failed items all come from one place
    /// (PRD P0-09). Only one finishing action runs at a time: a second request while one is
    /// running is ignored, because two overlapping results would each clear the running flag
    /// and let completion move the view before the last result's failures are known.
    func runGroupFinishing(_ plan: GroupFinishingPlan) async {
        guard !isRunningGroupFinishing else { return }
        let folder = state.folder
        dismissedGroupFailure = nil
        isRunningGroupFinishing = true
        let result = await runWrite { await library.runGroupFinishing(plan) }
        isRunningGroupFinishing = false
        // The action happened, but its result must not land in another folder's group view or
        // make U8 undo a mark in a folder it does not belong to (PRD P0-14).
        guard state.folder == folder else { return }
        finishingResults[plan.groupID] = result
        clearedFinishingGroups.remove(plan.groupID)
        groupFinishingRuns += 1
        // One finishing action is one undo step, from C10's own record of what it changed
        // (PRD P0-12). A retry resends its failed changes and records nothing more.
        await recordUndoStep(.groupFinishing(result.undo))
    }

    /// Retries only the changes that still need it, through C4 (PRD P0-09).
    ///
    /// It shares the one-action-at-a-time rule with ``runGroupFinishing(_:)``, so a retry can
    /// never overlap the action it retries.
    func retryGroupFinishing() async {
        guard !isRunningGroupFinishing, let result = lastGroupFinishing else { return }
        let folder = state.folder
        dismissedGroupFailure = nil
        isRunningGroupFinishing = true
        let retried = await runWrite { await library.retryGroupFinishing(result) }
        isRunningGroupFinishing = false
        // A retry that returns after the folder changed belongs to the folder that is gone.
        guard state.folder == folder else { return }
        finishingResults[retried.plan.groupID] = retried
        clearedFinishingGroups.remove(retried.plan.groupID)
        groupFinishingRuns += 1
    }

    /// Hides the finishing action's failure without retrying it (PRD Failure and recovery).
    func dismissGroupFinishingFailure() {
        dismissedGroupFailure = lastGroupFinishing
    }

    /// Moves the group view on when its group is complete, following C12's setting
    /// (PRD In-group culling, group completion; PRD P0-12).
    ///
    /// A complete group either stays (the setting says stay) or opens the next group in grid
    /// order that is not complete, skipping completed ones. With no incomplete group left, the
    /// view returns to the grid. The answer comes from the folder session's completion record,
    /// which the finishing executor writes and the marks complete, so the view never derives a
    /// second rule (``GroupViewCompletion``).
    ///
    /// The group, the route and the task are re-checked after the query: leaving the group view,
    /// opening another group or a finishing failure that arrives meanwhile each cancel the move,
    /// and none of them may be overridden by the answer to a question asked before it.
    func advanceFromCompletedGroup(_ behaviour: GroupCompletionBehaviour) async {
        guard state.route == .group, let position = state.groupPosition else { return }
        let completion = await library.groupCompletion(
            for: position.group, behaviour: behaviour)
        let failure = groupFinishingFailure
        guard !Task.isCancelled, state.route == .group,
            state.groupPosition?.group == position.group,
            failure?.plan.groupID != position.group
        else { return }
        switch completion {
        case .inProgress, .stay:
            break
        case .nextGroup(let group):
            openGroup(group)
        case .grid:
            state.groupPosition = nil
            state.route = .grid
        }
    }

    /// Shows Clove's settings (PRD Gesture-related settings).
    func showSettings() {
        state.route = .settings
    }

    /// Returns to the screen the current one came from (PRD P0-13).
    ///
    /// The grid's parent is entry, and detail and the group view return to the grid. Settings
    /// keeps the folder it was opened over, so closing them returns to the grid when a folder is
    /// open and to entry when none is. Going back from the grid leaves the folder, so PRD Failure
    /// and recovery's question comes first when something is unfinished.
    func back() {
        switch state.route {
        case .entry:
            break
        case .grid:
            guard askBeforeLeaving(.entry) else { return }
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

    /// How many times the bar dismissed its report, so a retry that finishes after Cancel does
    /// not bring the report the user dismissed back (PRD P0-09).
    private var reportDismissals = 0

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
        guard !isApplyingBatch, !isMovingRejects else { return }
        let targets = batchTargets
        let plan = BatchMarkPlan(action: action, photos: targets, settings: settings)
        guard !plan.items.isEmpty else { return }
        var marksBefore: [PhotoIdentity: PhotoMarks] = [:]
        for photo in targets { marksBefore[photo.id] = photo.marks }
        let folder = state.folder
        let clearances = selectionClearances
        isApplyingBatch = true
        defer { isApplyingBatch = false }
        // One bar action is one undo step, whatever the number of photos it writes. It is recorded
        // when the action starts, so a slow write cannot put it after an action taken later
        // (PRD P0-09, P0-05).
        await recordUndoStep(.batch(items: plan.items, marksBefore: marksBefore))
        guard state.folder == folder else { return }
        let result = await runWrite { await library.apply(plan.items) }
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
        guard !isApplyingBatch, !isMovingRejects, let report = batchReport, report.canRetry
        else { return }
        let folder = state.folder
        let clearances = selectionClearances
        let dismissals = reportDismissals
        isApplyingBatch = true
        defer { isApplyingBatch = false }
        guard let result = await runWrite({ await library.retryFailed(in: report.batch) }),
            state.folder == folder, clearances == selectionClearances,
            dismissals == reportDismissals
        else { return }
        batchReport = report.merging(result)
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

    /// How many times a move toast was shown, so a retry restarts its timer even when C14 keeps
    /// the same batch ID (PRD P0-10).
    private(set) var rejectMoveToastAttempt = 0

    /// Whether a Move rejects run is in progress (PRD P0-10).
    ///
    /// C6 drains the mark queue before it moves and skips a set with an unfinished mark change,
    /// so marking stays blocked for the whole run: the detail controls and the batch bar cannot
    /// start a write that would target a path the move is about to change.
    private(set) var isMovingRejects = false

    /// The progress steps of the next or running Move rejects (PRD P0-10).
    func rejectMoveProgress() async -> AsyncStream<RejectMoveProgress> {
        await library.rejectMoveProgress()
    }

    /// Plans Move rejects for the open folder's rejected photos (PRD P0-10).
    ///
    /// The plan is the confirmation sheet's input; nothing moves until ``runRejectMove(_:)``.
    /// The configuration is read from settings by the caller at move time, so a renamed folder
    /// applies without reopening the folder (PRD Move rejects, C12).
    func planRejectMove(configuration: RejectMoveConfiguration) async throws -> RejectMovePlan {
        try await library.planRejectMove(configuration: configuration)
    }

    /// Runs a confirmed Move rejects plan (PRD P0-10).
    ///
    /// The library drops every confirmed set from its photos and publishes the change through
    /// ``FolderLibrary/updates``, so the grid loses the moved photos and ``refresh()`` reconciles
    /// the selection, current photo and group place with what remains. The flag is set before the
    /// wait and cleared on every exit path, so a failed run never leaves marking blocked.
    func runRejectMove(_ plan: RejectMovePlan) async throws -> RejectMoveResult {
        guard !isMovingRejects else { throw RejectMoveRefusal.disabled }
        isMovingRejects = true
        defer { isMovingRejects = false }
        return try await library.runRejectMove(plan)
    }

    /// Records one completed move, so the toast can show it and C14 can undo it (PRD P0-10).
    func recordRejectMove(
        _ result: RejectMoveResult, keptIdentities: [PhotoIdentity],
        rejectsFolderName: RejectsFolderName, folder: FolderIdentity?, openGeneration: Int
    ) {
        lastRejectMove = CompletedRejectMove(
            result: result, keptIdentities: keptIdentities, rejectsFolderName: rejectsFolderName,
            folder: folder, openGeneration: openGeneration)
        isRejectMoveToastVisible = true
        rejectMoveToastAttempt += 1
    }

    /// Hides the move toast while keeping the completed move for a later undo (PRD P0-10).
    func dismissRejectMoveToast() {
        isRejectMoveToastVisible = false
    }

    /// Retries a completed move's failed sets and keeps the moved ones in the record (P0-10).
    ///
    /// The retry's outcomes replace only the failures, so the toast and C14's record still count
    /// every photo the run moved. A batch the library can no longer retry answers nil.
    func retryRejectMove(_ completed: CompletedRejectMove) async throws -> RejectMoveResult? {
        guard !isMovingRejects else { throw RejectMoveRefusal.disabled }
        // The details sheet can outlive its folder open. A record from another open must not
        // clear Reject or move anything in the replacement, even when the folder identity is the
        // same after a reopen (PRD P0-02, P0-10).
        guard
            completed.openGeneration == openGeneration, completed.folder == state.folder
        else { return nil }
        let folder = completed.folder
        let generation = completed.openGeneration
        let selection = RejectMoveRetrySelection(
            result: completed.result,
            keptIdentities: Set(completed.keptIdentities),
            rejectedIdentities: Set(
                storedPhotos.filter(\.marks.isRejected).map(\.id)))
        guard
            selection.hasRetryableMoves || !selection.clearFailures.isEmpty
                || !selection.noLongerRejected.isEmpty
        else { return nil }
        isMovingRejects = true
        defer { isMovingRejects = false }

        // C6 first, without the failures whose Reject was cleared. If its batch is gone, nothing
        // else changes and the details sheet can report the failure.
        var retried: RejectMoveResult?
        if selection.hasRetryableMoves {
            guard
                let result = try await library.retryFailedRejects(
                    in: completed.result.id, excluding: selection.excludedFromRetry)
            else { return nil }
            retried = result
        }

        guard state.folder == folder, openGeneration == generation else { return nil }

        // A kept photo's Reject clear is a C4 write, not a C6 move, so it is retried through the
        // same mark path. An unresolved one stays in the failure list for the next attempt.
        var clearing = RejectMoveKeepClearing()
        for set in selection.clearFailures {
            guard state.folder == folder, openGeneration == generation else { return nil }
            let status = await library.apply(.reject(false), to: set.identity)
            clearing.record(status, for: set.identity, files: set.files)
        }
        guard state.folder == folder, openGeneration == generation else { return nil }

        let combined = RejectMoveRetryMerge.result(
            previous: completed.result, retried: retried,
            unresolvedClearFailures: clearing.clearFailures,
            noLongerRejected: selection.noLongerRejected.map(\.identity))
        lastRejectMove = CompletedRejectMove(
            result: combined, keptIdentities: completed.keptIdentities,
            rejectsFolderName: completed.rejectsFolderName,
            folder: completed.folder, openGeneration: completed.openGeneration)
        isRejectMoveToastVisible = true
        rejectMoveToastAttempt += 1
        return combined
    }

    /// Dismisses the batch's report without retrying (PRD Failure and recovery: Cancel).
    ///
    /// A retry that is already running will not put the report back, so Cancel leaves the bar
    /// without a failure report; the photos that did not save keep their failed status for U7.
    func dismissBatchReport() {
        batchReport = nil
        reportDismissals += 1
    }

    /// The latest change to one photo with its save state, or nil when nothing was requested
    /// (PRD P0-08). U7 reads the same status for its retry.
    func latestChange(for photo: PhotoIdentity) -> MarkChangeStatus? {
        changes.latest(for: photo)
    }

    /// The marks in-group culling reads for one photo, including a requested change C4 has not
    /// saved yet (PRD P0-12; PRD How marks reach disk, rule 8).
    ///
    /// A finishing action must never reject a photo whose rating or colour label the user has
    /// already asked for, and auto-advance can bring the next photo onto the screen while the
    /// previous photo's write is still running. C4 keeps a request's marks until a newer change
    /// replaces them, so an unfinished change counts as marked here, exactly as it does in the
    /// open folder's own re-check (``FolderLibrary/runGroupFinishing(_:)``).
    func cullingMarks(for photo: GridPhoto) -> PhotoMarks {
        guard let latest = latestChange(for: photo.id), latest.state.isUnfinished else {
            return photo.marks
        }
        return photo.marks.including(latest.requested)
    }

    /// Applies one change to one photo through the library and shows its marks and save state
    /// (PRD P0-08).
    ///
    /// The await is C4's write queue. The change's states arrive only through the library's
    /// ordered stream, never from this call's return: a returned status can arrive after a newer
    /// change was admitted, which would let an older finished state paint over the newer one
    /// (``PhotoChangeStates``). A failed write therefore never shows a mark it did not confirm.
    /// The returned status is still the authority for the undo record, so a change a newer one
    /// superseded records no step (PRD P0-05).
    @discardableResult
    func apply(_ change: MarkChange, to photo: PhotoIdentity) async -> MarkChangeStatus? {
        guard !isMovingRejects, !change.isEmpty else { return nil }
        // PRD P0-05's Undo row restores the previous mark, so the marks on screen before the
        // change are the ones undo puts back; a field the user did not see is never restored.
        let folder = state.folder
        let marksBefore = storedPhotos.first { $0.id == photo }?.marks ?? PhotoMarks()
        // The action is recorded when it starts, so the history keeps the user's order and Undo is
        // live while the write runs; a step waits for this scene's writes before it reads marks.
        await recordUndoStep(.mark(change: change, photo: photo, marksBefore: marksBefore))
        guard state.folder == folder else { return nil }
        return await runWrite { await library.apply(change, to: photo) }
    }

    /// Runs one library write and keeps the scene's in-flight count (PRD P0-05).
    ///
    /// A step waits for these writes before it reads any marks, so it cannot undo an action that
    /// the history already holds while C4 has not admitted that action's write yet.
    private func runWrite<T>(_ write: () async -> T) async -> T {
        writesInFlight += 1
        defer {
            writesInFlight -= 1
            if writesInFlight == 0 {
                let waiters = writeIdleWaiters
                writeIdleWaiters = []
                for waiter in waiters { waiter.resume() }
            }
        }
        return await write()
    }

    /// Waits until this scene's own writes have finished (PRD P0-05).
    private func waitForPendingWrites() async {
        while writesInFlight > 0 {
            await withCheckedContinuation { writeIdleWaiters.append($0) }
        }
    }

    // MARK: - Undo

    /// Whether the open folder has an action to undo (PRD P0-05).
    ///
    /// PRD P0-05's Undo row asks for a toolbar Undo that is disabled when there is nothing to
    /// undo, and for the same answer on ⌘Z, so both read this one value.
    var canUndo: Bool { undoAvailability.canUndo }

    /// Whether there is an undone action to redo, which ⇧⌘Z and the redo gesture offer
    /// (PRD P0-05).
    var canRedo: Bool { undoAvailability.canRedo }

    /// Attaches the scene's undo manager to this model's undo bridge (PRD P0-05).
    ///
    /// Every screen that offers Undo attaches the manager it finds; the bridge keeps the first one
    /// for the scene, so the split layout's grid and detail registering the same manager changes
    /// nothing and one action is never applied twice.
    func attachUndoManager(_ manager: UndoManager?) {
        undoBridge.attach(manager)
    }

    /// Undoes the open folder's next action, from a toolbar button (PRD P0-05).
    ///
    /// The bridge routes it through the scene's undo manager while that manager holds the same
    /// step, so the button and ⌘Z are one path and one press is one action.
    func undo() {
        undoBridge.requestUndo()
    }

    /// Redoes the next undone action, for ⇧⌘Z and the three-finger redo gesture (PRD P0-05).
    func redo() {
        undoBridge.requestRedo()
    }

    /// Undoes the history's next action through the open folder and returns the view to its photo
    /// (PRD P0-05).
    func undoThroughHistory() async -> UndoStepResult? {
        await applyUndoStep(isRedo: false) { await library.undoMarkChange() }
    }

    /// Redoes the history's next undone action through the open folder (PRD P0-05).
    func redoThroughHistory() async -> UndoStepResult? {
        await applyUndoStep(isRedo: true) { await library.redoMarkChange() }
    }

    /// Retries a failed undo or redo step in the direction it failed (PRD P0-08).
    ///
    /// C5 keeps a failed step's entry, so running the same direction again is the retry; U7's
    /// per-photo Retry resends the individual writes as well.
    func retryFailedUndoStep() {
        guard let failure = undoFailure else { return }
        if failure.isRedo {
            redo()
        } else {
            undo()
        }
    }

    /// Records one change on the open folder's undo history (PRD P0-05, P0-09, P0-12).
    ///
    /// Every kind of step goes through this one call, so one action is one entry. A mark and a bar
    /// action are recorded when they start, before their writes finish, so the history keeps the
    /// order the user acted in and Undo is live while the write runs; a step waits for the scene's
    /// own writes before it reads any marks (``applyUndoStep(isRedo:_:)``). A finishing action is
    /// recorded from C10's own record of what it changed. A retry resends an already recorded
    /// change, so it records nothing and never gives one action two entries.
    private func recordUndoStep(_ request: UndoRecordRequest) async {
        // A new action discards the redo future (PRD P0-05), so a failure the user could have
        // retried no longer belongs to the action that is next.
        undoFailure = nil
        guard await library.recordUndoStep(request) else {
            undoAvailability = library.undoAvailability
            return
        }
        undoAvailability = library.undoAvailability
        recordedActions += 1
        // The history gained a step, so the system undo stack mirrors it once, here.
        undoBridge.historyDidRecord()
    }

    /// Runs one undo or redo through the library and applies its answer (PRD P0-05, P0-12).
    private func applyUndoStep(
        isRedo: Bool, _ step: () async -> UndoStepResult?
    ) async -> UndoStepResult? {
        // The screen that asked decides where the view returns to, and the folder the step belongs
        // to must still be the open one when it answers (PRD P0-14).
        let folder = state.folder
        // A step reads the marks C4 has now, so it waits for the writes this scene started: an
        // undo can otherwise run between recording a mark and that mark reaching the queue.
        await waitForPendingWrites()
        let screen = undoReturnScreen
        let recorded = recordedActions
        guard let result = await step() else {
            undoAvailability = library.undoAvailability
            return nil
        }
        guard state.folder == folder else { return nil }
        undoAvailability = library.undoAvailability
        // A newer action recorded during the step takes the failed entry's place at the top of the
        // history, so its retry would run that newer action instead; U7 still shows the writes.
        undoFailure =
            recordedActions == recorded
            ? result.failureSummary.map { UndoFailure(summary: $0, isRedo: isRedo) }
            : nil
        applyCompletionChange(result.completion)
        returnToPhoto(after: result, from: screen)
        return result
    }

    /// Applies the completion a finishing-action step changed (PRD P0-12).
    ///
    /// PRD In-group culling makes a group complete when a finishing action ran, so undoing that
    /// action must stop the group view treating the group as finished; the marks the step restores
    /// make it incomplete again on their own. Redoing the action restores both C10's record and the
    /// model's own copy, so the group view recognises the completion again.
    private func applyCompletionChange(_ change: UndoCompletionChange?) {
        guard let change else { return }
        if change.isCleared {
            clearedFinishingGroups.insert(change.groupID)
            dismissedGroupFailure = nil
        } else {
            clearedFinishingGroups.remove(change.groupID)
        }
    }

    /// Returns the view to the photo the step restored (PRD P0-05's Undo row).
    ///
    /// The screen that asked decides the place: detail shows the photo again, the group view shows
    /// it in its group — reopening a group that completed and moved the view on (PRD P0-12) — and
    /// the grid brings its cell into view. Entry and settings show no photo and stay where they
    /// are (``MarkUndoReturnPlan``).
    private func returnToPhoto(after result: UndoStepResult, from screen: MarkUndoReturnScreen) {
        let place = MarkUndoReturnPlan.place(
            from: screen, photo: result.photoToReturnTo, in: library.contents)
        guard place != .stay else { return }
        // A screen holding the auto-advance the undone mark started drops it now, so the step's
        // photo is the one the user sees (PRD Auto-advance, PRD P0-05).
        undoReturnCount += 1
        switch place {
        case .detail(let photo):
            openPhoto(photo)
        case .group(let group, let photo):
            state.groupPosition = BrowsingGroupPosition(group: group, photo: photo)
            state.route = .group
        case .grid(let photo):
            // A photo grouping no longer puts in a group has no group view to show, so the grid
            // takes the place the group view would have had.
            if state.route == .group {
                state.groupPosition = nil
                state.route = .grid
            }
            state.currentPhoto = photo
            gridReveals += 1
            gridReveal = GridRevealRequest(photo: photo, token: gridReveals)
        case .stay:
            break
        }
    }

    /// The screen the undo was asked from, which decides where the view returns (PRD P0-05).
    private var undoReturnScreen: MarkUndoReturnScreen {
        switch state.route {
        case .detail:
            return .detail
        case .group:
            return .group
        case .grid:
            return .grid
        case .entry, .settings:
            return .elsewhere
        }
    }

    // MARK: - Save state and recovery

    /// The folder indicator's one line (PRD P0-08).
    ///
    /// It summarises every photo's latest change in the open folder, so it never claims Saved
    /// for a write C4 has not confirmed and never misses a photo whose change failed.
    var saveSummary: FolderSaveSummary {
        FolderSaveSummary(states: storedPhotos.compactMap { changes.latest(for: $0.id)?.state })
    }

    /// What the marking HUD's save-state line says for one photo (PRD P0-08).
    ///
    /// PRD P0-08 shows **Saved** only for a confirmed sidecar write and **Saved in Clove only**
    /// only for confirmed Clove storage; a Clove-stored Reject reads **Stored in Clove** because
    /// G1 decision 5 keeps the word Saved for XMP writes and a confirmed move.
    func saveText(for photo: PhotoIdentity) -> String {
        SaveStatus.text(
            for: latestChange(for: photo)?.state, folderLost: folderLocationLoss != nil)
    }

    /// The situation the open folder's own loss explains, or nil while it is reachable
    /// (PRD Failure and recovery, rows 3 and 6).
    var folderSituation: SaveSituation? {
        folderLocationLoss.map { SaveStatus.situation(for: $0) }
    }

    /// The photos whose change has not finished saving, in grid order (PRD P0-08).
    ///
    /// The indicator's count opens this list, so each row can retry exactly one photo and the
    /// whole list can retry them all with the same per-photo call.
    var unsavedChanges: [UnsavedChange] {
        storedPhotos.compactMap { photo in
            guard let status = changes.latest(for: photo.id), status.state.isUnfinished else {
                return nil
            }
            return UnsavedChange(
                id: status.id, photo: photo.id, fileName: photo.fileName, state: status.state)
        }
    }

    /// Whether leaving the open folder asks first (PRD Failure and recovery, last row).
    var leaveConfirmation: LeaveFolderConfirmation {
        LeaveFolderConfirmation(
            states: storedPhotos.compactMap { changes.latest(for: $0.id)?.state })
    }

    /// Resends one photo's latest failed change through C4 (PRD P0-08).
    ///
    /// The retry's transitions arrive on the library's ordered stream like any other change, so a
    /// retried change shows **Writing…** and then only what its storage confirmed. PRD How marks
    /// reach disk, rule 8, keeps a superseded change from being retried (the library reads the
    /// photo's latest change).
    func retryLatestChange(for photo: PhotoIdentity) async {
        _ = await runWrite { await library.retryLatestChange(for: photo) }
    }

    /// Retries every photo the indicator lists, one call per photo (PRD P0-08).
    func retryAllUnfinishedChanges() async {
        for change in unsavedChanges {
            await retryLatestChange(for: change.photo)
        }
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

    /// Waits for C4 to finish, then answers the leaving question again (PRD P0-08).
    ///
    /// **Wait for writes** keeps the question on screen with a visible waiting state, and PRD
    /// Failure and recovery lets the user still choose **Leave anyway**. Once every change is
    /// confirmed the user's answer proceeds to the destination they named; a change that failed
    /// stays unfinished and keeps the question, so nobody leaves believing it was saved.
    func waitForWrites() async {
        guard let prompt = leavePrompt, !isWaitingForWrites else { return }
        isWaitingForWrites = true
        await library.drainWrites()
        // Cancel, Leave anyway or a new question may have replaced the one that started this wait,
        // and a stale waiter must never answer the newer question or clear its progress.
        guard leavePrompt?.id == prompt.id else { return }
        // The queue's own answer is authoritative: a streamed status can still be on its way to
        // this screen when the drain returns, and the question must not stay over confirmed work.
        let unfinished = await library.hasUnfinishedWrites()
        // Answering takes another await, so the question can have been cancelled or replaced
        // meanwhile; a stale waiter never acts on the newer one.
        guard leavePrompt?.id == prompt.id else { return }
        isWaitingForWrites = false
        guard !unfinished else { return }
        await leave(to: prompt.destination)
    }

    /// Leaves the open folder now, without reporting its unconfirmed changes as saved
    /// (PRD Failure and recovery, last row).
    func leaveAnyway() async {
        guard let prompt = leavePrompt else { return }
        await leave(to: prompt.destination)
    }

    /// Dismisses the leaving question and stays in the folder (PRD Failure and recovery).
    func cancelLeave() {
        leavePrompt = nil
        isWaitingForWrites = false
    }

    /// Shows the question when the destination leaves the open folder with unfinished writes.
    ///
    /// - Returns: `false` when the question is now open and the destination must wait for the
    ///   answer, `true` when the caller may proceed.
    private func askBeforeLeaving(_ destination: LeaveFolderDestination) -> Bool {
        guard leavesWithUnfinishedWrites(destination) else { return true }
        leavePrompt = LeaveFolderPrompt(destination: destination)
        // A question that was cancelled mid-wait must not leave the new one's Wait disabled.
        isWaitingForWrites = false
        return false
    }

    /// Whether the destination leaves the open folder while something is unfinished.
    ///
    /// Reopening the folder that is already open is not leaving it, and a scene with no open
    /// folder has nothing to leave (PRD Failure and recovery).
    private func leavesWithUnfinishedWrites(_ destination: LeaveFolderDestination) -> Bool {
        guard state.folder != nil else { return false }
        if case .recent(let recent) = destination, recent.identity == state.folder { return false }
        return leaveConfirmation.shouldAsk
    }

    /// Performs the destination the user chose after the question (PRD P0-08).
    ///
    /// Leaving for entry shows entry before the folder closes, so **Leave anyway** never waits for
    /// C4 the way **Wait for writes** does: the library still ends the session and releases C11's
    /// scope, but the screen is already where the user asked to be (PRD Failure and recovery, last
    /// row).
    private func leave(to destination: LeaveFolderDestination) async {
        leavePrompt = nil
        isWaitingForWrites = false
        let token = openRequests
        // The screen leaves the folder before anything that waits for its writes, so no
        // destination keeps the user on the old folder while C4 drains (G1 keeps the scope until
        // the work ends, but that is not something the user has to watch).
        showEntryAfterLeaving()
        // Leaving closes the folder even when the next destination never opens, so its scan stops
        // and its scope is not held for a folder the user no longer sees (G1 folder access).
        await library.closeFolder()
        // A folder the user opened while the close drained wins: the destination they were
        // heading for before that must not replace it (PRD P0-08).
        guard token == openRequests else { return }
        switch destination {
        case .entry:
            break
        case .picked(let url):
            await openPickedFolderNow(url)
        case .recent(let recent):
            await reopenNow(recent)
        }
    }

    /// Shows entry and drops the closed folder's state at once (PRD Failure and recovery).
    ///
    /// The library ends the folder's session and its write queue keeps the unconfirmed changes,
    /// so nothing is reported as saved afterwards; the next open reads the actual XMP and
    /// Clove-stored marks. The filter and order survive, because they describe the grid rather
    /// than the folder that closed.
    private func showEntryAfterLeaving() {
        state.folder = nil
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .entry
        folderLocationLoss = nil
        changes = PhotoChangeStates()
        groupsPublishedFor = nil
        finishedScanFor = nil
        pendingRestore = nil
        hasLeftFolder = true
        // The closed folder's completed move cannot be undone through its ended session.
        lastRejectMove = nil
        isRejectMoveToastVisible = false
        storedPhotos = []
        groups = []
        // The folder's undo history goes with it (PRD P0-05), so no screen offers to undo an
        // action from a folder the user left and the system stack forgets it too.
        undoAvailability = .none
        undoFailure = nil
        finishingResults = [:]
        clearedFinishingGroups = []
        undoBridge.historyDidReset()
        thumbnails = library.thumbnails
        detailImages = library.detailImages
    }

    /// The auto-advance the last mark made in the detail view resolved to, with the photo it
    /// marked (PRD Auto-advance).
    ///
    /// U8 reads ``lastAutoAdvance``'s `markedPhoto` after an undo to return to the photo whose
    /// mark was undone (PRD Undo row: undoing after auto-advance returns to the photo whose mark
    /// was undone). Every detail mark records its plan, including the one that stays, so the
    /// record always names the latest mark rather than the latest move. A batch mark from the grid
    /// has no detail view to advance, so it records nothing.
    private(set) var lastAutoAdvance: AutoAdvancePlan?

    /// Records the advance one written mark started, so undo can return to the marked photo
    /// (PRD Undo row).
    func recordAutoAdvance(_ plan: AutoAdvancePlan) {
        lastAutoAdvance = plan
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
                // The scan and grouping can answer before this scene catches up, so the decision
                // reads their current state rather than assuming neither has happened.
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
            current: state, contents: library.contents, scanFinished: scanFinished,
            groupsPublished: groupsPublished)
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
        case .scanStarted:
            // A reopen of the same folder starts a new scan, so the old finished marker cannot
            // make the folder look ready before its new scan ends (PRD P0-01, P0-10).
            finishedScanFor = nil
            groupsPublishedFor = nil
            refresh()
        case .photos, .reads:
            refresh()
            resolvePendingRestore(scanFinished: false)
        case .scanFinished:
            finishedScanFor = library.folder
            refresh()
            resolvePendingRestore(scanFinished: true)
            await reloadRecents()
        case .change(let status):
            // A streamed transition keeps "Writing…" and "Saved" current without re-reading
            // every photo, and the merge rule keeps a finished change from moving backwards.
            changes.insert(status)
        case .locationLost(let folder, let loss, let generation):
            // PRD Failure and recovery forbids keeping Writing… or Saved for the folder's
            // unfinished changes after a loss; the indicator supplies the copy (PRD P0-02).
            // A buffered loss can arrive after another folder opened, or after the same folder
            // opened again, so it only applies to the folder and the open this scene shows.
            guard folder == library.folder, generation == library.openGeneration else { return }
            folderLocationLoss = loss
        case .groups(let groups):
            self.groups = groups
            groupsPublishedFor = library.folder
            keepGroupViewOnItsPhoto()
            // A saved group view waited for this publication (PRD P0-11, P0-14).
            resolvePendingRestore(scanFinished: hasFinishedScan)
        }
    }

    /// Keeps the open group view on its photo when grouping refines or reruns (PRD P0-11, P0-14).
    ///
    /// A split can move the viewed photo to another group or out of every group, and grouping
    /// never re-keys a group to prevent it (C9's ancestry keeps only the surviving group's key).
    /// The saved-scene validation already defines the fallback, so the live view uses the same
    /// one: the group still holding the photo, otherwise the group that holds it now, otherwise
    /// no group place and the grid.
    private func keepGroupViewOnItsPhoto() {
        guard let position = state.groupPosition else { return }
        if let moved = library.contents.position(for: position) {
            state.groupPosition = moved
            return
        }
        state.groupPosition = nil
        if state.route == .group {
            state.route = .grid
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
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .grid
        // The previous folder's completed move cannot be undone through this folder's session.
        lastRejectMove = nil
        isRejectMoveToastVisible = false
        leavePrompt = nil
        isWaitingForWrites = false
        // The finishing action, its failure and its event count belong to the folder that is
        // gone, so a new folder's group view never shows or advances on the old one (PRD P0-12).
        finishingResults = [:]
        clearedFinishingGroups = []
        dismissedGroupFailure = nil
        groupFinishingRuns = 0

        // Another folder replaces every selected photo's identity, so the batch's report and
        // U8's undo snapshot go with the selection.
        lastBatch = nil
        batchReport = nil
        selectionClearances += 1
        // The folder's undo history starts empty, and continuing in the open folder keeps the one
        // it already has (PRD P0-05).
        undoAvailability = library.undoAvailability
        undoFailure = nil
        undoBridge.historyDidReset()
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
    /// screens keep reading the model while the library changes underneath it. Save states are
    /// deliberately not copied from the library here: they arrive only on the ordered update
    /// stream, so a snapshot can never paint an older transition over a newer one.
    private func refresh() {
        storedPhotos = library.photos
        groups = library.groups
        reconcileRemovedPhotos()
    }

    /// Drops scene state that names a photo the folder no longer holds (PRD P0-10, P0-14).
    ///
    /// A confirmed move removes photos, so the selection, the current photo and the group place
    /// must not point at one. The scan only adds photos, so this changes nothing during a normal
    /// scan; a detail or group route whose photo is gone returns to the grid, the same fallback a
    /// restore uses. Grouping's own update then keeps a surviving group's place.
    private func reconcileRemovedPhotos() {
        let present = Set(storedPhotos.map(\.id))
        if !state.selection.isSubset(of: present) {
            state.selection.formIntersection(present)
            batchReport = nil
            selectionClearances += 1
        }
        if let current = state.currentPhoto, !present.contains(current) {
            state.currentPhoto = nil
            if state.route == .detail { state.route = .grid }
        }
        if let position = state.groupPosition, !present.contains(position.photo) {
            state.groupPosition = nil
            if state.route == .group { state.route = .grid }
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

/// The latest completed Move rejects run, kept for the toast and C14's undo (PRD P0-10).
///
/// The result names every set the run moved, failed or skipped, and the kept identities are the
/// photos the person kept in the confirmation. C14's undo will move the files back and restore
/// Reject on both lists as one step; this task only keeps the value.
struct CompletedRejectMove: Sendable, Identifiable {
    /// The run's outcomes and its retry handle (PRD P0-10).
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
}
