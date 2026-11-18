import CloveCore
import SwiftUI

/// Regular-width marking stays beside the stage, including while the photo's chrome is hidden.
///
/// The rail keeps its direct-manipulation quick-rating ladder, which fills from the bottom on a
/// tap or a drag, then the marking family's shared Reject action and the label picker's inline
/// vertical column below it (owner decisions, 2026-11-13, #227 and #229). No action is
/// duplicated.
struct DetailMarkRail: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    var photoID: PhotoIdentity? = nil
    let rate: (Rating) -> Void
    let label: (ColourLabel) -> Void
    let toggleReject: () -> Void
    let markingBegan: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: 10) {
            VerticalStarBar(
                rating: previewRating ?? (marks.isRejected ? .unrated : marks.rating),
                enabledRatings: settings.enabledRatings, size: .pad, showsRejectChip: false,
                identifier: "clove.detail.rail.stars", photoID: photoID, onPreview: { _ in },
                onCommit: rate, onReject: toggleReject, onBegin: markingBegan)
            Rectangle()
                .fill(Color.clove.separator)
                .frame(width: 48, height: 1)
            MarkRejectAction(
                isRejected: marks.isRejected, identifier: "clove.detail.rail.reject",
                photoID: photoID,
                onToggle: toggleReject
            )
            .help(
                AppLocalization.string(marks.isRejected ? "Rejected" : "Reject", language: language)
            )
            .frame(width: 48, height: 40)
            LabelPicker(
                selection: marks.isRejected ? nil : marks.label.colour,
                labels: settings.availableLabels.map { Optional($0) },
                identifier: "clove.detail.rail.label",
                onPick: { label($0.map { ColourLabel(colour: $0) } ?? .clear) },
                axis: .vertical, showsGlass: false, isNeutral: marks.isRejected,
                photoID: photoID)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 96)
        .frame(maxHeight: .infinity)
        .background(Color.clove.bg.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.rail")
        .accessibilityValue(MarkSummary.text(for: marks, language: language))
    }
}
