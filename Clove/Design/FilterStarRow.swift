import CloveCore
import SwiftUI

/// The filter menu's rating floor: five compact stars that fill to the chosen minimum.
///
/// This is a filter control, not a marking input: every level is tappable regardless of the
/// enabled-ratings setting, and tapping the current minimum clears it back to All.
struct FilterStarRow: View {
    /// The filter's current minimum rating, or unrated for All.
    let rating: Rating

    /// The identifier the screen's UI test uses; each star is `"<identifier>.<n>"`.
    var identifier = "clove.grid.filter.stars"

    /// Sets the rating floor, or clears it with unrated.
    let onSelect: (Rating) -> Void

    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EnabledRatings.all.levels, id: \.rawValue) { level in
                Button {
                    onSelect(level == rating ? .unrated : level)
                } label: {
                    Image(systemName: level <= rating ? "star.fill" : "star")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(
                            level <= rating ? Color.clove.rating.on : Color.clove.rating.off
                        )
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    AppLocalization.starCount(level.starCount ?? 0, language: language)
                )
                .accessibilityAddTraits(level == rating ? .isSelected : [])
                .accessibilityIdentifier("\(identifier).\(level.rawValue)")
            }
        }
    }
}

#Preview("Filter stars") {
    FilterStarRow(rating: Rating(rawValue: 3) ?? .unrated) { _ in }
        .padding(16)
        .background(Rectangle().fill(Color.clove.surface.sheet))
}
