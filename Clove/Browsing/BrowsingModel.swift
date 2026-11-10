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

    /// The open this scene shows, so a loss from an earlier open of the same folder is dropped
    /// (PRD P0-02).
    private var shownOpenGeneration = 0

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
    /// With unfinished writes in the open folder, the question comes first (PRD P0-08).
    func openPickedFolder(_ url: URL) async {
        pendingRestore = nil
        guard askBeforeLeaving(.picked(url)) else { return }
        await openPickedFolderNow(url)
    }

    /// Opens a folder the user chose, once any leaving question is answered (PRD P0-01).
    private func openPickedFolderNow(_ url: URL) async {
        folderFailure = await library.pick(url)
        guard folderFailure == nil else { return }
        // C11 just validated this folder with a real read, so an earlier folder's loss no longer
        // applies (PRD P0-02).
        folderLocationLoss = nil
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
        if let failure = await library.reopen(recent) {
            recentFailures[recent.id] = failure
            return
        }
        recentFailures[recent.id] = nil
        folderFailure = nil
        // The reopen read the folder, so the loss the watch reported is no longer current.
        folderLocationLoss = nil
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
        _ = await library.retryLatestChange(for: photo)
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
        isWaitingForWrites = false
        // The queue's own answer is authoritative: a streamed status can still be on its way to
        // this screen when the drain returns, and the question must not stay over confirmed work.
        guard await library.hasUnfinishedWrites() else {
            await leave(to: prompt.destination)
            return
        }
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
        // The screen leaves the folder before anything that waits for its writes, so no
        // destination keeps the user on the old folder while C4 drains (G1 keeps the scope until
        // the work ends, but that is not something the user has to watch).
        showEntryAfterLeaving()
        // Leaving closes the folder even when the next destination never opens, so its scan stops
        // and its scope is not held for a folder the user no longer sees (G1 folder access).
        await library.closeFolder()
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
        storedPhotos = []
        groups = []
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
            // up belongs to whatever was open then, not to what it shows now (PRD P0-02).
            folderLocationLoss = nil
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
            guard folder == library.folder, generation == shownOpenGeneration else { return }
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
        shownOpenGeneration = library.openGeneration
        state.folder = library.folder
        state.currentPhoto = nil
        state.selection = []
        state.groupPosition = nil
        state.route = .grid
        leavePrompt = nil
        isWaitingForWrites = false
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
    }
}
