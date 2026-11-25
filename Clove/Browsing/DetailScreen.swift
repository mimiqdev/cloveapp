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

    /// The auto-advance a mark started, waiting out its pause (PRD Auto-advance).
    @State private var autoAdvance = MarkAutoAdvance()

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
                    duo: duo)
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
        .accessibilityIdentifier("clove.detail")
        .onChange(of: browsing.compareSession != nil) { _, isComparing in
            if isComparing {
                autoAdvance.cancel()
            }
        }
        .onChange(of: settings.similarGroupsEnabled) { _, enabled in
            if !enabled {
                autoAdvance.cancel()
                browsing.collapseGroup()
            }
        }
        .onDisappear {
            // Leaving detail drops a pending advance, so coming back never jumps photos
            // (PRD Auto-advance).
            autoAdvance.cancel()
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
            presentation: presentation,
            initialPresentation: initialPresentation)
    }

    /// What the marking view asks this screen to do: write a mark, advance after it, and move
    /// through the active Detail level's order (Timeline vs Group Focus).
    private var actions: DetailMarkingActions {
        DetailMarkingActions(
            apply: { change, photo in browsing.apply(change, to: photo.id) },
            marked: { kind, change, photo in
                startAutoAdvance(after: kind, change: change, from: photo)
            },
            step: { offset in stepPhoto(offset: offset) },
            markingSwipeBegan: { autoAdvance.cancel() },
            openPhoto: { openPhoto($0) },
            selectGroupPhoto: { selectGroupPhoto($0) },
            expandGroup: { expandGroup($0) },
            collapseGroup: { collapseGroup() },
            finishGroup: { plan in
                guard browsing.canMark, let expanded = activeExpandedGroup else { return }
                autoAdvance.cancel()
                let advance = timeline.finishingAdvancePlan(
                    groupID: expanded.id, from: plan.currentPhoto, rules: rules)
                browsing.runGroupFinishing(plan)
                schedule(advance)
            })
    }

    // MARK: - Navigation

    /// Steps horizontally within the active level (Timeline slots or Group Focus members) without
    /// crossing levels or wrapping at ends.
    private func stepPhoto(offset: Int) {
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
        autoAdvance.cancel()
        browsing.openPhoto(photo)
    }

    /// Selects another member within the active expanded group and drops any pending advance.
    private func selectGroupPhoto(_ photo: PhotoIdentity) {
        autoAdvance.cancel()
        browsing.selectGroupPhoto(photo)
    }

    /// Enters Group Focus for `groupID` and drops any pending advance.
    private func expandGroup(_ groupID: GroupID) {
        autoAdvance.cancel()
        browsing.openGroup(groupID, on: browsing.state.currentPhoto)
    }

    /// Collapses Group Focus back to Timeline on the group's Representative Photo.
    private func collapseGroup() {
        autoAdvance.cancel()
        browsing.collapseGroup()
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
        }
    }

    /// C13's rules for this screen's settings.
    private var rules: MarkingInputRules { MarkingInputRules(settings: settings) }
}
