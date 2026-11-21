import CloveCore
import CloveImaging
import CoreGraphics
import SwiftUI

/// Side-by-side dual-photo comparison workspace supporting both scope stepping and fixed-pair inspection.
struct CompareView: View {
    let browsing: BrowsingModel
    let session: CompareSession
    let settings: AppSettings
    let images: any DetailImageSource
    let displayMode: PhotoDisplayMode
    var duo: DuoDetailLayout? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @Environment(\.cloveTheme) private var theme

    @State private var containerSize: CGSize = .zero
    @State private var verticalFoldRange: ClosedRange<CGFloat>?
    @State private var tapPickerDismissToken = 0
    @State private var pendingExitForUnsupportedLayout = false

    @State private var paneA = ComparePaneController(side: .reference)
    @State private var paneB = ComparePaneController(side: .challenger)

    @FocusState private var hasKeyFocus: Bool

    private var layoutPolicy: CompareLayoutPolicy {
        CompareLayoutPolicy(
            availableWidth: Double(containerSize.width),
            availableHeight: Double(containerSize.height),
            isRegularWidth: horizontalSizeClass == .regular,
            isCompactHeight: verticalSizeClass == .compact,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover)
    }

    private var activePhoto: GridPhoto? {
        browsing.placedPhoto(for: session.activePhoto)
    }

    private var scopePhotos: [GridPhoto] {
        session.scope.compactMap { browsing.placedPhoto(for: $0) }
    }

    private var paneControlSize: ControlSize {
        isDuoExpanded ? .duo : (horizontalSizeClass == .regular ? .pad : .phone)
    }

    var body: some View {
        let content =
            compareBody
            .background(Rectangle().fill(Color.clove.bg.stage).ignoresSafeArea())
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyFocus)
            .onKeyPress { press in
                handleKeyPress(press)
            }
            .onAppear {
                hasKeyFocus = true
            }
            .task {
                await images.setCompareRetention(active: true, keeping: session.activePhoto)
            }
            .onDisappear {
                let kept = browsing.compareSession?.activePhoto ?? session.activePhoto
                paneA.cancelTasks()
                paneB.cancelTasks()
                Task { await images.setCompareRetention(active: false, keeping: kept) }
            }
            .onChange(of: containerSize) { _, newSize in
                checkSupportedLayout(for: newSize)
            }
            .onChange(of: isDuoCover) { _, _ in
                checkSupportedLayout(for: containerSize)
            }
            .onChange(of: isDuoExpanded) { _, _ in
                checkSupportedLayout(for: containerSize)
            }
            .onChange(of: session.reference) { oldPhoto, newPhoto in
                if oldPhoto != newPhoto && oldPhoto != session.challenger {
                    Task { await images.releaseComparePhoto(oldPhoto) }
                }
            }
            .onChange(of: session.challenger) { oldPhoto, newPhoto in
                if oldPhoto != newPhoto && oldPhoto != session.reference {
                    Task { await images.releaseComparePhoto(oldPhoto) }
                }
            }
            .onChange(of: session.isSyncLocked) { _, isLocked in
                if isLocked {
                    syncInactivePaneToActive()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clove.compare")
            .navigationBarBackButtonHidden(true)

        if #available(iOS 27.1, *), usesVerticalToolbar {
            content.contentMargins(for: .container, edges: .horizontal)
        } else {
            content.toolbar(.hidden, for: .navigationBar)
        }
    }

    private var compareBody: some View {
        VStack(spacing: 8) {
            topBar
            if let message = browsing.failureToastMessage {
                Toast(
                    message: AppLocalization.string(message, language: language),
                    identifier: "clove.compare.save.toast"
                )
                .padding(.horizontal, 16)
            }
            FolderSaveBanner(
                browsing: browsing,
                identifierPrefix: "clove.compare.saveStatus.failure"
            )
            .padding(.horizontal, 12)
            splitPanes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomReviewBar
        }
        .padding(.top, verticalSizeClass == .compact ? 6 : 8)
        .padding(.bottom, verticalSizeClass == .compact ? 6 : 10)
        .onGeometryChange(for: CompareGeometrySnapshot.self) { proxy in
            let size = proxy.size
            let verticalFold = Self.verticalDivisionRange(
                in: proxy, containerWidth: size.width)
            return CompareGeometrySnapshot(size: size, verticalFold: verticalFold)
        } action: { snapshot in
            containerSize = snapshot.size
            verticalFoldRange = snapshot.verticalFold
        }
        .tapPickerContainer(dismissWhen: tapPickerDismissToken)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            Text(AppLocalization.string("Compare", language: language))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.clove.text.primary)
                .lineLimit(1)
                .accessibilityIdentifier("clove.compare.title")

            HStack(spacing: 12) {
                Button {
                    tapPickerDismissToken += 1
                    browsing.exitCompare()
                } label: {
                    Text(AppLocalization.string("Done", language: language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.clove.text.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Capsule())
                        .cloveGlass(in: Capsule())
                }
                .frame(minHeight: 40)
                .buttonStyle(.cloveGlassPress)
                .accessibilityIdentifier("clove.compare.done")

                Spacer(minLength: 16)

                Button {
                    tapPickerDismissToken += 1
                    browsing.toggleCompareSyncLock()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: session.isSyncLocked ? "lock.fill" : "lock.open")
                            .imageScale(.small)
                        Text(
                            AppLocalization.string(
                                session.isSyncLocked ? "Sync On" : "Sync Off",
                                language: language)
                        )
                        .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        session.isSyncLocked
                            ? Color.white : theme.tokens.primaryText.color
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        if session.isSyncLocked {
                            Capsule().fill(Color.clove.accent)
                        }
                    }
                    .contentShape(Capsule())
                    .cloveGlass(in: Capsule())
                }
                .frame(minHeight: 40)
                .buttonStyle(.cloveGlassPress)
                .accessibilityLabel(
                    AppLocalization.string(
                        session.isSyncLocked ? "Sync On" : "Sync Off",
                        language: language)
                )
                .accessibilityValue(
                    AppLocalization.string(session.isSyncLocked ? "On" : "Off", language: language)
                )
                .accessibilityIdentifier("clove.compare.syncToggle")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    // MARK: - Side-by-Side Split Panes

    private var splitPanes: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = verticalFoldRange == nil ? 12 : 8
            let innerWidth = max(0, proxy.size.width - horizontalInset * 2)
            let localFoldMinX = verticalFoldRange.map { $0.lowerBound - horizontalInset }
            let localFoldMaxX = verticalFoldRange.map { $0.upperBound - horizontalInset }
            let split = CompareSplitGeometry.layout(
                containerWidth: Double(innerWidth),
                verticalFoldMinX: localFoldMinX.map(Double.init),
                verticalFoldMaxX: localFoldMaxX.map(Double.init))

            HStack(spacing: CGFloat(split.dividerWidth)) {
                paneView(
                    side: .reference, photoID: session.reference, controller: paneA, peer: paneB
                )
                .frame(width: max(0, CGFloat(split.referenceWidth)), height: proxy.size.height)

                paneView(
                    side: .challenger, photoID: session.challenger, controller: paneB, peer: paneA
                )
                .frame(width: max(0, CGFloat(split.challengerWidth)), height: proxy.size.height)
            }
            .padding(.horizontal, horizontalInset)
        }
    }

    @ViewBuilder
    private func paneView(
        side: CompareSide,
        photoID: PhotoIdentity,
        controller: ComparePaneController,
        peer: ComparePaneController
    ) -> some View {
        let photo = browsing.placedPhoto(for: photoID)
        let isActive = session.activeSide == side

        ComparePaneView(
            side: side,
            badgeTitle: side == .reference ? "A" : "B",
            photoID: photoID,
            photo: photo,
            marks: browsing.shownMarks(for: photoID),
            isActive: isActive,
            controller: controller,
            images: images,
            thumbnails: browsing.thumbnails,
            displayMode: displayMode,
            settings: settings,
            showsFocusRegions: browsing.showsFocusRegions,
            language: language,
            identifierPrefix: side == .reference ? "clove.compare.paneA" : "clove.compare.paneB",
            onSelectPane: {
                tapPickerDismissToken += 1
                browsing.selectCompareSide(side)
            },
            onViewportChanged: { snapshot in
                guard session.isSyncLocked, let snapshot else { return }
                sync(from: controller, to: peer, snapshot: snapshot)
            },
            onInitialPixelsReady: {
                guard session.isSyncLocked, side == .challenger else { return }
                if peer.scale > DetailFitScale.tolerance,
                    let snapshot = peer.probe.container?.zoomSnapshot
                {
                    sync(from: peer, to: controller, snapshot: snapshot)
                } else {
                    controller.probe.container?.applySyncedViewport(scale: 1, anchor: .centre)
                }
            }
        )
    }

    // MARK: - Bottom Review Bar

    private var bottomReviewBar: some View {
        HStack(spacing: 10) {
            if session.mode == .stepping {
                if layoutPolicy.showsFilmstrip {
                    CompareFilmstrip(
                        photos: scopePhotos,
                        reference: session.reference,
                        challenger: session.challenger,
                        activeSide: session.activeSide,
                        thumbnails: browsing.thumbnails,
                        onSelectCandidate: { candidate in
                            tapPickerDismissToken += 1
                            browsing.selectCompareChallenger(candidate)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    steppingControls
                        .layoutPriority(1)
                } else {
                    steppingControls
                    Spacer(minLength: 8)
                }
            } else {
                Spacer(minLength: 8)
            }

            reviewActionCluster
                .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .frame(height: layoutPolicy.showsFilmstrip ? 58 : 50)
    }

    private var steppingControls: some View {
        HStack(spacing: 6) {
            GlassIconButton(
                label: AppLocalization.string("Previous candidate", language: language),
                symbol: "chevron.left",
                size: paneControlSize,
                identifier: "clove.compare.prev"
            ) {
                tapPickerDismissToken += 1
                browsing.stepCompareChallenger(offset: -1)
            }
            .disabled(!session.canStepPreviousChallenger)
            .opacity(session.canStepPreviousChallenger ? 1 : 0.45)

            GlassIconButton(
                label: AppLocalization.string("Next candidate", language: language),
                symbol: "chevron.right",
                size: paneControlSize,
                identifier: "clove.compare.next"
            ) {
                tapPickerDismissToken += 1
                browsing.stepCompareChallenger(offset: 1)
            }
            .disabled(!session.canStepNextChallenger)
            .opacity(session.canStepNextChallenger ? 1 : 0.45)

            Button {
                tapPickerDismissToken += 1
                browsing.promoteCompareChallengerToReference()
            } label: {
                Text(AppLocalization.string("Set as A", language: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.clove.text.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                    .cloveGlass(in: Capsule())
            }
            .frame(minHeight: 40)
            .buttonStyle(.cloveGlassPress)
            .disabled(!session.canPromoteChallenger)
            .accessibilityIdentifier("clove.compare.setAsA")
        }
    }

    private var reviewActionCluster: some View {
        let targetPhoto = session.activePhoto
        let marks = browsing.shownMarks(for: targetPhoto)

        return HStack(spacing: 8) {
            GlassIconButton(
                label: AppLocalization.string("Undo", language: language),
                symbol: "arrow.uturn.backward",
                size: paneControlSize,
                identifier: "clove.compare.undo"
            ) {
                tapPickerDismissToken += 1
                browsing.undoCompareMark()
            }
            .disabled(!browsing.canUndoCompareMark)
            .opacity(browsing.canUndoCompareMark ? 1 : 0.45)

            activeSideBadge

            MarkingToolbar(
                rating: marks.isRejected ? .unrated : marks.rating,
                label: marks.isRejected ? nil : marks.label.colour,
                isRejected: marks.isRejected,
                enabledRatings: settings.enabledRatings,
                labels: [nil] + settings.availableLabels.map { Optional($0) },
                identifier: "clove.compare.capsule",
                photoID: targetPhoto,
                onRate: { rateActive($0) },
                onReject: { toggleRejectActive() },
                onLabel: { chooseActiveLabel($0) },
                onBegin: {}
            )
            .disabled(!browsing.canMark)
            .opacity(browsing.canMark ? 1 : 0.45)
        }
    }

    private var activeSideBadge: some View {
        let sideLetter = session.activeSide == .reference ? "A" : "B"
        let accessibleSide = AppLocalization.string(
            session.activeSide == .reference ? "Reference photo A" : "Challenger photo B",
            language: language)

        return Text(sideLetter)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(Color.clove.accent, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibleSide)
            .accessibilityValue(sideLetter)
            .accessibilityIdentifier("clove.compare.activeSideBadge")
    }

    // MARK: - Marking & Keyboard Handling

    private var markingRules: MarkingInputRules {
        var inputSettings = settings
        inputSettings.gesturesEnabled = settings.gesturesEnabled && browsing.canMark
        return MarkingInputRules(settings: inputSettings)
    }

    private func rateActive(_ rating: Rating) {
        let target = session.activePhoto
        applyMarkingResult(
            markingRules.result(
                forRating: rating, marks: browsing.shownMarks(for: target),
                allowsMarking: browsing.canMark),
            to: target)
    }

    private func toggleRejectActive() {
        let target = session.activePhoto
        applyMarkingResult(
            markingRules.result(
                forRejectToggle: browsing.shownMarks(for: target),
                allowsMarking: browsing.canMark),
            to: target)
    }

    private func chooseActiveLabel(_ label: LabelColour?) {
        let target = session.activePhoto
        let resolvedLabel = label.map { ColourLabel(colour: $0) } ?? .clear
        applyMarkingResult(
            markingRules.result(
                forLabel: resolvedLabel,
                marks: browsing.shownMarks(for: target),
                allowsMarking: browsing.canMark),
            to: target)
    }

    private func applyMarkingResult(_ result: MarkingResult, to target: PhotoIdentity) {
        if case .mark(let change, _) = result {
            browsing.apply(change, to: target)
        }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            tapPickerDismissToken += 1
            browsing.exitCompare()
            return .handled
        }
        guard let key = MarkingKey(press) else { return .ignored }
        switch key {
        case .previousPhoto:
            guard session.mode == .stepping else { return .handled }
            tapPickerDismissToken += 1
            browsing.stepCompareChallenger(offset: -1)
            return .handled
        case .nextPhoto:
            guard session.mode == .stepping else { return .handled }
            tapPickerDismissToken += 1
            browsing.stepCompareChallenger(offset: 1)
            return .handled
        case .undo:
            tapPickerDismissToken += 1
            browsing.undoCompareMark()
            return .handled
        case .rating, .colourLabel, .nextRating, .reject:
            tapPickerDismissToken += 1
            let target = session.activePhoto
            applyMarkingResult(
                markingRules.result(
                    for: key, marks: browsing.shownMarks(for: target),
                    allowsMarking: browsing.canMark),
                to: target)
            return .handled
        case .toggleGroupFocus, .collapseGroup:
            return .ignored
        }
    }

    // MARK: - Sync & Layout Helpers

    private func sync(
        from source: ComparePaneController,
        to target: ComparePaneController,
        snapshot: DetailZoomSnapshot
    ) {
        let converted: CGFloat
        if snapshot.scale <= DetailFitScale.tolerance {
            converted = 1
        } else if let sourceNative = source.nativeFullResolutionScale,
            let targetNative = target.nativeFullResolutionScale
        {
            converted = DetailZoom.convertedScale(
                snapshot.scale, fromNativeScale: sourceNative, toNativeScale: targetNative)
        } else {
            converted = snapshot.scale
        }
        target.probe.container?.applySyncedViewport(scale: converted, anchor: snapshot.anchor)
    }

    private func syncInactivePaneToActive() {
        let (source, target) =
            session.activeSide == .reference ? (paneA, paneB) : (paneB, paneA)
        let snapshot =
            source.probe.container?.zoomSnapshot ?? DetailZoomSnapshot(scale: 1, anchor: .centre)
        sync(from: source, to: target, snapshot: snapshot)
    }

    private func checkSupportedLayout(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let policy = CompareLayoutPolicy(
            availableWidth: Double(size.width),
            availableHeight: Double(size.height),
            isRegularWidth: horizontalSizeClass == .regular,
            isCompactHeight: verticalSizeClass == .compact,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover)
        if !policy.supportsCompare && !pendingExitForUnsupportedLayout {
            pendingExitForUnsupportedLayout = true
            browsing.exitCompare()
        }
    }

    private nonisolated static func verticalDivisionRange(
        in proxy: GeometryProxy, containerWidth: CGFloat
    ) -> ClosedRange<CGFloat>? {
        if #available(iOS 27.1, *) {
            let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
            for fold in folds {
                let rect = fold.frame
                if rect.height > rect.width && rect.minX > 0 && rect.maxX < containerWidth {
                    return rect.minX...rect.maxX
                }
            }
        }
        return nil
    }
}

private struct CompareGeometrySnapshot: Equatable {
    let size: CGSize
    let verticalFold: ClosedRange<CGFloat>?
}

// MARK: - Per-Pane State & Controller

@MainActor
@Observable
private final class ComparePaneController {
    let side: CompareSide
    let consumer = UUID()
    let probe = DetailZoomProbe()

    enum Phase: Equatable {
        case placeholder(CGImage?)
        case shown
        case unavailable(DetailFailure)
        case deferred
    }

    enum ZoomMode: Equatable {
        case fit
        case fullResolution(anchor: DetailZoomAnchor, size: CGSize?)
    }

    var shown: DetailImage?
    var phase: Phase = .placeholder(nil)
    var limitation: DetailLimitation?
    var previewOnly = false
    var scale: CGFloat = 1
    var viewSize: CGSize = .zero
    var displayScale: CGFloat = 2
    var command: DetailZoomCommand?
    var commandCounter = 0
    var zoomMode: ZoomMode = .fit
    var focusRegionState = DetailFocusRegionState()
    var inspectedFocusRegionID: String?
    var focusAnalysisID = UUID()
    var upgradeTask: Task<Void, Never>?
    var zoomReportTask: Task<Void, Never>?
    var screenPixels: Int = 2400

    init(side: CompareSide) {
        self.side = side
    }

    func cancelTasks() {
        upgradeTask?.cancel()
        upgradeTask = nil
        zoomReportTask?.cancel()
        zoomReportTask = nil
    }

    var pixelSizeOfShown: CGSize {
        guard let shown else { return .zero }
        return CGSize(width: CGFloat(shown.width), height: CGFloat(shown.height))
    }

    var nativeFullResolutionScale: CGFloat? {
        guard viewSize.width > 0, viewSize.height > 0, let shown else { return nil }
        let pixels = shown.fullResolutionPixels ?? pixelSizeOfShown
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        return DetailZoom.fullResolutionTarget(
            nativePixels: pixels, shownPixels: pixels, viewSize: viewSize,
            screenScale: displayScale)
    }

    var isAtFullResolution: Bool {
        guard let shown, viewSize.width > 0, let pixels = shown.fullResolutionPixels else {
            return scale > DetailFitScale.tolerance
        }
        let target = DetailZoom.fullResolutionScale(
            nativePixels: pixels, shownPixels: pixels, viewSize: viewSize,
            screenScale: displayScale)
        return scale >= target * 0.995
    }

    func zoomLabel(language: ResolvedAppLanguage) -> String {
        if scale <= DetailFitScale.tolerance {
            return AppLocalization.string("Fit", language: language)
        }
        if let shown, viewSize.width > 0, let pixels = shown.fullResolutionPixels,
            DetailZoom.isFullResolution(
                scale: scale, nativePixels: pixels, viewSize: viewSize,
                screenScale: displayScale)
        {
            return AppLocalization.format("%lld%%", language: language, Int64(100))
        }
        return AppLocalization.format(
            "%lld%%", language: language, Int64((scale * 100).rounded()))
    }

    func requestPixels(scale: CGFloat) -> Int {
        let longest = max(viewSize.width, viewSize.height)
        return max(Int(ceil(longest * displayScale * max(1, scale))), 1)
    }

    func issueZoom(_ kind: DetailZoomCommand.Kind) {
        commandCounter &+= 1
        command = DetailZoomCommand(id: commandCounter, kind: kind)
        switch kind {
        case .fit:
            scale = 1
        case .scale(let target, _):
            scale = target
        }
    }
}

// MARK: - Single Compare Pane View

private struct ComparePaneView: View {
    let side: CompareSide
    let badgeTitle: String
    let photoID: PhotoIdentity
    let photo: GridPhoto?
    let marks: PhotoMarks
    let isActive: Bool
    let controller: ComparePaneController
    let images: any DetailImageSource
    let thumbnails: any GridThumbnailSource
    let displayMode: PhotoDisplayMode
    let settings: AppSettings
    let showsFocusRegions: Bool
    let language: ResolvedAppLanguage
    let identifierPrefix: String
    let onSelectPane: () -> Void
    let onViewportChanged: (DetailZoomSnapshot?) -> Void
    let onInitialPixelsReady: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.cloveTheme) private var theme

    private let paneRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
                .background(Color.clove.separator.opacity(0.6))
            paneStage
        }
        .background(Color.clove.bg.stage)
        .clipShape(RoundedRectangle(cornerRadius: paneRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: paneRadius, style: .continuous)
                .strokeBorder(
                    isActive ? Color.clove.accent : Color.clove.separator,
                    lineWidth: isActive ? 2 : 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifierPrefix)
        .onChange(of: photoID) { _, _ in
            controller.cancelTasks()
            controller.inspectedFocusRegionID = nil
            controller.focusAnalysisID = UUID()
            controller.focusRegionState = DetailFocusRegionState()
            controller.zoomMode = .fit
            controller.issueZoom(.fit)
        }
        .task(id: photoID) {
            await loadPixels(for: photoID)
        }
        .task(id: CompareFocusTrigger(photo: photoID, showsFocusRegions: showsFocusRegions)) {
            await loadFocusRegions(for: photoID)
        }
    }

    private var paneHeader: some View {
        let parts = DetailHeaderFileNameParts(photo?.fileName ?? photoID.stem)
        return HStack(spacing: 8) {
            Text(badgeTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? Color.white : theme.tokens.secondaryText.color)
                .frame(minWidth: 22, minHeight: 20)
                .padding(.horizontal, 4)
                .background(
                    isActive
                        ? theme.tokens.accent.color
                        : theme.tokens.separator.color.opacity(0.45),
                    in: Capsule()
                )
                .accessibilityIdentifier("\(identifierPrefix).badge")

            HStack(spacing: 0) {
                Text(parts.stem)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)
                if !parts.extensionSuffix.isEmpty {
                    Text(parts.extensionSuffix)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .accessibilityIdentifier("\(identifierPrefix).fileName.extension")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.clove.text.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo?.fileName ?? photoID.stem)
            .accessibilityIdentifier("\(identifierPrefix).fileName")

            Spacer(minLength: 8)

            Text(controller.zoomLabel(language: language))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.clove.text.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("\(identifierPrefix).zoom")

            ComparePaneMarksSummary(
                marks: marks,
                language: language,
                identifier: "\(identifierPrefix).marks"
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPane()
        }
        .accessibilityIdentifier("\(identifierPrefix).header")
    }

    @ViewBuilder
    private var paneStage: some View {
        let shownPixels: CGImage? =
            switch controller.phase {
            case .placeholder(let preview): preview
            case .shown: controller.shown?.image
            case .unavailable, .deferred: nil
            }

        let focusOverlayRegions = controller.focusRegionState.regions(
            visible: controller.shown != nil && showsFocusRegions,
            inspectedRegionID: controller.inspectedFocusRegionID)

        ZStack {
            DetailZoomView(
                image: shownPixels,
                fullResolutionPixels: controller.shown?.fullResolutionPixels,
                command: controller.command,
                doubleTapZoomEnabled: settings.doubleTap != .off,
                rules: MarkingInputRules(settings: settings),
                currentRating: marks.rating,
                feedback: DetailSwipeFeedback(),
                onZoomChange: { newScale in
                    handleZoomScaleChange(newScale)
                },
                isCompareMode: true,
                onViewportChanged: { snapshot in
                    if let snapshot {
                        handleZoomScaleChange(snapshot.scale)
                    }
                    onViewportChanged(snapshot)
                },
                onSyncedScaleApplied: { syncedScale in
                    handleZoomScaleChange(syncedScale)
                },
                onChromeToggle: {
                    onSelectPane()
                },
                onStep: { _ in },
                onDoubleTap: { tap in
                    handleDoubleTap(at: tap)
                },
                onMarkingSwipe: { _ in },
                onSwipeBegin: {},
                allowsMarking: false,
                hasPrevious: false,
                hasNext: false,
                probe: controller.probe,
                focusRegions: focusOverlayRegions,
                inspectedFocusRegionID: controller.inspectedFocusRegionID,
                focusRegionColours: DetailFocusRegionColours(
                    normal: UIColor(theme.tokens.focusOutline.color),
                    contrastEdge: UIColor(theme.tokens.focusEdge.color),
                    selected: UIColor(theme.tokens.accent.color),
                    unavailable: UIColor(theme.tokens.focusOutline.color.opacity(0.58))
                ),
                onFocusRegionTap: { region in
                    onSelectPane()
                    handleFocusRegionTap(region)
                },
                previewAccessibilityLabel: AppLocalization.format(
                    side == .reference ? "Reference photo %@" : "Challenger photo %@",
                    language: language,
                    photo?.fileName ?? photoID.stem
                )
            )
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { newSize in
                controller.viewSize = newSize
                controller.displayScale = displayScale
                if let screen = controller.probe.container?.window?.windowScene?.screen {
                    controller.screenPixels = Int(
                        max(screen.nativeBounds.width, screen.nativeBounds.height))
                } else if newSize != .zero {
                    controller.screenPixels = max(
                        1200, Int(ceil(max(newSize.width, newSize.height) * displayScale)))
                }
            }

            if case .unavailable(let failure) = controller.phase {
                Text(unavailableText(failure))
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .accessibilityIdentifier("\(identifierPrefix).unavailable")
            }

            if let limitation = controller.limitation, controller.shown != nil {
                VStack {
                    HStack {
                        Text(limitationText(limitation))
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("\(identifierPrefix).limitation")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pane Loading & Upgrades

    private func loadPixels(for targetID: PhotoIdentity) async {
        controller.cancelTasks()
        controller.limitation = nil
        controller.previewOnly = false
        controller.shown = nil

        let previewRequest = DetailPixelRequest(
            displayPixels: controller.screenPixels,
            need: .preview,
            mode: displayMode,
            screenPixels: controller.screenPixels
        )

        var presentedWarm = false
        if let warm = images.warmImage(for: targetID, request: previewRequest) {
            show(warm, for: targetID)
            presentedWarm = true
            onInitialPixelsReady()
        } else {
            controller.phase = .placeholder(nil)
            let thumb = await images.placeholder(for: targetID, gridThumbnails: thumbnails)
            guard !Task.isCancelled else { return }
            controller.phase = .placeholder(thumb)
        }

        if let screen = controller.probe.container?.window?.windowScene?.screen {
            controller.screenPixels = Int(
                max(screen.nativeBounds.width, screen.nativeBounds.height))
        }

        let screenReq = DetailPixelRequest(
            displayPixels: controller.screenPixels,
            need: .preview,
            mode: displayMode,
            screenPixels: controller.screenPixels
        )
        var attempts = 0
        while true {
            let outcome = await images.image(
                for: targetID, request: screenReq, consumer: controller.consumer)
            if Task.isCancelled { return }
            switch outcome {
            case .image(let image):
                if !presentedWarm
                    || image.image !== controller.shown?.image
                    || image.quality != controller.shown?.quality
                    || image.source != controller.shown?.source
                    || image.fullResolutionSize != controller.shown?.fullResolutionSize
                {
                    show(image, for: targetID)
                    onInitialPixelsReady()
                }
                await upgradeScreenRAWIfNeeded(for: targetID, screenPixels: controller.screenPixels)
                return
            case .unavailable(let failure):
                controller.phase = .unavailable(failure)
                return
            case .deferred:
                attempts += 1
                guard attempts < 3 else {
                    if !presentedWarm { controller.phase = .deferred }
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func upgradeScreenRAWIfNeeded(for targetID: PhotoIdentity, screenPixels: Int) async {
        guard !Task.isCancelled, controller.shown?.isBestAvailable != true else { return }
        let request = DetailPixelRequest(
            displayPixels: screenPixels,
            need: .screenRender,
            mode: displayMode,
            screenPixels: screenPixels
        )
        let outcome = await images.image(
            for: targetID, request: request, consumer: controller.consumer)
        guard !Task.isCancelled else { return }
        if case .image(let image) = outcome, controller.shown?.isBestAvailable != true {
            show(image, for: targetID)
        }
        upgradeIfNeeded(for: targetID)
    }

    private func show(_ image: DetailImage, for targetID: PhotoIdentity) {
        controller.shown = image
        controller.limitation = image.limitation
        controller.phase = .shown
        if image.limitation != nil {
            controller.previewOnly = true
        }
        if case .fullResolution(let chosen, let targetSize) = controller.zoomMode,
            controller.viewSize.width > 0
        {
            if let pixels = image.fullResolutionPixels,
                let target = DetailZoom.retargetedFullResolutionScale(
                    from: targetSize,
                    to: pixels,
                    viewSize: controller.viewSize,
                    screenScale: controller.displayScale)
            {
                controller.zoomMode = .fullResolution(anchor: chosen, size: pixels)
                let anchor = controller.probe.container?.zoomSnapshot?.anchor ?? chosen
                controller.issueZoom(.scale(target, anchor: anchor.unitPoint))
            } else if controller.previewOnly,
                let target = DetailZoom.fullResolutionTarget(
                    nativePixels: nil,
                    shownPixels: controller.pixelSizeOfShown,
                    viewSize: controller.viewSize,
                    screenScale: controller.displayScale,
                    previewIsAll: true)
            {
                controller.issueZoom(.scale(target, anchor: chosen.unitPoint))
            }
        }
    }

    private func handleZoomScaleChange(_ newScale: CGFloat) {
        controller.scale = newScale
        guard newScale > DetailFitScale.tolerance else {
            controller.inspectedFocusRegionID = nil
            controller.zoomMode = .fit
            controller.upgradeTask?.cancel()
            return
        }
        upgradeIfNeeded(for: photoID)
    }

    private func upgradeIfNeeded(for targetID: PhotoIdentity) {
        guard controller.scale > DetailFitScale.tolerance,
            !controller.previewOnly,
            let shown = controller.shown,
            controller.requestPixels(scale: controller.scale) > max(shown.width, shown.height)
        else { return }
        controller.upgradeTask?.cancel()
        controller.upgradeTask = Task {
            let need: DetailPixelRequest.Need =
                controller.isAtFullResolution ? .fullResolution : .morePixels
            let request = DetailPixelRequest(
                displayPixels: controller.requestPixels(scale: controller.scale),
                need: need,
                mode: displayMode,
                screenPixels: controller.screenPixels)
            let outcome = await images.image(
                for: targetID, request: request, consumer: controller.consumer)
            guard !Task.isCancelled, self.photoID == targetID else { return }
            if case .image(let image) = outcome {
                show(image, for: targetID)
            }
        }
    }

    private func handleDoubleTap(at tap: DetailDoubleTapLocation) {
        guard settings.doubleTap != .off else { return }
        guard controller.scale <= DetailFitScale.tolerance else {
            controller.inspectedFocusRegionID = nil
            controller.zoomMode = .fit
            controller.issueZoom(.fit)
            onViewportChanged(DetailZoomSnapshot(scale: 1, anchor: .centre))
            return
        }
        guard controller.shown != nil else { return }
        if settings.doubleTap == .zoomToFocus,
            let targetRegion = controller.focusRegionState.preferredDoubleTapRegion(
                at: tap.proximityAnchor,
                visible: showsFocusRegions,
                inspectedRegionID: controller.inspectedFocusRegionID)
        {
            controller.inspectedFocusRegionID = targetRegion.id
            inspectFullResolution(at: targetRegion.centre)
        } else {
            controller.inspectedFocusRegionID = nil
            inspectFullResolution(at: tap.zoomAnchor)
        }
    }

    private func handleFocusRegionTap(_ region: DetailFocusRegion) {
        guard region.isActionable else { return }
        controller.inspectedFocusRegionID = region.id
        inspectFullResolution(at: region.centre)
    }

    private func inspectFullResolution(at anchor: UnitPoint) {
        guard let shown = controller.shown else { return }
        let chosen = DetailZoomAnchor(x: anchor.x, y: anchor.y)
        controller.zoomMode = .fullResolution(anchor: chosen, size: shown.fullResolutionPixels)
        if let target = DetailZoom.fullResolutionTarget(
            nativePixels: shown.fullResolutionPixels,
            shownPixels: controller.pixelSizeOfShown,
            viewSize: controller.viewSize,
            screenScale: controller.displayScale,
            previewIsAll: controller.previewOnly)
        {
            controller.issueZoom(.scale(target, anchor: anchor))
            onViewportChanged(DetailZoomSnapshot(scale: target, anchor: chosen))
        }
        guard !controller.previewOnly else { return }
        controller.upgradeTask?.cancel()
        let currentPhoto = photoID
        let screenPixels = controller.screenPixels
        controller.upgradeTask = Task {
            let request = DetailPixelRequest(
                displayPixels: controller.requestPixels(scale: controller.scale),
                need: .fullResolution,
                mode: displayMode,
                screenPixels: screenPixels)
            let outcome = await images.image(
                for: currentPhoto, request: request, consumer: controller.consumer)
            guard !Task.isCancelled, self.photoID == currentPhoto else { return }
            if case .image(let image) = outcome {
                show(image, for: currentPhoto)
            }
        }
    }

    private func loadFocusRegions(for targetID: PhotoIdentity) async {
        let analysisID = UUID()
        controller.focusAnalysisID = analysisID
        guard showsFocusRegions else {
            controller.focusRegionState = DetailFocusRegionState()
            return
        }
        controller.focusRegionState.begin(for: targetID)
        guard let source = images as? DetailRegionSharpnessSource else {
            controller.focusRegionState.finish(nil, for: targetID)
            return
        }
        let analysis = await source.analyzeRegions(for: targetID, group: [], nearby: []) { result in
            Task { @MainActor in
                guard controller.focusAnalysisID == analysisID else { return }
                controller.focusRegionState.receiveAutofocus(result, for: targetID)
            }
        }
        guard !Task.isCancelled, controller.focusAnalysisID == analysisID else { return }
        controller.focusRegionState.finish(analysis, for: targetID)
    }

    private func unavailableText(_ failure: DetailFailure) -> String {
        switch failure {
        case .cannotOpen:
            AppLocalization.string("This file cannot be opened as an image.", language: language)
        case .noUsablePreview:
            AppLocalization.string("This file has no preview Clove can show.", language: language)
        case .sourceChanged:
            AppLocalization.string("The file changed while it was opening.", language: language)
        }
    }

    private func limitationText(_ limitation: DetailLimitation) -> String {
        switch limitation {
        case .rawRenderFailed:
            AppLocalization.string("Preview only — the RAW render failed.", language: language)
        case .noHigherResolution:
            AppLocalization.string(
                "Preview only — full resolution is unavailable.", language: language)
        }
    }
}

private struct CompareFocusTrigger: Equatable {
    let photo: PhotoIdentity
    let showsFocusRegions: Bool
}

// MARK: - Read-only Pane Marks Summary

private struct ComparePaneMarksSummary: View {
    let marks: PhotoMarks
    let language: ResolvedAppLanguage
    let identifier: String

    var body: some View {
        let hasStars = !marks.isRejected && marks.rating.rawValue > 0
        let hasLabel = !marks.isRejected && marks.label.colour != nil
        let hasAny = marks.isRejected || hasStars || hasLabel

        Group {
            if hasAny {
                HStack(spacing: 4) {
                    if marks.isRejected {
                        Image(systemName: "flag.slash.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.clove.reject)
                    } else {
                        if marks.rating.rawValue > 0 {
                            HStack(spacing: 1) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text("\(marks.rating.rawValue)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                            }
                            .foregroundStyle(Color.clove.rating.on)
                        }
                        if let colour = marks.label.colour {
                            Circle()
                                .fill(Color.clove.label.colour(for: colour))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(MarkSummary.text(for: marks, language: language))
                .accessibilityIdentifier(identifier)
            }
        }
    }
}

// MARK: - Compact Stepping Filmstrip

private struct CompareFilmstrip: View {
    let photos: [GridPhoto]
    let reference: PhotoIdentity
    let challenger: PhotoIdentity
    let activeSide: CompareSide
    let thumbnails: any GridThumbnailSource
    let onSelectCandidate: (PhotoIdentity) -> Void

    @Environment(\.appLanguage) private var language
    @Environment(\.cloveTheme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(photos) { photo in
                        filmstripItem(photo)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: challenger, initial: true) { _, target in
                withAnimation {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.compare.filmstrip")
    }

    @ViewBuilder
    private func filmstripItem(_ photo: GridPhoto) -> some View {
        let roleBadge: String? =
            if photo.id == reference {
                "A"
            } else if photo.id == challenger {
                "B"
            } else {
                nil
            }
        let isReference = photo.id == reference
        let isSelectedPane =
            (photo.id == reference && activeSide == .reference)
            || (photo.id == challenger && activeSide == .challenger)

        Button {
            guard !isReference else { return }
            onSelectCandidate(photo.id)
        } label: {
            DetailPhotoFrame(
                photo: photo,
                isCurrent: photo.id == challenger || isSelectedPane,
                thumbnails: thumbnails,
                side: 44,
                height: 44,
                showsMarks: true
            )
            .overlay(alignment: .topLeading) {
                if let roleBadge {
                    Text(roleBadge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            isSelectedPane
                                ? theme.tokens.accent.color : Color.black.opacity(0.65),
                            in: Capsule()
                        )
                        .padding(2)
                }
            }
            .opacity(isReference && photo.id != challenger ? 0.78 : 1)
        }
        .buttonStyle(.plain)
        .id(photo.id)
        .accessibilityLabel(photo.fileName)
        .accessibilityValue(
            roleBadge ?? MarkSummary.text(for: photo.marks, language: language)
        )
        .accessibilityAddTraits(photo.id == challenger ? [.isSelected] : [])
        .accessibilityIdentifier("clove.compare.filmstrip.\(photo.id.stem.lowercased())")
    }
}
