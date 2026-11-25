import CloveCore
import SwiftUI

enum FolderPreparationPresentationMode: Equatable, Sendable {
    case popover
    case sheet

    static func resolved(horizontalSizeClass: UserInterfaceSizeClass?) -> Self {
        horizontalSizeClass == .regular ? .popover : .sheet
    }
}

enum FolderPreparationAccessibility {
    static func summaryText(
        for status: FolderPreparationStatus, language: ResolvedAppLanguage = .english
    ) -> String {
        if status.phase == .enumeratingUnknown {
            return AppLocalization.string("Scanning folder…", language: language)
        }
        if let reason = status.waitingReason, status.totalPhotos == 0 {
            return waitingTitle(for: reason, language: language)
        }
        return AppLocalization.format(
            "%lld of %lld ready", language: language, Int64(status.readyForBothCount),
            Int64(status.totalPhotos))
    }

    static func analysisCountText(
        for status: FolderPreparationStatus, language: ResolvedAppLanguage = .english
    ) -> String {
        guard status.totalPhotos > 0 else {
            return AppLocalization.string("Waiting for photo count", language: language)
        }
        return AppLocalization.format(
            "%lld of %lld analyzed", language: language, Int64(status.analysis.completed),
            Int64(status.totalPhotos))
    }

    static func previewsCountText(
        for status: FolderPreparationStatus, language: ResolvedAppLanguage = .english
    ) -> String {
        guard status.totalPhotos > 0 else {
            return AppLocalization.string("Waiting for photo count", language: language)
        }
        return AppLocalization.format(
            "%lld of %lld prepared", language: language, Int64(status.previews.completed),
            Int64(status.totalPhotos))
    }

    static func taskIssueSummary(
        _ counts: FolderPreparationTaskCounts, language: ResolvedAppLanguage = .english
    ) -> String? {
        guard counts.issueCount > 0 else { return nil }
        var parts: [String] = []
        if counts.failed > 0 {
            parts.append(
                AppLocalization.format("%lld failed", language: language, Int64(counts.failed)))
        }
        if counts.unsupported > 0 {
            parts.append(
                AppLocalization.format(
                    "%lld unsupported", language: language, Int64(counts.unsupported)))
        }
        if counts.deferred > 0 {
            parts.append(
                AppLocalization.format("%lld deferred", language: language, Int64(counts.deferred)))
        }
        return parts.joined(separator: " · ")
    }

    static func waitingTitle(
        for reason: FolderPreparationWaitingReason, language: ResolvedAppLanguage = .english
    ) -> String {
        switch reason {
        case .memoryPressure:
            return AppLocalization.string("Paused for memory", language: language)
        case .folderUnavailable(.externalVolumeDisconnected):
            return AppLocalization.string("Paused · drive disconnected", language: language)
        case .folderUnavailable(.locationUnavailable):
            return AppLocalization.string("Paused · folder unavailable", language: language)
        }
    }

    static func waitingDetail(
        for reason: FolderPreparationWaitingReason, language: ResolvedAppLanguage = .english
    ) -> String {
        switch reason {
        case .memoryPressure:
            return AppLocalization.string(
                "Preparation paused while memory is low and will resume automatically.",
                language: language)
        case .folderUnavailable(.externalVolumeDisconnected):
            return AppLocalization.string(
                "Reconnect the drive to continue preparing this folder.", language: language)
        case .folderUnavailable(.locationUnavailable):
            return AppLocalization.string(
                "Reopen the folder to continue preparing photos.", language: language)
        }
    }

    static func waitingSymbol(for reason: FolderPreparationWaitingReason) -> String {
        switch reason {
        case .memoryPressure:
            return "pause.circle"
        case .folderUnavailable(.externalVolumeDisconnected):
            return "externaldrive.badge.xmark"
        case .folderUnavailable(.locationUnavailable):
            return "lock.fill"
        }
    }

    static func retryButtonTitle(language: ResolvedAppLanguage = .english) -> String {
        AppLocalization.string("Retry", language: language)
    }

    static func retryButtonAccessibilityLabel(language: ResolvedAppLanguage = .english) -> String {
        AppLocalization.string("Retry preparation issues", language: language)
    }

    static func retryButtonAccessibilityHint(
        for status: FolderPreparationStatus, language: ResolvedAppLanguage = .english
    ) -> String {
        if status.waitingReason != nil {
            return AppLocalization.string(
                "Unavailable while folder preparation is paused.", language: language)
        }
        return AppLocalization.string(
            "Retries failed or deferred analysis and preview tasks.", language: language)
    }

    static func canRetryIssues(for status: FolderPreparationStatus) -> Bool {
        status.canRetryIssues
    }

    static func groupingStatusText(
        for status: FolderPreparationStatus,
        progress: FolderGroupingProgress = .analyzing(completed: 0, total: 0),
        groupCount: Int = 0,
        isScanning: Bool = false,
        language: ResolvedAppLanguage = .english
    ) -> String {
        if isScanning || progress == .idle {
            if status.waitingReason != nil, status.totalPhotos > 0, !isScanning {
                return AppLocalization.string("Paused", language: language)
            }
            return AppLocalization.string("Waiting for photo count", language: language)
        }
        switch progress {
        case .idle:
            return AppLocalization.string("Waiting for photo count", language: language)
        case .analyzing(let completed, let total):
            if status.waitingReason != nil {
                return AppLocalization.string("Paused", language: language)
            }
            if total > 0 {
                return AppLocalization.format(
                    "%lld of %lld analyzed", language: language, Int64(completed), Int64(total))
            }
            return AppLocalization.string("Finding similar shots…", language: language)
        case .complete:
            return AppLocalization.format("%lld group", language: language, Int64(groupCount))
        }
    }

    static func indicatorAccessibilityValue(
        for status: FolderPreparationStatus,
        isFindingSimilarShots: Bool = false,
        groupingProgress: FolderGroupingProgress = .idle,
        language: ResolvedAppLanguage = .english
    ) -> String {
        switch status.phase {
        case .idle:
            guard isFindingSimilarShots else { return "" }
            if let reason = status.waitingReason {
                return waitingTitle(for: reason, language: language)
            }
            return groupingAccessibilityText(progress: groupingProgress, language: language)
        case .enumeratingUnknown:
            return AppLocalization.string("Scanning folder", language: language)
        case .preparing:
            return AppLocalization.format(
                "%lld of %lld ready", language: language, Int64(status.readyForBothCount),
                Int64(status.totalPhotos))
        case .waiting(let reason):
            let prefix = waitingTitle(for: reason, language: language)
            if status.totalPhotos > 0 {
                let ready = AppLocalization.format(
                    "%lld of %lld ready", language: language, Int64(status.readyForBothCount),
                    Int64(status.totalPhotos))
                return AppLocalization.format("%@, %@", language: language, prefix, ready)
            }
            return prefix
        case .complete:
            if isFindingSimilarShots {
                if let reason = status.waitingReason {
                    return waitingTitle(for: reason, language: language)
                }
                return groupingAccessibilityText(progress: groupingProgress, language: language)
            }
            let ready = AppLocalization.format(
                "%lld of %lld ready", language: language, Int64(status.readyForBothCount),
                Int64(status.totalPhotos))
            return AppLocalization.format("Complete, %@", language: language, ready)
        case .completeWithIssues:
            if isFindingSimilarShots, let reason = status.waitingReason {
                return waitingTitle(for: reason, language: language)
            }
            let issues = AppLocalization.format(
                "%lld issue", language: language, Int64(status.totalIssueCount))
            let ready = AppLocalization.format(
                "%lld of %lld ready", language: language, Int64(status.readyForBothCount),
                Int64(status.totalPhotos))
            return AppLocalization.format(
                "Finished with %@, %@", language: language, issues, ready)
        }
    }

    private static func groupingAccessibilityText(
        progress: FolderGroupingProgress, language: ResolvedAppLanguage
    ) -> String {
        let base = AppLocalization.string("Finding similar shots", language: language)
        if case .analyzing(let completed, let total) = progress, total > 0 {
            let count = AppLocalization.format(
                "%lld of %lld analyzed", language: language, Int64(completed), Int64(total))
            return AppLocalization.format("%@, %@", language: language, base, count)
        }
        return base
    }
}

private struct PreparationCompletionKey: Equatable {
    let phase: FolderPreparationPhase
    let folder: FolderIdentity
    let generation: Int
    let isShowingDetails: Bool
    let isVisible: Bool
    let isGroupingInProgress: Bool
    let waitingReason: FolderPreparationWaitingReason?
}

private struct FolderPreparationPresentationModeKey: EnvironmentKey {
    static let defaultValue: FolderPreparationPresentationMode? = nil
}

extension EnvironmentValues {
    var folderPreparationPresentationMode: FolderPreparationPresentationMode? {
        get { self[FolderPreparationPresentationModeKey.self] }
        set { self[FolderPreparationPresentationModeKey.self] = newValue }
    }
}

struct HeaderControlFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct HeaderControlCountsPreferenceKey: PreferenceKey {
    static let defaultValue: [String: Int] = [:]

    static func reduce(value: inout [String: Int], nextValue: () -> [String: Int]) {
        for (key, count) in nextValue() {
            value[key, default: 0] += count
        }
    }
}

extension View {
    func reportHeaderControlFrame(_ identifier: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: HeaderControlFramesPreferenceKey.self,
                        value: [identifier: proxy.frame(in: .global)]
                    )
                    .preference(
                        key: HeaderControlCountsPreferenceKey.self,
                        value: [identifier: 1])
            }
        }
    }
}

struct FolderPreparationIndicator: View {
    let browsing: BrowsingModel
    let identifierPrefix: String
    var inListRow = false
    var usesCompactLayoutPadding = true
    var usesFloatingBackdrop = false
    var presentTrigger: Int = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.folderPreparationPresentationMode) private var presentationModeOverride
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesVerticalBrowsingToolbar) private var usesVerticalToolbar
    @Environment(\.hasFoldRegion) private var hasFoldRegion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @State private var presentedMode: FolderPreparationPresentationMode?
    @State private var isAnchorReady = false

    private var status: FolderPreparationStatus {
        browsing.preparationStatus
    }

    private var isGroupingInProgress: Bool {
        browsing.isGroupingInProgress
    }

    private var isShowingDetails: Bool {
        presentedMode != nil
    }

    private var presentationMode: FolderPreparationPresentationMode {
        presentationModeOverride
            ?? FolderPreparationPresentationMode.resolved(horizontalSizeClass: horizontalSizeClass)
    }

    private var dismissTrigger: PreparationDismissTrigger {
        PreparationDismissTrigger(
            presentationMode: presentationMode,
            horizontalSizeClass: horizontalSizeClass,
            route: browsing.state.route,
            folder: browsing.state.folder,
            isDuoExpanded: isDuoExpanded,
            isDuoCover: isDuoCover,
            usesVerticalToolbar: usesVerticalToolbar,
            hasFoldRegion: hasFoldRegion)
    }

    var body: some View {
        let shouldShow = browsing.showsPreparationIndicator || isShowingDetails
        if shouldShow {
            indicatorButton
                .task(
                    id: PreparationCompletionKey(
                        phase: status.phase,
                        folder: status.folder,
                        generation: status.generation,
                        isShowingDetails: isShowingDetails,
                        isVisible: shouldShow,
                        isGroupingInProgress: isGroupingInProgress,
                        waitingReason: status.waitingReason)
                ) {
                    guard status.phase == .complete,
                        status.waitingReason == nil,
                        !isShowingDetails,
                        !isGroupingInProgress
                    else { return }
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                        browsing.dismissPreparationCompletion(
                            folder: status.folder, generation: status.generation)
                    }
                }
        }
    }

    private var indicatorAccessibilityValue: String {
        FolderPreparationAccessibility.indicatorAccessibilityValue(
            for: status,
            isFindingSimilarShots: isGroupingInProgress,
            groupingProgress: isGroupingInProgress ? browsing.groupingProgress : .idle,
            language: language)
    }

    @ViewBuilder
    private var indicatorButton: some View {
        let styledButton = Group {
            if usesFloatingBackdrop {
                if #available(iOS 26.0, *) {
                    Button {
                        presentedMode = presentationMode
                    } label: {
                        glyph
                            .frame(width: 14, height: 14)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
                    .accessibilityLabel(
                        AppLocalization.string("Folder preparation", language: language)
                    )
                    .accessibilityValue(indicatorAccessibilityValue)
                    .accessibilityHint(
                        AppLocalization.string(
                            "Shows folder analysis and preview preparation details.",
                            language: language)
                    )
                    .accessibilityIdentifier(identifierPrefix)
                    .reportHeaderControlFrame(identifierPrefix)
                } else {
                    Button {
                        presentedMode = presentationMode
                    } label: {
                        glyph
                            .frame(width: 14, height: 14)
                            .frame(width: 40, height: 40)
                            .cloveGlass(in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .reportHeaderControlFrame(identifierPrefix)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        AppLocalization.string("Folder preparation", language: language)
                    )
                    .accessibilityValue(indicatorAccessibilityValue)
                    .accessibilityHint(
                        AppLocalization.string(
                            "Shows folder analysis and preview preparation details.",
                            language: language)
                    )
                    .accessibilityIdentifier(identifierPrefix)
                }
            } else {
                let baseButton = Button {
                    presentedMode = presentationMode
                } label: {
                    glyph
                        .frame(width: 14, height: 14)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .reportHeaderControlFrame(identifierPrefix)
                }
                .padding(.vertical, usesCompactLayoutPadding ? -11 : 0)
                .padding(.leading, usesCompactLayoutPadding ? -9 : 0)
                .padding(.trailing, usesCompactLayoutPadding ? -15 : 0)
                .accessibilityLabel(
                    AppLocalization.string("Folder preparation", language: language)
                )
                .accessibilityValue(indicatorAccessibilityValue)
                .accessibilityHint(
                    AppLocalization.string(
                        "Shows folder analysis and preview preparation details.",
                        language: language)
                )
                .accessibilityIdentifier(identifierPrefix)

                if inListRow {
                    baseButton.buttonStyle(.borderless)
                } else {
                    baseButton.buttonStyle(.plain)
                }
            }
        }

        styledButton
            .popover(
                isPresented: Binding(
                    get: { presentedMode == .popover && isAnchorReady && scenePhase == .active },
                    set: { if !$0, presentedMode == .popover { presentedMode = nil } }),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                FolderPreparationDetails(browsing: browsing, showsDoneButton: false)
            }
            .sheet(
                isPresented: Binding(
                    get: { presentedMode == .sheet && isAnchorReady && scenePhase == .active },
                    set: { if !$0, presentedMode == .sheet { presentedMode = nil } })
            ) {
                FolderPreparationDetails(browsing: browsing, showsDoneButton: true)
            }
            .onChange(of: presentTrigger) { _, _ in
                if isAnchorReady, scenePhase == .active {
                    presentedMode = presentationMode
                }
            }
            .onChange(of: dismissTrigger) { _, _ in
                presentedMode = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    presentedMode = nil
                }
            }
            .onAppear {
                isAnchorReady = true
            }
            .onDisappear {
                isAnchorReady = false
                presentedMode = nil
            }
    }

    @ViewBuilder
    private var glyph: some View {
        if status.waitingReason != nil,
            isGroupingInProgress || status.phase != .completeWithIssues
        {
            pausedGlyph
        } else if isGroupingInProgress, status.phase == .complete || status.phase == .idle {
            if let fraction = browsing.groupingFraction {
                progressRing(fraction: fraction, tint: theme.tokens.group.color)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.tokens.group.color)
                    .scaleEffect(0.75)
            }
        } else {
            switch status.phase {
            case .idle:
                EmptyView()
            case .enumeratingUnknown:
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.tokens.accent.color)
                    .scaleEffect(0.75)
            case .preparing:
                progressRing(fraction: status.readyFraction ?? 0, tint: theme.tokens.accent.color)
            case .waiting:
                pausedGlyph
            case .complete:
                ZStack {
                    Circle()
                        .stroke(theme.tokens.accent.color, lineWidth: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(theme.tokens.accent.color)
                }
            case .completeWithIssues:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.clove.status.failed)
            }
        }
    }

    private func progressRing(fraction: Double, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(theme.tokens.secondaryText.color.opacity(0.24), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    CloveMotion.progress(reduceMotion: reduceMotion),
                    value: fraction)
        }
    }

    private var pausedGlyph: some View {
        let fraction = status.readyFraction ?? 0
        return ZStack {
            Circle()
                .stroke(theme.tokens.secondaryText.color.opacity(0.24), lineWidth: 2)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        theme.tokens.secondaryText.color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "pause.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(Color.clove.text.secondary)
        }
    }
}

struct FolderPreparationDetails: View {
    let browsing: BrowsingModel
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language

    private var status: FolderPreparationStatus {
        browsing.preparationStatus
    }

    private var folderDisplayName: String {
        status.folderName.isEmpty
            ? browsing.localizedFolderTitle(language: language) : status.folderName
    }

    var body: some View {
        Group {
            if showsDoneButton {
                NavigationStack {
                    ScrollView {
                        detailsContent
                            .padding(16)
                    }
                    .background(Color.clove.surface.sheet)
                    .navigationTitle(
                        AppLocalization.string("Folder preparation", language: language)
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(AppLocalization.string("Done", language: language)) { dismiss() }
                                .foregroundStyle(Color.clove.accent)
                                .accessibilityIdentifier("clove.preparation.done")
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                ViewThatFits(in: .vertical) {
                    detailsContent
                        .padding(16)
                    ScrollView {
                        detailsContent
                            .padding(16)
                    }
                    .frame(maxHeight: 440)
                }
                .frame(width: 340)
                .background(Color.clove.surface.sheet)
            }
        }
        .foregroundStyle(Color.clove.text.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.preparation.details")
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerCard
            if let reason = status.waitingReason {
                waitingBanner(reason)
            }
            tasksCard
            if !status.issues.isEmpty {
                issuesCard
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(Color.clove.text.secondary)
                    .accessibilityHidden(true)
                Text(folderDisplayName)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("clove.preparation.folderName")
            }
            Text(FolderPreparationAccessibility.summaryText(for: status, language: language))
                .font(.subheadline)
                .foregroundStyle(Color.clove.text.secondary)
                .accessibilityIdentifier("clove.preparation.summary")
            if status.isEnumerating && status.totalPhotos > 0 {
                Text(
                    AppLocalization.string(
                        "Still counting photos in this folder.", language: language)
                )
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)
            } else if status.isPartialScan {
                Text(AppLocalization.string("Showing partial folder scan.", language: language))
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.tokens.card.color, in: RoundedRectangle(cornerRadius: 12))
    }

    private func waitingBanner(_ reason: FolderPreparationWaitingReason) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: FolderPreparationAccessibility.waitingSymbol(for: reason))
                .font(.body)
                .foregroundStyle(Color.clove.text.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(FolderPreparationAccessibility.waitingTitle(for: reason, language: language))
                    .font(.subheadline.weight(.semibold))
                Text(FolderPreparationAccessibility.waitingDetail(for: reason, language: language))
                    .font(.caption)
                    .foregroundStyle(Color.clove.text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.tokens.card.color, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.preparation.waiting")
    }

    private var tasksCard: some View {
        let barTint =
            status.waitingReason != nil
            ? theme.tokens.secondaryText.color
            : theme.tokens.accent.color
        return VStack(alignment: .leading, spacing: 12) {
            taskRow(
                title: AppLocalization.string("Focus analysis", language: language),
                countText: FolderPreparationAccessibility.analysisCountText(
                    for: status, language: language),
                completed: status.analysis.completed,
                total: status.totalPhotos,
                issueSummary: FolderPreparationAccessibility.taskIssueSummary(
                    status.analysis, language: language),
                tint: barTint,
                identifierPrefix: "clove.preparation.analysis")
            Divider()
            taskRow(
                title: AppLocalization.string("Previews", language: language),
                countText: FolderPreparationAccessibility.previewsCountText(
                    for: status, language: language),
                completed: status.previews.completed,
                total: status.totalPhotos,
                issueSummary: FolderPreparationAccessibility.taskIssueSummary(
                    status.previews, language: language),
                tint: barTint,
                identifierPrefix: "clove.preparation.previews")
            if browsing.similarGroupsEnabled {
                Divider()
                groupingRow
            }
        }
        .padding(14)
        .background(theme.tokens.card.color, in: RoundedRectangle(cornerRadius: 12))
    }

    private var groupingRow: some View {
        let title = AppLocalization.string("Similar groups", language: language)
        let isScanning = browsing.readingProgress != nil
        let progress = browsing.groupingProgress
        let statusText = FolderPreparationAccessibility.groupingStatusText(
            for: status,
            progress: progress,
            groupCount: browsing.groups.count,
            isScanning: isScanning,
            language: language)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.clove.text.secondary)
                    .accessibilityIdentifier("clove.preparation.grouping.status")
            }
            groupingProgressView(progress: progress, isScanning: isScanning)
                .progressViewStyle(.linear)
                .accessibilityLabel(title)
                .accessibilityValue(statusText)
                .accessibilityIdentifier("clove.preparation.grouping.progress")
        }
    }

    @ViewBuilder
    private func groupingProgressView(
        progress: FolderGroupingProgress, isScanning: Bool
    ) -> some View {
        if isScanning || progress == .idle {
            let tint =
                (status.waitingReason != nil && !isScanning && status.totalPhotos > 0)
                ? theme.tokens.secondaryText.color
                : theme.tokens.group.color
            ProgressView(value: 0, total: 1)
                .tint(tint)
        } else {
            switch progress {
            case .idle:
                ProgressView(value: 0, total: 1)
                    .tint(theme.tokens.group.color)
            case .analyzing(let completed, let total):
                if status.waitingReason != nil {
                    let clampedTotal = Double(max(total, 1))
                    let clampedValue = Double(min(max(completed, 0), max(total, 1)))
                    ProgressView(value: clampedValue, total: clampedTotal)
                        .tint(theme.tokens.secondaryText.color)
                } else if total > 0 {
                    let clampedValue = Double(min(max(completed, 0), total))
                    ProgressView(value: clampedValue, total: Double(total))
                        .tint(theme.tokens.group.color)
                } else {
                    ProgressView()
                        .tint(theme.tokens.group.color)
                }
            case .complete:
                ProgressView(value: 1, total: 1)
                    .tint(theme.tokens.group.color)
            }
        }
    }

    @ViewBuilder
    private func taskRow(
        title: String,
        countText: String,
        completed: Int,
        total: Int,
        issueSummary: String?,
        tint: Color,
        identifierPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.clove.text.secondary)
                    .accessibilityIdentifier("\(identifierPrefix).count")
            }
            Group {
                if total > 0 {
                    ProgressView(
                        value: Double(min(max(completed, 0), total)),
                        total: Double(total))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(tint)
            .accessibilityLabel(title)
            .accessibilityValue(countText)
            .accessibilityIdentifier("\(identifierPrefix).progress")
            if let issueSummary {
                Text(issueSummary)
                    .font(.caption)
                    .foregroundStyle(Color.clove.status.failed)
                    .accessibilityIdentifier("\(identifierPrefix).issues")
            }
        }
    }

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Issues", language: language))
                    .font(.subheadline.weight(.semibold))
                Text(status.totalIssueCount.formatted(.number.locale(language.locale)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.clove.text.secondary)
                Spacer(minLength: 8)
                if status.hasRetryableIssues {
                    Button {
                        Task { await browsing.retryPreparationIssues() }
                    } label: {
                        Label(
                            FolderPreparationAccessibility.retryButtonTitle(language: language),
                            systemImage: "arrow.clockwise"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(theme.tokens.accent.color)
                    .disabled(!status.canRetryIssues)
                    .accessibilityLabel(
                        FolderPreparationAccessibility.retryButtonAccessibilityLabel(
                            language: language)
                    )
                    .accessibilityHint(
                        FolderPreparationAccessibility.retryButtonAccessibilityHint(
                            for: status, language: language)
                    )
                    .accessibilityIdentifier("clove.preparation.retry")
                }
            }
            ForEach(status.issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(issue.fileName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(
                            AppLocalization.string(
                                issue.task == .analysis ? "Focus analysis" : "Preview",
                                language: language)
                        )
                        .font(.caption2)
                        .foregroundStyle(Color.clove.text.secondary)
                    }
                    Text(AppLocalization.string(issue.reason, language: language))
                        .font(.caption)
                        .foregroundStyle(Color.clove.status.failed)
                }
                if issue.id != status.issues.last?.id {
                    Divider()
                }
            }
            if status.totalIssueCount > status.issues.count {
                Text(
                    AppLocalization.format(
                        "Showing %lld of %lld issues", language: language,
                        Int64(status.issues.count), Int64(status.totalIssueCount))
                )
                .font(.caption)
                .foregroundStyle(Color.clove.text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.tokens.card.color, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.preparation.issues")
    }
}

private struct PreparationDismissTrigger: Equatable {
    let presentationMode: FolderPreparationPresentationMode
    let horizontalSizeClass: UserInterfaceSizeClass?
    let route: BrowserRoute
    let folder: FolderIdentity?
    let isDuoExpanded: Bool
    let isDuoCover: Bool
    let usesVerticalToolbar: Bool
    let hasFoldRegion: Bool
}
