import CloveCore
import SwiftUI

/// The same floating capsule as detail, applying one mark to the visible selection.
/// Partial failures are reported by the header glyph and tile dots (owner decision, 2026-11-11).
struct GridBatchBar: View {
    let browsing: BrowsingModel
    let cells: [GridCellItem]
    @Environment(SettingsStore.self) private var store
    @State private var showsLabels = false

    var body: some View {
        MarkCapsule(
            rating: isRejected ? .unrated : commonRating,
            label: isRejected ? nil : commonLabel, isRejected: isRejected,
            enabledRatings: store.settings.enabledRatings, identifier: "clove.grid.batch",
            onRate: { apply(.rating($0)) }, onReject: { apply(.reject) },
            onLabel: { showsLabels.toggle() }
        )
        .overlay(alignment: .bottomTrailing) {
            if showsLabels {
                LabelPicker(
                    selection: commonLabel,
                    labels: [nil] + store.settings.availableLabels.map { Optional($0) },
                    identifier: "clove.grid.batch.labels"
                ) { colour in
                    apply(.label(colour.map { ColourLabel(colour: $0) } ?? .clear))
                    showsLabels = false
                }
                .offset(y: -66)
            }
        }
        .contextMenu {
            Button("Select all") { browsing.selectAllVisible(cells) }
                .accessibilityIdentifier("clove.grid.batch.selectAll")
        }
        .disabled(browsing.batchTargets.isEmpty || browsing.isApplyingBatch)
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
        Task { await browsing.applyBatch(action, settings: store.settings) }
    }
}
