import CloveCore
import SwiftUI

/// The five stars of the mark capsule: filled in `rating/on`, empty in `rating/off`, with a gap of
/// 6 and about 159 pt for the row (`design/handoff/components.md`, Stars).
///
/// Tapping the value the photo already has clears it, which is C13's rating-bar rule (PRD Marking
/// rules); the screen passes the levels it offers, so a disabled level does not appear here.
struct StarRow: View {
    /// The photo's rating.
    let rating: Rating

    /// The levels the row offers, ascending; the settings' enabled levels by default.
    var levels: [Rating] = EnabledRatings.all.levels

    /// The identifier the screen's UI test uses; each star is `"<identifier>.<n>"`.
    var identifier = "clove.mark.stars"

    /// Applies a rating, or clears it with unrated (PRD Marking rules).
    let onRate: (Rating) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(levels, id: \.rawValue) { level in
                star(level)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// One star button; the current value clears on a second tap (PRD Marking rules).
    private func star(_ level: Rating) -> some View {
        let isFilled = level <= rating
        return Button {
            onRate(level == rating ? .unrated : level)
        } label: {
            Image(systemName: isFilled ? "star.fill" : "star")
                .font(.title2)
                .foregroundStyle(isFilled ? Color.clove.rating.on : Color.clove.rating.off)
                .frame(width: 26, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.rawValue) stars")
        .accessibilityAddTraits(level == rating ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(level.rawValue)")
    }
}

#Preview("Stars") {
    VStack(spacing: 12) {
        StarRow(rating: .unrated, identifier: "preview.stars.none") { _ in }
        StarRow(rating: Rating(rawValue: 3) ?? .unrated, identifier: "preview.stars.three") { _ in }
    }
    .padding(24)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
