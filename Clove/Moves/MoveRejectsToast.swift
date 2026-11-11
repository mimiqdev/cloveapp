import CloveCore
import SwiftUI

/// Move results retain Undo; failure details describe the files left in place.
struct MoveRejectsToast: View {
    let browsing: BrowsingModel
    let completed: CompletedRejectMove
    let showDetails: () -> Void

    var body: some View {
        let copy = RejectMoveToast(
            result: completed.result, rejectsFolderName: completed.rejectsFolderName)
        VStack(spacing: 4) {
            if copy.showsDetails {
                Button("Details", action: showDetails)
                    .accessibilityIdentifier("clove.moves.toast.details")
            }
            Toast(
                message: copy.message,
                detail: [copy.failureMessage, copy.skippedMessage].compactMap { $0 }
                    .joined(separator: " ").nilIfEmpty,
                actionTitle: "Undo", identifier: "clove.moves.toast",
                onAction: { browsing.undoRejectMove(completed) })
        }
    }
}

struct MoveRejectsDetailsSheet: View {
    let browsing: BrowsingModel
    let completed: CompletedRejectMove
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let details = RejectMoveDetails(result: completed.result)
        VStack(alignment: .leading, spacing: 16) {
            Text(details.title).font(.title3.bold())
                .accessibilityIdentifier("clove.moves.details.title")
            Text(details.subtitle).font(.footnote).foregroundStyle(Color.clove.text.secondary)
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
                if let skipped = details.skippedMessage { Text(skipped).font(.footnote) }
            }
            Button("Done") { dismiss() }
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
                Text(row.reason).font(.footnote).foregroundStyle(Color.clove.reject)
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
