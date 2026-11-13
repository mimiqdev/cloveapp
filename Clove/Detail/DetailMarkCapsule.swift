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
    /// The capsule's identifier and its label picker's, per presentation (iPhone detail,
    /// expanded Duo beneath the photo).
    var identifier = "clove.detail.capsule"
    var labelPickerIdentifier = "clove.detail.labels"
    @Environment(\.tapPickerController) private var tapPicker
    @State private var labelAnchor: CGRect = .zero
    @State private var fallbackShowsLabels = false

    var body: some View {
        let labels: [LabelColour?] = [nil] + settings.availableLabels.map { Optional($0) }
        MarkCapsule(
            rating: previewRating ?? (marks.isRejected ? .unrated : marks.rating),
            label: marks.isRejected ? nil : marks.label.colour, isRejected: marks.isRejected,
            enabledRatings: settings.enabledRatings, identifier: identifier,
            onRate: {
                tapPicker?.dismiss()
                fallbackShowsLabels = false
                rate($0)
            },
            onReject: {
                tapPicker?.dismiss()
                fallbackShowsLabels = false
                toggleReject()
            },
            onLabel: { toggleLabelPicker(labels: labels) },
            onLabelAnchorChange: { rect in
                labelAnchor = rect
                tapPicker?.updateAnchor(id: labelPickerIdentifier, anchor: rect)
            }
        )
        .accessibilityValue(MarkSummary.text(for: marks))
        .overlay(alignment: .bottomTrailing) {
            if tapPicker == nil, fallbackShowsLabels {
                labelPickerView(labels: labels, axis: .horizontal) {
                    fallbackShowsLabels = false
                }
                .offset(y: -66)
            }
        }
    }

    private func toggleLabelPicker(labels: [LabelColour?]) {
        guard let tapPicker else {
            fallbackShowsLabels.toggle()
            return
        }
        tapPicker.toggle(
            id: labelPickerIdentifier,
            anchor: labelAnchor,
            horizontalSize: LabelPicker.preferredSize(for: .horizontal, count: labels.count),
            verticalSize: LabelPicker.preferredSize(for: .vertical, count: labels.count),
            preferredEdge: .top
        ) { axis, dismiss in
            labelPickerView(labels: labels, axis: axis, dismiss: dismiss)
        }
    }

    private func labelPickerView(
        labels: [LabelColour?], axis: Axis, dismiss: @escaping () -> Void
    ) -> some View {
        LabelPicker(
            selection: marks.label.colour,
            labels: labels,
            identifier: labelPickerIdentifier,
            onPick: { colour in
                label(colour.map { ColourLabel(colour: $0) } ?? .clear)
                dismiss()
            },
            axis: axis)
    }
}
