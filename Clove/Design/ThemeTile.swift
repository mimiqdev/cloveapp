import CloveCore
import SwiftUI

/// A theme's mini preview with its name below it (`design/handoff/components.md`, Theme tile;
/// `screens/11-settings-theme-picker.png`).
///
/// The preview is a portrait tile, 70 × 82, drawn in the tile's own theme tokens and never in the
/// theme in effect: the theme's stage holds one sample photo, and under it a dot row stands in for
/// the mark capsule with a reject dot, three stars and a label dot. That is how the picker shows
/// what a theme looks like before the user chooses it. The selected tile carries a 2 pt `accent`
/// ring, and its name is in `accent` as well.
///
/// The photo is a fixed placeholder landscape: photos are never tinted by a theme (tokens.md), and
/// the handoff's sample photos are placeholders (README.md).
struct ThemeTile: View {
    /// The theme this tile previews (clove-themes.json).
    let theme: CloveTheme

    /// Whether the tile is the one in effect, so it draws the ring (components.md).
    var isSelected = false

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: 70, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.tokens.separator.color, lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clove.accent, lineWidth: 2)
                    }
                }
            Text(theme.name)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.clove.accent : Color.clove.text.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The tile's own colours: the stage with one photo, and the dot row under it (components.md).
    private var preview: some View {
        ZStack(alignment: .top) {
            theme.tokens.canvas.color
            VStack(spacing: 0) {
                Color.clear.frame(height: 6)
                stage.frame(height: 44)
                dotRow.frame(maxHeight: .infinity)
            }
        }
    }

    /// The theme's stage with the sample photo on it.
    private var stage: some View {
        ZStack {
            theme.tokens.stage.color
            SamplePhoto()
                .frame(width: 52, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    /// The frame's miniature glass capsule: reject dot, rating dots and an accent dot.
    private var dotRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.tokens.reject.color)
                .frame(width: 6, height: 6)
            HStack(spacing: 2) {
                star(filled: true)
                star(filled: true)
                star(filled: false)
            }
            Circle()
                .fill(theme.tokens.accent.color)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(theme.tokens.glass.color, in: Capsule())
    }

    /// One star of the miniature, in the theme's rating tokens.
    private func star(filled: Bool) -> some View {
        Circle()
            .fill(filled ? theme.tokens.ratingOn.color : theme.tokens.ratingOff.color)
            .frame(width: 5, height: 5)
    }
}

/// The tile's sample photo: a fixed sunset landscape, the same in every theme.
///
/// The colours are the handoff frame's placeholder photo, not theme tokens, because a theme never
/// tints a photo (tokens.md).
private struct SamplePhoto: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ThemeColour(hex: 0x4C4877).color,
                    ThemeColour(hex: 0xA98F87).color,
                    ThemeColour(hex: 0xF2CD9B).color,
                ],
                startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(ThemeColour(hex: 0xFFE7BC).color)
                .frame(width: 16, height: 16)
                .offset(y: -2)
            Ellipse()
                .fill(ThemeColour(hex: 0x24212F).color)
                .frame(width: 86, height: 26)
                .offset(y: 20)
        }
    }
}

#Preview("Theme tiles") {
    HStack(spacing: 10) {
        ThemeTile(theme: .light, isSelected: true)
        ThemeTile(theme: .darkroom)
        ThemeTile(theme: .nord)
    }
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
