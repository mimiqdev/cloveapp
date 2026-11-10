import CloveCore
import SwiftUI

/// The floating mark capsule: Reject, five stars and the label circle on one glass capsule
/// (`design/handoff/components.md`, Mark capsule).
///
/// It is 358 × 56, radius 28, with a gap of 12 and padding of 16; the stars sit centred with
/// hairlines either side. It floats above the home indicator in detail, group review, select mode
/// and the half fold. Every mark goes through the closures, so the screen applies C13's rules and
/// writes the mark; the capsule itself knows nothing about the library.
struct MarkCapsule: View {
    /// The photo's rating (PRD P0-04).
    let rating: Rating

    /// The photo's label, or nil when it has none (PRD Marking rules).
    let label: LabelColour?

    /// Whether the photo is rejected (G1 decision 5).
    let isRejected: Bool

    /// The levels input may apply; all five by default, and every level still shows
    /// (PRD Enabled rating levels).
    var enabledRatings: EnabledRatings = .all

    /// The identifier the screen's UI test uses.
    var identifier = "clove.mark.capsule"

    /// Applies a rating, or clears it (PRD Marking rules).
    let onRate: (Rating) -> Void

    /// Toggles Reject (PRD Marking rules).
    let onReject: () -> Void

    /// Opens the label picker (PRD Marking rules).
    let onLabel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RejectCircle(
                isRejected: isRejected, identifier: "\(identifier).reject", onToggle: onReject)
            Spacer(minLength: 0)
            hairline
            StarRow(
                rating: rating, enabledRatings: enabledRatings,
                identifier: "\(identifier).stars", onRate: onRate)
            hairline
            Spacer(minLength: 0)
            LabelCircle(label: label, identifier: "\(identifier).label", onTap: onLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 358)
        .cloveGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The thin divider the capsule draws between the marks (components.md's frame).
    private var hairline: some View {
        Rectangle()
            .fill(Color.clove.separator)
            .frame(width: 1, height: 20)
    }
}

#Preview("Mark capsule") {
    MarkCapsule(
        rating: Rating(rawValue: 3) ?? .unrated, label: .blue, isRejected: false,
        identifier: "preview.capsule", onRate: { _ in }, onReject: {}, onLabel: {}
    )
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
