import CloveCore
import SwiftUI

/// Move results retain Undo; failure details describe the files left in place.
struct MoveRejectsToast: View {
    let browsing: BrowsingModel
    let completed: CompletedRejectMove
    let showDetails: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        let result = completed.result
        let message = AppLocalization.format(
            "Moved %lld to %@", language: language, Int64(result.movedCount),
            completed.rejectsFolderName.rawValue)
        let failureMessage: String? =
            result.unmovedCount == 0
            ? nil
            : AppLocalization.format(
                "%lld couldn't be moved", language: language, Int64(result.unmovedCount))
        let skippedMessage: String? =
            result.skippedCount > 0
            ? AppLocalization.format(
                "%lld photos were skipped.", language: language, Int64(result.skippedCount))
            : nil
        Toast(
            message: message,
            detail: [failureMessage, skippedMessage].compactMap { $0 }
                .joined(separator: " ").nilIfEmpty,
            actionTitle: browsing.canUndoRejectMove(completed)
                ? AppLocalization.string("Undo", language: language) : nil,
            secondaryActionTitle: result.unmovedCount > 0
                ? AppLocalization.string("Details", language: language) : nil,
            onSecondaryAction: showDetails,
            identifier: "clove.moves.toast",
            onAction: { browsing.undoRejectMove(completed) })
    }
}

struct MoveRejectsDetailsSheet: View {
    let browsing: BrowsingModel
    let completed: CompletedRejectMove
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    var body: some View {
        let details = RejectMoveDetails(result: completed.result)
        let skippedMessage: String? =
            completed.result.skippedCount > 0
            ? AppLocalization.format(
                "%lld photos were skipped.", language: language,
                Int64(completed.result.skippedCount))
            : nil
        VStack(alignment: .leading, spacing: 16) {
            Text(
                AppLocalization.format(
                    "%lld photos couldn't be moved", language: language,
                    Int64(completed.result.unmovedCount))
            )
            .font(.title3.bold())
            .accessibilityIdentifier("clove.moves.details.title")
            Text(
                AppLocalization.string(
                    "They stay rejected in place. Nothing was deleted.", language: language)
            )
            .font(.footnote).foregroundStyle(Color.clove.text.secondary)
            .accessibilityIdentifier("clove.moves.details.subtitle")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(details.rows) { row in
                        rowView(row)
                        if row.id != details.rows.last?.id {
                            Divider().overlay(Color.clove.separator)
                        }
                    }
                }
                .background(Color.clove.surface.card, in: RoundedRectangle(cornerRadius: 14))
                if let skipped = skippedMessage { Text(skipped).font(.footnote) }
            }
            Button(AppLocalization.string("Done", language: language)) { dismiss() }
                .buttonStyle(MoveSheetButtonStyle(secondary: true))
                .accessibilityIdentifier("clove.moves.details.done")
        }
        .padding(20).padding(.top, 12)
        .foregroundStyle(Color.clove.text.primary)
        .background(Color.clove.surface.sheet)
        .presentationBackground(Color.clove.surface.sheet)
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clove.moves.details.sheet")
    }

    private func rowView(_ row: RejectMoveDetails.Row) -> some View {
        HStack(spacing: 12) {
            MoveRejectsThumbnail(photo: row.id, source: browsing.thumbnails)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.fileName).font(.subheadline.weight(.semibold))
                Text(AppLocalization.string(row.reason, language: language))
                    .font(.footnote).foregroundStyle(Color.clove.reject)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clove.moves.details.row.\(row.id.stem)")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
