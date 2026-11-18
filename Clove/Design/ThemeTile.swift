import CloveCore
import SwiftUI

/// A theme family's mini paired preview with its name below it (`design/handoff/components.md`,
/// Theme tile; `screens/11-settings-theme-picker.png`).
///
/// The preview is a portrait tile, 70 × 82, split down the middle into the family's light palette
/// (left) and dark palette (right), never drawn in the theme in effect: each half draws its own
/// canvas, stage, glass capsule, reject dot, stars and accent dot, while the centered sample photo
/// stays untinted across both halves. That shows how a family behaves in both Light and Dark
/// appearances before selection. The selected tile carries a 2 pt `accent` ring, and its name is
/// in `accent` as well.
struct ThemeTile: View {
    /// The paired theme family this tile previews.
    let family: ThemeFamily

    /// Whether this family is currently selected, so the tile draws the `accent` ring.
    var isSelected = false

    @Environment(\.appLanguage) private var language

    var body: some View {
        let localizedName = AppLocalization.themeTitle(family, language: language)
        VStack(spacing: 6) {
            preview
                .frame(width: 70, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.clove.separator, lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.clove.accent, lineWidth: 2)
                    }
                }
            Text(localizedName)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.clove.accent : Color.clove.text.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Paired Light (left) and Dark (right) chrome behind an untinted centered photo.
    private var preview: some View {
        ZStack(alignment: .top) {
            ZStack {
                halfPreview(for: family.lightTheme)
                    .mask(leftHalfMask)
                halfPreview(for: family.darkTheme)
                    .mask(rightHalfMask)
            }
            VStack(spacing: 0) {
                Color.clear.frame(height: 6)
                SamplePhoto()
                    .frame(width: 52, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(height: 44)
                Spacer(minLength: 0)
            }
        }
    }

    private var leftHalfMask: some View {
        HStack(spacing: 0) {
            Color.black
            Color.clear
        }
    }

    private var rightHalfMask: some View {
        HStack(spacing: 0) {
            Color.clear
            Color.black
        }
    }

    /// Chrome preview in a single resolved palette's tokens (without the centered photo).
    private func halfPreview(for theme: CloveTheme) -> some View {
        ZStack(alignment: .top) {
            theme.tokens.canvas.color
            VStack(spacing: 0) {
                Color.clear.frame(height: 6)
                theme.tokens.stage.color.frame(height: 44)
                dotRow(for: theme).frame(maxHeight: .infinity)
            }
        }
    }

    /// The frame's miniature glass capsule: reject dot, rating dots and an accent dot.
    private func dotRow(for theme: CloveTheme) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.tokens.reject.color)
                .frame(width: 6, height: 6)
            HStack(spacing: 2) {
                star(filled: true, for: theme)
                star(filled: true, for: theme)
                star(filled: false, for: theme)
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
    private func star(filled: Bool, for theme: CloveTheme) -> some View {
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
        ThemeTile(family: .default, isSelected: true)
        ThemeTile(family: .catppuccin)
        ThemeTile(family: .darkroom)
        ThemeTile(family: .nord)
    }
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
