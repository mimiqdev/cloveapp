import CloveCore
import SwiftUI
import UIKit

/// Two-level Detail filmstrip built directly from `DetailTimeline` (issue #304, #318).
///
/// - Timeline (`expandedGroup == nil`): renders `timeline.slots` only — standalone photos and
///   collapsed group stacks (at `visibleMembers.count >= 2`). Never expands inline. Tapping the
///   already-selected collapsed stack, or dragging downward on any collapsed stack, enters Group
///   Focus. Tapping an unselected stack opens its Representative Photo in Timeline.
/// - Group Focus (`expandedGroup != nil`): renders ONLY the expanded group's `visibleMembers` with
///   the same background-free floating presentation as Timeline, flanked by `36 × 36 pt` native
///   Liquid Glass circular controls: a trailing `chevron.up` collapse button (always shown) and a
///   leading `square.grid.2x2` grid picker button shown only when `visibleMembers` overflow the
///   current filmstrip width. Dragging upward anywhere on the strip collapses back to Timeline.
///
/// Both tracks live independently inside one constant-height band (`body`: `76 pt` standard,
/// `62 pt` compact), keeping Timeline's `ScrollView` alive across Group Focus so collapsing never
/// resets its scroll offset or shifts neighboring thumbnails (#318) and reserving room for the
/// `6 pt` raised current tile plus its `12 × 4 pt` two-tone marker `2 pt` below (#407). The
/// screen draws the finishing pill itself, so the strip's height never changes with that pill's
/// availability and its layout can never take photo space (#305).
struct DetailFilmstrip: View {
    struct Metrics: Equatable {
        let thumbnailWidth: CGFloat
        let thumbnailHeight: CGFloat
        let stackHeight: CGFloat
        let bandHeight: CGFloat
        let groupActionButtonSize: CGFloat
        let groupActionSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalTrackPadding: CGFloat
        let groupStackPeek: CGFloat

        static let standard = Metrics(
            thumbnailWidth: 54,
            thumbnailHeight: 60,
            stackHeight: 64,
            bandHeight: 76,
            groupActionButtonSize: 36,
            groupActionSpacing: 8,
            horizontalPadding: 10,
            verticalTrackPadding: 3,
            groupStackPeek: 4
        )

        static let compact = Metrics(
            thumbnailWidth: 48,
            thumbnailHeight: 48,
            stackHeight: 52,
            bandHeight: 62,
            groupActionButtonSize: 36,
            groupActionSpacing: 6,
            horizontalPadding: 8,
            verticalTrackPadding: 2,
            groupStackPeek: 4
        )
    }

    static let thumbnailSpacing: CGFloat = FilmstripCurrentPhotoMarker.thumbnailSpacing

    let timeline: DetailTimeline
    let expandedGroup: ActiveBrowsingGroup?
    let current: PhotoIdentity?
    let thumbnails: any GridThumbnailSource
    let metrics: Metrics
    let gridPickerDismissToken: Int
    let gridPickerPresentTrigger: Int
    let openPhoto: (PhotoIdentity) -> Void
    let selectGroupPhoto: (PhotoIdentity) -> Void
    let expandGroup: (GroupID) -> Void
    let collapseGroup: () -> Void

    private static let groupRestingSpacing: CGFloat = thumbnailSpacing
    private static let groupCompressedSpacing: CGFloat = -8
    private static let rollOffset: CGFloat = 18
    private static let rollDegrees: Double = 24
    private static let rollPerspective: CGFloat = 0.4

    @State private var trackWidth: CGFloat = 0
    @State private var pendingTimelineScroll: Task<Void, Never>?
    @State private var pendingGroupScroll: Task<Void, Never>?
    @State private var isUserDraggingTimeline = false
    @State private var isUserDraggingGroup = false
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
    @State private var presentedGridPickerMode: GroupPhotoGridPickerPresentationMode?
    @State private var isGridPickerAnchorReady = false

    @Environment(\.cloveTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cloveReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tapPickerController) private var tapPicker
    @Environment(\.tapPickerTriggerRequest) private var tapPickerTriggerRequest

    init(
        timeline: DetailTimeline,
        expandedGroup: ActiveBrowsingGroup?,
        current: PhotoIdentity?,
        thumbnails: any GridThumbnailSource,
        metrics: Metrics = .standard,
        gridPickerDismissToken: Int = 0,
        gridPickerPresentTrigger: Int = 0,
        openPhoto: @escaping (PhotoIdentity) -> Void,
        selectGroupPhoto: @escaping (PhotoIdentity) -> Void,
        expandGroup: @escaping (GroupID) -> Void,
        collapseGroup: @escaping () -> Void
    ) {
        self.timeline = timeline
        self.expandedGroup = expandedGroup
        self.current = current
        self.thumbnails = thumbnails
        self.metrics = metrics
        self.gridPickerDismissToken = gridPickerDismissToken
        self.gridPickerPresentTrigger = gridPickerPresentTrigger
        self.openPhoto = openPhoto
        self.selectGroupPhoto = selectGroupPhoto
        self.expandGroup = expandGroup
        self.collapseGroup = collapseGroup
        let isExpanded = expandedGroup != nil
        _lastActiveGroup = State(initialValue: expandedGroup)
        _timelineOpacity = State(initialValue: isExpanded ? 0 : 1)
        _groupOpacity = State(initialValue: isExpanded ? 1 : 0)
    }

    static func showsGridPickerButton(
        memberCount: Int,
        trackWidth: CGFloat,
        metrics: Metrics
    ) -> Bool {
        guard trackWidth > 0, memberCount > 1 else { return false }
        let availableWithoutPicker =
            trackWidth
            - 2 * metrics.horizontalPadding
            - metrics.groupActionButtonSize
            - metrics.groupActionSpacing
        let totalMembersWidth =
            CGFloat(memberCount) * metrics.thumbnailWidth
            + CGFloat(max(0, memberCount - 1)) * Self.thumbnailSpacing
        return totalMembersWidth > availableWithoutPicker + 0.5
    }

    private func showsGridPicker(for group: ActiveBrowsingGroup) -> Bool {
        Self.showsGridPickerButton(
            memberCount: group.visibleMembers.count,
            trackWidth: trackWidth,
            metrics: metrics
        )
    }

    private var activeShowsGridPicker: Bool {
        guard let expandedGroup else { return false }
        return showsGridPicker(for: expandedGroup)
    }

    var body: some View {
        ZStack {
            timelineTrack
            if let activeGroup = expandedGroup ?? exitingGroup {
                groupFocusTrack(activeGroup)
            }
        }
        .frame(height: metrics.bandHeight)
        .clipped()
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { newWidth in
            if abs(trackWidth - newWidth) > 0.5 {
                trackWidth = newWidth
            }
        }
        .onChange(of: expandedGroup) { _, newValue in
            if let newValue {
                lastActiveGroup = newValue
            }
        }
        .onChange(of: expandedGroup?.id) { oldID, newID in
            handleLevelTransition(from: oldID, to: newID)
        }
        .onChange(of: gridPickerDismissTrigger) { _, _ in
            presentedGridPickerMode = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                presentedGridPickerMode = nil
            }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    presentedGridPickerMode == .sheet
                        && expandedGroup != nil
                        && activeShowsGridPicker
                        && scenePhase == .active
                },
                set: {
                    if !$0, presentedGridPickerMode == .sheet {
                        presentedGridPickerMode = nil
                    }
                })
        ) {
            if let sheetGroup = expandedGroup ?? lastActiveGroup {
                gridPickerContent(for: sheetGroup, showsDoneButton: true)
            }
        }
        .onDisappear {
            levelTransitionTask?.cancel()
            exitingGroupTask?.cancel()
            pendingTimelineScroll?.cancel()
            pendingGroupScroll?.cancel()
            isUserDraggingTimeline = false
            isUserDraggingGroup = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.filmstrip")
        .reportTapPickerFrame("clove.detail.filmstrip")
    }

    // MARK: - Timeline Track

    private var timelineScrollTrigger: TimelineScrollTrigger {
        TimelineScrollTrigger(
            current: current,
            expandedGroupID: expandedGroup?.id,
            slotCount: timeline.slots.count,
            currentSlotIndex: current.flatMap { timeline.slotIndex(containing: $0) },
            metrics: metrics,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            viewportWidth: Int(trackWidth.rounded())
        )
    }

    private var timelineTrack: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: Self.thumbnailSpacing) {
                    ForEach(timeline.slots) { slot in
                        timelineSlotView(slot)
                    }
                }
                .frame(
                    minHeight: metrics.bandHeight - 2 * metrics.verticalTrackPadding,
                    alignment: .bottom
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("clove.detail.filmstrip.timeline")
                .reportTapPickerFrame("clove.detail.filmstrip.timeline")
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalTrackPadding)
            }
            .frame(height: metrics.bandHeight)
            .contentShape(Rectangle())
            .filmstripScrollEdgeEffectHidden()
            .onScrollPhaseChange { _, newPhase in
                isUserDraggingTimeline = newPhase == .interacting || newPhase == .decelerating
                if newPhase == .interacting {
                    pendingTimelineScroll?.cancel()
                    pendingTimelineScroll = nil
                }
            }
            .onChange(of: timelineScrollTrigger, initial: true) { old, new in
                let isInitial = old == new
                let didLayoutChange =
                    old.metrics != new.metrics
                    || old.horizontalSizeClass != new.horizontalSizeClass
                    || old.verticalSizeClass != new.verticalSizeClass
                    || old.isDuoExpanded != new.isDuoExpanded
                    || old.isDuoCover != new.isDuoCover
                    || old.viewportWidth != new.viewportWidth
                    || old.slotCount != new.slotCount
                    || (old.current == new.current && old.currentSlotIndex != new.currentSlotIndex)
                let didCollapseToTimeline = old.expandedGroupID != nil && new.expandedGroupID == nil

                if isInitial || (old.viewportWidth == 0 && new.viewportWidth > 0) {
                    scheduleTimelineScroll(for: new.current, using: proxy, animated: false)
                } else if new.expandedGroupID == nil {
                    if didCollapseToTimeline || (didLayoutChange && !isUserDraggingTimeline) {
                        scheduleTimelineScroll(for: new.current, using: proxy, animated: false)
                    } else if old.current != new.current {
                        scheduleTimelineScroll(for: new.current, using: proxy, animated: true)
                    }
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

    private func groupScrollTrigger(for group: ActiveBrowsingGroup) -> GroupScrollTrigger {
        GroupScrollTrigger(
            current: current,
            expandedGroupID: expandedGroup?.id,
            memberCount: group.visibleMembers.count,
            currentMemberIndex: current.flatMap { id in
                group.visibleMembers.firstIndex { $0.id == id }
            },
            metrics: metrics,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            showsGridPicker: showsGridPicker(for: group),
            trackWidth: Int(trackWidth.rounded())
        )
    }

    private func groupFocusTrack(_ group: ActiveBrowsingGroup) -> some View {
        let currentMembersWidth = max(
            metrics.thumbnailWidth,
            CGFloat(group.visibleMembers.count) * metrics.thumbnailWidth
                + CGFloat(max(0, group.visibleMembers.count - 1)) * groupMemberSpacing
        )
        let showsPicker = showsGridPicker(for: group)

        return Color.clear
            .frame(
                maxWidth: .infinity, minHeight: metrics.bandHeight, maxHeight: metrics.bandHeight
            )
            .overlay {
                HStack(alignment: .bottom, spacing: metrics.groupActionSpacing) {
                    if showsPicker {
                        gridPickerButton(for: group)
                            .frame(
                                width: metrics.groupActionButtonSize,
                                height: metrics.thumbnailHeight
                            )
                            .padding(.vertical, metrics.verticalTrackPadding)
                            .layoutPriority(1)
                    }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .bottom, spacing: groupMemberSpacing) {
                                ForEach(group.visibleMembers) { photo in
                                    frame(
                                        photo,
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
                            .frame(
                                minHeight: metrics.bandHeight - 2 * metrics.verticalTrackPadding,
                                alignment: .bottom
                            )
                            .padding(.vertical, metrics.verticalTrackPadding)
                        }
                        .frame(height: metrics.bandHeight)
                        .contentShape(Rectangle())
                        .filmstripScrollEdgeEffectHidden()
                        .onScrollPhaseChange { _, newPhase in
                            isUserDraggingGroup =
                                newPhase == .interacting || newPhase == .decelerating
                            if newPhase == .interacting {
                                pendingGroupScroll?.cancel()
                                pendingGroupScroll = nil
                            }
                        }
                        .onChange(of: groupScrollTrigger(for: group), initial: true) { old, new in
                            guard new.expandedGroupID != nil else { return }
                            let isInitial = old == new
                            let didEnterOrSwitchGroup = old.expandedGroupID != new.expandedGroupID
                            let didLayoutChange =
                                old.metrics != new.metrics
                                || old.horizontalSizeClass != new.horizontalSizeClass
                                || old.verticalSizeClass != new.verticalSizeClass
                                || old.isDuoExpanded != new.isDuoExpanded
                                || old.isDuoCover != new.isDuoCover
                                || old.showsGridPicker != new.showsGridPicker
                                || old.trackWidth != new.trackWidth
                                || old.memberCount != new.memberCount
                                || (old.current == new.current
                                    && old.currentMemberIndex != new.currentMemberIndex)

                            if isInitial || didEnterOrSwitchGroup
                                || (didLayoutChange && !isUserDraggingGroup)
                            {
                                scheduleGroupScroll(
                                    for: new.current, using: proxy, animated: false)
                            } else if old.current != new.current {
                                scheduleGroupScroll(
                                    for: new.current, using: proxy, animated: true)
                            }
                        }
                    }
                    .frame(maxWidth: currentMembersWidth)

                    collapseButton
                        .frame(
                            width: metrics.groupActionButtonSize,
                            height: metrics.thumbnailHeight
                        )
                        .padding(.vertical, metrics.verticalTrackPadding)
                        .layoutPriority(1)
                }
                .frame(height: metrics.bandHeight, alignment: .bottom)
                .background {
                    Color.clear
                        .reportTapPickerFrame("clove.detail.filmstrip.expandedGroup")
                        .padding(.vertical, metrics.verticalTrackPadding)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("clove.detail.filmstrip.expandedGroup")
                .padding(.horizontal, metrics.horizontalPadding)
            }
            .contentShape(Rectangle())
            .gesture(
                FilmstripVerticalPanGesture(
                    direction: .up,
                    isEnabled: expandedGroup != nil,
                    onDragChanged: { isTracking in
                        isTrackingVerticalGroupDrag = isTracking
                        lastVerticalGroupDragDate = Date()
                    },
                    onTrigger: {
                        guard expandedGroup != nil else { return }
                        collapseGroup()
                    }
                )
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

    private var gridPickerPresentationMode: GroupPhotoGridPickerPresentationMode {
        GroupPhotoGridPickerPresentationMode.resolved(horizontalSizeClass: horizontalSizeClass)
    }

    private var gridPickerDismissTrigger: FilmstripGridPickerDismissTrigger {
        FilmstripGridPickerDismissTrigger(
            expandedGroupID: expandedGroup?.id,
            showsGridPicker: activeShowsGridPicker,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            usesVerticalToolbar: usesVerticalToolbar,
            hasFoldRegion: hasFoldRegion,
            externalToken: gridPickerDismissToken)
    }

    private func groupActionButtonLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.clove.text.primary)
            .frame(width: metrics.groupActionButtonSize, height: metrics.groupActionButtonSize)
            .contentShape(Circle())
            .cloveGlass(in: Circle())
    }

    private func gridPickerButton(for group: ActiveBrowsingGroup) -> some View {
        Button {
            guard let expandedGroup,
                !isTrackingVerticalGroupDrag,
                Date().timeIntervalSince(lastVerticalGroupDragDate) >= 0.25,
                showsGridPicker(for: expandedGroup),
                isGridPickerAnchorReady,
                scenePhase == .active
            else {
                return
            }
            tapPicker?.dismiss()
            presentedGridPickerMode = gridPickerPresentationMode
        } label: {
            groupActionButtonLabel(symbol: "square.grid.2x2")
        }
        .buttonStyle(.cloveGlassPress)
        .accessibilityLabel(AppLocalization.string("Show group photos", language: language))
        .accessibilityIdentifier("clove.detail.filmstrip.group.gridPicker")
        .reportTapPickerFrame("clove.detail.filmstrip.group.gridPicker")
        .popover(
            isPresented: Binding(
                get: {
                    presentedGridPickerMode == .popover
                        && expandedGroup != nil
                        && activeShowsGridPicker
                        && isGridPickerAnchorReady
                        && scenePhase == .active
                },
                set: {
                    if !$0, presentedGridPickerMode == .popover {
                        presentedGridPickerMode = nil
                    }
                }),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            gridPickerContent(for: expandedGroup ?? group, showsDoneButton: false)
        }
        .onChange(of: tapPickerTriggerRequest) { _, request in
            if request?.id == "clove.detail.filmstrip.group.gridPicker",
                let expandedGroup,
                showsGridPicker(for: expandedGroup),
                isGridPickerAnchorReady,
                scenePhase == .active
            {
                tapPicker?.dismiss()
                presentedGridPickerMode = gridPickerPresentationMode
            }
        }
        .onChange(of: gridPickerPresentTrigger) { _, _ in
            if let expandedGroup,
                showsGridPicker(for: expandedGroup),
                isGridPickerAnchorReady,
                scenePhase == .active
            {
                tapPicker?.dismiss()
                presentedGridPickerMode = gridPickerPresentationMode
            }
        }
        .onAppear {
            isGridPickerAnchorReady = true
        }
        .onDisappear {
            isGridPickerAnchorReady = false
            presentedGridPickerMode = nil
        }
    }

    private func gridPickerContent(
        for group: ActiveBrowsingGroup,
        showsDoneButton: Bool
    ) -> some View {
        GroupPhotoGridPicker(
            group: group,
            current: current,
            thumbnails: thumbnails,
            showsDoneButton: showsDoneButton
        ) { chosen in
            guard expandedGroup != nil else { return }
            presentedGridPickerMode = nil
            selectGroupPhoto(chosen)
        }
        .environment(\.cloveTheme, theme)
        .environment(\.appLanguage, language)
        .environment(\.locale, language.locale)
    }

    private var collapseButton: some View {
        Button {
            guard expandedGroup != nil else { return }
            collapseGroup()
        } label: {
            groupActionButtonLabel(symbol: "chevron.up")
        }
        .buttonStyle(.cloveGlassPress)
        .accessibilityLabel(AppLocalization.string("Collapse group", language: language))
        .accessibilityIdentifier("clove.detail.filmstrip.group.fold")
        .reportTapPickerFrame("clove.detail.filmstrip.group.fold")
    }

    // MARK: - Level Transition Choreography

    private var effectiveReduceMotion: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private func handleLevelTransition(from oldID: GroupID?, to newID: GroupID?) {
        levelTransitionTask?.cancel()
        exitingGroupTask?.cancel()

        if newID != nil {
            isTrackingVerticalStackDrag = false
            isUserDraggingGroup = false
        } else {
            isTrackingVerticalGroupDrag = false
            isUserDraggingGroup = false
        }

        if oldID == nil, newID != nil {
            // Expand: Timeline -> Group Focus (上 → 下 roll + fan-out)
            exitingGroup = nil
            let isOverflowing = expandedGroup.map(showsGridPicker(for:)) ?? false
            let compressedSpacing =
                isOverflowing ? Self.groupRestingSpacing : Self.groupCompressedSpacing
            if effectiveReduceMotion {
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
                groupMemberSpacing = compressedSpacing
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
            let isOverflowing = lastActiveGroup.map(showsGridPicker(for:)) ?? false
            let collapsedSpacing =
                isOverflowing ? Self.groupRestingSpacing : Self.groupCompressedSpacing
            UISelectionFeedbackGenerator().selectionChanged()
            if effectiveReduceMotion {
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
                        groupMemberSpacing = collapsedSpacing
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
            FilmstripRaisedTile(
                width: metrics.thumbnailWidth,
                baseHeight: metrics.stackHeight,
                isCurrent: holdsCurrent
            ) {
                FilmstripGroupStack(
                    cover: active.representative,
                    peekingIDs: peekingIDs,
                    isDimmed: isDimmed,
                    visibleCount: active.visibleMembers.count,
                    thumbnailWidth: metrics.thumbnailWidth,
                    thumbnailHeight: metrics.thumbnailHeight,
                    peek: metrics.groupStackPeek,
                    thumbnails: thumbnails
                )
            }
        }
        .buttonStyle(.plain)
        .gesture(
            FilmstripVerticalPanGesture(
                direction: .down,
                isEnabled: expandedGroup == nil,
                onDragChanged: { isTracking in
                    isTrackingVerticalStackDrag = isTracking
                    lastVerticalStackDragDate = Date()
                },
                onTrigger: {
                    guard expandedGroup == nil else { return }
                    expandGroup(active.id)
                }
            )
        )
        .id(GridCellItem.ID.group(active.id))
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
        scaleX: CGFloat,
        suppressTap: @escaping () -> Bool,
        tap: @escaping () -> Void
    ) -> some View {
        let cellID = GridCellItem.ID.photo(photo.id)
        return Button {
            guard !suppressTap() else { return }
            tap()
        } label: {
            FilmstripRaisedTile(
                width: metrics.thumbnailWidth,
                baseHeight: metrics.thumbnailHeight,
                isCurrent: photo.id == current
            ) {
                DetailPhotoFrame(
                    photo: photo, isCurrent: photo.id == current, thumbnails: thumbnails,
                    side: metrics.thumbnailWidth, height: metrics.thumbnailHeight
                )
            }
            .scaleEffect(x: scaleX, y: 1, anchor: .center)
        }
        .buttonStyle(.plain)
        .id(cellID)
        .accessibilityAddTraits(photo.id == current ? [.isSelected] : [])
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
        for photo: PhotoIdentity?, using proxy: ScrollViewProxy, animated: Bool
    ) {
        pendingTimelineScroll?.cancel()
        guard let photo else { return }
        pendingTimelineScroll = makeScrollTask(
            to: timelineScrollTarget(for: photo), using: proxy, animated: animated)
    }

    private func scheduleGroupScroll(
        for photo: PhotoIdentity?, using proxy: ScrollViewProxy, animated: Bool
    ) {
        pendingGroupScroll?.cancel()
        guard let photo else { return }
        pendingGroupScroll = makeScrollTask(
            to: GridCellItem.ID.photo(photo), using: proxy, animated: animated)
    }

    private func makeScrollTask(
        to target: GridCellItem.ID,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(animated ? CloveMotion.chrome(reduceMotion: effectiveReduceMotion) : nil)
            {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }
}

private struct TimelineScrollTrigger: Equatable {
    let current: PhotoIdentity?
    let expandedGroupID: GroupID?
    let slotCount: Int
    let currentSlotIndex: Int?
    let metrics: DetailFilmstrip.Metrics
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let viewportWidth: Int
}

private struct GroupScrollTrigger: Equatable {
    let current: PhotoIdentity?
    let expandedGroupID: GroupID?
    let memberCount: Int
    let currentMemberIndex: Int?
    let metrics: DetailFilmstrip.Metrics
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let showsGridPicker: Bool
    let trackWidth: Int
}

private struct FilmstripGroupStack: View {
    let cover: GridPhoto
    let peekingIDs: [PhotoIdentity]
    let isDimmed: Bool
    let visibleCount: Int
    let thumbnailWidth: CGFloat
    let thumbnailHeight: CGFloat
    let peek: CGFloat
    let thumbnails: any GridThumbnailSource
    @State private var peekingThumbnails: [PhotoIdentity: CGImage] = [:]

    var body: some View {
        GroupStack(
            peek: peek,
            peekingImages: peekingIDs.map { peekingThumbnails[$0] },
            cardBacking: Color.clove.bg.stage,
            isDimmed: isDimmed
        ) {
            DetailPhotoFrame(
                photo: cover, isCurrent: false, thumbnails: thumbnails,
                side: thumbnailWidth, height: thumbnailHeight,
                showsMarks: true, appliesRejectedDimming: false)
        }
        .overlay(alignment: .topTrailing) {
            GroupCountBadge(count: visibleCount, presentation: .filmstrip)
                .padding(2)
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

private struct FilmstripGridPickerDismissTrigger: Equatable {
    let expandedGroupID: GroupID?
    let showsGridPicker: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let usesVerticalToolbar: Bool
    let hasFoldRegion: Bool
    let externalToken: Int
}
