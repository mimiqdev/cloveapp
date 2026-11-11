import CloveCore
import SwiftUI

/// Group review owns its order and finishing action; detail owns the shared marking controls.
/// Finishing submits one entry to BrowsingModel's ordered action pipeline.
struct GroupScreen: View {
    let browsing: BrowsingModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SettingsStore.self) private var store
    @State private var undecidedOnly = false
    @State private var autoAdvance = MarkAutoAdvance()

    var body: some View {
        Group {
            if let group = browsing.currentGroup, let photo = browsing.groupPhoto {
                HStack(spacing: 0) {
                    markingView(group: group, photo: photo)
                    if horizontalSizeClass == .regular {
                        GroupSidebar(
                            photos: visiblePhotos, current: photo.id,
                            thumbnails: browsing.thumbnails,
                            open: show
                        ).frame(width: 320)
                    }
                }
            } else {
                ContentUnavailableView("No group", systemImage: "rectangle.stack")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.group")
        .onDisappear { autoAdvance.cancel() }
        .onChange(of: browsing.state.groupPosition?.group) { _, _ in
            autoAdvance.cancel()
            undecidedOnly = false
        }
    }

    private var visiblePhotos: [GridPhoto] {
        browsing.groupPhotos.filter { !undecidedOnly || $0.marks.isUndecided }
    }

    private var marks: [PhotoIdentity: PhotoMarks] {
        Dictionary(uniqueKeysWithValues: browsing.groupPhotos.map { ($0.id, $0.marks) })
    }

    private var navigation: GroupPhotoNavigation? {
        browsing.currentGroup.map { GroupPhotoNavigation(group: $0, undecidedOnly: undecidedOnly) }
    }

    private func markingView(group: BrowsingGroup, photo: GridPhoto) -> some View {
        DetailMarkingView(
            browsing: browsing, photo: photo, settings: store.settings,
            images: browsing.detailImages,
            displayMode: store.photoDisplayMode,
            recordRenderDurations: store.recordScreenRenderDurations,
            zoomPolicy: .group, order: visiblePhotos,
            actions: DetailMarkingActions(
                apply: { change, photo in browsing.apply(change, to: photo.id) },
                marked: { kind, photo in startAutoAdvance(after: kind, from: photo) },
                step: step, markingSwipeBegan: { autoAdvance.cancel() }, openPhoto: show),
            groupReview: GroupReviewChrome(
                group: group,
                undecided: GroupUndecidedCount(browsing.groupPhotos.map(\.marks)).undecided,
                undecidedOnly: $undecidedOnly, action: finishingAction(group: group, photo: photo)))
    }

    private func finishingAction(group: BrowsingGroup, photo: GridPhoto) -> PillAction? {
        let count = GroupUndecidedCount(browsing.groupPhotos.map(\.marks))
        let plan = GroupFinishingPlan(
            group: group, action: .rejectUnmarked, currentPhoto: photo.id, marks: marks)
        if count.isCompleteByMarks {
            return PillAction(
                title: "Continue →", tone: .accent, identifier: "clove.group.continue"
            ) {
                autoAdvance.cancel()
                browsing.continueFromGroup()
            }
        } else if plan.availability.isAvailable && !plan.isEmpty {
            return PillAction(
                title: "Reject \(plan.rejects.count.formatted()) unmarked", tone: .reject,
                identifier: "clove.group.rejectUnmarked"
            ) {
                autoAdvance.cancel()
                browsing.runGroupFinishing(plan)
            }
        }
        return nil
    }

    private func show(_ photo: PhotoIdentity) {
        autoAdvance.cancel()
        guard browsing.groupPhotos.contains(where: { $0.id == photo }) else { return }
        browsing.showGroupPhoto(photo)
    }

    private func step(_ offset: Int) {
        guard let navigation, let current = browsing.state.groupPosition?.photo else { return }
        let next =
            offset < 0
            ? navigation.previousPhoto(before: current, marks: marks)
            : navigation.nextPhoto(after: current, marks: marks)
        if let next { show(next) }
    }

    private func startAutoAdvance(after kind: MarkKind, from photo: GridPhoto) {
        let next = navigation?.nextUndecidedPhoto(after: photo.id, marks: marks)
        let plan = MarkingInputRules(settings: store.settings).autoAdvancePlan(
            after: kind, from: photo.id, photos: browsing.groupPhotos,
            group: next.map(GroupAdvance.nextUndecidedPhoto) ?? .complete)
        browsing.recordAutoAdvance(plan)
        autoAdvance.schedule(plan) { target in
            switch target {
            case .stay: break
            case .groupUndecidedPhoto(let next), .nextPhoto(let next), .nextUnmarkedPhoto(let next):
                show(next)
            }
        }
    }
}
