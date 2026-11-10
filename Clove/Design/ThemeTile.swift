import CloveCore
import SwiftUI

/// A theme's mini preview with its name below it (`design/handoff/components.md`, Theme tile).
///
/// The miniature is drawn in the tile's own theme tokens, never in the theme in effect: a grid
/// strip on `bg/stage` with three `surface/card` tiles, and a small mark capsule with the reject
/// ring, three stars and a label dot. That is how the picker shows what each theme looks like
/// before the user chooses it. The selected tile carries a 2 pt `accent` ring, and its name is in
/// `accent` as well (screens/11-settings-theme-picker.png).
struct ThemeTile: View {
    /// The theme this tile previews (clove-themes.json).
    let theme: CloveTheme

    /// Whether the tile is the one in effect, so it draws the ring (components.md).
    var isSelected = false

    var body: some View {
        VStack(spacing: 6) {
            miniature
                .frame(width: 74, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.tokens.separator.color, lineWidth: 1)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    /// The tile's own colours: a grid strip and a mark capsule (components.md).
    private var miniature: some View {
        ZStack {
            theme.tokens.canvas.color
            VStack(spacing: 3) {
                gridStrip
                capsule
            }
            .padding(4)
        }
    }

    /// Three photo tiles on the theme's stage, which stands in for a grid (components.md).
    private var gridStrip: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { _ in
                ZStack {
                    Rectangle().fill(theme.tokens.card.color)
                    Image(systemName: "photo.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tokens.secondaryText.color)
                }
            }
        }
        .frame(height: 28)
        .background(theme.tokens.stage.color)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    /// A miniature mark capsule: Reject, three stars and a label dot (components.md).
    private var capsule: some View {
        HStack(spacing: 2) {
            Circle()
                .strokeBorder(theme.tokens.reject.color, lineWidth: 1)
                .frame(width: 7, height: 7)
            Image(systemName: "star.fill")
                .font(.system(size: 7))
                .foregroundStyle(theme.tokens.ratingOn.color)
            Image(systemName: "star")
                .font(.system(size: 7))
                .foregroundStyle(theme.tokens.ratingOff.color)
            Spacer(minLength: 0)
            Circle()
                .fill(theme.tokens.labelGreen.color)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 3)
        .frame(height: 13)
        .background(Capsule().fill(theme.tokens.glass.color))
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
