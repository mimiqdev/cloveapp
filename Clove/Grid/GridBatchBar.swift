import CloveCore
import SwiftUI

/// The multi-select action bar: the selected count, the marks a batch applies and the batch's
/// result (PRD P0-09, PRD Failure and recovery).
///
/// The bar shows while the selection is non-empty and leaves the mode through Done, which clears
/// the selection (PRD P0-09). Its rating controls are the levels Settings enables plus `0` to
/// clear, and its labels are the available colours plus Clear, so a batch offers exactly the
/// marks a single photo does (PRD Marking rules, PRD Enabled rating levels). The count is the
/// number of selected photos the grid shows, because those are the photos a batch marks.
///
/// A partial failure shows PRD Failure and recovery's copy with Retry failed items and Cancel.
/// Retry resends only the photos the last batch did not save, and reports the retry's own result;
/// a failed photo therefore keeps the marks it had until a retry confirms the new ones
/// (PRD P0-08).
///
/// Design placeholder: a system bar of text buttons and a text banner stand in for the visual
/// design's action bar and failure treatment.
struct GridBatchBar: View {
    /// The scene's browsing state and the batch calls this bar performs on it.
    let browsing: BrowsingModel

    /// The cells the grid shows, so Select all covers every photo the user can see
    /// (PRD P0-09).
    let cells: [GridCellItem]

    /// The app-wide settings, read live so the bar offers only the enabled ratings and labels
    /// (PRD Gesture-related settings).
    @Environment(SettingsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = browsing.batchReport?.summary {
                failure(summary)
            }
            header
            marks
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid.batch")
    }

    /// The selected count and the two controls that change the selection (PRD P0-09).
    private var header: some View {
        HStack(spacing: 12) {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("clove.grid.batch.count")
            if browsing.isApplyingBatch {
                // The mark controls are off while one batch runs, so the bar says why rather
                // than looking broken on a slow write (PRD P0-09).
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button("Select all") { browsing.selectAllVisible(cells) }
                .accessibilityIdentifier("clove.grid.batch.selectAll")
            Button("Done") { browsing.clearSelection() }
                .accessibilityIdentifier("clove.grid.batch.done")
        }
        .font(.subheadline)
    }

    /// The marks a batch applies, in one row that scrolls when the width cannot hold it
    /// (PRD P0-09).
    private var marks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ratingLevels, id: \.rawValue) { level in
                    Button(level == .unrated ? "0" : "\(level.rawValue)") {
                        apply(.rating(level))
                    }
                    .accessibilityIdentifier("clove.grid.batch.rate.\(level.rawValue)")
                }
                Divider()
                    .frame(height: 18)
                ForEach(store.settings.availableLabels, id: \.self) { colour in
                    Button(colour.rawValue) {
                        apply(.label(ColourLabel(colour: colour)))
                    }
                    .accessibilityIdentifier(
                        "clove.grid.batch.label.\(colour.rawValue.lowercased())")
                }
                Button("Clear") { apply(.label(.clear)) }
                    .accessibilityIdentifier("clove.grid.batch.label.clear")
                Divider()
                    .frame(height: 18)
                Button("Reject") { apply(.reject) }
                    .accessibilityIdentifier("clove.grid.batch.reject")
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 2)
        }
        // A selection the current filter hides has no photo to mark, so the marks stay off
        // until a visible photo is selected, and one batch at a time keeps two plans from
        // reading the same marks (PRD P0-09).
        .disabled(browsing.batchTargets.isEmpty || browsing.isApplyingBatch)
    }

    /// The PRD's partial-batch copy with a retry of the failed photos only (PRD P0-09).
    private func failure(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(.callout)
                .accessibilityIdentifier("clove.grid.batch.failure")
            HStack {
                Button("Retry failed items") {
                    browsing.submitRetryBatch()
                }
                .disabled(browsing.isApplyingBatch)
                .accessibilityIdentifier("clove.grid.batch.retry")
                Button("Cancel", role: .cancel) { browsing.dismissBatchReport() }
                    .accessibilityIdentifier("clove.grid.batch.cancel")
            }
            .buttonStyle(.bordered)
        }
    }

    /// Sends one bar action to the model, which resolves it per photo and writes one batch
    /// (PRD P0-09).
    private func apply(_ action: BatchMarkAction) {
        browsing.submitBatch(action, settings: store.settings)
    }

    /// The ratings the bar offers: zero to clear, then every enabled level
    /// (PRD Marking rules, PRD Enabled rating levels).
    private var ratingLevels: [Rating] {
        [.unrated] + store.settings.enabledRatings.levels
    }

    /// "1 photo selected" or "3 photos selected" for the photos a batch marks (PRD P0-09).
    private var countText: String {
        let count = browsing.batchTargets.count
        return count == 1 ? "1 photo selected" : "\(count) photos selected"
    }
}
