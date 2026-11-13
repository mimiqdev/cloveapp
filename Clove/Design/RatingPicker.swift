import CloveCore
import SwiftUI

/// The shared visual tap-rating picker: an explicit Clear action (`star.slash`) plus five SF stars
/// (`star` / `star.fill`) in a glass capsule (`design/handoff/components.md`, Tap rating picker).
///
/// Horizontal order is Clear, 1, 2, 3, 4, 5 left to right (`288 × 52` pt reference). Vertical
/// order is 5, 4, 3, 2, 1, Clear top to bottom (`52 × 288` pt reference), so stars fill from the
/// bottom consistently with quick-swipe feedback. Stars fill cumulatively up to the current rating,
/// and the active target carries a subtle selected highlight. Clearing sets unrated (`0`) without
/// affecting color labels or confusing Clear with Reject (`-1`).
struct RatingPicker: View {
    /// The photo's current rating, or `.unrated` when mixed (combined with ``isMixed``).
    let selection: Rating

    /// True when a batch selection has differing ratings, so no target appears selected.
    var isMixed = false

    /// The star levels input may apply; disabled stars remain visible at reduced opacity.
    var enabledRatings: EnabledRatings = .all

    /// Single-photo controls clear to `.unrated` when tapping the already-selected star; batch
    /// controls keep set-only semantics and clear via the explicit Clear button.
    var allowsTapCurrentToClear = true

    /// Layout orientation: `.horizontal` (`288 × 52`) or `.vertical` (`52 × 288`).
    var axis: Axis = .horizontal

    /// Accessibility identifier prefix; targets use `"<identifier>.clear"` and `"<identifier>.1"`…`"5"`.
    var identifier = "clove.mark.ratingPicker"

    /// Applies the chosen rating (`.unrated` for Clear, or `1...5`).
    let onPick: (Rating) -> Void

    static let itemCount = 6
    static let targetExtent: CGFloat = 44
    static let itemSpacing: CGFloat = 3.2
    static let containerPadding: CGFloat = 4

    /// Reference dimensions (`288 × 52` horizontal, `52 × 288` vertical).
    static func preferredSize(for axis: Axis) -> CGSize {
        let major =
            containerPadding * 2
            + CGFloat(itemCount) * targetExtent
            + CGFloat(itemCount - 1) * itemSpacing
        let minor = containerPadding * 2 + targetExtent
        return axis == .horizontal
            ? CGSize(width: major, height: minor)
            : CGSize(width: minor, height: major)
    }

    var body: some View {
        let layout =
            axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: Self.itemSpacing))
            : AnyLayout(VStackLayout(spacing: Self.itemSpacing))
        layout {
            ForEach(orderedItems, id: \.self) { item in
                itemButton(for: item)
            }
        }
        .padding(Self.containerPadding)
        .cloveGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(identifier)
    }

    private enum PickerItem: Hashable {
        case clear
        case star(Rating)
    }

    private var orderedItems: [PickerItem] {
        let stars = EnabledRatings.all.levels.map(PickerItem.star)
        return axis == .horizontal ? [.clear] + stars : stars.reversed() + [.clear]
    }

    @ViewBuilder
    private func itemButton(for item: PickerItem) -> some View {
        switch item {
        case .clear:
            clearButton
        case .star(let level):
            starButton(level)
        }
    }

    private var clearButton: some View {
        let isSelected = !isMixed && selection == .unrated
        return Button {
            onPick(.unrated)
        } label: {
            Image(systemName: "star.slash")
                .font(.title3)
                .foregroundStyle(Color.clove.text.secondary)
                .frame(minWidth: Self.targetExtent, minHeight: Self.targetExtent)
                .background { selectedHighlight(active: isSelected) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear rating")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).clear")
        .help("Clear rating")
    }

    private func starButton(_ level: Rating) -> some View {
        let isFilled = !isMixed && level <= selection
        let isEnabled = enabledRatings.contains(level)
        let isSelected = !isMixed && level == selection
        let canClearDisabledCurrent = allowsTapCurrentToClear && isSelected
        let stars = level.starCount ?? 0
        let label = stars == 1 ? "1 star" : "\(stars) stars"

        return Button {
            onPick(allowsTapCurrentToClear && isSelected ? .unrated : level)
        } label: {
            Image(systemName: isFilled ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFilled ? Color.clove.rating.on : Color.clove.rating.off)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(minWidth: Self.targetExtent, minHeight: Self.targetExtent)
                .background { selectedHighlight(active: isSelected) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled && !canClearDisabledCurrent)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(level.rawValue)")
        .help(label)
    }

    @ViewBuilder
    private func selectedHighlight(active: Bool) -> some View {
        if active {
            Circle()
                .fill(Color.clove.text.primary.opacity(0.14))
                .overlay {
                    Circle().strokeBorder(Color.clove.text.primary.opacity(0.28), lineWidth: 1)
                }
                .padding(3)
        }
    }

    private var accessibilityValue: String {
        if isMixed { return "Mixed" }
        if selection == .rejected { return "Rejected" }
        guard let stars = selection.starCount else { return "Unrated" }
        return stars == 1 ? "1 star" : "\(stars) stars"
    }
}

#Preview("Rating picker") {
    VStack(spacing: 16) {
        RatingPicker(selection: .unrated, identifier: "preview.rating.clear") { _ in }
        RatingPicker(
            selection: Rating(rawValue: 3) ?? .unrated, identifier: "preview.rating.three"
        ) { _ in }
        RatingPicker(
            selection: .unrated, isMixed: true, identifier: "preview.rating.mixed"
        ) { _ in }
        RatingPicker(
            selection: Rating(rawValue: 3) ?? .unrated, axis: .vertical,
            identifier: "preview.rating.vertical"
        ) { _ in }
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
