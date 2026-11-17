import CloveCore
import SwiftUI

/// Two-level Detail filmstrip built directly from `DetailTimeline` (issue #304).
///
/// - Timeline (`expandedGroup == nil`): renders `timeline.slots` only — standalone photos and
///   collapsed group stacks (at `visibleMembers.count >= 2`). Never expands inline. Tapping the
///   already-selected collapsed stack, or dragging upward on any collapsed stack, enters Group Focus.
///   Tapping an unselected stack opens its Representative Photo in Timeline.
/// - Group Focus (`expandedGroup != nil`): renders ONLY the expanded group's `visibleMembers` inside
///   `ExpandedGroupSurface`, with a leading `chevron.down` collapse button. Dragging downward
///   anywhere on the strip collapses back to Timeline.
///
/// The strip is one constant band (`strip`). The screen draws the finishing pill itself, so the
/// strip's height never changes with that pill's availability and its layout can never take photo
/// space (#305).
struct DetailFilmstrip: View {
    let timeline: DetailTimeline
    let expandedGroup: ActiveBrowsingGroup?
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let openPhoto: (PhotoIdentity) -> Void
    let selectGroupPhoto: (PhotoIdentity) -> Void
    let expandGroup: (GroupID) -> Void
    let collapseGroup: () -> Void

    private static let viewportSpace = "clove.detail.filmstrip.viewport"
    @State private var layoutState = FilmstripLayoutState()
    @State private var isTrackingVerticalStackDrag = false
    @State private var lastVerticalStackDragDate = Date.distantPast
    @Environment(\.cloveTheme) private var theme

    var body: some View {
        strip
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clove.detail.filmstrip")
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: expandedGroup != nil ? 3 : 8) {
                    if let expandedGroup {
                        expandedGroupItems(expandedGroup)
                    } else {
                        ForEach(timeline.slots) { slot in
                            timelineSlotView(slot)
                        }
                    }
                }
                .padding(expandedGroup != nil ? 3 : 0)
                .background {
                    if expandedGroup != nil {
                        ExpandedGroupSurface(cornerRadius: 9)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    expandedGroup != nil
                        ? "clove.detail.filmstrip.expandedGroup"
                        : "clove.detail.filmstrip.timeline"
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard expandedGroup != nil,
                            FilmstripVerticalGesture.shouldCollapse(
                                horizontal: Double(value.translation.width),
                                vertical: Double(value.translation.height))
                        else { return }
                        collapseGroup()
                    }
            )
            .coordinateSpace(name: Self.viewportSpace)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                layoutState.viewportWidth = $0
            }
            .onChange(of: current, initial: true) { _, photo in
                scheduleScroll(for: photo, using: proxy, forceScroll: false)
            }
            .onChange(of: expandedGroup?.id) { _, _ in
                layoutState.frames.removeAll()
                scheduleScroll(for: current, using: proxy, forceScroll: true)
            }
        }
        .frame(height: 70)
    }

    @ViewBuilder
    private func expandedGroupItems(_ group: ActiveBrowsingGroup) -> some View {
        Button(action: collapseGroup) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: 20, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(GridCellItem.ID.group(group.id))
        .accessibilityLabel("Collapse group")
        .accessibilityIdentifier("clove.detail.filmstrip.group.fold")

        ForEach(group.visibleMembers) { photo in
            frame(photo) {
                selectGroupPhoto(photo.id)
            }
        }
    }

    @ViewBuilder
    private func timelineSlotView(_ slot: TimelineSlot) -> some View {
        switch slot {
        case .photo(let photo):
            frame(photo) {
                openPhoto(photo.id)
            }
        case .group(let active):
            collapsedGroupStack(active)
        }
    }

    private func collapsedGroupStack(_ active: ActiveBrowsingGroup) -> some View {
        let holdsCurrent =
            current.map { id in
                active.visibleMembers.contains { $0.id == id }
            } ?? false
        let isDimmed = active.visibleMembers.allSatisfy(\.marks.isRejected)
        let peekingIDs = GridDisplay.peekingPhotos(
            cover: active.representative.id, visibleMembers: active.visibleMembers)

        return Button {
            if isTrackingVerticalStackDrag
                || Date().timeIntervalSince(lastVerticalStackDragDate) < 0.25
            {
                return
            }
            if holdsCurrent {
                expandGroup(active.id)
            } else {
                openPhoto(active.representative.id)
            }
        } label: {
            FilmstripGroupStack(
                cover: active.representative,
                peekingIDs: peekingIDs,
                isCurrent: holdsCurrent,
                isDimmed: isDimmed,
                visibleCount: active.visibleMembers.count,
                thumbnails: thumbnails
            )
            .frame(width: 54, height: 64)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if abs(value.translation.height) > 12,
                        abs(value.translation.height)
                            > FilmstripVerticalGesture.dominanceRatio * abs(value.translation.width)
                    {
                        isTrackingVerticalStackDrag = true
                    }
                }
                .onEnded { value in
                    let shouldExpand = FilmstripVerticalGesture.shouldExpand(
                        horizontal: Double(value.translation.width),
                        vertical: Double(value.translation.height))
                    isTrackingVerticalStackDrag = false
                    if shouldExpand {
                        lastVerticalStackDragDate = Date()
                        expandGroup(active.id)
                    }
                }
        )
        .id(GridCellItem.ID.group(active.id))
        .modifier(
            FilmstripItemFrameTracker(
                id: .group(active.id), coordinateSpace: Self.viewportSpace,
                layoutState: layoutState)
        )
        .accessibilityLabel("Similar group of \(active.visibleMembers.count) photos")
        .accessibilityValue(MarkSummary.text(for: active.representative.marks))
        .accessibilityAddTraits(holdsCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("clove.detail.filmstrip.group.\(active.id.rawValue)")
    }

    private func frame(_ photo: GridPhoto, tap: @escaping () -> Void) -> some View {
        let cellID = GridCellItem.ID.photo(photo.id)
        return Button(action: tap) {
            DetailPhotoFrame(
                photo: photo, isCurrent: photo.id == current, thumbnails: thumbnails,
                side: 54, height: 60
            )
        }
        .buttonStyle(.plain)
        .id(cellID)
        .modifier(
            FilmstripItemFrameTracker(
                id: cellID, coordinateSpace: Self.viewportSpace, layoutState: layoutState)
        )
        .accessibilityIdentifier("clove.detail.filmstrip.\(photo.id.stem.lowercased())")
    }

    private func scrollTarget(for photo: PhotoIdentity) -> GridCellItem.ID {
        if expandedGroup != nil {
            return .photo(photo)
        }
        if let active = timeline.activeGroup(containing: photo) {
            return .group(active.id)
        }
        return .photo(photo)
    }

    private func scheduleScroll(
        for photo: PhotoIdentity?, using proxy: ScrollViewProxy, forceScroll: Bool
    ) {
        layoutState.pendingScroll?.cancel()
        guard let photo else { return }
        let target = scrollTarget(for: photo)
        layoutState.pendingScroll = Task { @MainActor in
            // The scroll runs after the change's layout settles, not inside its transaction:
            // entering or leaving a group swaps the lazy entries' identity in the same change,
            // and a scroll resolved against that transaction lands past the new content's end,
            // leaving the strip blank until the next drag (#237). Only scroll when the target
            // is off-screen so in-place taps do not jump (#241); level transitions always scroll
            // cleanly onto the target item or stack (#304).
            await Task.yield()
            guard !Task.isCancelled else { return }
            if forceScroll {
                proxy.scrollTo(target, anchor: .center)
            } else {
                guard !layoutState.isVisible(target) else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }
}

@MainActor
private final class FilmstripLayoutState {
    struct TrackedFrame {
        let token: UUID
        let frame: CGRect
    }

    var viewportWidth: CGFloat = 0
    var frames: [GridCellItem.ID: TrackedFrame] = [:]
    var pendingScroll: Task<Void, Never>?

    func isVisible(_ target: GridCellItem.ID) -> Bool {
        guard viewportWidth > 0, let frame = frames[target]?.frame else { return false }
        let tolerance: CGFloat = 4
        return frame.minX >= -tolerance && frame.maxX <= viewportWidth + tolerance
    }
}

private struct FilmstripItemFrameTracker: ViewModifier {
    let id: GridCellItem.ID
    let coordinateSpace: String
    let layoutState: FilmstripLayoutState
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(coordinateSpace))
            } action: { rect in
                layoutState.frames[id] = .init(token: token, frame: rect)
            }
            .onDisappear {
                if layoutState.frames[id]?.token == token {
                    layoutState.frames.removeValue(forKey: id)
                }
            }
    }
}

private struct FilmstripGroupStack: View {
    let cover: GridPhoto
    let peekingIDs: [PhotoIdentity]
    let isCurrent: Bool
    let isDimmed: Bool
    let visibleCount: Int
    let thumbnails: any GridThumbnailSource
    @State private var peekingThumbnails: [PhotoIdentity: CGImage] = [:]
    @Environment(\.cloveTheme) private var theme

    var body: some View {
        GroupStack(
            peek: 4,
            peekingImages: peekingIDs.map { peekingThumbnails[$0] },
            cardBacking: Color.clove.bg.stage
        ) {
            DetailPhotoFrame(
                photo: cover, isCurrent: false, thumbnails: thumbnails,
                side: 54, height: 60, showsMarks: true, appliesRejectedOpacity: false)
        }
        .opacity(isDimmed ? theme.tokens.rejectedOpacity : 1)
        .overlay(alignment: .topTrailing) {
            GroupCountBadge(count: visibleCount, presentation: .filmstrip)
                .padding(2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.clove.text.primary, lineWidth: isCurrent ? 2 : 0)
        }
        .onChange(of: peekingIDs, initial: true) { _, needed in
            let keep = Set(needed)
            peekingThumbnails = peekingThumbnails.filter { keep.contains($0.key) }
        }
        .task(id: peekingIDs.first) {
            await loadPeeking(peekingIDs.first)
        }
        .task(id: peekingIDs.dropFirst().first) {
            await loadPeeking(peekingIDs.dropFirst().first)
        }
    }

    private func loadPeeking(_ photo: PhotoIdentity?) async {
        guard let photo, peekingThumbnails[photo] == nil else { return }
        for delay in [0, 150, 300, 600, 1_200, 2_400] {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return }
            let outcome = await thumbnails.thumbnail(for: photo, priority: .visible)
            guard !Task.isCancelled, peekingIDs.contains(photo) else { return }
            switch outcome {
            case .image(let pixels):
                peekingThumbnails[photo] = pixels
                return
            case .unavailable:
                return
            case .deferred:
                continue
            }
        }
    }
}
