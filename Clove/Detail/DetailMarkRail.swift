import CloveCore
import SwiftUI

/// Regular-width marking stays beside the stage, including while the photo's chrome is hidden.
struct DetailMarkRail: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    let rate: (Rating) -> Void
    let label: (ColourLabel) -> Void
    let toggleReject: () -> Void
    let markingBegan: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            VerticalStarBar(
                rating: previewRating ?? (marks.isRejected ? .unrated : marks.rating),
                enabledRatings: settings.enabledRatings, size: .pad, showsRejectChip: false,
                identifier: "clove.detail.rail.stars", onPreview: { _ in },
                onCommit: rate, onReject: toggleReject, onBegin: markingBegan)
            Rectangle()
                .fill(Color.clove.separator)
                .frame(height: 1)
            RejectCircle(
                isRejected: marks.isRejected, size: .pad,
                identifier: "clove.detail.rail.reject", onToggle: toggleReject
            )
            .help(marks.isRejected ? "Rejected" : "Reject")
            LabelPicker(
                selection: marks.isRejected ? nil : marks.label.colour,
                labels: settings.availableLabels.map { Optional($0) },
                identifier: "clove.detail.rail.label",
                onPick: { label($0.map { ColourLabel(colour: $0) } ?? .clear) },
                axis: .vertical, isNeutral: marks.isRejected)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 96)
        .frame(maxHeight: .infinity)
        .background(Color.clove.bg.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.detail.rail")
        .accessibilityValue(MarkSummary.text(for: marks))
    }
}
