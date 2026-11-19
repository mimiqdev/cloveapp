import CloveCore
import SwiftUI

/// The unified contextual selection toolbar for batch marking and batch actions on the grid.
/// Write failures are reported once by the shared toast.
struct GridBatchBar: View {
    let browsing: BrowsingModel
    let cells: [GridCellItem]
    var onDeselectAll: () -> Void = {}
    var onRename: () -> Void = {}
    var onKeywords: () -> Void = {}
    @Environment(SettingsStore.self) private var store
    @Environment(\.appLanguage) private var language
    @Environment(\.tapPickerController) private var tapPicker

    private var canOperate: Bool {
        !browsing.batchTargets.isEmpty && browsing.canMark
    }

    var body: some View {
        let batchSelection = BatchSelection(
            groups: browsing.groups, selection: browsing.state.selection)
        HStack(spacing: 0) {
            markingGroup
                .disabled(!canOperate)
                .opacity(canOperate ? 1 : 0.4)
                .contextMenu {
                    Button(AppLocalization.string("Clear rating", language: language)) {
                        apply(.rating(.unrated))
                    }
                    .disabled(!canOperate)
                    .accessibilityIdentifier("clove.grid.batch.clearRating")
                    if !batchSelection.showsAllSelected(cells) {
                        Button(AppLocalization.string("Select all", language: language)) {
                            browsing.selectAllVisible(cells)
                        }
                        .accessibilityIdentifier("clove.grid.batch.selectAll")
                    }
                    if !browsing.batchTargets.isEmpty {
                        Button(AppLocalization.string("Deselect all", language: language)) {
                            onDeselectAll()
                            browsing.deselectAllVisible(cells)
                        }
                        .accessibilityIdentifier("clove.grid.batch.deselectAll")
                    }
                }
            Rectangle().fill(Color.clove.separator).frame(width: 1, height: 24)
            actionsMenu
        }
        .frame(height: 48)
        .cloveGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.grid.batch")
        .reportTapPickerFrame("clove.grid.batch")
    }

    private var markingGroup: some View {
        HStack(spacing: 0) {
            MarkRejectAction(
                isRejected: isRejected,
                identifier: "clove.grid.batch.reject",
                onToggle: { apply(.reject) }
            )
            .frame(width: 54, height: 48)
            .reportTapPickerFrame("clove.grid.batch.reject")

            Rectangle().fill(Color.clove.separator).frame(width: 1, height: 24)

            MarkRatingAction(
                rating: isRejected ? .unrated : commonRating,
                enabledRatings: store.settings.enabledRatings,
                isMixed: batchRatingIsMixed,
                allowsTapCurrentToClear: false,
                identifier: "clove.grid.batch.rating",
                pickerIdentifier: "clove.grid.batch.stars",
                onRate: { apply(.rating($0)) }
            )
            .frame(width: 54, height: 48)
            .reportTapPickerFrame("clove.grid.batch.rating")

            Rectangle().fill(Color.clove.separator).frame(width: 1, height: 24)

            MarkLabelAction(
                label: isRejected ? nil : batchLabelState.selection,
                labels: [nil] + store.settings.availableLabels.map { Optional($0) },
                isMixed: batchLabelState.isMixed,
                identifier: "clove.grid.batch.label",
                pickerIdentifier: "clove.grid.batch.labels",
                onPick: { apply(.label($0.map { ColourLabel(colour: $0) } ?? .clear)) }
            )
            .frame(width: 54, height: 48)
            .reportTapPickerFrame("clove.grid.batch.label")
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                tapPicker?.dismiss()
                onKeywords()
            } label: {
                Label(
                    AppLocalization.string("Add Keywords…", language: language),
                    systemImage: "tag")
            }
            .accessibilityIdentifier("clove.grid.batch.keywords")
            Button {
                tapPicker?.dismiss()
                onRename()
            } label: {
                Label(
                    AppLocalization.string("Rename…", language: language),
                    systemImage: "pencil")
            }
            .accessibilityIdentifier("clove.grid.batch.rename")
        } label: {
            HStack(spacing: 4) {
                Text(AppLocalization.string("Actions", language: language))
                    .lineLimit(1)
                Image(systemName: "ellipsis.circle")
                    .imageScale(.small)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(canOperate ? Color.clove.accent : Color.clove.text.secondary)
            .opacity(canOperate ? 1 : 0.45)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 48, maxHeight: 48)
            .contentShape(Rectangle())
        }
        .disabled(!canOperate)
        .accessibilityLabel(AppLocalization.string("Actions", language: language))
        .accessibilityIdentifier("clove.grid.batch.actions")
        .reportTapPickerFrame("clove.grid.batch.actions")
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

    private var batchRatingIsMixed: Bool {
        guard let first = browsing.batchTargets.first?.marks.rating else { return false }
        return browsing.batchTargets.contains { $0.marks.rating != first }
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
