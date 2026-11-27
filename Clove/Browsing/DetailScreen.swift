import CloveCore
import CloveImaging
import SwiftUI

/// One photo's detail: the preview, swipe navigation and the filmstrip, with the marking HUD
/// above them (PRD P0-04, PRD Detail and marking).
///
/// The screen keeps no browsing state of its own. The current photo, expanded group focus, grid
/// order and filter, marks and pixels all come from ``BrowsingModel`` and the open folder's
/// ``DetailImageSource``; the preview, its zoom and the marking controls are ``DetailMarkingView``.
/// This screen supplies the two-level ``DetailTimeline`` (Timeline vs Group Focus) and the
/// auto-advance that follows a written mark (PRD Auto-advance; PRD In-group culling; issue #304).
///
/// Settings come from the app-wide ``SettingsStore`` in the environment, so a change on the
/// settings screen applies the next time this screen draws; the screen reads no storage itself
/// (PRD Gesture-related settings).
///
/// The handoff's capsule and filmstrip float over the stage. Undo uses the model's action snapshot.
struct DetailScreen: View {
    /// The scene's browsing state and the operations this screen performs on it.
    let browsing: BrowsingModel

    /// The pixels to show, normally the open folder's source from the browsing model.
    private let images: any DetailImageSource
    var duo: DuoDetailLayout?
    var presentation: Binding<DetailPresentation>? = nil
    var initialPresentation: DetailPresentation = .photoPreview

    /// The app-wide settings, read live so a change on the settings screen applies the next time
    /// this screen draws (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isDuoCover) private var isDuoCover

    @State private var widePresentation: DetailPresentation

    /// The auto-advance a mark started, waiting out its pause (PRD Auto-advance).
    @State private var autoAdvance = MarkAutoAdvance()

    /// Transient high-regret Undo toast shown after `Reject N unmarked` or filter-hiding marks.
    @State private var undoToast: DetailUndoToast?
    @State private var toastContextPhoto: PhotoIdentity?
    @State private var toastContextExpandedGroup: GroupID?

    /// Transient completion toast shown when a mark leaves zero unmarked placed photos.
    @State private var allReviewedToast: DetailAllReviewedToast?
    @State private var allReviewedContextPhoto: PhotoIdentity?
    @State private var allReviewedContextExpandedGroup: GroupID?
    @State private var allReviewedContextPresentation: DetailPresentation?

    /// Brief non-blocking toast shown when Compare exits on rotation to portrait.
    static let compareRotateToastAutoDismissDelay: Duration = .seconds(2)
    @State private var compareRotateToastID: UUID?
    @State private var rotateToastContextPhoto: PhotoIdentity?
    @State private var rotateToastContextExpandedGroup: GroupID?

    /// C12's current settings: the double-tap behaviour, the zoomed gestures and the enabled
    /// ratings.
    private var settings: AppSettings { store.settings }

    private var groupsEnabled: Bool {
        settings.similarGroupsEnabled && !browsing.isScanning
    }

    private var timeline: DetailTimeline {
        DetailTimeline(
            photos: browsing.photos, groups: browsing.groups, groupsEnabled: groupsEnabled)
    }

    private var activePresentation: DetailPresentation {
        presentation?.wrappedValue ?? duo?.presentation.wrappedValue ?? widePresentation
    }

    private var activeExpandedGroup: ActiveBrowsingGroup? {
        guard let expanded = browsing.expandedGroup else { return nil }
        return timeline.activeGroup(with: expanded)
    }

    /// Creates the screen for one browsing model.
    ///
    /// `images` exists for previews and tests; the app uses the browsing model's source for the
    /// open folder. Settings come from the app-wide ``SettingsStore`` in the environment, so this
    /// screen reads no storage of its own and one source of settings serves every screen.
    init(
        browsing: BrowsingModel, images: (any DetailImageSource)? = nil,
        duo: DuoDetailLayout? = nil,
        presentation: Binding<DetailPresentation>? = nil,
        initialPresentation: DetailPresentation = .photoPreview
    ) {
        self.browsing = browsing
        self.images = images ?? browsing.detailImages
        self.duo = duo
        self.presentation = presentation
        self.initialPresentation = initialPresentation
        _widePresentation = State(initialValue: initialPresentation)
    }

    var body: some View {
        Group {
            if let compare = browsing.compareSession {
                CompareView(
                    browsing: browsing,
                    session: compare,
                    settings: settings,
                    images: images,
                    displayMode: store.photoDisplayMode,
                    duo: duo,
                    onUnsupportedLayoutExit: { showsRotateToast in
                        handleUnsupportedCompareLayoutExit(showsRotateToast: showsRotateToast)
                    })
            } else if let photo = browsing.currentPhoto {
                content(for: photo)
            } else {
                ContentUnavailableView {
                    Label(
                        AppLocalization.string("No photo", language: language),
                        systemImage: "photo")
                } description: {
                    Text(AppLocalization.string("Choose a photo in the grid.", language: language))
                }
                .accessibilityIdentifier("clove.detail.noPhoto")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(browsing.compareSession != nil ? "clove.compare" : "clove.detail")
        .onChange(of: browsing.compareSession != nil) { _, isComparing in
            if isComparing {
                autoAdvance.cancel()
                dismissTransientToasts()
            }
        }
        .onChange(of: settings.similarGroupsEnabled) { _, enabled in
            if !enabled {
                autoAdvance.cancel()
                dismissTransientToasts()
                browsing.collapseGroup()
            }
        }
        .onChange(of: browsing.state.currentPhoto) { _, newPhoto in
            if allReviewedToast != nil, newPhoto != allReviewedContextPhoto {
                dismissAllReviewedToast()
            }
            if undoToast != nil, newPhoto != toastContextPhoto {
                dismissUndoToast()
            }
            if compareRotateToastID != nil, newPhoto != rotateToastContextPhoto {
                dismissCompareRotateToast()
            }
        }
        .onChange(of: browsing.expandedGroup) { _, newGroup in
            if allReviewedToast != nil, newGroup != allReviewedContextExpandedGroup {
                dismissAllReviewedToast()
            }
            if undoToast != nil, newGroup != toastContextExpandedGroup {
                dismissUndoToast()
            }
            if compareRotateToastID != nil, newGroup != rotateToastContextExpandedGroup {
                dismissCompareRotateToast()
            }
        }
        .onChange(of: browsing.state.route) { _, route in
            if route != .detail {
                autoAdvance.cancel()
                dismissTransientToasts()
            }
        }
        .onChange(of: browsing.state.folder) { _, _ in
            dismissTransientToasts()
        }
        .onChange(of: browsing.state.filter) { _, _ in
            dismissTransientToasts()
        }
        .onChange(of: browsing.labelFilter) { _, _ in
            dismissTransientToasts()
        }
        .onChange(of: browsing.metadataFilter) { _, _ in
            dismissTransientToasts()
        }
        .onChange(of: browsing.failureToastMessage != nil) { _, hasFailure in
            if hasFailure {
                dismissTransientToasts()
            }
        }
        .onChange(of: browsing.canUndoMark) { _, canUndo in
            if !canUndo {
                dismissUndoToast()
                dismissAllReviewedToast()
            }
        }
        .onChange(of: browsing.sidebarCounts.unmarked > 0) { _, hasUnmarked in
            if hasUnmarked {
                dismissAllReviewedToast()
            }
        }
        .onChange(of: isDuoCover) { _, covered in
            if covered {
                dismissCompareRotateToast()
            }
        }
        .onChange(of: activePresentation) { _, _ in
            dismissAllReviewedToast()
        }
        .task(id: undoToast?.id) {
            guard let toastID = undoToast?.id else { return }
            try? await Task.sleep(for: DetailUndoToast.autoDismissDelay)
            guard !Task.isCancelled, undoToast?.id == toastID else { return }
            dismissUndoToast()
        }
        .task(id: compareRotateToastID) {
            guard let toastID = compareRotateToastID else { return }
            try? await Task.sleep(for: Self.compareRotateToastAutoDismissDelay)
            guard !Task.isCancelled, compareRotateToastID == toastID else { return }
            dismissCompareRotateToast()
        }
        .onDisappear {
            // Leaving detail drops a pending advance, so coming back never jumps photos
            // (PRD Auto-advance).
            autoAdvance.cancel()
            dismissTransientToasts()
        }
    }

    /// The marking controls and the preview, then the filmstrip, in the order PRD Detail and
    /// marking fixes.
    private func content(for photo: GridPhoto) -> some View {
        let currentTimeline = timeline
        let expanded = activeExpandedGroup
        return DetailMarkingView(
            browsing: browsing,
            photo: photo,
            settings: settings,
            images: images,
            displayMode: store.photoDisplayMode,
            timeline: currentTimeline,
            expandedGroup: expanded,
            order: currentTimeline.stageOrder(expandedGroup: expanded?.id),
            actions: actions,
            duo: duo,
            presentation: presentation ?? (duo == nil ? $widePresentation : nil),
            initialPresentation: compareRotateToastID != nil ? .focus : initialPresentation,
            allReviewedToast: activePresentation == allReviewedContextPresentation
                ? allReviewedToast : nil,
            undoToast: undoToast,
            compareRotateToastID: compareRotateToastID)
    }

    /// What the marking view asks this screen to do: write a mark, advance after it, and move
    /// through the active Detail level's order (Timeline vs Group Focus).
    private var actions: DetailMarkingActions {
        DetailMarkingActions(
            apply: { change, photo in
                let hadUnmarkedBefore = browsing.sidebarCounts.unmarked > 0
                let previousMarks = photo.marks
                let hidFromFilter = browsing.apply(change, to: photo.id)
                let undoKind: DetailUndoToast.Kind? =
                    if hidFromFilter,
                        let action = DetailUndoToast.Action(
                            change: change, previousMarks: previousMarks)
                    {
                        .hiddenByFilter(action: action)
                    } else {
                        nil
                    }
                handleMarkResult(hadUnmarkedBefore: hadUnmarkedBefore, undoKind: undoKind)
            },
            marked: { kind, change, photo in
                startAutoAdvance(after: kind, change: change, from: photo)
            },
            step: { offset in stepPhoto(offset: offset) },
            markingSwipeBegan: {
                autoAdvance.cancel()
                dismissAllReviewedToast()
            },
            openPhoto: { openPhoto($0) },
            selectGroupPhoto: { selectGroupPhoto($0) },
            expandGroup: { expandGroup($0) },
            collapseGroup: { collapseGroup() },
            finishGroup: { plan in
                guard browsing.canMark, let expanded = activeExpandedGroup else { return }
                autoAdvance.cancel()
                let hadUnmarkedBefore = browsing.sidebarCounts.unmarked > 0
                let advance = timeline.finishingAdvancePlan(
                    groupID: expanded.id, from: plan.currentPhoto, rules: rules)
                let rejectedCount = browsing.runGroupFinishing(plan)
                let undoKind: DetailUndoToast.Kind? =
                    rejectedCount > 0 ? .rejectedBatch(count: rejectedCount) : nil
                handleMarkResult(hadUnmarkedBefore: hadUnmarkedBefore, undoKind: undoKind)
                schedule(advance)
            },
            undo: { performUndo() },
            backToGrid: { performBackToGrid() },
            photoTapped: { dismissAllReviewedToast() })
    }

    // MARK: - Navigation

    /// Steps horizontally within the active level (Timeline slots or Group Focus members) without
    /// crossing levels or wrapping at ends.
    private func stepPhoto(offset: Int) {
        dismissTransientToasts()
        guard let current = browsing.state.currentPhoto,
            let target = timeline.steppedPhoto(
                from: current, offset: offset, expandedGroup: activeExpandedGroup?.id)
        else { return }
        if activeExpandedGroup != nil {
            selectGroupPhoto(target)
        } else {
            openPhoto(target)
        }
    }

    /// Opens one photo in Timeline mode (`expandedGroup = nil`) and drops any pending advance.
    private func openPhoto(_ photo: PhotoIdentity) {
        dismissTransientToasts()
        autoAdvance.cancel()
        browsing.openPhoto(photo)
    }

    /// Selects another member within the active expanded group and drops any pending advance.
    private func selectGroupPhoto(_ photo: PhotoIdentity) {
        dismissTransientToasts()
        autoAdvance.cancel()
        browsing.selectGroupPhoto(photo)
    }

    /// Enters Group Focus for `groupID` and drops any pending advance.
    private func expandGroup(_ groupID: GroupID) {
        dismissTransientToasts()
        autoAdvance.cancel()
        browsing.openGroup(groupID, on: browsing.state.currentPhoto)
    }

    /// Collapses Group Focus back to Timeline on the group's Representative Photo.
    private func collapseGroup() {
        dismissTransientToasts()
        autoAdvance.cancel()
        browsing.collapseGroup()
    }

    // MARK: - Transient toasts

    private func handleMarkResult(
        hadUnmarkedBefore: Bool,
        undoKind: DetailUndoToast.Kind?
    ) {
        let countsAfter = browsing.sidebarCounts
        if hadUnmarkedBefore, countsAfter.all > 0, countsAfter.unmarked == 0 {
            presentAllReviewedToast(totalCount: countsAfter.all)
            return
        }
        dismissAllReviewedToast()
        if let undoKind {
            presentUndoToast(undoKind)
        } else {
            dismissUndoToast()
        }
    }

    private func dismissTransientToasts() {
        dismissAllReviewedToast()
        dismissUndoToast()
        dismissCompareRotateToast()
    }

    private func handleUnsupportedCompareLayoutExit(showsRotateToast: Bool) {
        if showsRotateToast {
            presentation?.wrappedValue = .focus
            duo?.presentation.wrappedValue = .focus
            widePresentation = .focus
            presentCompareRotateToast(animated: false)
        } else {
            dismissCompareRotateToast()
        }
        browsing.exitCompare()
        if showsRotateToast, compareRotateToastID != nil {
            rotateToastContextPhoto = browsing.state.currentPhoto
            rotateToastContextExpandedGroup = browsing.expandedGroup
        }
    }

    private func presentCompareRotateToast(animated: Bool = true) {
        guard browsing.failureToastMessage == nil else {
            dismissCompareRotateToast()
            return
        }
        dismissAllReviewedToast()
        dismissUndoToast()
        rotateToastContextPhoto = browsing.state.currentPhoto
        rotateToastContextExpandedGroup = browsing.expandedGroup
        if animated {
            withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                compareRotateToastID = UUID()
            }
        } else {
            compareRotateToastID = UUID()
        }
    }

    private func dismissCompareRotateToast() {
        rotateToastContextPhoto = nil
        rotateToastContextExpandedGroup = nil
        guard compareRotateToastID != nil else { return }
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            compareRotateToastID = nil
        }
    }

    private func presentAllReviewedToast(totalCount: Int) {
        guard totalCount > 0, browsing.failureToastMessage == nil else { return }
        dismissUndoToast()
        dismissCompareRotateToast()
        allReviewedContextPhoto = browsing.state.currentPhoto
        allReviewedContextExpandedGroup = browsing.expandedGroup
        allReviewedContextPresentation = activePresentation
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            allReviewedToast = DetailAllReviewedToast(totalCount: totalCount)
        }
    }

    private func dismissAllReviewedToast() {
        allReviewedContextPhoto = nil
        allReviewedContextExpandedGroup = nil
        allReviewedContextPresentation = nil
        guard allReviewedToast != nil else { return }
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            allReviewedToast = nil
        }
    }

    private func presentUndoToast(_ kind: DetailUndoToast.Kind) {
        browsing.dismissFailureToast()
        dismissAllReviewedToast()
        dismissCompareRotateToast()
        let toast = DetailUndoToast(kind: kind)
        toastContextPhoto = browsing.state.currentPhoto
        toastContextExpandedGroup = browsing.expandedGroup
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            undoToast = toast
        }
    }

    private func dismissUndoToast() {
        toastContextPhoto = nil
        toastContextExpandedGroup = nil
        guard undoToast != nil else { return }
        withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
            undoToast = nil
        }
    }

    private func performUndo() {
        autoAdvance.cancel()
        dismissTransientToasts()
        browsing.undoLastMark(restoringNavigation: true)
    }

    private func performBackToGrid() {
        autoAdvance.cancel()
        dismissTransientToasts()
        browsing.back()
    }

    // MARK: - Auto-advance

    /// Starts the pause-then-advance one written mark asks for (PRD Auto-advance, issue #304).
    ///
    /// Plan before writing desired marks so the snapshot captures `hadUnmarkedBefore` cleanly.
    private func startAutoAdvance(after kind: MarkKind, change: MarkChange, from photo: GridPhoto) {
        let plan = timeline.autoAdvancePlan(
            after: kind, change: change, from: photo.id, expandedGroup: activeExpandedGroup?.id,
            rules: rules)
        schedule(plan)
    }

    private func schedule(_ plan: AutoAdvancePlan) {
        autoAdvance.schedule(plan) { target in
            switch target {
            case .stay:
                if plan.exitsGroupFocus {
                    browsing.collapseGroup()
                }
            case .groupUndecidedPhoto(let next):
                browsing.selectGroupPhoto(next)
            case .nextPhoto(let next), .nextUnmarkedPhoto(let next):
                browsing.openPhoto(next)
            }
            if undoToast != nil {
                toastContextPhoto = browsing.state.currentPhoto
                toastContextExpandedGroup = browsing.expandedGroup
            }
            if allReviewedToast != nil {
                allReviewedContextPhoto = browsing.state.currentPhoto
                allReviewedContextExpandedGroup = browsing.expandedGroup
            }
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules { MarkingInputRules(settings: settings) }
}
