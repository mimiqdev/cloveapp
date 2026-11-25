import CloveCore
import SwiftUI

/// A paired Light and Dark theme family preview tile with its family name below it.
///
/// The preview is a landscape `108 × 68` frame (`radius 10`, `4 pt` padding, `4 pt` gap) holding
/// two separate `48 × 60` (`radius 6`) mini-cards side-by-side: left in the family's Light
/// companion palette and right in the family's Dark palette, each showing its own canvas, subtle
/// chrome, and an untinted sample photo. When selected, the frame carries a `1.5 pt` `accent`
/// border and a bottom-right circular `accent` checkmark badge.
struct ThemeTile: View {
    nonisolated static let tileSize = CGSize(width: 108, height: 94)
    nonisolated static let previewSize = CGSize(width: 108, height: 68)
    nonisolated static let previewCornerRadius: CGFloat = 10
    nonisolated static let previewPadding: CGFloat = 4
    nonisolated static let cardGap: CGFloat = 4
    nonisolated static let cardSize = CGSize(width: 48, height: 60)
    nonisolated static let cardCornerRadius: CGFloat = 6
    nonisolated static let selectionBorderWidth: CGFloat = 1.5
    nonisolated static let checkmarkBadgeSize: CGFloat = 18

    /// The paired theme family this tile previews.
    let family: ThemeFamily

    /// Whether this family is currently selected, so the tile draws the selection ring and badge.
    var isSelected = false

    /// Proportional scale (`<= 1`) used on narrow containers without clipping.
    var scale: CGFloat = 1

    @Environment(\.appLanguage) private var language

    var body: some View {
        let localizedName = AppLocalization.themeTitle(family, language: language)
        let clampedScale = max(0.5, min(1, scale))
        VStack(spacing: 6 * clampedScale) {
            preview(scale: clampedScale)
            Text(localizedName)
                .font(.caption.weight(isSelected ? .medium : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.clove.text.primary)
        }
        .frame(width: Self.tileSize.width * clampedScale)
        .frame(minHeight: Self.tileSize.height * clampedScale, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Paired `48 × 60` Light (left) and Dark (right) mini-cards inside the `108 × 68` frame.
    private func preview(scale: CGFloat) -> some View {
        let frameShape = RoundedRectangle(
            cornerRadius: Self.previewCornerRadius * scale,
            style: .continuous
        )
        return HStack(spacing: Self.cardGap * scale) {
            miniCard(for: family.lightTheme, scale: scale)
            miniCard(for: family.darkTheme, scale: scale)
        }
        .padding(Self.previewPadding * scale)
        .frame(
            width: Self.previewSize.width * scale,
            height: Self.previewSize.height * scale
        )
        .background(Color.clove.surface.card, in: frameShape)
        .overlay {
            frameShape.strokeBorder(
                isSelected ? Color.clove.accent : Color.clove.separator,
                lineWidth: isSelected ? Self.selectionBorderWidth : 1
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                selectionCheckmarkBadge(scale: scale)
                    .padding(3 * scale)
            }
        }
    }

    /// A single `48 × 60` (`radius 6`) mini-card drawn in one resolved palette's tokens.
    private func miniCard(for theme: CloveTheme, scale: CGFloat) -> some View {
        let cardShape = RoundedRectangle(
            cornerRadius: Self.cardCornerRadius * scale,
            style: .continuous
        )
        return VStack(spacing: 0) {
            HStack(spacing: 3 * scale) {
                Capsule()
                    .fill(theme.tokens.primaryText.color.opacity(0.6))
                    .frame(width: 14 * scale, height: 2.5 * scale)
                Spacer(minLength: 0)
                Circle()
                    .fill(theme.tokens.accent.color)
                    .frame(width: 3.5 * scale, height: 3.5 * scale)
            }
            .padding(.horizontal, 5 * scale)
            .frame(height: 10 * scale)

            ZStack {
                theme.tokens.stage.color
                SamplePhoto()
                    .frame(width: 34 * scale, height: 22 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 3 * scale, style: .continuous))
            }
            .frame(height: 30 * scale)

            dotRow(for: theme, scale: scale)
                .frame(maxHeight: .infinity)
        }
        .frame(width: Self.cardSize.width * scale, height: Self.cardSize.height * scale)
        .background(theme.tokens.canvas.color)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.tokens.separator.color, lineWidth: 0.75)
        }
    }

    /// The card's miniature glass capsule: reject dot, rating dots, and an accent dot.
    private func dotRow(for theme: CloveTheme, scale: CGFloat) -> some View {
        HStack(spacing: 4 * scale) {
            Circle()
                .fill(theme.tokens.reject.color)
                .frame(width: 4 * scale, height: 4 * scale)
            HStack(spacing: 1.5 * scale) {
                star(filled: true, for: theme, scale: scale)
                star(filled: true, for: theme, scale: scale)
                star(filled: false, for: theme, scale: scale)
            }
            Circle()
                .fill(theme.tokens.accent.color)
                .frame(width: 4 * scale, height: 4 * scale)
        }
        .padding(.horizontal, 4 * scale)
        .padding(.vertical, 2.5 * scale)
        .background(theme.tokens.glass.color, in: Capsule())
    }

    /// One star of the miniature, in the theme's rating tokens.
    private func star(filled: Bool, for theme: CloveTheme, scale: CGFloat) -> some View {
        Circle()
            .fill(filled ? theme.tokens.ratingOn.color : theme.tokens.ratingOff.color)
            .frame(width: 3.5 * scale, height: 3.5 * scale)
    }

    /// Bottom-right circular `accent` checkmark badge on the selected preview frame.
    private func selectionCheckmarkBadge(scale: CGFloat) -> some View {
        let badgeSize = Self.checkmarkBadgeSize * scale
        return ZStack {
            Circle()
                .fill(Color.clove.accent)
            Circle()
                .stroke(Color.clove.surface.card, lineWidth: 1.5 * scale)
            Image(systemName: "checkmark")
                .font(.system(size: 9.5 * scale, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityHidden(true)
    }
}

/// The tile's sample photo: a fixed sunset landscape, the same in every theme.
///
/// The colours are the handoff frame's placeholder photo, not theme tokens, because a theme never
/// tints a photo (tokens.md).
private struct SamplePhoto: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        ThemeColour(hex: 0x4C4877).color,
                        ThemeColour(hex: 0xA98F87).color,
                        ThemeColour(hex: 0xF2CD9B).color,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(ThemeColour(hex: 0xFFE7BC).color)
                    .frame(width: width * 0.30, height: width * 0.30)
                    .offset(y: -height * 0.08)
                Ellipse()
                    .fill(ThemeColour(hex: 0x24212F).color)
                    .frame(width: width * 1.65, height: height * 0.76)
                    .offset(y: height * 0.56)
            }
            .frame(width: width, height: height)
        }
    }
}

#Preview("Theme tiles") {
    HStack(spacing: 10) {
        ThemeTile(family: .default, isSelected: true)
        ThemeTile(family: .catppuccin)
        ThemeTile(family: .darkroom)
    }
    .padding(16)
    .background(Rectangle().fill(Color.clove.surface.sheet))
}
