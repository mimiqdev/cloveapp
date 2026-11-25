import CloveCore
import SwiftUI

/// Responsive 3×2 grid metrics for ``ThemePicker`` across iPhone, Duo Cover, Duo Expanded, and
/// iPad widths.
struct ThemePickerLayout: Equatable, Sendable {
    let tileWidth: CGFloat
    let columnSpacing: CGFloat
    let scale: CGFloat

    static let columns = 3
    static let minColumnSpacing: CGFloat = 8
    static let maxColumnSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 14

    static func resolve(availableWidth: CGFloat) -> ThemePickerLayout {
        let referenceWidth = ThemeTile.tileSize.width
        guard availableWidth > 0 else {
            return ThemePickerLayout(tileWidth: referenceWidth, columnSpacing: 12, scale: 1)
        }
        let maxTilesWidth = CGFloat(columns) * referenceWidth
        if availableWidth >= maxTilesWidth + CGFloat(columns - 1) * minColumnSpacing {
            let idealSpacing = (availableWidth - maxTilesWidth) / CGFloat(columns - 1)
            let spacing = min(maxColumnSpacing, max(minColumnSpacing, idealSpacing))
            return ThemePickerLayout(tileWidth: referenceWidth, columnSpacing: spacing, scale: 1)
        }
        let tileWidth = max(
            1, (availableWidth - CGFloat(columns - 1) * minColumnSpacing) / CGFloat(columns))
        let scale = min(1, tileWidth / referenceWidth)
        return ThemePickerLayout(
            tileWidth: tileWidth, columnSpacing: minColumnSpacing, scale: scale)
    }
}

/// The six paired theme family tiles in a responsive 3 × 2 unboxed grid.
///
/// Choosing a family preserves the active appearance mode (`Light`, `Dark`, or `System`).
struct ThemePicker: View {
    /// The selected family, which carries the selection border and checkmark badge.
    let selection: ThemeFamily

    /// Optional width override for deterministic tests and previews; nil reads container width.
    var availableWidth: CGFloat? = nil

    /// Chosen family.
    let onSelect: (ThemeFamily) -> Void

    @Environment(\.appLanguage) private var language
    @State private var measuredWidth: CGFloat = 0

    private var layout: ThemePickerLayout {
        ThemePickerLayout.resolve(availableWidth: availableWidth ?? measuredWidth)
    }

    private var rows: [[ThemeFamily]] {
        let families = ThemeFamily.allCases
        return stride(from: 0, to: families.count, by: ThemePickerLayout.columns).map { start in
            Array(families[start..<min(start + ThemePickerLayout.columns, families.count)])
        }
    }

    var body: some View {
        let resolvedLayout = layout
        VStack(alignment: .leading, spacing: ThemePickerLayout.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: resolvedLayout.columnSpacing) {
                    ForEach(row) { family in
                        let isSelected = family == selection
                        Button {
                            onSelect(family)
                        } label: {
                            ThemeTile(
                                family: family,
                                isSelected: isSelected,
                                scale: resolvedLayout.scale
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.themeTitle(family, language: language))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("clove.settings.appearance.family.\(family.id)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if abs(measuredWidth - width) > 0.5 {
                measuredWidth = width
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings.appearance.picker")
    }
}

#Preview("Theme picker") {
    ThemePicker(selection: .nord) { _ in }
        .padding(20)
        .background(Rectangle().fill(Color.clove.surface.sheet))
}
