import CloveCore
import Foundation
import SwiftUI

/// Summarizes folder-wide review outcomes shown when the `Unmarked` filter empties.
struct GridReviewSummary: Equatable, Sendable {
    let totalCount: Int
    let highRatedCount: Int
    let ratedCount: Int
    let labelledOnlyCount: Int
    let rejectedCount: Int
    let offersMoveRejects: Bool

    init(
        totalCount: Int,
        highRatedCount: Int,
        ratedCount: Int,
        labelledOnlyCount: Int,
        rejectedCount: Int,
        moveRejectsEnabled: Bool
    ) {
        self.totalCount = max(totalCount, 0)
        self.highRatedCount = max(highRatedCount, 0)
        self.ratedCount = max(ratedCount, 0)
        self.labelledOnlyCount = max(labelledOnlyCount, 0)
        self.rejectedCount = max(rejectedCount, 0)
        self.offersMoveRejects = rejectedCount > 0 && moveRejectsEnabled
    }

    init(placedPhotos: [GridPhoto], rejectedPhotoCount: Int, moveRejectsEnabled: Bool) {
        var highRated = 0
        var rated = 0
        var labelledOnly = 0
        for photo in placedPhotos where !photo.marks.isRejected {
            if let stars = photo.marks.rating.starCount {
                rated += 1
                if stars >= 4 {
                    highRated += 1
                }
            } else if !photo.marks.label.isClear {
                labelledOnly += 1
            }
        }
        self.init(
            totalCount: placedPhotos.count,
            highRatedCount: highRated,
            ratedCount: rated,
            labelledOnlyCount: labelledOnly,
            rejectedCount: rejectedPhotoCount,
            moveRejectsEnabled: moveRejectsEnabled)
    }

    func localizedTitle(language: ResolvedAppLanguage) -> String {
        let countText = totalCount.formatted(.number.locale(language.locale))
        if totalCount == 1 {
            return AppLocalization.format("%@ photo reviewed", language: language, countText)
        }
        return AppLocalization.format("All %@ photos reviewed", language: language, countText)
    }

    func localizedSubtitle(language: ResolvedAppLanguage) -> String? {
        var parts: [String] = []
        if highRatedCount > 0 {
            parts.append(
                AppLocalization.format(
                    "%@ ★4+", language: language,
                    highRatedCount.formatted(.number.locale(language.locale))))
        } else if ratedCount > 0 {
            parts.append(
                AppLocalization.format(
                    "%@ rated", language: language,
                    ratedCount.formatted(.number.locale(language.locale))))
        }
        if labelledOnlyCount > 0 {
            parts.append(
                AppLocalization.format(
                    "%@ labeled", language: language,
                    labelledOnlyCount.formatted(.number.locale(language.locale))))
        }
        if rejectedCount > 0 {
            parts.append(
                AppLocalization.format(
                    "%@ rejected", language: language,
                    rejectedCount.formatted(.number.locale(language.locale))))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func localizedMoveRejectsTitle(language: ResolvedAppLanguage) -> String {
        let countText = rejectedCount.formatted(.number.locale(language.locale))
        if rejectedCount == 1 {
            return AppLocalization.format("Move %@ reject", language: language, countText)
        }
        return AppLocalization.format("Move %@ rejects", language: language, countText)
    }

    func localizedShowAllTitle(language: ResolvedAppLanguage) -> String {
        AppLocalization.string("Show all photos", language: language)
    }
}

/// Decides which empty state `GridScreen` presents when no visible cells are shown.
enum GridEmptyStateKind: Equatable, Sendable {
    case emptyFolder
    case allReviewed(GridReviewSummary)
    case filteredEmpty(isOpening: Bool, canClearFilters: Bool)

    /// O(1) trigger predicate avoiding `GridDisplay` cell construction or photo scans during
    /// ordinary browsing.
    static func isAllReviewed(
        isFolderOpening: Bool,
        hasFolderContents: Bool,
        visiblePhotoCount: Int,
        filter: PhotoFilter,
        labelFilter: LabelColour?,
        metadataFilter: PhotoMetadataFilter,
        placedPhotoCount: Int
    ) -> Bool {
        !isFolderOpening
            && hasFolderContents
            && visiblePhotoCount == 0
            && filter == .unmarked
            && labelFilter == nil
            && metadataFilter.isEmpty
            && placedPhotoCount > 0
    }

    @MainActor
    static func isAllReviewed(browsing: BrowsingModel) -> Bool {
        isAllReviewed(
            isFolderOpening: browsing.isFolderOpening,
            hasFolderContents: browsing.hasFolderContents,
            visiblePhotoCount: browsing.photos.count,
            filter: browsing.state.filter,
            labelFilter: browsing.labelFilter,
            metadataFilter: browsing.metadataFilter,
            placedPhotoCount: browsing.allPlacedPhotos.count)
    }

    static func resolve(
        isFolderOpening: Bool,
        hasFolderContents: Bool,
        visiblePhotoCount: Int,
        filter: PhotoFilter,
        labelFilter: LabelColour?,
        metadataFilter: PhotoMetadataFilter,
        hasActiveFilter: Bool,
        placedPhotos: [GridPhoto],
        rejectedPhotoCount: Int,
        moveRejectsEnabled: Bool
    ) -> GridEmptyStateKind {
        if !hasFolderContents && !isFolderOpening {
            return .emptyFolder
        }
        if isAllReviewed(
            isFolderOpening: isFolderOpening,
            hasFolderContents: hasFolderContents,
            visiblePhotoCount: visiblePhotoCount,
            filter: filter,
            labelFilter: labelFilter,
            metadataFilter: metadataFilter,
            placedPhotoCount: placedPhotos.count)
        {
            return .allReviewed(
                GridReviewSummary(
                    placedPhotos: placedPhotos,
                    rejectedPhotoCount: rejectedPhotoCount,
                    moveRejectsEnabled: moveRejectsEnabled))
        }
        return .filteredEmpty(
            isOpening: isFolderOpening,
            canClearFilters: !isFolderOpening && hasActiveFilter)
    }

    @MainActor
    static func resolve(browsing: BrowsingModel, moveRejectsEnabled: Bool) -> GridEmptyStateKind {
        resolve(
            isFolderOpening: browsing.isFolderOpening,
            hasFolderContents: browsing.hasFolderContents,
            visiblePhotoCount: browsing.photos.count,
            filter: browsing.state.filter,
            labelFilter: browsing.labelFilter,
            metadataFilter: browsing.metadataFilter,
            hasActiveFilter: browsing.hasActiveFilter,
            placedPhotos: browsing.allPlacedPhotos,
            rejectedPhotoCount: browsing.rejectedPhotoCount,
            moveRejectsEnabled: moveRejectsEnabled)
    }
}

/// Dedicated completion state shown strictly when the `Unmarked` filter empties in a non-empty folder.
struct GridAllReviewedView: View {
    let summary: GridReviewSummary
    let onMoveRejects: () -> Void
    let onShowAll: () -> Void

    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @Environment(\.tapPickerTriggerRequest) private var tapPickerTriggerRequest
    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 56

    private var effectiveBadgeSize: CGFloat {
        min(badgeSize, 88)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clove.bg.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid.allReviewed")
        .reportHeaderControlFrame("clove.grid.allReviewed")
        .onChange(of: tapPickerTriggerRequest) { _, request in
            switch request?.id {
            case "clove.grid.allReviewed.moveRejects" where summary.offersMoveRejects:
                onMoveRejects()
            case "clove.grid.allReviewed.showAll":
                onShowAll()
            default:
                break
            }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(theme.tokens.saved.color.opacity(0.14))
                    Circle()
                        .strokeBorder(theme.tokens.saved.color.opacity(0.24), lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: effectiveBadgeSize * 0.42, weight: .semibold))
                        .foregroundStyle(Color.clove.status.saved)
                }
                .frame(width: effectiveBadgeSize, height: effectiveBadgeSize)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(summary.localizedTitle(language: language))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.clove.text.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("clove.grid.allReviewed.title")
                        .reportHeaderControlFrame("clove.grid.allReviewed.title")

                    if let subtitle = summary.localizedSubtitle(language: language) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.clove.text.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("clove.grid.allReviewed.summary")
                            .reportHeaderControlFrame("clove.grid.allReviewed.summary")
                    }
                }
            }

            VStack(spacing: 12) {
                if summary.offersMoveRejects {
                    Button(action: onMoveRejects) {
                        Text(summary.localizedMoveRejectsTitle(language: language))
                    }
                    .buttonStyle(AllReviewedPillButtonStyle(emphasis: .reject))
                    .accessibilityIdentifier("clove.grid.allReviewed.moveRejects")
                    .reportHeaderControlFrame("clove.grid.allReviewed.moveRejects")
                }

                Button(action: onShowAll) {
                    Text(summary.localizedShowAllTitle(language: language))
                }
                .buttonStyle(
                    AllReviewedPillButtonStyle(
                        emphasis: summary.offersMoveRejects ? .secondary : .primary)
                )
                .accessibilityIdentifier("clove.grid.allReviewed.showAll")
                .reportHeaderControlFrame("clove.grid.allReviewed.showAll")
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    static func pillForegroundToken(on fill: ThemeColour, in theme: CloveTheme) -> ThemeColour {
        let white = ThemeColour(hex: 0xFFFFFF)
        if contrastRatio(fill, white) >= 4.5 {
            return white
        }
        let canvas = theme.tokens.canvas
        if theme.appearance == .dark, contrastRatio(fill, canvas) >= 4.5 {
            return canvas
        }
        return ThemeColour(hex: 0x000000)
    }

    static func contrastRatio(_ lhs: ThemeColour, _ rhs: ThemeColour) -> Double {
        let l1 = relativeLuminance(lhs)
        let l2 = relativeLuminance(rhs)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ colour: ThemeColour) -> Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(colour.red)
            + 0.7152 * linearize(colour.green)
            + 0.0722 * linearize(colour.blue)
    }
}

private struct AllReviewedPillButtonStyle: ButtonStyle {
    enum Emphasis {
        case reject
        case primary
        case secondary
    }

    let emphasis: Emphasis

    @Environment(\.cloveTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(backgroundFill, in: Capsule())
            .overlay {
                if case .secondary = emphasis {
                    Capsule().strokeBorder(Color.clove.separator, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(
                CloveMotion.micro(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .reject:
            GridAllReviewedView.pillForegroundToken(on: theme.tokens.reject, in: theme).color
        case .primary:
            GridAllReviewedView.pillForegroundToken(on: theme.tokens.accent, in: theme).color
        case .secondary:
            theme.tokens.primaryText.color
        }
    }

    private var backgroundFill: Color {
        switch emphasis {
        case .reject: theme.tokens.reject.color
        case .primary: theme.tokens.accent.color
        case .secondary: theme.tokens.card.color
        }
    }
}
