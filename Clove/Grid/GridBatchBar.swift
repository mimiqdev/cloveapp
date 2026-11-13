import CloveCore
import SwiftUI

/// The same shared marking family as detail, applying one mark to the visible selection.
/// Write failures are reported once by the shared toast.
struct GridBatchBar: View {
    let browsing: BrowsingModel
    let cells: [GridCellItem]
    @Environment(SettingsStore.self) private var store

    var body: some View {
        MarkingToolbar(
            rating: isRejected ? .unrated : commonRating,
            // Batch Reject is main's set-only action. Keep it unselected so it never
            // advertises a toggle that the existing batch operation cannot perform.
            label: isRejected ? nil : commonLabel, isRejected: false,
            enabledRatings: store.settings.enabledRatings,
            identifier: "clove.grid.batch", labelPickerIdentifier: "clove.grid.batch.labels",
            onRate: { apply(.rating($0)) }, onReject: { apply(.reject) },
            onLabel: { apply(.label($0.map { ColourLabel(colour: $0) } ?? .clear)) }
        )
        .contextMenu {
            Button("Clear rating") { apply(.rating(.unrated)) }
                .accessibilityIdentifier("clove.grid.batch.clearRating")
            Button("Select all") { browsing.selectAllVisible(cells) }
                .accessibilityIdentifier("clove.grid.batch.selectAll")
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

    private var commonLabel: LabelColour? {
        guard let first = browsing.batchTargets.first?.marks.label,
            browsing.batchTargets.allSatisfy({ $0.marks.label == first })
        else { return nil }
        return first.colour
    }

    private func apply(_ action: BatchMarkAction) {
        browsing.applyBatch(action, settings: store.settings)
    }
}
