import CloveCore
import SwiftUI

/// The eight theme tiles in a 4 × 2 grid (`design/handoff/screens.md`, Settings Appearance).
///
/// The ring follows the theme in effect, so with Match system on it sits on Light or Dark as the
/// system changes, exactly as the frame shows. Choosing a tile only reports the theme; the settings
/// section applies `design/handoff/interactions.md`'s rule: Light or Dark keeps Match system on,
/// and any other theme turns it off.
struct ThemePicker: View {
    /// The theme in effect, which carries the ring (components.md, Theme tile).
    let selection: CloveTheme

    /// Chosen tile.
    let onSelect: (CloveTheme) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CloveTheme.allCases) { theme in
                Button {
                    onSelect(theme)
                } label: {
                    ThemeTile(theme: theme, isSelected: theme == selection)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clove.settings.appearance.theme.\(theme.id)")
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
