import CloveCore
import SwiftUI

/// The detail capsule mirrors live swipe feedback without applying any mark before release.
struct DetailMarkCapsule: View {
    let marks: PhotoMarks
    let settings: AppSettings
    let previewRating: Rating?
    let rate: (Rating) -> Void
    let label: (ColourLabel) -> Void
    let toggleReject: () -> Void
    @State private var showsLabels = false

    var body: some View {
        MarkCapsule(
            rating: previewRating ?? (marks.isRejected ? .unrated : marks.rating),
            label: marks.isRejected ? nil : marks.label.colour, isRejected: marks.isRejected,
            enabledRatings: settings.enabledRatings, identifier: "clove.detail.capsule",
            onRate: rate, onReject: toggleReject, onLabel: { showsLabels.toggle() }
        )
        .accessibilityValue(MarkSummary.text(for: marks))
        .overlay(alignment: .bottomTrailing) {
            if showsLabels {
                LabelPicker(
                    selection: marks.label.colour,
                    labels: [nil] + settings.availableLabels.map { Optional($0) },
                    identifier: "clove.detail.labels"
                ) { colour in
                    label(colour.map { ColourLabel(colour: $0) } ?? .clear)
                    showsLabels = false
                }
                .offset(y: -66)
            }
        }
    }
}
