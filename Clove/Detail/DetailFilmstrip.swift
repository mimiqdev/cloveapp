import CloveCore
import SwiftUI
import UIKit

/// Two-level Detail filmstrip built directly from `DetailTimeline` (issue #304, #318).
///
/// - Timeline (`expandedGroup == nil`): renders `timeline.slots` only — standalone photos and
///   collapsed group stacks (at `visibleMembers.count >= 2`). Never expands inline. Tapping the
///   already-selected collapsed stack, or dragging downward on any collapsed stack, enters Group
///   Focus. Tapping an unselected stack opens its Representative Photo in Timeline.
/// - Group Focus (`expandedGroup != nil`): renders ONLY the expanded group's `visibleMembers` inside
///   `ExpandedGroupSurface`, with a permanently visible, non-scrolling trailing `chevron.up`
///   collapse cap. Dragging upward anywhere on the strip collapses back to Timeline.
///
/// Both tracks live independently inside one constant `70 pt` band (`body`), keeping Timeline's
/// `ScrollView` alive across Group Focus so collapsing never resets its scroll offset or shifts
/// neighboring thumbnails (#318). The screen draws the finishing pill itself, so the strip's height
/// never changes with that pill's availability and its layout can never take photo space (#305).
struct DetailFilmstrip: View {
    let timeline: DetailTimeline
    let expandedGroup: ActiveBrowsingGroup?
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let openPhoto: (PhotoIdentity) -> Void
    let selectGroupPhoto: (PhotoIdentity) -> Void
    let expandGroup: (GroupID) -> Void
    let collapseGroup: () -> Void

    private static let timelineViewportSpace = "clove.detail.filmstrip.timeline.viewport"
    private static let groupViewportSpace = "clove.detail.filmstrip.group.viewport"
    private static let thumbnailWidth: CGFloat = 54
    private static let thumbnailHeight: CGFloat = 60
    private static let timelineSpacing: CGFloat = 8
    private static let groupRestingSpacing: CGFloat = 3
    private static let groupCompressedSpacing: CGFloat = -8
    private static let collapseCapWidth: CGFloat = 30
    private static let rollOffset: CGFloat = 18
    private static let rollDegrees: Double = 24
    private static let rollPerspective: CGFloat = 0.4

    @State private var timelineLayoutState = FilmstripLayoutState()
    @State private var groupLayoutState = FilmstripLayoutState()
    @State private var isTrackingVerticalStackDrag = false
    @State private var lastVerticalStackDragDate = Date.distantPast
    @State private var isTrackingVerticalGroupDrag = false
    @State private var lastVerticalGroupDragDate = Date.distantPast

    @State private var lastActiveGroup: ActiveBrowsingGroup?
    @State private var exitingGroup: ActiveBrowsingGroup?
    @State private var exitingGroupTask: Task<Void, Never>?
    @State private var levelTransitionTask: Task<Void, Never>?

    @State private var timelineOpacity: Double
    @State private var timelineOffsetY: CGFloat = 0
    @State private var timelineTilt: Double = 0
    @State private var timelinePulseScale: CGFloat = 1

    @State private var groupOpacity: Double
    @State private var groupOffsetY: CGFloat = 0
    @State private var groupTilt: Double = 0
    @State private var groupMemberSpacing: CGFloat = DetailFilmstrip.groupRestingSpacing
    @State private var groupMemberScaleX: CGFloat = 1

    @Environment(\.cloveTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language

    init(
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?,
        current: PhotoIdentity?,
        thumbnails: any GridThumbnailSource,
        openPhoto: @escaping (PhotoIdentity) -> Void,
        selectGroupPhoto: @escaping (PhotoIdentity) -> Void,
        expandGroup: @escaping (GroupID) -> Void,
        collapseGroup: @escaping () -> Void
    ) {
        self.timeline = timeline
        self.expandedGroup = expandedGroup
        self.current = current
        self.thumbnails = thumbnails
        self.openPhoto = openPhoto
        self.selectGroupPhoto = selectGroupPhoto
        self.expandGroup = expandGroup
        self.collapseGroup = collapseGroup
        let isExpanded = expandedGroup != nil
        _lastActiveGroup = State(initialValue: expandedGroup)
        _timelineOpacity = State(initialValue: isExpanded ? 0 : 1)
        _groupOpacity = State(initialValue: isExpanded ? 1 : 0)
    }

    var body: some View {
        ZStack {
            timelineTrack
            if let activeGroup = expandedGroup ?? exitingGroup {
                groupFocusTrack(activeGroup)
            }
        }
        .frame(height: 70)
        .clipped()
        .onChange(of: expandedGroup) { _, newValue in
            if let newValue {
                lastActiveGroup = newValue
            }
        }
        .onChange(of: expandedGroup?.id) { oldID, newID in
            handleLevelTransition(from: oldID, to: newID)
        }
        .onDisappear {
            levelTransitionTask?.cancel()
            exitingGroupTask?.cancel()
            timelineLayoutState.pendingScroll?.cancel()
            groupLayoutState.pendingScroll?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.filmstrip")
    }

    // MARK: - Timeline Track

    private var timelineTrack: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: Self.timelineSpacing) {
                    ForEach(timeline.slots) { slot in
                        timelineSlotView(slot)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("clove.detail.filmstrip.timeline")
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }
            .coordinateSpace(name: Self.timelineViewportSpace)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                timelineLayoutState.viewportWidth = $0
            }
            .onChange(of: current, initial: true) { oldPhoto, photo in
                let isInitial = oldPhoto == photo
                if expandedGroup == nil || isInitial {
                    scheduleTimelineScroll(
                        for: photo, using: proxy, forceScroll: false, animated: !isInitial)
                }
            }
            .onChange(of: expandedGroup?.id) { oldID, newID in
                if oldID != nil && newID == nil {
                    scheduleTimelineScroll(
                        for: current, using: proxy, forceScroll: false, animated: false)
                }
            }
        }
        .scaleEffect(timelinePulseScale)
        .rotation3DEffect(
            .degrees(timelineTilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: Self.rollPerspective
        )
        .offset(y: timelineOffsetY)
        .opacity(timelineOpacity)
        .allowsHitTesting(expandedGroup == nil)
        .accessibilityHidden(expandedGroup != nil)
    }

    // MARK: - Group Focus Track

    private func groupFocusTrack(_ group: ActiveBrowsingGroup) -> some View {
        let currentMembersWidth = max(
            Self.thumbnailWidth,
            CGFloat(group.visibleMembers.count) * Self.thumbnailWidth
                + CGFloat(max(0, group.visibleMembers.count - 1)) * groupMemberSpacing
        )

        return Color.clear
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
            .overlay {
                HStack(spacing: 3) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .bottom, spacing: groupMemberSpacing) {
                                ForEach(group.visibleMembers) { photo in
                                    frame(
                                        photo,
                                        coordinateSpace: Self.groupViewportSpace,
                                        layoutState: groupLayoutState,
                                        scaleX: groupMemberScaleX,
                                        suppressTap: {
                                            expandedGroup == nil
                                                || isTrackingVerticalGroupDrag
                                                || Date().timeIntervalSince(
                                                    lastVerticalGroupDragDate) < 0.25
                                        }
                                    ) {
                                        selectGroupPhoto(photo.id)
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: Self.groupViewportSpace)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.width
                        } action: {
                            groupLayoutState.viewportWidth = $0
                        }
                        .onAppear {
                            groupLayoutState.frames.removeAll()
                            scheduleGroupScroll(for: current, using: proxy, forceScroll: true)
                        }
                        .onChange(of: current) { _, photo in
                            guard expandedGroup != nil else { return }
                            scheduleGroupScroll(for: photo, using: proxy, forceScroll: false)
                        }
                        .onChange(of: group.id) { _, _ in
                            groupLayoutState.frames.removeAll()
                            scheduleGroupScroll(for: current, using: proxy, forceScroll: true)
                        }
                    }
                    .frame(maxWidth: currentMembersWidth)
                    .frame(height: Self.thumbnailHeight)

                    collapseCapButton
                        .layoutPriority(1)
                }
                .padding(3)
                .background {
                    ExpandedGroupSurface(cornerRadius: 9)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("clove.detail.filmstrip.expandedGroup")
                .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard expandedGroup != nil else { return }
                        if abs(value.translation.height) >= 12,
                            abs(value.translation.height)
                                > FilmstripVerticalGesture.dominanceRatio
                                * abs(value.translation.width)
                        {
                            isTrackingVerticalGroupDrag = true
                            lastVerticalGroupDragDate = Date()
                        }
                    }
                    .onEnded { value in
                        let shouldCollapse =
                            expandedGroup != nil
                            && FilmstripVerticalGesture.shouldCollapse(
                                horizontal: Double(value.translation.width),
                                vertical: Double(value.translation.height))
                        let wasVerticalDominant =
                            abs(value.translation.height)
                            > FilmstripVerticalGesture.dominanceRatio * abs(value.translation.width)
                        isTrackingVerticalGroupDrag = false
                        if shouldCollapse || wasVerticalDominant {
                            lastVerticalGroupDragDate = Date()
                        }
                        if shouldCollapse {
                            collapseGroup()
                        }
                    }
            )
            .rotation3DEffect(
                .degrees(groupTilt),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: Self.rollPerspective
            )
            .offset(y: groupOffsetY)
            .opacity(groupOpacity)
            .allowsHitTesting(expandedGroup != nil)
            .accessibilityHidden(expandedGroup == nil)
    }

    private var collapseCapButton: some View {
        Button {
            guard expandedGroup != nil else { return }
            collapseGroup()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clove.text.primary)
                .frame(width: Self.collapseCapWidth, height: Self.thumbnailHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("Collapse group", language: language))
        .accessibilityIdentifier("clove.detail.filmstrip.group.fold")
    }

    // MARK: - Level Transition Choreography

    private func handleLevelTransition(from oldID: GroupID?, to newID: GroupID?) {
        levelTransitionTask?.cancel()
        exitingGroupTask?.cancel()

        if newID != nil {
            isTrackingVerticalStackDrag = false
        } else {
            isTrackingVerticalGroupDrag = false
        }

        if oldID == nil, newID != nil {
            // Expand: Timeline -> Group Focus (上 → 下 roll + fan-out)
            exitingGroup = nil
            if reduceMotion {
                timelineOffsetY = 0
                timelineTilt = 0
                timelinePulseScale = 1
                timelineOpacity = 1
                groupOffsetY = 0
                groupTilt = 0
                groupMemberSpacing = Self.groupRestingSpacing
                groupMemberScaleX = 1
                groupOpacity = 0
                levelTransitionTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(CloveMotion.filmstripLevel(reduceMotion: true)) {
                        timelineOpacity = 0
                        groupOpacity = 1
                    }
                }
            } else {
                timelineOffsetY = 0
                timelineTilt = 0
                timelinePulseScale = 1
                timelineOpacity = 1
                groupOffsetY = -Self.rollOffset
                groupTilt = Self.rollDegrees
                groupMemberSpacing = Self.groupCompressedSpacing
                groupMemberScaleX = 0.9
                groupOpacity = 0
                levelTransitionTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(CloveMotion.filmstripLevel(reduceMotion: false)) {
                        timelineOffsetY = Self.rollOffset
                        timelineTilt = -Self.rollDegrees
                        timelineOpacity = 0
                        groupOffsetY = 0
                        groupTilt = 0
                        groupMemberSpacing = Self.groupRestingSpacing
                        groupMemberScaleX = 1
                        groupOpacity = 1
                    }
                }
            }
        } else if oldID != nil, newID == nil {
            // Collapse: Group Focus -> Timeline (下 → 上 roll + gather-in + settle pulse + haptic)
            exitingGroup = lastActiveGroup
            UISelectionFeedbackGenerator().selectionChanged()
            if reduceMotion {
                groupOffsetY = 0
                groupTilt = 0
                groupMemberSpacing = Self.groupRestingSpacing
                groupMemberScaleX = 1
                groupOpacity = 1
                timelineOffsetY = 0
                timelineTilt = 0
                timelinePulseScale = 1
                timelineOpacity = 0
                levelTransitionTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(CloveMotion.filmstripLevel(reduceMotion: true)) {
                        groupOpacity = 0
                        timelineOpacity = 1
                    }
                }
                scheduleExitingGroupCleanup(after: CloveMotion.chromeDuration + 0.04)
            } else {
                groupOffsetY = 0
                groupTilt = 0
                groupMemberSpacing = Self.groupRestingSpacing
                groupMemberScaleX = 1
                groupOpacity = 1
                timelineOffsetY = Self.rollOffset
                timelineTilt = -Self.rollDegrees
                timelinePulseScale = 1.05
                timelineOpacity = 0
                levelTransitionTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(CloveMotion.filmstripLevel(reduceMotion: false)) {
                        groupOffsetY = -Self.rollOffset
                        groupTilt = Self.rollDegrees
                        groupMemberSpacing = Self.groupCompressedSpacing
                        groupMemberScaleX = 0.9
                        groupOpacity = 0
                        timelineOffsetY = 0
                        timelineTilt = 0
                        timelinePulseScale = 1
                        timelineOpacity = 1
                    }
                }
                scheduleExitingGroupCleanup(after: CloveMotion.filmstripLevelDuration + 0.08)
            }
        } else if oldID != newID {
            // Direct swap between two distinct groups (e.g. Undo re-entry).
            exitingGroup = nil
            timelineOpacity = 0
            timelineOffsetY = 0
            timelineTilt = 0
            timelinePulseScale = 1
            groupOpacity = 1
            groupOffsetY = 0
            groupTilt = 0
            groupMemberSpacing = Self.groupRestingSpacing
            groupMemberScaleX = 1
        }
    }

    private func scheduleExitingGroupCleanup(after duration: TimeInterval) {
        exitingGroupTask?.cancel()
        exitingGroupTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, expandedGroup == nil else { return }
            exitingGroup = nil
            groupMemberSpacing = Self.groupRestingSpacing
            groupMemberScaleX = 1
            groupOffsetY = 0
            groupTilt = 0
        }
    }

    // MARK: - Items & Slots

    @ViewBuilder
    private func timelineSlotView(_ slot: TimelineSlot) -> some View {
        switch slot {
        case .photo(let photo):
            frame(
                photo,
                coordinateSpace: Self.timelineViewportSpace,
                layoutState: timelineLayoutState,
                scaleX: 1,
                suppressTap: { expandedGroup != nil }
            ) {
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
            if expandedGroup != nil
                || isTrackingVerticalStackDrag
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
            .frame(width: Self.thumbnailWidth, height: 64)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard expandedGroup == nil else { return }
                    if abs(value.translation.height) >= 12,
                        abs(value.translation.height)
                            > FilmstripVerticalGesture.dominanceRatio * abs(value.translation.width)
                    {
                        isTrackingVerticalStackDrag = true
                        lastVerticalStackDragDate = Date()
                    }
                }
                .onEnded { value in
                    let shouldExpand =
                        expandedGroup == nil
                        && FilmstripVerticalGesture.shouldExpand(
                            horizontal: Double(value.translation.width),
                            vertical: Double(value.translation.height))
                    let wasVerticalDominant =
                        abs(value.translation.height)
                        > FilmstripVerticalGesture.dominanceRatio * abs(value.translation.width)
                    isTrackingVerticalStackDrag = false
                    if shouldExpand || wasVerticalDominant {
                        lastVerticalStackDragDate = Date()
                    }
                    if shouldExpand {
                        expandGroup(active.id)
                    }
                }
        )
        .id(GridCellItem.ID.group(active.id))
        .modifier(
            FilmstripItemFrameTracker(
                id: .group(active.id), coordinateSpace: Self.timelineViewportSpace,
                layoutState: timelineLayoutState)
        )
        .accessibilityLabel(
            AppLocalization.format(
                "Similar group of %lld photos", language: language,
                Int64(active.visibleMembers.count))
        )
        .accessibilityValue(MarkSummary.text(for: active.representative.marks, language: language))
        .accessibilityAddTraits(holdsCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("clove.detail.filmstrip.group.\(active.id.rawValue)")
    }

    private func frame(
        _ photo: GridPhoto,
        coordinateSpace: String,
        layoutState: FilmstripLayoutState,
        scaleX: CGFloat,
        suppressTap: @escaping () -> Bool,
        tap: @escaping () -> Void
    ) -> some View {
        let cellID = GridCellItem.ID.photo(photo.id)
        return Button {
            guard !suppressTap() else { return }
            tap()
        } label: {
            DetailPhotoFrame(
                photo: photo, isCurrent: photo.id == current, thumbnails: thumbnails,
                side: Self.thumbnailWidth, height: Self.thumbnailHeight
            )
            .scaleEffect(x: scaleX, y: 1, anchor: .center)
        }
        .buttonStyle(.plain)
        .id(cellID)
        .modifier(
            FilmstripItemFrameTracker(
                id: cellID, coordinateSpace: coordinateSpace, layoutState: layoutState)
        )
        .accessibilityIdentifier("clove.detail.filmstrip.\(photo.id.stem.lowercased())")
    }

    // MARK: - Scroll Anchoring

    private func timelineScrollTarget(for photo: PhotoIdentity) -> GridCellItem.ID {
        if let active = timeline.activeGroup(containing: photo) {
            return .group(active.id)
        }
        return .photo(photo)
    }

    private func scheduleTimelineScroll(
        for photo: PhotoIdentity?, using proxy: ScrollViewProxy, forceScroll: Bool, animated: Bool
    ) {
        timelineLayoutState.pendingScroll?.cancel()
        guard let photo else { return }
        let target = timelineScrollTarget(for: photo)
        timelineLayoutState.pendingScroll = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if forceScroll {
                proxy.scrollTo(target, anchor: .center)
            } else {
                guard !timelineLayoutState.isVisible(target) else { return }
                if animated {
                    withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                } else {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private func scheduleGroupScroll(
        for photo: PhotoIdentity?, using proxy: ScrollViewProxy, forceScroll: Bool
    ) {
        groupLayoutState.pendingScroll?.cancel()
        guard let photo else { return }
        let target = GridCellItem.ID.photo(photo)
        groupLayoutState.pendingScroll = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if forceScroll {
                proxy.scrollTo(target, anchor: .center)
            } else {
                guard !groupLayoutState.isVisible(target) else { return }
                withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(target, anchor: .center)
                }
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
