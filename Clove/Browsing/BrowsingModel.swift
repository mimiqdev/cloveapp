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
        self.detailImages = library.detailImages
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
    /// it.
    private(set) var lastGroupFinishing: GroupFinishingResult?

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
        dismissedGroupFailure = nil
        isRunningGroupFinishing = true
        let result = await library.runGroupFinishing(plan)
        lastGroupFinishing = result
        groupFinishingRuns += 1
        isRunningGroupFinishing = false
    }

    /// Retries only the changes that still need it, through C4 (PRD P0-09).
    ///
    /// It shares the one-action-at-a-time rule with ``runGroupFinishing(_:)``, so a retry can
    /// never overlap the action it retries.
    func retryGroupFinishing() async {
        guard !isRunningGroupFinishing, let result = lastGroupFinishing else { return }
        dismissedGroupFailure = nil
        isRunningGroupFinishing = true
        let retried = await library.retryGroupFinishing(result)
        lastGroupFinishing = retried
        groupFinishingRuns += 1
        isRunningGroupFinishing = false
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
        switch update {
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
    private func showOpenFolder() {
        state.folder = library.folder
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .grid
        // The folder's groups are whatever grouping published for it, even when the scan
        // answered before this scene caught up (PRD P0-11).
        groups = library.groups
        // The library replaced its pipeline with the folder's, so the grid takes the new source
        // even when the route does not change. Detail takes the source bound to the same folder.
        thumbnails = library.thumbnails
        detailImages = library.detailImages
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
