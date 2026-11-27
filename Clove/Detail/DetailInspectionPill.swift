import CloveCore
import SwiftUI

/// Paired native Liquid Glass capsule (`[ Focus | Compare ]`) for iPad and expanded Duo Detail.
///
/// Toggles camera/face focus overlays on the leading half and enters side-by-side Compare on the
/// trailing half, disabling Compare gracefully when fewer than two photos or narrow bounds prevent
/// split comparison.
struct DetailInspectionPill: View {
    let isFocusRegionsOn: Bool
    let canCompare: Bool
    var focusIdentifier = "clove.detail.focusToggle"
    var compareIdentifier = "clove.detail.compare"
    var identifier = "clove.detail.inspectionPill"
    let onToggleFocus: () -> Void
    let onCompare: () -> Void

    @Environment(\.cloveTheme) private var theme
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let focusLabel = AppLocalization.string("Focus regions", language: language)
        let focusValue = AppLocalization.string(
            isFocusRegionsOn ? "On" : "Off", language: language)
        let compareLabel = AppLocalization.string("Compare", language: language)
        let toggleAnimation = CloveMotion.micro(reduceMotion: reduceMotion)

        HStack(spacing: 0) {
            Button(action: onToggleFocus) {
                Image(systemName: "dot.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        isFocusRegionsOn
                            ? AnyShapeStyle(Color.clove.accent)
                            : AnyShapeStyle(theme.tokens.primaryText.color)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .animation(toggleAnimation, value: isFocusRegionsOn)
            }
            .buttonStyle(.cloveGlassPress)
            .help(focusLabel)
            .accessibilityLabel(focusLabel)
            .accessibilityValue(focusValue)
            .accessibilityAddTraits(isFocusRegionsOn ? .isSelected : [])
            .accessibilityIdentifier(focusIdentifier)
            .reportHeaderControlFrame(focusIdentifier)
            .reportTapPickerFrame(focusIdentifier)

            Rectangle()
                .fill(Color.clove.separator)
                .frame(width: 1, height: 22)

            Button(action: onCompare) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.tokens.primaryText.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .opacity(canCompare ? 1 : 0.35)
            .disabled(!canCompare)
            .buttonStyle(.cloveGlassPress)
            .help(compareLabel)
            .accessibilityLabel(compareLabel)
            .accessibilityIdentifier(compareIdentifier)
            .reportHeaderControlFrame(compareIdentifier)
            .reportTapPickerFrame(compareIdentifier)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .cloveGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .reportHeaderControlFrame(identifier)
        .reportTapPickerFrame(identifier)
    }

    /// Fixed paired capsule dimensions (`96 × 44 pt`, `47.5 × 44` per side around a `1 pt` divider).
    static let size = CGSize(width: 96, height: 44)
}

enum DetailBottomBandRole {
    case leadingPill
    case centerPill
    case toolbar
}

struct DetailBottomBandRoleKey: LayoutValueKey {
    static let defaultValue: DetailBottomBandRole = .toolbar
}

/// Shared single-row horizontal layout for Detail bottom controls:
/// - In 30/70 Photo Preview (iPad & Duo): `[ Focus | Compare ]` leading, optional `Stage Pill`
///   horizontally centered (clamped clear), and `MarkingToolbar` trailing on one vertical centerline.
/// - In Focus View (iPad & Duo): `[ Focus | Compare ]` floating bottom-left with optional centered
///   `Stage Pill` aligned along the same horizontal centerline `12 pt` above the full-width strip.
struct DetailPhotoPreviewBandLayout: Layout {
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let pillGap: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let leadingSize =
            subviews
            .first(where: { $0[DetailBottomBandRoleKey.self] == .leadingPill })?
            .sizeThatFits(.unspecified) ?? .zero
        let centerSize =
            subviews
            .first(where: { $0[DetailBottomBandRoleKey.self] == .centerPill })?
            .sizeThatFits(.unspecified) ?? .zero
        let toolbarSize =
            subviews
            .first(where: { $0[DetailBottomBandRoleKey.self] == .toolbar })?
            .sizeThatFits(.unspecified) ?? .zero

        let horizontalContent =
            leadingInset + leadingSize.width + centerSize.width + toolbarSize.width + trailingInset
        let rowHeight = max(leadingSize.height, max(centerSize.height, toolbarSize.height))
        return CGSize(
            width: proposal.width ?? horizontalContent,
            height: rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let leadingView = subviews.first { $0[DetailBottomBandRoleKey.self] == .leadingPill }
        let leadingSize = leadingView?.sizeThatFits(.unspecified) ?? .zero
        let leadingMinX = bounds.minX + leadingInset
        if let leadingView {
            leadingView.place(
                at: CGPoint(x: leadingMinX, y: bounds.midY - leadingSize.height / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(leadingSize))
        }

        let toolbarView = subviews.first { $0[DetailBottomBandRoleKey.self] == .toolbar }
        let toolbarSize = toolbarView?.sizeThatFits(.unspecified) ?? .zero
        let toolbarMinX = bounds.maxX - trailingInset - toolbarSize.width
        if let toolbarView {
            toolbarView.place(
                at: CGPoint(x: toolbarMinX, y: bounds.midY - toolbarSize.height / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(toolbarSize))
        }

        if let centerView = subviews.first(where: {
            $0[DetailBottomBandRoleKey.self] == .centerPill
        }) {
            let minAllowedX =
                leadingView != nil ? leadingMinX + leadingSize.width + pillGap : leadingMinX
            let trailingBoundary =
                toolbarView != nil ? toolbarMinX - pillGap : bounds.maxX - trailingInset
            let maxPillWidth = max(0, trailingBoundary - minAllowedX)
            let measured = centerView.sizeThatFits(
                ProposedViewSize(width: maxPillWidth, height: bounds.height))
            let pillWidth = min(measured.width, maxPillWidth)
            let idealX = bounds.midX - pillWidth / 2
            let maxAllowedX = trailingBoundary - pillWidth
            let pillX = max(minAllowedX, min(idealX, maxAllowedX))
            centerView.place(
                at: CGPoint(x: pillX, y: bounds.midY - measured.height / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: pillWidth, height: measured.height))
        }
    }
}
