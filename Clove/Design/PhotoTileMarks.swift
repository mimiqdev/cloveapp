import CloveCore
import SwiftUI

/// Rating pill shared across grid tiles, group grid picker tiles, and batch rename order tiles.
struct PhotoTileRatingBadge: View {
    let rating: Rating
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let stars = rating.starCount {
            HStack(spacing: 1) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.clove.rating.on)
                Text(stars.formatted(.number.locale(language.locale)))
                    .foregroundStyle(Color.clove.text.primary)
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.clove.surface.glass, in: Capsule())
            .padding(4)
        }
    }
}

/// Colour label dot shared across grid tiles, group grid picker tiles, and batch rename order tiles.
struct PhotoTileLabelDot: View {
    let label: ColourLabel

    var body: some View {
        if !label.isClear {
            Circle()
                .fill(Color.clove.label.colour(for: label.colour))
                .frame(width: 8, height: 8)
                .overlay { Circle().strokeBorder(Color.clove.text.primary, lineWidth: 1) }
                .padding(5)
        }
    }
}
