import CloveCore
import SwiftUI

/// The same shared marking family as detail, applying one mark to the visible selection.
/// Write failures are reported once by the shared toast.
struct GridBatchBar: View {
    let browsing: BrowsingModel
    let cells: [GridCellItem]
    var onDeselectAll: () -> Void = {}
    @Environment(SettingsStore.self) private var store
    @Environment(\.appLanguage) private var language

    var body: some View {
        let batchSelection = BatchSelection(
            groups: browsing.groups, selection: browsing.state.selection)
        MarkingToolbar(
            rating: isRejected ? .unrated : commonRating,
            // Batch Reject is main's set-only action. Keep it unselected so it never
            // advertises a toggle that the existing batch operation cannot perform.
            label: isRejected ? nil : batchLabelState.selection, isRejected: false,
            enabledRatings: store.settings.enabledRatings,
            identifier: "clove.grid.batch", labelPickerIdentifier: "clove.grid.batch.labels",
            // A mixed batch never highlights one sample photo's value (#227, #229).
            isMixed: batchLabelState.isMixed,
            allowsTapCurrentToClear: false,
            onRate: { apply(.rating($0)) }, onReject: { apply(.reject) },
            onLabel: { apply(.label($0.map { ColourLabel(colour: $0) } ?? .clear)) }
        )
        .contextMenu {
            Button(AppLocalization.string("Clear rating", language: language)) {
                apply(.rating(.unrated))
            }
            .accessibilityIdentifier("clove.grid.batch.clearRating")
            if !batchSelection.showsAllSelected(cells) {
                Button(AppLocalization.string("Select all", language: language)) {
                    browsing.selectAllVisible(cells)
                }
                .accessibilityIdentifier("clove.grid.batch.selectAll")
            }
            if !browsing.state.selection.isEmpty {
                Button(AppLocalization.string("Deselect all", language: language)) {
                    onDeselectAll()
                    browsing.deselectAllVisible(cells)
                }
                .accessibilityIdentifier("clove.grid.batch.deselectAll")
            }
        }
        .disabled(browsing.batchTargets.isEmpty || !browsing.canMark)
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
