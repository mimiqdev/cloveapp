import CloveCore
import SwiftUI

/// The six paired theme family tiles in a 3 × 2 grid (`design/handoff/screens.md`, Settings
/// Appearance).
///
/// Choosing a family preserves the active appearance mode (`Light`, `Dark`, or `System`).
struct ThemePicker: View {
    /// The selected family, which carries the ring (components.md, Theme tile).
    let selection: ThemeFamily

    /// Chosen family.
    let onSelect: (ThemeFamily) -> Void

    @Environment(\.appLanguage) private var language

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ThemeFamily.allCases) { family in
                let isSelected = family == selection
                Button {
                    onSelect(family)
                } label: {
                    ThemeTile(family: family, isSelected: isSelected)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.themeTitle(family, language: language))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("clove.settings.appearance.family.\(family.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.settings.appearance.picker")
    }
}

#Preview("Theme picker") {
    ThemePicker(selection: .nord) { _ in }
        .padding(16)
        .background(Rectangle().fill(Color.clove.bg.canvas))
}
