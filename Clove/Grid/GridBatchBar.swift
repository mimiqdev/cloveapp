import CloveCore
import SwiftUI

/// The same floating capsule as detail, applying one mark to the visible selection.
/// Write failures are reported once by the shared toast.
struct GridBatchBar: View {
    let browsing: BrowsingModel
    let cells: [GridCellItem]
    @Environment(SettingsStore.self) private var store
    @Environment(\.tapPickerController) private var tapPicker
    @State private var labelAnchor: CGRect = .zero
    @State private var fallbackShowsLabels = false

    var body: some View {
        let labels: [LabelColour?] = [nil] + store.settings.availableLabels.map { Optional($0) }
        let labelState = batchLabelState
        MarkCapsule(
            rating: isRejected ? .unrated : commonRating,
            // Batch Reject is main's set-only action. Keep it unselected so it never
            // advertises a toggle that the existing batch operation cannot perform.
            label: isRejected ? nil : labelState.selection, isRejected: false,
            enabledRatings: store.settings.enabledRatings, identifier: "clove.grid.batch",
            onRate: {
                tapPicker?.dismiss()
                fallbackShowsLabels = false
                apply(.rating($0))
            },
            onReject: {
                tapPicker?.dismiss()
                fallbackShowsLabels = false
                apply(.reject)
            },
            onLabel: { toggleLabelPicker(labels: labels, labelState: labelState) },
            onLabelAnchorChange: { rect in
                labelAnchor = rect
                tapPicker?.updateAnchor(id: "clove.grid.batch.labels", anchor: rect)
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if tapPicker == nil, fallbackShowsLabels {
                labelPickerView(labels: labels, labelState: labelState, axis: .horizontal) {
                    fallbackShowsLabels = false
                }
                .offset(y: -66)
            }
        }
        .contextMenu {
            Button("Clear rating") { apply(.rating(.unrated)) }
                .accessibilityIdentifier("clove.grid.batch.clearRating")
            Button("Select all") { browsing.selectAllVisible(cells) }
                .accessibilityIdentifier("clove.grid.batch.selectAll")
        }
        .disabled(browsing.batchTargets.isEmpty || !browsing.canMark)
    }

    private func toggleLabelPicker(
        labels: [LabelColour?], labelState: (selection: LabelColour?, isMixed: Bool)
    ) {
        guard let tapPicker else {
            fallbackShowsLabels.toggle()
            return
        }
        tapPicker.toggle(
            id: "clove.grid.batch.labels",
            anchor: labelAnchor,
            horizontalSize: LabelPicker.preferredSize(for: .horizontal, count: labels.count),
            verticalSize: LabelPicker.preferredSize(for: .vertical, count: labels.count),
            preferredEdge: .top
        ) { axis, dismiss in
            labelPickerView(labels: labels, labelState: labelState, axis: axis, dismiss: dismiss)
        }
    }

    private func labelPickerView(
        labels: [LabelColour?],
        labelState: (selection: LabelColour?, isMixed: Bool),
        axis: Axis,
        dismiss: @escaping () -> Void
    ) -> some View {
        LabelPicker(
            selection: labelState.selection,
            isMixed: labelState.isMixed,
            labels: labels,
            identifier: "clove.grid.batch.labels",
            onPick: { colour in
                apply(.label(colour.map { ColourLabel(colour: $0) } ?? .clear))
                dismiss()
            },
            axis: axis)
    }

    private var isRejected: Bool {
        !browsing.batchTargets.isEmpty && browsing.batchTargets.allSatisfy(\.marks.isRejected)
    }

    private var commonRating: Rating {
        guard let first = browsing.batchTargets.first?.marks.rating,
            browsing.batchTargets.allSatisfy({ $0.marks.rating == first })
        else { return .unrated }
        return first
    }

    private var batchLabelState: (selection: LabelColour?, isMixed: Bool) {
        guard let first = browsing.batchTargets.first?.marks.label else {
            return (nil, false)
        }
        let allSame = browsing.batchTargets.allSatisfy { $0.marks.label == first }
        return allSame ? (first.colour, false) : (nil, true)
    }

    private func apply(_ action: BatchMarkAction) {
        browsing.applyBatch(action, settings: store.settings)
    }
}
