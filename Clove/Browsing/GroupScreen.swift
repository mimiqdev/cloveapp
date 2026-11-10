import CloveCore
import SwiftUI

/// The group view: one similar group's photos, culled in place (PRD In-group culling; PRD P0-12).
///
/// The screen assembles what the detail lane already has for one group (PRD In-group culling):
///
/// - **Layout.** Compact width shows the marking controls and a large preview with the group's
///   filmstrip below; regular width shows the same preview beside the group's sidebar grid.
///   Every frame shows its rating or Reject, and a rejected frame is dimmed (PRD In-group
///   culling, layout).
/// - **Progress.** The header carries C10's "Undecided N / M total" and the Undecided only
///   switch, which makes navigation skip rated and rejected photos through
///   ``GroupPhotoNavigation`` (PRD In-group culling, comparison and elimination).
/// - **One marking path.** The preview, the HUD and the marking inputs are ``DetailMarkingView``,
///   so a rating, label, Reject, swipe or edge tap goes through the same C13 rules and the same
///   library call as detail (PRD P0-06, P0-06 acceptance).
/// - **Synchronized zoom.** The next photo of the group opens at the same zoom and on the same
///   spot of the image, because the policy keeps the position in unit image coordinates
///   (PRD In-group culling, synchronized zoom; ``DetailZoomPolicy/group(_:)``).
/// - **Auto-advance.** A written mark moves to the group's next undecided photo through C13's
///   plan with the group's own answer, and the plan is recorded for U8 (PRD Auto-advance;
///   PRD Undo row).
/// - **Finishing actions.** Keep this, reject the rest and Keep rated, reject the rest are C10's
///   plan and executor, so a rated or labelled photo is never rejected (PRD In-group culling,
///   finishing actions; PRD P0-12). A partial failure offers a retry of the failed items only
///   (PRD P0-09).
/// - **Completion.** A group is complete when every photo is rated or rejected or a finishing
///   action ran; the setting then keeps the group or opens the next incomplete group, and a
///   folder with nothing left returns to the grid (PRD In-group culling, group completion).
///
/// The group position lives in the browsing state, never in this view, so a fold, a resize or a
/// relaunch keeps it (PRD P0-14). Settings come from the app-wide ``SettingsStore`` in the
/// environment, like detail (PRD Gesture-related settings).
///
/// Design placeholder: the header, the failure bar, the preview's chrome and the photo frames use
/// system components until the visual design lands. The Undo button stays disabled until U8
/// supplies the one model call it should invoke.
struct GroupScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The app-wide settings, read live so a change applies the next time this screen draws
    /// (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store

    /// Whether navigation skips rated and rejected photos (PRD In-group culling). A view choice,
    /// not a saved setting: PRD In-group culling offers it as a switch of the group view.
    @State private var undecidedOnly = false

    /// The auto-advance a mark started, waiting out its pause (PRD Auto-advance).
    @State private var autoAdvance = MarkAutoAdvance()

    /// C12's current settings: the completion behaviour, keep-zoom and the enabled ratings.
    private var settings: AppSettings { store.settings }

    var body: some View {
        Group {
            if let group = browsing.currentGroup, let photo = browsing.groupPhoto {
                content(group: group, photo: photo)
            } else {
                ContentUnavailableView {
                    Label("No group", systemImage: "rectangle.stack")
                } description: {
                    Text("Choose a similar group in the grid.")
                }
                .accessibilityIdentifier("clove.group.noGroup")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.group")
        .onDisappear {
            // Leaving the group view drops a pending advance, so coming back never jumps photos
            // (PRD Auto-advance).
            autoAdvance.cancel()
            completionTask?.cancel()
        }
        .onChange(of: completionTrigger, initial: true) { previous, current in
            advanceIfCompleted(previous: previous, current: current)
        }
    }

    /// The header, the preview and the group's own strip or sidebar, plus any failure that still
    /// needs a retry (PRD In-group culling, layout and finishing actions).
    private func content(group: BrowsingGroup, photo: GridPhoto) -> some View {
        VStack(spacing: 0) {
            GroupCullingHeader(
                headerText: undecidedCount.headerText,
                undecidedOnly: $undecidedOnly,
                isBusy: browsing.isRunningGroupFinishing,
                keepThisAvailable: plan(for: .keepThis, in: group, photo: photo).availability
                    .isAvailable,
                keepRatedAvailable: plan(for: .keepRated, in: group, photo: photo).availability
                    .isAvailable,
                keepThis: { run(.keepThis, in: group, photo: photo) },
                keepRated: { run(.keepRated, in: group, photo: photo) })
            Divider()
            if usesSidebarLayout {
                HStack(spacing: 0) {
                    markingView(photo: photo)
                    Divider()
                    GroupSidebar(
                        photos: browsing.groupPhotos,
                        current: photo.id,
                        thumbnails: browsing.thumbnails,
                        open: { show($0) }
                    )
                    .frame(width: 320)
                }
            } else {
                markingView(photo: photo)
                Divider()
                DetailFilmstrip(
                    photos: browsing.groupPhotos,
                    current: photo.id,
                    thumbnails: browsing.thumbnails,
                    open: { show($0) })
            }
            if let failure = finishingFailure(for: group) {
                Divider()
                GroupFinishingFailureBar(
                    summary: failure.partialFailureSummary ?? "",
                    isBusy: browsing.isRunningGroupFinishing,
                    retry: { Task { await browsing.retryGroupFinishing() } },
                    cancel: { browsing.dismissGroupFinishingFailure() })
            }
        }
    }

    /// The shared preview and marking controls, with this screen's group order and zoom
    /// (PRD P0-04; PRD In-group culling).
    private func markingView(photo: GridPhoto) -> some View {
        DetailMarkingView(
            photo: photo,
            settings: settings,
            saveState: SaveStateSummary.text(for: browsing.latestChange(for: photo.id)?.state),
            images: browsing.detailImages,
            zoomPolicy: .group(settings),
            order: browsing.groupPhotos,
            actions: actions)
    }

    /// What the marking view asks this screen to do: write a mark, advance within the group and
    /// move through the group's member order (PRD In-group culling; PRD Auto-advance).
    private var actions: DetailMarkingActions {
        DetailMarkingActions(
            apply: { change, photo in await browsing.apply(change, to: photo.id) },
            marked: { kind, photo in startAutoAdvance(after: kind, from: photo) },
            step: { offset in step(offset) },
            markingSwipeBegan: { autoAdvance.cancel() })
    }

    /// Whether the group's photos sit beside the preview instead of below it (PRD In-group
    /// culling: iPad and the Duo inner screen use a sidebar grid).
    private var usesSidebarLayout: Bool { horizontalSizeClass == .regular }

    // MARK: - Progress

    /// C10's count for the group on screen (PRD In-group culling, layout).
    private var undecidedCount: GroupUndecidedCount {
        GroupUndecidedCount(browsing.groupPhotos.map(\.marks))
    }

    /// The marks the group's rules read now, so a plan or a navigation step never uses a stale
    /// copy (PRD P0-12).
    ///
    /// A photo whose rating or label is still being written counts as marked, so a finishing
    /// action planned within the write's time never rejects it
    /// (``BrowsingModel/cullingMarks(for:)``).
    private var marks: [PhotoIdentity: PhotoMarks] {
        var marks: [PhotoIdentity: PhotoMarks] = [:]
        for photo in browsing.groupPhotos { marks[photo.id] = browsing.cullingMarks(for: photo) }
        return marks
    }

    /// C10's navigation for the group on screen, with the Undecided only switch
    /// (PRD In-group culling).
    private var navigation: GroupPhotoNavigation? {
        browsing.currentGroup.map {
            GroupPhotoNavigation(group: $0, undecidedOnly: undecidedOnly)
        }
    }

    // MARK: - Navigation

    /// Shows one photo of the group and drops an advance that was still waiting to move
    /// (PRD Auto-advance).
    ///
    /// Grouping can refine while an advance waits out its pause, so a photo that is no longer a
    /// member of the group on screen is refused: the group view must keep showing a member, which
    /// is what makes its saved position valid (PRD P0-11, P0-14).
    private func show(_ photo: PhotoIdentity) {
        autoAdvance.cancel()
        // A user who moves within the group is not waiting to be handed the next group.
        completionTask?.cancel()
        guard browsing.groupPhotos.contains(where: { $0.id == photo }) else { return }
        browsing.showGroupPhoto(photo)
    }

    /// Moves one photo in the group's member order, skipping marked photos while Undecided only
    /// is on (PRD In-group culling, comparison and elimination).
    private func step(_ offset: Int) {
        guard let navigation, let current = browsing.state.groupPosition?.photo else { return }
        let marks = marks
        let target =
            offset < 0
            ? navigation.previousPhoto(before: current, marks: marks)
            : navigation.nextPhoto(after: current, marks: marks)
        guard let target else { return }
        show(target)
    }

    // MARK: - Marking

    /// Starts the pause-then-advance one written mark asks for (PRD Auto-advance).
    ///
    /// In a group the answer is C10's next undecided member, so a mark moves to the photo that
    /// still needs a decision instead of the next frame (PRD In-group culling, comparison and
    /// elimination; PRD Auto-advance). The plan is recorded on the model, so undo returns to the
    /// photo whose mark it undid (PRD Undo row).
    private func startAutoAdvance(after kind: MarkKind, from photo: GridPhoto) {
        let next = navigation?.nextUndecidedPhoto(after: photo.id, marks: marks)
        let plan = MarkingInputRules(settings: settings).autoAdvancePlan(
            after: kind, from: photo.id, photos: browsing.groupPhotos,
            group: next.map(GroupAdvance.nextUndecidedPhoto) ?? .complete)
        browsing.recordAutoAdvance(plan)
        autoAdvance.schedule(plan) { target in
            switch target {
            case .stay:
                break
            case .groupUndecidedPhoto(let next), .nextPhoto(let next), .nextUnmarkedPhoto(let next):
                show(next)
            }
        }
    }

    // MARK: - Finishing actions

    /// C10's plan for one finishing action over the marks read now (PRD P0-12).
    private func plan(
        for action: GroupFinishingAction, in group: BrowsingGroup, photo: GridPhoto
    ) -> GroupFinishingPlan {
        GroupFinishingPlan(
            group: group, action: action, currentPhoto: photo.id, marks: marks,
            enabledRatings: settings.enabledRatings)
    }

    /// Runs one finishing action through C10's plan and the library's executor (PRD P0-12).
    ///
    /// An unavailable action writes nothing and records no completion, so only an available plan
    /// reaches the library (PRD In-group culling, finishing actions).
    private func run(
        _ action: GroupFinishingAction, in group: BrowsingGroup, photo: GridPhoto
    ) {
        let plan = plan(for: action, in: group, photo: photo)
        guard plan.availability.isAvailable else { return }
        autoAdvance.cancel()
        completionTask?.cancel()
        Task { await browsing.runGroupFinishing(plan) }
    }

    /// The last finishing action's failure while it still needs a retry and belongs to this group
    /// (PRD P0-09; PRD Failure and recovery).
    private func finishingFailure(for group: BrowsingGroup) -> GroupFinishingResult? {
        retryableFailure(for: group.id)
    }
    // MARK: - Completion

    /// The values that change when the group on screen can complete (PRD P0-12).
    ///
    /// The marks, the finishing action, its per-photo result, the failure the user can still retry
    /// and C12's setting are all in the value, so any of them is one event the screen reacts to.
    private struct GroupCompletionTrigger: Hashable {
        /// The group on screen, or nil when there is none.
        let group: GroupID?
        /// The group's undecided photos right now (PRD In-group culling, layout).
        let undecided: Int
        /// The last finishing action, with its completion record (PRD P0-12).
        let finishing: GroupFinishingResult?
        /// How many finishing actions and retries have run, so two equal results stay two events
        /// (PRD P0-12).
        let finishingRuns: Int
        /// Whether a finishing action is still running, so its failures are not known yet
        /// (PRD P0-09).
        let finishingRunning: Bool
        /// The current group's finishing failure while the user can still retry it
        /// (PRD Failure and recovery).
        let failure: GroupFinishingResult?
        /// C12's "After a group is complete" (PRD Gesture-related settings).
        let behaviour: GroupCompletionBehaviour
    }

    /// Builds the completion trigger from the state the screen already reads.
    private var completionTrigger: GroupCompletionTrigger {
        let group = browsing.state.groupPosition?.group
        return GroupCompletionTrigger(
            group: group,
            undecided: undecidedCount.undecided,
            finishing: browsing.lastGroupFinishing,
            finishingRuns: browsing.groupFinishingRuns,
            finishingRunning: browsing.isRunningGroupFinishing,
            failure: retryableFailure(for: group),
            behaviour: settings.groupCompletion)
    }

    /// The finishing action's failure while it belongs to one group (PRD P0-09; PRD Failure and
    /// recovery).
    ///
    /// Scoping it to the group matters twice: a failure belongs to the action that produced it, so
    /// another group's failure must neither show its bar here nor hold this group's completion.
    private func retryableFailure(for group: GroupID?) -> GroupFinishingResult? {
        guard let group, let failure = browsing.groupFinishingFailure,
            failure.plan.groupID == group
        else { return nil }
        return failure
    }

    /// Whether the trigger's group is complete (PRD In-group culling, group completion).
    private func isComplete(_ trigger: GroupCompletionTrigger) -> Bool {
        trigger.undecided == 0
            || (trigger.group != nil && trigger.finishing?.plan.groupID == trigger.group)
    }

    /// The group whose completion is waiting for the view to move on (PRD P0-12).
    @State private var completedGroup: GroupID?

    /// The pause before a completed group hands the view on (PRD Auto-advance).
    @State private var completionTask: Task<Void, Never>?

    /// Moves the group view on when this screen watched its group complete (PRD In-group culling,
    /// group completion; PRD P0-12).
    ///
    /// A completion is an event, not a state: a group the user opens from the grid that is already
    /// finished stays where it is, while a group that completed here, a finishing action the user
    /// runs and a finishing failure the user retries or cancels all hand the view on. The move
    /// waits out C13's pause, because PRD Auto-advance shows the mark that completed the group for
    /// about 0.3 seconds before the view leaves it.
    ///
    /// A finishing action that left changes to retry keeps the view until the user decides, so the
    /// failure bar and its retry stay reachable (PRD P0-09; PRD Failure and recovery), and so does
    /// an action that is still running, because its failures are not known yet.
    private func advanceIfCompleted(
        previous: GroupCompletionTrigger, current: GroupCompletionTrigger
    ) {
        guard let group = current.group else {
            completedGroup = nil
            completionTask?.cancel()
            return
        }
        if group != previous.group {
            // Another group: nothing from the last one carries over (PRD P0-14).
            completedGroup = nil
            completionTask?.cancel()
            autoAdvance.cancel()
        }
        let becameComplete = group == previous.group && isComplete(current) && !isComplete(previous)
        let finishedNow =
            group == previous.group && current.finishingRuns != previous.finishingRuns
            && current.finishing?.plan.groupID == group
        let failureResolved =
            group == previous.group && previous.failure != nil && current.failure == nil
        if becameComplete || finishedNow || failureResolved { completedGroup = group }

        guard completedGroup == group,
            isComplete(current),
            !current.finishingRunning,
            current.failure == nil
        else {
            // A finishing action that is still running, or one that left changes to retry, keeps
            // the view so the failure bar and its retry stay reachable (PRD P0-09; PRD Failure and
            // recovery), and drops a move that was already waiting. A later update that is neither
            // — the action's own marks still streaming in — leaves that move alone.
            if current.finishingRunning || current.failure != nil { completionTask?.cancel() }
            return
        }
        completedGroup = nil
        autoAdvance.cancel()
        completionTask?.cancel()
        completionTask = Task {
            try? await Task.sleep(for: AutoAdvance.pause)
            guard !Task.isCancelled else { return }
            await browsing.advanceFromCompletedGroup(current.behaviour)
        }
    }
}
